import Foundation
import XCTest
@testable import KnowledgeCore

@MainActor
final class VideoTests: XCTestCase {
    func testSupportedURLsAndHostValidation() async throws {
        for url in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30",
            "https://youtu.be/dQw4w9WgXcQ?si=share",
            "https://m.youtube.com/shorts/dQw4w9WgXcQ",
            "https://youtube.com/embed/dQw4w9WgXcQ",
            "https://youtube.com/live/dQw4w9WgXcQ"
        ] { XCTAssertEqual(try YouTubeVideoID(urlString: url).rawValue, "dQw4w9WgXcQ") }
        for url in [
            "https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ",
            "https://youtube.com@evil.test/watch?v=dQw4w9WgXcQ",
            "javascript:alert(1)", "http://youtu.be/dQw4w9WgXcQ",
            "https://youtube.com/watch?v=bad", "https://youtube.com/playlist?list=abc",
            "https://youtube.com/watch?v=dQw4w9WgXcQ&v=abcdefghijk",
            "https://youtu.be/dQw4w9WgXcQ/extra", "https://youtu.be:9000/dQw4w9WgXcQ"
        ] { XCTAssertThrowsError(try YouTubeVideoID(urlString: url), url) }
    }

    @MainActor
    func testStoreReopensWithSameSourceAndExactTimestamp() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarkStore(fileURL: url)
        let first = try store.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
        XCTAssertEqual(try store.select(videoID: first.videoID).id, first.id)
        let mark = try store.append(sourceID: first.id, seconds: 42.125)
        _ = try store.append(sourceID: first.id, seconds: 0)
        let restored = try MarkStore(fileURL: url)
        XCTAssertEqual(restored.selectedSource?.id, first.id)
        XCTAssertEqual(restored.snapshot.sources.count, 1)
        XCTAssertEqual(restored.snapshot.marks.map(\.seconds), [42.125, 0])
        XCTAssertEqual(restored.snapshot.marks.first?.id, mark.id)
        XCTAssertEqual(mark.playbackStart(preRoll: 3), 39.125)
        XCTAssertEqual(mark.seconds, 42.125)
        XCTAssertEqual(restored.snapshot.marks[1].playbackStart(preRoll: 3), 0)
    }

    @MainActor
    func testInvalidTimeAndUnknownSourceNeverChangeStore() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarkStore(fileURL: url)
        let source = try store.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
        let before = try Data(contentsOf: url)
        for seconds in [Double.nan, .infinity, -.infinity, -1] {
            XCTAssertThrowsError(try store.append(sourceID: source.id, seconds: seconds))
        }
        XCTAssertThrowsError(try store.append(sourceID: UUID(), seconds: 1))
        XCTAssertTrue(store.snapshot.marks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    @MainActor
    func testFailedWriteDoesNotMutateMemory() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarkStore(fileURL: url)
        let source = try store.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
        let before = store.snapshot
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.append(sourceID: source.id, seconds: 12))
        XCTAssertEqual(store.snapshot, before)
    }

    @MainActor
    func testCorruptAndFutureDataAreNotReset() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for value in ["broken", "{\"formatVersion\":2,\"sources\":[],\"marks\":[]}"] {
            let data = Data(value.utf8)
            try data.write(to: url)
            XCTAssertThrowsError(try MarkStore(fileURL: url))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    @MainActor
    func testCaptureReadinessFailureAndZeroTime() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarkStore(fileURL: url)
        let source = try store.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
        let clock = MockClock(videoID: source.videoID)
        let capture = MarkCapture(store: store)
        let token = capture.activate(source: source, clock: clock)
        do { _ = try await capture.capture(); XCTFail("Unready player must fail") } catch { XCTAssertEqual(error as? VideoError, .notReady) }
        capture.updateReady(true, generation: token)
        clock.shouldFail = true
        do { _ = try await capture.capture(); XCTFail("Read failure must not create zero mark") } catch {}
        XCTAssertTrue(store.snapshot.marks.isEmpty)
        clock.shouldFail = false
        let mark = try await capture.capture()
        XCTAssertEqual(mark.seconds, 0)
        try await capture.replay(mark, preRoll: 3)
        XCTAssertEqual(clock.seeks, [0])
    }

    @MainActor
    func testDelayedReadAfterVideoSwitchCannotSave() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarkStore(fileURL: url)
        let first = try store.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
        let clock = MockClock(videoID: first.videoID)
        clock.suspend = true
        let capture = MarkCapture(store: store)
        let oldToken = capture.activate(source: first, clock: clock)
        capture.updateReady(true, generation: oldToken)
        let operation = Task { try await capture.capture() }
        while clock.continuation == nil { await Task.yield() }
        let second = try store.select(videoID: YouTubeVideoID("abcdefghijk"))
        _ = capture.activate(source: second, clock: MockClock(videoID: second.videoID))
        capture.updateReady(true, generation: oldToken)
        XCTAssertFalse(capture.isReady)
        clock.continuation?.resume(returning: PlaybackSample(videoID: first.videoID, seconds: 9))
        do { _ = try await operation.value; XCTFail("Stale session must fail") } catch { XCTAssertEqual(error as? VideoError, .staleSession) }
        XCTAssertTrue(store.snapshot.marks.isEmpty)
    }

    @MainActor
    func testUnexpectedPlayerVideoAndInvalidationRejectMark() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarkStore(fileURL: url)
        let source = try store.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
        let clock = MockClock(videoID: try YouTubeVideoID("abcdefghijk"))
        let capture = MarkCapture(store: store)
        let token = capture.activate(source: source, clock: clock)
        capture.updateReady(true, generation: token)
        do { _ = try await capture.capture(); XCTFail("Wrong video") } catch { XCTAssertEqual(error as? VideoError, .staleSession) }
        capture.invalidate()
        capture.updateReady(true, generation: token)
        XCTAssertFalse(capture.isReady)
        XCTAssertTrue(store.snapshot.marks.isEmpty)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("marks.json")
    }
}

@MainActor
private final class MockClock: VideoClock {
    let videoID: YouTubeVideoID
    var shouldFail = false
    var suspend = false
    var continuation: CheckedContinuation<PlaybackSample, any Error>?
    var seeks: [Double] = []
    init(videoID: YouTubeVideoID) { self.videoID = videoID }
    func sample() async throws -> PlaybackSample {
        if shouldFail { throw VideoError.invalidTime }
        if suspend { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return PlaybackSample(videoID: videoID, seconds: 0)
    }
    func seek(seconds: Double) async throws { seeks.append(seconds) }
}
