import Foundation
import XCTest

@testable import KnowledgeCore

final class LibraryTests: XCTestCase {
    func testHighlightTypeAndEPUBLocatorSurviveReopenAndLegacyDecode() throws {
        try withStore { repository, root in
            let source = LibrarySource(kind: .epub, title: "Book")
            let locator = ReadingLocator(
                kind: "epub", href: "chapter.xhtml", progression: 0.4,
                nativeJSON:
                    "{\"href\":\"chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"text\":{\"highlight\":\"Exact quote\",\"before\":\"Before \"}}"
            )
            var mark = LibraryMark(sourceID: source.id, locator: locator, excerpt: "Exact quote")
            mark.note = "My annotation"
            mark.cardKind = .keyword
            try repository.update {
                $0.sources.append(source)
                $0.marks.append(mark)
            }
            let reopened = try LibraryRepository(url: root.appendingPathComponent("library.sqlite")).read()
            XCTAssertEqual(reopened.marks.first, mark)
            var json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(mark)) as? [String: Any])
            json.removeValue(forKey: "cardKind")
            let old = try JSONDecoder().decode(
                LibraryMark.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(old.cardKind)
            XCTAssertEqual(old.locator, locator)
            XCTAssertEqual(old.note, mark.note)
        }
    }
    func testPDFAnchorNeverOverstatesPrecision() throws {
        var locator = ReadingLocator(kind: "pdf", page: 2)
        locator.rectangles = [HighlightRect(page: 2, x: 10, y: 20, width: 50, height: 30)]
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "same", pageCount: 3), .pageOnly)
        locator.fileFingerprint = "same"
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "same", pageCount: 3), .exactRegion)
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "different", pageCount: 3), .unavailable)
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "same", pageCount: 1), .unavailable)
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "same", pageCount: 0), .unavailable)
        locator.anchorText = "Original"
        XCTAssertEqual(
            locator.pdfAccuracy(currentFingerprint: "same", pageCount: 3, textVerified: true), .exactText)
        let restored = try JSONDecoder().decode(ReadingLocator.self, from: JSONEncoder().encode(locator))
        XCTAssertEqual(restored, locator)
        locator.rectangles[0].width = .nan
        XCTAssertEqual(locator.pdfAccuracy(currentFingerprint: "same", pageCount: 3), .pageOnly)
    }
    func testBoardRoundTripAndRemovalNeverDeletesReferencedContent() throws {
        try withStore { repository, root in
            let source = LibrarySource(kind: .pdf, title: "Book")
            let card = LibraryCard(type: .keyword, content: ["term": "Concept", "explanation": "Meaning"])
            var project = LibraryProject(title: "Study")
            var board = ProjectBoard()
            let sourceNode = BoardNode(kind: .source, text: source.title, targetID: source.id)
            let cardNode = BoardNode(kind: .card, text: card.title, targetID: card.id)
            board.nodes = [sourceNode, cardNode]
            board.edges = [BoardEdge(from: sourceNode.id, to: cardNode.id)]
            project.board = board
            try repository.update {
                $0.sources.append(source)
                $0.cards.append(card)
                $0.projects.append(project)
            }
            XCTAssertEqual(
                try LibraryRepository(url: root.appendingPathComponent("library.sqlite")).read().projects[0]
                    .board, board)
            XCTAssertThrowsError(try repository.update { $0.sources.removeAll() })
            try repository.update { $0.projects[0].board?.removeNode(sourceNode.id) }
            let state = try repository.read()
            XCTAssertEqual(state.sources.count, 1)
            XCTAssertEqual(state.cards.count, 1)
            XCTAssertEqual(state.projects[0].board?.nodes.count, 1)
            XCTAssertEqual(state.projects[0].board?.edges.count, 0)
        }
    }
    private func withStore(_ body: (LibraryRepository, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(LibraryRepository(url: root.appendingPathComponent("library.sqlite")), root)
    }
    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let local = root.appendingPathComponent("examples/import/" + name)
        let url =
            FileManager.default.fileExists(atPath: local.path)
            ? local
            : Bundle(for: LibraryTests.self).url(
                forResource: name, withExtension: nil, subdirectory: "import")!
        return try String(contentsOf: url, encoding: .utf8)
    }
    func testTransactionRollbackPreservesObjectsAndReferences() throws {
        try withStore { repository, root in
            let source = LibrarySource(kind: .pdf, title: "Book")
            try repository.update { $0.sources.append(source) }
            XCTAssertThrowsError(
                try repository.update { state in
                    state.sources.removeAll()
                    state.marks.append(
                        LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1)))
                })
            XCTAssertEqual(
                try LibraryRepository(url: root.appendingPathComponent("library.sqlite")).read().sources,
                [source])
            XCTAssertTrue(try repository.read().marks.isEmpty)
        }
    }
    func testRestoreInvalidGraphRollsBackAndValidSnapshotPreservesIDs() throws {
        try withStore { repository, _ in
            let card = LibraryCard(type: .keyword, content: ["term": "original"])
            try repository.update { $0.cards.append(card) }
            let original = try repository.read()
            var corrupt = original
            corrupt.relations.append(LibraryRelation(from: card.id, to: UUID(), kind: "related"))
            XCTAssertThrowsError(try repository.restore(corrupt))
            XCTAssertEqual(try repository.read(), original)
            try repository.update { $0.cards[0].deletedAt = Date() }
            try repository.restore(original)
            XCTAssertEqual(try repository.read(), original)
        }
    }
    func testFourTypesImportIsExplicitAtomicAndRemapsReferences() throws {
        try withStore { repository, _ in
            let preview = try ImportService.preview(
                fixture("valid-four-types.json"), existing: repository.read())
            XCTAssertTrue(try repository.read().cards.isEmpty)
            XCTAssertEqual(preview.cards.count, 4)
            let all = Set(preview.cards.map(\.id))
            XCTAssertThrowsError(
                try ImportService.commit(
                    preview, selected: all, projectID: UUID(), pendingID: nil, to: repository))
            XCTAssertTrue(try repository.read().cards.isEmpty)
            try ImportService.commit(preview, selected: all, projectID: nil, pendingID: nil, to: repository)
            let state = try repository.read()
            XCTAssertEqual(state.cards.count, 4)
            XCTAssertTrue(
                state.cards.allSatisfy {
                    $0.review == .not_enrolled && $0.note.isEmpty && $0.discovery == .ai
                })
            XCTAssertThrowsError(try ImportService.preview(fixture("valid-four-types.json"), existing: state))
            try state.validate()
        }
    }
    func testNativeImportRejectsInvalidFixturesAndDuplicateKeys() throws {
        for file in [
            "invalid-version.json", "invalid-type.json", "invalid-reference.json", "invalid-page-zero.json",
            "invalid-extra-field.json", "invalid-duplicate-id.json", "invalid-content.json",
            "invalid-missing-source-refs.json",
        ] {
            XCTAssertThrowsError(try ImportService.preview(fixture(file), existing: LibraryState()), file)
        }
        let text = try fixture("valid-word.json")
        XCTAssertThrowsError(
            try ImportService.preview(
                text.replacingOccurrences(
                    of: "\"schema_version\":", with: "\"schema_version\": \"1.0\", \"schema_version\":"),
                existing: LibraryState()))
        XCTAssertThrowsError(
            try ImportService.preview(
                text.trimmingCharacters(in: .whitespacesAndNewlines).dropLast() + ",}",
                existing: LibraryState()))
    }
    @MainActor
    func testPrototypeMigrationKeepsIDsTimesAndOriginalFile() throws {
        try withStore { repository, root in
            let file = root.appendingPathComponent("prototype-v1.json")
            let old = try MarkStore(fileURL: file)
            let source = try old.select(videoID: YouTubeVideoID("dQw4w9WgXcQ"))
            let mark = try old.append(sourceID: source.id, seconds: 12.345678)
            let bytes = try Data(contentsOf: file)
            try repository.migratePrototype(at: file)
            try repository.migratePrototype(at: file)
            XCTAssertEqual(try repository.read().sources.map(\.id), [source.id])
            XCTAssertEqual(try repository.read().marks.first?.id, mark.id)
            XCTAssertEqual(try repository.read().marks.first?.locator.seconds, 12.345678)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }
}

extension LibraryTests {
    func testSharedAnnotationsAndPermanentTombstonesSurviveRepeatedHandoff() throws {
        try withStore { repository, root in
            let shared = WebMarkStore(directory: root.appendingPathComponent("shared"))
            let mark = WebMark(
                version: 1, id: UUID(), videoID: try YouTubeVideoID("dQw4w9WgXcQ"), title: "Lesson",
                capturedSeconds: 12.8, preRoll: 2, seconds: 10, createdAt: 1000)
            try shared.save(mark)
            try repository.receive(shared.readAll())
            try shared.annotate(id: mark.id, note: "Keep note", deleted: true)
            try shared.save(mark)  // A late original delivery must not erase annotations.
            try repository.receive(shared.readAll())
            XCTAssertEqual(try repository.read().marks[0].note, "Keep note")
            XCTAssertNotNil(try repository.read().marks[0].deletedAt)
            try repository.update { $0.marks.removeAll() }
            try repository.receive(shared.readAll())
            XCTAssertTrue(try repository.read().marks.isEmpty)
        }
    }
    func testGenericCaptureRejectsInvalidOriginAndKeepsDuplicateIdentity() throws {
        try withStore { repository, root in
            let store = PageCaptureStore(directory: root.appendingPathComponent("pages"))
            let capture = PageCapture(
                version: 1, id: UUID(), kind: .article, sourceURL: "https://example.org/article",
                title: "Article", locator: ReadingLocator(kind: "article", href: "paragraph"),
                excerpt: "Original sentence", createdAt: 1000)
            try store.save(capture)
            try store.save(capture)
            try repository.receivePages(store.readAll())
            try repository.receivePages(store.readAll())
            XCTAssertEqual(try repository.read().marks.count, 1)
            XCTAssertEqual(try repository.read().marks[0].id, capture.id)
            let invalid = PageCapture(
                version: 1, id: UUID(), kind: .article, sourceURL: "file:///private/test", title: "No",
                locator: ReadingLocator(kind: "article"), excerpt: "x", createdAt: 0)
            XCTAssertThrowsError(try store.save(invalid))
            XCTAssertEqual(try store.readAll().count, 1)
        }
    }
}

extension LibraryTests {
    func testBatchHandoffIndexesSourcesAndKeepsKindsSeparate() throws {
        try withStore { repository, _ in
            let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            try repository.update {
                $0.sources.append(LibrarySource(kind: .text, title: "Imported text", url: url))
            }
            let marks = try (0..<1000).map { index in
                WebMark(
                    version: 1, id: UUID(), videoID: try YouTubeVideoID("dQw4w9WgXcQ"), title: "Video",
                    capturedSeconds: Double(index), preRoll: 0, seconds: Double(index), createdAt: 1000)
            }
            let start = Date()
            try repository.receive(marks)
            let first = Date().timeIntervalSince(start)
            let repeatStart = Date()
            try repository.receive(marks)
            print("1000-mark handoff: first=\(first)s repeat=\(Date().timeIntervalSince(repeatStart))s")
            let state = try repository.read()
            XCTAssertEqual(state.marks.count, 1000)
            XCTAssertEqual(state.sources.count, 2)
            let video = try XCTUnwrap(state.sources.first { $0.kind == .youtube })
            XCTAssertTrue(state.marks.allSatisfy { $0.sourceID == video.id })
        }
    }
}
