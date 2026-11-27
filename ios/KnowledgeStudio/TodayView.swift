import KnowledgeCore
import SwiftUI

enum TodayReview {
    private static func isDue(_ card: LibraryCard, at date: Date) -> Bool {
        card.deletedAt == nil && card.review == .active && (card.schedule?.due ?? .distantPast) <= date
    }
    static func due(_ cards: [LibraryCard], at date: Date) -> [LibraryCard] {
        cards.filter { isDue($0, at: date) }
            .sorted { ($0.schedule?.due ?? .distantPast) < ($1.schedule?.due ?? .distantPast) }
    }
    static func countDue(_ cards: [LibraryCard], at date: Date) -> Int {
        cards.reduce(0) { $0 + (isDue($1, at: date) ? 1 : 0) }
    }
}

struct TodayView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                let due = Dictionary(grouping: TodayReview.due(model.cards, at: clock.date), by: \.type)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("今日复习").font(.system(.largeTitle, design: .serif, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text(due.isEmpty ? "今天的复习已就绪，暂无到期卡片。" :
                                "\(due.values.reduce(0) { $0 + $1.count }) 张卡片待复习")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 460), spacing: 16)], spacing: 16) {
                            ForEach(CardKind.allCases, id: \.self) { kind in
                                let ids = (due[kind] ?? []).map(\.id)
                                NavigationLink {
                                    ReviewQueueView(kind: kind, cardIDs: ids)
                                } label: {
                                    ReviewQueueTile(kind: kind, count: ids.count)
                                }.buttonStyle(.plain).disabled(ids.isEmpty)
                                    .accessibilityIdentifier("review.queue." + kind.rawValue)
                            }
                        }
                    }.padding(24).frame(maxWidth: 860).frame(maxWidth: .infinity, alignment: .center)
                }.studySurface().navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

private struct ReviewQueueTile: View {
    let kind: CardKind
    let count: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind.title).font(.system(.headline, design: .serif))
                Spacer()
                Image(systemName: count > 0 ? "arrow.up.right" : "checkmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(count.formatted()).font(.system(size: 37, weight: .medium, design: .serif))
                .monospacedDigit()
            Text(count > 0 ? "张待复习" : "暂无到期").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(StudyTheme.leaf, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) { Rectangle().fill(kind.color).frame(width: 3) }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}

private struct ReviewQueueView: View {
    @Environment(StudioModel.self) private var model
    let kind: CardKind
    @State var cardIDs: [UUID]
    @State private var index = 0
    @State private var reviewed = 0

    init(kind: CardKind, cardIDs: [UUID]) {
        self.kind = kind
        _cardIDs = State(initialValue: cardIDs)
    }

    private var nextIndex: Int? {
        let active = Set(model.cards.lazy.filter {
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
    @Environment(StudioModel.self) private var model
    let cardID: UUID
    var onSaved: () -> Void = {}
    @State private var eventID = UUID()
    @State private var expectedRevision: Int?
    @State private var started = Date()
    @State private var saved = false
    @State private var saving = false
    @State private var failure: String?
    @AppStorage("reviewRetention") private var retention = 0.9
    var body: some View {
        VStack(spacing: 8) {
            Text(saved ? "复习记录已保存" : "看过原卡后，记录这次记忆情况").font(.caption)
            HStack {
                ForEach(Array(["忘记", "困难", "良好", "轻松"].enumerated()), id: \.offset) { index, label in
                    Button(label) {
                        guard !saving, !saved else { return }
                        saving = true
                        failure = nil
                        let elapsed = max(0, Int(min(86_400, Date().timeIntervalSince(started)) * 1000))
                        Task {
                            defer { saving = false }
                            do {
                                try await model.reviewCard(cardID, rating: index + 1,
                                    expectedRevision: expectedRevision, eventID: eventID,
                                    elapsedMilliseconds: elapsed, retention: retention)
                                saved = true
                                onSaved()
                            } catch { failure = error.localizedDescription }
                        }
                    }.buttonStyle(.bordered).disabled(saved || saving)
                        .accessibilityIdentifier("review.rate.\(index + 1)")
                }
            }
            if saving { ProgressView().controlSize(.small).accessibilityLabel("正在保存复习结果") }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            if saved, let due = model.cards.first(where: { $0.id == cardID })?.schedule?.due {
                Text("下次：\(due.formatted(date: .abbreviated, time: .shortened))").font(.caption)
            }
        }.padding().background(.regularMaterial)
            .onAppear { expectedRevision = model.cards.first { $0.id == cardID }?.schedule?.revision }
    }
}

struct CardReviewHistory: View {
    @Environment(StudioModel.self) private var model
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
            let records = model.reviewRecords.filter { $0.cardID == card.id }.sorted {
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
