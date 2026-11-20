import KnowledgeCore
import SwiftUI

struct ProjectBoardView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    @State private var text = ""
    @State private var dragged: UUID?
    @GestureState private var dragOffset = CGSize.zero
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
    private func position(_ node: BoardNode) -> CGPoint {
        let offset = dragged == node.id ? dragOffset : .zero
        return CGPoint(
            x: min(1480, max(120, node.x + offset.width)), y: min(1100, max(100, node.y + offset.height)))
    }
    private func move(_ id: UUID, x: Double, y: Double) {
        change { value in
            if let i = value.nodes.firstIndex(where: { $0.id == id }) {
                value.nodes[i].x = min(1480, max(120, value.nodes[i].x + x))
                value.nodes[i].y = min(1100, max(100, value.nodes[i].y + y))
            }
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
    private func connect(to node: BoardNode) {
        guard let start, start != node.id else {
            opened = node
            return
        }
        change { value in
            let exists = value.edges.contains {
                ($0.from == start && $0.to == node.id) || ($0.to == start && $0.from == node.id)
            }
            if !exists { value.edges.append(BoardEdge(from: start, to: node.id)) }
        }
        self.start = nil
    }
    var body: some View {
        VStack(spacing: 0) {
            controls
            Text("拖动节点布局，点击打开内容；长按节点连线或移除。移除节点不会删除原资料和卡片。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            ScrollView([.horizontal, .vertical]) { canvas }
        }.studySurface().navigationTitle("研究白板").background(StudyTheme.paper)
            .sheet(item: $edited) { editSheet($0) }
            .sheet(isPresented: $connections) { connectionSheet }
            .sheet(item: $opened) { contentSheet($0) }
    }
    private var controls: some View {
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
    }
    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let nodes = Dictionary(uniqueKeysWithValues: board.nodes.map { ($0.id, $0) })
                for edge in board.edges {
                    guard let a = nodes[edge.from], let b = nodes[edge.to] else { continue }
                    var path = Path()
                    path.move(to: position(a))
                    path.addLine(to: position(b))
                    context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 2)
                }
            }
            ForEach(board.nodes) { node in nodeView(node) }
        }.frame(width: 1600, height: 1200)
    }
    private func nodeView(_ node: BoardNode) -> some View {
        nodeButton(node)
            .position(position(node))
            .gesture(nodeDrag(node.id))
            .accessibilityAction(named: "向左移动") { move(node.id, x: -40, y: 0) }
            .accessibilityAction(named: "向右移动") { move(node.id, x: 40, y: 0) }
            .accessibilityAction(named: "向上移动") { move(node.id, x: 0, y: -40) }
            .accessibilityAction(named: "向下移动") { move(node.id, x: 0, y: 40) }
            .contextMenu { nodeMenu(node) }
    }
    private func nodeButton(_ node: BoardNode) -> some View {
        Button {
            connect(to: node)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(nodeTitle(node.kind)).font(.caption.weight(.semibold)).foregroundStyle(StudyTheme.ink)
                Text(node.text).font(.system(.body, design: .serif)).lineLimit(5)
            }.frame(width: 190, alignment: .leading).frame(minHeight: 56).padding(12)
                .background(StudyTheme.leaf, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(
                        start == node.id ? StudyTheme.ink : Color.secondary.opacity(0.2)))
        }.buttonStyle(.plain)
    }
    private func nodeTitle(_ kind: BoardNode.Kind) -> String {
        switch kind {
        case .source: "资料"
        case .card: "知识卡片"
        case .concept: "概念"
        case .note: "研究笔记"
        }
    }
    private func nodeDrag(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, state, _ in state = value.translation }
            .onChanged { _ in dragged = id }
            .onEnded { value in
                move(id, x: value.translation.width, y: value.translation.height)
                dragged = nil
            }
    }
    @ViewBuilder private func nodeMenu(_ node: BoardNode) -> some View {
        Button("编辑文字") {
            draft = node.text
            edited = node
        }
        Button("从这里连线") { start = node.id }
        if let start, start != node.id { Button("连接到此处") { connect(to: node) } }
        Button("移除节点", role: .destructive) {
            change { $0.removeNode(node.id) }
            if start == node.id { start = nil }
        }
    }
    private func editSheet(_ node: BoardNode) -> some View {
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
    private func edgeTitle(_ edge: BoardEdge) -> String {
        let from = board.nodes.first { $0.id == edge.from }?.text ?? ""
        let to = board.nodes.first { $0.id == edge.to }?.text ?? ""
        return from + " → " + to
    }
    private var connectionSheet: some View {
        NavigationStack {
            List {
                if board.edges.isEmpty { Text("长按节点选择“从这里连线”，再点另一节点。") }
                ForEach(board.edges) { edge in
                    HStack {
                        Text(edgeTitle(edge))
                        Spacer()
                        Button("移除", role: .destructive) {
                            change { $0.edges.removeAll { $0.id == edge.id } }
                        }
                    }
                }
            }.navigationTitle("白板连线").toolbar { Button("完成") { connections = false } }
        }
    }
    private func contentSheet(_ node: BoardNode) -> some View {
        NavigationStack {
            nodeContent(node).toolbar { Button("完成") { opened = nil } }
        }.environmentObject(model)
    }
    @ViewBuilder private func nodeContent(_ node: BoardNode) -> some View {
        if node.kind == .source,
            let source = model.state.sources.first(where: { $0.id == node.targetID && $0.deletedAt == nil })
        {
            SourceReaderView(source: source, location: source.lastLocation)
        } else if node.kind == .card, let id = node.targetID,
            model.state.cards.contains(where: { $0.id == id && $0.deletedAt == nil })
        {
            CardDetailView(cardID: id)
        } else {
            ScrollView { Text(node.text).textSelection(.enabled).padding() }
        }
    }
}
