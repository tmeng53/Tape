import AppKit
import ApplicationServices
import TapeCore

@MainActor
public final class AXFocusReader: FocusReading {
    nonisolated static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    private var preparedApps: Set<pid_t> = []

    public init() {}

    public func focusedTextTarget() -> FocusTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        prepare(app, element: appElement)
        guard let focused = Self.element(appElement, kAXFocusedUIElementAttribute),
            let role = Self.isEditable(focused)
        else { return nil }
        return FocusTarget(
            processID: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? app.bundleIdentifier ?? "App",
            role: role
        )
    }

    private func prepare(_ app: NSRunningApplication, element: AXUIElement) {
        guard !preparedApps.contains(app.processIdentifier) else { return }
        preparedApps.insert(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    nonisolated static func isEditable(_ element: AXUIElement) -> String? {
        let role = string(element, kAXRoleAttribute) ?? ""
        if editableRoles.contains(role) { return role }
        if self.element(element, "AXEditableAncestor") != nil { return role.isEmpty ? "AXEditable" : role }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
            settable.boolValue, role != kAXSliderRole, role != kAXCheckBoxRole
        {
            return role.isEmpty ? "AXEditable" : role
        }
        return nil
    }

    nonisolated static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
