import CryptoKit
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
            Text(StudioModel.importTitle(source.title)).font(.subheadline.weight(.semibold)).lineLimit(2)
        }.multilineTextAlignment(.leading)
    }
}

struct StudySourceCover: View {
    let source: LibrarySource
    let asset: URL?
    var revision = 0
    @State private var thumbnail: UIImage?
    @State private var author: String?
    @State private var editorial: UIImage?
    @State private var custom: UIImage?

    private struct RequestKey: Hashable {
        let asset: URL?
        let mode: SourceCoverMode
        let revision: Int
    }

    private var variant: Int {
        let key = source.id.uuidString + source.kind.rawValue + source.title
        let base = key.utf8.reduce(0) { ($0 * 31 + Int($1)) % 6 }
        return (base + max(0, source.coverVariation ?? 0) % 6) % 6
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
                if let image = displayImage ?? (w > 80 ? editorial : nil) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: coverWidth, height: coverHeight).clipped()
                        .shadow(color: .black.opacity(0.17), radius: 3, x: 2, y: 3)
                } else {
                    editorialCover(showTitle: w > 80)
                        .frame(width: coverWidth, height: coverHeight)
                        .shadow(color: .black.opacity(0.17), radius: 3, x: 2, y: 3)
                }
            }
            .task(id: w > 80 ? editorialKey : nil) {
                editorial = nil
                guard w > 80, let key = editorialKey else { return }
                let rendered = await StudyThumbnails.editorialArt(key: key) {
                    let size = isWide ? CGSize(width: 340, height: 218) : CGSize(width: 236, height: 342)
                    let renderer = ImageRenderer(content: editorialCover(showTitle: true)
                        .frame(width: size.width, height: size.height))
                    renderer.scale = 1
                    return renderer.uiImage
                }
                if !Task.isCancelled { editorial = rendered }
            }
        }.accessibilityHidden(true)
            .task(id: source.coverImage) {
                custom = nil
                if let data = source.coverImage {
                    let image = await StudyThumbnails.customArt(data)
                    if !Task.isCancelled { custom = image }
                }
            }
            .task(id: RequestKey(asset: asset, mode: source.resolvedCoverMode, revision: revision)) {
                thumbnail = nil
                author = nil
                guard let asset, source.resolvedCoverMode != .custom else { return }
                let artwork = await StudyThumbnails.artwork(asset, kind: source.kind)
                if !Task.isCancelled {
                    thumbnail = artwork.image
                    author = artwork.author
                }
            }
    }

    private var editorialKey: String? {
        if source.resolvedCoverMode == .custom || (source.resolvedCoverMode == .original && thumbnail != nil) { return nil }
        let host = source.url.flatMap { URL(string: $0)?.host } ?? ""
        return ["v1", String(variant), StudioModel.importTitle(source.title), author ?? "", source.kind.rawValue, host]
            .joined(separator: "\u{1F}")
    }

    private var displayImage: UIImage? {
        switch source.resolvedCoverMode {
        case .custom: custom
        case .original: thumbnail
        case .generated: nil
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
                switch variant {
                case 0:
                    for step in 0..<5 {
                        let d = CGFloat(step) * w * 0.12
                        context.stroke(Path(ellipseIn: CGRect(x: w * 0.19 + d, y: h * 0.43 + d * 0.35,
                            width: w * 1.1, height: w * 1.1)), with: .color(lines.opacity(0.75)), lineWidth: 1)
                    }
                case 1:
                    for step in 0..<10 {
                        let offset = CGFloat(step) * w * 0.115
                        var line = Path()
                        line.move(to: CGPoint(x: offset - w * 0.4, y: h))
                        line.addLine(to: CGPoint(x: offset + w * 0.48, y: h * 0.44))
                        context.stroke(line, with: .color(lines.opacity(0.64)), lineWidth: step.isMultiple(of: 3) ? 2 : 0.6)
                    }
                case 2:
                    let grid = CGRect(x: w * 0.35, y: h * 0.53, width: w * 0.65, height: h * 0.47)
                    context.fill(Path(grid), with: .color(lines.opacity(0.28)))
                    for step in 1..<5 {
                        let y = grid.minY + CGFloat(step) * grid.height / 5
                        var line = Path()
                        line.move(to: CGPoint(x: grid.minX, y: y))
                        line.addLine(to: CGPoint(x: w, y: y))
                        context.stroke(line, with: .color(lines.opacity(0.8)), lineWidth: 0.75)
                    }
                case 3:
                    for step in 0..<5 {
                        let y = h * (0.45 + Double(step) * 0.075)
                        let x = w * (0.22 + Double(step) * 0.095)
                        var leaf = Path()
                        leaf.move(to: CGPoint(x: x, y: h))
                        leaf.addQuadCurve(to: CGPoint(x: w * 0.95, y: y),
                            control: CGPoint(x: x - w * 0.15, y: y + h * 0.04))
                        context.stroke(leaf, with: .color(lines.opacity(0.73)), lineWidth: 1.35)
                    }
                case 4:
                    for step in 0..<4 {
                        let d = Double(step) * w * 0.14
                        let box = CGRect(x: w * 0.09 + d, y: h * 0.42 + d * 0.46,
                            width: w * 0.62, height: h * 0.43)
                        context.fill(Path(box), with: .color(lines.opacity(0.10 + Double(step) * 0.05)))
                        context.stroke(Path(box), with: .color(lines.opacity(0.7)), lineWidth: 0.85)
                    }
                default:
                    for step in 0..<9 {
                        let x = w * (0.09 + Double(step) * 0.105)
                        let top = h * (0.48 + 0.15 * sin(Double(step) * 0.88))
                        let bar = CGRect(x: x, y: top, width: w * 0.05, height: h * 0.92 - top)
                        context.fill(Path(bar), with: .color(lines.opacity(step.isMultiple(of: 2) ? 0.62 : 0.26)))
                    }
                }
            }
            if showTitle {
                VStack(alignment: .leading, spacing: 3) {
                    Text(StudioModel.importTitle(source.title)).font(.system(.headline, design: .serif)).lineLimit(3)
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

    private static var memory = CostBoundedCache<URL, Artwork>(limit: 24 * 1_048_576)
    private static var editorialMemory = CostBoundedCache<String, UIImage>(limit: 12 * 1_048_576)
    private static var customMemory = CostBoundedCache<Data, UIImage>(limit: 12 * 1_048_576)
    @MainActor private final class Request {
        let id = UUID()
        let task: Task<Artwork, Never>
        var consumers: Set<UUID> = []
        init(task: Task<Artwork, Never>) { self.task = task }
    }
    private static var requests: [URL: Request] = [:]
    private static var activeLoads = 0
    private static var waiting: [CheckedContinuation<Void, Never>] = []
    private static var generation = 0

    static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StudyCovers-v2", isDirectory: true)
    }
    private static func cacheFile(_ asset: URL) -> URL? {
        cacheDirectory?.appendingPathComponent(asset.lastPathComponent + ".jpg")
    }
    static func apply(_ budget: PerformanceBudget) {
        memory.limit = budget.artworkBytes
        editorialMemory.limit = budget.editorialBytes
        customMemory.limit = budget.customCoverBytes
    }
    static func releaseMemory() {
        generation &+= 1
        memory.removeAll(); editorialMemory.removeAll(); customMemory.removeAll()
        for request in requests.values { request.task.cancel() }
        requests.removeAll()
    }
    static func clearCache() async throws {
        releaseMemory()
        if let cacheDirectory { try await CoverDiskWorker.shared.clear(cacheDirectory) }
    }
    private static func cost(_ image: UIImage?) -> Int {
        image?.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
    }
    static func customArt(_ data: Data) async -> UIImage? {
        _ = PerformancePolicy.shared
        if let image = customMemory.value(for: data) { return image }
        let epoch = generation
        guard let bitmap = await CoverDiskWorker.shared.read(data), !Task.isCancelled else { return nil }
        let image = UIImage(cgImage: bitmap.image)
        if generation == epoch { customMemory.insert(image, for: data, cost: bitmap.cost + data.count) }
        return image
    }
    static func editorialArt(key: String, draw: () -> UIImage?) async -> UIImage? {
        _ = PerformancePolicy.shared
        if let cached = editorialMemory.value(for: key) { return cached }
        let epoch = generation
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = cacheDirectory?.appendingPathComponent("editorial-" + digest + ".jpg")
        var existing: UIImage?
        if let file, let bitmap = await CoverDiskWorker.shared.read(file) { existing = UIImage(cgImage: bitmap.image) }
        guard !Task.isCancelled, generation == epoch, let image = existing ?? draw() else { return nil }
        editorialMemory.insert(image, for: key, cost: cost(image))
        if existing == nil, let file, let bitmap = image.cgImage {
            await CoverDiskWorker.shared.write(CoverBitmap(image: bitmap), to: file, quality: 0.86)
        }
        return image
    }
    static func artwork(_ asset: URL, kind: SourceKind) async -> Artwork {
        _ = PerformancePolicy.shared
        if let cached = memory.value(for: asset) { return cached }
        let request: Request
        if let existing = requests[asset] { request = existing }
        else {
            let epoch = generation
            request = Request(task: Task { await loadArtwork(asset, kind: kind, epoch: epoch) })
            requests[asset] = request
        }
        let consumer = UUID()
        request.consumers.insert(consumer)
        let artwork = await withTaskCancellationHandler {
            await request.task.value
        } onCancel: {
            Task { @MainActor in releaseConsumer(consumer, asset: asset, request: request) }
        }
        releaseConsumer(consumer, asset: asset, request: request)
        return artwork
    }
    private static func releaseConsumer(_ consumer: UUID, asset: URL, request: Request) {
        guard requests[asset]?.id == request.id else { return }
        request.consumers.remove(consumer)
        if request.consumers.isEmpty {
            request.task.cancel()
            requests.removeValue(forKey: asset)
        }
    }
    private static func acquire() async {
        // Transfer a permit to the next waiter on release, avoiding a polling timer.
        if activeLoads >= PerformancePolicy.shared.budget.artworkConcurrency {
            await withCheckedContinuation { waiting.append($0) }
        } else { activeLoads += 1 }
    }
    private static func release() {
        activeLoads -= 1
        while activeLoads < PerformancePolicy.shared.budget.artworkConcurrency, !waiting.isEmpty {
            activeLoads += 1
            waiting.removeFirst().resume()
        }
    }
    private static func loadArtwork(_ asset: URL, kind: SourceKind, epoch: Int) async -> Artwork {
        await acquire()
        let trace = PerformanceTrace.signposter.beginInterval("CoverLoad", id: PerformanceTrace.signposter.makeSignpostID())
        defer { release(); PerformanceTrace.signposter.endInterval("CoverLoad", trace) }
        guard !Task.isCancelled else { return Artwork() }
        let file = cacheFile(asset)
        if let file, let bitmap = await CoverDiskWorker.shared.read(file) {
            let author = await CoverDiskWorker.shared.author(asset, cachedFile: file)
            let cached = Artwork(image: UIImage(cgImage: bitmap.image), author: author)
            if generation == epoch, !Task.isCancelled { memory.insert(cached, for: asset, cost: bitmap.cost) }
            return cached
        }
        let original: Artwork
        switch kind {
        case .epub: original = await epubCover(asset)
        case .pdf: original = Artwork(author: await CoverDiskWorker.shared.author(asset, cachedFile: nil))
        default: original = Artwork()
        }
        guard !Task.isCancelled else { return Artwork() }
        let resolved: Artwork
        if original.image != nil { resolved = original }
        else {
            let request = QLThumbnailGenerator.Request(
                fileAt: asset, size: CGSize(width: 320, height: 420), scale: 1, representationTypes: .thumbnail)
            let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.uiImage
            resolved = Artwork(image: image, author: original.author)
        }
        guard !Task.isCancelled, generation == epoch else { return resolved }
        memory.insert(resolved, for: asset, cost: cost(resolved.image))
        if let file, let image = resolved.image?.cgImage {
            await CoverDiskWorker.shared.write(CoverBitmap(image: image), to: file, quality: 0.76, author: resolved.author)
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
    @State private var custom: UIImage?

    var body: some View {
        ZStack {
            StudyTheme.plum
            if let image = custom {
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
            .task(id: project.boardCoverImage) {
                custom = nil
                if let data = project.boardCoverImage {
                    let image = await StudyThumbnails.customArt(data)
                    if !Task.isCancelled { custom = image }
                }
            }
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
