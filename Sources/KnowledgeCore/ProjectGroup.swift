import Foundation

public struct ProjectGroup: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var sourceIDs: [UUID] = []
    public var cardIDs: [UUID] = []
    public init(title: String) { self.title = title }
}
extension LibraryProject {
    public func references(_ id: UUID, includingBoard: Bool = true) -> Bool {
        sourceIDs.contains(id) || cardIDs.contains(id) || relationIDs.contains(id)
            || (includingBoard && board?.nodes.contains(where: { $0.targetID == id }) == true)
            || sourceNotes?[id.uuidString] != nil
            || groups?.contains(where: { $0.sourceIDs.contains(id) || $0.cardIDs.contains(id) }) == true
    }
}
