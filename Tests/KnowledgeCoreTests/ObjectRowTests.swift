import Foundation
import XCTest
@testable import KnowledgeCore

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

final class ObjectRowTests: XCTestCase {
    func testProjectionMatchesLegacyAcrossFiltersAndBoardTrash() throws {
        var state = LibraryState()
        state.sources = [LibrarySource(kind: .pdf, title: "资料10"), LibrarySource(kind: .pdf, title: "资料2")]
        state.sources[1].deletedAt = .now
        state.marks = [LibraryMark(sourceID: state.sources[0].id, locator: ReadingLocator(kind: "pdf", page: 2), excerpt: ""),
            LibraryMark(sourceID: state.sources[0].id, locator: ReadingLocator(kind: "pdf", page: 3), excerpt: "HELLO")]
        state.marks[1].deletedAt = .now
        state.cards = [LibraryCard(type: .word, content: ["word": "hello2"]), LibraryCard(type: .expression, content: ["text": "hello10"])]
        state.cards[1].deletedAt = .now
        state.relations = [LibraryRelation(from: state.cards[0].id, to: state.cards[1].id, kind: "hello")]
        state.reviewRecords = [LibraryReviewRecord(cardID: state.cards[0].id, rating: 3, reviewedAt: .now, elapsedMilliseconds: 0, schedulerVersion: "test")]
        for index in 0..<4 {
            var project = LibraryProject(title: "项目\(index)")
            project.board = ProjectBoard()
            if index & 1 != 0 { project.deletedAt = .now }
            if index & 2 != 0 { project.boardTrashedAt = .now }
            state.projects.append(project)
        }
        try state.validate()
        for kind in ["全部", "资料", "标记", "卡片", "项目", "白板", "关系", "复习记录", "未知"] {
            for trash in [false, true] {
                for search in ["", "hello", "定位", "项目", "missing"] {
                    for sort in [false, true] {
                        XCTAssertEqual(LibraryObjectRow.project(state, kind: kind, trash: trash, search: search, sortByName: sort,
                            markTitle: { $0.excerpt.isEmpty ? "定位" : $0.excerpt }),
                            legacyRows(state, kind: kind, trash: trash, search: search, sortByName: sort))
                    }
                }
            }
        }
        var titles = 0
        _ = LibraryObjectRow.project(state, kind: "资料", trash: false, search: "", sortByName: false,
            markTitle: { titles += 1; return $0.excerpt })
        XCTAssertEqual(titles, 0)
    }
}
