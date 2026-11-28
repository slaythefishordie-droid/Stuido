import Foundation

/// Presentation-only projection. Filter before constructing titles, especially
/// review dates; never used to decide whether an object can be deleted.
public struct LibraryObjectRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let kind: String
    public let deleted: Bool

    public init(id: UUID, title: String, kind: String, deleted: Bool) {
        self.id = id; self.title = title; self.kind = kind; self.deleted = deleted
    }

    public static func project(_ state: LibraryState, kind: String, trash: Bool,
        search: String, sortByName: Bool, markTitle: (LibraryMark) -> String
    ) -> [Self] {
        var rows: [Self] = []
        func append<T>(_ items: [T], kind category: String, deleted: (T) -> Bool,
            id: (T) -> UUID, title: (T) -> String, eligible: (T) -> Bool = { _ in true }) {
            guard kind == "全部" || kind == category else { return }
            for item in items where deleted(item) == trash && eligible(item) {
                let value = title(item)
                rows.append(Self(id: id(item), title: value, kind: category, deleted: trash))
            }
        }
        append(state.sources, kind: "资料", deleted: { $0.deletedAt != nil }, id: { $0.id }, title: { $0.title })
        append(state.marks, kind: "标记", deleted: { $0.deletedAt != nil }, id: { $0.id }, title: markTitle)
        append(state.cards, kind: "卡片", deleted: { $0.deletedAt != nil }, id: { $0.id }, title: { $0.title })
        append(state.projects, kind: "项目", deleted: { $0.deletedAt != nil }, id: { $0.id }, title: { $0.title })
        append(state.projects, kind: "白板", deleted: { $0.boardTrashedAt != nil },
            id: { $0.boardManagementID }, title: { $0.title + " · 白板" },
            eligible: { $0.hasBoard && ($0.deletedAt == nil || $0.boardTrashedAt != nil) })
        append(state.relations, kind: "关系", deleted: { $0.deletedAt != nil }, id: { $0.id }, title: { $0.kind })
        append(state.reviewRecords, kind: "复习记录", deleted: { $0.deletedAt != nil }, id: { $0.id },
            title: { "\($0.rating) · \($0.reviewedAt.formatted())" })
        // Keep date formatting and localized matching in separate passes. Interleaving
        // these Foundation operations regressed the full-library search benchmark.
        if !search.isEmpty { rows = rows.filter { $0.title.localizedCaseInsensitiveContains(search) } }
        if sortByName { rows.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        return rows
    }
}
