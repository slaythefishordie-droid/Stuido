import KnowledgeCore
import PDFKit
import PencilKit
import SwiftUI

enum PDFInkTool: String, CaseIterable {
    case select, pen, marker, eraser

    var title: String {
        switch self {
        case .select: "阅读与选文"
        case .pen: "手写笔"
        case .marker: "荧光笔"
        case .eraser: "笔迹橡皮"
        }
    }

    var icon: String {
        switch self {
        case .select: "selection.pin.in.out"
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .eraser: "eraser"
        }
    }
}

@MainActor
final class StudyInkCanvas: PKCanvasView {
    private let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

@MainActor
final class StudyInkPage: UIView {
    let page: PDFPage
    let canvas = StudyInkCanvas()
    var transformToOverlay: CGAffineTransform?
    var saved: Data?
    var lastObservedDrawing: PKDrawing?
    var dirty = false
    var active = false
    var changingLayout = false
    var isValid = true
    var layoutChanged: (() -> Void)?

    init(page: PDFPage) {
        self.page = page
        super.init(frame: .zero)
        backgroundColor = .clear
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .pencilOnly
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        layoutChanged?()
    }
}

// PDFKit calls its legacy overlay protocol as part of the PDFView layout lifecycle.
@MainActor
final class PDFStudyInk: NSObject, ObservableObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate,
    UIPencilInteractionDelegate
{
    @Published private(set) var tool: PDFInkTool = .select
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var showPalette = false
    private var previous: PDFInkTool = .pen
    private var colorKind: CardKind = .expression
    private var fingerInk = false
    private var model: StudioModel?
    private var sourceID: UUID?
    private var fingerprint: String?
    private weak var view: PDFView?
    private var pages: [ObjectIdentifier: StudyInkPage] = [:]
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var saving: Set<ObjectIdentifier> = []

    func prepare(view: PDFView, model: StudioModel, sourceID: UUID, fingerprint: String) {
        guard self.view == nil else { return }
        self.view = view
        self.model = model
        self.sourceID = sourceID
        self.fingerprint = fingerprint
        let interaction = UIPencilInteraction()
        interaction.delegate = self
        view.addInteraction(interaction)
        // Installing the provider before attaching the document also refreshes already visible overlays.
        let document = view.document
        let page = view.currentPage
        view.document = nil
        view.pageOverlayViewProvider = self
        view.document = document
        if let page { view.go(to: page) }
    }

    func choose(_ tool: PDFInkTool, kind: CardKind, fingerInk: Bool) {
        guard tool == .select || fingerprint != nil else { return }
        if self.tool != tool { previous = self.tool }
        self.tool = tool
        colorKind = kind
        self.fingerInk = fingerInk
        view?.isInMarkupMode = tool != .select
        for page in pages.values { applyTool(to: page) }
        refreshUndo()
    }

    private func applyTool(to page: StudyInkPage) {
        let editable = tool != .select && page.transformToOverlay != nil && page.isValid
        page.isUserInteractionEnabled = editable
        page.canvas.drawingPolicy = fingerInk ? .anyInput : .pencilOnly
        switch tool {
        case .select: break
        case .pen: page.canvas.tool = PKInkingTool(.pen, color: colorKind.highlightColor, width: 2.5)
        case .marker: page.canvas.tool = PKInkingTool(.marker, color: colorKind.highlightColor, width: 11)
        case .eraser: page.canvas.tool = PKEraserTool(.vector)
        }
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let key = ObjectIdentifier(page)
        if let current = pages[key] { return current }
        let overlay = StudyInkPage(page: page)
        overlay.canvas.delegate = self
        overlay.layoutChanged = { [weak self, weak overlay] in
            if let overlay { self?.layout(overlay) }
        }
        if let identity = identity(of: page) {
            overlay.saved = attachedSource?.pdfPageInk?.first {
                $0.fingerprint == identity.fingerprint && $0.page == identity.page
            }?.drawing
        }
        pages[key] = overlay
        applyTool(to: overlay)
        return overlay
    }

    func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        guard let overlay = overlayView as? StudyInkPage else { return }
        overlay.setNeedsLayout()
    }

    func pdfView(_ view: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let overlay = overlayView as? StudyInkPage else { return }
        let key = ObjectIdentifier(page)
        pending.removeValue(forKey: key)?.cancel()
        persist(overlay)
        if !overlay.dirty { pages.removeValue(forKey: key) }
    }

    private var attachedSource: LibrarySource? {
        model?.state.sources.first { $0.id == sourceID }
    }

    private func identity(of page: PDFPage) -> (fingerprint: String, page: Int)? {
        guard let document = view?.document, let fingerprint else { return nil }
        let index = document.index(for: page)
        guard index >= 0, index < document.pageCount else { return nil }
        return (fingerprint, index + 1)
    }

    private func layout(_ overlay: StudyInkPage) {
        guard let view, !overlay.active, overlay.isValid, overlay.bounds.width > 0, overlay.bounds.height > 0,
            overlay.isDescendant(of: view) else { return }
        let box = overlay.page.bounds(for: .cropBox)
        let origin = CGPoint(x: box.minX, y: box.maxY)
        func convert(_ point: CGPoint) -> CGPoint {
            overlay.convert(view.convert(point, from: overlay.page), from: view)
        }
        let p0 = convert(origin)
        let px = convert(CGPoint(x: origin.x + 1, y: origin.y))
        let py = convert(CGPoint(x: origin.x, y: origin.y - 1))
        let transform = CGAffineTransform(a: px.x - p0.x, b: px.y - p0.y, c: py.x - p0.x,
            d: py.y - p0.y, tx: p0.x, ty: p0.y)
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard abs(determinant) > 1e-8,
            [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite),
            overlay.transformToOverlay != transform else { return }
        if overlay.dirty {
            persist(overlay)
            guard !overlay.dirty else { return }
        }
        do {
            let canonical = try overlay.saved.map { try PKDrawing(data: $0) } ?? PKDrawing()
            overlay.changingLayout = true
            overlay.transformToOverlay = transform
            let visible = canonical.transformed(using: transform)
            overlay.lastObservedDrawing = visible
            overlay.canvas.drawing = visible
            overlay.changingLayout = false
            applyTool(to: overlay)
        } catch {
            overlay.isValid = false
            applyTool(to: overlay)
            model?.message = "PDF 笔迹无法打开，原数据已保留。"
        }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        overlay(for: canvasView)?.active = true
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard let overlay = overlay(for: canvasView) else { return }
        overlay.active = false
        scheduleSave(overlay)
        overlay.setNeedsLayout()
        refreshUndo()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard let overlay = overlay(for: canvasView), !overlay.changingLayout, overlay.isValid,
            canvasView.drawing != overlay.lastObservedDrawing else { return }
        overlay.lastObservedDrawing = canvasView.drawing
        overlay.dirty = true
        if !overlay.active { scheduleSave(overlay) }
        refreshUndo()
    }

    private func overlay(for canvas: PKCanvasView) -> StudyInkPage? {
        canvas.superview as? StudyInkPage
    }

    private func scheduleSave(_ overlay: StudyInkPage) {
        let key = ObjectIdentifier(overlay.page)
        pending[key]?.cancel()
        pending[key] = Task { @MainActor [weak self, weak overlay] in
            try? await Task.sleep(for: .milliseconds(230))
            guard !Task.isCancelled, let self, let overlay else { return }
            self.pending.removeValue(forKey: key)
            self.persist(overlay)
        }
    }

    private func persist(_ overlay: StudyInkPage) {
        let key = ObjectIdentifier(overlay.page)
        guard !saving.contains(key) else { return }
        guard overlay.dirty, !overlay.active, overlay.isValid, let transform = overlay.transformToOverlay,
            let model, let sourceID, let identity = identity(of: overlay.page)
        else { return }
        let drawing = overlay.canvas.drawing
        let data = drawing.strokes.isEmpty ? nil : drawing.transformed(using: transform.inverted()).dataRepresentation()
        let expected = overlay.saved
        guard data != expected else { overlay.dirty = false; return }
        saving.insert(key)
        model.scheduleReaderSave { [self] in
            do {
                try await model.savePDFInk(sourceID: sourceID, fingerprint: identity.fingerprint,
                    page: identity.page, drawing: data, expected: expected)
                overlay.saved = data
                // New strokes/erasures may arrive during the write. Never mark
                // that newer drawing clean or overwrite it with the saved one.
                overlay.dirty = overlay.canvas.drawing != drawing
                saving.remove(key)
                if overlay.dirty { persist(overlay) }
                else if view == nil || !overlay.isDescendant(of: view!) { pages.removeValue(forKey: key) }
            } catch {
                saving.remove(key)
                overlay.dirty = true
                model.message = error.localizedDescription
            }
        }
    }

    func flush() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
        for overlay in pages.values { persist(overlay) }
    }

    private var undoManager: UndoManager? {
        guard let page = view?.currentPage else { return nil }
        return pages[ObjectIdentifier(page)]?.canvas.undoManager
    }

    func refreshUndo() {
        canUndo = undoManager?.canUndo == true
        canRedo = undoManager?.canRedo == true
    }

    func undo() {
        undoManager?.undo()
        refreshUndo()
    }

    func redo() {
        undoManager?.redo()
        refreshUndo()
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        if #available(iOS 17.5, *) { return }
        handleDoubleTap()
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        handleDoubleTap()
    }

    private func handleDoubleTap() {
        guard tool != .select else { return }
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser:
            choose(tool == .eraser ? (previous == .select ? .pen : previous) : .eraser,
                kind: colorKind, fingerInk: fingerInk)
        case .switchPrevious:
            choose(previous, kind: colorKind, fingerInk: fingerInk)
        case .showColorPalette:
            showPalette.toggle()
        default: break
        }
    }
}
