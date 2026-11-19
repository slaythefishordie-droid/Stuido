import SwiftUI
import KnowledgeCore

extension CardKind {
    var title: String {
        switch self { case .word: "单词卡"; case .expression: "语料卡"; case .keyword: "关键词卡"; case .key_sentence: "关键句卡" }
    }
    var highlightColor: UIColor {
        switch self { case .word: .systemBlue; case .expression: .systemYellow; case .keyword: .systemPurple; case .key_sentence: .systemGreen }
    }
    var color: Color { Color(uiColor: highlightColor) }
}
extension LibraryMark {
    var highlightKind: CardKind { cardKind ?? .expression }
}
/// Presentation-only labels; persisted schema keys stay unchanged.
func studioLabel(_ key: String) -> String {
    ["inbox":"待整理", "saved":"已收藏", "archived":"已归档", "not_enrolled":"未加入复习", "active":"复习中", "paused":"已暂停", "word":"单词卡", "expression":"语料卡", "keyword":"关键词卡", "key_sentence":"关键句卡", "pdf":"PDF 文档", "epub":"EPUB 书籍", "youtube":"YouTube 视频", "local_video":"本地视频", "text":"文本", "article":"文章", "podcast":"播客", "user_input":"个人填写", "original":"原文", "ai":"AI 生成", "text_en":"英文内容", "text_zh":"中文内容", "example_en":"英文例句", "example_zh":"例句译文", "definition_en":"英文释义", "definition_zh":"中文释义", "text":"内容", "term":"词条", "meaning":"含义", "translation":"译文", "context":"语境", "explanation":"解释", "pronunciation":"发音", "part_of_speech":"词性" ][key] ?? key
}
