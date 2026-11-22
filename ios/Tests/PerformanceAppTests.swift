import Foundation
import KnowledgeCore
import Observation
import UIKit
import XCTest
@testable import KnowledgeStudio

private final class ObservationCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@MainActor
final class PerformanceAppTests: XCTestCase {
    func testCollectionObservationDoesNotInvalidateCardsForReadingOrMessages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        try model.commit { $0.sources.append(source) }
        let cards = ObservationCount(), marks = ObservationCount(), sources = ObservationCount()
        withObservationTracking { _ = model.cards } onChange: { cards.increment() }
        withObservationTracking { _ = model.markIndex } onChange: { marks.increment() }
        withObservationTracking { _ = model.sources } onChange: { sources.increment() }
        model.message = "Information"
        model.saveLocation(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 2))
        XCTAssertEqual(cards.value, 0)
        XCTAssertEqual(marks.value, 0)
        XCTAssertEqual(sources.value, 1)
        model.saveCard(LibraryCard(type: .word, content: ["word": "Test"]))
        XCTAssertEqual(cards.value, 1)
    }

    func testQueuedPositionsKeepLatestAndPreserveEditsAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        try model.commit { $0.sources.append(source) }
        for page in 1...200 {
            model.queueReadingPosition(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: page))
        }
        model.saveCard(LibraryCard(type: .keyword, content: ["term": "Preserved"]))
        try await model.flushReadingPositions()
        let reopened = try LibraryRepository(url: root.appendingPathComponent("library.sqlite")).read()
        XCTAssertEqual(reopened.sources[0].lastLocation?.page, 200)
        XCTAssertEqual(reopened.cards.count, 1)
        XCTAssertEqual(model.sources, reopened.sources)
        let savedAt = reopened.sources[0].lastReadAt
        model.queueReadingPosition(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 200))
        try await model.flushReadingPositions()
        XCTAssertEqual(model.sources[0].lastReadAt, savedAt)
    }

    func testQueuedPositionCannotOverwriteNewerExplicitMark() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        try model.commit { $0.sources.append(source) }
        model.queueReadingPosition(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))
        model.saveMark(source: source, locator: ReadingLocator(kind: "pdf", page: 9))
        try await model.flushReadingPositions()
        XCTAssertEqual(model.sources[0].lastLocation?.page, 9)
        XCTAssertEqual(model.marks.count, 1)
    }

    func testDecodedCustomCoverIsBoundedAndCacheClearPreservesOriginal() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 800))
        let data = try XCTUnwrap(renderer.image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 800))
        }.jpegData(compressionQuality: 0.8))
        let decoded = await StudyThumbnails.customArt(data)
        let image = try XCTUnwrap(decoded)
        XCTAssertEqual(image.cgImage?.width, 420)
        XCTAssertEqual(image.cgImage?.height, 210)
        StudyThumbnails.releaseMemory()
        let decodedAgain = await StudyThumbnails.customArt(data)
        let reloaded = try XCTUnwrap(decodedAgain)
        XCTAssertEqual(reloaded.cgImage?.width, 420)
        XCTAssertGreaterThan(data.count, 0)
    }
}
