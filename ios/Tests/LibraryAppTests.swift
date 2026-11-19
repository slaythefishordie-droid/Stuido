import XCTest
import Foundation
import KnowledgeCore
@preconcurrency import ReadiumZIPFoundation
@testable import KnowledgeStudio

@MainActor
final class LibraryAppTests: XCTestCase {
    func testBackupRestorePreservesCardsAndReferencedAsset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let input = root.appendingPathComponent("sample.pdf")
        try Data("PDF fixture bytes".utf8).write(to: input)
        model.importFile(input)
        let source = try XCTUnwrap(model.state.sources.first)
        var card = LibraryCard(type: .expression, content: ["text": "Example"])
        card.sourceRefs = [CardReference(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))]
        model.saveCard(card)
        let original = model.state
        let zip = try await BackupService.export(model: model)
        defer { try? FileManager.default.removeItem(at: zip) }
        let validated = try await BackupService.validate(zip)
        defer { try? FileManager.default.removeItem(at: validated.directory) }
        model.delete([card.id])
        XCTAssertNotNil(model.state.cards.first?.deletedAt)
        try BackupService.restore(validated, model: model)
        XCTAssertEqual(model.state, original)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.assetURL(source))), Data("PDF fixture bytes".utf8))
    }
    func testBackupRejectsTraversalAndPreservesLiveState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("data")
        try Data("unsafe".utf8).write(to: file)
        let zip = root.appendingPathComponent("unsafe.zip")
        let archive = try await Archive(url: zip, accessMode: .create)
        try await archive.addEntry(with: "../escape", fileURL: file)
        do { _ = try await BackupService.validate(zip); XCTFail("Traversal accepted") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape").path))
    }
    func testDeletingProjectNeverDeletesContentAndReferencedSourceCannotBePurged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let source = LibrarySource(kind: .pdf, title: "Book")
        let mark = LibraryMark(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: 1))
        var project = LibraryProject(title: "Study"); project.sourceIDs = [source.id]
        model.change { $0.sources = [source]; $0.marks = [mark]; $0.projects = [project] }
        model.delete([project.id]); model.delete([project.id], permanently: true)
        XCTAssertEqual(model.state.sources.count, 1); XCTAssertEqual(model.state.marks.count, 1)
        model.delete([source.id]); model.delete([source.id], permanently: true)
        XCTAssertNotNil(model.message); XCTAssertEqual(model.state.sources.count, 1)
        model.delete([source.id], restore: true)
        XCTAssertNil(model.state.sources[0].deletedAt)
    }
    func testAssetCleanupPreservesReferencesAndRecoverySnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        let assets = root.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let hash = String(repeating: "a", count: 64)
        let referenced = assets.appendingPathComponent(hash + ".pdf")
        try Data("keep".utf8).write(to: referenced)
        var snapshot = LibraryState(); snapshot.sources = [LibrarySource(kind: .pdf, title: "Protected", assetHash: hash, assetExtension: "pdf")]
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("before-restore-test.json"))
        let orphan = assets.appendingPathComponent("orphan.pdf"); try Data("unused".utf8).write(to: orphan)
        model.cleanUnusedAssets()
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testRestoreRejectsFalseUncompressedSize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = StudioModel(root: root)
        model.saveCard(LibraryCard(type: .expression, content: ["text": String(repeating: "A", count: 10000)]))
        let original = model.state
        let zip = try await BackupService.export(model: model)
        defer { try? FileManager.default.removeItem(at: zip) }
        var bytes = try Data(contentsOf: zip)
        let central = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        bytes.replaceSubrange((central.lowerBound + 24)..<(central.lowerBound + 28), with: [1, 0, 0, 0])
        try bytes.write(to: zip)
        do { _ = try await BackupService.validate(zip); XCTFail("False size accepted") } catch { }
        XCTAssertEqual(model.state, original)
    }

}
