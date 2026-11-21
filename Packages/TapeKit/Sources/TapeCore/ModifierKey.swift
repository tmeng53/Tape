public enum ModifierKey: String, CaseIterable, Codable, Sendable {
    case leftControl, rightControl
    case leftOption, rightOption
    case leftCommand, rightCommand
    case leftShift, rightShift

    public var keyCode: UInt16 {
        switch self {
        case .leftControl: 59
        case .rightControl: 62
        case .leftOption: 58
        case .rightOption: 61
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        }
    }

    public var deviceMask: UInt64 {
        switch self {
        case .leftControl: 0x0000_0001
        case .rightControl: 0x0000_2000
        case .leftShift: 0x0000_0002
        case .rightShift: 0x0000_0004
        case .leftCommand: 0x0000_0008
        case .rightCommand: 0x0000_0010
        case .leftOption: 0x0000_0020
        case .rightOption: 0x0000_0040
        }
    }

    public var genericMask: UInt64 {
        switch self {
        case .leftControl, .rightControl: ModifierFlags.control
        case .leftOption, .rightOption: ModifierFlags.option
        case .leftCommand, .rightCommand: ModifierFlags.command
        case .leftShift, .rightShift: ModifierFlags.shift
        }
    }

    public var symbol: String {
        switch self {
        case .leftControl, .rightControl: "⌃"
        case .leftOption, .rightOption: "⌥"
        case .leftCommand, .rightCommand: "⌘"
        case .leftShift, .rightShift: "⇧"
        }
    }

    public var displayName: String {
        let side = rawValue.hasPrefix("left") ? "Left" : "Right"
        let name: String
        switch self {
        case .leftControl, .rightControl: name = "Control"
        case .leftOption, .rightOption: name = "Option"
        case .leftCommand, .rightCommand: name = "Command"
        case .leftShift, .rightShift: name = "Shift"
        }
        return "\(side) \(symbol) \(name)"
    }

    public func isDown(in flags: UInt64) -> Bool {
        flags & deviceMask != 0
    }

    public var otherSide: ModifierKey {
        switch self {
        case .leftControl: .rightControl
        case .rightControl: .leftControl
        case .leftOption: .rightOption
        case .rightOption: .leftOption
        case .leftCommand: .rightCommand
        case .rightCommand: .leftCommand
        case .leftShift: .rightShift
        case .rightShift: .leftShift
        }
    }

    public func removed(from flags: UInt64) -> UInt64 {
        let withoutDevice = flags & ~deviceMask
        return otherSide.isDown(in: flags) ? withoutDevice : withoutDevice & ~genericMask
    }
}

public enum ModifierFlags {
    public static let shift: UInt64 = 0x0002_0000
    public static let control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000
    public static let command: UInt64 = 0x0010_0000
    public static let all: UInt64 = shift | control | option | command
}
