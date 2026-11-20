import ImageIO
import KnowledgeCore
import PDFKit
@preconcurrency import QuickLookThumbnailing
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer
import SwiftUI
import UniformTypeIdentifiers

struct StudySourceTile: View {
    let source: LibrarySource
    let asset: URL?
    var compact = false
    var revision = 0

    var body: some View {
        if compact {
            HStack(spacing: 12) {
                StudySourceCover(source: source, asset: asset, revision: revision).frame(width: 47, height: 60)
                caption
                Spacer(minLength: 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                StudySourceCover(source: source, asset: asset, revision: revision).aspectRatio(1.06, contentMode: .fit)
                caption
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(source.lastLocation.map(locationLabel) ?? studioLabel(source.kind.rawValue))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.multilineTextAlignment(.leading)
    }
}

struct StudySourceCover: View {
    let source: LibrarySource
    let asset: URL?
    var revision = 0
    @State private var thumbnail: UIImage?
    @State private var author: String?

    private struct RequestKey: Hashable {
        let asset: URL?
        let custom: Bool
        let revision: Int
    }

    private var variant: Int {
        source.id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % 6 }
    }

    private var palette: (UInt32, UInt32, UInt32) {
        [
            (0x633E50, 0xE6B797, 0xFFF0D7), (0x344B42, 0x9CB8A1, 0xF5E7CF),
            (0x343F56, 0xB4BCCF, 0xF6E8D0), (0x68463D, 0xDDA385, 0xFFF3DC),
            (0x53446B, 0xC3ABCB, 0xF6E8D7), (0x4A4E35, 0xC9B983, 0xFFF4D8),
        ][variant]
    }

    private var isWide: Bool {
        switch source.kind {
        case .youtube, .local_video, .article, .podcast: true
        default: false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let h = geometry.size.height
            let w = geometry.size.width
            let coverWidth = isWide ? w * 0.89 : min(w * 0.9, h * 0.64)
            let coverHeight = isWide ? min(h * 0.89, w * 0.59) : h * 0.9
            ZStack {
                StudyTheme.mat
                if let image = source.coverImage.flatMap({ UIImage(data: $0) }) ?? thumbnail {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: coverWidth, height: coverHeight).clipped()
                        .shadow(color: .black.opacity(0.17), radius: 3, x: 2, y: 3)
                } else {
                    editorialCover(showTitle: w > 80)
                        .frame(width: coverWidth, height: coverHeight)
                        .shadow(color: .black.opacity(0.17), radius: 3, x: 2, y: 3)
                }
            }
        }.accessibilityHidden(true)
            .task(id: RequestKey(asset: asset, custom: source.coverImage != nil, revision: revision)) {
                thumbnail = nil
                author = nil
                guard let asset, source.coverImage == nil else { return }
                let artwork = await StudyThumbnails.artwork(asset, kind: source.kind)
                if !Task.isCancelled {
                    thumbnail = artwork.image
                    author = artwork.author
                }
            }
    }

    private func editorialCover(showTitle: Bool) -> some View {
        let background = Color(uiColor: StudyTheme.rgb(palette.0))
        let lines = Color(uiColor: StudyTheme.rgb(palette.1))
        let lettering = Color(uiColor: StudyTheme.rgb(palette.2))
        return ZStack(alignment: .topLeading) {
            background
            Canvas { context, size in
                let w = size.width
                let h = size.height
                if variant % 3 == 0 {
                    for step in 0..<5 {
                        let d = CGFloat(step) * w * 0.12
                        context.stroke(Path(ellipseIn: CGRect(x: w * 0.19 + d, y: h * 0.43 + d * 0.35,
                            width: w * 1.1, height: w * 1.1)), with: .color(lines.opacity(0.75)), lineWidth: 1)
                    }
                } else if variant % 3 == 1 {
                    for step in 0..<10 {
                        let offset = CGFloat(step) * w * 0.115
                        var line = Path()
                        line.move(to: CGPoint(x: offset - w * 0.4, y: h))
                        line.addLine(to: CGPoint(x: offset + w * 0.48, y: h * 0.44))
                        context.stroke(line, with: .color(lines.opacity(0.64)), lineWidth: step.isMultiple(of: 3) ? 2 : 0.6)
                    }
                } else {
                    let grid = CGRect(x: w * 0.35, y: h * 0.53, width: w * 0.65, height: h * 0.47)
                    context.fill(Path(grid), with: .color(lines.opacity(0.28)))
                    for step in 1..<5 {
                        let y = grid.minY + CGFloat(step) * grid.height / 5
                        var line = Path()
                        line.move(to: CGPoint(x: grid.minX, y: y))
                        line.addLine(to: CGPoint(x: w, y: y))
                        context.stroke(line, with: .color(lines.opacity(0.8)), lineWidth: 0.75)
                    }
                }
            }
            if showTitle {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title).font(.system(.headline, design: .serif)).lineLimit(3)
                    Spacer(minLength: 0)
                    Text(author ?? source.url.flatMap { URL(string: $0)?.host } ?? studioLabel(source.kind.rawValue))
                        .font(.caption2.weight(.semibold)).lineLimit(1)
                }.foregroundStyle(lettering).padding(9)
            } else if isWide {
                Image(systemName: source.kind == .youtube || source.kind == .local_video ? "play.circle" : "doc.text")
                    .foregroundStyle(lettering).padding(7)
            }
        }.border(lines.opacity(0.6)).clipped()
    }
}

@MainActor
enum StudyThumbnails {
    @MainActor final class Artwork {
        let image: UIImage?
        let author: String?
        init(image: UIImage? = nil, author: String? = nil) {
            self.image = image
            let value = author?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.author = value.flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
        }
    }

    private static let memory = NSCache<NSURL, Artwork>()
    private static var requests: [URL: (UUID, Task<Artwork, Never>)] = [:]

    private static func cacheFile(_ asset: URL) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StudyCovers-v2", isDirectory: true)
            .appendingPathComponent(asset.lastPathComponent + ".jpg")
    }

    static func invalidate(_ asset: URL) throws {
        memory.removeObject(forKey: asset as NSURL)
        requests.removeValue(forKey: asset)?.1.cancel()
        if let file = cacheFile(asset) {
            for target in [file, file.appendingPathExtension("author")] where FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
        }
    }

    static func artwork(_ asset: URL, kind: SourceKind) async -> Artwork {
        if let cached = memory.object(forKey: asset as NSURL) { return cached }
        if let request = requests[asset] { return await request.1.value }

        let id = UUID()
        let task = Task { await loadArtwork(asset, kind: kind) }
        requests[asset] = (id, task)
        let artwork = await task.value
        if requests[asset]?.0 == id { requests.removeValue(forKey: asset) }
        return artwork
    }

    private static func loadArtwork(_ asset: URL, kind: SourceKind) async -> Artwork {
        let file = cacheFile(asset)
        if let file, let image = UIImage(contentsOfFile: file.path) {
            let author = try? String(contentsOf: file.appendingPathExtension("author"), encoding: .utf8)
            let cached = Artwork(image: image, author: author)
            memory.setObject(cached, forKey: asset as NSURL)
            return cached
        }

        let original: Artwork
        switch kind {
        case .epub: original = await epubCover(asset)
        case .pdf:
            original = Artwork(author: PDFKit.PDFDocument(url: asset)?
                .documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)
        default: original = Artwork()
        }
        let resolved: Artwork
        if original.image != nil {
            resolved = original
        } else {
            let request = QLThumbnailGenerator.Request(
                fileAt: asset, size: CGSize(width: 320, height: 420), scale: 1, representationTypes: .thumbnail)
            let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.uiImage
            resolved = Artwork(image: image, author: original.author)
        }
        guard !Task.isCancelled else { return resolved }
        memory.countLimit = 96
        memory.setObject(resolved, forKey: asset as NSURL)
        if let file, let data = resolved.image?.jpegData(compressionQuality: 0.76) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let author = resolved.author {
                try? author.write(to: file.appendingPathExtension("author"), atomically: true, encoding: .utf8)
            }
            try? data.write(to: file, options: .atomic)
        }
        return resolved
    }

    private static func epubCover(_ url: URL) async -> Artwork {
        guard let file = FileURL(url: url) else { return Artwork() }
        let retriever = AssetRetriever(httpClient: DefaultHTTPClient())
        guard let asset = try? await retriever.retrieve(url: file).get(),
            let publication = try? await PublicationOpener(parser: EPUBParser()).open(
                asset: asset, allowUserInteraction: false).get()
        else { return Artwork() }
        let image = try? await publication.coverFitting(maxSize: CGSize(width: 320, height: 420)).get()
        return Artwork(image: image, author: publication.metadata.authors.first?.name)
    }
}

struct StudyBoardCover: View {
    let project: LibraryProject

    var body: some View {
        ZStack {
            StudyTheme.plum
            if let data = project.boardCoverImage, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let board = project.board, !board.nodes.isEmpty {
                Canvas { context, size in
                    let minX = board.nodes.map(\.x).min() ?? 0
                    let maxX = board.nodes.map(\.x).max() ?? 1
                    let minY = board.nodes.map(\.y).min() ?? 0
                    let maxY = board.nodes.map(\.y).max() ?? 1
                    let scale = min((size.width - 44) / max(1, maxX - minX),
                        (size.height - 38) / max(1, maxY - minY))
                    let origin = CGPoint(x: (size.width - (maxX - minX) * scale) / 2,
                        y: (size.height - (maxY - minY) * scale) / 2)
                    let points = Dictionary(uniqueKeysWithValues: board.nodes.map {
                        ($0.id, CGPoint(x: origin.x + ($0.x - minX) * scale, y: origin.y + ($0.y - minY) * scale))
                    })
                    for edge in board.edges {
                        guard let start = points[edge.from], let end = points[edge.to] else { continue }
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        context.stroke(path, with: .color(StudyTheme.copper), lineWidth: 1)
                    }
                    for node in board.nodes {
                        guard let p = points[node.id] else { continue }
                        let rect = CGRect(x: p.x - 9, y: p.y - 6, width: 18, height: 12)
                        let color: Color = node.kind == .source ? StudyTheme.copper : StudyTheme.railText
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                    }
                }
            } else {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.largeTitle)
                    .foregroundStyle(StudyTheme.copper)
            }
        }.frame(height: 116).clipped().accessibilityHidden(true)
    }
}

@MainActor
enum StudyCoverImport {
    static func read(_ url: URL) throws -> Data {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 32 * 1024 * 1024 {
            throw LibraryError.invalid("请选择不超过 32 MiB 的封面图片")
        }
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: 420,
        ]
        guard let input = CGImageSourceCreateWithURL(url as CFURL, nil),
            let preview = CGImageSourceCreateThumbnailAtIndex(input, 0, options as CFDictionary),
            let data = UIImage(cgImage: preview).jpegData(compressionQuality: 0.75),
            data.count <= 196_608
        else { throw LibraryError.invalid("无法读取封面图片") }
        return data
    }
}
