import KnowledgeCore
import SwiftUI
import UniformTypeIdentifiers

struct AIInboxView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var text = ""
    @State private var importing = false
    @State private var pending: PendingImport?
    @State private var editingJSON = false
    @State private var staging = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        StudyHeading(title: "导入卡片包")
                        Text("先校验内容，再匹配资料和选择候选卡片。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.studyPanel()
                }.listRowBackground(Color.clear)
                Section("准备卡片包") {
                    Button("选择 JSON 文件", systemImage: "doc.badge.plus") { importing = true }.disabled(staging)
                    DisclosureGroup("查看或粘贴 JSON", isExpanded: $editingJSON) {
                        TextEditor(text: $text).frame(minHeight: 126).font(.system(.body, design: .monospaced))
                    }
                    Button {
                        let input = text
                        staging = true
                        Task {
                            await model.stageImport(input)
                            if model.message == nil && text == input { text = "" }
                            staging = false
                        }
                    } label: {
                        if staging { ProgressView().accessibilityLabel("正在校验卡片包") }
                        else { Text("校验并放入导入箱") }
                    }.disabled(text.isEmpty || staging)
                }
                Section("待确认批次") {
                    if model.state.pending.isEmpty {
                        Label("暂无待确认批次", systemImage: "tray").foregroundStyle(.secondary)
                    }
                    ForEach(model.state.pending) { item in
                        Button {
                            pending = item
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.system(.headline, design: .serif))
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.studySurface().navigationTitle("导入箱")
        }.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            staging = true
            Task {
                defer { staging = false }
                do {
                    let url = try result.get()
                    text = try await Task.detached(priority: .userInitiated) {
                        let scope = url.startAccessingSecurityScopedResource()
                        defer { if scope { url.stopAccessingSecurityScopedResource() } }
                        let limit = 10 * 1024 * 1024
                        let file = try FileHandle(forReadingFrom: url)
                        defer { try? file.close() }
                        let data = try file.read(upToCount: limit + 1) ?? Data()
                        guard data.count <= limit else { throw LibraryError.invalid("JSON 超过 10 MiB") }
                        return String(decoding: data, as: UTF8.self)
                    }.value
                } catch { model.message = error.localizedDescription }
            }
        }.sheet(item: $pending) { ImportReviewView(pending: $0).environmentObject(model) }
    }
}
struct ImportReviewView: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    let pending: PendingImport
    @State private var preview: ImportPreview?
    @State private var selected: Set<UUID> = []
    @State private var project: UUID?
    @State private var matches: [String: UUID] = [:]
    @State private var confirm = false
    @State private var loading = false
    @State private var rawSources: [[String: String]] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("匹配已有资料") {
                    ForEach(rawSources, id: \.self) { source in
                        Picker(
                            source["title"] ?? "",
                            selection: Binding<UUID?>(
                                get: { matches[source["id"]!] },
                                set: {
                                    matches[source["id"]!] = $0
                                    preview = nil
                                })
                        ) {
                            Text("按摘要／链接匹配，否则新建").tag(nil as UUID?)
                            ForEach(
                                model.state.sources.filter {
                                    $0.deletedAt == nil && $0.kind.rawValue == source["kind"]
                                }
                            ) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    if loading { ProgressView("正在校验…") }
                    else { Button("生成预览") { Task { await load() } } }
                }
                if let preview {
                    Section("候选卡片（\(selected.count)/\(preview.cards.count)）") {
                        ForEach(preview.cards) { card in
                            ObjectSelectionRow(
                                isSelected: Binding(
                                    get: { selected.contains(card.id) },
                                    set: {
                                        if $0 { selected.insert(card.id) } else { selected.remove(card.id) }
                                    })
                            ) {
                                VStack(alignment: .leading) {
                                    Text(card.title)
                                    Text(card.type.title).font(.caption)
                                    ForEach(card.content.keys.sorted(), id: \.self) { field in
                                        Text("\(studioFieldLabel(field))：\(card.content[field]!)").font(
                                            .caption)
                                    }
                                    if preview.duplicateCardIDs.contains(card.id) {
                                        Text("已有相同内容，默认跳过；勾选将新增副本。").foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                    Section("提示") {
                        ForEach(Array(preview.warnings.enumerated()), id: \.offset) {
                            Text($0.element).font(.caption)
                        }
                        Text("关系仅在双方卡片都被选中时导入。导入说明不会写成个人笔记，不会自动加入复习。")
                    }
                    Picker("项目", selection: $project) {
                        Text("不关联项目").tag(nil as UUID?)
                        ForEach(model.state.projects.filter { $0.deletedAt == nil }) {
                            Text($0.title).tag(Optional($0.id))
                        }
                    }
                    Button("确认导入所选卡片") { confirm = true }.disabled(selected.isEmpty)
                }
            }.studySurface().navigationTitle(pending.title).toolbar { Button("关闭") { dismiss() } }
        }.task {
            let json = pending.json
            rawSources = await Task.detached {
                guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                    let sources = root["sources"] as? [[String: Any]]
                else { return [[String: String]]() }
                return sources.map {
                    ["id": $0["id"] as? String ?? "", "title": $0["title"] as? String ?? "",
                        "kind": $0["kind"] as? String ?? ""]
                }
            }.value
            await load()
        }
            .confirmationDialog("将所选候选写入知识库？", isPresented: $confirm, titleVisibility: .visible) {
                Button("导入") {
                    guard let preview, let repository = model.repository else { return }
                    model.message = nil
                    model.perform {
                        try ImportService.commit(
                            preview, selected: selected, projectID: project, pendingID: pending.id,
                            to: repository)
                    }
                    if model.message == nil { dismiss() }
                }
            }
    }
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let json = pending.json
        let snapshot = model.state
        let selections = matches
        do {
            let value = try await Task.detached(priority: .userInitiated) {
                try ImportService.preview(json, existing: snapshot, sourceMatches: selections)
            }.value
            guard selections == matches, !Task.isCancelled else { return }
            preview = value
            selected = Set(value.cards.map(\.id)).subtracting(value.duplicateCardIDs)
        } catch {
            model.message = error.localizedDescription
            preview = nil
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var importing = false
    @State private var search = ""
    @State private var projectTitle = ""
    @State private var selectedProject: UUID?
    @State private var coverSourceID: UUID?
    @AppStorage("libraryCoverLayout") private var coverLayout = true
    @State private var collection = "全部"
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    private var sources: [LibrarySource] {
        let projects = model.state.projects.filter { $0.deletedAt == nil }
        let classified = collection == "未分类" ? Set(projects.flatMap(\.sourceIDs)) : []
        let results = model.state.sources.filter { source in
            source.deletedAt == nil
                && (search.isEmpty || source.title.localizedCaseInsensitiveContains(search))
                && (collection != "收藏" || source.isFavorite == true)
                && (collection != "未分类" || !classified.contains(source.id))
                && (collection != "最近" || source.lastReadAt != nil)
        }
        return collection == "最近" ? results.sorted {
            ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
        } : results
    }

    private var collectionPicker: some View {
        Picker("资料集合", selection: $collection) {
            ForEach(["全部", "最近", "未分类", "收藏"], id: \.self) { Text($0) }
        }.pickerStyle(.segmented)
            .onChange(of: collection) { _, _ in selected.removeAll() }
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= 850 {
                    HStack(spacing: 0) {
                        List {
                            Button {
                                selectedProject = nil
                            } label: {
                                Label("全部资料", systemImage: "books.vertical")
                            }
                            projectTree(wide: true)
                        }.studySurface().frame(width: 212)
                        Divider()
                        if let selectedProject {
                            ProjectView(projectID: selectedProject).id(selectedProject)
                        } else {
                            sourceList(includeProjects: false)
                        }
                    }
                } else {
                    sourceList(includeProjects: true)
                }
            }.studySurface().navigationTitle("资料库").searchable(text: $search)
                .toolbar {
                    Button(model.isImporting ? "导入中…" : "导入资料") {
                        coverSourceID = nil
                        importing = true
                    }.disabled(
                        model.isImporting)
                    if selectedProject == nil {
                        Button {
                            coverLayout.toggle()
                        } label: {
                            Label(coverLayout ? "列表" : "封面",
                                systemImage: coverLayout ? "list.bullet" : "square.grid.2x2")
                        }.disabled(selecting)
                        Button(selecting ? "完成" : "选择") {
                            selecting.toggle()
                            selected.removeAll()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting && !selected.isEmpty {
                        HStack {
                            Text("已选 \(selected.count) 项")
                            Button("移入回收站", role: .destructive) {
                                model.delete(selected)
                                if model.message == nil { selected.removeAll() }
                            }
                        }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
                    }
                }
        }.fileImporter(
            isPresented: $importing,
            allowedContentTypes: coverSourceID == nil ? [.pdf, UTType(filenameExtension: "epub") ?? .data, .movie] : [.image]
        ) { result in
            if let id = coverSourceID {
                coverSourceID = nil
                do { saveSourceCover(try StudyCoverImport.read(result.get()), id: id) }
                catch { model.message = error.localizedDescription }
                return
            }
            Task {
                do { await model.importFile(try result.get()) } catch {
                    model.message = error.localizedDescription
                }
            }
        }
    }
    private func saveSourceCover(_ data: Data?, id: UUID) {
        model.change { state in
            guard let index = state.sources.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
                throw LibraryError.invalid("资料已不可用")
            }
            state.sources[index].coverImage = data
            state.sources[index].coverMode = .custom
        }
    }

    @ViewBuilder private func sourceActionMenu(_ source: LibrarySource) -> some View {
        Menu("封面") {
            Button(source.coverImage == nil ? "选择自定义图片" : "更换自定义图片") {
                coverSourceID = source.id
                importing = true
            }
            if source.coverImage != nil {
                Button("使用自定义封面") { setCoverMode(.custom, source: source) }
            }
            Button("使用原始封面") {
                Task {
                    guard let asset = model.assetURL(source),
                        await StudyThumbnails.artwork(asset, kind: source.kind).image != nil else {
                        model.message = "此资料没有可用的原始封面，当前封面已保留。"
                        return
                    }
                    setCoverMode(.original, source: source)
                }
            }
            Button("使用自动封面") { setCoverMode(.generated, source: source) }
            Button("重新生成自动封面") { setCoverMode(.generated, source: source, regenerate: true) }
        }
        Button(source.isFavorite == true ? "取消收藏" : "收藏") {
            model.change { state in
                guard let index = state.sources.firstIndex(where: { $0.id == source.id && $0.deletedAt == nil }) else {
                    throw LibraryError.invalid("资料已不可用")
                }
                state.sources[index].isFavorite = state.sources[index].isFavorite != true
            }
        }
        Button("移入回收站", role: .destructive) { model.delete([source.id]) }
    }

    private func setCoverMode(_ mode: SourceCoverMode, source: LibrarySource, regenerate: Bool = false) {
        model.change { state in
            guard let index = state.sources.firstIndex(where: { $0.id == source.id && $0.deletedAt == nil }) else {
                throw LibraryError.invalid("资料已不可用")
            }
            state.sources[index].coverMode = mode
            if regenerate {
                let previous = max(0, state.sources[index].coverVariation ?? 0)
                state.sources[index].coverVariation = (previous % 6 + 1) % 6
            }
        }
    }

    private func sourceLink(_ source: LibrarySource, compact: Bool) -> some View {
        NavigationLink {
            SourceReaderView(source: source, location: source.lastLocation)
        } label: {
            StudySourceTile(source: source, asset: model.assetURL(source), compact: compact)
        }.contextMenu { sourceActionMenu(source) }
    }

    @ViewBuilder private func projectTree(wide: Bool) -> some View {
        Section("研究项目") {
            DisclosureGroup("新建项目") {
                TextField("项目名称", text: $projectTitle)
                Button("创建") {
                    let title = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    model.change { $0.projects.append(LibraryProject(title: title)) }
                    if model.message == nil { projectTitle = "" }
                }
            }
            ForEach(model.state.projects.filter { $0.deletedAt == nil }) { project in
                if wide {
                    Button {
                        selectedProject = project.id
                        selecting = false
                        selected.removeAll()
                    } label: {
                        Label(
                            project.title,
                            systemImage: selectedProject == project.id ? "folder.fill" : "folder")
                    }
                } else {
                    NavigationLink(project.title) { ProjectView(projectID: project.id) }
                }
            }
        }
    }
    @ViewBuilder private var importFeedback: some View {
        if model.isImporting {
            ProgressView("正在安全复制资料…").font(.caption)
        } else if let status = model.importStatus {
            Label(status, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func sourceList(includeProjects: Bool) -> some View {
        if coverLayout {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if includeProjects {
                        VStack(alignment: .leading, spacing: 10) { projectTree(wide: false) }.studyPanel()
                    }
                    StudyHeading(title: "资料")
                    collectionPicker
                    importFeedback
                    emptySources
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 13)], spacing: 17) {
                        ForEach(sources) { source in
                            if selecting {
                                ObjectSelectionRow(isSelected: selectedSource(source.id)) {
                                    StudySourceTile(source: source, asset: model.assetURL(source), compact: false)
                                }
                            } else { sourceLink(source, compact: false).buttonStyle(.plain) }
                        }
                    }
                }.padding(18)
            }.studySurface()
        } else {
            List {
                if includeProjects { projectTree(wide: false) }
                Section("资料") {
                    collectionPicker
                    importFeedback
                    emptySources
                    ForEach(sources) { source in
                        if selecting {
                            ObjectSelectionRow(isSelected: selectedSource(source.id)) {
                                StudySourceTile(source: source, asset: model.assetURL(source), compact: true)
                            }
                        } else { sourceLink(source, compact: true) }
                    }
                }
            }.studySurface()
        }
    }

    private func selectedSource(_ id: UUID) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { enabled in
            if enabled { selected.insert(id) }
            else { selected.remove(id) }
        })
    }

    @ViewBuilder private var emptySources: some View {
        if sources.isEmpty {
            Text(search.isEmpty ? "导入一本书，开始阅读。" : "没有找到资料").foregroundStyle(.secondary)
        }
    }

}

struct ProjectView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    private enum SectionKind: String, CaseIterable { case sources = "资料", cards = "卡片", maps = "地图", relations = "关系" }
    @State private var section = SectionKind.sources
    @State private var showProjectCovers = true
    @State private var managingLinks = false
    @State private var title = ""
    @State private var note = ""
    @State private var choosingCover = false
    private var project: LibraryProject? { model.state.projects.first { $0.id == projectID } }

    var body: some View {
        List {
            if let project {
                header(project)
                if managingLinks {
                    membership(project)
                } else {
                    Picker("项目内容", selection: $section) {
                        ForEach(SectionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    projectContent(project)
                }
            }
        }.studySurface()
            .navigationTitle(project?.title ?? "项目").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button(managingLinks ? "完成关联" : "管理关联") { managingLinks.toggle() }
            }
            .fileImporter(isPresented: $choosingCover, allowedContentTypes: [.image]) { result in
                do { saveBoardCover(try StudyCoverImport.read(result.get())) }
                catch { model.message = error.localizedDescription }
            }.onAppear {
                if let project { title = project.title; note = project.note }
            }
    }

    private func header(_ project: LibraryProject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(project.title).font(.system(.largeTitle, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if !project.note.isEmpty { Text(project.note).foregroundStyle(.secondary) }
            DisclosureGroup("编辑项目说明") {
                TextField("名称", text: $title)
                TextField("描述", text: $note, axis: .vertical)
                Button("保存") {
                    model.change { state in
                        if let index = state.projects.firstIndex(where: { $0.id == projectID }) {
                            guard !title.isEmpty else { throw LibraryError.invalid("项目名称不能为空") }
                            state.projects[index].title = title
                            state.projects[index].note = note
                        }
                    }
                }
            }
        }.studyPanel().listRowBackground(Color.clear)
    }

    @ViewBuilder private func projectContent(_ project: LibraryProject) -> some View {
        switch section {
        case .sources:
            Section("资料分组") {
                NavigationLink("管理自定义分组") { ProjectGroupsView(projectID: projectID) }
                ForEach(project.groups ?? []) { group in
                    DisclosureGroup(group.title) {
                        ForEach(projectSources(group.sourceIDs)) { sourceRow($0) }
                        if group.sourceIDs.isEmpty { Text("此组没有资料。").foregroundStyle(.secondary) }
                    }
                }
            }
            let sources = projectSources(project.sourceIDs)
            let recent = sources.filter { $0.lastReadAt != nil }.sorted {
                ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast)
            }.prefix(3)
            if !recent.isEmpty {
                DisclosureGroup("最近打开") { ForEach(recent) { sourceRow($0) } }
            }
            Section("全部项目资料") {
                Toggle("封面视图", isOn: $showProjectCovers)
                if showProjectCovers {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 14) {
                        ForEach(sources) { source in
                            NavigationLink {
                                SourceReaderView(source: source, location: source.lastLocation)
                            } label: {
                                StudySourceTile(source: source, asset: model.assetURL(source))
                            }.buttonStyle(.plain)
                        }
                    }.listRowBackground(Color.clear)
                } else {
                    ForEach(sources) { sourceRow($0) }
                }
            }
        case .cards:
            Section("项目卡片") {
                let linked = Set(project.cardIDs)
                ForEach(model.state.cards.filter { $0.deletedAt == nil && linked.contains($0.id) }
                    .sorted { $0.updatedAt > $1.updatedAt }) { card in
                    NavigationLink { CardDetailView(cardID: card.id) } label: { StudyCardFace(card: card) }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        case .maps:
            NavigationLink { ProjectBoardView(projectID: projectID) } label: {
                VStack(alignment: .leading, spacing: 9) {
                    StudyBoardCover(project: project)
                    Label("研究白板", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.system(.headline, design: .serif))
                    if let board = project.board {
                        Text("\(board.nodes.count) 个节点 · \(board.edges.count) 条连线").font(.caption)
                    }
                }
            }.contextMenu {
                Button("更换白板封面") { choosingCover = true }
                if project.boardCoverImage != nil { Button("恢复白板预览") { saveBoardCover(nil) } }
            }
        case .relations:
            projectRelations(project)
        }
    }

    @ViewBuilder private func projectRelations(_ project: LibraryProject) -> some View {
        let cardIndex = Dictionary(uniqueKeysWithValues: model.state.cards.map { ($0.id, $0) })
        let relations = model.state.relations.filter { $0.deletedAt == nil && project.relationIDs.contains($0.id) }
        Section("卡片关系") {
            if relations.isEmpty { Text("此项目暂无已关联的卡片关系。").foregroundStyle(.secondary) }
            ForEach(relations) { relation in
                VStack(alignment: .leading, spacing: 8) {
                    Text(studioLabel(relation.kind)).font(.caption.weight(.semibold)).foregroundStyle(StudyTheme.ink)
                    relationEndpoint(cardIndex[relation.from])
                    relationEndpoint(cardIndex[relation.to])
                    if !relation.note.isEmpty { Text(relation.note).foregroundStyle(.secondary) }
                }.studyPanel().listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder private func relationEndpoint(_ card: LibraryCard?) -> some View {
        if let card, card.deletedAt == nil {
            NavigationLink(card.title) { CardDetailView(cardID: card.id) }
        } else { Text("卡片当前不可用").foregroundStyle(.secondary) }
    }

    private func projectSources(_ ids: [UUID]) -> [LibrarySource] {
        let ids = Set(ids)
        return model.state.sources.filter { $0.deletedAt == nil && ids.contains($0.id) }
    }

    private func sourceRow(_ source: LibrarySource) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            NavigationLink {
                SourceReaderView(source: source, location: source.lastLocation)
            } label: {
                StudySourceTile(source: source, asset: model.assetURL(source), compact: true)
            }
            NavigationLink("项目研究笔记") {
                ProjectSourceNoteView(projectID: projectID, sourceID: source.id)
            }.font(.caption)
        }
    }

    private func saveBoardCover(_ data: Data?) {
        model.change { state in
            guard let index = state.projects.firstIndex(where: { $0.id == projectID && $0.deletedAt == nil }) else {
                throw LibraryError.invalid("项目已不可用")
            }
            state.projects[index].boardCoverImage = data
        }
    }

    @ViewBuilder private func membership(_ project: LibraryProject) -> some View {
        Section("关联资料") {
            ForEach(model.state.sources.filter { $0.deletedAt == nil }) { source in
                ObjectSelectionRow(
                    source.title,
                    isSelected: Binding(
                        get: { project.sourceIDs.contains(source.id) },
                        set: { enabled in
                            model.change { state in
                                if let i = state.projects.firstIndex(where: { $0.id == projectID }
                                ) {
                                    state.projects[i].sourceIDs.removeAll { $0 == source.id }
                                    if enabled { state.projects[i].sourceIDs.append(source.id) }
                                }
                            }
                        }))
            }
        }
        Section("关联卡片") {
            ForEach(model.state.cards.filter { $0.deletedAt == nil }) { card in
                ObjectSelectionRow(
                    card.title,
                    isSelected: Binding(
                        get: { project.cardIDs.contains(card.id) },
                        set: { enabled in
                            model.change { state in
                                if let i = state.projects.firstIndex(where: { $0.id == projectID }
                                ) {
                                    state.projects[i].cardIDs.removeAll { $0 == card.id }
                                    if enabled { state.projects[i].cardIDs.append(card.id) }
                                }
                            }
                        }))
            }
        }
        Text("解除关联只影响项目，不删除卡片或资料。").font(.caption)
    }
}

struct DataManagerView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var trash = false
    @State private var kind = "全部"
    @State private var search = ""
    @State private var selected: Set<UUID> = []
    @State private var confirming = false
    @State private var permanent = false
    @State private var backup: URL?
    @State private var restoring = false
    @State private var busy = false
    @State private var confirmCleanup = false
    @State private var showCleanup = false
    @State private var confirmCacheCleanup = false
    @State private var orphanFiles: [URL] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var fileSizes: [URL: Int64] = [:]
    @State private var cacheBytes: Int64 = 0
    @State private var orphanBytes: Int64 = 0
    @State private var databaseBytes: Int64 = 0
    @State private var recoveryBytes: Int64 = 0
    @State private var sort = "类型"
    @State private var refreshStorage = UUID()

    private struct StorageKey: Equatable {
        let files: Set<URL>
        let refresh: UUID
    }

    private var storageKey: StorageKey {
        StorageKey(files: Set(model.state.sources.compactMap { model.assetURL($0) }), refresh: refreshStorage)
    }
    @State private var validated: BackupService.Validated?
    @State private var confirmRestore = false
    struct Row: Identifiable {
        let id: UUID
        let title: String
        let kind: String
        let deleted: Bool
    }
    var rows: [Row] {
        var all: [Row] = model.state.sources.map {
            Row(id: $0.id, title: $0.title, kind: "资料", deleted: $0.deletedAt != nil)
        }
        all += model.state.marks.map {
            Row(
                id: $0.id, title: $0.excerpt.isEmpty ? locationLabel($0.locator) : $0.excerpt, kind: "标记",
                deleted: $0.deletedAt != nil)
        }
        all += model.state.cards.map {
            Row(id: $0.id, title: $0.title, kind: "卡片", deleted: $0.deletedAt != nil)
        }
        all += model.state.projects.map {
            Row(id: $0.id, title: $0.title, kind: "项目", deleted: $0.deletedAt != nil)
        }
        all += model.state.relations.map {
            Row(id: $0.id, title: $0.kind, kind: "关系", deleted: $0.deletedAt != nil)
        }
        all += model.state.reviewRecords.map {
            Row(
                id: $0.id, title: "\($0.rating) · \($0.reviewedAt.formatted())", kind: "复习记录",
                deleted: $0.deletedAt != nil)
        }
        let filtered = all.filter {
            $0.deleted == trash && (kind == "全部" || $0.kind == kind)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
        if sort == "名称" { return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        return filtered
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= 830 {
                    HStack(spacing: 0) {
                        List { storageSummary; objectSummary }.studySurface().frame(width: 285)
                        Divider()
                        objectList(showStorage: false)
                    }
                } else {
                    objectList(showStorage: true)
                }
            }.navigationTitle("数据管理").searchable(text: $search)
                .toolbar { EditButton() }
                .onChange(of: kind) { _, _ in selected.removeAll() }
                .onChange(of: search) { _, _ in selected.removeAll() }
        }.confirmationDialog(
            permanent ? "永久清理不可撤销，确认已备份？" : "将所选对象移入回收站？",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(permanent ? "永久清理" : "移入回收站", role: .destructive) {
                model.delete(selected, permanently: permanent)
                if model.message == nil { selected = [] }
                refreshStorage = UUID()
            }
        }.confirmationDialog("清除可重新生成的缩略图缓存？", isPresented: $confirmCacheCleanup) {
            Button("清理缓存", role: .destructive) {
                do { try StudyThumbnails.clearCache(); refreshStorage = UUID() }
                catch { model.message = error.localizedDescription }
            }
        }.sheet(isPresented: $showCleanup) { cleanupSheet }
        .task(id: storageKey.refresh) { await readStorage() }
        .onChange(of: storageKey.files) { _, _ in refreshStorage = UUID() }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.zip]) { result in
            busy = true
            Task {
                do {
                    validated = try await BackupService.validate(result.get())
                    confirmRestore = true
                } catch { model.message = error.localizedDescription }
                busy = false
            }
        }.confirmationDialog(
            "校验通过。替换为备份中的 \(validated?.state.cards.count ?? 0) 张卡片、\(validated?.state.marks.count ?? 0) 条标记？",
            isPresented: $confirmRestore, titleVisibility: .visible
        ) {
            Button("确认恢复并替换当前知识库", role: .destructive) {
                guard let validated else { return }
                busy = true
                Task {
                    do { try await BackupService.restore(validated, model: model) } catch {
                        model.message = error.localizedDescription
                    }
                    try? FileManager.default.removeItem(at: validated.directory)
                    self.validated = nil
                    busy = false
                    refreshStorage = UUID()
                }
            }
            Button("取消", role: .cancel) {
                if let validated { try? FileManager.default.removeItem(at: validated.directory) }
                validated = nil
            }
        }
    }

    private func objectList(showStorage: Bool) -> some View {
        List(selection: $selected) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        StudyHeading(title: trash ? "回收站" : "知识库维护")
                        Label("\(rows.count) 个对象", systemImage: trash ? "trash" : "externaldrive")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.studyPanel()
                }.listRowBackground(Color.clear)
                if showStorage {
                    storageSummary
                    objectSummary
                }
                DisclosureGroup("备份与恢复") {
                    Button(busy ? "正在处理…" : "生成完整备份 ZIP") {
                        busy = true
                        Task {
                            do { backup = try await BackupService.export(model: model) } catch {
                                model.message = error.localizedDescription
                            }
                            busy = false
                        }
                    }.disabled(busy)
                    if let backup { ShareLink("导出备份", item: backup) }
                    Button("选择备份并校验") { restoring = true }.disabled(busy)
                }
                Picker("内容范围", selection: $trash) {
                    Text("知识库").tag(false)
                    Text("回收站").tag(true)
                }.pickerStyle(.segmented).onChange(of: trash) { _, _ in selected = [] }
                Picker("类型", selection: $kind) {
                    ForEach(["全部", "资料", "标记", "卡片", "项目", "关系", "复习记录"], id: \.self) { Text($0) }
                }
                Picker("排序", selection: $sort) {
                    Text("按类型").tag("类型")
                    Text("按名称").tag("名称")
                }
                Section("对象") {
                    ForEach(rows) { row in
                        NavigationLink {
                            managedContent(row)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).lineLimit(3)
                                Text(row.kind).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tag(row.id)
                    }
                }
                if !selected.isEmpty {
                    Section("操作影响") {
                        ForEach(Array(selected), id: \.self) { Text(model.impact(of: $0)).font(.caption) }
                        if trash {
                            Button("恢复所选") {
                                model.delete(selected, restore: true)
                                selected = []
                            }
                            Button("永久清理所选", role: .destructive) {
                                permanent = true
                                confirming = true
                            }
                        } else {
                            Button("移回待整理") {
                                model.change { state in
                                    for i in state.cards.indices where selected.contains(state.cards[i].id) {
                                        state.cards[i].organization = .inbox
                                    }
                                    for i in state.marks.indices where selected.contains(state.marks[i].id) {
                                        state.marks[i].organization = .inbox
                                    }
                                }
                                selected = []
                            }
                            Button("归档所选卡片与标记") {
                                model.change { state in
                                    for i in state.cards.indices where selected.contains(state.cards[i].id) {
                                        state.cards[i].organization = .archived
                                    }
                                    for i in state.marks.indices where selected.contains(state.marks[i].id) {
                                        state.marks[i].organization = .archived
                                    }
                                }
                                selected = []
                            }
                            Button("移入回收站", role: .destructive) {
                                permanent = false
                                confirming = true
                            }
                        }
                    }
                }
        }.studySurface()
    }

    private var objectSummary: some View {
        let counts = [
            ("资料", model.state.sources.lazy.filter { $0.deletedAt == nil }.count),
            ("标记", model.state.marks.lazy.filter { $0.deletedAt == nil }.count),
            ("卡片", model.state.cards.lazy.filter { $0.deletedAt == nil }.count),
            ("项目", model.state.projects.lazy.filter { $0.deletedAt == nil }.count),
            ("关系", model.state.relations.lazy.filter { $0.deletedAt == nil }.count),
            ("复习记录", model.state.reviewRecords.lazy.filter { $0.deletedAt == nil }.count),
        ]
        let peak = max(1, counts.map { $0.1 }.max() ?? 1)
        return Section("知识库对象") {
            ForEach(counts, id: \.0) { name, count in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent(name, value: "\(count)")
                    ProgressView(value: Double(count), total: Double(peak))
                        .tint(StudyTheme.copper).accessibilityHidden(true)
                }
            }
        }
    }

    private var storageSummary: some View {
        let sources = fileSizes.values.reduce(0, +)
        let breakdown = [
            (title: "资料文件（去重）", bytes: sources, color: StudyTheme.ink),
            (title: "数据库", bytes: databaseBytes, color: StudyTheme.copper),
            (title: "恢复前快照", bytes: recoveryBytes, color: Color.indigo),
            (title: "待核对的资料文件", bytes: orphanBytes, color: Color.orange),
            (title: "缩略图缓存", bytes: cacheBytes, color: Color.teal),
        ]
        let total = breakdown.reduce(Int64(0)) { $0 + $1.bytes }
        return Section("本地存储") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("合计", value: ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    .font(.headline)
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(breakdown, id: \.title) { item in
                            Rectangle().fill(item.color)
                                .frame(width: geometry.size.width * Double(item.bytes) / Double(max(1, total)))
                        }
                    }
                }.frame(height: 7).background(StudyTheme.rule).clipShape(Capsule()).accessibilityHidden(true)
                ForEach(breakdown, id: \.title) { item in
                    Label {
                        LabeledContent(item.title, value: ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                    } icon: { Circle().fill(item.color).frame(width: 7, height: 7) }
                        .font(.caption)
                }
            }
            Button("检查未引用的文件") {
                do {
                    orphanFiles = try model.unusedAssets().sorted { $0.lastPathComponent < $1.lastPathComponent }
                    selectedFiles.removeAll()
                    showCleanup = true
                } catch { model.message = error.localizedDescription }
            }.disabled(model.isImporting || busy)
            Button("清理缩略图缓存") { confirmCacheCleanup = true }.disabled(cacheBytes == 0)
        }
    }

    private var cleanupSheet: some View {
        NavigationStack {
            List {
                if orphanFiles.isEmpty {
                    ContentUnavailableView("没有可清理文件", systemImage: "checkmark.circle")
                }
                ForEach(orphanFiles, id: \.self) { file in
                    ObjectSelectionRow(isSelected: Binding(get: { selectedFiles.contains(file) }, set: {
                        if $0 { selectedFiles.insert(file) } else { selectedFiles.remove(file) }
                    })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text("知识库、回收站和恢复快照均无引用").font(.caption).foregroundStyle(.secondary)
                            if let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.caption)
                            }
                        }
                    }
                }
            }.studySurface().navigationTitle("清理未引用文件")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { showCleanup = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("删除所选", role: .destructive) { confirmCleanup = true }.disabled(selectedFiles.isEmpty)
                    }
                }
                .confirmationDialog("永久删除所选的 \(selectedFiles.count) 个文件？", isPresented: $confirmCleanup) {
                    Button("确认清理", role: .destructive) {
                        model.cleanUnusedAssets(selectedFiles)
                        if model.message == nil { showCleanup = false }
                        refreshStorage = UUID()
                    }
                }
        }
    }

    private func readStorage() async {
        let urls = storageKey.files
        let cache = StudyThumbnails.cacheDirectory
        let root = model.root
        let result = await Task.detached(priority: .utility) {
            func size(_ url: URL) -> Int64? {
                let metadata = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard metadata?.isRegularFile == true, metadata?.isSymbolicLink != true else { return nil }
                return Int64(metadata?.fileSize ?? 0)
            }
            func fileList(_ directory: URL?) -> [URL] {
                directory.flatMap {
                    try? FileManager.default.contentsOfDirectory(at: $0,
                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                } ?? []
            }
            let files = fileList(root.appendingPathComponent("assets", isDirectory: true))
            let known = Dictionary(uniqueKeysWithValues: urls.compactMap { url in size(url).map { (url, $0) } })
            let filenames = Set(urls.map(\.lastPathComponent))
            let untracked = files.filter { !filenames.contains($0.lastPathComponent) }.compactMap(size).reduce(0, +)
            let cached = fileList(cache).compactMap(size).reduce(0, +)
            let rootFiles = fileList(root)
            let db = rootFiles.filter { $0.lastPathComponent.hasPrefix("library.sqlite") }.compactMap(size).reduce(0, +)
            let recovery = rootFiles.filter { $0.lastPathComponent.hasPrefix("before-restore-") }
                .compactMap(size).reduce(0, +)
            return (known, untracked, cached, db, recovery)
        }.value
        guard !Task.isCancelled else { return }
        (fileSizes, orphanBytes, cacheBytes, databaseBytes, recoveryBytes) = result
    }

    @ViewBuilder private func managedContent(_ row: Row) -> some View {
        if row.deleted {
            VStack(spacing: 16) {
                Text(row.title).font(.title3)
                Text("此内容在回收站中。返回后点选择可恢复或永久清理。").foregroundStyle(.secondary)
            }.padding()
        } else if let source = model.state.sources.first(where: { $0.id == row.id }) {
            SourceReaderView(source: source, location: source.lastLocation)
        } else if model.state.cards.contains(where: { $0.id == row.id }) {
            CardDetailView(cardID: row.id)
        } else if model.state.marks.contains(where: { $0.id == row.id }) {
            MarkDetailView(markID: row.id)
        } else if model.state.projects.contains(where: { $0.id == row.id }) {
            ProjectView(projectID: row.id)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(row.title).font(.title3)
                Text(model.impact(of: row.id))
            }.padding()
        }
    }

}
