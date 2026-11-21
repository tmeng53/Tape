import Foundation
import TapeCore
import Testing

struct SoundCueTests {
    let startedAt = Date(timeIntervalSince1970: 0)
    let target = FocusTarget(processID: 1, bundleID: "com.apple.TextEdit", appName: "TextEdit", role: "AXTextArea")

    @Test func startCuePlaysWhenRecordingBegins() {
        #expect(SoundCue(from: .idle, to: .recording(startedAt: startedAt, target: nil)) == .start)
    }

    @Test func focusChangesDuringRecordingStaySilent() {
        let before = SessionStatus.recording(startedAt: startedAt, target: nil)
        let after = SessionStatus.recording(startedAt: startedAt, target: target)
        #expect(SoundCue(from: before, to: after) == nil)
    }

    @Test func stopCuePlaysOnReleaseBeforeDelivery() {
        #expect(SoundCue(from: .recording(startedAt: startedAt, target: nil), to: .finishing) == .stop)
    }

    @Test func deliveryOutcomesStaySilent() {
        #expect(SoundCue(from: .finishing, to: .pasted(appName: "TextEdit")) == nil)
        #expect(SoundCue(from: .finishing, to: .copied) == nil)
        #expect(SoundCue(from: .finishing, to: .kept) == nil)
    }

    @Test func failureCuePlaysOnFailure() {
        #expect(SoundCue(from: .finishing, to: .failed("x")) == .failure)
    }
}
