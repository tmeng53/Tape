import AVFoundation
import AppKit
import OSLog
import ScreenCaptureKit
import TapeCore

public enum RecorderError: Error {
    case noDisplay
    case notRecording
}

@MainActor
public final class ScreenCaptureRecorder: NSObject, ScreenRecording {
    private let log = Logger(subsystem: TapeLog.subsystem, category: "recording")
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var finished: CheckedContinuation<Void, Error>?
    private var finishError: Error?
    private var didFinish = false
    private var isStopping = false
    public var onUnexpectedStop: (Error) -> Void = { _ in }

    public override init() {}

    public func start(writingTo url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = Self.displayUnderCursor()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
        else {
            throw RecorderError.noDisplay
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = Double(Self.backingScale(for: displayID))
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
        self.stream = stream
        self.output = output
        didFinish = false
        finishError = nil
        isStopping = false
        do {
            try await stream.startCapture()
        } catch {
            log.error("startCapture failed: \(error.localizedDescription, privacy: .public)")
            self.stream = nil
            self.output = nil
            throw error
        }
    }

    public func stop() async throws {
        guard let stream else { throw RecorderError.notRecording }
        isStopping = true
        try await stream.stopCapture()
        if !didFinish {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                finished = continuation
            }
        } else if let finishError {
            throw finishError
        }
        self.stream = nil
        self.output = nil
    }

    private func recordingEnded(_ error: Error?) {
        if let error { log.error("recording ended: \(error.localizedDescription, privacy: .public)") }
        let firstEnd = !didFinish
        didFinish = true
        finishError = error
        if let error, firstEnd, !isStopping, stream != nil { onUnexpectedStop(error) }
        guard let continuation = finished else { return }
        finished = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    private static func displayUnderCursor() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.displayID ?? CGMainDisplayID()
    }

    private static func backingScale(for displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
    }
}

extension ScreenCaptureRecorder: SCRecordingOutputDelegate {
    public nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.recordingEnded(error) }
    }

    public nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.recordingEnded(nil) }
    }
}

extension ScreenCaptureRecorder: SCStreamDelegate {
    public nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.recordingEnded(error) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
