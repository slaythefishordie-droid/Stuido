import Foundation
import XCTest

@testable import KnowledgeCore

final class ReviewSchedulerTests: XCTestCase {
    func testReviewIsAtomicIdempotentAndSurvivesReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let repository = try LibraryRepository(url: url)
        var card = LibraryCard(type: .keyword, content: ["term": "Test", "explanation": "Meaning"])
        card.review = .active
        try repository.update { $0.cards.append(card) }
        let event = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try repository.recordReview(
            cardID: card.id, rating: 3, expectedRevision: nil, eventID: event, now: now)
        let result = try repository.read()
        XCTAssertEqual(result.reviewRecords.count, 1)
        XCTAssertEqual(result.cards[0].schedule?.revision, 1)
        XCTAssertGreaterThan(try XCTUnwrap(result.cards[0].schedule?.due), now)
        XCTAssertNotNil(result.reviewRecords[0].schedulerBefore)
        XCTAssertNotNil(result.reviewRecords[0].schedulerLog)
        try repository.recordReview(
            cardID: card.id, rating: 3, expectedRevision: nil, eventID: event, now: now)
        XCTAssertEqual(try repository.read(), result)
        XCTAssertThrowsError(
            try repository.recordReview(
                cardID: card.id, rating: 4, expectedRevision: nil, eventID: UUID(), now: now))
        XCTAssertEqual(try LibraryRepository(url: url).read(), result)
        try repository.update { $0.cards[0].review = .not_enrolled }
        XCTAssertEqual(try repository.read().cards[0].schedule, result.cards[0].schedule)
        XCTAssertEqual(try repository.read().reviewRecords.count, 1)
    }
    func testRetentionDoesNotRewriteDueAndUnknownVersionFailsClosed() throws {
        var schedule = try ReviewSchedule(now: Date(timeIntervalSince1970: 1_800_000_000))
        let due = schedule.due
        try schedule.setRetention(0.85)
        XCTAssertEqual(schedule.due, due)
        XCTAssertEqual(schedule.retention, 0.85)
        XCTAssertThrowsError(try schedule.setRetention(1.0))
        schedule.version = "unknown"
        XCTAssertThrowsError(try schedule.validate())
    }
}
