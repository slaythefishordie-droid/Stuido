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
    func testSelectionSaveGateAllowsNewSelectionAndRetry() {
        var gate = PendingSelectionSaves()
        let first = ReadingLocator(kind: "pdf", page: 1)
        let second = ReadingLocator(kind: "pdf", page: 2)
        XCTAssertTrue(gate.begin(first))
        XCTAssertFalse(gate.begin(first), "Repeated taps before commit must not duplicate a highlight")
        XCTAssertTrue(gate.begin(second), "A new selection remains interactive")
        gate.finish(first)
        XCTAssertTrue(gate.begin(first), "A failed or completed save must release its selection")
        XCTAssertFalse(gate.begin(second))
    }

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

    func testFailedPositionCanRetryAndMarksRemainDurable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        try model.commit { $0.sources.append(source) }
        model.queueReadingPosition(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 0))
        do { try await model.flushReadingPositions(); XCTFail("Invalid locator must fail") } catch {}
        XCTAssertNil(model.sources[0].lastLocation)
        XCTAssertNotNil(model.message)
        model.queueReadingPosition(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 5))
        try await model.flushReadingPositions()
        try await model.saveMarkAsync(source: source, locator: ReadingLocator(kind: "pdf", page: 9), excerpt: "Quote", kind: .expression)
        let reopened = try LibraryRepository(url: root.appendingPathComponent("library.sqlite")).read()
        XCTAssertEqual(reopened.marks[0].excerpt, "Quote")
        XCTAssertEqual(reopened.marks[0].cardKind, .expression)
        XCTAssertEqual(reopened.sources[0].lastLocation?.page, 9)
    }

    func testAsyncInkSavesPreserveConflictProtectionAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let fingerprint = String(repeating: "a", count: 64)
        let source = LibrarySource(kind: .pdf, title: "Book", assetHash: fingerprint, assetExtension: "pdf")
        let epub = LibrarySource(kind: .epub, title: "EPUB")
        let mark = LibraryMark(sourceID: epub.id, locator: ReadingLocator(kind: "epub", href: "chapter.xhtml", nativeJSON: "{}"))
        try model.commit { $0.sources = [source, epub]; $0.marks = [mark] }
        try await model.savePDFInk(sourceID: source.id, fingerprint: fingerprint, page: 1, drawing: Data([1]), expected: nil)
        do {
            try await model.savePDFInk(sourceID: source.id, fingerprint: fingerprint, page: 1, drawing: Data([2]), expected: nil)
            XCTFail("Stale window must fail")
        } catch {}
        try await model.saveEPUBInk(mark: mark, drawing: Data([3]))
        do { try await model.saveEPUBInk(mark: mark, drawing: Data([4])); XCTFail("Stale note must fail") } catch {}
        let reopened = try LibraryRepository(url: root.appendingPathComponent("library.sqlite")).read()
        XCTAssertEqual(reopened.sources[0].pdfPageInk?[0].drawing, Data([1]))
        XCTAssertEqual(reopened.marks[0].epubNoteInk, Data([3]))
    }

    func testFlushWaitsForRegisteredReaderSaveBeforeItsTaskStarts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        try model.commit { $0.sources.append(source) }
        model.scheduleReaderSave {
            do { try await model.saveMarkAsync(source: source, locator: ReadingLocator(kind: "pdf", page: 7)) }
            catch { XCTFail(error.localizedDescription) }
        }
        // No sleep/yield: this is the same boundary used by export and restore.
        try await model.flushReaderWrites()
        XCTAssertEqual(try model.repository?.read().marks.count, 1)
        XCTAssertEqual(model.marks.count, 1)
    }

    func testReaderPresentationCallbacksReleaseSessions() {
        weak var pdf: PDFSession?
        weak var epub: EPUBSession?
        autoreleasepool {
            let session = PDFSession(url: URL(fileURLWithPath: "/unused.pdf"), location: nil)
            pdf = session
            session.view.capture = { [session] _, _ in _ = session.view }
            session.view.dictionary = { [session] _ in _ = session.view }
            session.disconnectPresentation()
            let book = EPUBSession()
            epub = book
            book.selectMark = { [book] _ in _ = book.navigator }
            book.savePosition = { [book] _ in _ = book.navigator }
            book.saveSelection = { [book] _, _, _ in _ = book.navigator; return true }
            book.disconnectPresentation()
        }
        XCTAssertNil(pdf, "Closed PDF presentation must release its callback ownership cycle")
        XCTAssertNil(epub, "Closed EPUB presentation must release its callback ownership cycle")
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
