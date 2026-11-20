import XCTest
@testable import KnowledgeStudio

final class SharedProbeTests: XCTestCase {
    func testSeparateWritersSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = SharedProbeStore(directory: directory)
        let safari = SharedProbeStore(directory: directory)
        let first = try app.write(from: .app)
        let second = try safari.write(from: .safari)
        let reopened = SharedProbeStore(directory: directory)
        XCTAssertEqual(try reopened.read(from: .app)?.id, first.id)
        XCTAssertEqual(try reopened.read(from: .safari)?.id, second.id)
        _ = try safari.write(from: .safari)
        XCTAssertEqual(try reopened.read(from: .app)?.id, first.id)
    }

    func testCorruptRecordIsReportedAndRetained() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("safari.json")
        let data = Data("broken".utf8)
        try data.write(to: file)
        XCTAssertThrowsError(try SharedProbeStore(directory: directory).read(from: .safari))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testProvisionedGroupTakesPrecedenceAndInvalidMetadataFails() throws {
        let original = "group.original"
        XCTAssertEqual(try SharedProbeStore.groupIdentifier(in: ["SharedAppGroup": original]), original)
        XCTAssertEqual(try SharedProbeStore.groupIdentifier(in: [
            "SharedAppGroup": original, "ALTAppGroups": ["group.resigned"]
        ]), "group.resigned")
        for invalid in [[], ["group.one", "group.two"], [""], [" "], "group.wrongType", [42]] as [Any] {
            XCTAssertThrowsError(try SharedProbeStore.groupIdentifier(in: [
                "SharedAppGroup": original, "ALTAppGroups": invalid
            ]))
        }
        XCTAssertThrowsError(try SharedProbeStore.groupIdentifier(in: [:]))
    }

    func testMissingFileIsEmptyButInvalidFileAndWriterAreErrors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedProbeStore(directory: directory)
        XCTAssertNil(try store.read(from: .safari))
        let record = try store.write(from: .app)
        let safariFile = directory.appendingPathComponent("safari.json")
        try JSONEncoder().encode(record).write(to: safariFile)
        XCTAssertThrowsError(try store.read(from: .safari))
        try FileManager.default.removeItem(at: safariFile)
        try FileManager.default.createDirectory(at: safariFile, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.read(from: .safari))
    }
}
