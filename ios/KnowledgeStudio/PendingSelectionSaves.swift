import KnowledgeCore

/// Keep the original selected text available until its durable save finishes,
/// without turning rapid taps on that selection into duplicate highlights.
/// Separate new selections remain usable while an older save is in progress.
struct PendingSelectionSaves {
    private var locations: [ReadingLocator] = []
    mutating func begin(_ locator: ReadingLocator) -> Bool {
        guard !locations.contains(locator) else { return false }
        locations.append(locator)
        return true
    }
    mutating func finish(_ locator: ReadingLocator) {
        locations.removeAll { $0 == locator }
    }
}
