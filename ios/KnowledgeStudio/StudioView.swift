import KnowledgeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct StudioView: View {
    @StateObject private var model = StudioModel()
    @Environment(\.scenePhase) private var phase
    @State private var quickCard = false
    @SceneStorage("studyDestination") private var destination = StudySection.home.rawValue
    @SceneStorage("studyRailRevealed") private var railRevealed = false
    @AppStorage("studyRailMode") private var railMode = "auto"
    @AppStorage("compactDisplay") private var compactDisplay = false
    @AppStorage("appAppearance") private var appearance = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeReaders: Set<UUID> = []
    private var selected: StudySection { StudySection(rawValue: destination) ?? .home }
    private let primary: [StudySection] = [.home, .library, .inbox, .cards, .today]
    private let secondary: [StudySection] = [.imports, .manager, .settings]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let immersive = !activeReaders.isEmpty
            let expanded = width >= 850 && (railMode == "expanded" || (railMode == "auto" && width >= 1040))
            let sideVisible = !immersive && width >= 620
            HStack(spacing: 0) {
                if sideVisible { sidebar(expanded: expanded).frame(width: expanded ? 208 : 64) }
                VStack(spacing: 0) {
                    if !sideVisible && (!immersive || railRevealed) {
                        compactNavigation
                    }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: sideVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: expanded)
        }
        .environment(\.studyNavigation, StudyNavigation { select($0) })
        .environment(\.studyReaderPresentation, StudyReaderPresentation(setActive: { id, visible in
            if visible {
                if activeReaders.isEmpty { railRevealed = false }
                activeReaders.insert(id)
            } else { activeReaders.remove(id) }
        }, toggleNavigation: { railRevealed.toggle() }))
        .background(StudyTheme.paper)
        .tint(StudyTheme.ink)
        .environment(\.defaultMinListRowHeight, compactDisplay ? 44 : 60)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .environmentObject(model)
        .sheet(isPresented: $quickCard) {
            CardEditor(card: LibraryCard(type: .keyword, content: [:])).environmentObject(model)
        }
        .alert(
            "提示", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })
        ) {
            Button("知道了") { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .onChange(of: phase) { _, value in if value == .active { model.refresh() } }
    }
    @ViewBuilder private var detail: some View {
        switch selected {
        case .home: StudyHomeView()
        case .today: TodayView()
        case .library: LibraryView()
        case .inbox: InboxView()
        case .cards: CardsView()
        case .imports: AIInboxView()
        case .manager: DataManagerView()
        case .settings: ExtensionSetupView()
        }
    }

    private func select(_ section: StudySection) {
        if selected != section { activeReaders.removeAll() }
        destination = section.rawValue
        railRevealed = false
    }

    private var compactNavigation: some View {
        HStack {
            Menu {
                ForEach(primary + secondary) { section in
                    Button { select(section) } label: {
                        Label(section.title, systemImage: selected == section ? "checkmark" : section.symbol)
                    }
                }
                Divider()
                Button("随手记一张卡片") { quickCard = true }
                if !activeReaders.isEmpty {
                    Button("隐藏导航") { railRevealed = false }
                }
            } label: {
                Label("Knowledge Studio", systemImage: "sidebar.leading")
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .frame(minHeight: 44)
            }
            Spacer()
            Text(selected.title).font(.caption)
        }.padding(.horizontal, 15).foregroundStyle(StudyTheme.railText).background(StudyTheme.plum)
    }

    private func sidebar(expanded: Bool) -> some View {
        VStack(spacing: 8) {
            Group {
                if expanded {
                    Text("Knowledge\nStudio")
                        .font(.system(.title2, design: .serif, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                } else {
                    Image(systemName: "book.closed").font(.title2).frame(height: 44)
                        .accessibilityLabel("Knowledge Studio")
                }
            }.padding(.top, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(primary) { railButton($0, expanded: expanded) }
                    Rectangle().fill(StudyTheme.railText.opacity(0.24)).frame(height: 1).padding(.vertical, 8)
                    ForEach(secondary) { railButton($0, expanded: expanded) }
                }
            }.scrollIndicators(.hidden)
            Button { quickCard = true } label: {
                if expanded { Label("随手记一张卡片", systemImage: "square.and.pencil") }
                else { Image(systemName: "square.and.pencil") }
            }.frame(minHeight: 44).accessibilityLabel("随手记一张卡片")
            Menu {
                Picker("导航栏布局", selection: $railMode) {
                    Text("自动调整").tag("auto")
                    Text("固定展开").tag("expanded")
                    Text("紧凑图标").tag("compact")
                }
            } label: {
                Image(systemName: "sidebar.leading").frame(width: 44, height: 44)
            }.accessibilityLabel("导航栏布局")
        }.padding(8).foregroundStyle(StudyTheme.railText).background(StudyTheme.plum.ignoresSafeArea())
            .tint(StudyTheme.railText)
    }

    private func railButton(_ section: StudySection, expanded: Bool) -> some View {
        Button { select(section) } label: {
            HStack(spacing: 9) {
                Image(systemName: section.symbol).frame(width: 24)
                if expanded { Text(section.title).lineLimit(1); Spacer(minLength: 0) }
            }.frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, expanded ? 8 : 0)
                .background(selected == section ? Color.white.opacity(0.13) : .clear)
                .overlay(alignment: .leading) {
                    if selected == section { Rectangle().fill(StudyTheme.copper).frame(width: 2) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(section.title)
            .accessibilityAddTraits(selected == section ? .isSelected : [])
    }

}

struct InboxView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var search = ""
    @State private var editor: LibraryCard?
    @State private var selected: Set<UUID> = []
    private struct SourceGroup: Identifiable {
        let id: UUID
        let source: LibrarySource?
        let marks: [LibraryMark]
        var title: String { source?.title ?? "资料不可用" }
    }
    private var groups: [SourceGroup] {
        let sources = Dictionary(uniqueKeysWithValues: model.state.sources.map { ($0.id, $0) })
        let marks = model.state.marks.filter { mark in
            guard mark.deletedAt == nil, mark.organization == .inbox else { return false }
            let content = mark.excerpt + mark.note + (sources[mark.sourceID]?.title ?? "")
            return search.isEmpty || content.localizedCaseInsensitiveContains(search)
        }.sorted { $0.createdAt > $1.createdAt }
        return Dictionary(grouping: marks, by: \.sourceID).map { id, marks in
            SourceGroup(id: id, source: sources[id], marks: marks)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            inboxList.studySurface().navigationTitle("收集箱").searchable(text: $search)
                .refreshable { model.refresh() }.toolbar { inboxToolbar }
        }.sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }
    private var inboxList: some View {
        let groups = groups
        return List(selection: $selected) {
            if let warning = model.sharedWarning { Text(warning).foregroundStyle(.orange) }
            if groups.isEmpty {
                ContentUnavailableView(
                    "没有待整理标记", systemImage: "tray", description: Text("在 Safari、PDF、EPUB 或本地视频中保存标记。"))
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.marks) { mark in
                        markRow(mark, source: group.source).tag(mark.id)
                    }
                }
            }
        }
    }
    private func markRow(_ mark: LibraryMark, source: LibrarySource?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(mark.highlightKind.title, systemImage: "circle.fill").font(.caption).foregroundStyle(
                mark.highlightKind.color)
            if !mark.excerpt.isEmpty {
                Text(mark.excerpt).font(.system(.title3, design: .serif)).lineLimit(5)
            }
            if !mark.note.isEmpty { Text(mark.note).foregroundStyle(.secondary) }
            Text(locationLabel(mark.locator)).font(.caption)
            ScrollView(.horizontal, showsIndicators: false) { markActions(mark, source: source) }
            NavigationLink("备注与详情") { MarkDetailView(markID: mark.id) }
        }.studyPanel()
            .overlay(alignment: .leading) { Rectangle().fill(mark.highlightKind.color).frame(width: 2) }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .contextMenu {
            Button("移入回收站", role: .destructive) { model.delete([mark.id]) }
        }
    }
    private func markActions(_ mark: LibraryMark, source: LibrarySource?) -> some View {
        HStack {
            Button("整理为\(mark.highlightKind.title)") {
                editor = model.card(from: mark, type: mark.highlightKind)
            }
            Menu("其他类型") {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    Button(kind.title) { editor = model.card(from: mark, type: kind) }
                }
            }
            if let source, source.deletedAt == nil {
                NavigationLink("回到出处") { SourceReaderView(source: source, location: mark.locator) }
            }
            Button("归档") { archive([mark.id]) }
        }.buttonStyle(.borderless)
    }
    private func archive(_ ids: Set<UUID>) {
        model.change { state in
            for i in state.marks.indices where ids.contains(state.marks[i].id) {
                state.marks[i].organization = .archived
            }
        }
        if model.message == nil { selected.subtract(ids) }
    }
    @ToolbarContentBuilder private var inboxToolbar: some ToolbarContent {
        ToolbarItemGroup {
            EditButton()
            Button("接收标记") { model.refresh() }
            if !selected.isEmpty {
                Button("归档所选") { archive(selected) }
                Button("移入回收站", role: .destructive) {
                    model.delete(selected)
                    if model.message == nil { selected.removeAll() }
                }
            }
        }
    }
}

func locationLabel(_ locator: ReadingLocator) -> String {
    if let page = locator.page { return "文件第 \(page) 页" }
    if let seconds = locator.seconds { return String(format: "%.1f 秒", seconds) }
    return locator.href ?? "阅读定位"
}
struct MarkDetailView: View {
    @EnvironmentObject private var model: StudioModel
    let markID: UUID
    @State private var note = ""
    @State private var showingInk = false
    @State private var kind: CardKind = .expression
    var body: some View {
        Form {
            if let mark = model.state.marks.first(where: { $0.id == markID }) {
                Label(mark.highlightKind.title, systemImage: "circle.fill").foregroundStyle(
                    mark.highlightKind.color)
                Text(mark.excerpt)
                Text(locationLabel(mark.locator))
                Picker("高亮类型", selection: $kind) {
                    ForEach(CardKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("个人备注", text: $note, axis: .vertical)
                Button("保存备注与颜色") {
                    model.setMarkNote(id: markID, note: note)
                    if model.message == nil {
                        model.change { state in
                            if let i = state.marks.firstIndex(where: { $0.id == markID }) {
                                state.marks[i].cardKind = kind
                            }
                        }
                    }
                }
                if mark.locator.kind == "epub", !mark.excerpt.isEmpty, mark.locator.nativeJSON != nil,
                    mark.deletedAt == nil
                {
                    Button(mark.epubNoteInk == nil ? "添加手写页边注" : "打开手写页边注",
                        systemImage: "pencil.tip") { showingInk = true }
                }
                DisclosureGroup("标记技术信息") {
                    Text(mark.id.uuidString).font(.caption).textSelection(.enabled)
                }
            }
        }.studySurface().navigationTitle("标记详情").sheet(isPresented: $showingInk) {
            if let mark = model.state.marks.first(where: { $0.id == markID }) {
                EPUBInkNote(mark: mark).environmentObject(model)
            }
        }.onAppear {
            note = model.state.marks.first { $0.id == markID }?.note ?? ""
            kind = model.state.marks.first { $0.id == markID }?.highlightKind ?? .expression
        }
    }
}

struct CardsView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var search = ""
    @State private var category = "全部"
    @State private var editor: LibraryCard?
    var cards: [LibraryCard] {
        model.state.cards.filter { card in
            card.deletedAt == nil
                && (category == "全部" || card.type.title == category
                    || (category == "词汇库" && [.word, .keyword].contains(card.type))
                    || (category == "语料库" && [.expression, .key_sentence].contains(card.type)))
                && (search.isEmpty
                    || (card.content.values.joined(separator: " ") + card.note
                        + card.tags.joined(separator: " "))
                        .localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Picker("视图", selection: $category) {
                    ForEach(["全部", "词汇库", "语料库"] + CardKind.allCases.map(\.title), id: \.self) { Text($0) }
                }.pickerStyle(.menu)
                ForEach(cards) { card in
                    NavigationLink {
                        CardDetailView(cardID: card.id)
                    } label: {
                        StudyCardFace(card: card)
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden).contextMenu {
                        Button("编辑卡片") { editor = card }
                        Button("移入回收站", role: .destructive) { model.delete([card.id]) }
                    }
                }
            }.studySurface().navigationTitle("知识卡片").searchable(text: $search)
                .toolbar { Button("新建") { editor = LibraryCard(type: .keyword, content: [:]) } }
        }.sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }
}

struct CardEditor: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State var card: LibraryCard
    @State private var tags = ""
    @State private var project: UUID?
    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $card.type) {
                    ForEach(CardKind.allCases, id: \.self) { Text(studioLabel($0.rawValue)) }
                }
                ForEach(LibraryCard.fields(for: card.type), id: \.self) { field in
                    TextField(
                        studioFieldLabel(field),
                        text: Binding(
                            get: { card.content[field] ?? "" },
                            set: { value in
                                card.content[field] = value
                                card.provenance[field] = FieldOrigin(kind: "user_input")
                            }), axis: .vertical)
                }
                TextField("语言", text: $card.language)
                TextField("标签（逗号分隔）", text: $tags)
                TextField("个人笔记", text: $card.note, axis: .vertical)
                Picker("整理状态", selection: $card.organization) {
                    ForEach(Organization.allCases, id: \.self) { Text(studioLabel($0.rawValue)) }
                }
                Picker("复习状态（由你选择）", selection: $card.review) {
                    ForEach(ReviewStatus.allCases, id: \.self) { Text(studioLabel($0.rawValue)) }
                }
                Text("主动加入复习后，可在今日复习查看到期卡片；暂停和退出均保留历史。").font(.caption)
                Picker("关联项目", selection: $project) {
                    Text("不新增项目关联").tag(nil as UUID?)
                    ForEach(model.state.projects.filter { $0.deletedAt == nil }) {
                        Text($0.title).tag(Optional($0.id))
                    }
                }
                if !card.sourceRefs.isEmpty {
                    Text("已保留 \(card.sourceRefs.count) 个出处和 \(card.markIDs.count) 个标记关联。")
                }
            }.studySurface().navigationTitle("编辑卡片")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let allowed = Set(LibraryCard.fields(for: card.type))
                            card.content = card.content.filter {
                                allowed.contains($0.key) && !$0.value.isEmpty
                            }
                            card.provenance = card.provenance.filter {
                                allowed.contains($0.key) || $0.key == "import_annotation"
                            }
                            for field in card.content.keys where card.provenance[field] == nil {
                                card.provenance[field] = FieldOrigin(kind: "user_input")
                            }
                            card.tags = Array(
                                Set(
                                    tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty }))
                            card.updatedAt = Date()
                            model.message = nil
                            model.saveCard(card, project: project)
                            if model.message == nil { dismiss() }
                        }
                    }
                }
        }.onAppear { tags = card.tags.joined(separator: ", ") }
    }
}

struct CardDetailView: View {
    @EnvironmentObject private var model: StudioModel
    let cardID: UUID
    var reviewMode = false
    @State private var editor: LibraryCard?
    @State private var comparison: CardReference?
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                content(showComparison: geometry.size.width >= 900)
                    .frame(maxWidth: comparison != nil && geometry.size.width >= 900 ? 380 : .infinity)
                if geometry.size.width >= 900, let ref = comparison,
                    let source = model.state.sources.first(where: {
                        $0.id == ref.sourceID && $0.deletedAt == nil
                    })
                {
                    Divider()
                    NavigationStack {
                        SourceReaderView(source: source, location: ref.locator)
                            .id(ref.id)
                            .toolbar { Button("结束对照") { comparison = nil } }
                    }
                }
            }
        }.safeAreaInset(edge: .bottom) { if reviewMode { ReviewControls(cardID: cardID) } }.navigationTitle(
            "卡片详情"
        ).sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }
    private func content(showComparison: Bool) -> some View {
        Form {
            if let card = model.state.cards.first(where: { $0.id == cardID }) {
                Section { StudyCardFace(card: card, featured: card.type == .key_sentence) }
                    .listRowBackground(Color.clear)
                ForEach(LibraryCard.fields(for: card.type), id: \.self) { field in
                    if let value = card.content[field] {
                        Section(studioFieldLabel(field)) {
                            Text(value).textSelection(.enabled)
                            Text(studioLabel(card.provenance[field]?.kind ?? "user_input")).font(.caption)
                                .foregroundStyle(
                                    .secondary)
                        }
                    }
                }
                if card.type == .word {
                    Section("发音") { PronunciationButton(word: card.content["word"] ?? "") }
                }
                Section("笔记") {
                    Text(card.note)
                    if !card.importAnnotation.isEmpty { Text("导入说明：\(card.importAnnotation)") }
                }
                Section("出处") {
                    ForEach(card.sourceRefs) { ref in
                        if let source = model.state.sources.first(where: { $0.id == ref.sourceID }) {
                            if source.deletedAt == nil {
                                NavigationLink {
                                    SourceReaderView(source: source, location: ref.locator)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.title)
                                        if let locator = ref.locator {
                                            Text(locationLabel(locator)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                if showComparison { Button("与原文并排对照") { comparison = ref } }
                            } else {
                                Text("\(source.title)（在回收站）")
                            }
                        }
                    }
                }
                Section("关联标记") {
                    ForEach(card.markIDs, id: \.self) { id in
                        NavigationLink(
                            model.state.marks.first { $0.id == id }?.excerpt.isEmpty == false
                                ? String((model.state.marks.first { $0.id == id }?.excerpt ?? "").prefix(80))
                                : "查看标记与备注"
                        ) { MarkDetailView(markID: id) }
                    }
                }
                Section("词典外链") {
                    Link(
                        "维基词典",
                        destination: URL(
                            string: "https://en.wiktionary.org/wiki/" + card.title.addingPercentEncoding(
                                withAllowedCharacters: .urlPathAllowed)!)!)
                }
                CardReviewHistory(card: card)
                Button("编辑") { editor = card }
            }
        }.studySurface().tint(model.state.cards.first { $0.id == cardID }?.type.color ?? .accentColor)
    }
}
