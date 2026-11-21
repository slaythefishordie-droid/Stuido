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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("导入箱").font(.system(.largeTitle, design: .serif, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    importDesk
                    if editingJSON { pasteArea }
                    VStack(alignment: .leading, spacing: 12) {
                        StudyHeading(title: "待确认批次")
                        if model.state.pending.isEmpty {
                            Label("暂无待确认批次", systemImage: "tray").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(model.state.pending) { item in
                            Button { pending = item } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "doc.text").foregroundStyle(StudyTheme.copper)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.system(.headline, design: .serif))
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.studyPanel()
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(24).frame(maxWidth: 810).frame(maxWidth: .infinity)
            }.studySurface().navigationBarTitleDisplayMode(.inline)
        }.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { receiveFile(try result.get()) }
            catch { model.message = error.localizedDescription }
        }.sheet(item: $pending) { ImportReviewView(pending: $0).environmentObject(model) }
    }

    private var importDesk: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "tray.and.arrow.down").font(.title).foregroundStyle(StudyTheme.copper)
            StudyHeading(title: "导入卡片包")
            HStack(spacing: 12) {
                Button("选择 JSON 文件") { importing = true }.buttonStyle(.borderedProminent)
                Button(editingJSON ? "收起粘贴区" : "粘贴 JSON") { editingJSON.toggle() }.buttonStyle(.bordered)
            }.disabled(staging)
            if staging { ProgressView("正在读取并校验…").font(.caption) }
        }.frame(maxWidth: .infinity, minHeight: 140, alignment: .leading).studyPanel()
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, url.isFileURL, url.pathExtension.lowercased() == "json", !staging else { return false }
                receiveFile(url)
                return true
            }
    }

    private var pasteArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text).frame(minHeight: 112).font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden).accessibilityLabel("JSON 内容")
            Button("校验并预览") {
                let input = text
                staging = true
                Task {
                    defer { staging = false }
                    if let item = await model.stageImport(input) {
                        text = ""
                        pending = item
                    }
                }
            }.buttonStyle(.bordered).disabled(staging || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.studyPanel()
    }

    private func receiveFile(_ url: URL) {
        guard !staging else { return }
        staging = true
        Task {
            defer { staging = false }
            do {
                let contents = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let limit = 10 * 1024 * 1024
                    let file = try FileHandle(forReadingFrom: url)
                    defer { try? file.close() }
                    let data = try file.read(upToCount: limit + 1) ?? Data()
                    guard data.count <= limit, let text = String(data: data, encoding: .utf8) else {
                        throw LibraryError.invalid("请选择 10 MiB 以内的 UTF-8 JSON 文件")
                    }
                    return text
                }.value
                pending = await model.stageImport(contents)
            } catch { model.message = error.localizedDescription }
        }
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
    @State private var writing = false
    @State private var writeError: String?
    @State private var rawSources: [[String: String]] = []

    var body: some View {
        NavigationStack {
            Form {
                if let writeError { Text(writeError).foregroundStyle(StudyTheme.copper) }
                if writing { ProgressView("正在导入所选卡片…") }
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
                    Button("确认导入所选卡片") { confirm = true }.disabled(selected.isEmpty || writing)
                }
            }.studySurface().navigationTitle(pending.title).toolbar { Button("关闭") { dismiss() } }
        }.interactiveDismissDisabled(writing).task {
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
                    guard let preview, !writing else { return }
                    let ids = selected
                    let projectID = project
                    writing = true
                    writeError = nil
                    Task {
                        defer { writing = false }
                        do {
                            try await model.commitImport(preview, selected: ids, projectID: projectID, pendingID: pending.id)
                            dismiss()
                        } catch { writeError = error.localizedDescription }
                    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var coverMotion
    @State private var importing = false
    @State private var search = ""
    @State private var projectTitle = ""
    @State private var selectedProject: UUID?
    @State private var coverSourceID: UUID?
    @State private var renamingSource: UUID?
    @State private var newSourceTitle = ""
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
            }.studySurface().navigationTitle("资料库").searchable(text: $search, prompt: "搜索资料")
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
        }.alert("重命名资料", isPresented: Binding(get: { renamingSource != nil }, set: {
            if !$0 { renamingSource = nil }
        })) {
            TextField("显示名称", text: $newSourceTitle)
            Button("保存") {
                if let renamingSource { model.renameSource(renamingSource, title: newSourceTitle) }
                renamingSource = nil
            }
            Button("取消", role: .cancel) { renamingSource = nil }
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
        Button("重命名", systemImage: "pencil") {
            newSourceTitle = source.title
            renamingSource = source.id
        }
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
                .studioTransitionDestination(source.id, in: coverMotion, enabled: !reduceMotion)
        } label: {
            StudySourceTile(source: source, asset: model.assetURL(source), compact: compact)
                .studioTransitionSource(source.id, in: coverMotion, enabled: !reduceMotion)
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
            HStack {
                ProgressView()
                Text(model.importStatus ?? "正在导入资料…")
                if model.importCanCancel { Button("取消导入") { model.cancelImport() } }
            }.font(.caption)
        } else if let status = model.importStatus {
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        if !model.sharedDocuments.isEmpty {
            DisclosureGroup("来自分享菜单 · \(model.sharedDocuments.count)") {
                ForEach(model.sharedDocuments) { entry in
                    Button(entry.filename, systemImage: "square.and.arrow.down") {
                        Task { await model.acceptSharedDocument(entry) }
                    }.disabled(model.isImporting)
                }
            }
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
                    StudyCardPreview(card: card)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
        case .maps:
            if project.boardTrashedAt != nil {
                Text("白板在回收站").foregroundStyle(.secondary)
            } else {
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
    @State private var selecting = false
    @State private var moving = false
    private enum Decision { case trash, purge, cache, backup }
    @State private var decision: Decision?
    @State private var affected: Set<UUID> = []
    @State private var backup: URL?
    @State private var restoring = false
    @State private var busy = false
    @State private var confirmCleanup = false
    @State private var showCleanup = false
    @State private var orphanFiles: [URL] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var fileSizes: [URL: Int64] = [:]
    @State private var cacheBytes: Int64 = 0
    @State private var orphanBytes: Int64 = 0
    @State private var databaseBytes: Int64 = 0
    @State private var recoveryBytes: Int64 = 0
    @State private var objectBytes: [String: Int64] = [:]
    @State private var sort = "类型"
    @State private var refreshStorage = UUID()

    @State private var validated: BackupService.Validated?
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
        all += model.state.projects.filter { $0.hasBoard && ($0.deletedAt == nil || $0.boardTrashedAt != nil) }
            .map { Row(id: $0.boardManagementID, title: $0.title + " · 白板", kind: "白板",
                deleted: $0.boardTrashedAt != nil) }
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
            }.navigationTitle("数据管理").searchable(text: $search, prompt: "搜索对象")
                .toolbar {
                    Button(selecting ? "完成选择" : "选择") {
                        selecting.toggle()
                        selected.removeAll()
                    }.accessibilityIdentifier("storage.select")
                }
                .onChange(of: kind) { _, _ in selected.removeAll() }
                .onChange(of: search) { _, _ in selected.removeAll() }
        }.confirmationDialog(decisionTitle, isPresented: Binding(get: { decision != nil }, set: {
            if !$0 { decision = nil }
        }), titleVisibility: .visible) {
            switch decision {
            case .trash, .purge:
                let purge = decision == .purge
                Button(purge ? "永久删除" : "移入回收站", role: .destructive) {
                    apply(affected, purge: purge)
                }
            case .cache:
                Button("清理缓存", role: .destructive) {
                    do { try StudyThumbnails.clearCache(); refreshStorage = UUID() }
                    catch { model.message = error.localizedDescription }
                }
            case .backup:
                Button("恢复并替换当前知识库", role: .destructive) { restoreBackup() }
                Button("取消", role: .cancel) { clearBackup() }
            case nil: EmptyView()
            }
        } message: {
            if decision == .trash || decision == .purge {
                Text(affected.prefix(3).map { model.impact(of: $0) }.joined(separator: "\n"))
            }
        }.sheet(isPresented: $showCleanup) { cleanupSheet }
        .task(id: refreshStorage) { await readStorage() }
        .onReceive(model.$state.dropFirst()) { _ in refreshStorage = UUID() }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.zip]) { result in
            busy = true
            Task {
                do {
                    validated = try await BackupService.validate(result.get())
                    decision = .backup
                } catch { model.message = error.localizedDescription }
                busy = false
            }
        }
    }

    private var decisionTitle: String {
        switch decision {
        case .trash: "将 \(affected.count) 个对象移入回收站？"
        case .purge: "永久删除 \(affected.count) 个对象？"
        case .cache: "清理可重新生成的缩略图缓存？"
        case .backup: "用已校验的备份替换当前知识库？"
        case nil: ""
        }
    }

    private func ask(_ action: Decision, ids: Set<UUID>) {
        affected = ids
        decision = action
    }

    private func clearBackup() {
        if let validated { try? FileManager.default.removeItem(at: validated.directory) }
        validated = nil
    }

    private func restoreBackup() {
        guard let validated else { return }
        busy = true
        Task {
            defer { clearBackup(); busy = false; refreshStorage = UUID() }
            do { try await BackupService.restore(validated, model: model) }
            catch { model.message = error.localizedDescription }
        }
    }

    private func objectList(showStorage: Bool) -> some View {
        let visible = rows
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if showStorage {
                    VStack(alignment: .leading, spacing: 14) { storageSummary; objectSummary }.studyPanel()
                }
                HStack {
                    Picker("内容范围", selection: $trash) {
                        Text("知识库").tag(false)
                        Text("回收站").tag(true)
                    }.pickerStyle(.segmented).frame(maxWidth: 300)
                        .accessibilityIdentifier("storage.scope")
                        .onChange(of: trash) { _, _ in selected.removeAll() }
                    Spacer()
                    backupMenu
                }
                HStack {
                    StudyHeading(title: trash ? "回收站" : "知识库对象")
                    Text(visible.count.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Picker("类型", selection: $kind) {
                        ForEach(["全部", "资料", "标记", "卡片", "项目", "白板", "关系", "复习记录"], id: \.self) {
                            Text($0)
                        }
                    }.pickerStyle(.menu)
                    Picker("排序", selection: $sort) {
                        Text("按类型").tag("类型")
                        Text("按名称").tag("名称")
                    }.pickerStyle(.menu)
                }
                if moving { ProgressView("正在处理所选对象…").font(.subheadline) }
                if visible.isEmpty {
                    ContentUnavailableView(trash ? "回收站为空" : "没有匹配的对象",
                        systemImage: trash ? "trash" : "tray")
                }
                ForEach(visible) { row in dataRow(row) }
            }.padding(20)
        }.studySurface().studyChange(visible.count)
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty { bulkActions }
            }
    }

    private var backupMenu: some View {
        Menu {
            Button("生成完整备份 ZIP") {
                busy = true
                Task {
                    defer { busy = false }
                    do { backup = try await BackupService.export(model: model) }
                    catch { model.message = error.localizedDescription }
                }
            }.disabled(busy || moving)
            if let backup { ShareLink("导出备份", item: backup) }
            Button("选择备份并校验") { restoring = true }.disabled(busy || moving)
        } label: {
            Label(busy ? "正在准备" : "备份", systemImage: "archivebox")
        }
    }

    private func dataRow(_ row: Row) -> some View {
        HStack(spacing: 14) {
            if selecting {
                ObjectSelectionRow(isSelected: Binding(get: { selected.contains(row.id) }, set: { checked in
                    if checked { selected.insert(row.id) } else { selected.remove(row.id) }
                })) { rowTitle(row) }.accessibilityIdentifier("storage.row." + row.title)
            } else {
                NavigationLink { managedContent(row) } label: { rowTitle(row) }
                    .buttonStyle(.plain).accessibilityIdentifier("storage.row." + row.title)
            }
            if !selecting {
                if row.deleted {
                    Button { apply([row.id], restore: true) } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                            .font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("storage.restore." + row.title)
                }
                Menu {
                    if row.deleted {
                        Button("永久删除", role: .destructive) { ask(.purge, ids: [row.id]) }
                    } else {
                        Button("移入回收站", role: .destructive) { ask(.trash, ids: [row.id]) }
                    }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("对象操作").accessibilityIdentifier("storage.actions." + row.title)
            }
        }.padding(.horizontal, 12).background(StudyTheme.leaf)
            .overlay(alignment: .bottom) { Rectangle().fill(StudyTheme.rule).frame(height: 1).allowsHitTesting(false) }
            .disabled(moving)
    }

    private func rowTitle(_ row: Row) -> some View {
        HStack(spacing: 12) {
            Text(row.title).font(.subheadline.weight(.medium)).lineLimit(2)
            Spacer(minLength: 8)
            Text(row.kind).font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 61).contentShape(Rectangle())
    }

    private var bulkActions: some View {
        HStack(spacing: 13) {
            Text("已选 \(selected.count) 项").font(.subheadline)
            Spacer()
            if trash {
                Button("恢复所选") { apply(selected, restore: true) }.buttonStyle(.bordered)
                Button("永久删除", role: .destructive) { ask(.purge, ids: selected) }.buttonStyle(.bordered)
            } else {
                Menu("其它操作") {
                    Button("移回待整理") { organize(.inbox) }
                    Button("归档卡片与标记") { organize(.archived) }
                }
                Button("移入回收站", role: .destructive) { ask(.trash, ids: selected) }.buttonStyle(.bordered)
            }
        }.padding(12).background(StudyTheme.mat).disabled(moving)
    }

    private func organize(_ status: Organization) {
        model.change { state in
            for i in state.cards.indices where selected.contains(state.cards[i].id) { state.cards[i].organization = status }
            for i in state.marks.indices where selected.contains(state.marks[i].id) { state.marks[i].organization = status }
        }
        if model.message == nil { selected.removeAll() }
    }

    private func apply(_ ids: Set<UUID>, restore: Bool = false, purge: Bool = false) {
        guard !moving else { return }
        moving = true
        Task {
            defer { moving = false }
            if await model.deleteManaged(ids, restore: restore, permanently: purge) {
                selected.subtract(ids)
                refreshStorage = UUID()
            }
        }
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
                    if let bytes = objectBytes[name] {
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " 数据库内容")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
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
            Button("清理缩略图缓存") { decision = .cache }.disabled(cacheBytes == 0)
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
        let urls = Set(model.state.sources.compactMap { model.assetURL($0) })
        let snapshot = model.state
        let cache = StudyThumbnails.cacheDirectory
        let root = model.root
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
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
            let encoder = JSONEncoder()
            func contentSize<T: Encodable>(_ items: [T]) -> Int64 {
                guard let data = try? encoder.encode(items) else { return 0 }
                return Int64(max(0, data.count - 2))
            }
            let records = [
                "资料": contentSize(snapshot.sources.filter { $0.deletedAt == nil }),
                "标记": contentSize(snapshot.marks.filter { $0.deletedAt == nil }),
                "卡片": contentSize(snapshot.cards.filter { $0.deletedAt == nil }),
                "项目": contentSize(snapshot.projects.filter { $0.deletedAt == nil }),
                "关系": contentSize(snapshot.relations.filter { $0.deletedAt == nil }),
                "复习记录": contentSize(snapshot.reviewRecords.filter { $0.deletedAt == nil }),
            ]
            return (known, untracked, cached, db, recovery, records)
        }.value
        guard !Task.isCancelled else { return }
        (fileSizes, orphanBytes, cacheBytes, databaseBytes, recoveryBytes, objectBytes) = result
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
        } else if let project = model.state.projects.first(where: { $0.boardManagementID == row.id && $0.hasBoard }) {
            ProjectBoardView(projectID: project.id)
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
