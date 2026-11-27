import Foundation
import XCTest
@testable import KnowledgeCore
final class ContentSizeTests: XCTestCase {
    func testCollectionInvalidationDeletionAndFailure() throws {
        var cache = LibraryContentSizeCache(), state = LibraryState()
        state.sources = [LibrarySource(kind: .pdf, title: "书")]
        state.cards = [LibraryCard(type: .word, content: ["word": "test"])]
        let original = try cache.measure(state)
        XCTAssertEqual(cache.encodedCollectionCount, 6)
        XCTAssertEqual(try cache.measure(state), original)
        XCTAssertEqual(cache.encodedCollectionCount, 0)
        state.sources[0].lastLocation = ReadingLocator(kind: "pdf", page: 8)
        let updated = try cache.measure(state)
        XCTAssertEqual(cache.encodedCollectionCount, 1)
        XCTAssertEqual(updated["卡片"], original["卡片"])
        XCTAssertEqual(updated["资料"], Int64(try JSONEncoder().encode(state.sources).count - 2))
        state.cards[0].deletedAt = .now
        XCTAssertEqual(try cache.measure(state)["卡片"], 0)
        XCTAssertEqual(cache.encodedCollectionCount, 1)
        let good = state
        state.sources[0].createdAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertThrowsError(try cache.measure(state))
        _ = try cache.measure(good)
        XCTAssertEqual(cache.encodedCollectionCount, 0)
    }
}
