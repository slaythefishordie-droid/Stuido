import Foundation
import KnowledgeCore
@preconcurrency import ReadiumZIPFoundation

struct BackupManifest: Codable, Sendable {
    var version = 1
    var createdAt = Date()
    var files: [String: String]
    var missingAssets: [String]
}

struct ValidatedBackup: Sendable {
    let directory: URL
    let state: LibraryState
    let manifest: BackupManifest
}

@MainActor
enum BackupService {
    static func export(model: StudioModel) async throws -> URL {
        guard let repository = model.repository else { throw LibraryError.invalid("知识库不可用") }
        let snapshot = try repository.read()
        let root = model.root
        return try await Task.detached(priority: .userInitiated) {
            try await makeArchive(snapshot: snapshot, root: root)
        }.value
    }
    nonisolated private static func makeArchive(snapshot: LibraryState, root: URL) async throws -> URL {
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let library = stage.appendingPathComponent("library.json")
        try JSONEncoder().encode(snapshot).write(to: library, options: .atomic)
        var files = ["library.json": try StudioModel.hash(library)]
        var missing: [String] = []
        for source in snapshot.sources {
            guard let hash = source.assetHash, let ext = source.assetExtension else { continue }
            let asset = root.appendingPathComponent("assets/\(hash).\(ext)")
            let path = "assets/" + asset.lastPathComponent
            if files[path] != nil { continue }
            if !FileManager.default.fileExists(atPath: asset.path) {
                missing.append(path)
                continue
            }
            guard try StudioModel.hash(asset) == source.assetHash else {
                throw LibraryError.invalid("原始资料摘要不符，停止备份：\(source.title)")
            }
            let copy = stage.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: asset, to: copy)
            files[path] = try StudioModel.hash(copy)
        }
        try JSONEncoder().encode(BackupManifest(files: files, missingAssets: missing)).write(
            to: stage.appendingPathComponent("manifest.json"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KnowledgeStudio-\(UUID().uuidString).zip")
        let archive = try await Archive(url: output, accessMode: .create)
        for path in ["manifest.json"] + files.keys.sorted() {
            try await archive.addEntry(with: path, relativeTo: stage, compressionMethod: .deflate)
        }
        return output
    }

    typealias Validated = ValidatedBackup
    static func validate(_ url: URL) async throws -> Validated {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) { try await validateArchive(url) }.value
    }
    nonisolated private static func validateArchive(_ url: URL) async throws -> Validated {
        let stage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        do {
            let archive = try await Archive(url: url, accessMode: .read)
            let entries = try await archive.entries()
            guard entries.count <= 20_002 else { throw LibraryError.invalid("备份文件过多") }
            var paths: Set<String> = []
            var total: UInt64 = 0
            for entry in entries {
                let path = entry.path
                guard paths.insert(path).inserted, entry.type == .file,
                    path == "manifest.json" || path == "library.json"
                        || path.range(
                            of: "^assets/[a-f0-9]{64}\\.(pdf|epub|mp4|mov|m4v)$", options: .regularExpression)
                            != nil,
                    entry.uncompressedSize <= 4_294_967_296
                else { throw LibraryError.invalid("备份包含非法路径、链接或过大文件") }
                total += entry.uncompressedSize
                guard total <= 8_589_934_592,
                    path.hasPrefix("assets/") || entry.uncompressedSize <= 67_108_864
                else { throw LibraryError.invalid("备份解压大小超过限制") }
                let sink = try BoundedBackupSink(
                    url: stage.appendingPathComponent(path), limit: entry.uncompressedSize)
                let crc: UInt32
                do {
                    crc = try await archive.extract(entry) { chunk in try await sink.write(chunk) }
                    try await sink.finish()
                } catch {
                    await sink.cancel()
                    throw error
                }
                guard crc == entry.checksum else { throw LibraryError.invalid("备份 ZIP 校验失败") }
            }
            let manifest = try JSONDecoder().decode(
                BackupManifest.self, from: Data(contentsOf: stage.appendingPathComponent("manifest.json")))
            guard manifest.version == 1, paths == Set(manifest.files.keys).union(["manifest.json"]),
                manifest.files["library.json"] != nil
            else { throw LibraryError.invalid("备份清单版本或文件集合不符") }
            for (path, digest) in manifest.files {
                guard try StudioModel.hash(stage.appendingPathComponent(path)) == digest else {
                    throw LibraryError.invalid("备份摘要校验失败：\(path)")
                }
            }
            let state = try JSONDecoder().decode(
                LibraryState.self, from: Data(contentsOf: stage.appendingPathComponent("library.json")))
            try state.validate()
            for source in state.sources {
                guard let hash = source.assetHash, let ext = source.assetExtension else { continue }
                let path = "assets/\(hash).\(ext)"
                guard manifest.files[path] == hash || manifest.missingAssets.contains(path) else {
                    throw LibraryError.invalid("备份缺少资料或资料摘要不符")
                }
            }
            return Validated(directory: stage, state: state, manifest: manifest)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }
    static func restore(_ validated: Validated, model: StudioModel) async throws {
        guard let repository = model.repository else { throw LibraryError.invalid("知识库不可用") }
        let root = model.root
        try await Task.detached(priority: .userInitiated) { try prepareRestore(validated, root: root) }.value
        // Recoverable pre-restore snapshot, written before changing the live state.
        let previous = try JSONEncoder().encode(repository.read())
        try previous.write(
            to: model.root.appendingPathComponent("before-restore-\(UUID().uuidString).json"),
            options: .atomic)
        try repository.restore(validated.state)
        model.refresh()
    }
    nonisolated private static func prepareRestore(_ validated: Validated, root: URL) throws {
        try validated.state.validate()
        // Copy immutable content-addressed assets first. Failed commits leave harmless orphan files.
        // Existing assets and the live database are never removed before a successful transaction.
        for (path, hash) in validated.manifest.files where path.hasPrefix("assets/") {
            let from = validated.directory.appendingPathComponent(path)
            let to = root.appendingPathComponent(path)
            guard try StudioModel.hash(from) == hash else { throw LibraryError.invalid("恢复文件在确认期间已改变") }
            if FileManager.default.fileExists(atPath: to.path) {
                guard try StudioModel.hash(to) == hash else { throw LibraryError.invalid("本地资料损坏，停止覆盖") }
            } else {
                try FileManager.default.createDirectory(
                    at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
    }

}

/// Enforce the limit on bytes actually inflated, not only untrusted ZIP metadata.
private actor BoundedBackupSink {
    private let handle: FileHandle
    private let limit: UInt64
    private var count: UInt64 = 0
    init(url: URL, limit: UInt64) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw LibraryError.invalid("无法创建恢复临时文件")
        }
        handle = try FileHandle(forWritingTo: url)
        self.limit = limit
    }
    func write(_ data: Data) throws {
        guard UInt64(data.count) <= limit - count else { throw LibraryError.invalid("实际解压大小超过声明，已停止恢复") }
        try handle.write(contentsOf: data)
        count += UInt64(data.count)
    }
    func finish() throws {
        try handle.close()
        guard count == limit else { throw LibraryError.invalid("解压文件大小不符") }
    }
    func cancel() { try? handle.close() }
}
