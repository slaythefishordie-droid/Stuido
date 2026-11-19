import KnowledgeCore
import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @StateObject private var model = StudioModel()
    @Environment(\.scenePhase) private var phase
    @State private var quickCard = false
    @State private var destination: StudySection? = .home
    @AppStorage("compactDisplay") private var compactDisplay = false
    @AppStorage("appAppearance") private var appearance = "system"
    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("阅读与思考") {
                    ForEach([StudySection.home, .library, .inbox, .cards]) { section in
                        NavigationLink(value: section) { Label(section.title, systemImage: section.symbol) }
                    }
                }
                Section("整理与维护") {
                    ForEach([StudySection.imports, .manager, .settings]) { section in
                        NavigationLink(value: section) { Label(section.title, systemImage: section.symbol) }
                    }
                }
            }
            .navigationTitle("我的书房")
            .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 290)
            .safeAreaInset(edge: .bottom) {
                Button {
                    quickCard = true
                } label: {
                    Label("随手记一张卡片", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).padding()
            }
        } detail: {
            Group {
                switch destination ?? .home {
                case .home: StudyHomeView()
                case .library: LibraryView()
                case .inbox: InboxView()
                case .cards: CardsView()
                case .imports: AIInboxView()
                case .manager: DataManagerView()
                case .settings: ExtensionSetupView()
                }
            }
            .background(StudyTheme.paper)
        }
        .navigationSplitViewStyle(.balanced)
        .scrollContentBackground(.hidden)
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
}

struct InboxView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var search = ""
    @State private var editor: LibraryCard?
    @State private var selected: Set<UUID> = []
    var marks: [LibraryMark] {
        model.state.marks.filter {
            $0.deletedAt == nil && $0.organization == .inbox
                && (search.isEmpty
                    || ($0.excerpt + $0.note + sourceTitle($0)).localizedCaseInsensitiveContains(search))
        }.sorted { $0.createdAt > $1.createdAt }
    }
    func sourceTitle(_ mark: LibraryMark) -> String {
        model.state.sources.first { $0.id == mark.sourceID }?.title ?? "资料不可用"
    }
    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                if let warning = model.sharedWarning { Text(warning).foregroundStyle(.orange) }
                if marks.isEmpty {
                    ContentUnavailableView(
                        "没有待整理标记", systemImage: "tray", description: Text("在 Safari、PDF、EPUB 或本地视频中保存标记。"))
                }
                ForEach(
                    Array(Set(marks.map(\.sourceID))).sorted { $0.uuidString < $1.uuidString }, id: \.self
                ) { sourceID in
                    Section(model.state.sources.first { $0.id == sourceID }?.title ?? "资料不可用") {
                        ForEach(marks.filter { $0.sourceID == sourceID }) { mark in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(mark.highlightKind.title, systemImage: "circle.fill").font(.caption)
                                    .foregroundStyle(mark.highlightKind.color)
                                Text(sourceTitle(mark)).font(.headline)
                                if !mark.excerpt.isEmpty { Text(mark.excerpt).lineLimit(5) }
                                if !mark.note.isEmpty { Text(mark.note).foregroundStyle(.secondary) }
                                Text(locationLabel(mark.locator)).font(.caption)
                                HStack {
                                    Button("整理为\(mark.highlightKind.title)") {
                                        editor = model.card(from: mark, type: mark.highlightKind)
                                    }
                                    Menu("其他类型") {
                                        ForEach(CardKind.allCases, id: \.self) { kind in
                                            Button(kind.title) { editor = model.card(from: mark, type: kind) }
                                        }
                                    }
                                    if let source = model.state.sources.first(where: {
                                        $0.id == mark.sourceID && $0.deletedAt == nil
                                    }) {
                                        NavigationLink("回到出处") {
                                            SourceReaderView(source: source, location: mark.locator)
                                        }
                                    }
                                    Button("归档") {
                                        model.change { state in
                                            if let i = state.marks.firstIndex(where: { $0.id == mark.id }) {
                                                state.marks[i].organization = .archived
                                            }
                                        }
                                    }
                                }.buttonStyle(.borderless)
                                NavigationLink("备注与详情") { MarkDetailView(markID: mark.id) }
                            }.padding(.vertical, 4).tag(mark.id).contextMenu {
                                Button("移入回收站", role: .destructive) { model.delete([mark.id]) }
                            }
                        }
                    }
                }
            }.navigationTitle("收集箱").searchable(text: $search).refreshable { model.refresh() }
                .toolbar {
                    EditButton()
                    Button("接收标记") { model.refresh() }
                    if !selected.isEmpty {
                        Button("归档所选") {
                            model.change { state in
                                for i in state.marks.indices where selected.contains(state.marks[i].id) {
                                    state.marks[i].organization = .archived
                                }
                            }
                            selected.removeAll()
                        }
                        Button("移入回收站", role: .destructive) {
                            model.delete(Array(selected))
                            selected.removeAll()
                        }
                    }
                }
        }.sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
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
                Text(mark.id.uuidString).font(.caption).textSelection(.enabled)
            }
        }.navigationTitle("标记详情").onAppear {
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
                && (category == "全部" || card.type.title == category)
                && (search.isEmpty
                    || (card.title + card.note + card.tags.joined(separator: " "))
                        .localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Picker("视图", selection: $category) {
                    ForEach(["全部"] + CardKind.allCases.map(\.title), id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                ForEach(cards) { card in
                    NavigationLink {
                        CardDetailView(cardID: card.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(card.type == .word ? card.content["example_en"] ?? "" : card.title)
                                .lineLimit(3)
                            if card.type == .word {
                                Text(card.content["word"] ?? "").font(.headline)
                                Text(card.content["definition_en"] ?? "").foregroundStyle(.secondary)
                            }
                            Text(
                                "\(card.type.title) · \(studioLabel(card.organization.rawValue)) · \(studioLabel(card.review.rawValue))"
                            ).font(.caption).foregroundStyle(card.type.color)
                        }
                    }.contextMenu {
                        Button("编辑卡片") { editor = card }
                        Button("移入回收站", role: .destructive) { model.delete([card.id]) }
                    }
                }
            }.navigationTitle("知识卡片").searchable(text: $search)
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
                Text("复习调度与每日任务将在产品阶段 6 接入。").font(.caption)
                Picker("关联项目", selection: $project) {
                    Text("不新增项目关联").tag(nil as UUID?)
                    ForEach(model.state.projects.filter { $0.deletedAt == nil }) {
                        Text($0.title).tag(Optional($0.id))
                    }
                }
                if !card.sourceRefs.isEmpty {
                    Text("已保留 \(card.sourceRefs.count) 个出处和 \(card.markIDs.count) 个 Mark 关联。")
                }
            }.navigationTitle("编辑卡片")
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
        }.navigationTitle("卡片详情").sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }
    private func content(showComparison: Bool) -> some View {
        Form {
            if let card = model.state.cards.first(where: { $0.id == cardID }) {
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
                if card.type == .word { Section("发音") { PronunciationButton(word: card.content["word"] ?? "") } }
                Section("笔记") {
                    Text(card.note)
                    if !card.importAnnotation.isEmpty { Text("导入说明：\(card.importAnnotation)") }
                }
                Section("出处") {
                    ForEach(card.sourceRefs) { ref in
                        if let source = model.state.sources.first(where: { $0.id == ref.sourceID }) {
                            if source.deletedAt == nil {
                                NavigationLink(source.title) {
                                    SourceReaderView(source: source, location: ref.locator)
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
                Button("编辑") { editor = card }
            }
        }.tint(model.state.cards.first { $0.id == cardID }?.type.color ?? .accentColor)
    }
}
