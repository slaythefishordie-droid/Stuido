import Foundation
import XCTest
#if canImport(SQLite3)
import SQLite3
#else
import GRDBSQLite
#endif
@testable import KnowledgeCore

final class RepositoryCacheTests: XCTestCase {
    private func withRepositories(_ body: (LibraryRepository, LibraryRepository, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        try body(LibraryRepository(url: url), LibraryRepository(url: url), url)
    }

    func testExternalCommitRestoreAndValueIsolation() throws {
        try withRepositories { first, second, url in
            let source = LibrarySource(kind: .pdf, title: "Original")
            try first.update { $0.sources.append(source) }
            XCTAssertEqual(try second.read().sources, [source])
            var copy = try first.read()
            copy.sources[0].title = "Uncommitted"
            XCTAssertEqual(try first.read().sources[0].title, "Original")
            try second.update { $0.sources[0].title = "External" }
            XCTAssertEqual(try first.read().sources[0].title, "External")
            try first.update { $0.sources[0].lastLocation = ReadingLocator(kind: "pdf", page: 9) }
            XCTAssertEqual(try second.read().sources[0].lastLocation?.page, 9)
            XCTAssertEqual(try second.read().sources[0].title, "External")
            try second.restore(copy)
            XCTAssertEqual(try first.read(), copy)
            XCTAssertEqual(try LibraryRepository(url: url).read(), copy)
        }
    }

    func testFailedMutationAndInvalidReferenceNeverPublish() throws {
        try withRepositories { first, second, _ in
            let source = LibrarySource(kind: .pdf, title: "Book")
            try first.update { $0.sources.append(source) }
            let baseline = try first.read()
            XCTAssertThrowsError(try first.update {
                $0.sources.removeAll()
                throw LibraryError.invalid("Injected failure")
            })
            XCTAssertThrowsError(try first.update {
                $0.marks.append(LibraryMark(sourceID: UUID(), locator: ReadingLocator(kind: "pdf", page: 1)))
            })
            XCTAssertEqual(try first.read(), baseline)
            XCTAssertEqual(try second.read(), baseline)
            try second.update { $0.sources[0].title = "Still writable" }
            XCTAssertEqual(try first.read().sources[0].title, "Still writable")
        }
    }

    func testSQLWriteFailureAndExternalCorruptionCannotHideBehindCache() throws {
        try withRepositories { first, _, url in
            let source = LibrarySource(kind: .pdf, title: "Original")
            try first.update { $0.sources.append(source) }
            // Use the system SQLite API to simulate an independent writer. The
            // native test host must not link a second copy of GRDB's Swift types.
            var connection: OpaquePointer?
            XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
            guard let connection else { throw LibraryError.invalid("Test connection failed") }
            defer { sqlite3_close(connection) }
            func execute(_ sql: String) throws {
                guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
                    throw LibraryError.invalid(String(cString: sqlite3_errmsg(connection)))
                }
            }
            try execute("CREATE TRIGGER reject_edit BEFORE UPDATE ON library_state BEGIN SELECT RAISE(ABORT, 'injected'); END")
            XCTAssertThrowsError(try first.update { $0.sources[0].title = "Must roll back" })
            XCTAssertEqual(try first.read().sources, [source])
            try execute("DROP TRIGGER reject_edit")
            try execute("UPDATE library_state SET payload = X'696e76616c6964' WHERE id = 1")
            XCTAssertThrowsError(try first.read())
            XCTAssertThrowsError(try first.update { $0.sources.removeAll() })
        }
    }

    func testConcurrentConnectionsNeverLoseSuccessfulUpdates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let first = try LibraryRepository(url: url)
        let second = try LibraryRepository(url: url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<80 {
                let repository = index.isMultiple(of: 2) ? first : second
                group.addTask {
                    try repository.update { $0.sources.append(LibrarySource(kind: .pdf, title: "Book \(index)")) }
                    _ = try repository.read()
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(try first.read().sources.count, 80)
        XCTAssertEqual(try first.read(), try second.read())
        XCTAssertEqual(try first.read(), try LibraryRepository(url: url).read())
    }
}
