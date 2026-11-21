import Foundation

public struct FocusTarget: Equatable, Sendable {
    public var processID: Int32
    public var bundleID: String?
    public var appName: String
    public var role: String

    public init(processID: Int32, bundleID: String?, appName: String, role: String) {
        self.processID = processID
        self.bundleID = bundleID
        self.appName = appName
        self.role = role
    }
}

public protocol ScreenRecording: AnyObject, Sendable {
    func start(writingTo url: URL) async throws
    func stop() async throws
}

public protocol FocusReading: AnyObject, Sendable {
    @MainActor func focusedTextTarget() -> FocusTarget?
}

public protocol ClipDelivering: AnyObject, Sendable {
    @MainActor func paste(_ fileURL: URL, into target: FocusTarget, recipe: PasteRecipe) async throws
    @MainActor func copyToClipboard(_ fileURL: URL)
}

public protocol ClipStoring: AnyObject, Sendable {
    func makeDraft(at date: Date) throws -> ClipDraft
    func finish(_ draft: ClipDraft, manifest: ClipManifest) throws
    func discard(_ draft: ClipDraft)
}
