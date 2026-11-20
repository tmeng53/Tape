import AppKit
import ApplicationServices
import Carbon.HIToolbox
import TapeCore

public enum PasteError: Error {
    case appGone
    case notFrontmost
}

public final class PasteboardDelivery: ClipDelivering, @unchecked Sendable {
    private let restoreDelay: Duration

    public init(restoreDelay: Duration = .milliseconds(1500)) {
        self.restoreDelay = restoreDelay
    }

    @MainActor
    public func paste(_ fileURL: URL, into target: FocusTarget, recipe: PasteRecipe) async throws {
        guard let app = NSRunningApplication(processIdentifier: target.processID) else { throw PasteError.appGone }
        try await bringForward(app)

        let pasteboard = NSPasteboard.general
        let saved = Self.snapshot(pasteboard)
        write(fileURL, recipe: recipe, to: pasteboard)
        let ourChange = pasteboard.changeCount

        Self.postCommandV(to: target.processID)

        try? await Task.sleep(for: restoreDelay)
        if pasteboard.changeCount == ourChange, let saved {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved)
        }
    }

    @MainActor
    public func copyToClipboard(_ fileURL: URL) {
        write(fileURL, recipe: .fileReference, to: .general)
    }

    @MainActor
    private func write(_ fileURL: URL, recipe: PasteRecipe, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch recipe {
        case .fileReference:
            pasteboard.writeObjects([fileURL as NSURL])
        case .pathText:
            pasteboard.setString(Self.shellQuoted(fileURL.path), forType: .string)
        }
    }

    @MainActor
    private func bringForward(_ app: NSRunningApplication) async throws {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        throw PasteError.notFrontmost
    }

    static func postCommandV(to processID: pid_t) {
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

    @MainActor
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

    static func shellQuoted(_ path: String) -> String {
        let safe = path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) }
        return safe ? path : "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
