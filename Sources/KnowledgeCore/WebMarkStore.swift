import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Immutable handoff record. Original playback seconds and adjusted locator are distinct.
public struct WebMark: Codable, Equatable, Identifiable, Sendable {
    public let version: Int
    public let id: UUID
    public let videoID: YouTubeVideoID
    public let title: String
    public let capturedSeconds: Double
    public let preRoll: Int
    public let seconds: Double
    public let createdAt: Double // Unix milliseconds, shared with JavaScript.
    public var note: String? = nil
    public var deletedAt: Double? = nil
    public var updatedAt: Double? = nil

    public func validate() throws {
        guard version == 1 else { throw VideoError.unsupportedVersion }
        guard (note?.utf8.count ?? 0) <= 20_000, deletedAt == nil || (deletedAt!.isFinite && deletedAt! >= 0), updatedAt == nil || (updatedAt!.isFinite && updatedAt! >= 0),
              !title.isEmpty, title.utf8.count <= 4096,
              capturedSeconds.isFinite, capturedSeconds >= 0, capturedSeconds <= 3_155_760_000,
              (0...3).contains(preRoll), seconds.isFinite,
              seconds == max(0, floor(capturedSeconds - Double(preRoll))),
              createdAt.isFinite, createdAt >= 0, createdAt <= 8_640_000_000_000_000 else { throw VideoError.corruptStore }
    }

    public var sourceURL: URL { videoID.watchURL }
}

/// One immutable file per ID; flock serializes extension processes and App readers.
/// The App reads these same records, so no destructive queue acknowledgement is needed.
public struct WebMarkStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func save(_ mark: WebMark) throws {
        try mark.validate()
        try locked {
            let url = directory.appendingPathComponent(mark.id.uuidString + ".json")
            do {
                let existing = try JSONDecoder().decode(WebMark.self, from: Data(contentsOf: url))
                try existing.validate()
                var original = existing
                original.note = mark.note; original.deletedAt = mark.deletedAt; original.updatedAt = mark.updatedAt
                guard original == mark else { throw VideoError.corruptStore }
                return
            } catch CocoaError.fileReadNoSuchFile { }
            try JSONEncoder().encode(mark).write(to: url, options: .atomic)
        }
    }

    public func annotate(id: UUID, note: String? = nil, deleted: Bool? = nil) throws {
        try locked {
            let url = directory.appendingPathComponent(id.uuidString + ".json")
            var mark = try JSONDecoder().decode(WebMark.self, from: Data(contentsOf: url))
            guard mark.id == id else { throw VideoError.corruptStore }
            if let note { mark.note = note }
            if let deleted { mark.deletedAt = deleted ? Date().timeIntervalSince1970 * 1000 : nil }
            mark.updatedAt = Date().timeIntervalSince1970 * 1000
            try mark.validate()
            try JSONEncoder().encode(mark).write(to: url, options: .atomic)
        }
    }

    public func readAll() throws -> [WebMark] {
        try locked {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let marks = try files.filter { $0.pathExtension == "json" }.map { url in
                let mark = try JSONDecoder().decode(WebMark.self, from: Data(contentsOf: url))
                try mark.validate()
                guard url.deletingPathExtension().lastPathComponent == mark.id.uuidString else {
                    throw VideoError.corruptStore
                }
                return mark
            }
            return marks.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
