import Testing
@testable import TapeCore

struct TalkGestureTests {
    @Test func holdRecordsUntilRelease() {
        var g = TalkGesture()
        #expect(g.handle(.talkDown(at: 0, othersHeld: false)) == .init(.swallow, [.startRecording]))
        #expect(g.handle(.otherKeyDown(at: 1)) == .init(.passStrippingTalkModifier))
        #expect(g.handle(.mouseDown(at: 1.5)) == .init(.passStrippingTalkModifier))
        #expect(g.handle(.talkUp(at: 2)) == .init(.swallow, [.stopAndDeliver]))
        #expect(g.phase == .idle)
    }

    @Test func holdWithoutOtherEventsStillDelivers() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        #expect(g.handle(.talkUp(at: 0.3)) == .init(.swallow, [.stopAndDeliver]))
    }

    @Test func tapStartsHandsFreeAndNextPressDelivers() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        #expect(g.handle(.talkUp(at: 0.1)) == .init(.swallow))
        #expect(g.phase == .handsFree)
        #expect(g.isRecording)
        #expect(g.handle(.otherKeyDown(at: 3)) == .init(.pass))
        #expect(g.handle(.talkDown(at: 5, othersHeld: false)) == .init(.swallow, [.stopAndDeliver]))
        #expect(g.handle(.talkUp(at: 5.1)) == .init(.swallow))
        #expect(g.phase == .idle)
    }

    @Test func quickChordIsReplayedAndDiscarded() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        #expect(g.handle(.otherKeyDown(at: 0.1)) == .init(.replayTalkDownThenPass, [.discardRecording]))
        #expect(g.handle(.talkUp(at: 0.2)) == .init(.pass))
        #expect(g.phase == .idle)
    }

    @Test func controlClickIsAChord() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        #expect(g.handle(.mouseDown(at: 0.05)) == .init(.replayTalkDownThenPass, [.discardRecording]))
    }

    @Test func talkKeyWithAnotherModifierIsNeverTalk() {
        var g = TalkGesture()
        #expect(g.handle(.talkDown(at: 0, othersHeld: true)) == .init(.pass))
        #expect(g.handle(.talkUp(at: 1)) == .init(.pass))
        #expect(g.phase == .idle)
    }

    @Test func escapeWhileHoldingKeepsClipAndHidesRelease() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        #expect(g.handle(.escape(at: 1)) == .init(.swallow, [.cancelRecording]))
        #expect(g.handle(.talkUp(at: 2)) == .init(.swallow))
        #expect(g.phase == .idle)
    }

    @Test func escapeInHandsFreeCancels() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        _ = g.handle(.talkUp(at: 0.1))
        #expect(g.handle(.escape(at: 2)) == .init(.swallow, [.cancelRecording]))
        #expect(g.phase == .idle)
    }

    @Test func escapeWhenIdlePasses() {
        var g = TalkGesture()
        #expect(g.handle(.escape(at: 0)) == .init(.pass))
    }

    @Test func externalStopWhileHoldingHidesRelease() {
        var g = TalkGesture()
        _ = g.handle(.talkDown(at: 0, othersHeld: false))
        _ = g.handle(.otherKeyDown(at: 1))
        g.recordingEndedExternally()
        #expect(g.handle(.talkUp(at: 2)) == .init(.swallow))
        #expect(g.phase == .idle)
    }

    @Test func interruptDuringHoldCancelsAndKeepsClip() {
        var gesture = TalkGesture()
        _ = gesture.handle(.talkDown(at: 0, othersHeld: false))
        _ = gesture.handle(.mouseOther(at: 0.5))
        #expect(gesture.interrupt() == [.cancelRecording])
        #expect(gesture.phase == .idle)
    }

    @Test func interruptDuringHandsFreeCancelsAndKeepsClip() {
        var gesture = TalkGesture()
        _ = gesture.handle(.talkDown(at: 0, othersHeld: false))
        _ = gesture.handle(.talkUp(at: 0.1))
        #expect(gesture.interrupt() == [.cancelRecording])
    }

    @Test func interruptBeforeHoldDiscards() {
        var gesture = TalkGesture()
        _ = gesture.handle(.talkDown(at: 0, othersHeld: false))
        #expect(gesture.interrupt() == [.discardRecording])
    }

    @Test func interruptWhenIdleDoesNothing() {
        var gesture = TalkGesture()
        #expect(gesture.interrupt().isEmpty)
    }
}
