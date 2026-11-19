import SwiftUI
import PDFKit
import AVKit
import KnowledgeCore
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer
@preconcurrency import ReadiumNavigator

struct SourceReaderView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource
    var location: ReadingLocator?
    @State private var attach = false
    var body: some View {
        Group {
            if let url = model.assetURL(source), FileManager.default.fileExists(atPath: url.path) {
                switch source.kind {
                case .pdf: PDFStudyView(source: source, url: url, location: location)
                case .epub: EPUBStudyView(source: source, url: url, location: location)
                case .local_video: LocalVideoStudyView(source: source, url: url, location: location)
                default: Text("不支持的本地资料类型")
                }
            } else if let value = source.url, let url = URL(string: value), url.scheme == "https" {
                VStack(spacing: 20) {
                    Text(source.title).font(.title2)
                    Link("在 Safari 打开出处", destination: destination(url))
                    Text("在 Safari 原页面学习并使用扩展采集。")
                }.padding()
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView("原始资料尚未绑定或不可用", systemImage: "doc.questionmark", description: Text("卡片和出处定位仍保留，请绑定相同的原始文件。"))
                    Button("绑定原始文件") { attach = true }
                }
            }
        }.navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $attach, allowedContentTypes: [.pdf, .movie, .data]) { result in
                do { model.importFile(try result.get(), replacing: source.id) } catch { model.message = error.localizedDescription }
            }
    }
    private func destination(_ url: URL) -> URL {
        if source.kind == .article, let json = location?.nativeJSON,
           let quote = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])?["textQuote"], !quote.isEmpty {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.fragment = ":~:text=" + quote
            return parts.url ?? url
        }
        guard let seconds = location?.seconds, [.youtube, .podcast].contains(source.kind) else { return url }
        if source.kind == .podcast { var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!; parts.fragment = "t=\(seconds)"; return parts.url ?? url }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var query = parts.queryItems ?? []; query.removeAll { $0.name == "t" }; query.append(URLQueryItem(name: "t", value: String(Int(seconds))))
        parts.queryItems = query; return parts.url ?? url
    }
}

@MainActor
final class PDFSession: ObservableObject {
    let view = PDFView()
    init(url: URL, location: ReadingLocator?) {
        view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        if let page = location?.page, let target = view.document?.page(at: page - 1) { view.go(to: target) }
    }
    var pageNumber: Int? { guard let page = view.currentPage, let document = view.document else { return nil }; return document.index(for: page) + 1 }
}
struct PDFStudyView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource
    @StateObject private var session: PDFSession
    init(source: LibrarySource, url: URL, location: ReadingLocator?) { self.source = source; _session = StateObject(wrappedValue: PDFSession(url: url, location: location)) }
    var body: some View {
        VStack(spacing: 0) {
            if session.view.document == nil { Text("PDF 无法打开或已损坏，原文件保留。") }
            PDFHost(view: session.view, marks: model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil })
            HStack {
                Button("Mark／保存选文") {
                    guard let page = session.pageNumber, let document = session.view.document else { return }
                    let selection = session.view.currentSelection
                    var locator = ReadingLocator(kind: "pdf", page: selection?.pages.first.map { document.index(for: $0) + 1 } ?? page)
                    for line in selection?.selectionsByLine() ?? [] {
                        for page in line.pages {
                            let bounds = line.bounds(for: page)
                            locator.rectangles.append(HighlightRect(page: document.index(for: page) + 1, x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height))
                        }
                    }
                    model.saveMark(source: source, locator: locator, excerpt: selection?.string ?? "")
                }.buttonStyle(.borderedProminent)
                Text("长按选择文字可保存摘录与高亮；扫描 PDF 无文字层时仅记录页码。") .font(.caption)
            }.padding()
        }.onDisappear { if let page = session.pageNumber { model.saveLocation(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: page)) } }
    }
}
struct PDFHost: UIViewRepresentable {
    let view: PDFView
    let marks: [LibraryMark]
    func makeUIView(context: Context) -> PDFView { view }
    func updateUIView(_ view: PDFView, context: Context) {
        guard let document = view.document else { return }
        let ids = Set(marks.map(\.id))
        guard ids != context.coordinator.ids else { return }; context.coordinator.ids = ids
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations where annotation.contents?.hasPrefix("KnowledgeStudio:") == true { page.removeAnnotation(annotation) }
        }
        for mark in marks {
            for rect in mark.locator.rectangles {
                guard let page = document.page(at: rect.page - 1) else { continue }
                let annotation = PDFAnnotation(bounds: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), forType: .highlight, withProperties: nil)
                annotation.color = .yellow.withAlphaComponent(0.4); annotation.contents = "KnowledgeStudio:" + mark.id.uuidString
                page.addAnnotation(annotation)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var ids: Set<UUID> = [] }
}

@MainActor
final class VideoSession: ObservableObject {
    let player: AVPlayer
    init(url: URL, location: ReadingLocator?) {
        player = AVPlayer(url: url)
        if let seconds = location?.seconds { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) }
    }
}
struct LocalVideoStudyView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource
    @StateObject private var session: VideoSession
    init(source: LibrarySource, url: URL, location: ReadingLocator?) { self.source = source; _session = StateObject(wrappedValue: VideoSession(url: url, location: location)) }
    var body: some View {
        VStack {
            VideoPlayer(player: session.player)
            Button("Mark") {
                let seconds = session.player.currentTime().seconds
                guard session.player.currentItem?.status == .readyToPlay, seconds.isFinite, seconds >= 0 else { model.message = "未取得有效播放位置，本次未保存"; return }
                model.saveMark(source: source, locator: ReadingLocator(kind: "video", seconds: seconds))
            }.buttonStyle(.borderedProminent).padding()
        }.onDisappear { let seconds = session.player.currentTime().seconds; session.player.pause(); if seconds.isFinite && seconds >= 0 { model.saveLocation(sourceID: source.id, locator: ReadingLocator(kind: "video", seconds: seconds)) } }
    }
}

@MainActor
final class EPUBSession: ObservableObject {
    @Published var navigator: EPUBNavigatorViewController?
    @Published var error: String?
    func open(url: URL, location: ReadingLocator?) async {
        do {
            guard let file = FileURL(url: url) else { throw LibraryError.invalid("EPUB 文件路径无效") }
            let retriever = AssetRetriever(httpClient: DefaultHTTPClient())
            let asset = try await retriever.retrieve(url: file).get()
            let publication = try await PublicationOpener(parser: EPUBParser()).open(asset: asset, allowUserInteraction: false).get()
            var initial: Locator?
            if let json = location?.nativeJSON, let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                initial = try? Locator(json: object, warnings: nil)
            }
            if initial == nil, let href = location?.href, let link = publication.readingOrder.first(where: { $0.href.string == href }) {
                initial = await publication.locate(link)
            }
            navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: initial)
        } catch { self.error = "EPUB 无法打开（不支持 DRM）：\(error.localizedDescription)" }
    }
    func location(selection: Bool) throws -> (ReadingLocator, String)? {
        guard let navigator, let locator = selection ? (navigator.currentSelection?.locator ?? navigator.currentLocation) : navigator.currentLocation else { return nil }
        return (ReadingLocator(kind: "epub", href: locator.href.string, progression: locator.locations.progression, nativeJSON: try locator.jsonString()), selection ? navigator.currentSelection?.locator.text.highlight ?? "" : "")
    }
}
struct EPUBStudyView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource, url: URL
    let location: ReadingLocator?
    @StateObject private var session = EPUBSession()
    var body: some View {
        VStack {
            if let error = session.error { Text(error) }
            else if let navigator = session.navigator { EPUBHost(navigator: navigator, marks: model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil }) }
            else { ProgressView("正在打开 EPUB…") }
            Button("Mark／保存选文") { do { guard let (locator, text) = try session.location(selection: true) else { throw LibraryError.invalid("阅读器尚未提供定位") }; model.saveMark(source: source, locator: locator, excerpt: text) } catch { model.message = error.localizedDescription } }.buttonStyle(.borderedProminent).padding()
        }.task { await session.open(url: url, location: location) }
            .onDisappear { if let value = try? session.location(selection: false) { model.saveLocation(sourceID: source.id, locator: value.0) } }
    }
}
struct EPUBHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    let marks: [LibraryMark]
    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { navigator }
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {
        let decorations: [Decoration] = marks.compactMap { mark in
            guard !mark.excerpt.isEmpty, let json = mark.locator.nativeJSON,
                  let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let locator = try? Locator(json: object, warnings: nil) else { return nil }
            return Decoration(id: mark.id.uuidString, locator: locator, style: .highlight(tint: .yellow))
        }
        controller.apply(decorations: decorations, in: "knowledge-marks")
    }
}
