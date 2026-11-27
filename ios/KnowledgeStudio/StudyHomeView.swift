import KnowledgeCore
import SwiftUI

struct StudyHomeView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.studyNavigation) private var navigation
    @AppStorage("studyHomeReviewFirst") private var reviewFirst = false
    @ScaledMetric(relativeTo: .body) private var columnWidth = 305.0
    private var reading: [LibrarySource] {
        model.sources.filter { $0.deletedAt == nil && $0.lastLocation != nil }
            .sorted { ($0.lastReadAt ?? $0.updatedAt) > ($1.lastReadAt ?? $1.updatedAt) }
    }
    private var cards: [LibraryCard] {
        model.cards.filter { $0.deletedAt == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var projects: [LibraryProject] {
        Array(model.projects.filter { $0.deletedAt == nil }.reversed())
    }

    var body: some View {
        // Reuse one projection across ViewThatFits candidates and the recent
        // shelf instead of filtering/sorting the library in every helper.
        let cards = self.cards
        let reading = self.reading
        let projects = self.projects
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("书桌").font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            thoughts(cards: cards).frame(minWidth: columnWidth + 90)
                            activity(reading: reading, projects: projects).frame(idealWidth: columnWidth, maxWidth: columnWidth)
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            thoughts(cards: cards)
                            activity(reading: reading, projects: projects)
                        }
                    }
                    recent(reading: reading)
                }.padding(24).frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
            }.studySurface()
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func thoughts(cards: [LibraryCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StudyHeading(title: "思想卡片")
            if let featured = cards.first(where: { $0.type == .key_sentence }) ?? cards.first {
                cardLink(featured, featured: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(relatedCards(to: featured, cards: cards)) { cardLink($0) }
                }
            } else {
                ContentUnavailableView("还没有知识卡片", systemImage: "rectangle.stack",
                    description: Text("在阅读器留下一个 Mark，或在知识卡片中记录第一个想法。"))
            }
            Button("浏览知识卡片") { navigation.open(.cards) }.font(.subheadline)
        }
    }

    private func relatedCards(to featured: LibraryCard, cards: [LibraryCard]) -> [LibraryCard] {
        let remaining = cards.filter { $0.id != featured.id }
        let distinct = CardKind.allCases.compactMap { kind in remaining.first { $0.type == kind } }
        let distinctIDs = Set(distinct.map(\.id))
        return Array((distinct + remaining.filter { !distinctIDs.contains($0.id) }).prefix(3))
    }

    private func activity(reading: [LibrarySource], projects: [LibraryProject]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if reviewFirst { reviewModule }
            StudyHeading(title: "继续阅读／观看")
            if let source = reading.first {
                sourceLink(source, compact: true).studyPanel()
            } else {
                Text("打开一份资料后，阅读位置会保存在这里。").foregroundStyle(.secondary)
            }
            StudyHeading(title: "活跃项目")
            if projects.isEmpty { Text("在资料库创建研究项目。").foregroundStyle(.secondary) }
            ForEach(projects.prefix(3)) { project in
                NavigationLink {
                    ProjectView(projectID: project.id)
                } label: {
                    HStack {
                        Label(project.title, systemImage: "folder")
                        Spacer()
                        Text("\(project.sourceIDs.count + project.cardIDs.count) 项")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }
            }
            if !reviewFirst { reviewModule }
        }
    }

    private var reviewModule: some View {
        TimelineView(.periodic(from: .now, by: 60)) { clock in
            let count = TodayReview.countDue(model.cards, at: clock.date)
            Button { navigation.open(.today) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("今日复习", systemImage: "calendar")
                            .font(.system(.title3, design: .serif, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(count.formatted()).font(.system(size: 38, weight: .medium, design: .serif))
                            .monospacedDigit()
                        Text("张卡片待复习").font(.subheadline)
                    }
                }.frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).padding(16)
                    .background(StudyTheme.plum, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(StudyTheme.railText)
            }.buttonStyle(.plain)
        }
    }

    private func recent(reading: [LibrarySource]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StudyHeading(title: "最近打开")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 14) {
                ForEach(reading.prefix(6)) { sourceLink($0, compact: false) }
            }
            Button("浏览资料库") { navigation.open(.library) }.font(.subheadline)
        }
    }

    private func cardLink(_ card: LibraryCard, featured: Bool = false) -> some View {
        StudyCardPreview(card: card, featured: featured)
    }

    private func sourceLink(_ source: LibrarySource, compact: Bool) -> some View {
        NavigationLink {
            SourceReaderView(source: source, location: source.lastLocation)
        } label: {
            StudySourceTile(source: source, asset: model.assetURL(source), compact: compact)
        }.buttonStyle(.plain)
    }
}
