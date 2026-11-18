import Foundation

/// Milestone 1 diagnostics. Each process writes its own file to avoid lost updates.
struct SharedProbeStore {
    enum Writer: String, Codable { case app, safari }
    struct Record: Codable {
        let id: UUID
        let writer: Writer
        let createdAt: Date
    }

    let directory: URL

    static func configured() throws -> SharedProbeStore {
        // AltStore records the provisioned group IDs after re-signing.
        let provisioned = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]
        let configured = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String
        let group = provisioned.map { $0.count == 1 ? $0.first : nil } ?? configured
        guard let group,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else {
            throw NSError(domain: "SharedProbe", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法访问 App Group。请记录 AltStore 重签结果及共享权限。"
            ])
        }
        return SharedProbeStore(directory: container.appendingPathComponent("SharingProbe-v1"))
    }

    func write(from writer: Writer) throws -> Record {
        let record = Record(id: UUID(), writer: writer, createdAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: file(for: writer), options: .atomic)
        return record
    }

    func read(from writer: Writer) throws -> Record? {
        let url = file(for: writer)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard record.writer == writer else {
            throw NSError(domain: "SharedProbe", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "共享验证记录的来源不匹配。"
            ])
        }
        return record
    }

    private func file(for writer: Writer) -> URL {
        directory.appendingPathComponent(writer.rawValue + ".json")
    }
}
