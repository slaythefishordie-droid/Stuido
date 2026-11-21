import KnowledgeCore
import SwiftUI

enum TodayReview {
    static func due(_ cards: [LibraryCard], at date: Date) -> [LibraryCard] {
        cards.filter {
            $0.deletedAt == nil && $0.review == .active && ($0.schedule?.due ?? .distantPast) <= date
        }.sorted { ($0.schedule?.due ?? .distantPast) < ($1.schedule?.due ?? .distantPast) }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: StudioModel

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                let due = Dictionary(grouping: TodayReview.due(model.state.cards, at: clock.date), by: \.type)
                List {
                    ForEach(CardKind.allCases, id: \.self) { kind in
                        let ids = (due[kind] ?? []).map(\.id)
                        NavigationLink {
                            ReviewQueueView(kind: kind, cardIDs: ids)
                        } label: {
                            Label {
                                LabeledContent(kind.title, value: "\(ids.count)")
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(kind.color)
                            }.frame(minHeight: 44)
                        }.disabled(ids.isEmpty)
                    }
                }.studySurface().navigationTitle("今日复习")
            }
        }
    }
}

private struct ReviewQueueView: View {
    @EnvironmentObject private var model: StudioModel
    let kind: CardKind
    @State var cardIDs: [UUID]
    @State private var index = 0
    @State private var reviewed = 0

    init(kind: CardKind, cardIDs: [UUID]) {
        self.kind = kind
        _cardIDs = State(initialValue: cardIDs)
    }

    private var nextIndex: Int? {
        let active = Set(model.state.cards.lazy.filter {
            $0.deletedAt == nil && $0.review == .active && ($0.schedule?.due ?? .distantPast) <= .now
        }.map(\.id))
        return cardIDs.indices.dropFirst(index).first { active.contains(cardIDs[$0]) }
    }

    var body: some View {
        Group {
            if let nextIndex {
                let id = cardIDs[nextIndex]
                CardDetailView(cardID: id)
                    .safeAreaInset(edge: .bottom) {
                        ReviewControls(cardID: id) {
                            reviewed += 1
                            index = nextIndex + 1
                        }
                    }.id(id).transition(.opacity)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("\(kind.title) · \(nextIndex + 1)/\(cardIDs.count)").font(.subheadline)
                        }
                    }
            } else {
                ContentUnavailableView("本轮结束", systemImage: "checkmark.circle",
                    description: Text("已完成 \(reviewed) 张\(kind.title)。"))
            }
        }.studySurface().studyChange(nextIndex)
    }
}

struct ReviewControls: View {
    @EnvironmentObject private var model: StudioModel
    let cardID: UUID
    var onSaved: () -> Void = {}
    @State private var eventID = UUID()
    @State private var expectedRevision: Int?
    @State private var started = Date()
    @State private var saved = false
    @AppStorage("reviewRetention") private var retention = 0.9
    var body: some View {
        VStack(spacing: 8) {
            Text(saved ? "复习记录已保存" : "看过原卡后，记录这次记忆情况").font(.caption)
            HStack {
                ForEach(Array(["忘记", "困难", "良好", "轻松"].enumerated()), id: \.offset) { index, label in
                    Button(label) {
                        model.perform {
                            try model.repository?.recordReview(
                                cardID: cardID, rating: index + 1,
                                expectedRevision: expectedRevision, eventID: eventID,
                                elapsedMilliseconds: max(
                                    0, Int(min(86_400, Date().timeIntervalSince(started)) * 1000)),
                                retention: retention)
                        }
                        saved = model.message == nil
                        if saved { onSaved() }
                    }.buttonStyle(.bordered).disabled(saved)
                }
            }
            if saved, let due = model.state.cards.first(where: { $0.id == cardID })?.schedule?.due {
                Text("下次：\(due.formatted(date: .abbreviated, time: .shortened))").font(.caption)
            }
        }.padding().background(.regularMaterial)
            .onAppear { expectedRevision = model.state.cards.first { $0.id == cardID }?.schedule?.revision }
    }
}

struct CardReviewHistory: View {
    @EnvironmentObject private var model: StudioModel
    let card: LibraryCard
    @State private var retention = 0.9
    var body: some View {
        DisclosureGroup("复习记录与调度") {
            if let schedule = card.schedule {
                Text("下次复习：\(schedule.due.formatted(date: .abbreviated, time: .shortened))")
                Text("算法：FSRS-6").font(.caption)
                Slider(value: $retention, in: 0.7...0.97, step: 0.01)
                Button("保存目标保持率 \(Int(retention * 100))%") {
                    model.change { state in
                        guard let i = state.cards.firstIndex(where: { $0.id == card.id }) else { return }
                        try state.cards[i].schedule?.setRetention(retention)
                    }
                }
                Text("保留当前到期时间，新参数从下一次评分起生效。").font(.caption).foregroundStyle(.secondary)
            }
            let records = model.state.reviewRecords.filter { $0.cardID == card.id }.sorted {
                $0.reviewedAt > $1.reviewedAt
            }
            if records.isEmpty { Text("尚无复习记录") }
            ForEach(records.prefix(50)) { record in
                HStack {
                    Text(record.reviewedAt, style: .date)
                    Text(record.reviewedAt, style: .time)
                    Spacer()
                    Text(
                        (1...4).contains(record.rating) ? ["忘记", "困难", "良好", "轻松"][record.rating - 1] : "旧评分")
                }.font(.caption)
            }
            if records.count > 50 { Text("显示最近 50 条；完整历史保留在备份中。").font(.caption) }
        }.onAppear { retention = card.schedule?.retention ?? 0.9 }
    }
}
