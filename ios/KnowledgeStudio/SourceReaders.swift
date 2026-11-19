import AVKit
import KnowledgeCore
import PDFKit
@preconcurrency import ReadiumNavigator
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer
import SwiftUI

struct SourceReaderView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource
    var location: ReadingLocator?
    @State private var attach = false
    var body: some View {
        Group {
            if let url = model.assetURL(source), FileManager.default.fileExists(atPath: url.path) {
                switch source.kind {
                case .pdf: PDFStudyView(source: source, url: url, location: location ?? source.lastLocation)
                case .epub: EPUBStudyView(source: source, url: url, location: location ?? source.lastLocation)
                case .local_video:
                    LocalVideoStudyView(source: source, url: url, location: location ?? source.lastLocation)
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
                    ContentUnavailableView(
                        "原始资料尚未绑定或不可用", systemImage: "doc.questionmark",
                        description: Text("卡片和出处定位仍保留，请绑定相同的原始文件。"))
                    Button("绑定原始文件") { attach = true }
                }
            }
        }.navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $attach, allowedContentTypes: [.pdf, .movie, .data]) { result in
                Task {
                    do { await model.importFile(try result.get(), replacing: source.id) } catch {
                        model.message = error.localizedDescription
                    }
                }
            }
    }
    private func destination(_ url: URL) -> URL {
        if source.kind == .article, let json = location?.nativeJSON,
            let quote = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])?[
                "textQuote"], !quote.isEmpty
        {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.fragment = ":~:text=" + quote
            return parts.url ?? url
        }
        guard let seconds = location?.seconds, [.youtube, .podcast].contains(source.kind) else { return url }
        if source.kind == .podcast {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.fragment = "t=\(seconds)"
            return parts.url ?? url
        }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var query = parts.queryItems ?? []
        query.removeAll { $0.name == "t" }
        query.append(URLQueryItem(name: "t", value: String(Int(seconds))))
        parts.queryItems = query
        return parts.url ?? url
    }
}

@MainActor
final class PDFSession: ObservableObject {
    let view = PDFView()
    @Published var anchorStatus = ""
    private var restored = false
    init(url: URL, location: ReadingLocator?) {
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFKit.PDFDocument(url: url)

    }
    func restore(_ locator: ReadingLocator?, fingerprint: String?) {
        guard !restored, let locator, let document = view.document else { return }
        restored = true
        let accuracy = locator.pdfAccuracy(currentFingerprint: fingerprint, pageCount: document.pageCount)
        switch accuracy {
        case .unavailable: anchorStatus = "出处不可定位：文件指纹或页码不符，未执行跳转"
        case .pageOnly:
            if let number = locator.page, let page = document.page(at: number - 1) { view.go(to: page) }
            anchorStatus = "仅页面定位：此记录缺少可核对的区域锚点"
        case .exactRegion, .exactText:
            guard let rect = locator.rectangles.first, let page = document.page(at: rect.page - 1) else {
                return
            }
            let bounds = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            guard page.bounds(for: .cropBox).contains(bounds) else {
                view.go(to: page)
                anchorStatus = "仅页面定位：保存区域超出书页范围"
                return
            }
            view.go(to: bounds, on: page)
            anchorStatus = "精确区域定位（不推断文字匹配）"
        }
    }
    var pageNumber: Int? {
        guard let page = view.currentPage, let document = view.document else { return nil }
        return document.index(for: page) + 1
    }
}
struct PDFStudyView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource
    @State private var regionMode = false
    private let initialLocation: ReadingLocator?
    private let url: URL
    @State private var kind: CardKind = .expression
    @StateObject private var session: PDFSession
    init(source: LibrarySource, url: URL, location: ReadingLocator?) {
        self.source = source
        self.url = url
        initialLocation = location ?? source.lastLocation
        _session = StateObject(wrappedValue: PDFSession(url: url, location: location ?? source.lastLocation))
    }
    var body: some View {
        VStack(spacing: 0) {
            if session.view.document == nil { Text("PDF 无法打开或已损坏，原文件保留。") }
            PDFHost(
                view: session.view,
                marks: model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil },
                regionMode: regionMode,
                onRegion: { rect in
                    var locator = ReadingLocator(kind: "pdf", page: rect.page)
                    locator.rectangles = [rect]
                    locator.fileFingerprint = source.assetHash
                    model.saveMark(source: source, locator: locator, kind: kind)
                    regionMode = false
                })
            if !session.anchorStatus.isEmpty {
                Text(session.anchorStatus).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Toggle("区域标记", isOn: $regionMode).toggleStyle(.button)

                Picker("标记类型", selection: $kind) {
                    ForEach(CardKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Button("保存选文或页码") {
                    guard let page = session.pageNumber, let document = session.view.document else { return }
                    let selection = session.view.currentSelection
                    var locator = ReadingLocator(
                        kind: "pdf", page: selection?.pages.first.map { document.index(for: $0) + 1 } ?? page)
                    for line in selection?.selectionsByLine() ?? [] {
                        for page in line.pages {
                            let bounds = line.bounds(for: page)
                            locator.rectangles.append(
                                HighlightRect(
                                    page: document.index(for: page) + 1, x: bounds.origin.x,
                                    y: bounds.origin.y, width: bounds.width, height: bounds.height))
                        }
                    }
                    locator.fileFingerprint = source.assetHash
                    locator.anchorText = selection?.string
                    model.saveMark(
                        source: source, locator: locator, excerpt: selection?.string ?? "", kind: kind)
                }.buttonStyle(.borderedProminent)
                Button {
                    WordPronunciation.shared.speak(session.view.currentSelection?.string ?? "")
                } label: {
                    Label("听发音", systemImage: "speaker.wave.2")
                }
                Text("长按选择文字可保存摘录与高亮；扫描页可开启区域标记，长按拖出范围；跨页区域请分次标记。").font(.caption)
            }.padding()
        }.task {
            do {
                let fingerprint = try await Task.detached { try StudioModel.hash(url) }.value
                session.restore(initialLocation, fingerprint: fingerprint)
            } catch { session.anchorStatus = "无法核对文件指纹，未执行精确回跳" }
        }.onDisappear {
            if let page = session.pageNumber {
                model.saveLocation(sourceID: source.id, locator: ReadingLocator(kind: "pdf", page: page))
            }
        }
    }
}
struct PDFHost: UIViewRepresentable {
    let view: PDFView
    let marks: [LibraryMark]
    var regionMode = false
    var onRegion: ((HighlightRect) -> Void)?
    func makeUIView(context: Context) -> PDFView {
        let gesture = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.capture(_:)))
        gesture.minimumPressDuration = 0.3
        gesture.isEnabled = regionMode
        view.addGestureRecognizer(gesture)
        context.coordinator.gesture = gesture
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onRegion = onRegion
        context.coordinator.gesture?.isEnabled = regionMode
        guard let document = view.document else { return }
        let ids = marks
        guard ids != context.coordinator.ids else { return }
        context.coordinator.ids = ids
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations
            where annotation.contents?.hasPrefix("KnowledgeStudio:") == true {
                page.removeAnnotation(annotation)
            }
        }
        for mark in marks {
            for rect in mark.locator.rectangles {
                guard rect.isValid, let page = document.page(at: rect.page - 1) else { continue }
                let annotation = PDFAnnotation(
                    bounds: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                    forType: .highlight, withProperties: nil)
                annotation.color = mark.highlightKind.highlightColor.withAlphaComponent(0.4)
                annotation.contents = "KnowledgeStudio:" + mark.id.uuidString
                page.addAnnotation(annotation)
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator: NSObject {
        var ids: [LibraryMark] = []
        var gesture: UILongPressGestureRecognizer?
        var onRegion: ((HighlightRect) -> Void)?
        private var start: CGPoint?
        private var page: PDFPage?
        private let outline = CAShapeLayer()
        @objc func capture(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view as? PDFView else { return }
            let point = gesture.location(in: view)
            if gesture.state == .began {
                start = point
                page = view.page(for: point, nearest: false)
                outline.fillColor = UIColor.systemYellow.withAlphaComponent(0.2).cgColor
                outline.strokeColor = UIColor.systemOrange.cgColor
                view.layer.addSublayer(outline)
            }
            guard let start, let page else { return }
            let screen = CGRect(
                x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x),
                height: abs(point.y - start.y))
            outline.path = UIBezierPath(rect: screen).cgPath
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                defer {
                    outline.removeFromSuperlayer()
                    self.start = nil
                    self.page = nil
                }
                guard gesture.state == .ended, screen.width >= 8, screen.height >= 8,
                    view.page(for: point, nearest: false) === page, let document = view.document
                else { return }
                let rect = view.convert(screen, to: page).intersection(page.bounds(for: .cropBox))
                guard !rect.isNull, !rect.isEmpty else { return }
                onRegion?(
                    HighlightRect(
                        page: document.index(for: page) + 1, x: rect.minX, y: rect.minY, width: rect.width,
                        height: rect.height))
            }
        }
    }
}

@MainActor
final class VideoSession: ObservableObject {
    let player: AVPlayer
    init(url: URL, location: ReadingLocator?) {
        player = AVPlayer(url: url)
        if let seconds = location?.seconds {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
    }
}
struct LocalVideoStudyView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource
    @StateObject private var session: VideoSession
    init(source: LibrarySource, url: URL, location: ReadingLocator?) {
        self.source = source
        _session = StateObject(
            wrappedValue: VideoSession(url: url, location: location ?? source.lastLocation))
    }
    var body: some View {
        VStack {
            VideoPlayer(player: session.player)
            Button("保存时间标记") {
                let seconds = session.player.currentTime().seconds
                guard session.player.currentItem?.status == .readyToPlay, seconds.isFinite, seconds >= 0
                else {
                    model.message = "未取得有效播放位置，本次未保存"
                    return
                }
                model.saveMark(source: source, locator: ReadingLocator(kind: "video", seconds: seconds))
            }.buttonStyle(.borderedProminent).padding()
        }.onDisappear {
            let seconds = session.player.currentTime().seconds
            session.player.pause()
            if seconds.isFinite && seconds >= 0 {
                model.saveLocation(
                    sourceID: source.id, locator: ReadingLocator(kind: "video", seconds: seconds))
            }
        }
    }
}

@MainActor
final class EPUBSession: NSObject, ObservableObject, EPUBNavigatorDelegate {
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        locationWarning = "此书籍限制复制，无法完成所选操作。"
    }
    func navigator(
        _ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError
    ) {
        locationWarning = "部分书页资源无法读取，请检查原始书籍文件。原有标记仍保留。"
    }
    var savePosition: ((ReadingLocator) -> Void)?
    var saveSelection: ((ReadingLocator, String, CardKind) -> Void)?
    var selectMark: ((UUID) -> Void)?
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        if let value = try? Self.readingLocator(locator) { savePosition?(value) }
    }
    static func readingLocator(_ locator: Locator) throws -> ReadingLocator {
        ReadingLocator(
            kind: "epub", href: locator.href.string, progression: locator.locations.progression,
            nativeJSON: try locator.jsonString())
    }
    @Published var navigator: EPUBNavigatorViewController?
    @Published var error: String?
    @Published var locationWarning: String?
    func open(url: URL, location: ReadingLocator?) async {
        guard navigator == nil else { return }
        do {
            guard let file = FileURL(url: url) else { throw LibraryError.invalid("EPUB 文件路径无效") }
            let retriever = AssetRetriever(httpClient: DefaultHTTPClient())
            let asset = try await retriever.retrieve(url: file).get()
            let publication = try await PublicationOpener(parser: EPUBParser()).open(
                asset: asset, allowUserInteraction: false
            ).get()
            var initial: Locator?
            if let json = location?.nativeJSON,
                let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            {
                initial = try? Locator(json: ReadiumShared.JSONValue(object), warnings: nil)
            }
            if initial == nil, let href = location?.href,
                let link = publication.readingOrder.first(where: { $0.href == href })
            {
                initial = await publication.locate(link)
                if let progression = location?.progression {
                    initial = initial?.copy(locations: { $0.progression = progression })
                }
                locationWarning = "缺少完整选文定位，已回到章节阅读位置；不能保证精确到原句。"
            }
            if location != nil && initial == nil { locationWarning = "此定位无法精确还原，已打开资料。可在阅读器中重新标记。" }
            let reader = try StudyEPUBNavigator(
                publication: publication, initialLocation: initial,
                config: .init(editingActions: [
                    EditingAction(title: "单词高亮", action: #selector(StudyEPUBNavigator.markWord)),
                    EditingAction(title: "语料高亮", action: #selector(StudyEPUBNavigator.markExpression)),
                    EditingAction(title: "关键词高亮", action: #selector(StudyEPUBNavigator.markKeyword)),
                    EditingAction(title: "关键句高亮", action: #selector(StudyEPUBNavigator.markSentence)),
                    EditingAction(title: "听发音（合成语音）", action: #selector(StudyEPUBNavigator.pronounce)),
                    .copy, .lookup,
                ]))
            reader.capture = { [weak self, weak reader] kind in
                guard let locator = reader?.currentSelection?.locator, let text = locator.text.highlight,
                    !text.isEmpty
                else { return }
                do { self?.saveSelection?(try Self.readingLocator(locator), text, kind) } catch {
                    self?.error = "选文定位未保存：\(error.localizedDescription)"
                }
            }
            reader.observeDecorationInteractions(inGroup: "knowledge-marks") { [weak self] event in
                if let id = UUID(uuidString: event.decoration.id) { self?.selectMark?(id) }
            }
            reader.delegate = self
            navigator = reader
        } catch { self.error = "EPUB 无法打开（不支持 DRM）：\(error.localizedDescription)" }
    }
    func location(selection: Bool) throws -> (ReadingLocator, String)? {
        guard let navigator,
            let locator = selection
                ? navigator.currentSelection?.locator
                : navigator.currentLocation
        else { return nil }
        return (
            ReadingLocator(
                kind: "epub", href: locator.href.string, progression: locator.locations.progression,
                nativeJSON: try locator.jsonString()),
            selection ? navigator.currentSelection?.locator.text.highlight ?? "" : ""
        )
    }
}
final class StudyEPUBNavigator: EPUBNavigatorViewController {
    var capture: ((CardKind) -> Void)?
    @objc func pronounce() {
        WordPronunciation.shared.speak(currentSelection?.locator.text.highlight ?? "")
    }
    @objc func markWord() { capture?(.word) }
    @objc func markExpression() { capture?(.expression) }
    @objc func markKeyword() { capture?(.keyword) }
    @objc func markSentence() { capture?(.key_sentence) }
}
struct EPUBStudyView: View {
    @EnvironmentObject private var model: StudioModel
    let source: LibrarySource, url: URL
    let location: ReadingLocator?
    @StateObject private var session = EPUBSession()
    @AppStorage("readerFontSize") private var fontSize = 110.0
    @AppStorage("readerLineHeight") private var lineHeight = 1.6
    @AppStorage("readerTheme") private var theme = "sepia"
    @AppStorage("readerColumns") private var columns = true
    @State private var settings = false
    @State private var selectedMark: LibraryMark?
    @AppStorage("readerFont") private var font = "serif"
    var body: some View {
        VStack {
            if let warning = session.locationWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            if let error = session.error {
                Text(error)
            } else if let navigator = session.navigator {
                EPUBHost(
                    navigator: navigator,
                    marks: model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil })
            } else {
                ProgressView("正在打开 EPUB…")
            }
            HStack {
                Text("选中文字后，点选对应颜色高亮；备注可在收集箱中编辑。").font(.caption).foregroundStyle(.secondary)
                Button("保存当前位置") {
                    do {
                        guard let (locator, _) = try session.location(selection: false) else {
                            throw LibraryError.invalid("尚未取得阅读位置")
                        }
                        model.saveMark(source: source, locator: locator)
                    } catch { model.message = error.localizedDescription }
                }
                Button("阅读设置") { settings = true }
            }.padding()
        }.task {
            session.selectMark = { id in selectedMark = model.state.marks.first { $0.id == id } }
            session.savePosition = { model.saveLocation(sourceID: source.id, locator: $0) }
            session.saveSelection = { model.saveMark(source: source, locator: $0, excerpt: $1, kind: $2) }
            await session.open(url: url, location: location)
            applyPreferences()
        }
        .onChange(of: font) { _, _ in applyPreferences() }
        .sheet(item: $selectedMark) { mark in
            NavigationStack {
                MarkDetailView(markID: mark.id).toolbar { Button("完成") { selectedMark = nil } }
            }.environmentObject(model)
        }
        .onChange(of: fontSize) { _, _ in applyPreferences() }
        .onChange(of: lineHeight) { _, _ in applyPreferences() }
        .onChange(of: theme) { _, _ in applyPreferences() }
        .onChange(of: columns) { _, _ in applyPreferences() }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Picker("字体", selection: $font) {
                        Text("衬线阅读体").tag("serif")
                        Text("无衬线体").tag("sans")
                    }
                    Section("字号") {
                        Slider(value: $fontSize, in: 80...180, step: 10)
                        Text("\(Int(fontSize))%")
                    }
                    Section("行距") { Slider(value: $lineHeight, in: 1.2...2.2, step: 0.1) }
                    Picker("书页", selection: $theme) {
                        Text("纸白").tag("light")
                        Text("暖纸").tag("sepia")
                        Text("夜读").tag("dark")
                    }
                    Toggle("宽屏自动双页", isOn: $columns)
                    Text("双页按可用宽度与书籍排版自动调整；固定版式书籍可能不支持字号和行距调整。").font(.caption)
                }.navigationTitle("阅读设置").toolbar { Button("完成") { settings = false } }
            }.presentationDetents([.medium])
        }
        .onDisappear {
            if let value = try? session.location(selection: false) {
                model.saveLocation(sourceID: source.id, locator: value.0)
            }
        }
    }
    private func applyPreferences() {
        session.navigator?.submitPreferences(
            EPUBPreferences(
                columnCount: columns ? .auto : .one, fontFamily: font == "serif" ? .serif : .sansSerif,
                fontSize: fontSize, lineHeight: lineHeight,
                theme: theme == "dark" ? .dark : theme == "light" ? .light : .sepia))
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
                let locator = try? Locator(json: ReadiumShared.JSONValue(object), warnings: nil)
            else { return nil }
            return Decoration(
                id: mark.id.uuidString, locator: locator,
                style: .highlight(tint: mark.highlightKind.highlightColor))
        }
        controller.apply(decorations: decorations, in: "knowledge-marks")
    }
}
