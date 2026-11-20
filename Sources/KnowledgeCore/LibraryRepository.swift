import Foundation
import GRDB

/// One versioned aggregate per SQLite transaction keeps import/restore atomic.
/// Entity IDs and references are validated before every commit; no implicit cascade.
public final class LibraryRepository {
    private let database: DatabaseQueue
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("library-v1") { db in
            try db.execute(
                sql:
                    "CREATE TABLE library_state (id INTEGER PRIMARY KEY CHECK(id = 1), payload BLOB NOT NULL)"
            )
            try db.execute(
                sql: "INSERT INTO library_state (id, payload) VALUES (1, ?)",
                arguments: [try JSONEncoder().encode(LibraryState())])
        }
        try migrator.migrate(database)
        _ = try read()
    }
    public func read() throws -> LibraryState {
        try database.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM library_state WHERE id = 1")
            else { throw LibraryError.invalid("知识库记录缺失") }
            let state = try JSONDecoder().decode(LibraryState.self, from: data)
            try state.validate()
            return state
        }
    }
    public func update(_ mutate: (inout LibraryState) throws -> Void) throws {
        try database.write { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM library_state WHERE id = 1")
            else { throw LibraryError.invalid("知识库记录缺失") }
            var state = try JSONDecoder().decode(LibraryState.self, from: data)
            try state.validate()
            let previous = state
            try mutate(&state)
            try state.validate()
            guard state != previous else { return }
            try db.execute(
                sql: "UPDATE library_state SET payload = ? WHERE id = 1",
                arguments: [try JSONEncoder().encode(state)])
        }
    }
    public func restore(_ snapshot: LibraryState) throws {
        try snapshot.validate()
        try update { $0 = snapshot }
    }

    public func receive(_ webMarks: [WebMark]) throws {
        try update { state in
            var markIndices = Dictionary(
                uniqueKeysWithValues: state.marks.enumerated().map { ($0.element.id, $0.offset) })
            var sourceByURL: [String: LibrarySource] = [:]
            for source in state.sources where source.kind == .youtube {
                if let url = source.url, sourceByURL[url] == nil { sourceByURL[url] = source }
            }
            var received = Set(state.receivedWebIDs)
            for web in webMarks {
                try web.validate()
                if let index = markIndices[web.id] {
                    if let revision = web.updatedAt, revision > (state.marks[index].externalUpdatedAt ?? 0) {
                        state.marks[index].note = web.note ?? ""
                        state.marks[index].deletedAt = web.deletedAt.map {
                            Date(timeIntervalSince1970: $0 / 1000)
                        }
                        state.marks[index].externalUpdatedAt = revision
                    }
                    continue
                }
                guard received.insert(web.id).inserted else { continue }
                state.receivedWebIDs.append(web.id)
                let url = web.sourceURL.absoluteString
                let source: LibrarySource
                if let existing = sourceByURL[url] {
                    source = existing
                } else {
                    source = LibrarySource(kind: .youtube, title: web.title, url: url)
                    state.sources.append(source)
                    sourceByURL[url] = source
                }
                var locator = ReadingLocator(kind: "video", seconds: web.seconds)
                locator.nativeJSON = String(data: try JSONEncoder().encode(web), encoding: .utf8)
                var mark = LibraryMark(
                    id: web.id, sourceID: source.id, locator: locator,
                    createdAt: Date(timeIntervalSince1970: web.createdAt / 1000))
                mark.note = web.note ?? ""
                mark.externalUpdatedAt = web.updatedAt
                mark.deletedAt = web.deletedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                markIndices[mark.id] = state.marks.count
                state.marks.append(mark)
            }
        }
    }

    @MainActor
    public func migratePrototype(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path),
            !(try read().migrations.contains("prototype-v1"))
        else { return }
        let old = try MarkStore(fileURL: url).snapshot
        try update { state in
            for video in old.sources {
                guard !state.sources.contains(where: { $0.id == video.id }) else { continue }
                var source = LibrarySource(
                    id: video.id, kind: .youtube, title: video.videoID.rawValue,
                    url: video.videoID.watchURL.absoluteString)
                source.createdAt = video.createdAt
                source.updatedAt = video.createdAt
                state.sources.append(source)
            }
            for mark in old.marks where !state.marks.contains(where: { $0.id == mark.id }) {
                state.marks.append(
                    LibraryMark(
                        id: mark.id, sourceID: mark.sourceID,
                        locator: ReadingLocator(kind: "video", seconds: mark.seconds),
                        createdAt: mark.createdAt))
            }
            state.migrations.append("prototype-v1")
        }
    }
}
