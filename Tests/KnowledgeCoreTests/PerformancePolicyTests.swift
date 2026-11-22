import Foundation
import XCTest
@testable import KnowledgeCore

final class PerformancePolicyTests: XCTestCase {
    func testMemoryBudgetAndLRUEviction() {
        var cache = CostBoundedCache<String, Int>(limit: 10)
        cache.insert(1, for: "first", cost: 4)
        cache.insert(2, for: "second", cost: 4)
        XCTAssertEqual(cache.value(for: "first"), 1)
        cache.insert(3, for: "third", cost: 4)
        XCTAssertNil(cache.value(for: "second"))
        XCTAssertEqual(cache.totalCost, 8)
        cache.limit = 4
        XCTAssertNil(cache.value(for: "first"))
        XCTAssertEqual(cache.value(for: "third"), 3)
        cache.insert(99, for: "too-big", cost: 5)
        XCTAssertNil(cache.value(for: "too-big"))
        cache.countLimit = 1
        cache.insert(4, for: "small", cost: 0)
        XCTAssertNil(cache.value(for: "third"))
        cache.removeAll()
        XCTAssertEqual(cache.totalCost, 0)
    }
    func testBudgetsRespondToPowerThermalAndMemoryPressure() {
        let normal = PerformanceBudget(lowPower: false, thermal: .nominal)
        let low = PerformanceBudget(lowPower: true, thermal: .nominal)
        let hot = PerformanceBudget(lowPower: false, thermal: .serious)
        let critical = PerformanceBudget(lowPower: false, thermal: .critical, memoryPressure: true)
        XCTAssertEqual(normal.artworkConcurrency, 2)
        XCTAssertEqual(low.artworkConcurrency, 1)
        XCTAssertEqual(low, hot)
        XCTAssertLessThan(critical.artworkBytes, low.artworkBytes)
        XCTAssertGreaterThan(critical.customCoverBytes, 0)
    }
    func testIdleWakeupsAndUserDeadlines() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(PerformanceBudget.nextWakeDelay(now: now, checkpointIn: 30, deadlines: []), 30)
        XCTAssertEqual(PerformanceBudget.nextWakeDelay(now: now, checkpointIn: 25,
            deadlines: [now.addingTimeInterval(3), now.addingTimeInterval(90)]), 3)
        XCTAssertEqual(PerformanceBudget.nextWakeDelay(now: now, checkpointIn: 0, deadlines: []), 1)
    }
    func testMarkIndexPreservesOrderDeletionAndSnapshotIsolation() {
        let source = LibrarySource(kind: .pdf, title: "Book")
        var first = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 2))
        let second = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))
        first.deletedAt = .now
        var marks = [first, second]
        let index = LibraryMarkIndex(marks)
        marks.removeAll()
        XCTAssertEqual(index.marks(for: source.id), [second])
        XCTAssertEqual(index.marks(for: source.id, includingDeleted: true), [first, second])
        XCTAssertTrue(index.marks(for: UUID()).isEmpty)
    }
}
