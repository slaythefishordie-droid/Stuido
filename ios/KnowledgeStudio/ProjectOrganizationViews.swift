import KnowledgeCore
import SwiftUI

struct ProjectSourceNoteView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    let sourceID: UUID
    @State private var text = ""
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading) {
            Text("只属于这个项目的研究笔记。原文件、高亮和标记仍与其他项目共享。").font(.caption).foregroundStyle(.secondary).padding()
            TextEditor(text: $text).padding()
        }.studySurface().navigationTitle("项目研究笔记").toolbar {
            Button("保存") {
                model.change { state in
                    guard
                        let i = state.projects.firstIndex(where: { $0.id == projectID && $0.deletedAt == nil }
                        )
                    else { throw LibraryError.invalid("项目不可用") }
                    var notes = state.projects[i].sourceNotes ?? [:]
                    if text.isEmpty {
                        notes.removeValue(forKey: sourceID.uuidString)
                    } else {
                        notes[sourceID.uuidString] = text
                    }
                    state.projects[i].sourceNotes = notes
                }
            }
        }.onAppear {
            guard !loaded else { return }
            loaded = true
            text = model.state.projects.first { $0.id == projectID }?.sourceNotes?[sourceID.uuidString] ?? ""
        }
    }
}

struct ProjectGroupsView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    @State private var title = ""
    private var groups: [ProjectGroup] { model.state.projects.first { $0.id == projectID }?.groups ?? [] }
    var body: some View {
        List {
            Section("新建分组") {
                TextField("分组名称", text: $title)
                Button("创建") {
                    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    model.change { state in
                        if let i = state.projects.firstIndex(where: { $0.id == projectID }) {
                            var values = state.projects[i].groups ?? []
                            values.append(ProjectGroup(title: name))
                            state.projects[i].groups = values
                        }
                    }
                    if model.message == nil { title = "" }
                }
            }
            ForEach(groups) { group in
                NavigationLink(group.title) { ProjectGroupDetail(projectID: projectID, groupID: group.id) }
                    .swipeActions {
                        Button("移除分组", role: .destructive) {
                            model.change { state in
                                if let i = state.projects.firstIndex(where: { $0.id == projectID }) {
                                    state.projects[i].groups?.removeAll { $0.id == group.id }
                                }
                            }
                        }
                    }
            }
            Text("移除分组不删除资料和卡片。分组仅用于这个项目。").font(.caption)
        }.navigationTitle("项目分组")
    }
}
struct ProjectGroupDetail: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    let groupID: UUID
    @State private var editing = false
    @State private var title = ""
    private var group: ProjectGroup? {
        model.state.projects.first { $0.id == projectID }?.groups?.first { $0.id == groupID }
    }
    private func update(_ action: (inout ProjectGroup) -> Void) {
        model.change { state in
            guard let i = state.projects.firstIndex(where: { $0.id == projectID && $0.deletedAt == nil }),
                let j = state.projects[i].groups?.firstIndex(where: { $0.id == groupID })
            else { throw LibraryError.invalid("项目分组不可用") }
            action(&state.projects[i].groups![j])
        }
    }
    var body: some View {
        List {
            if let group {
                if editing {
                    TextField("分组名称", text: $title)
                    Button("保存名称") { update { $0.title = title } }
                }
                Section("资料") {
                    ForEach(
                        model.state.sources.filter {
                            $0.deletedAt == nil && (editing || group.sourceIDs.contains($0.id))
                        }
                    ) { source in
                        if editing {
                            Button {
                                update {
                                    if $0.sourceIDs.contains(source.id) {
                                        $0.sourceIDs.removeAll { $0 == source.id }
                                    } else {
                                        $0.sourceIDs.append(source.id)
                                    }
                                }
                            } label: {
                                Label(
                                    source.title,
                                    systemImage: group.sourceIDs.contains(source.id)
                                        ? "checkmark.circle.fill" : "circle")
                            }
                        } else {
                            NavigationLink(source.title) {
                                SourceReaderView(source: source, location: source.lastLocation)
                            }
                        }
                    }
                }
                Section("卡片") {
                    ForEach(
                        model.state.cards.filter {
                            $0.deletedAt == nil && (editing || group.cardIDs.contains($0.id))
                        }
                    ) { card in
                        if editing {
                            Button {
                                update {
                                    if $0.cardIDs.contains(card.id) {
                                        $0.cardIDs.removeAll { $0 == card.id }
                                    } else {
                                        $0.cardIDs.append(card.id)
                                    }
                                }
                            } label: {
                                Label(
                                    card.title,
                                    systemImage: group.cardIDs.contains(card.id)
                                        ? "checkmark.circle.fill" : "circle")
                            }
                        } else {
                            NavigationLink(card.title) { CardDetailView(cardID: card.id) }
                        }
                    }
                }
            }
        }.navigationTitle(group?.title ?? "分组").toolbar {
            Button(editing ? "完成" : "管理分组") { editing.toggle() }
        }
        .onAppear { title = group?.title ?? "" }
    }
}
