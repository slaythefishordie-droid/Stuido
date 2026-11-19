import SwiftUI
import UniformTypeIdentifiers
import KnowledgeCore

struct AIInboxView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var text = ""
    @State private var importing = false
    @State private var pending: PendingImport?
    var body: some View {
        NavigationStack {
            List {
                Section("JSON 导入") {
                    TextEditor(text: $text).frame(minHeight: 150).font(.system(.body, design: .monospaced))
                    Button("选择 JSON 文件") { importing = true }
                    Button("校验并放入 AI Inbox") { model.stageImport(text) }.disabled(text.isEmpty)
                    Text("这里只创建待确认候选。预览、匹配资料并确认后才会加入卡片库。") .font(.caption)
                }
                Section("待确认批次") { ForEach(model.state.pending) { item in Button { pending = item } label: { VStack(alignment: .leading) { Text(item.title); Text(item.packageID).font(.caption) } } } }
            }.navigationTitle("AI Inbox")
        }.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let scope = url.startAccessingSecurityScopedResource(); defer { if scope { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); guard data.count <= 10 * 1024 * 1024 else { throw LibraryError.invalid("JSON 超过 10 MiB") }; text = String(decoding: data, as: UTF8.self) }
            catch { model.message = error.localizedDescription }
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
    var rawSources: [[String: String]] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(pending.json.utf8)) as? [String: Any], let sources = root["sources"] as? [[String: Any]] else { return [] }
        return sources.map { ["id": $0["id"] as? String ?? "", "title": $0["title"] as? String ?? "", "kind": $0["kind"] as? String ?? ""] }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("匹配已有资料") {
                    ForEach(rawSources, id: \.self) { source in
                        Picker(source["title"] ?? "", selection: Binding<UUID?>(get: { matches[source["id"]!] }, set: { matches[source["id"]!] = $0; preview = nil })) {
                            Text("按摘要／链接匹配，否则新建").tag(nil as UUID?)
                            ForEach(model.state.sources.filter { $0.deletedAt == nil && $0.kind.rawValue == source["kind"] }) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                    Button("生成预览") { load() }
                }
                if let preview {
                    Section("候选卡片（\(selected.count)/\(preview.cards.count)）") {
                        ForEach(preview.cards) { card in
                            Toggle(isOn: Binding(get: { selected.contains(card.id) }, set: { if $0 { selected.insert(card.id) } else { selected.remove(card.id) } })) {
                                VStack(alignment: .leading) {
                                    Text(card.title); Text(card.type.rawValue).font(.caption)
                                    ForEach(card.content.keys.sorted(), id: \.self) { field in Text("\(field)：\(card.content[field]!)").font(.caption) }
                                    if preview.duplicateCardIDs.contains(card.id) { Text("已有相同内容，默认跳过；勾选将新增副本。").foregroundStyle(.orange) }
                                }
                            }
                        }
                    }
                    Section("提示") { ForEach(Array(preview.warnings.enumerated()), id: \.offset) { Text($0.element).font(.caption) }; Text("关系仅在双方卡片都被选中时导入。导入说明不会写成个人笔记，不会自动加入复习。") }
                    Picker("项目", selection: $project) { Text("不关联项目").tag(nil as UUID?); ForEach(model.state.projects.filter { $0.deletedAt == nil }) { Text($0.title).tag(Optional($0.id)) } }
                    Button("确认导入所选卡片") { confirm = true }.disabled(selected.isEmpty)
                }
            }.navigationTitle(pending.title).toolbar { Button("关闭") { dismiss() } }
        }.onAppear { load() }
        .confirmationDialog("将所选候选写入知识库？", isPresented: $confirm, titleVisibility: .visible) {
            Button("导入") {
                guard let preview, let repository = model.repository else { return }
                model.message = nil
                model.perform { try ImportService.commit(preview, selected: selected, projectID: project, pendingID: pending.id, to: repository) }
                if model.message == nil { dismiss() }
            }
        }
    }
    private func load() {
        do { let value = try ImportService.preview(pending.json, existing: model.state, sourceMatches: matches); preview = value; selected = Set(value.cards.map(\.id)).subtracting(value.duplicateCardIDs) }
        catch { model.message = error.localizedDescription; preview = nil }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: StudioModel
    @State private var importing = false
    @State private var search = ""
    @State private var projectTitle = ""
    var body: some View {
        NavigationStack {
            List {
                Section("项目") {
                    HStack { TextField("新项目名称", text: $projectTitle); Button("创建") { let title = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines); if !title.isEmpty { model.change { $0.projects.append(LibraryProject(title: title)) }; projectTitle = "" } } }
                    ForEach(model.state.projects.filter { $0.deletedAt == nil }) { project in NavigationLink(project.title) { ProjectView(projectID: project.id) } }
                }
                Section("资料") {
                    Button("导入 PDF、EPUB 或本地视频") { importing = true }
                    ForEach(model.state.sources.filter { $0.deletedAt == nil && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { source in
                        NavigationLink { SourceReaderView(source: source, location: source.lastLocation) } label: { VStack(alignment: .leading) { Text(source.title); Text(source.kind.rawValue).font(.caption).foregroundStyle(.secondary) } }
                    }
                }
            }.navigationTitle("Library").searchable(text: $search)
        }.fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, UTType(filenameExtension: "epub") ?? .data, .movie]) { result in
            do { model.importFile(try result.get()) } catch { model.message = error.localizedDescription }
        }
    }
}
struct ProjectView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    @State private var title = ""
    @State private var note = ""
    var body: some View {
        Form {
            if let project = model.state.projects.first(where: { $0.id == projectID }) {
                TextField("名称", text: $title); TextField("描述", text: $note, axis: .vertical)
                Button("保存") { model.change { state in if let i = state.projects.firstIndex(where: { $0.id == projectID }) { guard !title.isEmpty else { throw LibraryError.invalid("项目名称不能为空") }; state.projects[i].title = title; state.projects[i].note = note } } }
                Section("关联资料") { ForEach(model.state.sources.filter { $0.deletedAt == nil }) { source in
                    Toggle(source.title, isOn: Binding(get: { project.sourceIDs.contains(source.id) }, set: { enabled in model.change { state in if let i = state.projects.firstIndex(where: { $0.id == projectID }) { state.projects[i].sourceIDs.removeAll { $0 == source.id }; if enabled { state.projects[i].sourceIDs.append(source.id) } } } }))
                } }
                Section("关联卡片") { ForEach(model.state.cards.filter { $0.deletedAt == nil }) { card in
                    Toggle(card.title, isOn: Binding(get: { project.cardIDs.contains(card.id) }, set: { enabled in model.change { state in if let i = state.projects.firstIndex(where: { $0.id == projectID }) { state.projects[i].cardIDs.removeAll { $0 == card.id }; if enabled { state.projects[i].cardIDs.append(card.id) } } } }))
                } }
                Text("解除关联只影响项目，不删除卡片或资料。") .font(.caption)
            }
        }.navigationTitle("项目").onAppear { if let p = model.state.projects.first(where: { $0.id == projectID }) { title = p.title; note = p.note } }
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
    @State private var validated: BackupService.Validated?
    @State private var confirmRestore = false
    struct Row: Identifiable { let id: UUID; let title: String; let kind: String; let deleted: Bool }
    var rows: [Row] {
        var all: [Row] = model.state.sources.map { Row(id: $0.id, title: $0.title, kind: "资料", deleted: $0.deletedAt != nil) }
        all += model.state.marks.map { Row(id: $0.id, title: $0.excerpt.isEmpty ? locationLabel($0.locator) : $0.excerpt, kind: "Mark", deleted: $0.deletedAt != nil) }
        all += model.state.cards.map { Row(id: $0.id, title: $0.title, kind: "卡片", deleted: $0.deletedAt != nil) }
        all += model.state.projects.map { Row(id: $0.id, title: $0.title, kind: "项目", deleted: $0.deletedAt != nil) }
        all += model.state.relations.map { Row(id: $0.id, title: $0.kind, kind: "关系", deleted: $0.deletedAt != nil) }
        all += model.state.reviewRecords.map { Row(id: $0.id, title: "\($0.rating) · \($0.reviewedAt.formatted())", kind: "复习记录", deleted: $0.deletedAt != nil) }
        return all.filter { $0.deleted == trash && (kind == "全部" || $0.kind == kind) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("备份与恢复") {
                    Button(busy ? "正在处理…" : "生成完整备份 ZIP") { busy = true; Task { do { backup = try await BackupService.export(model: model) } catch { model.message = error.localizedDescription }; busy = false } }.disabled(busy)
                    if let backup { ShareLink("导出备份", item: backup) }
                    Button("清理未被引用的资料文件", role: .destructive) { confirmCleanup = true }
                    Button("选择备份并校验") { restoring = true }.disabled(busy)
                    Text("包含知识库和已存在的本地资料；在线资料仅备份链接。恢复替换当前知识库，确认前校验路径、大小、摘要和引用，并保留恢复前快照。") .font(.caption)
                }
                Toggle("回收站", isOn: $trash).onChange(of: trash) { _, _ in selected = [] }
                Picker("类型", selection: $kind) { ForEach(["全部", "资料", "Mark", "卡片", "项目", "关系", "复习记录"], id: \.self) { Text($0) } }
                Section("对象") { ForEach(rows) { row in
                    Toggle(isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } })) { VStack(alignment: .leading) { Text(row.title); Text(row.kind).font(.caption) } }
                } }
                if !selected.isEmpty {
                    Section("操作影响") {
                        ForEach(Array(selected), id: \.self) { Text(model.impact(of: $0)).font(.caption) }
                        if trash { Button("恢复所选") { model.delete(selected, restore: true); selected = [] }; Button("永久清理所选", role: .destructive) { permanent = true; confirming = true } }
                        else {
                            Button("归档所选卡片与 Mark") { model.change { state in for i in state.cards.indices where selected.contains(state.cards[i].id) { state.cards[i].organization = .archived }; for i in state.marks.indices where selected.contains(state.marks[i].id) { state.marks[i].organization = .archived } }; selected = [] }
                            Button("移入回收站", role: .destructive) { permanent = false; confirming = true }
                        }
                    }
                }
            }.navigationTitle("Data Manager").searchable(text: $search)
        }.confirmationDialog(permanent ? "永久清理不可撤销，确认已备份？" : "将所选对象移入回收站？", isPresented: $confirming, titleVisibility: .visible) {
            Button(permanent ? "永久清理" : "移入回收站", role: .destructive) { model.delete(selected, permanently: permanent); selected = [] }
        }.confirmationDialog("清理未被当前知识库、回收站或恢复前快照引用的文件？", isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("确认清理", role: .destructive) { model.cleanUnusedAssets() }
        }.fileImporter(isPresented: $restoring, allowedContentTypes: [.zip]) { result in
            busy = true
            Task { do { validated = try await BackupService.validate(result.get()); confirmRestore = true } catch { model.message = error.localizedDescription }; busy = false }
        }.confirmationDialog("校验通过。替换为备份中的 \(validated?.state.cards.count ?? 0) 张卡片、\(validated?.state.marks.count ?? 0) 条 Mark？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("确认恢复并替换当前知识库", role: .destructive) { if let validated { do { try BackupService.restore(validated, model: model) } catch { model.message = error.localizedDescription }; try? FileManager.default.removeItem(at: validated.directory); self.validated = nil } }
            Button("取消", role: .cancel) { if let validated { try? FileManager.default.removeItem(at: validated.directory) }; validated = nil }
        }
    }
}
