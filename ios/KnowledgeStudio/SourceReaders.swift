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
    private var immersive: Bool { [.pdf, .epub, .local_video].contains(source.kind) }
    var body: some View {
        let live = model.state.sources.first { $0.id == self.source.id }
        let source = live ?? self.source
        return Group {
            if live == nil || source.deletedAt != nil {
                ContentUnavailableView("资料不可用", systemImage: "doc.questionmark")
            } else if let url = model.assetURL(source), FileManager.default.fileExists(atPath: url.path) {
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
                if immersive { readerPresentation.setActive(readerID, true) }
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
            focus(bounds, on: page)
            let anchors = locator.pdfTextAnchors ?? []
            let verified =
                !anchors.isEmpty
                && anchors.allSatisfy { anchor in
                    guard anchor.page > 0, anchor.page <= document.pageCount,
                        let text = document.page(at: anchor.page - 1)?.string
                    else { return false }
                    return anchor.matches(text)
                }
            anchorStatus = anchors.isEmpty || verified ? "" : "已定位原区域，文字内容无法核对。"
        }
    }
    private func focus(_ bounds: CGRect, on page: PDFPage) {
        view.go(to: bounds, on: page)
        view.layoutIfNeeded()
        if let parent = view.documentView?.superview,
            let scroll = sequence(first: parent, next: { $0.superview }).compactMap({ $0 as? UIScrollView }).first {
            let area = view.convert(view.convert(bounds, from: page), to: scroll)
            let inset = scroll.adjustedContentInset
            let x = area.midX - (scroll.bounds.width + inset.left - inset.right) / 2
            let y = area.midY - (scroll.bounds.height + inset.top - inset.bottom) / 2
            let maxX = max(-inset.left, scroll.contentSize.width - scroll.bounds.width + inset.right)
            let maxY = max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
            scroll.setContentOffset(CGPoint(x: min(maxX, max(-inset.left, x)),
                y: min(maxY, max(-inset.top, y))), animated: false)
        }
        let cue = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
        cue.color = UIColor.systemOrange
        let border = PDFBorder()
        border.lineWidth = 2
        cue.border = border
        page.addAnnotation(cue)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            page.removeAnnotation(cue)
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
        if let destination, let page = destination.page {
            view.go(to: PDFDestination(page: page, at: destination.point))
        }
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
    @State private var selectionActive = false
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
            StudyReaderDock(selectionActive: selectionActive || regionMode) {
                readerContent
            } tools: {
                PDFStudyDockControls(ink: session.ink, selection: $kind, enabled: session.verifiedFingerprint != nil,
                    regionMode: $regionMode, save: { color in
                        guard session.ink.tool == .select,
                            session.view.currentSelection?.string?.isEmpty == false else { return }
                        capture(kind: color, annotate: false)
                    }, choose: selectInkTool) { pdfOptions }
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
        }.onChange(of: regionMode) { _, active in
            if active { selectInkTool(.select) }
        }.onReceive(NotificationCenter.default.publisher(for: .PDFViewSelectionChanged, object: session.view)) { _ in
            selectionActive = session.view.currentSelection?.string?.isEmpty == false
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
                marksInteractive: session.ink.tool == .select && !regionMode,
                onMark: { id in selectedMark = model.state.marks.first { $0.id == id && $0.deletedAt == nil } },
                onRegion: saveRegion)
            PronunciationStatus()
            if !session.anchorStatus.isEmpty {
                Text(session.anchorStatus).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            if recognizing { ProgressView("正在识别选区…").font(.caption) }
        }
    }

    @ViewBuilder private var pdfOptions: some View {
        Button("收藏当前位置") { capture(kind: kind, annotate: false) }
            .disabled(session.verifiedFingerprint == nil)
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

    private func saveRegion(_ rect: HighlightRect) {
        guard !recognizing, let fingerprint = session.verifiedFingerprint else { return }
        let color = kind
        var locator = ReadingLocator(kind: "pdf", page: rect.page)
        locator.rectangles = [rect]
        locator.fileFingerprint = fingerprint
        regionMode = false
        let page = session.view.document?.page(at: rect.page - 1)
        if page?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            model.saveMark(source: source, locator: locator, kind: color)
            return
        }
        recognizing = true
        Task {
            defer { recognizing = false }
            let target = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            let results = (try? await PDFRecognition.recognize(url: url, pageNumber: rect.page)) ?? []
            let excerpt = results.filter {
                let line = CGRect(x: $0.rect.x, y: $0.rect.y, width: $0.rect.width, height: $0.rect.height)
                return target.contains(CGPoint(x: line.midX, y: line.midY))
            }.sorted { $0.rect.y > $1.rect.y }.map(\.text).joined(separator: "\n")
            locator.anchorText = excerpt.isEmpty ? nil : excerpt
            model.saveMark(source: source, locator: locator, excerpt: excerpt, kind: color)
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
        if model.message == nil {
            session.view.clearSelection()
            if annotate { selectedMark = mark }
        }
    }

}
struct SystemDictionaryView: UIViewControllerRepresentable {
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
    var marksInteractive = true
    var onMark: ((UUID) -> Void)?
    var onRegion: ((HighlightRect) -> Void)?
    func makeUIView(context: Context) -> PDFView {
        let gesture = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.capture(_:)))
        gesture.minimumPressDuration = 0.3
        gesture.isEnabled = regionMode
        view.addGestureRecognizer(gesture)
        context.coordinator.gesture = gesture
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openMark(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.tap = tap
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onRegion = onRegion
        context.coordinator.onMark = onMark
        context.coordinator.tap?.isEnabled = marksInteractive
        context.coordinator.gesture?.isEnabled = regionMode
        guard let document = view.document else { return }
        let coordinator = context.coordinator
        if coordinator.document !== document {
            coordinator.removeHighlights()
            coordinator.document = document
        }

        var latest: [Int: [Highlight]] = [:]
        if let fingerprint {
            for mark in marks where mark.locator.fileFingerprint == nil || mark.locator.fileFingerprint == fingerprint {
                for (index, rect) in mark.locator.rectangles.enumerated()
                    where rect.isValid && rect.page <= document.pageCount
                {
                    let quads = mark.locator.pdfTextQuads
                    let quad = quads.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                    latest[rect.page, default: []].append(
                        Highlight(id: mark.id, kind: mark.highlightKind, rect: rect, quad: quad))
                }
            }
        }
        guard latest != coordinator.highlights else { return }
        let pages = Set(latest.keys).union(coordinator.highlights.keys)
        for number in pages where latest[number] != coordinator.highlights[number] {
            coordinator.removeHighlights(on: number)
            guard let highlights = latest[number], let page = document.page(at: number - 1) else { continue }
            let annotations = highlights.map(makeAnnotation)
            for annotation in annotations { page.addAnnotation(annotation) }
            coordinator.annotations[number] = (page, annotations)
        }
        coordinator.highlights = latest
    }

    struct Highlight: Equatable {
        let id: UUID
        let kind: CardKind
        let rect: HighlightRect
        let quad: PDFTextQuad?
    }

    private func makeAnnotation(_ mark: Highlight) -> PDFAnnotation {
        let rect = mark.rect
        let annotation = PDFAnnotation(
            bounds: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
            forType: .highlight, withProperties: nil)
        annotation.color = mark.kind.highlightColor.withAlphaComponent(0.4)
        if let quad = mark.quad, quad.page == rect.page, quad.points.count == 4,
            quad.points.allSatisfy({
                $0.x.isFinite && $0.y.isFinite && (rect.x...(rect.x + rect.width)).contains($0.x)
                    && (rect.y...(rect.y + rect.height)).contains($0.y)
            })
        {
            annotation.quadrilateralPoints = quad.points.map {
                NSValue(cgPoint: CGPoint(x: $0.x - rect.x, y: $0.y - rect.y))
            }
        }
        annotation.contents = "KnowledgeStudio:" + mark.id.uuidString
        return annotation
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        if let gesture = coordinator.gesture { view.removeGestureRecognizer(gesture) }
        if let tap = coordinator.tap { view.removeGestureRecognizer(tap) }
        coordinator.removeHighlights()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var document: PDFKit.PDFDocument?
        var highlights: [Int: [Highlight]] = [:]
        var annotations: [Int: (PDFPage, [PDFAnnotation])] = [:]

        func removeHighlights(on pageNumber: Int) {
            guard let (page, previous) = annotations.removeValue(forKey: pageNumber) else { return }
            for annotation in previous { page.removeAnnotation(annotation) }
        }

        func removeHighlights() {
            for number in Array(annotations.keys) { removeHighlights(on: number) }
            highlights.removeAll()
        }
        var gesture: UILongPressGestureRecognizer?
        var tap: UITapGestureRecognizer?
        var onMark: ((UUID) -> Void)?
        var onRegion: ((HighlightRect) -> Void)?
        private var start: CGPoint?
        private var page: PDFPage?
        private let outline = CAShapeLayer()
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            gestureRecognizer === tap || otherGestureRecognizer === tap
        }

        @objc func openMark(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PDFView else { return }
            let location = gesture.location(in: view)
            if let selection = view.currentSelection, selection.string?.isEmpty == false {
                let inside = selection.pages.contains { page in
                    view.convert(selection.bounds(for: page), from: page).insetBy(dx: -6, dy: -6)
                        .contains(location)
                }
                if !inside { view.clearSelection() }
                return
            }
            let prefix = "KnowledgeStudio:"
            guard let page = view.page(for: location, nearest: false),
                let value = page.annotation(at: view.convert(location, to: page))?.contents,
                value.hasPrefix(prefix), let id = UUID(uuidString: String(value.dropFirst(prefix.count)))
            else { return }
            onMark?(id)
        }

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
    @Published private(set) var loopA: Double?
    @Published private(set) var loopB: Double?
    private var loopObserver: Any?

    var time: Double? {
        let value = player.currentTime().seconds
        guard player.currentItem?.status == .readyToPlay, value.isFinite, value >= 0 else { return nil }
        return value
    }

    func seek(_ seconds: Double) {
        let duration = player.currentItem?.duration.seconds ?? .infinity
        let capped = duration.isFinite ? min(duration, seconds) : seconds
        player.seek(to: CMTime(seconds: max(0, capped), preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func step(_ interval: Int) {
        guard let time else { return }
        let target = time + Double(interval)
        if let start = loopA, target < start || target > (loopB ?? .infinity) { clearLoop() }
        seek(target)
    }

    func checkLoopAfterSeek() {
        if let start = loopA, let end = loopB, let time,
            time < start - 0.1 || time > end + 0.1 { clearLoop() }
    }

    func finishItem() {
        guard let start = loopA, loopB != nil else { return }
        seek(start)
        player.play()
    }

    func startLoop(at time: Double) {
        clearLoop()
        loopA = time
    }

    func finishLoop(at time: Double) -> Bool {
        guard let start = loopA, time > start + 0.1 else { return false }
        if let loopObserver { player.removeTimeObserver(loopObserver) }
        loopB = time
        loopObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: time, preferredTimescale: 600))],
            queue: .main
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.loopA == start, self.loopB == time else { return }
                self.seek(start)
            }
        }
        seek(start)
        return true
    }

    func clearLoop() {
        if let loopObserver { player.removeTimeObserver(loopObserver) }
        loopObserver = nil
        loopA = nil
        loopB = nil
    }

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
    @State private var showListening = false
    @State private var lastMark: Double?
    @AppStorage("quickMarkLead") private var lead = 2
    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: session.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            HStack {
                Button("标记", systemImage: "bookmark") { markTime() }.buttonStyle(.borderedProminent)
                if let lastMark {
                    Text("已标记 " + locationLabel(ReadingLocator(kind: "video", seconds: lastMark)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer()
                Button("精听", systemImage: session.loopB == nil ? "waveform" : "repeat") {
                    showListening = true
                }.popover(isPresented: $showListening) { listeningTools }
                Button("标记历史", systemImage: "list.bullet") { showMarks = true }.labelStyle(.iconOnly)
            }.padding(.horizontal, 14).padding(.vertical, 7).background(StudyTheme.mat)
        }.sheet(isPresented: $showMarks) {
            NavigationStack {
                List(model.state.marks.filter { $0.sourceID == source.id && $0.deletedAt == nil }) { mark in
                    Button {
                        guard let seconds = mark.locator.seconds else { return }
                        session.clearLoop()
                        session.seek(seconds)
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
        }.onReceive(NotificationCenter.default.publisher(
            for: .AVPlayerItemTimeJumped, object: session.player.currentItem
        )) { _ in
            session.checkLoopAfterSeek()
        }.onReceive(NotificationCenter.default.publisher(
            for: .AVPlayerItemDidPlayToEndTime, object: session.player.currentItem
        )) { _ in
            session.finishItem()
        }.onDisappear {
            let seconds = session.player.currentTime().seconds
            session.player.pause()
            session.clearLoop()
            if seconds.isFinite && seconds >= 0 {
                model.saveLocation(
                    sourceID: source.id, locator: ReadingLocator(kind: "video", seconds: seconds))
            }
        }
    }

    private func markTime() {
        guard let time = session.time else {
            model.message = "视频尚未就绪，本次标记未保存。"
            return
        }
        let seconds = max(0, floor(time - Double(min(3, max(0, lead)))))
        model.saveMark(source: source, locator: ReadingLocator(kind: "video", seconds: seconds))
        if model.message == nil { lastMark = seconds }
    }

    private var listeningTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudyHeading(title: "精听")
            HStack {
                ForEach([-3, -1, 1, 3], id: \.self) { offset in
                    Button(offset > 0 ? "+\(offset) 秒" : "\(offset) 秒") {
                        session.step(offset)
                    }.buttonStyle(.bordered)
                }
            }
            Picker("标记提前量", selection: $lead) {
                ForEach(0...3, id: \.self) { Text("\($0) 秒").tag($0) }
            }
            if let start = session.loopA {
                let a = start.formatted(.number.precision(.fractionLength(1)))
                let b = session.loopB.map { " → B " + $0.formatted(.number.precision(.fractionLength(1))) + " 秒" } ?? ""
                Text("A \(a) 秒" + b).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("设 A") { if let time = session.time { session.startLoop(at: time) } }
                Button("设 B") {
                    guard let time = session.time else { return }
                    if !session.finishLoop(at: time) { model.message = "终点 B 必须在 A 之后。" }
                }.disabled(session.loopA == nil)
                Button("清除") { session.clearLoop() }.disabled(session.loopA == nil)
            }.buttonStyle(.bordered)
        }.padding(18).presentationCompactAdaptation(.popover)
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
    var saveSelection: ((ReadingLocator, String, CardKind) -> Bool)?
    var captureSelection: ((CardKind) -> Void)?
    @Published var selectionActive = false
    func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: ReadiumNavigator.Selection) -> Bool {
        if selection.locator.text.highlight?.isEmpty == false {
            Task { @MainActor in selectionActive = true }
        }
        return true
    }
    var selectMark: ((UUID) -> Void)?
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        if let value = try? Self.readingLocator(locator) { savePosition?(value) }
    }
    /// The Settings slider stores whole percentages. Readium expects a scale factor.
    static func fontScale(for percent: Double) -> Double { min(180, max(80, percent)) / 100 }

    static func readingLocator(_ locator: Locator) throws -> ReadingLocator {
        ReadingLocator(
            kind: "epub", href: locator.href.string, progression: locator.locations.progression,
            nativeJSON: try locator.jsonString())
    }
    @Published var navigator: EPUBNavigatorViewController?
    private var preferences: EPUBPreferences?
    func submit(_ value: EPUBPreferences) {
        guard let navigator, value != preferences else { return }
        preferences = value
        navigator.submitPreferences(value)
    }
    @Published var error: String?
    @Published var locationWarning: String?
    func open(url: URL, location: ReadingLocator?, preferences: EPUBPreferences) async {
        guard navigator == nil else { return }
        error = nil
        locationWarning = nil
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
            try Task.checkCancellation()
            let reader = try EPUBNavigatorViewController(
                publication: publication, initialLocation: initial,
                config: .init(preferences: preferences, editingActions: [
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
                do {
                    if self?.saveSelection?(try Self.readingLocator(locator), text, kind) == true {
                        reader?.clearSelection()
                        self?.selectionActive = false
                    }
                } catch { self?.locationWarning = "选文定位未保存：\(error.localizedDescription)" }
            }
            reader.observeDecorationInteractions(inGroup: "knowledge-marks") { [weak self] event in
                if let id = UUID(uuidString: event.decoration.id) { self?.selectMark?(id) }
            }
            reader.delegate = self
            self.preferences = preferences
            navigator = reader
        } catch is CancellationError {
            return
        } catch { self.error = "无法打开 EPUB：\(error.localizedDescription)" }
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
            StudyReaderDock(selectionActive: session.selectionActive) {
                epubContent
            } tools: {
                StudyMarkColors(selection: $kind, onPick: { session.captureSelection?($0) })
                    .disabled(session.navigator == nil)
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
            session.saveSelection = { locator, text, kind in
                model.saveMark(source: source, locator: locator, excerpt: text, kind: kind)
                return model.message == nil
            }
            await session.open(url: url, location: location, preferences: readerPreferences)
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
                    Button("收藏当前阅读位置") { saveReadingMark() }
                        .disabled(session.navigator == nil)
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
            if let error = session.error {
                ContentUnavailableView {
                    Label("无法打开 EPUB", systemImage: "book.closed")
                } description: {
                    Text(error)
                } actions: {
                    if session.navigator == nil {
                        Button("重试") {
                            Task { await session.open(url: url, location: location, preferences: readerPreferences) }
                        }.buttonStyle(.bordered)
                    }
                }
            } else if let navigator = session.navigator {
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

    private var readerPreferences: EPUBPreferences {
        let mode: StudyPageLayout = columnMode == "two" ? .spread :
            columnMode == "one" || (columnMode == "legacy" && !legacyColumns) ? .single : .automatic
        return EPUBPreferences(
            columnCount: mode.usesSpread(in: readerSize) ? .two : .one,
            fontFamily: font == "serif" ? .serif : .sansSerif,
            fontSize: EPUBSession.fontScale(for: fontSize),
            lineHeight: lineHeight, pageMargins: margins,
            theme: theme == "dark" ? .dark : theme == "light" ? .light : .sepia)
    }

    private func applyPreferences() { session.submit(readerPreferences) }

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
    struct Highlight: Equatable {
        let id: UUID
        let kind: CardKind
        let json: String
    }

    final class Coordinator {
        var highlights: [Highlight]?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIViewController(_ container: StudyEPUBContainer, context: Context) {
        container.capture = capture
        let highlights = marks.compactMap { mark -> Highlight? in
            guard !mark.excerpt.isEmpty, let json = mark.locator.nativeJSON else { return nil }
            return Highlight(id: mark.id, kind: mark.highlightKind, json: json)
        }
        guard highlights != context.coordinator.highlights else { return }
        context.coordinator.highlights = highlights
        let decorations: [Decoration] = highlights.compactMap { mark in
            guard let object = try? JSONSerialization.jsonObject(with: Data(mark.json.utf8)) as? [String: Any],
                let locator = try? Locator(json: ReadiumShared.JSONValue(object), warnings: nil)
            else { return nil }
            return Decoration(
                id: mark.id.uuidString, locator: locator,
                style: .highlight(tint: mark.kind.highlightColor))
        }
        container.reader.apply(decorations: decorations, in: "knowledge-marks")
    }
}
