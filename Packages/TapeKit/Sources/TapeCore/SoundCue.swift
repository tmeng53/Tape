public enum SoundCue: Equatable, Sendable {
    case start
    case stop
    case failure

    public init?(from old: SessionStatus, to new: SessionStatus) {
        switch (old, new) {
        case (.recording, .recording): return nil
        case (_, .recording): self = .start
        case (.finishing, .finishing): return nil
        case (_, .finishing): self = .stop
        case (_, .failed): self = .failure
        default: return nil
        }
    }
}
