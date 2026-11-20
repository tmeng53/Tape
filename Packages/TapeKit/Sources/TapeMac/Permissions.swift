import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

public enum Permission: CaseIterable, Sendable {
    case accessibility
    case screenRecording
    case microphone

    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        }
    }

    public var why: String {
        switch self {
        case .accessibility: "to catch the talk key and paste into apps"
        case .screenRecording: "to record your screen"
        case .microphone: "to record your voice"
        }
    }

    var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .microphone: anchor = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    @MainActor
    public var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    @MainActor
    public func request() async {
        switch self {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) { openSettings() }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings() }
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined: _ = await AVCaptureDevice.requestAccess(for: .audio)
            case .authorized: break
            default: openSettings()
            }
        }
    }

    @MainActor
    public func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
