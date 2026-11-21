public struct TalkGesture: Sendable {
    public enum Event: Equatable, Sendable {
        case talkDown(at: Double, othersHeld: Bool)
        case talkUp(at: Double)
        case otherKeyDown(at: Double)
        case otherModifierChanged(at: Double)
        case mouseDown(at: Double)
        case mouseOther(at: Double)
        case escape(at: Double)
    }

    public enum Disposition: Equatable, Sendable {
        case pass
        case swallow
        case passStrippingTalkModifier
        case replayTalkDownThenPass
    }

    public enum Action: Equatable, Sendable {
        case startRecording
        case stopAndDeliver
        case cancelRecording
        case discardRecording
    }

    public enum Phase: Equatable, Sendable {
        case idle
        case pressed(since: Double)
        case holding
        case handsFree
        case awaitingTalkUp
        case chordPassthrough
    }

    public struct Output: Equatable, Sendable {
        public var disposition: Disposition
        public var actions: [Action]

        public init(_ disposition: Disposition, _ actions: [Action] = []) {
            self.disposition = disposition
            self.actions = actions
        }
    }

    public var holdThreshold: Double
    public private(set) var phase: Phase = .idle

    public init(holdThreshold: Double = 0.3) {
        self.holdThreshold = holdThreshold
    }

    public var isRecording: Bool {
        switch phase {
        case .pressed, .holding, .handsFree: true
        case .idle, .awaitingTalkUp, .chordPassthrough: false
        }
    }

    public mutating func handle(_ event: Event) -> Output {
        promoteToHoldIfDue(at: event.time)

        switch (phase, event) {
        case let (.idle, .talkDown(at, othersHeld)):
            if othersHeld {
                phase = .chordPassthrough
                return Output(.pass)
            }
            phase = .pressed(since: at)
            return Output(.swallow, [.startRecording])
        case (.idle, _):
            return Output(.pass)

        case let (.pressed(since), .talkUp(at)):
            if at - since < holdThreshold {
                phase = .handsFree
                return Output(.swallow)
            }
            phase = .idle
            return Output(.swallow, [.stopAndDeliver])
        case (.pressed, .otherKeyDown), (.pressed, .otherModifierChanged), (.pressed, .mouseDown):
            phase = .chordPassthrough
            return Output(.replayTalkDownThenPass, [.discardRecording])
        case (.pressed, .escape):
            phase = .awaitingTalkUp
            return Output(.swallow, [.discardRecording])
        case (.pressed, .mouseOther):
            return Output(.passStrippingTalkModifier)
        case (.pressed, .talkDown):
            return Output(.swallow)

        case (.holding, .talkUp):
            phase = .idle
            return Output(.swallow, [.stopAndDeliver])
        case (.holding, .escape):
            phase = .awaitingTalkUp
            return Output(.swallow, [.cancelRecording])
        case (.holding, .talkDown):
            return Output(.swallow)
        case (.holding, _):
            return Output(.passStrippingTalkModifier)

        case (.handsFree, .talkDown):
            phase = .awaitingTalkUp
            return Output(.swallow, [.stopAndDeliver])
        case (.handsFree, .escape):
            phase = .idle
            return Output(.swallow, [.cancelRecording])
        case (.handsFree, .talkUp):
            return Output(.swallow)
        case (.handsFree, _):
            return Output(.pass)

        case (.awaitingTalkUp, .talkUp):
            phase = .idle
            return Output(.swallow)
        case (.awaitingTalkUp, .talkDown):
            return Output(.swallow)
        case (.awaitingTalkUp, _):
            return Output(.passStrippingTalkModifier)

        case (.chordPassthrough, .talkUp):
            phase = .idle
            return Output(.pass)
        case (.chordPassthrough, _):
            return Output(.pass)
        }
    }

    public mutating func recordingEndedExternally() {
        switch phase {
        case .pressed, .holding: phase = .awaitingTalkUp
        case .handsFree: phase = .idle
        case .idle, .awaitingTalkUp, .chordPassthrough: break
        }
    }

    public mutating func interrupt() -> [Action] {
        let wasRecording = isRecording
        phase = .idle
        return wasRecording ? [.cancelRecording] : []
    }

    private mutating func promoteToHoldIfDue(at time: Double) {
        if case let .pressed(since) = phase, time - since >= holdThreshold {
            phase = .holding
        }
    }
}

extension TalkGesture.Event {
    var time: Double {
        switch self {
        case let .talkDown(at, _), let .talkUp(at), let .otherKeyDown(at),
            let .otherModifierChanged(at), let .mouseDown(at), let .mouseOther(at),
            let .escape(at):
            at
        }
    }
}
