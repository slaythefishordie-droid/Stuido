import Foundation
import KnowledgeCore
import YouTubePlayerKit

@MainActor
final class YouTubeClock: VideoClock {
    let player: YouTubePlayer
    init(player: YouTubePlayer) { self.player = player }

    func sample() async throws -> PlaybackSample {
        let before = try YouTubeVideoID(urlString: await player.getVideoURL())
        let seconds = try await player.getCurrentTime().converted(to: .seconds).value
        let after = try YouTubeVideoID(urlString: await player.getVideoURL())
        guard before == after else { throw VideoError.staleSession }
        return PlaybackSample(videoID: after, seconds: seconds)
    }

    func seek(seconds: Double) async throws {
        try await player.seek(to: .init(value: seconds, unit: .seconds), allowSeekAhead: true)
    }
}
