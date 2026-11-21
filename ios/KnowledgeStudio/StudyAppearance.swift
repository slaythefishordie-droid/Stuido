import KnowledgeCore
import SwiftUI

extension CardKind {
    var title: String {
        switch self {
        case .word: "单词卡"
        case .expression: "语料卡"
        case .keyword: "关键词卡"
        case .key_sentence: "关键句卡"
        }
    }
    var highlightColor: UIColor {
        switch self {
        case .word: .systemBlue
        case .expression: .systemYellow
        case .keyword: .systemPurple
        case .key_sentence: .systemGreen
        }
    }
    var color: Color { Color(uiColor: highlightColor) }
}
extension LibraryMark {
    var highlightKind: CardKind { cardKind ?? .expression }
}
/// Presentation-only labels; persisted schema keys stay unchanged.
func studioLabel(_ key: String) -> String {
    [
        "inbox": "待整理", "saved": "已收藏", "archived": "已归档", "not_enrolled": "未加入复习", "active": "复习中",
        "paused": "已暂停", "word": "单词卡", "expression": "语料卡", "keyword": "关键词卡", "key_sentence": "关键句卡",
        "pdf": "PDF 文档", "epub": "EPUB 书籍", "youtube": "YouTube 视频", "local_video": "本地视频", "article": "文章",
        "ai_explanation": "AI 解释", "ai_generated": "AI 生成", "self": "个人采集", "both": "个人与 AI",
        "podcast": "播客", "user_input": "个人填写", "original": "原文", "ai": "AI 生成", "text_en": "英文内容",
        "text_zh": "中文内容", "example_en": "英文例句", "example_zh": "例句译文", "definition_en": "英文释义",
        "definition_zh": "中文释义", "text": "内容", "term": "词条", "meaning": "含义", "translation": "译文",
        "context": "语境", "explanation": "解释", "pronunciation": "发音", "part_of_speech": "词性",
    ][key] ?? key
}

func studioFieldLabel(_ key: String) -> String {
    key == "word" ? "单词" : key == "term" ? "关键词" : studioLabel(key)
}

/// Shared native surfaces, with dynamic dark-mode contrast and system type scaling.
enum StudyTheme {
    static let paper = adaptive(0xF6F1E8, dark: 0x211C21)
    static let leaf = adaptive(0xFFFBF4, dark: 0x2C242C)
    static let mat = adaptive(0xEEE5D7, dark: 0x372C37)
    static let text = adaptive(0x2E262A, dark: 0xF6EBDF)
    static let ink = adaptive(0x7D463B, dark: 0xE2AD99)
    static let rule = adaptive(0xD9CABC, dark: 0x594955)
    static let plum = Color(uiColor: rgb(0x3C2637))
    static let railText = Color(uiColor: rgb(0xF8E9DA))
    static let copper = Color(uiColor: rgb(0xD3A06E))

    static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            rgb(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

}

enum StudySection: String, CaseIterable, Identifiable {
    case home, today, library, inbox, cards, imports, manager, settings, lounge
    var id: Self { self }
    var title: String {
        switch self {
        case .home: "书桌"
        case .today: "今日复习"
        case .library: "资料库"
        case .inbox: "收集箱"
        case .cards: "知识卡片"
        case .imports: "导入箱"
        case .manager: "数据管理"
        case .settings: "设置"
        case .lounge: "休息室"
        }
    }
    var symbol: String {
        switch self {
        case .home: "sun.max"
        case .today: "calendar"
        case .library: "books.vertical"
        case .inbox: "tray"
        case .cards: "rectangle.stack"
        case .imports: "tray.and.arrow.down"
        case .manager: "externaldrive"
        case .settings: "gearshape"
        case .lounge: "cup.and.saucer"
        }
    }
}

/// Object membership is an explicit selection, not a settings switch.
struct ObjectSelectionRow<Content: View>: View {
    @Binding var isSelected: Bool
    let content: Content
    init(isSelected: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isSelected = isSelected
        self.content = content()
    }
    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                content.foregroundStyle(.primary)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
extension ObjectSelectionRow where Content == Text {
    init(_ title: String, isSelected: Binding<Bool>) {
        self.init(isSelected: isSelected) { Text(title) }
    }
}


extension View {
    func studySurface() -> some View {
        scrollContentBackground(.hidden)
            .background(StudyTheme.paper)
            .foregroundStyle(StudyTheme.text)
    }

    func studyPanel() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyTheme.leaf, in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(StudyTheme.rule, lineWidth: 1) }
    }
}

struct StudyHeading: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(.title2, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(StudyTheme.rule).frame(height: 1)
        }
    }
}

struct StudyCardFace: View {
    let card: LibraryCard
    var featured = false
    private var title: String {
        if !card.title.isEmpty { return card.title }
        return card.content["example_en"] ?? "未命名卡片"
    }
    private var detail: String? {
        switch card.type {
        case .word: card.content["example_en"]
        case .expression: card.note
        case .keyword, .key_sentence: card.content["explanation"]
        }
    }
    private var textColor: Color { featured ? Color.white : StudyTheme.text }
    private var accent: Color {
        switch card.type {
        case .word: StudyTheme.adaptive(0x356780, dark: 0xA6CDE0)
        case .expression: StudyTheme.adaptive(0x775516, dark: 0xEAC581)
        case .keyword: StudyTheme.adaptive(0x6D4D86, dark: 0xDABDEA)
        case .key_sentence: StudyTheme.adaptive(0x3D6750, dark: 0xB4D5BB)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.type.title).font(.caption.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .foregroundStyle(featured ? Color.white : accent)
                .background((featured ? Color.white : accent).opacity(0.14))
            Text(title)
                .font(.system(featured ? .largeTitle : .title3, design: .serif, weight: .semibold))
                .italic(card.type == .expression)
                .foregroundStyle(textColor).lineLimit(featured ? 7 : 3)
            if let detail, !detail.isEmpty, detail != title {
                Text(detail).font(.subheadline).lineLimit(featured ? 4 : 3)
                    .foregroundStyle(textColor.opacity(0.84))
            }
            Spacer(minLength: 4)
            HStack {
                if card.review != .not_enrolled {
                    Text(studioLabel(card.review.rawValue)).font(.caption)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }.foregroundStyle(featured ? Color.white.opacity(0.88) : accent)
        }
        .padding(featured ? 22 : 14)
        .frame(maxWidth: .infinity, minHeight: featured ? 215 : 142, alignment: .topLeading)
        .background(featured ? Color(uiColor: StudyTheme.rgb(0x31493F)) : StudyTheme.leaf)
        .overlay(alignment: .top) { Rectangle().fill(accent).frame(height: 2) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct StudyReaderPresentation: Sendable {
    let setActive: @MainActor @Sendable (UUID, UUID, Bool, Bool) -> Void
    static let neutral = StudyReaderPresentation(setActive: { _, _, _, _ in })

}

private struct StudyReaderPresentationKey: EnvironmentKey {
    static let defaultValue = StudyReaderPresentation.neutral
}

extension EnvironmentValues {
    var studyReaderPresentation: StudyReaderPresentation {
        get { self[StudyReaderPresentationKey.self] }
        set { self[StudyReaderPresentationKey.self] = newValue }
    }
}


struct StudyNavigation: Sendable {
    let open: @MainActor @Sendable (StudySection) -> Void
}

private struct StudyNavigationKey: EnvironmentKey {
    static let defaultValue = StudyNavigation { _ in }
}

extension EnvironmentValues {
    var studyNavigation: StudyNavigation {
        get { self[StudyNavigationKey.self] }
        set { self[StudyNavigationKey.self] = newValue }
    }
}
