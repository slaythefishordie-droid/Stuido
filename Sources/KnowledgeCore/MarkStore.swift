import Foundation

public struct VideoSource: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let videoID: YouTubeVideoID
    public let createdAt: Date
}

public struct TimestampMark: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let sourceID: UUID
    public let seconds: Double
    public let createdAt: Date

    public func playbackStart(preRoll: Double) -> Double {
        max(0, seconds - (preRoll.isFinite ? max(0, preRoll) : 0))
    }
}

public struct PrototypeSnapshot: Codable, Equatable, Sendable {
    public var formatVersion = 1
    public var selectedSourceID: UUID?
    public var sources: [VideoSource] = []
    public var marks: [TimestampMark] = []

    public init() {}

    public func validate() throws {
        guard formatVersion == 1 else { throw VideoError.unsupportedVersion }
        let ids = Set(sources.map(\.id))
        guard ids.count == sources.count,
              Set(sources.map(\.videoID)).count == sources.count,
              Set(marks.map(\.id)).count == marks.count,
              selectedSourceID.map({ ids.contains($0) }) ?? true,
              marks.allSatisfy({ ids.contains($0.sourceID) && $0.seconds.isFinite && $0.seconds >= 0 })
        else { throw VideoError.corruptStore }
    }
}

/// Stage 0 only: versioned, atomic local storage behind a replaceable boundary.
/// Stage 1 migrates these IDs and timestamps into the formal database; never discard this file.
@MainActor
public final class MarkStore {
    public private(set) var snapshot: PrototypeSnapshot
    public let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(PrototypeSnapshot.self, from: Data(contentsOf: fileURL))
            try snapshot.validate()
        } else { snapshot = PrototypeSnapshot() }
    }

    public var selectedSource: VideoSource? {
        snapshot.sources.first { $0.id == snapshot.selectedSourceID }
    }

    @discardableResult
    public func select(videoID: YouTubeVideoID) throws -> VideoSource {
        var candidate = snapshot
        let source = candidate.sources.first { $0.videoID == videoID }
            ?? VideoSource(id: UUID(), videoID: videoID, createdAt: Date())
        if !candidate.sources.contains(where: { $0.id == source.id }) { candidate.sources.append(source) }
        candidate.selectedSourceID = source.id
        try commit(candidate)
        return source
    }

    @discardableResult
    public func append(sourceID: UUID, seconds: Double) throws -> TimestampMark {
        guard seconds.isFinite && seconds >= 0 else { throw VideoError.invalidTime }
        guard snapshot.sources.contains(where: { $0.id == sourceID }) else { throw VideoError.unknownSource }
        let mark = TimestampMark(id: UUID(), sourceID: sourceID, seconds: seconds, createdAt: Date())
        var candidate = snapshot
        candidate.marks.append(mark)
        try commit(candidate)
        return mark
    }

    private func commit(_ candidate: PrototypeSnapshot) throws {
        try candidate.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(candidate)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        snapshot = candidate // Update memory only after a successful durable write.
    }
}
