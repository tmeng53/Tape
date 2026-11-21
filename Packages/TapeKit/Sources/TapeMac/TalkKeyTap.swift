import AppKit
import CoreGraphics
import TapeCore

@MainActor
public final class TalkKeyTap {
    public static let syntheticEventMarker: Int64 = 0x7461_7065

    public var talkKey: ModifierKey {
        didSet { interruptGesture() }
    }
    public var onAction: (TalkGesture.Action) -> Void = { _ in }
    public private(set) var isRunning = false

    private var gesture = TalkGesture()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var heldTalkDown: CGEvent?
    private let escapeKeyCode: Int64 = 53

    public init(talkKey: ModifierKey) {
        self.talkKey = talkKey
    }

    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .flagsChanged, .keyDown, .keyUp,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<TalkKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            nonisolated(unsafe) var result: Unmanaged<CGEvent>?
            MainActor.assumeIsolated { result = tap.handle(proxy: proxy, type: type, event: event) }
            return result
        }
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return false }
        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isRunning = true
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isRunning = false
        interruptGesture()
    }

    private func interruptGesture() {
        heldTalkDown = nil
        gesture.interrupt().forEach(onAction)
    }

    public func recordingEndedExternally() {
        gesture.recordingEndedExternally()
    }

    public func captureFailed() {
        gesture.captureFailed().forEach(onAction)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            interruptGesture()
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        guard let gestureEvent = classify(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        if case .talkDown = gestureEvent { heldTalkDown = event.copy() }

        let output = gesture.handle(gestureEvent)
        output.actions.forEach(onAction)

        switch output.disposition {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .passStrippingTalkModifier:
            event.flags = CGEventFlags(rawValue: talkKey.removed(from: event.flags.rawValue))
            return Unmanaged.passUnretained(event)
        case .replayTalkDownThenPass:
            if let heldTalkDown { heldTalkDown.tapPostEvent(proxy) }
            heldTalkDown = nil
            return Unmanaged.passUnretained(event)
        }
    }

    private func classify(type: CGEventType, event: CGEvent) -> TalkGesture.Event? {
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            guard keyCode == talkKey.keyCode else { return .otherModifierChanged(at: now) }
            if talkKey.isDown(in: flags) {
                let others = flags & ModifierFlags.all & ~talkKey.genericMask
                return .talkDown(at: now, othersHeld: others != 0)
            }
            return .talkUp(at: now)
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == escapeKeyCode { return .escape(at: now) }
            return .otherKeyDown(at: now)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return .mouseDown(at: now)
        case .keyUp, .leftMouseUp, .rightMouseUp, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            return .mouseOther(at: now)
        default:
            return nil
        }
    }
}
