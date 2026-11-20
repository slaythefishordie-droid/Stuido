import KnowledgeCore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct StudioView: View {
    @StateObject private var model = StudioModel()
    @Environment(\.scenePhase) private var phase
    @State private var choosingCard = false
    @State private var showingSearch = false
    @State private var quickCard: LibraryCard?
    @State private var pendingDocument: IncomingDocument?
    @State private var importProject: UUID?
    private struct IncomingDocument: Identifiable {
        let id = UUID()
        let url: URL
    }
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
                    if !sideVisible && !immersive {
                        compactNavigation
                    }
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay(alignment: .leading) {
                if immersive {
                    if railRevealed {
                        HStack(spacing: 0) {
                            sidebar(expanded: expanded).frame(width: expanded ? 208 : 64)
                            Color.black.opacity(0.18).onTapGesture { railRevealed = false }
                                .accessibilityHidden(true)
                        }.transition(.move(edge: .leading))
                    } else {
                        Button { railRevealed = true } label: {
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                .padding(.vertical, 15).padding(.horizontal, 5)
                                .background(StudyTheme.plum, in: Capsule()).foregroundStyle(StudyTheme.railText)
                        }.buttonStyle(.plain).accessibilityLabel("展开书房导航")
                            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { value in
                                if value.translation.width > 14 { railRevealed = true }
                            })
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: railRevealed)
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
        .confirmationDialog("新建知识卡片", isPresented: $choosingCard) {
            ForEach(CardKind.allCases, id: \.self) { kind in
                Button(kind.title) { quickCard = LibraryCard(type: kind, content: [:]) }
            }
        }
        .sheet(isPresented: $showingSearch) { StudioSearchView().environmentObject(model) }
        .sheet(item: $quickCard) { CardEditor(card: $0).environmentObject(model) }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            guard pendingDocument == nil, !model.isImporting else {
                model.message = "正在处理另一份资料，请稍后重新打开此文件。"
                return
            }
            importProject = nil
            pendingDocument = IncomingDocument(url: url)
        }
        .sheet(item: $pendingDocument) { document in
            NavigationStack {
                Form {
                    Text(document.url.lastPathComponent)
                    Picker("归入项目", selection: $importProject) {
                        Text("暂不分类").tag(nil as UUID?)
                        ForEach(model.state.projects.filter { $0.deletedAt == nil }) { project in
                            Text(project.title).tag(Optional(project.id))
                        }
                    }
                }.studySurface().navigationTitle("导入资料")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { pendingDocument = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                let project = importProject
                                pendingDocument = nil
                                select(.library)
                                Task { await model.importFile(document.url, projectID: project) }
                            }
                        }
                    }
            }.presentationDetents([.medium])
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
                Button("全局搜索", systemImage: "magnifyingglass") { showingSearch = true }
                Button("随手记一张卡片") { choosingCard = true }
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
            Button { showingSearch = true } label: {
                if expanded { Label("全局搜索", systemImage: "magnifyingglass") }
                else { Image(systemName: "magnifyingglass") }
            }.frame(minHeight: 44).accessibilityLabel("全局搜索")
            Button { choosingCard = true } label: {
                if expanded { Label("随手记一张卡片", systemImage: "square.and.pencil") }
                else { Image(systemName: "square.and.pencil") }
            }.frame(minHeight: 44).accessibilityLabel("随手记一张卡片")
            Button {
                railMode = expanded ? "compact" : "expanded"
            } label: {
                Image(systemName: expanded ? "sidebar.left" : "sidebar.leading")
                    .frame(width: 44, height: 44)
            }.accessibilityLabel(expanded ? "收起导航栏" : "展开导航栏")
                .contextMenu {
                    Button("自动调整") { railMode = "auto" }
                }
            if !activeReaders.isEmpty {
                Button { railRevealed = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("隐藏导航")
            }
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

private struct StudioSearchView: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var projectID: UUID?

    var body: some View {
        NavigationStack {
            List {
                let projects = model.state.projects.filter { $0.deletedAt == nil }
                Picker("范围", selection: $projectID) {
                    Text("全书房").tag(nil as UUID?)
                    ForEach(projects) { Text($0.title).tag(Optional($0.id)) }
                }
                let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let project = projects.first { $0.id == projectID }
                    let sources = Set(project?.sourceIDs ?? [])
                    let cards = Set(project?.cardIDs ?? [])
                    Section("资料") {
                        ForEach(model.state.sources.filter {
                            $0.deletedAt == nil && (project == nil || sources.contains($0.id))
                                && $0.title.localizedCaseInsensitiveContains(query)
                        }) { source in
                            NavigationLink { SourceReaderView(source: source, location: source.lastLocation) } label: {
                                StudySourceTile(source: source, asset: model.assetURL(source), compact: true)
                            }
                        }
                    }
                    Section("卡片") {
                        ForEach(model.state.cards.filter {
                            $0.deletedAt == nil && (project == nil || cards.contains($0.id))
                                && $0.content.values.contains { $0.localizedCaseInsensitiveContains(query) }
                        }) { card in
                            NavigationLink { CardDetailView(cardID: card.id) } label: {
                                Label(card.title, systemImage: "rectangle.on.rectangle").foregroundStyle(card.type.color)
                            }
                        }
                    }
                    if project == nil {
                        Section("项目") {
                            ForEach(projects.filter { $0.title.localizedCaseInsensitiveContains(query) }) { item in
                                NavigationLink(item.title) { ProjectView(projectID: item.id) }
                            }
                        }
                    }
                }
            }.studySurface().navigationTitle("搜索书房").searchable(text: $text)
                .toolbar { Button("关闭") { dismiss() } }
        }
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
        }.studyPanel()
            .overlay(alignment: .leading) { Rectangle().fill(mark.highlightKind.color).frame(width: 2) }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .contextMenu {
            Button("移入回收站", role: .destructive) { model.delete([mark.id]) }
        }
    }
    private func markActions(_ mark: LibraryMark, source: LibrarySource?) -> some View {
        HStack {
            Menu("整理成卡片") {
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
        }.sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }
}

struct CardEditor: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    @State var card: LibraryCard
    @State private var projects: Set<UUID> = []
    @State private var initialized = false

    private var fields: [String] { LibraryCard.fields(for: card.type) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    fieldEditor(fields[0])
                    if fields.count > 1 {
                        DisclosureGroup("补充内容") {
                            ForEach(fields.dropFirst(), id: \.self) { fieldEditor($0) }
                        }
                    }
                } header: {
                    Label(card.type.title, systemImage: "circle.fill").foregroundStyle(card.type.color)
                }
                if !card.sourceRefs.isEmpty {
                    Section("出处") {
                        ForEach(card.sourceRefs) { ref in
                            if let source = model.state.sources.first(where: { $0.id == ref.sourceID }) {
                                LabeledContent(source.title, value: ref.locator.map { locationLabel($0) } ?? "")
                            }
                        }
                    }
                }
                if model.state.projects.contains(where: { $0.deletedAt == nil }) {
                    DisclosureGroup("关联项目（\(projects.count)）") {
                        ForEach(model.state.projects.filter { $0.deletedAt == nil }) { project in
                            Toggle(project.title, isOn: Binding(
                                get: { projects.contains(project.id) },
                                set: { enabled in
                                    if enabled { projects.insert(project.id) }
                                    else { projects.remove(project.id) }
                                }))
                        }
                    }
                }
                if model.state.cards.contains(where: { $0.id == card.id }) {
                    DisclosureGroup("个人笔记") {
                        TextField("个人笔记", text: $card.note, axis: .vertical)
                    }
                }
                Toggle("加入复习", isOn: Binding(
                    get: { card.review == .active },
                    set: { card.review = $0 ? .active : (card.schedule == nil ? .not_enrolled : .paused) }))
            }.studySurface().navigationTitle("编辑卡片")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }
                            .disabled(card.content[fields[0]]?.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty ?? true)
                    }
                }
        }.onAppear {
            guard !initialized else { return }
            initialized = true
            let exists = model.state.cards.contains { $0.id == card.id }
            let sourceIDs = Set(card.sourceRefs.map(\.sourceID))
            projects = Set(model.state.projects.filter { project in
                project.deletedAt == nil && (exists
                    ? project.cardIDs.contains(card.id)
                    : !sourceIDs.isDisjoint(with: project.sourceIDs))
            }.map(\.id))
        }
    }

    private func fieldEditor(_ field: String) -> some View {
        TextField(studioFieldLabel(field), text: Binding(
            get: { card.content[field] ?? "" },
            set: { value in
                card.content[field] = value
                card.provenance[field] = FieldOrigin(kind: "user_input")
            }), axis: .vertical)
    }

    private func save() {
        card.content = card.content.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        card.provenance = card.provenance.filter { card.content[$0.key] != nil || $0.key == "import_annotation" }
        card.updatedAt = Date()
        model.saveCard(card, projects: projects)
        if model.message == nil { dismiss() }
    }
}

struct CardDetailView: View {
    @EnvironmentObject private var model: StudioModel
    let cardID: UUID
    var reviewMode = false
    @State private var editor: LibraryCard?
    @State private var showDictionary = false
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
                    Section("发音与释义") {
                        PronunciationButton(word: card.title)
                        Button("系统词典") { showDictionary = true }
                            .disabled(!UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: card.title))
                            .sheet(isPresented: $showDictionary) { SystemDictionaryView(word: card.title) }
                    }
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
                CardReviewHistory(card: card)
                Button("编辑") { editor = card }
            }
        }.studySurface().tint(model.state.cards.first { $0.id == cardID }?.type.color ?? .accentColor)
    }
}
