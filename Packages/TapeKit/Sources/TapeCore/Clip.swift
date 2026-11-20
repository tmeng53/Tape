import Foundation

public struct ClipManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum Delivery: Codable, Equatable, Sendable {
        case pasted(bundleID: String?, appName: String)
        case clipboard
        case kept
    }

    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var durationSeconds: Double
    public var videoFile: String
    public var delivery: Delivery

    public init(id: UUID, createdAt: Date, durationSeconds: Double, videoFile: String, delivery: Delivery) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.videoFile = videoFile
        self.delivery = delivery
    }
}

public struct ClipDraft: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let folder: URL
    public let videoURL: URL
}

public enum ClipNaming {
    public static func stamp(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d_%02d-%02d-%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    public static func videoFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        "tape_\(stamp(for: date, timeZone: timeZone)).mp4"
    }

    public static func timer(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

public final class LocalClipStore: ClipStoring {
    public let root: URL
    private let fileManager: FileManager
    private let makeID: @Sendable () -> UUID

    public init(root: URL, fileManager: FileManager = .default, makeID: @escaping @Sendable () -> UUID = { UUID() }) {
        self.root = root
        self.fileManager = fileManager
        self.makeID = makeID
    }

    public func makeDraft(at date: Date) throws -> ClipDraft {
        let id = makeID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return ClipDraft(
            id: id,
            createdAt: date,
            folder: folder,
            videoURL: folder.appendingPathComponent(ClipNaming.videoFileName(for: date))
        )
    }

    public func finish(_ draft: ClipDraft, manifest: ClipManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: draft.folder.appendingPathComponent("clip.json"), options: .atomic)
    }

    public func discard(_ draft: ClipDraft) {
        try? fileManager.removeItem(at: draft.folder)
    }

    public func manifest(for id: UUID) throws -> ClipManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let url = root.appendingPathComponent(id.uuidString).appendingPathComponent("clip.json")
        return try decoder.decode(ClipManifest.self, from: Data(contentsOf: url))
    }
}
