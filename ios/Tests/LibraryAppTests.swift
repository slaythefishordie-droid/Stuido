import Foundation
import KnowledgeCore
import PDFKit
import ReadiumShared
@preconcurrency import ReadiumZIPFoundation
import UIKit
import XCTest

@testable import KnowledgeStudio

@MainActor
final class LibraryAppTests: XCTestCase {
    func testReadingResumeRecordsActualRecencyWithoutDuplicateWrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Reading")
        model.change { $0.sources.append(source) }
        let locator = ReadingLocator(kind: "pdf", page: 3)
        model.saveLocation(sourceID: source.id, locator: locator)
        let saved = model.state.sources[0]
        XCTAssertNotNil(saved.lastReadAt)
        model.saveLocation(sourceID: source.id, locator: locator)
        XCTAssertEqual(model.state.sources[0], saved)
        XCTAssertEqual(try model.repository?.read().sources[0], saved)
    }
    func testStaleCardEditorCannotOverwriteCompletedReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        var card = LibraryCard(type: .keyword, content: ["term": "Recall", "explanation": "Meaning"])
        card.review = .active
        model.saveCard(card)
        try model.repository?.recordReview(cardID: card.id, rating: 3, expectedRevision: nil, eventID: UUID())
        card.note = "Edited before review completed"
        model.saveCard(card)
        XCTAssertEqual(model.state.cards[0].schedule?.revision, 1)
        XCTAssertEqual(model.state.reviewRecords.count, 1)
        XCTAssertEqual(model.state.cards[0].note, card.note)
    }
    func testPDFSelectedRangeAndRegionSurviveSerialization() throws {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData {
            context in
            context.beginPage()
            ("First repeated word. Second repeated word." as NSString).draw(
                at: CGPoint(x: 30, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
        let document = try XCTUnwrap(PDFKit.PDFDocument(data: data))
        let page = try XCTUnwrap(document.page(at: 0))
        let text = try XCTUnwrap(page.string) as NSString
        let range = text.range(of: "repeated", options: .backwards)
        XCTAssertNotEqual(range.location, NSNotFound)
        let selection = try XCTUnwrap(page.selection(for: range))
        let locator = selection.studioLocator(document: document, fallbackPage: 1, fingerprint: "fixture")
        let decoded = try JSONDecoder().decode(ReadingLocator.self, from: JSONEncoder().encode(locator))
        XCTAssertEqual(decoded, locator)
        XCTAssertFalse(locator.rectangles.isEmpty)
        XCTAssertTrue(try XCTUnwrap(locator.pdfTextAnchors).allSatisfy { $0.matches(text as String) })
        XCTAssertEqual(locator.pdfTextAnchors?.first?.location, range.location)
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "changed", pageCount: 1), .unavailable)
        page.rotation = 90
        XCTAssertEqual(
            locator.rectangles, decoded.rectangles, "Page-space geometry must not be rewritten after rotation"
        )
    }
    func testEPUBSelectionLocatorRoundTripPreservesTextContext() throws {
        let json: [String: Any] = [
            "href": "chapter.xhtml", "type": "application/xhtml+xml",
            "locations": ["progression": 0.35],
            "text": ["before": "Before ", "highlight": "Selected words", "after": " after"],
        ]
        let locator = try XCTUnwrap(try Locator(json: ReadiumShared.JSONValue(json), warnings: nil))
        let stored = try EPUBSession.readingLocator(locator)
        let decoded = try JSONSerialization.jsonObject(with: Data(XCTUnwrap(stored.nativeJSON).utf8))
        let reopened = try XCTUnwrap(try Locator(json: ReadiumShared.JSONValue(decoded), warnings: nil))
        XCTAssertEqual(reopened.text.highlight, "Selected words")
        XCTAssertEqual(reopened.text.before, "Before ")
        XCTAssertEqual(reopened.text.after, " after")
        XCTAssertEqual(reopened.locations.progression, 0.35)
        XCTAssertEqual(reopened.href.string, "chapter.xhtml")
    }
    func testHighlightPaletteMatchesCardTypes() {
        XCTAssertEqual(CardKind.word.highlightColor, .systemBlue)
        XCTAssertEqual(CardKind.expression.highlightColor, .systemYellow)
        XCTAssertEqual(CardKind.keyword.highlightColor, .systemPurple)
        XCTAssertEqual(CardKind.key_sentence.highlightColor, .systemGreen)
    }
    func testBackupRestorePreservesCardsAndReferencedAsset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let input = root.appendingPathComponent("sample.pdf")
        try Data("PDF fixture bytes".utf8).write(to: input)
        await model.importFile(input)
        let source = try XCTUnwrap(model.state.sources.first)
        var card = LibraryCard(type: .expression, content: ["text": "Example"])
        card.sourceRefs = [CardReference(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))]
        model.saveCard(card)
        model.change { state in
            state.cards[0].review = .active
            var project = LibraryProject(title: "Study")
            project.sourceIDs = [source.id]
            project.sourceNotes = [source.id.uuidString: "Project context"]
            var group = ProjectGroup(title: "Reading")
            group.cardIDs = [card.id]
            project.groups = [group]
            state.projects.append(project)
        }
        try model.repository?.recordReview(cardID: card.id, rating: 3, expectedRevision: nil, eventID: UUID())
        model.perform {}
        let original = model.state
        let zip = try await BackupService.export(model: model)
        defer { try? FileManager.default.removeItem(at: zip) }
        let validated = try await BackupService.validate(zip)
        defer { try? FileManager.default.removeItem(at: validated.directory) }
        model.delete([card.id])
        XCTAssertNotNil(model.state.cards.first?.deletedAt)
        try await BackupService.restore(validated, model: model)
        XCTAssertEqual(model.state, original)
        XCTAssertEqual(
            try Data(contentsOf: XCTUnwrap(model.assetURL(source))), Data("PDF fixture bytes".utf8))
    }
    func testBackupRejectsTraversalAndPreservesLiveState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data")
        try Data("unsafe".utf8).write(to: file)
        let zip = root.appendingPathComponent("unsafe.zip")
        let archive = try await Archive(url: zip, accessMode: .create)
        try await archive.addEntry(with: "../escape", fileURL: file)
        do {
            _ = try await BackupService.validate(zip)
            XCTFail("Traversal accepted")
        } catch {}
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.deletingLastPathComponent().appendingPathComponent("escape").path))
    }
    func testDeletingProjectNeverDeletesContentAndReferencedSourceCannotBePurged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        let mark = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))
        var project = LibraryProject(title: "Study")
        project.sourceIDs = [source.id]
        model.change {
            $0.sources = [source]
            $0.marks = [mark]
            $0.projects = [project]
        }
        model.delete([project.id])
        model.delete([project.id], permanently: true)
        XCTAssertEqual(model.state.sources.count, 1)
        XCTAssertEqual(model.state.marks.count, 1)
        model.delete([source.id])
        model.delete([source.id], permanently: true)
        XCTAssertNotNil(model.message)
        XCTAssertEqual(model.state.sources.count, 1)
        model.delete([source.id], restore: true)
        XCTAssertNil(model.state.sources[0].deletedAt)
    }
    func testAssetCleanupPreservesReferencesAndRecoverySnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let assets = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let hash = String(repeating: "a", count: 64)
        let referenced = assets.appendingPathComponent(hash + ".pdf")
        try Data("keep".utf8).write(to: referenced)
        var snapshot = LibraryState()
        snapshot.sources = [
            LibrarySource(kind: .pdf, title: "Protected", assetHash: hash, assetExtension: "pdf")
        ]
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("before-restore-test.json"))
        let orphan = assets.appendingPathComponent("orphan.pdf")
        try Data("unused".utf8).write(to: orphan)
        model.cleanUnusedAssets()
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testRestoreRejectsFalseUncompressedSize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        model.saveCard(
            LibraryCard(type: .expression, content: ["text": String(repeating: "A", count: 10000)]))
        let original = model.state
        let zip = try await BackupService.export(model: model)
        defer { try? FileManager.default.removeItem(at: zip) }
        var bytes = try Data(contentsOf: zip)
        let central = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        bytes.replaceSubrange((central.lowerBound + 24)..<(central.lowerBound + 28), with: [1, 0, 0, 0])
        try bytes.write(to: zip)
        do {
            _ = try await BackupService.validate(zip)
            XCTFail("False size accepted")
        } catch {}
        XCTAssertEqual(model.state, original)
    }

}
