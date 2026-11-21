import Foundation
import KnowledgeCore
import XCTest

@testable import KnowledgeStudio

@MainActor
final class LoungeAppTests: XCTestCase {
    func testAudioImportsDecodeAcrossSupportedContainersAndPersist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let hub = LoungeHub(root: root)
        let bundle = Bundle(for: Self.self)
        let inputs = try ["mp3", "aac", "m4a", "flac"].map {
            try XCTUnwrap(bundle.url(forResource: "studio", withExtension: $0, subdirectory: "LoungeFixtures"))
        }
        await hub.importTracks(inputs)
        XCTAssertNil(hub.message)
        XCTAssertEqual(hub.tracks.count, 4)
        XCTAssertTrue(hub.tracks.allSatisfy { $0.duration > 0 })
        await hub.importTracks(inputs)
        XCTAssertEqual(hub.tracks.count, 4)
        XCTAssertEqual(LoungeHub(root: root).tracks, hub.tracks)
    }

    func testSceneLedgerCountsAtMostOneSourceAtATime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let hub = LoungeHub(root: root)
        let a = UUID(), b = UUID(), sourceA = UUID(), sourceB = UUID()
        hub.scene(a, active: true, sourceID: sourceA)
        hub.scene(b, active: true, sourceID: sourceB)
        hub.scene(b, active: false, sourceID: nil)
        hub.scene(a, active: false, sourceID: nil)
        let records = hub.intervals()
        XCTAssertEqual(records.map(\.sourceID), [sourceA, sourceB, sourceA])
        XCTAssertEqual(records, LoungeHub(root: root).intervals())
    }
}
