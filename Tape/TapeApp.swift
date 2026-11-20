import AppKit
import SwiftUI
import TapeCore
import TapeMac

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.launch() }
    }
}

@main
struct TapeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.menuBarSymbol)
                .accessibilityLabel(delegate.model.statusLine)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Text(model.statusLine)
        Divider()
        if !model.missingPermissions.isEmpty {
            ForEach(model.missingPermissions, id: \.self) { permission in
                Button("Allow \(permission.title) \(permission.why)…") {
                    Task {
                        await permission.request()
                        model.refreshPermissions()
                    }
                }
            }
            Divider()
        }
        Picker("Talk Key", selection: $model.talkKey) {
            ForEach(ModifierKey.talkKeyChoices, id: \.self) { key in
                Text(key.displayName).tag(key)
            }
        }
        Button("Open Clips Folder") { model.openClipsFolder() }
        Divider()
        Button("Quit Tape") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension ModifierKey {
    static let talkKeyChoices: [ModifierKey] = [.leftControl, .rightControl, .rightOption, .rightCommand]
}

extension AppModel {
    var menuBarSymbol: String {
        switch status {
        case .recording: "record.circle.fill"
        case .finishing: "ellipsis.circle"
        case .pasted, .copied: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .idle, .kept: missingPermissions.isEmpty && keyTapRunning ? "waveform.circle" : "lock.circle"
        }
    }

    var statusLine: String {
        switch status {
        case .idle, .kept:
            if !keyTapRunning { return String(localized: "Waiting for Accessibility permission") }
            return String(localized: "Hold \(talkKey.displayName) to talk, or tap it to start")
        case let .recording(_, target):
            guard let target else { return String(localized: "Recording") }
            return String(localized: "Recording → \(target.appName)")
        case .finishing: return String(localized: "Finishing clip…")
        case let .pasted(appName): return String(localized: "Pasted into \(appName)")
        case .copied: return String(localized: "Copied. Press ⌘V to paste")
        case let .failed(message): return message
        }
    }
}
