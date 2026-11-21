import Foundation

public enum SessionStatus: Equatable, Sendable {
    case idle
    case recording(startedAt: Date, target: FocusTarget?)
    case finishing
    case pasted(appName: String)
    case copied
    case kept
    case failed(String)
}

@MainActor
public final class RecordingSession {
    public var onStatus: (SessionStatus) -> Void = { _ in }
    public private(set) var status: SessionStatus = .idle {
        didSet { onStatus(status) }
    }

    private let recorder: ScreenRecording
    private let focus: FocusReading
    private let delivery: ClipDelivering
    private let store: ClipStoring
    private let planner: DeliveryPlanner
    private let now: () -> Date
    private let focusPollInterval: Duration

    private var draft: ClipDraft?
    private var startTask: Task<Void, Error>?
    private var pollTask: Task<Void, Never>?
    private var lastTarget: FocusTarget?

    public init(
        recorder: ScreenRecording,
        focus: FocusReading,
        delivery: ClipDelivering,
        store: ClipStoring,
        planner: DeliveryPlanner = DeliveryPlanner(),
        focusPollInterval: Duration = .milliseconds(250),
        now: @escaping () -> Date = Date.init
    ) {
        self.recorder = recorder
        self.focus = focus
        self.delivery = delivery
        self.store = store
        self.planner = planner
        self.focusPollInterval = focusPollInterval
        self.now = now
    }

    public var isActive: Bool { draft != nil }

    public func perform(_ action: TalkGesture.Action) async {
        switch action {
        case .startRecording: start()
        case .stopAndDeliver: await finish(deliver: true)
        case .cancelRecording: await finish(deliver: false)
        case .discardRecording: await discard()
        }
    }

    public func start() {
        guard draft == nil else { return }
        let startedAt = now()
        let newDraft: ClipDraft
        do {
            newDraft = try store.makeDraft(at: startedAt)
        } catch {
            status = .failed("Couldn't create the clip folder")
            return
        }
        draft = newDraft
        lastTarget = focus.focusedTextTarget()
        status = .recording(startedAt: startedAt, target: lastTarget)
        let recorder = recorder
        startTask = Task { try await recorder.start(writingTo: newDraft.videoURL) }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.focusPollInterval ?? .milliseconds(250))
                self?.pollFocus()
            }
        }
    }

    private func pollFocus() {
        guard case let .recording(startedAt, shown) = status else { return }
        let current = focus.focusedTextTarget()
        if let current { lastTarget = current }
        if current != shown { status = .recording(startedAt: startedAt, target: current) }
    }

    private enum StopResult {
        case finished
        case neverStarted
        case stopFailed
    }

    private func stopRecorder() async -> StopResult {
        pollTask?.cancel()
        pollTask = nil
        do {
            try await startTask?.value
        } catch {
            startTask = nil
            return .neverStarted
        }
        startTask = nil
        do {
            try await recorder.stop()
            return .finished
        } catch {
            return .stopFailed
        }
    }

    private func finish(deliver: Bool) async {
        guard let draft else { return }
        let focusedAtRelease = deliver ? focus.focusedTextTarget() : nil
        let fallback = lastTarget
        status = .finishing
        let stopResult = await stopRecorder()
        self.draft = nil
        lastTarget = nil
        if stopResult == .neverStarted {
            store.discard(draft)
            status = .failed("Recording failed. Check Screen Recording and Microphone in System Settings.")
            return
        }

        let duration = now().timeIntervalSince(draft.createdAt)
        var outcome: ClipManifest.Delivery = .kept
        if deliver && stopResult == .finished {
            switch planner.decide(focusedAtRelease: focusedAtRelease, lastDuringRecording: fallback) {
            case let .paste(target, _):
                do {
                    try await delivery.paste(draft.videoURL, into: target, recipe: .forApp(bundleID: target.bundleID))
                    outcome = .pasted(bundleID: target.bundleID, appName: target.appName)
                } catch {
                    delivery.copyToClipboard(draft.videoURL)
                    outcome = .clipboard
                }
            case .waitForNextTextBox, .clipboardOnly:
                delivery.copyToClipboard(draft.videoURL)
                outcome = .clipboard
            }
        }

        let manifest = ClipManifest(
            id: draft.id,
            createdAt: draft.createdAt,
            durationSeconds: duration,
            videoFile: draft.videoURL.lastPathComponent,
            delivery: outcome
        )
        do {
            try store.finish(draft, manifest: manifest)
        } catch {
            status = .failed("Couldn't save the clip's details")
            return
        }

        if stopResult == .stopFailed {
            status = .failed("The recording may be incomplete. It's kept in the clips folder.")
            return
        }

        switch outcome {
        case let .pasted(_, appName): status = .pasted(appName: appName)
        case .clipboard: status = .copied
        case .kept: status = .kept
        }
    }

    private func discard() async {
        guard let draft else { return }
        self.draft = nil
        lastTarget = nil
        _ = await stopRecorder()
        store.discard(draft)
        status = .idle
    }
}
