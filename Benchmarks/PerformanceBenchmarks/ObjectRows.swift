import Foundation
import KnowledgeCore

// Frozen pre-optimization projection for result and timing comparisons.
func legacyRows(_ state: LibraryState, kind: String, trash: Bool, search: String, sortByName: Bool) -> [LibraryObjectRow] {
        var all: [LibraryObjectRow] = state.sources.map {
            LibraryObjectRow(id: $0.id, title: $0.title, kind: "资料", deleted: $0.deletedAt != nil)
        }
        all += state.marks.map {
            LibraryObjectRow(
                id: $0.id, title: $0.excerpt.isEmpty ? "定位" : $0.excerpt, kind: "标记",
                deleted: $0.deletedAt != nil)
        }
        all += state.cards.map {
            LibraryObjectRow(id: $0.id, title: $0.title, kind: "卡片", deleted: $0.deletedAt != nil)
        }
        all += state.projects.map {
            LibraryObjectRow(id: $0.id, title: $0.title, kind: "项目", deleted: $0.deletedAt != nil)
        }
        all += state.projects.filter { $0.hasBoard && ($0.deletedAt == nil || $0.boardTrashedAt != nil) }
            .map { LibraryObjectRow(id: $0.boardManagementID, title: $0.title + " · 白板", kind: "白板",
                deleted: $0.boardTrashedAt != nil) }
        all += state.relations.map {
            LibraryObjectRow(id: $0.id, title: $0.kind, kind: "关系", deleted: $0.deletedAt != nil)
        }
        all += state.reviewRecords.map {
            LibraryObjectRow(
                id: $0.id, title: "\($0.rating) · \($0.reviewedAt.formatted())", kind: "复习记录",
                deleted: $0.deletedAt != nil)
        }
        let filtered = all.filter {
            $0.deleted == trash && (kind == "全部" || $0.kind == kind)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
        if sortByName { return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        return filtered
}

func objectRowsBenchmark() throws {
    var results: [[String: Any]] = []
    for size in [100, 2_000, 10_000] {
        var state = fixture(cards: size)
        state.reviewRecords = (0..<(size * 2)).map { index in
            var record = LibraryReviewRecord(cardID: state.cards[index % size].id, rating: 3,
                reviewedAt: Date(timeIntervalSince1970: 1_700_000_000), elapsedMilliseconds: 1000, schedulerVersion: "fixture")
            record.id = identifier(5, index)
            return record
        }
        try state.validate()
        for (kind, trash, search) in [("资料", false, ""), ("全部", true, ""), ("全部", false, "Card 9"), ("全部", false, "")] {
            func old() -> [LibraryObjectRow] { legacyRows(state, kind: kind, trash: trash, search: search, sortByName: false) }
            func new() -> [LibraryObjectRow] { LibraryObjectRow.project(state, kind: kind, trash: trash, search: search,
                sortByName: false, markTitle: { $0.excerpt.isEmpty ? "定位" : $0.excerpt }) }
            precondition(old() == new())
            func checksum(_ rows: [LibraryObjectRow]) -> Int { rows.reduce(0) { $0 &+ $1.title.utf8.count } }
            // Alternate ordering across process repetitions using the command-line flag.
            let before: [String: Any], after: [String: Any]
            if CommandLine.arguments.contains("--reverse") {
                after = measure { checksum(new()) }; before = measure { checksum(old()) }
            } else {
                before = measure { checksum(old()) }; after = measure { checksum(new()) }
            }
            results.append(["cards": size, "marks": state.marks.count, "reviews": state.reviewRecords.count,
                "kind": kind, "trash": trash, "search": search, "before": before, "after": after])
        }
    }
    let report: [String: Any] = ["scope": "Linux Release projection only; not UI latency or energy", "iterations": 7, "results": results]
    print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
}
