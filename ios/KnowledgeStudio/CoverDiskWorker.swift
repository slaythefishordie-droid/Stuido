import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// CGImage is immutable. The wrapper transfers the decoded bitmap only; PDFKit,
/// UIKit views and Readium publications never cross this actor boundary.
struct CoverBitmap: @unchecked Sendable {
    let image: CGImage
    var cost: Int { image.bytesPerRow * image.height }
}

actor CoverDiskWorker {
    static let shared = CoverDiskWorker()
    private var writesSinceTrim = 16

    func clear(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        writesSinceTrim = 16
    }

    func read(_ file: URL) -> CoverBitmap? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return decode(source)
    }
    func read(_ data: Data) -> CoverBitmap? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decode(source)
    }
    private func decode(_ source: CGImageSource) -> CoverBitmap? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 420,
            kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { CoverBitmap(image: $0) }
    }
    func author(_ asset: URL, cachedFile: URL?) -> String? {
        if let cachedFile, let author = try? String(contentsOf: cachedFile.appendingPathExtension("author"), encoding: .utf8) {
            return author
        }
        guard asset.pathExtension.lowercased() == "pdf" else { return nil }
        return PDFDocument(url: asset)?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
    }
    func write(_ bitmap: CoverBitmap, to file: URL, quality: Double, author: String? = nil) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, bitmap.image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let author { try author.write(to: file.appendingPathExtension("author"), atomically: true, encoding: .utf8) }
            try (data as Data).write(to: file, options: .atomic)
            writesSinceTrim += 1
            if writesSinceTrim >= 16 {
                writesSinceTrim = 0
                trim(file.deletingLastPathComponent())
            }
        } catch { /* Reconstructible artwork: a cache failure must not fail reading. */ }
    }
    private func trim(_ directory: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: Array(keys)) else { return }
        let files = urls.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = files.reduce(0) { $0 + $1.1 }
        for (url, size, _) in files where bytes > 128 * 1_048_576 {
            do { try FileManager.default.removeItem(at: url); bytes -= size } catch { continue }
        }
    }
}
