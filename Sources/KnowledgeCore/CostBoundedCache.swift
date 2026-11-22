/// A small deterministic LRU for decoded resources. Costs are supplied by the
/// renderer (bytesPerRow × height), not compressed file sizes. Values larger than
/// the entire budget are returned by the caller without being retained here.
public struct CostBoundedCache<Key: Hashable, Value> {
    private struct Entry { let value: Value; let cost: Int; var access: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    public private(set) var totalCost = 0
    public var limit: Int { didSet { trim() } }
    public var countLimit = 128 { didSet { trim() } }
    public init(limit: Int) { self.limit = max(0, limit) }
    public mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1; entry.access = clock; entries[key] = entry
        return entry.value
    }
    public mutating func insert(_ value: Value, for key: Key, cost: Int) {
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
        guard cost >= 0, cost <= max(0, limit) else { return }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, access: clock)
        totalCost += cost
        trim()
    }
    public mutating func removeAll() { entries.removeAll(); totalCost = 0 }
    private mutating func trim() {
        while totalCost > max(0, limit) || entries.count > max(0, countLimit), let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
    }
}
