import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog
import TapeCore

public enum PasteError: Error {
    case appGone
    case notFrontmost
    case noTextBoxFocused
}

@MainActor
public final class PasteboardDelivery: ClipDelivering {
    private let focus: FocusReading
    private let restoreDelay: Duration
    private var restoreTask: Task<Void, Never>?
    private var pendingRestore: (original: [NSPasteboardItem], ourChange: Int)?
    private let log = Logger(subsystem: TapeLog.subsystem, category: "paste")

    public init(focus: FocusReading, restoreDelay: Duration = .milliseconds(1500)) {
        self.focus = focus
        self.restoreDelay = restoreDelay
    }

    public func paste(_ fileURL: URL, into target: FocusTarget, recipe: PasteRecipe) async throws {
        guard let app = NSRunningApplication(processIdentifier: target.processID) else { throw PasteError.appGone }
        try await bringForward(app)
        try await waitForTextBox(in: target.processID)

        restoreTask?.cancel()
        let pasteboard = NSPasteboard.general
        let original = originalClipboard(of: pasteboard)
        write(fileURL, recipe: recipe, to: pasteboard)
        let ourChange = pasteboard.changeCount

        Self.postCommandV(to: target.processID)

        guard let original else {
            pendingRestore = nil
            return
        }
        pendingRestore = (original, ourChange)
        let delay = restoreDelay
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pendingRestore = nil
            guard pasteboard.changeCount == ourChange else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(original)
        }
    }

    private func originalClipboard(of pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        if let pendingRestore, pasteboard.changeCount == pendingRestore.ourChange {
            return pendingRestore.original
        }
        return Self.snapshot(pasteboard)
    }

    private func waitForTextBox(in processID: pid_t) async throws {
        for _ in 0..<20 {
            if focus.focusedTextTarget()?.processID == processID { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        log.error("no text box focused in the target app")
        throw PasteError.noTextBoxFocused
    }

    public func copyToClipboard(_ fileURL: URL) {
        write(fileURL, recipe: .fileReference, to: .general)
    }

    private func write(_ fileURL: URL, recipe: PasteRecipe, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch recipe {
        case .fileReference:
            pasteboard.writeObjects([fileURL as NSURL])
        case .pathText:
            pasteboard.setString(Self.shellQuoted(fileURL.path), forType: .string)
        }
    }

    private func bringForward(_ app: NSRunningApplication) async throws {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        log.error("\(app.bundleIdentifier ?? "app", privacy: .public) did not come to the front")
        throw PasteError.notFrontmost
    }

    nonisolated static func postCommandV(to processID: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = 0x7461_7065
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.postToPid(processID)
        up?.postToPid(processID)
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        var copies: [NSPasteboardItem] = []
        for item in items {
            if item.types.contains(.fileURL) { return nil }
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            copies.append(copy)
        }
        return copies
    }

    nonisolated static func shellQuoted(_ path: String) -> String {
        let safe = path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) }
        return safe ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
