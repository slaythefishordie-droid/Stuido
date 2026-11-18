import Combine
import Foundation
import KnowledgeCore
import UIKit
import YouTubePlayerKit

@MainActor
final class YouTubeStudyModel: ObservableObject {
    @Published var input = ""
    @Published private(set) var player: YouTubePlayer?
    @Published private(set) var source: VideoSource?
    @Published private(set) var sources: [VideoSource] = []
    @Published private(set) var marks: [TimestampMark] = []
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var message = "粘贴 YouTube 视频链接，在播放器内点播放。"
    @Published private(set) var storageError: String?
    private let store: MarkStore?
    private let capture: MarkCapture?
    private var token: UUID?
    private var subscriptions: Set<AnyCancellable> = []
    private var deadline: Task<Void, Never>?
    private var operation: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        do {
            let url = try fileURL ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("KnowledgeStudio/prototype-v1.json")
            let store = try MarkStore(fileURL: url)
            self.store = store
            capture = MarkCapture(store: store)
            refresh()
            if let selected = store.selectedSource { activate(selected.videoID) }
        } catch {
            store = nil
            capture = nil
            storageError = "无法读取标记存储：\(error.localizedDescription) 原文件不会被覆盖。"
        }
    }

    func openInput() {
        do {
            let id = try YouTubeVideoID(urlString: input)
            activate(id)
        } catch { message = error.localizedDescription }
    }

    func activate(_ videoID: YouTubeVideoID) {
        guard let store, let capture else { return }
        let selected: VideoSource
        do { selected = try store.select(videoID: videoID) }
        catch { message = error.localizedDescription; return }
        operation?.cancel()
        deadline?.cancel()
        subscriptions.removeAll()
        capture.invalidate()
        isReady = false
        isBusy = false
        token = nil
        source = selected
        refresh()
        input = selected.videoID.watchURL.absoluteString
        // The wrapper uses originURL as loadHTMLString's baseURL, which supplies Referer.
        // Derive this at runtime so AltStore's re-signed bundle identifier is respected.
        guard let identifier = Bundle.main.bundleIdentifier,
              let origin = URL(string: "https://\(identifier.lowercased())") else {
            self.player = nil
            message = "无法读取应用身份，播放器未加载。"
            return
        }
        let player = YouTubePlayer(
            source: .video(id: selected.videoID.rawValue),
            parameters: .init(autoPlay: false, showControls: true, showFullscreenButton: false,
                              originURL: origin, referrerURL: origin),
            configuration: .init(
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: false,
                openURLAction: .init { url, _ in
                    guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
                    await UIApplication.shared.open(url)
                }
            )
        )
        self.player = player
        let current = capture.activate(source: selected, clock: YouTubeClock(player: player))
        token = current
        message = "正在连接播放器…"
        player.statePublisher.sink { [weak self] state in
            Task { @MainActor in self?.receive(state, token: current) }
        }.store(in: &subscriptions)
        player.autoplayBlockedPublisher.sink { [weak self] in
            Task { @MainActor in
                guard self?.token == current else { return }
                self?.message = "自动播放受限，请点播放器内的播放按钮。"
            }
        }.store(in: &subscriptions)
        armDeadline(seconds: 20, token: current, message: "播放器连接超时，请检查网络后重试。")
    }

    func saveMark() {
        perform(success: "Mark 已保存，可继续观看。") { [capture] in _ = try await capture?.capture() }
    }

    func replay(_ mark: TimestampMark, preRoll: Bool) {
        perform(success: "已请求回跳；若播放被浏览器限制，请点播放器内的播放按钮。") { [capture] in
            try await capture?.replay(mark, preRoll: preRoll ? 3 : 0)
        }
    }

    private func perform(success: String, action: @escaping @MainActor () async throws -> Void) {
        guard let current = token, isReady, !isBusy else { return }
        isBusy = true
        armDeadline(seconds: 8, token: current, message: "读取播放器超时，本次未保存；请重新连接。")
        operation = Task { [weak self] in
            do {
                try await action()
                guard let self, self.token == current else { return }
                self.message = success
                self.refresh()
            } catch {
                guard let self, self.token == current else { return }
                self.message = "操作未完成：\(error.localizedDescription)"
            }
            guard let self, self.token == current else { return }
            self.deadline?.cancel()
            self.isBusy = false
        }
    }

    private func receive(_ state: YouTubePlayer.State, token: UUID) {
        guard self.token == token else { return }
        isReady = state.isReady
        capture?.updateReady(isReady, generation: token)
        switch state {
        case .idle: break
        case .ready:
            deadline?.cancel()
            message = "播放器已就绪。点击播放；Mark 会保存读取到的原始秒数。"
        case .error(let error):
            deadline?.cancel()
            switch error {
            case .missingAPIClientIdentification: message = "YouTube 拒绝应用身份（153），需检查重签后的 Bundle ID 与 Referer。"
            case .embeddedVideoPlayingNotAllowed: message = "视频禁止嵌入（101/150），可在 YouTube 打开。"
            case .notFound: message = "视频不存在、为私有视频或已删除。"
            default: message = "播放器加载失败，请检查网络后重试：\(error)"
            }
        }
    }

    private func armDeadline(seconds: Double, token: UUID, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.token == token else { return }
            self.capture?.invalidate()
            self.token = nil
            self.isReady = false
            self.isBusy = false
            self.operation?.cancel()
            self.message = message
        }
    }

    private func refresh() {
        sources = store?.snapshot.sources ?? []
        marks = (store?.snapshot.marks ?? []).filter { $0.sourceID == source?.id }.reversed()
    }
}
