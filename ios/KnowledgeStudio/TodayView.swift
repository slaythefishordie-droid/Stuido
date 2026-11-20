import KnowledgeCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: StudioModel
    @AppStorage("reviewRetention") private var retention = 0.9
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                let active = model.state.cards.filter { $0.deletedAt == nil && $0.review == .active }
                let end =
                    Calendar.current.date(
                        byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: clock.date))
                    ?? clock.date
                List {
                    Section("现在可复习") {
                        let due = active.filter { ($0.schedule?.due ?? .distantPast) <= clock.date }.sorted {
                            ($0.schedule?.due ?? .distantPast) < ($1.schedule?.due ?? .distantPast)
                        }
                        if due.isEmpty { Text("今天可以从容阅读。没有到期卡片。").foregroundStyle(.secondary) }
                        ForEach(due) { card in
                            NavigationLink {
                                CardDetailView(cardID: card.id, reviewMode: true)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(card.title)
                                    Text(card.type.title).font(.caption).foregroundStyle(card.type.color)
                                }
                            }
                        }
                    }
                    Section("今天稍后") {
                        ForEach(
                            active.filter {
                                ($0.schedule?.due ?? .distantPast) > clock.date
                                    && ($0.schedule?.due ?? .distantFuture) < end
                            }
                        ) { card in
                            NavigationLink {
                                CardDetailView(cardID: card.id)
                            } label: {
                                HStack {
                                    Text(card.title)
                                    Spacer()
                                    Text(card.schedule?.due ?? clock.date, style: .time).foregroundStyle(
                                        .secondary)
                                }
                            }
                        }
                    }
                    DisclosureGroup("调度设置") {
                        Slider(value: $retention, in: 0.7...0.97, step: 0.01)
                        Text("新卡目标保持率：\(Int(retention * 100))%")
                        Text("仅在首次记录复习时采用；已有卡片保留原参数与到期时间。日期按设备时区展示，算法按固定时间戳计算。").font(.caption)
                    }
                    Text("只显示你主动加入复习的卡片。打开原卡后记录自评，不增加题型。").font(.caption).foregroundStyle(.secondary)
                }.navigationTitle("今日复习")
            }
        }
    }
}

struct ReviewControls: View {
    @EnvironmentObject private var model: StudioModel
    let cardID: UUID
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
