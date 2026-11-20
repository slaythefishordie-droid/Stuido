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
    static let paper = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.11, blue: 0.11, alpha: 1)
                : UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1)
        })
    static let ink = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.83, green: 0.73, blue: 0.59, alpha: 1)
                : UIColor(red: 0.43, green: 0.31, blue: 0.22, alpha: 1)
        })
}

enum StudySection: String, CaseIterable, Identifiable {
    case home, today, library, inbox, cards, imports, manager, settings
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
