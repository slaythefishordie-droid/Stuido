import KnowledgeCore
import SwiftUI

struct ExtensionSetupView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case reading = "阅读与 Pencil", video = "视频与 QuickMark", cards = "卡片与复习"
        case appearance = "界面与布局", data = "数据与导入", help = "帮助与高级设置", lounge = "休息室"
        var id: Self { self }
        var icon: String {
            switch self {
            case .reading: "book"
            case .video: "play.rectangle"
            case .cards: "rectangle.on.rectangle"
            case .appearance: "sidebar.leading"
            case .data: "externaldrive"
            case .help: "questionmark.circle"
            case .lounge: "cup.and.saucer"
            }
        }
    }
    @Environment(\.studyNavigation) private var navigation
    @State private var category: Category? = .reading
    @State private var reset = false
    @AppStorage("compactDisplay") private var compactDisplay = false
    @AppStorage("appAppearance") private var appearance = "system"
    @AppStorage("studyRailMode") private var rail = "auto"
    @AppStorage("studyHomeReviewFirst") private var homeReviewFirst = false
    @AppStorage("pronunciationAccent") private var accent = "en-US"
    @AppStorage("reviewRetention") private var retention = 0.9
    @AppStorage("quickMarkLead") private var lead = 2
    @AppStorage("studyPDFLayout") private var pdfLayout = StudyPageLayout.automatic.rawValue
    @AppStorage("studyPDFFingerInk") private var fingerInk = false
    @AppStorage("studyPDFContinuous") private var continuous = true
    @AppStorage("studyPDFBook") private var cover = true
    @AppStorage("studyPDFRTL") private var rtl = false
    @AppStorage("readerFontSize") private var size = 110.0
    @AppStorage("readerLineHeight") private var lines = 1.6
    @AppStorage("readerTheme") private var paper = "sepia"
    @AppStorage("readerColumnMode") private var columns = "legacy"
    @AppStorage("readerFont") private var font = "serif"
    @AppStorage("readerMargins") private var margins = 1.0
    @AppStorage("readerParagraphSpacing") private var paragraphSpacing = 0.65
    @AppStorage("studyReaderToolsFade") private var toolsFade = true

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= 650 {
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Category.allCases) { item in
                                    Button { category = item } label: {
                                        Label(item.rawValue, systemImage: item.icon)
                                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .background(category == item ? StudyTheme.mat : .clear,
                                                in: RoundedRectangle(cornerRadius: 5))
                                    }.buttonStyle(.plain)
                                        .accessibilityAddTraits(category == item ? .isSelected : [])
                                }
                            }.padding(12)
                        }.studySurface().frame(width: 225)
                        Divider()
                        preferences(category ?? .reading)
                    }
                } else {
                    List {
                        ForEach(Category.allCases) { item in
                            NavigationLink {
                                preferences(item).navigationTitle(item.rawValue)
                            } label: { Label(item.rawValue, systemImage: item.icon) }
                        }
                    }.studySurface()
                }
            }.navigationTitle("设置")
                .confirmationDialog("恢复全局偏好的默认值？", isPresented: $reset, titleVisibility: .visible) {
                    Button("恢复默认偏好", role: .destructive) { restoreDefaults() }
                }
        }
    }

    private func preferences(_ item: Category) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(item.rawValue, systemImage: item.icon)
                    .font(.system(.title2, design: .serif, weight: .semibold)).accessibilityAddTraits(.isHeader)
                preferenceContent(item)
            }.padding(24).frame(maxWidth: 740).frame(maxWidth: .infinity)
        }.studySurface().studyChange(item)
    }

    @ViewBuilder private func preferenceContent(_ item: Category) -> some View {
        switch item {
            case .reading: reading
            case .video:
                StudyPreferenceShelf("本地视频") {
                    Picker("标记提前量", selection: $lead) {
                        ForEach(0...3, id: \.self) { Text("\($0) 秒").tag($0) }
                    }
                }
                StudyPreferenceShelf("Safari") {
                    NavigationLink("QuickMark 与 Safari 扩展") { StudioGuide(initialTopic: .safari) }
                    SafariSharedSettings()
                }
            case .cards:
                StudyPreferenceShelf("FSRS · 新加入的卡片") {
                    Slider(value: $retention, in: 0.7...0.97, step: 0.01)
                    LabeledContent("目标保持率", value: "\(Int((retention * 100).rounded()))%")
                }
                Picker("发音口音偏好", selection: $accent) {
                    Text("美式英语").tag("en-US")
                    Text("英式英语").tag("en-GB")
                }
            case .appearance:
                StudyPreferenceShelf("书房") {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    Picker("导航栏", selection: $rail) {
                        Text("自动调整").tag("auto")
                        Text("固定展开").tag("expanded")
                        Text("紧凑图标").tag("compact")
                    }
                    Toggle("紧凑显示", isOn: $compactDisplay)
                    Toggle("书桌优先显示今日复习", isOn: $homeReviewFirst)
                }
            case .data:
                Button("库存、缓存与备份", systemImage: "externaldrive") { navigation.open(.manager) }
                Button("导入 AI 卡片包", systemImage: "tray.and.arrow.down") { navigation.open(.imports) }
                NavigationLink("从文件 App 导入") { StudioGuide(initialTopic: .files) }
            case .lounge:
                LoungePreferences()
            case .help:
                NavigationLink("使用指南") { StudioGuide() }
                Button("恢复默认偏好", role: .destructive) { reset = true }
        }
    }

    private var reading: some View {
        Group {
            StudyPreferenceShelf("PDF") {
                Picker("布局", selection: $pdfLayout) {
                    ForEach(StudyPageLayout.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("连续滚动", isOn: $continuous)
                Toggle("独立封面页", isOn: $cover)
                Toggle("从右向左", isOn: $rtl)
            }
            StudyPreferenceShelf("EPUB") {
                Picker("分页", selection: $columns) {
                    Text("沿用原设置").tag("legacy")
                    Text("自动").tag("auto")
                    Text("单页").tag("one")
                    Text("双页").tag("two")
                }
                Picker("纸色", selection: $paper) {
                    Text("纸白").tag("light")
                    Text("暖纸").tag("sepia")
                    Text("夜读").tag("dark")
                }
                Picker("字体", selection: $font) {
                    Text("宋体 · 衬线").tag("serif")
                    Text("黑体 · 无衬线").tag("sans")
                }
                Stepper("字号 \(Int(size))%", value: $size, in: EPUBSession.fontRange, step: 5)
                LabeledContent("行距") { Slider(value: $lines, in: EPUBSession.spacingRange, step: 0.05) }
                LabeledContent("页边距") { Slider(value: $margins, in: EPUBSession.marginRange, step: 0.1) }
                LabeledContent("段间距") { Slider(value: $paragraphSpacing, in: 0...1.5, step: 0.05) }
            }
            StudyPreferenceShelf("工具") {
                Toggle("工具栏空闲时淡化", isOn: $toolsFade)
                Toggle("允许手指书写 PDF", isOn: $fingerInk)
                NavigationLink("Pencil 操作指南") { StudioGuide(initialTopic: .pencil) }
            }
        }
    }

    private func restoreDefaults() {
        compactDisplay = false
        appearance = "system"
        rail = "auto"
        homeReviewFirst = false
        accent = "en-US"
        retention = 0.9
        lead = 2
        pdfLayout = StudyPageLayout.automatic.rawValue
        fingerInk = false
        continuous = true
        cover = true
        rtl = false
        size = 110
        lines = 1.6
        paper = "sepia"
        columns = "legacy"
        font = "serif"
        margins = 1
        paragraphSpacing = 0.65
        toolsFade = true
    }
}

struct StudyPreferenceShelf<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(.headline, design: .serif))
            Rectangle().fill(StudyTheme.rule).frame(height: 1)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).studyPanel()
    }
}

private struct SafariSharedSettings: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appRecord = "尚无记录"
    @State private var safariRecord = "尚无记录"
    @State private var status = ""

    var body: some View {
        DisclosureGroup("共享诊断") {
            LabeledContent("主 App", value: appRecord).font(.footnote.monospaced()).textSelection(.enabled)
            Button("写入主 App 验证记录") { refresh(write: true) }
            LabeledContent("Safari", value: safariRecord).font(.footnote.monospaced()).textSelection(.enabled)
            Button("重新读取共享记录") { refresh() }
            Text(status).accessibilityIdentifier("extensionSharingStatus")
        }.onAppear { refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh(write: Bool = false) {
        do {
            let store = try SharedProbeStore.configured()
            if write { _ = try store.write(from: .app) }
            appRecord = try store.read(from: .app)?.id.uuidString ?? "尚无记录"
            safariRecord = try store.read(from: .safari)?.id.uuidString ?? "尚无记录"
            status = "共享目录可访问。"
        } catch { status = error.localizedDescription }
    }
}

struct StudioGuide: View {
    enum Topic: String, CaseIterable, Identifiable {
        case pencil = "阅读与 Pencil", files = "从文件 App 导入", safari = "Safari QuickMark"
        case cards = "整理知识卡片", review = "连续复习", video = "视频精听"
        var id: Self { self }
        var steps: [(String, String)] {
            switch self {
            case .pencil:
                [("selection.pin.in.out", "选中文字后轻点颜色，将原文和出处存入收集箱。"),
                 ("square.dashed", "扫描件使用区域工具，长按并拖动框选。"),
                 ("pencil.tip", "在 PDF 选笔或橡皮，手指仍可翻页和缩放。双击遵循系统偏好。")]
            case .files:
                [("folder", "在文件 App 中长按 PDF、EPUB 或 MP4、M4V、MOV，找到系统的打开选项。"),
                 ("books.vertical", "选择 Knowledge Studio，确认导入，可同时选择项目。")]
            case .safari:
                [("safari", "在 iPad 的 Safari 扩展设置中启用 Knowledge Studio。"),
                 ("bookmark", "在支持的网页轻点标记。精听中可设置提前量和循环。"),
                 ("tray", "切回书房，收集箱会接收已保存的标记。")]
            case .cards:
                [("tray", "从收集箱选一条摘录，轻点「整理成卡片」。"),
                 ("rectangle.on.rectangle", "选择四种类型之一，核对正文和关联项目，然后保存。")]
            case .review:
                [("calendar", "在卡片编辑页打开「加入复习」。在书桌打开今日复习。"),
                 ("checkmark.circle", "选择卡片类型，逐张评分。保存后自动进入下一张。")]
            case .video:
                [("waveform", "在精听面板微调播放位置，或更改标记提前量。"),
                 ("repeat", "在视频中先设 A 再设 B，反复播放这一段。")]
            }
        }
    }
    var initialTopic: Topic?
    @State private var query = ""
    var body: some View {
        List {
            ForEach(Topic.allCases.filter { topic in
                (initialTopic == nil || initialTopic == topic || !query.isEmpty) &&
                    (query.isEmpty || topic.rawValue.localizedCaseInsensitiveContains(query) ||
                        topic.steps.contains { $0.1.localizedCaseInsensitiveContains(query) })
            }) { topic in
                Section(topic.rawValue) {
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { _, step in
                        Label(step.1, systemImage: step.0).padding(.vertical, 4)
                    }
                }
            }
        }.studySurface().navigationTitle("使用指南").searchable(text: $query)
    }
}
