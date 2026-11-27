import Foundation

extension LibraryState {
    // Shared with synthesized Codable: adding a persisted field requires handling
    // its case here, so partial writes cannot silently omit it.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, sources, marks, cards, projects, relations, pending
        case importedPackages, migrations, receivedWebIDs, reviewRecords
    }

    /// JSON path/value pairs for SQLite json_set. Every value still uses the same
    /// Foundation Codable representation as a complete v1 snapshot.
    func encodedChanges(from previous: LibraryState) throws -> [String] {
        let encoder = JSONEncoder()
        var arguments: [String] = []
        func append<T: Encodable & Equatable>(_ key: CodingKeys, _ value: T, _ old: T) throws {
            guard value != old else { return }
            arguments.append("$." + key.rawValue)
            arguments.append(String(decoding: try encoder.encode(value), as: UTF8.self))
        }
        // Bound SQL arguments and temporary encodings. Small edits/appends use
        // array positions; bulk replacement, shrink and large reorder encode the
        // collection once. json_set evaluates append positions left to right.
        var elementChanges = 0
        let elementLimit = 16
        func appendArray<T: Encodable & Equatable>(_ key: CodingKeys, _ value: [T], _ old: [T]) throws {
            guard value != old else { return }
            if value.count >= old.count, elementChanges < elementLimit {
                var offsets: [Int] = []
                for offset in value.indices where offset >= old.count || value[offset] != old[offset] {
                    offsets.append(offset)
                    if offsets.count > elementLimit - elementChanges { break }
                }
                if offsets.count <= elementLimit - elementChanges {
                    for offset in offsets {
                        arguments.append("$." + key.rawValue + "[\(offset)]")
                        arguments.append(String(decoding: try encoder.encode(value[offset]), as: UTF8.self))
                    }
                    elementChanges += offsets.count
                    return
                }
            }
            try append(key, value, old)
        }
        for key in CodingKeys.allCases {
            switch key {
            case .version: try append(key, version, previous.version)
            case .sources: try appendArray(key, sources, previous.sources)
            case .marks: try appendArray(key, marks, previous.marks)
            case .cards: try appendArray(key, cards, previous.cards)
            case .projects: try appendArray(key, projects, previous.projects)
            case .relations: try appendArray(key, relations, previous.relations)
            case .pending: try appendArray(key, pending, previous.pending)
            case .importedPackages: try append(key, importedPackages, previous.importedPackages)
            case .migrations: try appendArray(key, migrations, previous.migrations)
            case .receivedWebIDs: try appendArray(key, receivedWebIDs, previous.receivedWebIDs)
            case .reviewRecords: try appendArray(key, reviewRecords, previous.reviewRecords)
            }
        }
        return arguments
    }
}
