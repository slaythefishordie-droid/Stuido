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

    enum StoreError: LocalizedError {
        case invalidGroupConfiguration
        case unavailableGroup(String)
        case mismatchedWriter

        var errorDescription: String? {
            switch self {
            case .invalidGroupConfiguration:
                "App Group 配置无效，需要一个明确的共享组标识。"
            case .unavailableGroup(let identifier):
                "无法访问共享组 \(identifier)。请记录 AltStore 重签结果及共享权限。"
            case .mismatchedWriter:
                "共享验证记录的来源不匹配。"
            }
        }
    }

    static func configured() throws -> SharedProbeStore {
        let group = try groupIdentifier(in: Bundle.main.infoDictionary ?? [:])
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw StoreError.unavailableGroup(group)
        }
        return SharedProbeStore(directory: container.appendingPathComponent("SharingProbe-v1"))
    }

    static func groupIdentifier(in info: [String: Any]) throws -> String {
        // A present AltStore value must be valid. Falling back could select a different container.
        if let provisioned = info["ALTAppGroups"] {
            guard let groups = provisioned as? [String],
                  groups.count == 1,
                  let group = groups.first,
                  !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StoreError.invalidGroupConfiguration
            }
            return group
        }
        guard let group = info["SharedAppGroup"] as? String,
              !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.invalidGroupConfiguration
        }
        return group
    }

    func write(from writer: Writer) throws -> Record {
        let record = Record(id: UUID(), writer: writer, createdAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: file(for: writer), options: .atomic)
        return record
    }

    func read(from writer: Writer) throws -> Record? {
        let url = file(for: writer)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.writer == writer else {
            throw StoreError.mismatchedWriter
        }
        return record
    }

    private func file(for writer: Writer) -> URL {
        directory.appendingPathComponent(writer.rawValue + ".json")
    }
}
