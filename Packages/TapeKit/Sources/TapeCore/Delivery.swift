public enum DeliveryDecision<Target: Equatable & Sendable>: Equatable, Sendable {
    case paste(into: Target, reason: Reason)
    case waitForNextTextBox(seconds: Double)
    case clipboardOnly

    public enum Reason: Equatable, Sendable {
        case focusedAtRelease
        case lastDuringRecording
    }
}

public struct DeliveryPlanner: Sendable {
    public var waitWindow: Double

    public init(waitWindow: Double = 0) {
        self.waitWindow = waitWindow
    }

    public func decide<Target: Equatable & Sendable>(
        focusedAtRelease: Target?,
        lastDuringRecording: Target?
    ) -> DeliveryDecision<Target> {
        if let focusedAtRelease {
            return .paste(into: focusedAtRelease, reason: .focusedAtRelease)
        }
        if let lastDuringRecording {
            return .paste(into: lastDuringRecording, reason: .lastDuringRecording)
        }
        if waitWindow > 0 {
            return .waitForNextTextBox(seconds: waitWindow)
        }
        return .clipboardOnly
    }
}

public enum PasteRecipe: Equatable, Sendable {
    case fileReference
    case pathText

    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
    ]

    public static func forApp(bundleID: String?) -> PasteRecipe {
        guard let bundleID else { return .fileReference }
        return terminalBundleIDs.contains(bundleID) ? .pathText : .fileReference
    }
}
