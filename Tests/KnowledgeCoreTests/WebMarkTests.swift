import Foundation
import XCTest

@testable import KnowledgeCore

final class WebMarkTests: XCTestCase {
    private func mark(id: UUID = UUID(), seconds: Double = 12.8) throws -> WebMark {
        WebMark(
            version: 1, id: id, videoID: try YouTubeVideoID("dQw4w9WgXcQ"), title: "Example",
            capturedSeconds: seconds, preRoll: 2, seconds: max(0, floor(seconds - 2)),
            createdAt: 1_700_000_000_000)
    }

    func testReopenAndDuplicateDeliveryPreserveIDAndOriginalTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try mark()
        try WebMarkStore(directory: directory).save(original)
        let reopened = WebMarkStore(directory: directory)
        try reopened.save(original)
        XCTAssertEqual(try reopened.readAll(), [original])
        XCTAssertEqual(original.capturedSeconds, 12.8)
        XCTAssertEqual(original.seconds, 10)
    }

    func testConflictingIDAndCorruptionNeverOverwriteOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WebMarkStore(directory: directory)
        let original = try mark()
        try store.save(original)
        XCTAssertThrowsError(try store.save(mark(id: original.id, seconds: 20)))
        XCTAssertEqual(try store.readAll(), [original])
        let file = directory.appendingPathComponent(original.id.uuidString + ".json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.readAll())
        XCTAssertThrowsError(try store.save(original))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testInvalidTimestampAndVersionAreRejected() throws {
        XCTAssertNoThrow(try mark(seconds: 0).validate())
        XCTAssertThrowsError(try mark(seconds: -1).validate())
        XCTAssertThrowsError(try mark(seconds: .infinity).validate())
        XCTAssertThrowsError(try mark(seconds: 3_155_760_001).validate())
        let valid = try mark()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as! [String: Any]
        json["seconds"] = 12
        XCTAssertThrowsError(
            try JSONDecoder().decode(WebMark.self, from: JSONSerialization.data(withJSONObject: json))
                .validate())
        json["version"] = 2
        XCTAssertThrowsError(
            try JSONDecoder().decode(WebMark.self, from: JSONSerialization.data(withJSONObject: json))
                .validate())
    }

    func testWriteFailureDoesNotReportSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("keep".utf8).write(to: directory)
        XCTAssertThrowsError(try WebMarkStore(directory: directory).save(mark()))
        XCTAssertEqual(try Data(contentsOf: directory), Data("keep".utf8))
    }

    @MainActor
    func testConcurrentIndependentStoresDoNotLoseMarks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try (0..<20).map { _ in try mark() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for record in records + records {
                group.addTask { try WebMarkStore(directory: directory).save(record) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(
            Set(try WebMarkStore(directory: directory).readAll().map(\.id)), Set(records.map(\.id)))
    }
}
