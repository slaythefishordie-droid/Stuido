import Foundation

/// A rebuild-on-change index. Keeps the original snapshot's order and value semantics;
/// deletion filtering is explicit so inbox, readers and trash cannot share stale views.
public struct LibraryMarkIndex: Sendable {
    private let marks: [LibraryMark]
    private let positions: [UUID: [Int]]

    public init(_ marks: [LibraryMark]) {
        self.marks = marks
        var positions: [UUID: [Int]] = [:]
        for (offset, mark) in marks.enumerated() {
            positions[mark.sourceID, default: []].append(offset)
        }
        self.positions = positions
    }

    public func marks(for sourceID: UUID, includingDeleted: Bool = false) -> [LibraryMark] {
        (positions[sourceID] ?? []).compactMap { offset in
            let mark = marks[offset]
            return includingDeleted || mark.deletedAt == nil ? mark : nil
        }
    }
}
