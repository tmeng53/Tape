import Testing
@testable import TapeCore

struct DeliveryTests {
    let planner = DeliveryPlanner()

    @Test func focusedAtReleaseWins() {
        #expect(planner.decide(focusedAtRelease: "a", lastDuringRecording: "b") == .paste(into: "a", reason: .focusedAtRelease))
    }

    @Test func lastDuringRecordingIsSecond() {
        #expect(planner.decide(focusedAtRelease: nil, lastDuringRecording: "b") == .paste(into: "b", reason: .lastDuringRecording))
    }

    @Test func clipboardWhenNothing() {
        #expect(planner.decide(focusedAtRelease: String?.none, lastDuringRecording: nil) == .clipboardOnly)
    }

    @Test func waitsWhenWindowEnabled() {
        let waiting = DeliveryPlanner(waitWindow: 15)
        #expect(waiting.decide(focusedAtRelease: String?.none, lastDuringRecording: nil) == .waitForNextTextBox(seconds: 15))
    }

    @Test func terminalsGetPathText() {
        #expect(PasteRecipe.forApp(bundleID: "com.googlecode.iterm2") == .pathText)
        #expect(PasteRecipe.forApp(bundleID: "com.tinyspeck.slackmacgap") == .fileReference)
        #expect(PasteRecipe.forApp(bundleID: nil) == .fileReference)
    }

    @Test func videoFileNameIsPathSafe() {
        let name = ClipNaming.videoFileName(for: .init(timeIntervalSince1970: 0), timeZone: .gmt)
        #expect(name == "tape_1970-01-01_00-00-00.mp4")
    }

    @Test func timerFormat() {
        #expect(ClipNaming.timer(7.9) == "0:07")
        #expect(ClipNaming.timer(125) == "2:05")
    }
}
