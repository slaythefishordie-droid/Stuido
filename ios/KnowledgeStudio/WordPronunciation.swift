import AVFoundation
import KnowledgeCore
import SwiftUI

/// One playback owner for reader and vocabulary cards. Never labels synthesized audio as recorded speech.
@MainActor
final class WordPronunciation: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate
{
    static let shared = WordPronunciation()
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    @Published private(set) var status = "真人录音优先，缺少时使用设备合成语音"
    @Published private(set) var recording: PronunciationRecording?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.releaseAudioIfIdle() }
    }
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.releaseAudioIfIdle() }
    }
    private func releaseAudioIfIdle() {
        guard player?.isPlaying != true, !synthesizer.isSpeaking else { return }
        if !LoungeHub.shared.playing {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func speak(_ text: String) {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 200 else {
            status = "请先选择单词或简短词组"
            return
        }
        stop()
        let preference = UserDefaults.standard.string(forKey: "pronunciationAccent") ?? "en-US"
        let preferred = preference == "en-GB" ? "en-GB" : "en-US"
        status = "正在查找可用录音…"
        task = Task {
            let cached = await CommonsPronunciation.shared.recording(word: word, preferredAccent: preferred)
            guard !Task.isCancelled else { return }
            if let cached, let audio = try? AVAudioPlayer(data: cached.audio) {
                prepareAudioSession()
                player = audio
                audio.delegate = self
                if audio.play() {
                    recording = cached.recording
                    status = "真人录音 · \(cached.recording.accent == "en-US" ? "美式英语" : "英式英语")"
                    return
                }
            }
            speakUsingDevice(word, preferred: preferred)
        }
    }
    private func speakUsingDevice(_ word: String, preferred: String) {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard
            let voice = voices.first(where: { $0.language == preferred })
                ?? voices.first(where: { $0.language.hasPrefix("en-") })
        else {
            status = "设备暂无可用英语语音，请在系统设置中添加英语语音"
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        prepareAudioSession()
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        status =
            "Apple 合成语音 · \(voice.language == "en-US" ? "美式英语" : voice.language == "en-GB" ? "英式英语" : voice.language)"
        synthesizer.speak(utterance)
    }
    private func prepareAudioSession() {
        guard !LoungeHub.shared.playing else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        recording = nil
        status = "已停止"
        if !LoungeHub.shared.playing {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

struct PronunciationButton: View {
    let word: String
    @ObservedObject private var service = WordPronunciation.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    service.speak(word)
                } label: {
                    Label("听发音", systemImage: "speaker.wave.2")
                }
                Button("停止") { service.stop() }
            }
            PronunciationStatus()
        }
    }
}

struct PronunciationStatus: View {
    @ObservedObject private var service = WordPronunciation.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.status).font(.caption).foregroundStyle(.secondary)
            if let recording = service.recording {
                HStack {
                    Link("录音：" + recording.author, destination: recording.sourceURL)
                    Link(recording.license, destination: recording.licenseURL)
                }.font(.caption)
            }
        }
    }
}
