import Foundation

public struct PlaybackSample: Sendable {
    public let videoID: YouTubeVideoID
    public let seconds: Double
    public init(videoID: YouTubeVideoID, seconds: Double) {
        self.videoID = videoID
        self.seconds = seconds
    }
}

@MainActor
public protocol VideoClock: AnyObject {
    func sample() async throws -> PlaybackSample
    func seek(seconds: Double) async throws
}

@MainActor
public final class MarkCapture {
    public private(set) var generation = UUID()
    public private(set) var isReady = false
    private let store: MarkStore
    private var source: VideoSource?
    private var clock: (any VideoClock)?

    public init(store: MarkStore) { self.store = store }

    @discardableResult
    public func activate(source: VideoSource, clock: any VideoClock) -> UUID {
        generation = UUID()
        self.source = source
        self.clock = clock
        isReady = false
        return generation
    }

    public func updateReady(_ ready: Bool, generation: UUID) {
        guard self.generation == generation else { return }
        isReady = ready
    }

    public func invalidate() {
        generation = UUID()
        isReady = false
        source = nil
        clock = nil
    }

    public func capture() async throws -> TimestampMark {
        guard isReady, let source, let clock else { throw VideoError.notReady }
        let token = generation
        let sample = try await clock.sample()
        try Task.checkCancellation()
        guard token == generation, isReady, sample.videoID == source.videoID else {
            throw VideoError.staleSession
        }
        // No pause(), no form, no fallback to zero. The original fraction is retained.
        return try store.append(sourceID: source.id, seconds: sample.seconds)
    }

    public func replay(_ mark: TimestampMark, preRoll: Double) async throws {
        guard isReady, let source, let clock else { throw VideoError.notReady }
        guard source.id == mark.sourceID else { throw VideoError.unknownSource }
        let token = generation
        let sample = try await clock.sample()
        try Task.checkCancellation()
        guard token == generation, isReady, sample.videoID == source.videoID else { throw VideoError.staleSession }
        try await clock.seek(seconds: mark.playbackStart(preRoll: preRoll))
        guard token == generation else { throw VideoError.staleSession }
    }
}
