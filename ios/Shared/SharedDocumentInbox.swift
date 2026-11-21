import Foundation

/// The extension publishes a completed directory atomically. The app only removes it after import.
struct SharedDocumentInbox: Sendable {
    struct Entry: Codable, Identifiable, Sendable {
        let id: UUID
        let filename: String
    }

    let directory: URL
    static let extensions: Set<String> = ["pdf", "epub", "mp4", "m4v", "mov"]

    static func configured() throws -> Self {
        let container = try SharedProbeStore.configured().directory.deletingLastPathComponent()
        return Self(directory: container.appendingPathComponent("IncomingDocuments-v1", isDirectory: true))
    }

    func stage(_ temporary: URL, suggestedName: String?, fallbackExtension: String?) throws -> Entry {
        let fm = FileManager.default
        let suggested = suggestedName.map { URL(fileURLWithPath: $0).lastPathComponent }
        let suffixes = [suggested.map { URL(fileURLWithPath: $0).pathExtension }, temporary.pathExtension, fallbackExtension]
        guard let ext = suffixes.compactMap({ $0?.lowercased() }).first(where: Self.extensions.contains) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "请选择 PDF、EPUB 或受支持的视频。"])
        }
        let title = suggested.flatMap { $0.isEmpty ? nil : $0 } ?? temporary.lastPathComponent
        let originalSuffix = URL(fileURLWithPath: title).pathExtension
        let stem = originalSuffix.lowercased() == ext ? String(title.dropLast(ext.count + 1)) : title
        let safeName = String(stem.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        let entry = Entry(id: UUID(), filename: (safeName.isEmpty ? "资料" : safeName) + "." + ext)
        let temporaryFolder = directory.appendingPathComponent("." + entry.id.uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: temporaryFolder) }
        try fm.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        try fm.copyItem(at: temporary, to: temporaryFolder.appendingPathComponent(entry.filename))
        try JSONEncoder().encode(entry).write(to: temporaryFolder.appendingPathComponent("entry.json"), options: .atomic)
        try fm.moveItem(at: temporaryFolder, to: folder(entry.id))
        return entry
    }

    func entries() throws -> [Entry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles])
        let available: [(entry: Entry, created: Date)] = contents.compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent),
                let data = try? Data(contentsOf: url.appendingPathComponent("entry.json")),
                let entry = try? JSONDecoder().decode(Entry.self, from: data),
                entry.id == id, valid(entry.filename) else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (entry, created)
        }
        return available.sorted { $0.created < $1.created }.map { $0.entry }
    }

    func file(_ entry: Entry) throws -> URL {
        guard valid(entry.filename) else { throw CocoaError(.fileReadInvalidFileName) }
        let url = folder(entry.id).appendingPathComponent(entry.filename)
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        return url
    }

    func remove(_ entry: Entry) throws { try FileManager.default.removeItem(at: folder(entry.id)) }

    private func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func valid(_ name: String) -> Bool {
        !name.contains("/") && !name.contains("\0") && Self.extensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased())
    }
}
