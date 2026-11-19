import SwiftUI
import UniformTypeIdentifiers
import KnowledgeCore

struct StudioView: View {
    @StateObject private var model = StudioModel()
    @Environment(\.scenePhase) private var phase
    @State private var quickCard = false
    @AppStorage("appAppearance") private var appearance = "system"
    var body: some View {
        TabView {
            InboxView().tabItem { Label("My Inbox", systemImage: "tray") }
            CardsView().tabItem { Label("卡片", systemImage: "rectangle.stack") }
            LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
            AIInboxView().tabItem { Label("AI Inbox", systemImage: "tray.and.arrow.down") }
            DataManagerView().tabItem { Label("数据管理", systemImage: "externaldrive") }
            ExtensionSetupView().tabItem { Label("设置", systemImage: "gearshape") }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .environmentObject(model)
        .overlay(alignment: .bottomTrailing) {
            Button { quickCard = true } label: { Image(systemName: "plus").font(.title2).padding().background(.tint, in: Circle()).foregroundStyle(.white) }
                .accessibilityLabel("快速建卡").padding(.bottom, 70).padding(.trailing, 20)
        }
        .sheet(isPresented: $quickCard) { CardEditor(card: LibraryCard(type: .keyword, content: [:])).environmentObject(model) }
        .alert("提示", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("知道了") { model.message = nil } } message: { Text(model.message ?? "") }
        .onChange(of: phase) { _, value in if value == .active { model.refresh() } }
    }
}

struct InboxView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var search = ""
    @State private var editor: LibraryCard?
    var marks: [LibraryMark] { model.state.marks.filter { $0.deletedAt == nil && $0.organization == .inbox && (search.isEmpty || ($0.excerpt + $0.note + sourceTitle($0)).localizedCaseInsensitiveContains(search)) }.sorted { $0.createdAt > $1.createdAt } }
    func sourceTitle(_ mark: LibraryMark) -> String { model.state.sources.first { $0.id == mark.sourceID }?.title ?? "资料不可用" }
    var body: some View {
        NavigationStack {
            List {
                if let warning = model.sharedWarning { Text(warning).foregroundStyle(.orange) }
                if marks.isEmpty { ContentUnavailableView("没有待整理标记", systemImage: "tray", description: Text("在 Safari、PDF、EPUB 或本地视频中保存 Mark。")) }
                ForEach(marks) { mark in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sourceTitle(mark)).font(.headline)
                        if !mark.excerpt.isEmpty { Text(mark.excerpt).lineLimit(5) }
                        if !mark.note.isEmpty { Text(mark.note).foregroundStyle(.secondary) }
                        Text(locationLabel(mark.locator)).font(.caption)
                        HStack {
                            Menu("整理为卡片") { ForEach(CardKind.allCases, id: \.self) { kind in Button(kind.rawValue) { editor = model.card(from: mark, type: kind) } } }
                            if let source = model.state.sources.first(where: { $0.id == mark.sourceID && $0.deletedAt == nil }) { NavigationLink("回到出处") { SourceReaderView(source: source, location: mark.locator) } }
                            Button("归档") { model.change { state in if let i = state.marks.firstIndex(where: { $0.id == mark.id }) { state.marks[i].organization = .archived } } }
                        }.buttonStyle(.borderless)
                        NavigationLink("备注与详情") { MarkDetailView(markID: mark.id) }
                    }.padding(.vertical, 4)
                }
            }.navigationTitle("My Inbox").searchable(text: $search).refreshable { model.refresh() }
                .toolbar { Button("接收 Safari 标记") { model.refresh() } }
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
    var body: some View {
        Form {
            if let mark = model.state.marks.first(where: { $0.id == markID }) {
                Text(mark.excerpt); Text(locationLabel(mark.locator))
                TextField("个人备注", text: $note, axis: .vertical)
                Button("保存备注") { model.setMarkNote(id: markID, note: note) }
                Text(mark.id.uuidString).font(.caption).textSelection(.enabled)
            }
        }.navigationTitle("Mark 详情").onAppear { note = model.state.marks.first { $0.id == markID }?.note ?? "" }
    }
}

struct CardsView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var search = "", category = "全部"
    @State private var editor: LibraryCard?
    var cards: [LibraryCard] { model.state.cards.filter { card in card.deletedAt == nil && (category == "全部" || (category == "Dictionary" ? [.word, .keyword].contains(card.type) : [.expression, .key_sentence].contains(card.type))) && (search.isEmpty || (card.title + card.note + card.tags.joined(separator: " ")).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        NavigationStack {
            List {
                Picker("视图", selection: $category) { ForEach(["全部", "Dictionary", "Corpus"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                ForEach(cards) { card in NavigationLink { CardDetailView(cardID: card.id) } label: {
                    VStack(alignment: .leading) {
                        Text(card.type == .word ? card.content["example_en"] ?? "" : card.title).lineLimit(3)
                        if card.type == .word { Text(card.content["definition_en"] ?? "").foregroundStyle(.secondary) }
                        Text("\(card.type.rawValue) · \(card.organization.rawValue) · \(card.review.rawValue)").font(.caption)
                    }
                } }
            }.navigationTitle("卡片").searchable(text: $search)
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
                Picker("类型", selection: $card.type) { ForEach(CardKind.allCases, id: \.self) { Text($0.rawValue) } }
                ForEach(LibraryCard.fields(for: card.type), id: \.self) { field in
                    TextField(field, text: Binding(get: { card.content[field] ?? "" }, set: { value in
                        card.content[field] = value
                        card.provenance[field] = FieldOrigin(kind: "user_input")
                    }), axis: .vertical)
                }
                TextField("语言", text: $card.language)
                TextField("标签（逗号分隔）", text: $tags)
                TextField("个人笔记", text: $card.note, axis: .vertical)
                Picker("整理状态", selection: $card.organization) { ForEach(Organization.allCases, id: \.self) { Text($0.rawValue) } }
                Picker("复习状态（由你选择）", selection: $card.review) { ForEach(ReviewStatus.allCases, id: \.self) { Text($0.rawValue) } }
                Text("复习调度与每日任务将在产品阶段 6 接入。") .font(.caption)
                Picker("关联项目", selection: $project) {
                    Text("不新增项目关联").tag(nil as UUID?)
                    ForEach(model.state.projects.filter { $0.deletedAt == nil }) { Text($0.title).tag(Optional($0.id)) }
                }
                if !card.sourceRefs.isEmpty { Text("已保留 \(card.sourceRefs.count) 个出处和 \(card.markIDs.count) 个 Mark 关联。") }
            }.navigationTitle("编辑卡片")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") {
                        let allowed = Set(LibraryCard.fields(for: card.type))
                        card.content = card.content.filter { allowed.contains($0.key) && !$0.value.isEmpty }
                        card.provenance = card.provenance.filter { allowed.contains($0.key) || $0.key == "import_annotation" }
                        for field in card.content.keys where card.provenance[field] == nil { card.provenance[field] = FieldOrigin(kind: "user_input") }
                        card.tags = Array(Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
                        card.updatedAt = Date(); model.message = nil; model.saveCard(card, project: project)
                        if model.message == nil { dismiss() }
                    } }
                }
        }.onAppear { tags = card.tags.joined(separator: ", ") }
    }
}

struct CardDetailView: View {
    @EnvironmentObject private var model: StudioModel
    let cardID: UUID
    @State private var editor: LibraryCard?
    var body: some View {
        Form {
            if let card = model.state.cards.first(where: { $0.id == cardID }) {
                ForEach(LibraryCard.fields(for: card.type), id: \.self) { field in
                    if let value = card.content[field] { Section(field) { Text(value).textSelection(.enabled); Text(card.provenance[field]?.kind ?? "user_input").font(.caption).foregroundStyle(.secondary) } }
                }
                Section("笔记") { Text(card.note); if !card.importAnnotation.isEmpty { Text("导入说明：\(card.importAnnotation)") } }
                Section("出处") { ForEach(card.sourceRefs) { ref in
                    if let source = model.state.sources.first(where: { $0.id == ref.sourceID }) {
                        if source.deletedAt == nil { NavigationLink(source.title) { SourceReaderView(source: source, location: ref.locator) } }
                        else { Text("\(source.title)（在回收站）") }
                    }
                } }
                Section("关联 Mark") { ForEach(card.markIDs, id: \.self) { id in NavigationLink(id.uuidString) { MarkDetailView(markID: id) } } }
                Section("词典外链") { Link("Wiktionary", destination: URL(string: "https://en.wiktionary.org/wiki/" + card.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!) }
                Button("编辑") { editor = card }
            }
        }.navigationTitle("卡片详情").sheet(item: $editor) { CardEditor(card: $0).environmentObject(model) }
    }
}
