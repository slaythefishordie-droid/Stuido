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

/// Reserves space at the snapped edge, so controls never sit over a line of text or captions.
struct StudyReaderDock<Content: View, Tools: View>: View {
    @AppStorage("studyReaderDockBottom") private var bottom = false
    @AppStorage("studyReaderDockPosition") private var horizontalPosition = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hidden = false
    @GestureState private var offset: CGSize = .zero
    @State private var toolbarWidth: CGFloat = 0
    let content: Content
    let tools: Tools
    init(@ViewBuilder content: () -> Content, @ViewBuilder tools: () -> Tools) {
        self.content = content()
        self.tools = tools()
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let inset: CGFloat = hidden ? 26 : 58
            content
                .padding(bottom ? .bottom : .top, inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: bottom ? .bottom : .top) {
                    toolbar
                        .frame(maxWidth: max(1, width - 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { measure in
                                Color.clear.onChange(of: measure.size.width, initial: true) { _, value in
                                    toolbarWidth = value
                                }
                            }
                        }
                        .offset(x: xPosition(container: width) + offset.width, y: offset.height)
                        .gesture(drag(width: width, height: height))
                        .padding(.vertical, 2)
                }
                .clipped()
        }.background(StudyTheme.paper)
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            Button {
                animate { hidden.toggle() }
            } label: {
                Image(systemName: hidden ? (bottom ? "chevron.up" : "chevron.down") : "line.3.horizontal")
                    .font(.caption.weight(.semibold)).frame(width: 44, height: hidden ? 24 : 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(hidden ? "显示标记工具" : "隐藏标记工具")
            if !hidden { tools }
        }.padding(.horizontal, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(StudyTheme.rule, lineWidth: 1) }
            .accessibilityAction(named: "切换工具栏边缘") { animate { bottom.toggle() } }
    }

    private func xPosition(container: CGFloat) -> CGFloat {
        let travel = max(0, (container - toolbarWidth) / 2 - 6)
        return travel * CGFloat(horizontalPosition * 2 - 1)
    }

    private func drag(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 13)
            .updating($offset) { value, state, _ in
                let travel = max(0, (width - toolbarWidth) / 2 - 6)
                let x = min(travel, max(-travel, xPosition(container: width) + value.translation.width))
                let dy = max(-height + 54, min(height - 54, value.translation.height))
                state = CGSize(width: x - xPosition(container: width), height: dy)
            }
            .onEnded { value in
                animate {
                    let dy = value.translation.height
                    let outward = bottom ? dy : -dy
                    if hidden {
                        if outward < -14 { hidden = false }
                    } else if outward > 23 {
                        hidden = true
                    } else if abs(dy) > max(74, height * 0.34) {
                        bottom = dy > 0
                    }
                    let travel = max(1, (width - toolbarWidth) / 2 - 6)
                    let relativeX = (xPosition(container: width) + value.translation.width) / travel
                    horizontalPosition = min(1, max(0, Double((relativeX + 1) / 2)))
                }
            }
    }

    private func animate(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.19), action)
    }
}

struct StudyMarkColors: View {
    @Binding var selection: CardKind

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(CardKind.allCases, id: \.self) { kind in
                    Button { selection = kind } label: {
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
                Picker("标记颜色", selection: $selection) {
                    ForEach(CardKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Circle().fill(selection.color).frame(width: 17, height: 17)
                    .frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("标记颜色，\(selection.title)")
        }
    }
}

struct PDFStudyDockControls<Options: View>: View {
    @ObservedObject var ink: PDFStudyInk
    @Binding var selection: CardKind
    let enabled: Bool
    let save: () -> Void
    let choose: (PDFInkTool) -> Void
    let options: Options

    init(ink: PDFStudyInk, selection: Binding<CardKind>, enabled: Bool, save: @escaping () -> Void,
        choose: @escaping (PDFInkTool) -> Void, @ViewBuilder options: () -> Options)
    {
        self.ink = ink
        self._selection = selection
        self.enabled = enabled
        self.save = save
        self.choose = choose
        self.options = options()
    }

    var body: some View {
        StudyMarkColors(selection: $selection).disabled(!enabled)
        Button("Mark", action: save).buttonStyle(.bordered).disabled(!enabled)
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
