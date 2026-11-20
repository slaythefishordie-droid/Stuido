import KnowledgeCore
import SwiftUI

enum StudyPageLayout: String, CaseIterable {
    case automatic, single, spread
    var title: String {
        switch self {
        case .automatic: "自动"
        case .single: "单页"
        case .spread: "双页"
        }
    }

    func usesSpread(in size: CGSize) -> Bool {
        guard size.width >= 740 else { return false }
        switch self {
        case .automatic: return size.width > size.height
        case .single: return false
        case .spread: return true
        }
    }
}

/// Keep reader tools in the upper margin, outside the document's touch and drawing area.
struct StudyReaderDock<Content: View, Tools: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("studyReaderToolsFade") private var fade = true
    @State private var hidden = false
    @State private var idle = false
    @State private var activity = UUID()
    var selectionActive: Bool
    let content: Content
    let tools: Tools

    init(selectionActive: Bool = false, @ViewBuilder content: () -> Content,
        @ViewBuilder tools: () -> Tools)
    {
        self.selectionActive = selectionActive
        self.content = content()
        self.tools = tools()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                Button {
                    setHidden(!hidden)
                } label: {
                    Image(systemName: hidden ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold)).frame(width: 44, height: hidden ? 25 : 44)
                }.buttonStyle(.plain)
                    .accessibilityLabel(hidden ? "显示标记工具" : "隐藏标记工具")
                if !hidden { tools }
            }.padding(.horizontal, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(StudyTheme.rule, lineWidth: 1).allowsHitTesting(false) }
                .opacity(fade && idle && !hidden && !voiceOver ? 0.58 : 1)
                .padding(.vertical, 2)
                .simultaneousGesture(DragGesture(minimumDistance: 15).onEnded { value in
                    if value.translation.height < -20 { setHidden(true) }
                    if value.translation.height > 20 { setHidden(false) }
                })
                .simultaneousGesture(TapGesture().onEnded { wake() })
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(StudyTheme.paper)
            .onChange(of: selectionActive) { _, selected in
                if selected { setHidden(false) }
                else { wake() }
            }
            .task(id: activity) {
                guard !voiceOver, !selectionActive, !hidden else { return }
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { idle = true }
            }
    }

    private func wake() { idle = false; activity = UUID() }

    private func setHidden(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.19)) { hidden = value }
        wake()
    }
}

struct StudyMarkColors: View {
    @Binding var selection: CardKind
    var onPick: (CardKind) -> Void = { _ in }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    Button { pick(kind) } label: {
                        Circle().fill(kind.color).frame(width: 15, height: 15)
                            .overlay {
                                if kind == selection { Circle().strokeBorder(StudyTheme.text, lineWidth: 2) }
                            }
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(kind.title)
                        .accessibilityAddTraits(kind == selection ? .isSelected : [])
                }
            }
            Menu {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    Button(kind.title) { pick(kind) }
                }
            } label: {
                Circle().fill(selection.color).frame(width: 17, height: 17)
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("标记颜色，\(selection.title)")
        }
    }

    private func pick(_ kind: CardKind) {
        selection = kind
        onPick(kind)
    }
}

struct PDFStudyDockControls<Options: View>: View {
    @ObservedObject var ink: PDFStudyInk
    @Binding var selection: CardKind
    let enabled: Bool
    let save: (CardKind) -> Void
    @Binding var regionMode: Bool
    let choose: (PDFInkTool) -> Void
    let options: Options

    init(ink: PDFStudyInk, selection: Binding<CardKind>, enabled: Bool,
        regionMode: Binding<Bool>, save: @escaping (CardKind) -> Void, choose: @escaping (PDFInkTool) -> Void, @ViewBuilder options: () -> Options)
    {
        self.ink = ink
        self._selection = selection
        self.enabled = enabled
        self.save = save
        self._regionMode = regionMode
        self.choose = choose
        self.options = options()
    }

    var body: some View {
        StudyMarkColors(selection: $selection, onPick: save).disabled(!enabled)
        Button {
            regionMode.toggle()
        } label: {
            Image(systemName: regionMode ? "viewfinder.circle.fill" : "viewfinder")
                .frame(minWidth: 40, minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("区域标记")
            .accessibilityAddTraits(regionMode ? .isSelected : []).disabled(!enabled)
        historyButton("arrow.uturn.backward", label: "撤销笔迹", enabled: ink.canUndo, action: ink.undo)
        historyButton("arrow.uturn.forward", label: "重做笔迹", enabled: ink.canRedo, action: ink.redo)
        Menu {
            ForEach(PDFInkTool.allCases, id: \.self) { tool in
                Button {
                    choose(tool)
                } label: {
                    Label(tool.title, systemImage: ink.tool == tool ? "checkmark" : tool.icon)
                }.disabled(!enabled && tool != .select)
            }
            Divider()
            options
        } label: {
            Image(systemName: ink.tool.icon).frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("批注工具，\(ink.tool.title)")
            .popover(isPresented: $ink.showPalette) {
                StudyMarkColors(selection: $selection).padding()
                    .presentationCompactAdaptation(.popover)
            }
    }

    private func historyButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: icon).frame(minWidth: 40, minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(label).disabled(!enabled)
    }
}
