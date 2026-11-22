import KnowledgeCore
import PencilKit
import SwiftUI

/// The note has its own fixed coordinate space. The Mark retains the existing EPUB Locator.
struct EPUBInkNote: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var erasing = false
    @State private var finger = false
    @State private var invalid = false
    @State private var saving = false
    let mark: LibraryMark

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(mark.excerpt).font(.system(.title3, design: .serif)).studyPanel()
                    if invalid {
                        Text("笔迹无法读取，原记录保留。").foregroundStyle(.secondary)
                    } else {
                        EPUBPencilCanvas(drawing: $drawing, color: mark.highlightKind.highlightColor,
                            erasing: erasing, finger: finger)
                            .aspectRatio(600.0 / 340.0, contentMode: .fit)
                            .border(StudyTheme.rule)
                            .accessibilityLabel("页边手写区")
                        Toggle("笔迹橡皮", isOn: $erasing).toggleStyle(.button)
                        Toggle("允许手指书写", isOn: $finger)
                    }
                }.padding(20)
            }.studySurface().navigationTitle("页边笔记")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }.disabled(invalid || saving)
                    }
                }
        }.allowsHitTesting(!saving).onAppear {
            guard let data = mark.epubNoteInk else { return }
            do { drawing = try PKDrawing(data: data) }
            catch { invalid = true }
        }.interactiveDismissDisabled()
    }

    private func save() {
        let data = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            do { try await model.saveEPUBInk(mark: mark, drawing: data); dismiss() }
            catch { model.message = error.localizedDescription }
        }
    }
}

private struct EPUBPencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let color: UIColor
    let erasing: Bool
    let finger: Bool

    func makeCoordinator() -> Coordinator { Coordinator(value: $drawing) }

    func makeUIView(context: Context) -> InkView {
        let view = InkView()
        view.canvas.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: InkView, context: Context) {
        let coordinator = context.coordinator
        coordinator.value = $drawing
        view.canonical = drawing
        view.canvas.drawingPolicy = finger ? .anyInput : .pencilOnly
        if erasing { view.canvas.tool = PKEraserTool(.vector) }
        else { view.canvas.tool = PKInkingTool(.pen, color: color, width: 2.5) }
        view.loadIfNeeded()
    }

    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        var value: Binding<PKDrawing>
        init(value: Binding<PKDrawing>) { self.value = value }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let view = canvasView.superview as? InkView, !view.loading, view.factor > 0 else { return }
            let drawing = canvasView.drawing.transformed(using:
                CGAffineTransform(scaleX: 1 / view.factor, y: 1 / view.factor))
            view.canonical = drawing
            view.loaded = drawing
            value.wrappedValue = drawing
        }
    }

    @MainActor final class InkView: UIView {
        let canvas = PKCanvasView()
        var canonical = PKDrawing()
        var loaded: PKDrawing?
        var factor: CGFloat = 0
        var loading = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            canvas.isScrollEnabled = false
            canvas.backgroundColor = .secondarySystemBackground
            addSubview(canvas)
        }

        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { return nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            canvas.frame = bounds
            loadIfNeeded()
        }

        func loadIfNeeded() {
            let scale = min(bounds.width / 600, bounds.height / 340)
            guard scale > 0, scale != factor || canonical != loaded else { return }
            factor = scale
            loaded = canonical
            loading = true
            canvas.drawing = canonical.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            loading = false
        }
    }
}
