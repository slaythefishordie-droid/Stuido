import Foundation

public struct BoardNode: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case source, card, concept, note }
    public var id = UUID()
    public var kind: Kind
    public var targetID: UUID?
    public var text: String
    public var x: Double = 200
    public var y: Double = 180
    public init(kind: Kind, text: String, targetID: UUID? = nil) {
        self.kind = kind
        self.text = text
        self.targetID = targetID
    }
}
public struct BoardEdge: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var from: UUID
    public var to: UUID
    public init(from: UUID, to: UUID) {
        self.from = from
        self.to = to
    }
}
public struct ProjectBoard: Codable, Equatable, Sendable {
    public var nodes: [BoardNode] = []
    public var edges: [BoardEdge] = []
    public init() {}
    public mutating func removeNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.from == id || $0.to == id }
    }
    public func validate(sourceIDs: Set<UUID>, cardIDs: Set<UUID>) throws {
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count, Set(edges.map(\.id)).count == edges.count else {
            throw LibraryError.invalid("白板节点或连线编号重复")
        }
        for node in nodes {
            guard node.x.isFinite, node.y.isFinite, (0...1600).contains(node.x), (0...1200).contains(node.y)
            else { throw LibraryError.invalid("白板坐标无效") }
            switch node.kind {
            case .source:
                guard let id = node.targetID, sourceIDs.contains(id) else {
                    throw LibraryError.invalid("白板引用的资料不存在，请先移除对应节点")
                }
            case .card:
                guard let id = node.targetID, cardIDs.contains(id) else {
                    throw LibraryError.invalid("白板引用的卡片不存在，请先移除对应节点")
                }
            case .concept, .note:
                guard node.targetID == nil else { throw LibraryError.invalid("自由笔记不能冒充对象引用") }
            }
        }
        guard edges.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to }) else {
            throw LibraryError.invalid("白板连线端点无效")
        }
    }
}
