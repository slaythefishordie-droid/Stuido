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
    @State private var readerID = UUID()
    @Environment(\.studyReaderPresentation) private var readerPresentation
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
        }.studySurface().navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if [.pdf, .epub, .local_video].contains(source.kind) { readerPresentation.setActive(readerID, true) }
            }.onDisappear { readerPresentation.setActive(readerID, false) }
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
    let view = StudyPDFView()
    let ink = PDFStudyInk()
    @Published var anchorStatus = "正在核对原始资料…"
    @Published var verifiedFingerprint: String?
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
            if let number = locator.page, let page = document.page(at: number - 1) {
                if locator.fileFingerprint == fingerprint, let point = locator.pdfViewportPoint {
                    let destination = CGPoint(x: point.x, y: point.y)
                    if page.bounds(for: .cropBox).contains(destination) {
                        view.go(to: PDFDestination(page: page, at: destination))
                        return
                    }
                }
                view.go(to: page)
            }
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
            let anchors = locator.pdfTextAnchors ?? []
            let verified =
                !anchors.isEmpty
                && anchors.allSatisfy { anchor in
                    guard anchor.page > 0, anchor.page <= document.pageCount,
                        let text = document.page(at: anchor.page - 1)?.string
                    else { return false }
                    return anchor.matches(text)
                }
            anchorStatus = verified ? "精确文字定位：文件、文字范围与上下文一致" : "精确区域定位（未确认文字匹配）"
        }
    }
    func setLayout(spread: Bool, continuous: Bool, book: Bool, rtl: Bool) {
        let mode: PDFDisplayMode = spread
            ? (continuous ? .twoUpContinuous : .twoUp)
            : (continuous ? .singlePageContinuous : .singlePage)
        guard view.displayMode != mode || view.displaysAsBook != book || view.displaysRTL != rtl else { return }
        let selection = view.currentSelection
        let destination = view.currentDestination
        let originalPage = view.currentPage
        view.displayMode = mode
        view.displaysAsBook = book
        view.displaysRTL = rtl
        view.autoScales = true
        view.layoutDocumentView()
        if let destination { view.go(to: destination) }
        else if let originalPage { view.go(to: originalPage) }
        if let selection { view.setCurrentSelection(selection, animate: false) }
    }

    func readingPosition() -> ReadingLocator? {
        guard let pageNumber else { return nil }
        var locator = ReadingLocator(kind: "pdf", page: pageNumber)
        locator.fileFingerprint = verifiedFingerprint
        if let destination = view.currentDestination, let page = view.currentPage,
            destination.page === page, page.bounds(for: .cropBox).contains(destination.point)
        {
            locator.pdfViewportPoint = .init(x: destination.point.x, y: destination.point.y)
        }
        return locator
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
    @State private var recognizing = false
    @State private var recognized: [RecognizedPDFRegion] = []
    @State private var showRecognition = false
    @State private var selectedMark: LibraryMark?
    @State private var dictionaryWord: String?
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("studyPDFLayout") private var layout = StudyPageLayout.automatic.rawValue
    @AppStorage("studyPDFContinuous") private var continuous = true
    @AppStorage("studyPDFBook") private var book = true
    @AppStorage("studyPDFRTL") private var rtl = false
    @AppStorage("studyPDFFingerInk") private var fingerInk = false
    @State private var readerSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            StudyReaderDock {
                readerContent
            } tools: {
                PDFStudyDockControls(ink: session.ink, selection: $kind, enabled: session.verifiedFingerprint != nil,
                    save: { capture(kind: kind, annotate: false) }, choose: selectInkTool) { pdfOptions }
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                readerSize = size
                updateLayout()
            }
        }
        .onChange(of: layout) { _, _ in updateLayout() }
        .onChange(of: continuous) { _, _ in updateLayout() }
        .onChange(of: book) { _, _ in updateLayout() }
        .onChange(of: rtl) { _, _ in updateLayout() }
        .onChange(of: kind) { _, value in
            session.ink.choose(session.ink.tool, kind: value, fingerInk: fingerInk)
        }
        .onChange(of: fingerInk) { _, value in
            session.ink.choose(session.ink.tool, kind: kind, fingerInk: value)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.ink.flush() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged, object: session.view)) { _ in
            session.ink.refreshUndo()
        }
        .sheet(item: $selectedMark) { mark in
            NavigationStack {
                MarkDetailView(markID: mark.id).toolbar { Button("完成") { selectedMark = nil } }
            }.environmentObject(model)
        }.sheet(
            isPresented: Binding(get: { dictionaryWord != nil }, set: { if !$0 { dictionaryWord = nil } })
        ) {
            SystemDictionaryView(word: dictionaryWord ?? "")
        }.sheet(isPresented: $showRecognition) {
            NavigationStack {
                List {
                    Text("识别结果请自行核对。保存后按页面区域回跳，不标记为精确文字定位。").font(.caption)
                    if recognized.isEmpty { Text("未识别到可靠文字，可使用手动区域标记。") }
                    ForEach(recognized) { result in
                        Button {
                            var locator = ReadingLocator(kind: "pdf", page: result.rect.page)
                            locator.rectangles = [result.rect]
                            locator.fileFingerprint = session.verifiedFingerprint
                            locator.anchorText = result.text
                            model.saveMark(source: source, locator: locator, excerpt: result.text, kind: kind)
                            if model.message == nil { recognized.removeAll { $0.id == result.id } }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(result.text)
                                Text("保存区域摘录").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.navigationTitle("本页文字识别").toolbar { Button("完成") { showRecognition = false } }
            }
        }.task {
            session.view.capture = { capture(kind: $0, annotate: $1) }
            session.view.dictionary = { dictionaryWord = $0 }
            do {
                let fingerprint = try await Task.detached { try StudioModel.hash(url) }.value
                guard fingerprint == source.assetHash else {
                    session.anchorStatus = "文件与资料指纹不一致，已停止新增标记与精确回跳"
                    return
                }
                session.verifiedFingerprint = fingerprint
                session.ink.prepare(view: session.view, model: model, sourceID: source.id, fingerprint: fingerprint)
                session.view.captureReady = true
                session.anchorStatus = ""
                session.restore(initialLocation, fingerprint: fingerprint)
            } catch { session.anchorStatus = "无法核对文件指纹，未执行精确回跳" }
        }.onDisappear {
            session.ink.flush()
            if let locator = session.readingPosition() {
                model.saveLocation(sourceID: source.id, locator: locator)
            }
        }
    }

    private var readerContent: some View {
        VStack(spacing: 3) {
            if session.view.document == nil { Text("PDF 无法打开或已损坏，原文件保留。") }
            PDFHost(
                view: session.view,
                marks: model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil },
                regionMode: regionMode && session.verifiedFingerprint != nil && session.ink.tool == .select,
                fingerprint: session.verifiedFingerprint,
                onRegion: { rect in
                    var locator = ReadingLocator(kind: "pdf", page: rect.page)
                    locator.rectangles = [rect]
                    locator.fileFingerprint = session.verifiedFingerprint
                    model.saveMark(source: source, locator: locator, kind: kind)
                    regionMode = false
                })
            PronunciationStatus()
            if !session.anchorStatus.isEmpty {
                Text(session.anchorStatus).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            if regionMode {
                Text("长按并拖动，选取本页的图像区域。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var pdfOptions: some View {
        Toggle("区域标记", isOn: $regionMode)
            .disabled(session.verifiedFingerprint == nil)
            .onChange(of: regionMode) { _, active in
                if active { selectInkTool(.select) }
            }
        Button(recognizing ? "正在识别…" : "识别本页文字") {
            recognizePage()
        }.disabled(recognizing || session.verifiedFingerprint == nil)
        Button("选文批注") { capture(kind: kind, annotate: true) }
            .disabled(session.verifiedFingerprint == nil)
        Button("听发音", systemImage: "speaker.wave.2") {
            WordPronunciation.shared.speak(session.view.currentSelection?.string ?? "")
        }
        Divider()
        Picker("书页布局", selection: $layout) {
            ForEach(StudyPageLayout.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
        Toggle("连续滚动", isOn: $continuous)
        Toggle("双页保留独立封面", isOn: $book)
        Toggle("从右向左阅读", isOn: $rtl)
        Toggle("允许手指书写", isOn: $fingerInk)
    }

    private func selectInkTool(_ tool: PDFInkTool) {
        if tool != .select { regionMode = false }
        session.ink.choose(tool, kind: kind, fingerInk: fingerInk)
    }

    private func updateLayout() {
        let mode = StudyPageLayout(rawValue: layout) ?? .automatic
        session.ink.flush()
        session.setLayout(spread: mode.usesSpread(in: readerSize), continuous: continuous, book: book, rtl: rtl)
    }

    private func recognizePage() {
        guard let page = session.pageNumber else { return }
        recognizing = true
        Task {
            defer { recognizing = false }
            do {
                recognized = try await PDFRecognition.recognize(url: url, pageNumber: page)
                showRecognition = true
            } catch { model.message = "文字识别失败：\(error.localizedDescription)" }
        }
    }
    private func capture(kind: CardKind, annotate: Bool) {
        guard let fingerprint = session.verifiedFingerprint, let document = session.view.document,
            let page = session.pageNumber
        else { return }
        let selection = session.ink.tool == .select ? session.view.currentSelection : nil
        var locator =
            selection?.studioLocator(
                document: document, fallbackPage: page, fingerprint: fingerprint)
            ?? ReadingLocator(kind: "pdf", page: page)
        locator.fileFingerprint = fingerprint
        var mark = LibraryMark(
            sourceID: source.id, locator: locator, excerpt: selection?.string ?? "")
        mark.cardKind = kind
        model.change { $0.marks.append(mark) }
        if annotate && model.message == nil { selectedMark = mark }
    }

}
private struct SystemDictionaryView: UIViewControllerRepresentable {
    let word: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: word)
    }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
struct PDFHost: UIViewRepresentable {
    let view: PDFView
    let marks: [LibraryMark]
    var regionMode = false
    var fingerprint: String?
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
        let ids = marks.filter {
            fingerprint != nil
                && ($0.locator.fileFingerprint == nil || $0.locator.fileFingerprint == fingerprint)
        }
        guard ids != context.coordinator.ids else { return }
        context.coordinator.ids = ids
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations
            where annotation.contents?.hasPrefix("KnowledgeStudio:") == true {
                page.removeAnnotation(annotation)
            }
        }
        for mark in ids {
            for rect in mark.locator.rectangles {
                guard rect.isValid, rect.page <= document.pageCount,
                    let page = document.page(at: rect.page - 1)
                else { continue }
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
    @State private var showMarks = false
    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: session.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            HStack {
                Button("时间标记", systemImage: "bookmark") {
                    let seconds = session.player.currentTime().seconds
                    guard session.player.currentItem?.status == .readyToPlay, seconds.isFinite, seconds >= 0
                    else {
                        model.message = "未取得有效播放位置，本次未保存"
                        return
                    }
                    model.saveMark(source: source, locator: ReadingLocator(kind: "video", seconds: seconds))
                }.buttonStyle(.borderedProminent)
                Spacer()
                Button("标记历史", systemImage: "list.bullet") { showMarks = true }
            }.padding(.horizontal, 16).padding(.vertical, 8).background(StudyTheme.mat)

        }.sheet(isPresented: $showMarks) {
            NavigationStack {
                List(model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil }) { mark in
                    Button {
                        guard let seconds = mark.locator.seconds else { return }
                        session.player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
                        showMarks = false
                    } label: {
                        VStack(alignment: .leading) {
                            Text(locationLabel(mark.locator))
                            if !mark.note.isEmpty { Text(mark.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.studySurface().navigationTitle("时间标记")
                    .toolbar { Button("完成") { showMarks = false } }
            }
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
    var captureSelection: ((CardKind) -> Void)?
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
            let reader = try EPUBNavigatorViewController(
                publication: publication, initialLocation: initial,
                config: .init(editingActions: [
                    EditingAction(title: "单词高亮", action: #selector(StudyEPUBContainer.markWord)),
                    EditingAction(title: "语料高亮", action: #selector(StudyEPUBContainer.markExpression)),
                    EditingAction(title: "关键词高亮", action: #selector(StudyEPUBContainer.markKeyword)),
                    EditingAction(title: "关键句高亮", action: #selector(StudyEPUBContainer.markSentence)),
                    EditingAction(title: "听发音", action: #selector(StudyEPUBContainer.pronounce)),
                    .copy, .lookup,
                ]))
            captureSelection = { [weak self, weak reader] kind in
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
/// Readium's public convenience initializer cannot be inherited (its designated initializer is private).
/// A parent controller adds selection actions through UIKit's responder chain instead of subclassing Readium.
@MainActor
final class StudyEPUBContainer: UIViewController {
    let reader: EPUBNavigatorViewController
    var capture: ((CardKind) -> Void)?
    init(reader: EPUBNavigatorViewController) {
        self.reader = reader
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(reader)
        view.addSubview(reader.view)
        reader.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            reader.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            reader.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            reader.view.topAnchor.constraint(equalTo: view.topAnchor),
            reader.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reader.didMove(toParent: self)
    }
    @objc func pronounce() {
        WordPronunciation.shared.speak(reader.currentSelection?.locator.text.highlight ?? "")
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
    @AppStorage("readerColumns") private var legacyColumns = true
    @AppStorage("readerColumnMode") private var columnMode = "legacy"
    @AppStorage("readerMargins") private var margins = 1.0
    @State private var settings = false
    @State private var selectedMark: LibraryMark?
    @AppStorage("readerFont") private var font = "serif"
    @State private var readerSize: CGSize = .zero
    @State private var kind: CardKind = .expression
    var body: some View {
        GeometryReader { geometry in
            StudyReaderDock {
                epubContent
            } tools: {
                StudyMarkColors(selection: $kind)
                Button("Mark") { saveReadingMark() }
                    .buttonStyle(.bordered).disabled(session.navigator == nil)
                Button {
                    settings = true
                } label: {
                    Image(systemName: "textformat.size").frame(width: 44, height: 44)
                }.accessibilityLabel("阅读设置")
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                readerSize = size
                applyPreferences()
            }
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
        .onChange(of: columnMode) { _, _ in applyPreferences() }
        .onChange(of: margins) { _, _ in applyPreferences() }
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
                    Picker("分页", selection: $columnMode) {
                        Text("沿用原设置").tag("legacy")
                        Text("自动").tag("auto")
                        Text("单页").tag("one")
                        Text("双页").tag("two")
                    }
                    Section("页边距") { Slider(value: $margins, in: 0.5...2.0, step: 0.25) }
                    Text("双页按可用宽度与书籍排版自动调整；固定版式书籍可能不支持字号和行距调整。").font(.caption)
                }.studySurface().navigationTitle("阅读设置").toolbar { Button("完成") { settings = false } }
            }.presentationDetents([.medium])
        }
        .onDisappear {
            if let value = try? session.location(selection: false) {
                model.saveLocation(sourceID: source.id, locator: value.0)
            }
        }
    }
    private var epubContent: some View {
        VStack(spacing: 2) {
            if let warning = session.locationWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            if let error = session.error { Text(error) }
            else if let navigator = session.navigator {
                EPUBHost(
                    navigator: navigator,
                    marks: model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil },
                    capture: { session.captureSelection?($0) })
            } else { ProgressView("正在打开 EPUB…") }
            PronunciationStatus()
        }
    }

    private func saveReadingMark() {
        do {
            if let (locator, excerpt) = try session.location(selection: true), !excerpt.isEmpty {
                model.saveMark(source: source, locator: locator, excerpt: excerpt, kind: kind)
            } else if let (locator, _) = try session.location(selection: false) {
                model.saveMark(source: source, locator: locator)
            } else { throw LibraryError.invalid("尚未取得阅读位置") }
        } catch { model.message = error.localizedDescription }
    }

    private func applyPreferences() {
        let mode: StudyPageLayout = columnMode == "two" ? .spread :
            columnMode == "one" || (columnMode == "legacy" && !legacyColumns) ? .single : .automatic
        session.navigator?.submitPreferences(
            EPUBPreferences(
                columnCount: mode.usesSpread(in: readerSize) ? .two : .one,
                fontFamily: font == "serif" ? .serif : .sansSerif,
                fontSize: fontSize, lineHeight: lineHeight, pageMargins: margins,
                theme: theme == "dark" ? .dark : theme == "light" ? .light : .sepia))
    }

}
struct EPUBHost: UIViewControllerRepresentable {
    let navigator: EPUBNavigatorViewController
    let marks: [LibraryMark]
    var capture: (CardKind) -> Void
    func makeUIViewController(context: Context) -> StudyEPUBContainer {
        let container = StudyEPUBContainer(reader: navigator)
        container.capture = capture
        return container
    }
    func updateUIViewController(_ container: StudyEPUBContainer, context: Context) {
        container.capture = capture
        let controller = container.reader
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
