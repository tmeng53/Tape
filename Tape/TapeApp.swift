import SwiftUI
import TapeCore
import TapeMac

@main
struct TapeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .task { await model.launch() }
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
            if !keyTapRunning { return "Waiting for Accessibility permission" }
            return "Hold \(talkKey.displayName) to talk, or tap it to start"
        case let .recording(_, target):
            return target.map { "Recording → \($0.appName)" } ?? "Recording"
        case .finishing: return "Finishing clip…"
        case let .pasted(appName): return "Pasted into \(appName)"
        case .copied: return "Copied. Press ⌘V to paste"
        case let .failed(message): return message
        }
    }
}
