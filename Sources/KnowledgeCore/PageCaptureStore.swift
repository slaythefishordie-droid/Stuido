import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct PageCapture: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let kind: SourceKind
    public let sourceURL: String
    public let title: String
    public let locator: ReadingLocator
    public let excerpt: String
    public let createdAt: Double
    public func validate() throws {
        guard version == 1, [.article, .podcast].contains(kind), let url = URL(string: sourceURL),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              sourceURL.utf8.count <= 4000, !title.isEmpty, title.utf8.count <= 4096,
              excerpt.utf8.count <= 20000, createdAt.isFinite, createdAt >= 0,
              locator.kind == kind.rawValue else { throw LibraryError.invalid("网页采集记录无效") }
        try locator.validate()
    }
}
public struct PageCaptureStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(.EIO) }; defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }; defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }
    public func save(_ capture: PageCapture) throws {
        try capture.validate()
        try locked {
            let file = directory.appendingPathComponent(capture.id.uuidString + ".json")
            do {
                let existing = try JSONDecoder().decode(PageCapture.self, from: Data(contentsOf: file))
                guard existing == capture else { throw LibraryError.invalid("采集编号冲突，原记录已保留") }; return
            } catch CocoaError.fileReadNoSuchFile { }
            try JSONEncoder().encode(capture).write(to: file, options: .atomic)
        }
    }
    public func readAll() throws -> [PageCapture] {
        try locked {
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { file in
                let capture = try JSONDecoder().decode(PageCapture.self, from: Data(contentsOf: file)); try capture.validate()
                guard file.deletingPathExtension().lastPathComponent == capture.id.uuidString else { throw LibraryError.invalid("采集记录编号不符") }; return capture
            }
        }
    }
}
public extension LibraryRepository {
    func receivePages(_ captures: [PageCapture]) throws {
        try update { state in
            for capture in captures {
                try capture.validate()
                guard !state.receivedWebIDs.contains(capture.id), !state.marks.contains(where: { $0.id == capture.id }) else { continue }
                let source: LibrarySource
                if let existing = state.sources.first(where: { $0.kind == capture.kind && $0.url == capture.sourceURL }) { source = existing }
                else { source = LibrarySource(kind: capture.kind, title: capture.title, url: capture.sourceURL); state.sources.append(source) }
                state.marks.append(LibraryMark(id: capture.id, sourceID: source.id, locator: capture.locator, excerpt: capture.excerpt, createdAt: Date(timeIntervalSince1970: capture.createdAt / 1000)))
                state.receivedWebIDs.append(capture.id)
            }
        }
    }
}
