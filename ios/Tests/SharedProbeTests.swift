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
}
