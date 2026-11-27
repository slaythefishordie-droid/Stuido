import Foundation
import XCTest
#if canImport(SQLite3)
import SQLite3
#else
import GRDBSQLite
#endif
@testable import KnowledgeCore

final class RepositoryPersistenceTests: XCTestCase {
    private func withStore(_ body: (LibraryRepository, URL, OpaquePointer) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let repository = try LibraryRepository(url: url)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        let db = try XCTUnwrap(connection)
        defer { sqlite3_close(db) }
        try body(repository, url, db)
    }

    private func execute(_ sql: String, on db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw LibraryError.invalid(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func payload(_ db: OpaquePointer) throws -> Data {
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT payload FROM library_state WHERE id=1", -1, &statement, nil), SQLITE_OK)
        let query = try XCTUnwrap(statement)
        defer { sqlite3_finalize(query) }
        XCTAssertEqual(sqlite3_step(query), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_type(query, 0), SQLITE_BLOB)
        return Data(bytes: try XCTUnwrap(sqlite3_column_blob(query, 0)), count: Int(sqlite3_column_bytes(query, 0)))
    }

    private func legacyWrite(_ state: LibraryState, on db: OpaquePointer) throws {
        // Exactly the previous writer's full Codable BLOB, through an independent connection.
        let data = try JSONEncoder().encode(state)
        let hex = data.map { String(format: "%02x", $0) }.joined()
        try execute("UPDATE library_state SET payload = X'\(hex)' WHERE id=1", on: db)
    }

    func testEveryCollectionAndOptionalRemovalRoundTripsWithLegacyWriter() throws {
        try withStore { repository, url, db in
            var original = LibraryState()
            var source = LibrarySource(kind: .pdf, title: "书 \\\" / 🐟\n")
            source.coverImage = Data([0, 1, 254, 255])
            source.lastLocation = ReadingLocator(kind: "pdf", page: 1)
            source.pdfPageInk = [PDFPageInk(fingerprint: String(repeating: "a", count: 64), page: 1, drawing: Data([2, 3]))]
            original.sources = [source]
            let mark = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1), excerpt: "正文")
            original.marks = [mark]
            original.cards = CardKind.allCases.map { kind in
                var card = LibraryCard(type: kind, content: [LibraryCard.fields(for: kind)[0]: "value \(kind)"])
                let ref = CardReference(sourceID: source.id, locator: mark.locator)
                card.sourceRefs = [ref]; card.markIDs = [mark.id]
                card.provenance = [LibraryCard.fields(for: kind)[0]: FieldOrigin(kind: "original", sourceRefIDs: [ref.id])]
                return card
            }
            original.cards[0].schedule = try ReviewSchedule(now: Date(timeIntervalSince1970: 1_700_000_000))
            original.relations = [LibraryRelation(from: original.cards[0].id, to: original.cards[1].id, kind: "related")]
            var project = LibraryProject(title: "项目")
            project.sourceIDs = [source.id]; project.cardIDs = original.cards.map(\.id)
            project.relationIDs = original.relations.map(\.id)
            project.sourceNotes = [source.id.uuidString: "保留笔记"]
            project.board = ProjectBoard()
            project.board?.nodes = [BoardNode(kind: .source, text: "书", targetID: source.id)]
            original.projects = [project]
            original.pending = [PendingImport(packageID: "p", title: "导入", json: "{\"text\":\"保留\"}")]
            original.importedPackages = ["old": "hash"]
            original.migrations = ["prototype-v1"]
            original.receivedWebIDs = [UUID()]
            original.reviewRecords = [LibraryReviewRecord(cardID: original.cards[0].id, rating: 3,
                reviewedAt: .now, elapsedMilliseconds: 123, schedulerVersion: "test")]
            try original.validate()
            try legacyWrite(original, on: db)
            XCTAssertEqual(try repository.read(), original)

            let changes: [(inout LibraryState) -> Void] = [
                { $0.sources[0].lastLocation = nil; $0.sources[0].coverImage = nil; $0.sources[0].pdfPageInk = [] },
                { $0.marks[0].note = "Note \u{0} \"quoted\" \\ / 中文"; $0.marks[0].deletedAt = .now },
                { $0.cards[0].note = "编辑"; $0.cards[0].schedule = nil },
                { $0.projects[0].board = nil; $0.projects[0].sourceNotes = [:] },
                { $0.relations[0].note = "关联" },
                { $0.pending[0].json = "[]" },
                { $0.importedPackages["new"] = "next" },
                { $0.migrations.append("second") },
                { $0.receivedWebIDs.append(UUID()) },
                { $0.reviewRecords[0].schedulerAfter = Data([255, 0, 128]); $0.reviewRecords[0].deletedAt = .now },
            ]
            var expected = original
            let originalKeys = Set(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]).keys)
            for change in changes {
                change(&expected)
                let next = expected
                try repository.update { $0 = next }
                let data = try payload(db)
                XCTAssertEqual(try JSONDecoder().decode(LibraryState.self, from: data), expected)
                XCTAssertEqual(Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys), originalKeys)
                XCTAssertEqual(try LibraryRepository(url: url).read(), expected)
            }
            // New -> old full writer -> existing cached connection -> new partial writer.
            expected.sources[0].title = "Legacy edit"
            try legacyWrite(expected, on: db)
            expected.cards[1].note = "New edit"
            try repository.update { $0.cards[1].note = "New edit" }
            XCTAssertEqual(try JSONDecoder().decode(LibraryState.self, from: payload(db)), expected)
            try repository.restore(original)
            XCTAssertEqual(try LibraryRepository(url: url).read(), original)
            try repository.restore(LibraryState())
            XCTAssertEqual(try LibraryRepository(url: url).read(), LibraryState())
        }
    }

    func testAppendReorderShrinkAndBulkReplacementPreserveArrayOrder() throws {
        try withStore { repository, url, db in
            var expected = LibraryState()
            for batchSize in [1, 2, 16, 17, 64] {
                expected.sources += (0..<batchSize).map { LibrarySource(kind: .pdf, title: "Book \($0)") }
                let next = expected
                try repository.update { $0 = next }
                XCTAssertEqual(try JSONDecoder().decode(LibraryState.self, from: payload(db)), expected)
            }
            expected.sources.swapAt(0, 2)
            var next = expected
            try repository.update { $0 = next }
            XCTAssertEqual(try LibraryRepository(url: url).read(), expected)
            expected.sources.reverse()
            next = expected
            try repository.update { $0 = next }
            XCTAssertEqual(try LibraryRepository(url: url).read(), expected)
            expected.sources.removeSubrange(3..<expected.sources.count)
            next = expected
            try repository.update { $0 = next }
            XCTAssertEqual(try LibraryRepository(url: url).read(), expected)
            // Several collections share the same bounded patch budget.
            expected.marks = (0..<12).map { LibraryMark(sourceID: expected.sources[0].id,
                locator: ReadingLocator(kind: "pdf", page: $0 + 1)) }
            expected.cards = (0..<12).map { LibraryCard(type: .word, content: ["word": "Word \($0)"]) }
            next = expected
            try repository.update { $0 = next }
            XCTAssertEqual(try JSONDecoder().decode(LibraryState.self, from: payload(db)), expected)
        }
    }

    func testNoOpAndEncodingFailureLeaveOriginalPayloadUntouched() throws {
        try withStore { repository, _, db in
            try repository.update { $0.sources.append(LibrarySource(kind: .pdf, title: "Book")) }
            let before = try repository.read()
            let bytes = try payload(db)
            try execute("CREATE TRIGGER reject_write BEFORE UPDATE ON library_state BEGIN SELECT RAISE(ABORT, 'unexpected write'); END", on: db)
            try repository.update { $0.sources[0].title = "Book" }
            XCTAssertEqual(try payload(db), bytes)
            try execute("DROP TRIGGER reject_write", on: db)
            XCTAssertThrowsError(try repository.update {
                $0.sources[0].createdAt = Date(timeIntervalSinceReferenceDate: .infinity)
                $0.migrations.append("must not persist")
            })
            XCTAssertEqual(try repository.read(), before)
            XCTAssertEqual(try payload(db), bytes)
        }
    }

    func testCommitFailureDoesNotPublishAndRetryPersists() throws {
        try withStore { repository, url, db in
            try repository.update { $0.sources.append(LibrarySource(kind: .pdf, title: "Original")) }
            let before = try repository.read()
            let bytes = try payload(db)
            // The UPDATE succeeds; the deferred constraint fails only at COMMIT.
            try execute("CREATE TABLE parent (id INTEGER PRIMARY KEY)", on: db)
            try execute("CREATE TABLE child (parent_id INTEGER REFERENCES parent(id) DEFERRABLE INITIALLY DEFERRED)", on: db)
            try execute("CREATE TRIGGER reject_commit AFTER UPDATE ON library_state BEGIN INSERT INTO child VALUES(42); END", on: db)
            XCTAssertThrowsError(try repository.update { $0.sources[0].title = "Candidate" })
            XCTAssertEqual(try repository.read(), before)
            XCTAssertEqual(try payload(db), bytes)
            try execute("DROP TRIGGER reject_commit", on: db)
            try repository.update { $0.sources[0].title = "Candidate" }
            XCTAssertEqual(try LibraryRepository(url: url).read().sources[0].title, "Candidate")
        }
    }
}
