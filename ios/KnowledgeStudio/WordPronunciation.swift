import AVFoundation
import SwiftUI

/// One playback owner for reader and vocabulary cards. Never labels synthesized audio as recorded speech.
@MainActor
final class WordPronunciation: ObservableObject {
    static let shared = WordPronunciation()
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var status = "设备合成语音"

    func speak(_ text: String) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 200 else {
            status = "请先选择单词或简短词组"
            return
        }
        let preference = UserDefaults.standard.string(forKey: "pronunciationAccent") ?? "en-US"
        let preferred = preference == "en-GB" ? "en-GB" : "en-US"
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard let voice = voices.first(where: { $0.language == preferred })
            ?? voices.first(where: { $0.language.hasPrefix("en-") }) else {
            status = "设备暂无可用英语语音，请在系统设置中添加英语语音"
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        status = "Apple 合成语音 · \(voice.language == "en-US" ? "美式英语" : voice.language == "en-GB" ? "英式英语" : voice.language)"
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

struct PronunciationButton: View {
    let word: String
    @ObservedObject private var service = WordPronunciation.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { service.speak(word) } label: { Label("听发音", systemImage: "speaker.wave.2") }
                Button("停止") { service.stop() }
            }
            Text(service.status).font(.caption).foregroundStyle(.secondary)
        }
    }
}
