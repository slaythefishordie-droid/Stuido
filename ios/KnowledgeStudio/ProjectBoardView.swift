import KnowledgeCore
import SwiftUI

struct ProjectBoardView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    @State private var text = ""
    @State private var start: UUID?
    @State private var opened: BoardNode?
    @State private var edited: BoardNode?
    @State private var draft = ""
    @State private var connections = false
    @State private var undoBoards: [ProjectBoard] = []
    @State private var expectedBoard: ProjectBoard?
    private var board: ProjectBoard {
        model.state.projects.first { $0.id == projectID }?.board ?? ProjectBoard()
    }
    private func change(_ action: (inout ProjectBoard) -> Void) {
        let previous = board
        model.change { state in
            guard let i = state.projects.firstIndex(where: { $0.id == projectID && $0.deletedAt == nil })
            else { throw LibraryError.invalid("项目不可用") }
            var value = state.projects[i].board ?? ProjectBoard()
            action(&value)
            state.projects[i].board = value
        }
        if model.message == nil && board != previous {
            undoBoards.append(previous)
            if undoBoards.count > 20 { undoBoards.removeFirst() }
            expectedBoard = board
        }
    }
    private func undo() {
        guard let previous = undoBoards.last else { return }
        model.change { state in
            guard let i = state.projects.firstIndex(where: { $0.id == projectID }),
                (state.projects[i].board ?? ProjectBoard()) == expectedBoard
            else {
                throw LibraryError.invalid("白板已在别处更新，未覆盖新修改")
            }
            state.projects[i].board = previous
        }
        if model.message == nil {
            undoBoards.removeLast()
            expectedBoard = board
        }
    }
    private func add(_ node: BoardNode) {
        change { value in
            var node = node
            node.x = 180 + Double(value.nodes.count % 5) * 270
            node.y = 150 + Double(value.nodes.count / 5 % 6) * 170
            value.nodes.append(node)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("写下概念或研究笔记", text: $text)
                Menu("添加") {
                    Button("概念") {
                        add(BoardNode(kind: .concept, text: text))
                        text = ""
                    }.disabled(text.isEmpty)
                    Button("笔记") {
                        add(BoardNode(kind: .note, text: text))
                        text = ""
                    }.disabled(text.isEmpty)
                    Menu("已有资料") {
                        ForEach(model.state.sources.filter { $0.deletedAt == nil }) { source in
                            Button(source.title) {
                                add(BoardNode(kind: .source, text: source.title, targetID: source.id))
                            }
                        }
                    }
                    Menu("已有卡片") {
                        ForEach(model.state.cards.filter { $0.deletedAt == nil }) { card in
                            Button(card.title) {
                                add(BoardNode(kind: .card, text: card.title, targetID: card.id))
                            }
                        }
                    }
                }
                if start != nil { Button("取消连线") { start = nil } }
                Button("撤销") { undo() }.disabled(undoBoards.isEmpty)
                Button("连线") { connections = true }
            }.padding()
            Text("拖动节点布局，点击打开内容；长按节点连线或移除。移除节点不会删除原资料和卡片。").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for edge in board.edges {
                            if let a = board.nodes.first(where: { $0.id == edge.from }),
                                let b = board.nodes.first(where: { $0.id == edge.to })
                            {
                                var path = Path()
                                path.move(to: CGPoint(x: a.x, y: a.y))
                                path.addLine(to: CGPoint(x: b.x, y: b.y))
                                context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 2)
                            }
                        }
                    }
                    ForEach(board.nodes) { node in
                        Button {
                            if let start, start != node.id {
                                change { value in
                                    if !value.edges.contains(where: {
                                        ($0.from == start && $0.to == node.id)
                                            || ($0.to == start && $0.from == node.id)
                                    }) {
                                        value.edges.append(BoardEdge(from: start, to: node.id))
                                    }
                                }
                                self.start = nil
                            } else {
                                opened = node
                            }
                        } label: {
                            Text(node.text).lineLimit(5).frame(width: 190).frame(minHeight: 70).padding(12)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14).stroke(
                                        start == node.id ? StudyTheme.ink : .secondary.opacity(0.2)))
                        }.buttonStyle(.plain).position(x: node.x, y: node.y)
                            .gesture(
                                DragGesture(minimumDistance: 10).onEnded { value in
                                    change { board in
                                        if let i = board.nodes.firstIndex(where: { $0.id == node.id }) {
                                            board.nodes[i].x = min(
                                                1480, max(120, node.x + value.translation.width))
                                            board.nodes[i].y = min(
                                                1100, max(100, node.y + value.translation.height))
                                        }
                                    }
                                }
                            )
                            .contextMenu {
                                Button("编辑文字") {
                                    draft = node.text
                                    edited = node
                                }
                                Button("从这里连线") { start = node.id }
                                if let start, start != node.id {
                                    Button("连接到此处") {
                                        change { value in
                                            if !value.edges.contains(where: {
                                                ($0.from == start && $0.to == node.id)
                                                    || ($0.to == start && $0.from == node.id)
                                            }) {
                                                value.edges.append(BoardEdge(from: start, to: node.id))
                                            }
                                        }
                                        self.start = nil
                                    }
                                }
                                Button("移除节点", role: .destructive) {
                                    change { $0.removeNode(node.id) }
                                    if start == node.id { start = nil }
                                }
                            }
                    }
                }.frame(width: 1600, height: 1200)
            }
        }.navigationTitle("研究白板").background(StudyTheme.paper)
            .sheet(item: $edited) { node in
                NavigationStack {
                    TextEditor(text: $draft).padding().navigationTitle("编辑白板文字").toolbar {
                        Button("取消") { edited = nil }
                        Button("保存") {
                            change { value in
                                if let i = value.nodes.firstIndex(where: { $0.id == node.id }) {
                                    value.nodes[i].text = draft
                                }
                            }
                            if model.message == nil { edited = nil }
                        }
                    }
                }
            }
            .sheet(isPresented: $connections) {
                NavigationStack {
                    List {
                        if board.edges.isEmpty { Text("长按节点选择“从这里连线”，再点另一节点。") }
                        ForEach(board.edges) { edge in
                            HStack {
                                Text(
                                    (board.nodes.first { $0.id == edge.from }?.text ?? "") + " → "
                                        + (board.nodes.first { $0.id == edge.to }?.text ?? ""))
                                Spacer()
                                Button("移除", role: .destructive) {
                                    change { $0.edges.removeAll { $0.id == edge.id } }
                                }
                            }
                        }
                    }.navigationTitle("白板连线").toolbar { Button("完成") { connections = false } }
                }
            }
            .sheet(item: $opened) { node in
                NavigationStack {
                    Group {
                        if node.kind == .source,
                            let source = model.state.sources.first(where: {
                                $0.id == node.targetID && $0.deletedAt == nil
                            })
                        {
                            SourceReaderView(source: source, location: source.lastLocation)
                        } else if node.kind == .card, let id = node.targetID,
                            model.state.cards.contains(where: { $0.id == id && $0.deletedAt == nil })
                        {
                            CardDetailView(cardID: id)
                        } else {
                            ScrollView { Text(node.text).textSelection(.enabled).padding() }
                        }
                    }.toolbar { Button("完成") { opened = nil } }
                }.environmentObject(model)
            }
    }
}
