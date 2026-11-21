import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

let leftControlKeyCode: CGKeyCode = 59
let escapeKeyCode: CGKeyCode = 53
let leftControlDeviceFlag: UInt64 = 0x0000_0001

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func stamp(_ label: String) {
    print("\(label) \(Date().timeIntervalSince1970)")
}

func postControl(down: Bool) {
    guard let source = CGEventSource(stateID: .hidSystemState),
        let event = CGEvent(keyboardEventSource: source, virtualKey: leftControlKeyCode, keyDown: down)
    else { fail("could not create control event") }
    event.type = .flagsChanged
    event.flags = down ? CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | leftControlDeviceFlag) : []
    event.post(tap: .cghidEventTap)
    stamp(down ? "control-down" : "control-up")
}

func postEscape() {
    guard let source = CGEventSource(stateID: .hidSystemState),
        let down = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: false)
    else { fail("could not create escape event") }
    down.flags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | leftControlDeviceFlag)
    up.flags = down.flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    stamp("escape")
}

func pause(_ seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

func audioLevel(of path: String) async throws -> (seconds: Double, peakDecibels: Double, rmsDecibels: Double) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let seconds = try await asset.load(.duration).seconds
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else { fail("no audio track in \(path)") }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
    )
    reader.add(output)
    reader.startReading()
    var sumOfSquares = 0.0
    var count = 0
    var peak = 0
    while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        CMBlockBufferGetDataPointer(
            block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
        guard let pointer else { continue }
        pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { values in
            for index in 0..<(length / 2) {
                let value = Int(values[index])
                sumOfSquares += Double(value * value)
                peak = max(peak, abs(value))
                count += 1
            }
        }
    }
    func decibels(_ value: Double) -> Double { value > 0 ? 20 * log10(value / 32767) : -120 }
    return (seconds, decibels(Double(peak)), decibels((sumOfSquares / Double(max(count, 1))).squareRoot()))
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func findTextArea(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole { return element }
    guard depth < 12, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    for child in children {
        if let found = findTextArea(in: child, depth: depth + 1) { return found }
    }
    return nil
}

func attachmentCount(processName: String) -> Int {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", processName]
    let pipe = Pipe()
    task.standardOutput = pipe
    do { try task.run() } catch { fail("pgrep failed: \(error)") }
    task.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard let pid = output.split(separator: "\n").first.flatMap({ pid_t($0) }) else {
        fail("\(processName) is not running")
    }
    let app = AXUIElementCreateApplication(pid)
    guard let window = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(window) == AXUIElementGetTypeID() else {
        fail("\(processName) has no focused window")
    }
    guard let area = findTextArea(in: unsafeBitCast(window, to: AXUIElement.self)) else {
        fail("no text area in \(processName)")
    }
    let text = attribute(area, kAXValueAttribute) as? String ?? ""
    return text.filter { $0 == "\u{FFFC}" }.count
}

struct LogEntry {
    let time: Double
    let message: String
}

func logEntries(in path: String) -> [LogEntry] {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    return contents.split(separator: "\n").compactMap { line in
        guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let timestamp = object["timestamp"] as? String,
            let date = formatter.date(from: timestamp),
            let message = object["eventMessage"] as? String
        else { return nil }
        return LogEntry(time: date.timeIntervalSince1970, message: message)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail(
        "usage: smoke-tool preflight|hold SECONDS|tap|escape-during-hold|attachments PROCESS|frontmost|cue-delay LOGFILE CUE EPOCH|log-lines LOGFILE|level FILE"
    )
}

switch command {
case "preflight":
    print(CGPreflightPostEventAccess() ? "post-events allowed" : "post-events denied")
    exit(CGPreflightPostEventAccess() ? 0 : 1)
case "hold":
    let seconds = arguments.count > 1 ? Double(arguments[1]) ?? 3 : 3
    postControl(down: true)
    pause(seconds)
    postControl(down: false)
case "tap":
    postControl(down: true)
    pause(0.08)
    postControl(down: false)
case "escape-during-hold":
    postControl(down: true)
    pause(1.2)
    postEscape()
    pause(0.3)
    postControl(down: false)
case "attachments":
    print(attachmentCount(processName: arguments.count > 1 ? arguments[1] : "TextEdit"))
case "frontmost":
    print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
case "cue-delay":
    guard arguments.count > 3, let reference = Double(arguments[3]) else { fail("cue-delay needs LOGFILE CUE EPOCH") }
    let cueMessage = "cue \(arguments[2])"
    guard
        let entry = logEntries(in: arguments[1]).first(where: {
            $0.message == cueMessage && $0.time >= reference - 0.05
        })
    else {
        fail("no \(cueMessage) after \(reference)")
    }
    print(Int(((entry.time - reference) * 1000).rounded()))
case "log-lines":
    guard arguments.count > 1 else { fail("log-lines needs a file") }
    for entry in logEntries(in: arguments[1]) {
        print(String(format: "  %.3f %@", entry.time, entry.message))
    }
case "level":
    guard arguments.count > 1 else { fail("level needs a file") }
    let result = try await audioLevel(of: arguments[1])
    print(
        String(
            format: "duration=%.2fs peak=%.1fdBFS rms=%.1fdBFS", result.seconds, result.peakDecibels, result.rmsDecibels
        ))
default:
    fail("unknown command \(command)")
}
