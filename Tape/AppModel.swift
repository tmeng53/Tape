import AppKit
import Observation
import OSLog
import TapeCore
import TapeMac

@MainActor
@Observable
final class AppModel {
    private(set) var status: SessionStatus = .idle
    private(set) var missingPermissions: [Permission] = []
    private(set) var keyTapRunning = false

    var talkKey: ModifierKey {
        didSet {
            UserDefaults.standard.set(talkKey.rawValue, forKey: Self.talkKeyDefaultsKey)
            tap.talkKey = talkKey
        }
    }

    let clipsFolder: URL
    @ObservationIgnored private let session: RecordingSession
    @ObservationIgnored private let tap: TalkKeyTap
    @ObservationIgnored private var maxDurationTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var actionLoop: Task<Void, Never>?
    @ObservationIgnored private let actions: AsyncStream<TalkGesture.Action>
    @ObservationIgnored private let actionSink: AsyncStream<TalkGesture.Action>.Continuation
    @ObservationIgnored private let log = Logger(subsystem: TapeLog.subsystem, category: "app")

    static let talkKeyDefaultsKey = "talkKey"
    static let maxDuration: Duration = .seconds(300)

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.talkKeyDefaultsKey).flatMap(ModifierKey.init(rawValue:))
        let initialKey = saved ?? .leftControl
        talkKey = initialKey
        clipsFolder = URL.applicationSupportDirectory.appending(path: "Tape/Clips", directoryHint: .isDirectory)
        session = RecordingSession(
            recorder: ScreenCaptureRecorder(),
            focus: AXFocusReader(),
            delivery: PasteboardDelivery(),
            store: LocalClipStore(root: clipsFolder)
        )
        tap = TalkKeyTap(talkKey: initialKey)
        let (actions, continuation) = AsyncStream.makeStream(of: TalkGesture.Action.self)
        self.actions = actions
        actionSink = continuation

        session.onStatus = { [weak self] in self?.statusChanged($0) }
        tap.onAction = { continuation.yield($0) }
    }

    var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    func launch() async {
        startActionLoop()
        for permission in Permission.allCases where !permission.isGranted {
            await permission.request()
        }
        refreshPermissions()
        while !tap.start() {
            try? await Task.sleep(for: .seconds(2))
            refreshPermissions()
        }
        keyTapRunning = true
        refreshPermissions()
    }

    private func startActionLoop() {
        guard actionLoop == nil else { return }
        let session = session
        let actions = actions
        actionLoop = Task {
            for await action in actions {
                await session.perform(action)
            }
        }
    }

    func refreshPermissions() {
        missingPermissions = Permission.allCases.filter { !$0.isGranted }
    }

    func openClipsFolder() {
        try? FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(clipsFolder)
    }

    private func statusChanged(_ newStatus: SessionStatus) {
        status = newStatus
        switch newStatus {
        case .recording:
            NSSound(named: "Tink")?.play()
            if maxDurationTask == nil {
                maxDurationTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.maxDuration)
                    guard let self, !Task.isCancelled, self.isRecording else { return }
                    self.tap.recordingEndedExternally()
                    self.actionSink.yield(.stopAndDeliver)
                }
            }
        case .pasted, .copied, .kept, .failed:
            maxDurationTask?.cancel()
            maxDurationTask = nil
            if case let .failed(message) = newStatus {
                log.error("\(message, privacy: .public)")
                NSSound(named: "Basso")?.play()
            } else {
                NSSound(named: "Pop")?.play()
            }
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                if case .recording = self.status { return }
                if case .finishing = self.status { return }
                self.status = .idle
            }
        case .idle, .finishing:
            if case .idle = newStatus {
                maxDurationTask?.cancel()
                maxDurationTask = nil
            }
        }
    }
}
