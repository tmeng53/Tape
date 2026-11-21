import Foundation
import Testing
@testable import TapeCore

final class FakeRecorder: ScreenRecording, @unchecked Sendable {
    var started: URL?
    var stopped = false
    var failStart = false
    var failStop = false

    func start(writingTo url: URL) async throws {
        if failStart { throw CocoaError(.fileWriteUnknown) }
        started = url
        try Data("video".utf8).write(to: url)
    }

    func stop() async throws {
        stopped = true
        if failStop { throw CocoaError(.fileWriteUnknown) }
    }
}

final class FakeFocus: FocusReading, @unchecked Sendable {
    var target: FocusTarget?
    func focusedTextTarget() -> FocusTarget? { target }
}

final class FakeDelivery: ClipDelivering, @unchecked Sendable {
    var pasted: [(URL, FocusTarget, PasteRecipe)] = []
    var copied: [URL] = []
    var failPaste = false

    func paste(_ fileURL: URL, into target: FocusTarget, recipe: PasteRecipe) async throws {
        if failPaste { throw CocoaError(.featureUnsupported) }
        pasted.append((fileURL, target, recipe))
    }

    func copyToClipboard(_ fileURL: URL) {
        copied.append(fileURL)
    }
}

@MainActor
struct RecordingSessionTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recorder = FakeRecorder()
    let focus = FakeFocus()
    let delivery = FakeDelivery()
    let claude = FocusTarget(
        processID: 42, bundleID: "com.anthropic.claudefordesktop", appName: "Claude", role: "AXTextArea")
    let terminal = FocusTarget(processID: 7, bundleID: "com.apple.Terminal", appName: "Terminal", role: "AXTextArea")

    func makeSession() -> (RecordingSession, LocalClipStore) {
        let store = LocalClipStore(root: root)
        return (RecordingSession(recorder: recorder, focus: focus, delivery: delivery, store: store), store)
    }

    @Test func pastesIntoBoxFocusedAtRelease() async throws {
        let (session, store) = makeSession()
        session.start()
        focus.target = claude
        await session.perform(.stopAndDeliver)

        #expect(delivery.pasted.count == 1)
        #expect(delivery.pasted.first?.1 == claude)
        #expect(delivery.pasted.first?.2 == .fileReference)
        #expect(session.status == .pasted(appName: "Claude"))
        let url = try #require(recorder.started)
        let id = try #require(UUID(uuidString: url.deletingLastPathComponent().lastPathComponent))
        #expect(try store.manifest(for: id).delivery == .pasted(bundleID: claude.bundleID, appName: "Claude"))
    }

    @Test func fallsBackToBoxFocusedDuringRecording() async {
        let (session, _) = makeSession()
        focus.target = terminal
        session.start()
        focus.target = nil
        await session.perform(.stopAndDeliver)

        #expect(delivery.pasted.first?.1 == terminal)
        #expect(delivery.pasted.first?.2 == .pathText)
    }

    @Test func copiesWhenNoTextBoxWasEverFocused() async {
        let (session, _) = makeSession()
        session.start()
        await session.perform(.stopAndDeliver)

        #expect(delivery.pasted.isEmpty)
        #expect(delivery.copied.count == 1)
        #expect(session.status == .copied)
    }

    @Test func copiesWhenPasteFails() async {
        let (session, _) = makeSession()
        delivery.failPaste = true
        focus.target = claude
        session.start()
        await session.perform(.stopAndDeliver)

        #expect(delivery.copied.count == 1)
        #expect(session.status == .copied)
    }

    @Test func cancelKeepsClipWithoutPasting() async throws {
        let (session, _) = makeSession()
        focus.target = claude
        session.start()
        await session.perform(.cancelRecording)

        #expect(delivery.pasted.isEmpty)
        #expect(session.status == .kept)
        let url = try #require(recorder.started)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func stopFailureKeepsClipWithoutPasting() async throws {
        let (session, store) = makeSession()
        recorder.failStop = true
        focus.target = claude
        session.start()
        await session.perform(.stopAndDeliver)

        #expect(delivery.pasted.isEmpty)
        #expect(delivery.copied.isEmpty)
        if case .failed = session.status {} else { Issue.record("expected failure, got \(session.status)") }
        let url = try #require(recorder.started)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let id = try #require(UUID(uuidString: url.deletingLastPathComponent().lastPathComponent))
        #expect(try store.manifest(for: id).delivery == .kept)
    }

    @Test func captureFailureCancelKeepsClipAndRepeatIsHarmless() async throws {
        let (session, store) = makeSession()
        recorder.failStop = true
        focus.target = claude
        session.start()
        await session.perform(.cancelRecording)
        await session.perform(.cancelRecording)

        #expect(!session.isActive)
        #expect(delivery.pasted.isEmpty && delivery.copied.isEmpty)
        if case .failed = session.status {} else { Issue.record("expected failure, got \(session.status)") }
        let url = try #require(recorder.started)
        let id = try #require(UUID(uuidString: url.deletingLastPathComponent().lastPathComponent))
        #expect(try store.manifest(for: id).delivery == .kept)
    }

    @Test func discardDeletesClip() async throws {
        let (session, _) = makeSession()
        session.start()
        await session.perform(.discardRecording)

        let url = try #require(recorder.started)
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        #expect(session.status == .idle)
    }

    @Test func failedStartReportsAndCleansUp() async {
        let (session, _) = makeSession()
        recorder.failStart = true
        session.start()
        await session.perform(.stopAndDeliver)

        if case .failed = session.status {} else { Issue.record("expected failure, got \(session.status)") }
        #expect(delivery.pasted.isEmpty && delivery.copied.isEmpty)
    }

    @Test func failedStartIsReportedRightAway() async throws {
        let (session, _) = makeSession()
        recorder.failStart = true
        session.start()
        for _ in 0..<100 where session.isActive { await Task.yield() }

        #expect(!session.isActive)
        if case .failed = session.status {} else { Issue.record("expected failure, got \(session.status)") }
    }

    @Test func manifestWriteFailureIsReported() async throws {
        let blocked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FailingFinishStore(root: blocked)
        let session = RecordingSession(recorder: recorder, focus: focus, delivery: delivery, store: store)
        session.start()
        await session.perform(.cancelRecording)

        if case .failed = session.status {} else { Issue.record("expected failure, got \(session.status)") }
    }
}

final class FailingFinishStore: ClipStoring, @unchecked Sendable {
    let inner: LocalClipStore
    init(root: URL) { inner = LocalClipStore(root: root) }
    func makeDraft(at date: Date) throws -> ClipDraft { try inner.makeDraft(at: date) }
    func finish(_ draft: ClipDraft, manifest: ClipManifest) throws { throw CocoaError(.fileWriteNoPermission) }
    func discard(_ draft: ClipDraft) { inner.discard(draft) }
}
