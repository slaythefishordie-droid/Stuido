import Foundation
import GRDB

/// One versioned aggregate per SQLite transaction keeps import/restore atomic.
/// Entity IDs and references are validated before every commit; no implicit cascade.
public final class LibraryRepository: Sendable {
    private let database: DatabaseQueue
    // Access is confined to DatabaseQueue's serialized connection, including publication
    // after COMMIT. No mutable state escapes the queue; LibraryState has value semantics.
    private final class SnapshotCache: @unchecked Sendable {
        var version: Int64?
        var state: LibraryState?
    }
    private let cache = SnapshotCache()

    private func load(_ db: Database, version: Int64) throws -> LibraryState {
        if cache.version == version, let state = cache.state { return state }
        guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM library_state WHERE id = 1")
        else { throw LibraryError.invalid("知识库记录缺失") }
        let state = try JSONDecoder().decode(LibraryState.self, from: data)
        try state.validate()
        cache.state = state
        cache.version = version
        return state
    }
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        // Another window/process may briefly own SQLite's write lock. Give its
        // transaction time to finish instead of failing a valid concurrent edit.
        configuration.busyMode = .timeout(5)
        database = try DatabaseQueue(path: url.path, configuration: configuration)
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
            // SQLite changes this value when another connection commits. It is not a
            // wall clock or file timestamp, so same-size and rapid updates are visible.
            let version = try Int64.fetchOne(db, sql: "PRAGMA data_version")!
            return try load(db, version: version)
        }
    }
    public func update(_ mutate: (inout LibraryState) throws -> Void) throws {
        _ = try updateAndRead(mutate)
    }

    /// Returns and caches a snapshot only after SQLite successfully commits.
    public func updateAndRead(_ mutate: (inout LibraryState) throws -> Void) throws -> LibraryState {
        try database.writeWithoutTransaction { db in
            var committed: LibraryState!
            var version: Int64 = 0
            try db.inTransaction(.immediate) {
                // Acquire the writer lock BEFORE checking the external revision. A
                // second repository cannot change the snapshot between load and save.
                version = try Int64.fetchOne(db, sql: "PRAGMA data_version")!
                let previous = try load(db, version: version)
                var next = previous
                try mutate(&next)
                if next != previous {
                    try next.validate()
                    try db.execute(
                        sql: "UPDATE library_state SET payload = ? WHERE id = 1",
                        arguments: [try JSONEncoder().encode(next)])
                }
                committed = next
                return .commit
            }
            // Use the version observed under the lock. Reading a NEW version after
            // COMMIT could incorrectly tag this snapshot with a later external write.
            cache.state = committed
            cache.version = version
            return committed
        }
    }
    public func restore(_ snapshot: LibraryState) throws {
        try snapshot.validate()
        try update { $0 = snapshot }
    }

    public func receive(_ webMarks: [WebMark]) throws {
        guard !webMarks.isEmpty else { return }
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
