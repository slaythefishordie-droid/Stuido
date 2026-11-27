import Foundation

/// Exact UI payload-size estimates, reused by collection; never used for persistence
/// validation or deletion decisions. The retained snapshot shares copy-on-write storage.
public struct LibraryContentSizeCache: Sendable {
    private var previous: LibraryState?
    private var values: [String: Int64] = [:]
    public private(set) var encodedCollectionCount = 0
    public init() {}

    public mutating func measure(_ state: LibraryState) throws -> [String: Int64] {
        var next = values
        var count = 0
        let encoder = JSONEncoder()
        func update<T: Encodable & Equatable>(_ key: String, _ items: [T], _ old: [T]?, active: (T) -> Bool) throws {
            guard items != old else { return }
            try Task.checkCancellation()
            next[key] = Int64(max(0, try encoder.encode(items.filter(active)).count - 2))
            count += 1
        }
        try update("资料", state.sources, previous?.sources) { $0.deletedAt == nil }
        try update("标记", state.marks, previous?.marks) { $0.deletedAt == nil }
        try update("卡片", state.cards, previous?.cards) { $0.deletedAt == nil }
        try update("项目", state.projects, previous?.projects) { $0.deletedAt == nil }
        try update("关系", state.relations, previous?.relations) { $0.deletedAt == nil }
        try update("复习记录", state.reviewRecords, previous?.reviewRecords) { $0.deletedAt == nil }
        previous = state
        values = next
        encodedCollectionCount = count
        return next
    }
}
