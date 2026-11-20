import AppKit
import AVFoundation
import ScreenCaptureKit
import TapeCore

public enum RecorderError: Error {
    case noDisplay
    case notRecording
}

public final class ScreenCaptureRecorder: NSObject, ScreenRecording, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    public override init() {}

    public func start(writingTo url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = await MainActor.run { Self.displayUnderCursor() }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw RecorderError.noDisplay
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = await MainActor.run { Self.backingScale(for: displayID) }
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = false
        config.captureMicrophone = true

        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = url
        recordingConfig.outputFileType = .mp4
        recordingConfig.videoCodecType = .h264

        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(output)
        lock.withLock { self.stream = stream }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { started = continuation }
            stream.startCapture { error in
                if let error { self.resumeStarted(throwing: error) }
            }
        }
    }

    public func stop() async throws {
        guard let stream = lock.withLock({ self.stream }) else { throw RecorderError.notRecording }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.withLock { finished = continuation }
            stream.stopCapture { error in
                if let error { self.resumeFinished(throwing: error) }
            }
        }
        lock.withLock { self.stream = nil }
    }

    public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        resumeStarted(throwing: nil)
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        resumeStarted(throwing: error)
        resumeFinished(throwing: error)
    }

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resumeFinished(throwing: nil)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        resumeStarted(throwing: error)
        resumeFinished(throwing: error)
    }

    private func resumeStarted(throwing error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { started = nil }
            return started
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    private func resumeFinished(throwing error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { finished = nil }
            return finished
        }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    @MainActor
    private static func displayUnderCursor() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.displayID ?? CGMainDisplayID()
    }

    @MainActor
    private static func backingScale(for displayID: CGDirectDisplayID) -> Double {
        Double(NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
