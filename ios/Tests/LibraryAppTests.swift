import Foundation
import KnowledgeCore
import PDFKit
@preconcurrency import ReadiumNavigator
import ReadiumShared
@preconcurrency import ReadiumZIPFoundation
import UIKit
import XCTest

@testable import KnowledgeStudio

@MainActor
final class LibraryAppTests: XCTestCase {
    func testCommitPublishesPersistedSourceAndMarkTogether() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Paper")
        let mark = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 2))
        try model.commit {
            $0.sources.append(source)
            $0.marks.append(mark)
        }
        XCTAssertEqual(model.state.marks.first?.sourceID, model.state.sources.first?.id)
        let saved = model.state
        XCTAssertThrowsError(try model.commit { $0.sources.removeAll() })
        XCTAssertEqual(model.state, saved)
        XCTAssertEqual(try model.repository?.read(), saved)
    }

    func testReadingSpreadsRespectTheActualWindow() {
        XCTAssertTrue(StudyPageLayout.automatic.usesSpread(in: CGSize(width: 1024, height: 680)))
        XCTAssertFalse(StudyPageLayout.automatic.usesSpread(in: CGSize(width: 820, height: 1050)))
        XCTAssertTrue(StudyPageLayout.spread.usesSpread(in: CGSize(width: 820, height: 1050)))
        XCTAssertFalse(StudyPageLayout.spread.usesSpread(in: CGSize(width: 620, height: 550)))
        XCTAssertFalse(StudyPageLayout.single.usesSpread(in: CGSize(width: 1220, height: 680)))
    }

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
    func testEPUBFontSliderConvertsPercentToReadiumScale() {
        XCTAssertEqual(EPUBSession.fontScale(for: 110), 1.1, accuracy: 0.001)
        XCTAssertEqual(EPUBSession.fontScale(for: 80), 0.8, accuracy: 0.001)
        XCTAssertEqual(EPUBSession.fontScale(for: 180), 1.8, accuracy: 0.001)
    }

    func testWordAndKeywordFromInboxRetainAnchorAndProjectOnSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Paper")
        let locator = ReadingLocator(kind: "pdf", page: 2)
        let mark = LibraryMark(sourceID: source.id, locator: locator, excerpt: "tea")
        var project = LibraryProject(title: "Reading")
        project.sourceIDs = [source.id]
        try model.commit {
            $0.sources = [source]
            $0.projects = [project]
            $0.marks = [mark]
        }
        for kind in [CardKind.word, .keyword] {
            let card = model.card(from: mark, type: kind)
            XCTAssertEqual(card.title, mark.excerpt)
            XCTAssertEqual(card.sourceRefs.first?.locator, locator)
            XCTAssertEqual(model.suggestedProjects(for: card), [project.id])
            model.saveCard(card, projects: model.suggestedProjects(for: card))
            XCTAssertNil(model.message)
            XCTAssertTrue(model.state.projects[0].cardIDs.contains(card.id))
            XCTAssertEqual(model.state.cards.last?.markIDs, [mark.id])
        }
    }

    func testImportedEPUBOpensInReadiumAndDuplicateLinksExistingSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let project = LibraryProject(title: "Reading")
        try model.commit { $0.projects = [project] }

        let input = root.appendingPathComponent("reading.epub")
        let archive = try await Archive(url: input, accessMode: .create)
        let entries = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", """
                <?xml version="1.0" encoding="UTF-8"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles>
                </container>
                """),
            ("book.opf", """
                <?xml version="1.0" encoding="UTF-8"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:identifier id="book-id">urn:uuid:acea7480-0266-48f4-ad6c-70223c747f32</dc:identifier>
                    <dc:title>Reading Fixture</dc:title><dc:language>en</dc:language>
                    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>
                  </metadata>
                  <manifest>
                    <item id="navigation" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine><itemref idref="chapter"/></spine>
                </package>
                """),
            ("nav.xhtml", """
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                  <head><title>Contents</title></head>
                  <body><nav epub:type="toc"><ol><li><a href="chapter.xhtml">Chapter</a></li></ol></nav></body>
                </html>
                """),
            ("chapter.xhtml", """
                <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter</title></head>
                <body><p>A short passage for the EPUB reader.</p></body></html>
                """),
        ]
        let entryFile = root.appendingPathComponent("entry")
        for (name, content) in entries {
            try Data(content.utf8).write(to: entryFile)
            try await archive.addEntry(with: name, fileURL: entryFile, compressionMethod: .none)
        }

        await model.importFile(input)
        XCTAssertNil(model.message)
        let source = try XCTUnwrap(model.state.sources.first)
        XCTAssertEqual(source.kind, .epub)
        await model.importFile(input, projectID: project.id)
        XCTAssertNil(model.message)
        XCTAssertEqual(model.state.sources.count, 1)
        XCTAssertEqual(model.state.projects[0].sourceIDs, [source.id])

        let session = EPUBSession()
        await session.open(url: try XCTUnwrap(model.assetURL(source)), location: nil,
            preferences: .init(columnCount: .one, fontSize: EPUBSession.fontScale(for: 110)))
        XCTAssertNil(session.error)
        XCTAssertNotNil(session.navigator)
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
            state.sources[0].coverImage = Data([1, 2, 3])
            if let fingerprint = source.assetHash {
                state.sources[0].pdfPageInk = [
                    PDFPageInk(fingerprint: fingerprint, page: 1, drawing: Data([4, 5, 6]))
                ]
            }
            var project = LibraryProject(title: "Study")
            project.sourceIDs = [source.id]
            project.boardCoverImage = Data([7, 8, 9])
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
    func testInboxCardAndArchiveCommitTogetherAndReopenWithoutDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Paper")
        let mark = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1), excerpt: "Tea")
        try model.commit { $0.sources = [source]; $0.marks = [mark] }
        let card = model.card(from: mark, type: .word)
        try await model.saveEditedCard(card, projects: [], inboxMark: mark.id)
        XCTAssertEqual(model.state.marks[0].organization, .archived)
        model.change { $0.marks[0].organization = .inbox }
        try await model.saveEditedCard(card, projects: [], inboxMark: mark.id)
        XCTAssertEqual(model.state.cards.map(\.id), [card.id])
        XCTAssertEqual(StudioModel(root: root).state.marks[0].organization, .archived)
    }

    func testPermanentSourceRemovalDeletesAssetAndKeepsRenamingIndependent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let input = root.appendingPathComponent("fixture.pdf")
        try Data("fixture for asset copy".utf8).write(to: input)
        await model.importFile(input)
        let source = try XCTUnwrap(model.state.sources.first)
        let asset = try XCTUnwrap(model.assetURL(source))
        model.renameSource(source.id, title: "Renamed")
        XCTAssertEqual(model.state.sources.first?.title, "Renamed")
        XCTAssertEqual(model.state.sources.first?.assetHash, source.assetHash)
        XCTAssertEqual(model.state.sources.first.flatMap { model.assetURL($0) }, asset)
        model.delete([source.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.path))
        await model.importFile(input)
        XCTAssertEqual(model.state.sources.count, 1)
        XCTAssertNotNil(model.message)
        model.delete([source.id], restore: true)
        XCTAssertNil(model.state.sources[0].deletedAt)
        model.delete([source.id])
        model.delete([source.id], permanently: true)
        XCTAssertNil(model.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
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
        let unselected = assets.appendingPathComponent("unselected.pdf")
        try Data("also unused".utf8).write(to: unselected)
        model.cleanUnusedAssets([orphan])
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unselected.path))
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
