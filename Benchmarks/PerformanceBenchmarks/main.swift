import Foundation
import KnowledgeCore

// Isolated synthetic data only. Never opens the application's library or App Group.
func identifier(_ family: Int, _ value: Int) -> UUID {
    UUID(uuidString: String(format: "%08x-0000-0000-0000-%012x", family, value))!
}
func fixture(cards: Int) -> LibraryState {
    var state = LibraryState()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    state.sources = (0..<max(10, cards / 10)).map { index in
        var source = LibrarySource(id: identifier(1, index), kind: .pdf, title: "Book \(index)")
        source.createdAt = date; source.updatedAt = date
        return source
    }
    state.marks = (0..<(cards * 2)).map { index in
        LibraryMark(id: identifier(2, index), sourceID: state.sources[index % state.sources.count].id,
            locator: ReadingLocator(kind: "pdf", page: index % 500 + 1),
            excerpt: "An isolated passage for performance measurement \(index).", createdAt: date)
    }
    state.cards = (0..<cards).map { index in
        let kind = CardKind.allCases[index % 4]
        var card = LibraryCard(type: kind, content: [LibraryCard.fields(for: kind)[0]: "Card \(index)"])
        card.id = identifier(3, index)
        card.createdAt = date; card.updatedAt = date
        card.markIDs = [state.marks[index].id]
        card.sourceRefs = [CardReference(id: identifier(4, index), sourceID: state.marks[index].sourceID, locator: state.marks[index].locator)]
        return card
    }
    return state
}
func measure(_ operation: () throws -> Int) rethrows -> [String: Any] {
    var times: [Double] = []
    var checksum = 0
    for _ in 0..<7 {
        let start = ContinuousClock.now
        checksum &+= try operation()
        let elapsed = start.duration(to: .now).components
        times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
    }
    times.sort()
    return ["median_ms": times[times.count / 2], "max_ms": times.last!, "samples_ms": times,
        "checksum": checksum]
}

let label = CommandLine.arguments.dropFirst().first ?? "unlabeled"
var results: [[String: Any]] = []
for size in [100, 2_000, 10_000] {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ks-performance-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LibraryRepository(url: directory.appendingPathComponent("library.sqlite"))
    let state = fixture(cards: size)
    try repository.restore(state)
    var edit = 0
    let index = LibraryMarkIndex(state.marks)
    let metrics: [String: Any] = [
        "read": try measure { try repository.read().cards.count },
        "no_change_transaction": try measure { try repository.updateAndRead { _ in }.marks.count },
        "reading_position_transaction": try measure {
            edit += 1
            return try repository.updateAndRead {
                $0.sources[0].lastLocation = ReadingLocator(kind: "pdf", page: edit)
            }.sources.count
        },
        "mark_index_build": measure { LibraryMarkIndex(state.marks).marks(for: state.sources[0].id).count },
        "indexed_marks_for_100_sources": measure {
            state.sources.prefix(100).reduce(0) { $0 + index.marks(for: $1.id).count }
        },
        "marks_for_100_sources": measure {
            state.sources.prefix(100).reduce(0) { total, source in
                total + state.marks.filter { $0.sourceID == source.id }.count
            }
        },
    ]
    let reopened = try LibraryRepository(url: directory.appendingPathComponent("library.sqlite")).read()
    precondition(reopened.sources[0].lastLocation?.page == 7 && reopened.cards == state.cards)
    results.append(["cards": size, "sources": state.sources.count, "marks": state.marks.count,
        "snapshot_bytes": try JSONEncoder().encode(state).count, "metrics": metrics])
}
let report: [String: Any] = ["label": label, "fixture_version": 2,
    "recorded_at_utc": ISO8601DateFormatter().string(from: Date()),
    "revision": ProcessInfo.processInfo.environment["KS_BENCHMARK_REVISION"] ?? "unknown",
    "working_tree_dirty": ProcessInfo.processInfo.environment["KS_BENCHMARK_DIRTY"] == "true",
    "toolchain": ProcessInfo.processInfo.environment["KS_BENCHMARK_TOOLCHAIN"] ?? "unknown",
    "active_processors": ProcessInfo.processInfo.activeProcessorCount, "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "configuration": "Release", "iterations": 7, "datasets": results,
    "scope": "Synthetic repository operations; not iPad frame rate, touch latency, or energy measurements."]
let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: output, as: UTF8.self))
