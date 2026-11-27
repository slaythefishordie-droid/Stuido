import Foundation
import XCTest
@testable import KnowledgeCore
final class ValidationTests: XCTestCase {
    func testCardFieldsReferencesAndProvenanceRemainStrict() throws {
        var state = LibraryState()
        let source = LibrarySource(kind: .pdf, title: "Book")
        state.sources = [source]
        let mark = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))
        state.marks = [mark]
        for kind in CardKind.allCases {
            let field = LibraryCard.fields(for: kind)[0]
            var card = LibraryCard(type: kind, content: [field: "Text"])
            let ref = CardReference(sourceID: source.id, locator: mark.locator)
            card.sourceRefs = [ref]; card.markIDs = [mark.id]
            card.provenance = [field: FieldOrigin(kind: "original", sourceRefIDs: [ref.id])]
            state.cards = [card]
            try state.validate()
            state.cards[0].content["unsupported"] = "Invalid"
            XCTAssertThrowsError(try state.validate())
            state.cards = [card]; state.cards[0].sourceRefs.append(ref)
            XCTAssertThrowsError(try state.validate())
            state.cards = [card]; state.cards[0].markIDs = [UUID()]
            XCTAssertThrowsError(try state.validate())
            state.cards = [card]; state.cards[0].provenance[field]?.sourceRefIDs = [UUID()]
            XCTAssertThrowsError(try state.validate())
            state.cards = [card]; state.cards[0].provenance[field]?.sourceRefIDs = []
            XCTAssertThrowsError(try state.validate())
        }
    }
}
