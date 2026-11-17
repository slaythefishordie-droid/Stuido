import XCTest
import KnowledgeCore
@testable import KnowledgeStudio

@MainActor
final class AppSmokeTests: XCTestCase {
    func testFirstLaunchKeepsPlayerOfflineUntilUserOpensVideo() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("store.json")
        let model = YouTubeStudyModel(fileURL: file)
        XCTAssertNil(model.storageError)
        XCTAssertNil(model.player)
        XCTAssertTrue(model.marks.isEmpty)
        XCTAssertFalse(model.isReady)
    }

    func testInvalidURLDoesNotCreatePlayerOrSource() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("store.json")
        let model = YouTubeStudyModel(fileURL: file)
        model.input = "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ"
        model.openInput()
        XCTAssertNil(model.player)
        XCTAssertTrue(model.sources.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
