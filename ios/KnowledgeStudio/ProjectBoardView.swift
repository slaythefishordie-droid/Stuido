import KnowledgeCore
import SwiftUI

struct ProjectBoardView: View {
    @EnvironmentObject private var model: StudioModel
    let projectID: UUID
    @State private var text = ""
    @GestureState private var drag: NodeDrag?
    @State private var choosingObject = false
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    private var displayedZoom: CGFloat { min(1.6, max(0.5, zoom * magnification)) }

    private struct NodeDrag {
        let id: UUID
        let offset: CGSize
    }
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
        let offset = drag.flatMap { $0.id == node.id ? $0.offset : nil } ?? .zero
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
            if let target = node.targetID,
                value.nodes.contains(where: { $0.kind == node.kind && $0.targetID == target }) { return }
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
            ScrollView([.horizontal, .vertical]) {
                canvas.scaleEffect(displayedZoom, anchor: .topLeading)
                    .frame(width: 1600 * displayedZoom, height: 1200 * displayedZoom, alignment: .topLeading)
            }.simultaneousGesture(MagnifyGesture()
                .updating($magnification) { value, scale, _ in scale = value.magnification }
                .onEnded { value in zoom = min(1.6, max(0.5, zoom * value.magnification)) })
        }.studySurface().navigationTitle("研究白板").background(StudyTheme.paper)
            .sheet(item: $edited) { editSheet($0) }
            .sheet(isPresented: $connections) { connectionSheet }
            .sheet(item: $opened) { contentSheet($0) }
            .sheet(isPresented: $choosingObject) {
                BoardObjectPicker(projectID: projectID, existingTargets: Set(board.nodes.compactMap(\.targetID))) {
                    add($0)
                    if model.message == nil { choosingObject = false }
                }
            }
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
                Button("已有资料或卡片") { choosingObject = true }
            }
            if start != nil { Button("取消连线") { start = nil } }
            Button("撤销") { undo() }.disabled(undoBoards.isEmpty)
            Button("连线") { connections = true }
            Menu {
                Button("缩小") { zoom = max(0.5, zoom - 0.15) }
                Button("放大") { zoom = min(1.6, zoom + 0.15) }
                Button("原始大小") { zoom = 1 }
            } label: {
                Image(systemName: "magnifyingglass").frame(minWidth: 35, minHeight: 44)
            }.accessibilityLabel("缩放白板")
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
        }.frame(width: 1600, height: 1200).coordinateSpace(name: "board-canvas")
    }
    private func nodeView(_ node: BoardNode) -> some View {
        nodeButton(node)
            .position(position(node))
            .highPriorityGesture(nodeDrag(node.id))
            .zIndex(drag?.id == node.id ? 1 : 0)
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
        DragGesture(minimumDistance: 8, coordinateSpace: .named("board-canvas"))
            .updating($drag) { value, state, transaction in
                transaction.animation = nil
                state = NodeDrag(id: id, offset: value.translation)
            }
            .onEnded { value in
                move(id, x: value.translation.width, y: value.translation.height)
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


private struct BoardObjectPicker: View {
    @EnvironmentObject private var model: StudioModel
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    let existingTargets: Set<UUID>
    let add: (BoardNode) -> Void
    @State private var search = ""
    @State private var scope = "项目"
    @State private var filterProject: UUID?
    @State private var kind = "全部"

    private struct Choice: Identifiable {
        let id: UUID
        let title: String
        let kind: BoardNode.Kind
        let date: Date
    }

    private var choices: [Choice] {
        let project = model.state.projects.first { $0.id == (filterProject ?? projectID) && $0.deletedAt == nil }
        let ids = Set((project?.sourceIDs ?? []) + (project?.cardIDs ?? []))
        var results: [Choice] = []
        if kind != "卡片" {
            results += model.state.sources.lazy.filter { $0.deletedAt == nil }.map {
                Choice(id: $0.id, title: $0.title, kind: .source, date: $0.lastReadAt ?? $0.updatedAt)
            }
        }
        if kind != "资料" {
            results += model.state.cards.lazy.filter { $0.deletedAt == nil }.map {
                Choice(id: $0.id, title: $0.title, kind: .card, date: $0.updatedAt)
            }
        }
        results = results.filter {
            !existingTargets.contains($0.id) && (scope != "项目" || ids.contains($0.id))
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
        return scope == "最近" ? Array(results.prefix(40)) : results
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("范围", selection: $scope) {
                    ForEach(["项目", "最近", "全库"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented)
                if scope == "项目" {
                    Picker("项目", selection: $filterProject) {
                        Text("当前项目").tag(nil as UUID?)
                        ForEach(model.state.projects.filter { $0.deletedAt == nil && $0.id != projectID }) {
                            Text($0.title).tag(Optional($0.id))
                        }
                    }
                }
                Picker("类型", selection: $kind) {
                    ForEach(["全部", "资料", "卡片"], id: \.self) { Text($0) }
                }
                let results = choices
                if results.isEmpty { ContentUnavailableView("没有可添加的对象", systemImage: "square.on.square") }
                ForEach(results) { item in
                    Button {
                        add(BoardNode(kind: item.kind, text: item.title, targetID: item.id))
                    } label: {
                        Label(item.title, systemImage: item.kind == .source ? "doc" : "rectangle.on.rectangle")
                    }
                }
            }.studySurface().searchable(text: $search).navigationTitle("添加知识对象")
                .toolbar { Button("关闭") { dismiss() } }
        }
    }
}
