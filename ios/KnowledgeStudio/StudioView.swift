import KnowledgeCore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct StudioView: View {
    @StateObject private var model = StudioModel()
    @ObservedObject private var lounge = LoungeHub.shared
    @State private var sceneID = UUID()
    @State private var sourcesReading: [(reader: UUID, source: UUID)] = []
    @State private var loungeOverlay = false
    @AppStorage("loungePopupSeconds") private var popupSeconds = 12
    @Environment(\.scenePhase) private var phase
    @State private var choosingCard = false
    @State private var creatingProject = false
    @State private var projectTitle = ""
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
    private let secondary: [StudySection] = [.imports, .manager, .settings, .lounge]

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
                            Color.clear.contentShape(Rectangle()).onTapGesture { railRevealed = false }
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
            .overlay(alignment: .bottomTrailing) { loungeCorner }
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: lounge.reminder)
        }
        .environment(\.studyNavigation, StudyNavigation { select($0) })
        .environment(\.studyReaderPresentation, StudyReaderPresentation(setActive: { id, sourceID, visible, immersive in
            sourcesReading.removeAll { $0.reader == id }
            if visible {
                sourcesReading.append((id, sourceID))
                if immersive {
                    if activeReaders.isEmpty { railRevealed = false }
                    activeReaders.insert(id)
                }
            } else { activeReaders.remove(id) }
            updateLoungeActivity()
        }))
        .environmentObject(lounge)
        .sheet(isPresented: $loungeOverlay) {
            NavigationStack {
                LoungeView().toolbar { Button("返回学习") { loungeOverlay = false } }
            }.environmentObject(lounge).environmentObject(model)
        }
        .task(id: lounge.reminder) {
            if lounge.reminder != nil {
                do { try await Task.sleep(for: .seconds(max(5, min(30, popupSeconds)))) } catch { return }
                lounge.closeReminder()
            }
        }
        .onChange(of: lounge.route, initial: true) { _, token in
            if token != nil { openLounge() }
        }
        .onChange(of: loungeOverlay) { _, _ in updateLoungeActivity() }
        .onAppear { updateLoungeActivity(promote: true) }
        .onDisappear { lounge.scene(sceneID, active: false, sourceID: nil) }
        .background(StudyTheme.paper)
        .tint(StudyTheme.ink)
        .environment(\.defaultMinListRowHeight, compactDisplay ? 44 : 60)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .environmentObject(model)
        .confirmationDialog("新建", isPresented: $choosingCard) {
            ForEach(CardKind.allCases, id: \.self) { kind in
                Button(kind.title) { quickCard = LibraryCard(type: kind, content: [:]) }
            }
            Button("研究项目") {
                projectTitle = ""
                creatingProject = true
            }
        }
        .alert("新建项目", isPresented: $creatingProject) {
            TextField("项目名称", text: $projectTitle)
            Button("创建") {
                let title = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { model.message = "请输入项目名称。"; return }
                model.change { $0.projects.append(LibraryProject(title: title)) }
                if model.message == nil { select(.library) }
            }
            Button("取消", role: .cancel) {}
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
        .onChange(of: phase) { _, value in
            updateLoungeActivity(promote: value == .active)
            if value == .active { Task { await model.refreshAsync() } }
        }
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
        case .lounge: LoungeView()
        }
    }

    private func updateLoungeActivity(promote: Bool = false) {
        lounge.scene(sceneID, active: phase == .active,
            sourceID: loungeOverlay ? nil : sourcesReading.last?.source, promote: promote)
    }

    private func openLounge() {
        lounge.closeReminder()
        if !sourcesReading.isEmpty { loungeOverlay = true }
        else { select(.lounge) }
    }

    @ViewBuilder private var loungeCorner: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let error = lounge.message {
                HStack(alignment: .top) {
                    Text(error).font(.caption)
                    Button { lounge.message = nil } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭提示")
                }.padding(12).background(StudyTheme.leaf)
            }
            if lounge.reminder != nil {
                HStack(spacing: 15) {
                    Button { openLounge() } label: {
                        Label("休息片刻", systemImage: "cup.and.saucer")
                            .font(.system(.headline, design: .serif)).frame(minHeight: 44)
                    }
                    Button { lounge.closeReminder() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭休息提醒")
                }.padding(.horizontal, 12).background(StudyTheme.leaf, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(StudyTheme.rule).allowsHitTesting(false) }
                    .transition(.opacity.combined(with: reduceMotion ? .identity : .offset(y: 8)))
            }
            if selected != .lounge, !loungeOverlay, let track = lounge.track, lounge.player != nil {
                Menu {
                    Button(lounge.playing ? "暂停" : "播放") { lounge.togglePlayback() }
                    Button("上一首") { lounge.skip(-1) }
                    Button("下一首") { lounge.skip(1) }
                    Button("打开休息室") { openLounge() }
                } label: {
                    Label(track.title, systemImage: lounge.playing ? "waveform" : "music.note")
                        .lineLimit(1).font(.caption).frame(minHeight: 38)
                        .padding(.horizontal, 12).background(StudyTheme.leaf, in: Capsule())
                }.frame(maxWidth: 210)
            }
        }.buttonStyle(.plain).frame(maxWidth: 310, alignment: .trailing).padding(16)
    }

    private func select(_ section: StudySection) {
        if selected != section {
            activeReaders.removeAll()
            sourcesReading.removeAll()
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.19)) { destination = section.rawValue }
        updateLoungeActivity()
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
                Button("新建") { choosingCard = true }
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
                if expanded { Label("新建", systemImage: "square.and.pencil") }
                else { Image(systemName: "square.and.pencil") }
            }.frame(minHeight: 44).accessibilityLabel("新建")
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
    @State private var archived = false
    @State private var undoMark: UUID?
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
            guard mark.deletedAt == nil, mark.organization == (archived ? .archived : .inbox) else { return false }
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
                .refreshable { await model.refreshAsync() }.toolbar { inboxToolbar }
        }.safeAreaInset(edge: .bottom) {
            if let undoMark {
                HStack {
                    Label("卡片已保存，摘录已归档", systemImage: "checkmark.circle")
                    Spacer()
                    Button("撤销归档") {
                        model.change { state in
                            if let index = state.marks.firstIndex(where: { $0.id == undoMark && $0.deletedAt == nil }) {
                                state.marks[index].organization = .inbox
                            }
                        }
                        if model.message == nil { self.undoMark = nil }
                    }
                }.padding().background(StudyTheme.leaf)
            }
        }.task(id: undoMark) {
            if undoMark != nil {
                do { try await Task.sleep(for: .seconds(7)) } catch { return }
                undoMark = nil
            }
        }.sheet(item: $editor) { card in
            CardEditor(card: card, inboxMark: card.markIDs.first) { undoMark = card.markIDs.first }
                .environmentObject(model)
        }
    }
    private var inboxList: some View {
        let groups = groups
        return List(selection: $selected) {
            if let warning = model.sharedWarning { Text(warning).foregroundStyle(.orange) }
            if groups.isEmpty {
                ContentUnavailableView(
                    archived ? "归档为空" : "没有待整理标记", systemImage: "tray", description: Text("在 Safari、PDF、EPUB 或本地视频中保存标记。"))
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
            if !archived {
                Button {
                    guard editor == nil else { return }
                    editor = model.state.cards.first { $0.markIDs.contains(mark.id) && $0.deletedAt == nil }
                        ?? model.card(from: mark, type: mark.highlightKind)
                } label: {
                    Label("整理成卡片", systemImage: "rectangle.badge.plus")
                }.buttonStyle(.bordered)
            }
            if let source, source.deletedAt == nil {
                NavigationLink("回到出处") { SourceReaderView(source: source, location: mark.locator) }
            }
            if !archived { Button("归档") { archive([mark.id]) } }
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
            Button(archived ? "待整理" : "归档历史") { archived.toggle(); selected.removeAll() }
            Button("接收标记") { Task { await model.refreshAsync() } }
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
                    StudyCardPreview(card: card).listRowBackground(Color.clear).listRowSeparator(.hidden).contextMenu {
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
    var inboxMark: UUID? = nil
    var onSaved: () -> Void = {}
    @State private var saving = false
    @State private var failure: String?
    @State private var projects: Set<UUID> = []
    @State private var initialized = false

    private var fields: [String] { LibraryCard.fields(for: card.type) }

    var body: some View {
        NavigationStack {
            Form {
                if let failure { Text(failure).foregroundStyle(.red) }
                if inboxMark != nil && !model.state.cards.contains(where: { $0.id == card.id }) {
                    Picker("卡片类型", selection: Binding(get: { card.type }, set: { kind in
                        guard let inboxMark, let mark = model.state.marks.first(where: { $0.id == inboxMark }) else { return }
                        let previous = card.content[fields[0]]
                        let wasEdited = card.provenance[fields[0]]?.kind == "user_input"
                        var next = model.card(from: mark, type: kind)
                        next.id = card.id
                        next.review = card.review
                        if wasEdited {
                            let field = LibraryCard.fields(for: kind)[0]
                            next.content[field] = previous
                            next.provenance[field] = FieldOrigin(kind: "user_input")
                        }
                        card = next
                    })) {
                        ForEach(CardKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
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
            }.disabled(saving).studySurface().navigationTitle("编辑卡片").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "正在保存…" : "保存") { save() }
                            .disabled(saving || (card.content[fields[0]]?.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty ?? true))
                    }
                }
        }.interactiveDismissDisabled(saving).onAppear {
            guard !initialized else { return }
            initialized = true
            projects = model.suggestedProjects(for: card)
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
        guard !saving else { return }
        saving = true
        failure = nil
        let draft = card
        let selectedProjects = projects
        Task {
            do {
                try await model.saveEditedCard(draft, projects: selectedProjects, inboxMark: inboxMark)
                onSaved()
                dismiss()
            } catch { failure = error.localizedDescription }
            saving = false
        }
    }
}

struct StudyCardPreview: View {
    @EnvironmentObject private var model: StudioModel
    let card: LibraryCard
    var featured = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { CardDetailView(cardID: card.id) } label: {
                StudyCardFace(card: card, featured: featured)
            }.buttonStyle(.plain)
            if let ref = card.sourceRefs.first(where: { ref in
                model.state.sources.contains { $0.id == ref.sourceID && $0.deletedAt == nil }
            }), let source = model.state.sources.first(where: { $0.id == ref.sourceID }) {
                NavigationLink {
                    CardDetailView(cardID: card.id, initialComparison: ref)
                } label: {
                    HStack {
                        Text(source.title).lineLimit(1).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Label("原文对照", systemImage: "book.pages")
                    }.font(.caption).padding(.horizontal, 14).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).background(StudyTheme.leaf)
            }
        }
    }
}

struct CardDetailView: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cardID: UUID
    var reviewMode = false
    @State private var editor: LibraryCard?
    @State private var showDictionary = false
    @State private var comparison: CardReference?

    init(cardID: UUID, reviewMode: Bool = false, initialComparison: CardReference? = nil) {
        self.cardID = cardID
        self.reviewMode = reviewMode
        _comparison = State(initialValue: initialComparison)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 820
            HStack(spacing: 0) {
                ScrollView {
                    if let card = model.state.cards.first(where: { $0.id == cardID }) {
                        folio(card).frame(maxWidth: 740).padding(24).frame(maxWidth: .infinity)
                    }
                }.frame(maxWidth: wide && comparison != nil ? 440 : .infinity)
                if wide, let comparison {
                    Divider()
                    sourcePane(comparison).transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }.animation(reduceMotion ? nil : .smooth(duration: 0.24), value: comparison?.id)
                .sheet(isPresented: Binding(get: { !wide && comparison != nil }, set: {
                    if !$0 { comparison = nil }
                })) {
                    if let comparison { sourcePane(comparison) }
                }
        }.studySurface().navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { if reviewMode { ReviewControls(cardID: cardID) } }
            .sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }

    private func sourcePane(_ ref: CardReference) -> some View {
        NavigationStack {
            Group {
                if let source = model.state.sources.first(where: { $0.id == ref.sourceID && $0.deletedAt == nil }) {
                    SourceReaderView(source: source, location: ref.locator).id(ref.id)
                } else { ContentUnavailableView("原文不可用", systemImage: "book.closed") }
            }.toolbar { Button("结束对照") { comparison = nil } }
        }
    }

    private func folio(_ card: LibraryCard) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            VStack(alignment: .leading, spacing: 18) {
                Label(card.type.title, systemImage: card.type == .key_sentence ? "quote.opening" : "circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(card.type.color)
                Text(card.title)
                    .font(.system(card.type == .word ? .largeTitle : .title, design: .serif,
                        weight: card.type == .keyword ? .bold : .medium))
                    .italic(card.type == .expression)
                    .textSelection(.enabled).accessibilityAddTraits(.isHeader)
                ForEach(LibraryCard.fields(for: card.type).dropFirst(), id: \.self) { field in
                    if let value = card.content[field], !value.isEmpty, value != card.title {
                        Text(value).font(field == "example_en" ? .callout.italic() : .body)
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if card.type == .word {
                    HStack {
                        PronunciationButton(word: card.title)
                        Button("系统词典") { showDictionary = true }
                            .disabled(!UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: card.title))
                    }.sheet(isPresented: $showDictionary) { SystemDictionaryView(word: card.title) }
                }
                if !card.note.isEmpty { Text(card.note).font(.callout).textSelection(.enabled) }
                if !card.importAnnotation.isEmpty { Text(card.importAnnotation).font(.callout).foregroundStyle(.secondary) }
                ForEach(card.sourceRefs) { ref in
                    if let source = model.state.sources.first(where: { $0.id == ref.sourceID && $0.deletedAt == nil }) {
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).font(.subheadline.weight(.medium))
                                if let locator = ref.locator { Text(locationLabel(locator)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button { comparison = comparison?.id == ref.id ? nil : ref } label: {
                                Label("原文对照", systemImage: "book.pages").labelStyle(.titleAndIcon)
                            }.buttonStyle(.bordered)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(StudyTheme.leaf)
                .overlay(alignment: .leading) { Rectangle().fill(card.type.color).frame(width: 3) }
            HStack {
                Button("编辑", systemImage: "pencil") { editor = card }
                Spacer()
                if !card.markIDs.isEmpty {
                    Menu("关联标记") {
                        ForEach(card.markIDs, id: \.self) { id in
                            if let mark = model.state.marks.first(where: { $0.id == id && $0.deletedAt == nil }) {
                                NavigationLink(mark.excerpt.isEmpty ? locationLabel(mark.locator) : String(mark.excerpt.prefix(65))) {
                                    MarkDetailView(markID: id)
                                }
                            }
                        }
                    }
                }
            }.font(.subheadline)
            CardReviewHistory(card: card)
        }
    }
}
