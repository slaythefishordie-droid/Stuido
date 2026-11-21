@preconcurrency import AVFoundation
import Foundation
import KnowledgeCore
import SwiftUI
@preconcurrency import UserNotifications

struct LoungeTrack: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let filename: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artwork: Data?
    var favorite = false
}

struct LoungePlaylist: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var trackIDs: [String]
}

enum LoungePromptKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case activity, trivia
    var id: Self { self }
    var title: String { self == .activity ? "有趣の事" : "你知道吗？" }
}

struct LoungePrompt: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: LoungePromptKind
    var title: String
    var text: String
    var source: URL?
    var favorite = false
}

private struct LoungeDisk: Codable, Equatable {
    var tracks: [LoungeTrack] = []
    var playlists: [LoungePlaylist] = []
    var prompts: [LoungePrompt] = []
    var draws: [String: [UUID]] = [:]
    var nextDraw: [String: Date] = [:]
    var timer = LoungeCountdown()
    var lastTrackID: String?
    var playhead: Double?
}

@MainActor
final class LoungeHub: ObservableObject {
    static let shared = LoungeHub()
    static let notificationID = "knowledge-studio.lounge.timer"

    @Published private var disk = LoungeDisk()
    @Published private(set) var player: AVAudioPlayer?
    @Published private(set) var playing = false
    @Published private(set) var reminder: UUID?
    @Published private(set) var route: UUID?
    @Published private(set) var ledgerVersion = 0
    @Published private(set) var importing = false
    @Published var message: String?
    @Published var volume: Float = 0.75 {
        didSet { player?.volume = volume }
    }
    @Published var mode: PlaybackMode = .sequence
    enum PlaybackMode: String, CaseIterable, Identifiable {
        case sequence = "顺序", shuffle = "随机", repeatOne = "单曲循环"
        var id: Self { self }
    }

    private struct SceneActivity {
        var order: UInt64
        var sourceID: UUID?
    }
    private let root: URL
    private var ledger: LoungeLedger
    private var scenes: [UUID: SceneActivity] = [:]
    private var sceneOrder: UInt64 = 0
    private var ticker: Task<Void, Never>?
    private var audioCheckpoint: TimeInterval = 0
    private var lastSavedLedger: [StudyInterval]
    private var entryLoadFailed = false
    private var ledgerLoadFailed = false
    private var playbackScope: UUID?
    private var wikiCache: [String: WikipediaNote] = [:]
    private var lastWikiRequest = Date.distantPast

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KnowledgeStudio/Lounge", isDirectory: true)
        let journal = self.root.appendingPathComponent("study-time.json")
        let library = self.root.appendingPathComponent("lounge.json")
        let restored = try? JSONDecoder().decode([StudyInterval].self, from: Data(contentsOf: journal))
        lastSavedLedger = restored ?? []
        ledger = LoungeLedger(records: restored ?? [])
        ledgerLoadFailed = restored == nil && FileManager.default.fileExists(atPath: journal.path)
        do {
            if FileManager.default.fileExists(atPath: library.path) {
                disk = try JSONDecoder().decode(LoungeDisk.self, from: Data(contentsOf: library))
            }
        } catch {
            entryLoadFailed = true
            message = "休息室资料无法读取，原文件已保留。"
        }
        if ledgerLoadFailed { message = "学习时光记录无法读取，原文件已保留。" }
        if !entryLoadFailed { recoverMusicRemovals() }
    }

    private func recoverMusicRemovals() {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: audioDirectory,
            includingPropertiesForKeys: nil) else { return }
        let protected = Set(disk.tracks.map(\.filename))
        for stage in entries where stage.lastPathComponent.hasPrefix("removed-") {
            let name = String(stage.lastPathComponent.dropFirst("removed-".count))
            let original = audioDirectory.appendingPathComponent(name)
            do {
                if protected.contains(name) && !FileManager.default.fileExists(atPath: original.path) {
                    try FileManager.default.moveItem(at: stage, to: original)
                } else { try FileManager.default.removeItem(at: stage) }
            } catch { message = "曲库还有待恢复的文件：\(error.localizedDescription)" }
        }
    }

    var tracks: [LoungeTrack] { disk.tracks }
    var playlists: [LoungePlaylist] { disk.playlists }
    var countdown: LoungeCountdown { disk.timer }
    var track: LoungeTrack? { tracks.first { $0.id == disk.lastTrackID } }
    var playhead: Double { player?.currentTime ?? disk.playhead ?? 0 }

    func scene(_ id: UUID, active: Bool, sourceID: UUID?, promote: Bool = false) {
        let now = Date.now
        let uptime = ProcessInfo.processInfo.systemUptime
        if active {
            if scenes[id] == nil || promote { sceneOrder &+= 1 }
            scenes[id] = SceneActivity(order: promote ? sceneOrder : scenes[id]?.order ?? sceneOrder,
                sourceID: sourceID)
        } else {
            scenes.removeValue(forKey: id)
        }
        let foreground = scenes.values.max { $0.order < $1.order }
        ledger.transition(active: foreground != nil, sourceID: foreground?.sourceID, now: now, uptime: uptime)
        persistLedger()
        if scenes.isEmpty {
            ticker?.cancel()
            ticker = nil
            savePlayhead()
        } else {
            tick()
            if ticker == nil {
                ticker = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        self?.tick()
                    }
                }
            }
        }
    }

    func intervals(at now: Date = .now) -> [StudyInterval] {
        ledger.snapshot(now: now, uptime: ProcessInfo.processInfo.systemUptime)
    }

    private func persistLedger() {
        guard !ledgerLoadFailed, ledger.records != lastSavedLedger else { return }
        do {
            try write(ledger.records, to: "study-time.json")
            lastSavedLedger = ledger.records
            ledgerVersion &+= 1
        } catch { message = "学习时间未能保存：\(error.localizedDescription)" }
    }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent(name), options: .atomic)
    }

    @discardableResult private func update(_ edit: (inout LoungeDisk) -> Void) -> Bool {
        guard !entryLoadFailed else { message = "休息室资料未能读取，原文件已保留。"; return false }
        var next = disk
        edit(&next)
        guard next != disk else { return true }
        do { try write(next, to: "lounge.json"); disk = next; return true }
        catch { message = "休息室未能保存：\(error.localizedDescription)"; return false }
    }

    private func tick() {
        let now = Date.now
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - audioCheckpoint >= 30 {
            audioCheckpoint = uptime
            ledger.checkpoint(now: now, uptime: uptime)
            persistLedger()
            savePlayhead()
        }
        if playing, let player, !player.isPlaying {
            if player.currentTime == 0 || player.currentTime >= player.duration - 0.1 {
                if mode == .repeatOne, let track { play(track, scope: playbackScope, resume: false) }
                else { skip(1, automatically: true) }
            } else { playing = false }
        }
        var timer = disk.timer
        if timer.consumeCompletion(at: now), update({ $0.timer = timer }) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
            if UserDefaults.standard.object(forKey: "loungeTimerPopup") == nil ||
                UserDefaults.standard.bool(forKey: "loungeTimerPopup") {
                reminder = UUID()
            }
            if UserDefaults.standard.bool(forKey: "loungeTimerHaptics") {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        let interval = drawInterval
        if interval > 0 {
            for kind in LoungePromptKind.allCases where disk.nextDraw[kind.rawValue, default: .distantPast] <= now {
                draw(kind)
            }
        }
    }

    func startTimer(_ minutes: Int) {
        if update({ $0.timer.start(minutes: minutes, at: .now) }) { scheduleNotification(requestPermission: true) }
    }
    func pauseTimer() {
        tick()
        if update({ $0.timer.pause(at: .now) }) { scheduleNotification() }
    }
    func resumeTimer() {
        if update({ $0.timer.resume(at: .now) }) { scheduleNotification() }
    }
    func cancelTimer() {
        if update({ $0.timer = LoungeCountdown() }) { scheduleNotification() }
    }

    func openFromNotification() {
        reminder = nil
        route = UUID()
    }
    func closeReminder() { reminder = nil }

    private func scheduleNotification(requestPermission: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        guard let deadline = disk.timer.deadline else { return }
        Task {
            var settings = await center.notificationSettings()
            if requestPermission, settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }
            guard disk.timer.deadline == deadline else { return }
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
                if requestPermission { message = "计时已开始。系统通知未启用，可在 iPad 设置中开启。" }
                return
            }
            let seconds = deadline.timeIntervalSinceNow
            guard seconds > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = "休息片刻"
            content.body = "计时完成，休息室为你留了一盏灯。"
            if !UserDefaults.standard.bool(forKey: "loungeTimerSilent") { content.sound = .default }
            do {
                try await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)))
            } catch { message = "计时已开始，系统提醒未能安排。" }
            if disk.timer.deadline != deadline {
                scheduleNotification()
            }
        }
    }

    private var audioDirectory: URL { root.appendingPathComponent("Music", isDirectory: true) }

    func importTracks(_ urls: [URL]) async {
        guard !importing, !entryLoadFailed else { return }
        importing = true
        defer { importing = false }
        let directory = audioDirectory
        var failures: [String] = []
        for url in urls {
            do {
                let track = try await Task.detached(priority: .userInitiated) {
                    try await Self.copyTrack(url, to: directory)
                }.value
                update { state in
                    if !state.tracks.contains(where: { $0.id == track.id }) { state.tracks.append(track) }
                }
            } catch { failures.append(url.lastPathComponent + " · " + error.localizedDescription) }
        }
        if !failures.isEmpty { message = failures.joined(separator: "\n") }
    }

    nonisolated private static func copyTrack(_ url: URL, to directory: URL) async throws -> LoungeTrack {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        guard ["mp3", "m4a", "aac", "flac"].contains(ext) else {
            throw LibraryError.invalid("请选择 MP3、AAC、M4A 或 FLAC")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appendingPathComponent("import-" + UUID().uuidString + "." + ext)
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: url, to: stage)
        let audio = try AVAudioFile(forReading: stage)
        guard audio.length > 0, audio.processingFormat.sampleRate > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 1024)
        else { throw LibraryError.invalid("音频为空或编码不可用") }
        try audio.read(into: buffer, frameCount: 1024)
        guard buffer.frameLength > 0 else { throw LibraryError.invalid("音频无法解码") }
        let id = try StudioModel.hash(stage)
        let filename = id + "." + ext
        let asset = AVURLAsset(url: stage)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func value(_ key: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: key).first else { return nil }
            return try? await item.load(.stringValue)
        }
        let title = await value(.commonIdentifierTitle)
        let artist = await value(.commonIdentifierArtist)
        let album = await value(.commonIdentifierAlbumName)
        let artItem = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first
        let artwork = try? await artItem?.load(.dataValue)
        let output = directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: output.path) { try FileManager.default.moveItem(at: stage, to: output) }
        return LoungeTrack(id: id, filename: filename, title: title ?? url.deletingPathExtension().lastPathComponent,
            artist: artist ?? "", album: album ?? "", duration: Double(audio.length) / audio.processingFormat.sampleRate,
            artwork: artwork.flatMap { $0.count <= 250_000 ? $0 : nil })
    }

    func play(_ track: LoungeTrack, scope: UUID? = nil, resume: Bool = true) {
        do {
            let next = try AVAudioPlayer(contentsOf: audioDirectory.appendingPathComponent(track.filename))
            if resume, disk.lastTrackID == track.id { next.currentTime = min(next.duration, disk.playhead ?? 0) }
            next.volume = volume
            guard next.prepareToPlay(), next.play() else { throw LibraryError.invalid("系统未能播放这个音频文件") }
            guard update({ $0.lastTrackID = track.id; $0.playhead = next.currentTime }) else {
                next.stop()
                return
            }
            player?.stop()
            player = next
            playbackScope = scope
            playing = true
        } catch { message = error.localizedDescription }
    }

    func togglePlayback() {
        if let player {
            if player.isPlaying { player.pause(); playing = false; savePlayhead() }
            else {
                playing = player.play()
                if !playing { message = "播放未能继续。" }
            }
        } else if let track = track ?? tracks.first { play(track) }
    }

    func seek(_ seconds: Double) {
        guard let player else {
            if let track { update { $0.playhead = min(track.duration, max(0, seconds)) } }
            return
        }
        player.currentTime = min(player.duration, max(0, seconds))
        savePlayhead()
    }

    func skip(_ direction: Int, automatically: Bool = false) {
        let ids = playlists.first { $0.id == playbackScope }?.trackIDs
        let list = ids?.compactMap { id in tracks.first { $0.id == id } } ?? tracks
        guard !list.isEmpty else { playing = false; return }
        let index = list.firstIndex { $0.id == track?.id } ?? 0
        if automatically, mode == .sequence, index == list.count - 1 {
            player?.stop()
            player = nil
            playing = false
            update { $0.playhead = 0 }
            return
        }
        let next = mode == .shuffle && list.count > 1
            ? list.indices.filter { $0 != index }.randomElement() ?? index
            : (index + direction + list.count) % list.count
        play(list[next], scope: playbackScope, resume: false)
    }

    private func savePlayhead() {
        if let player { update { $0.playhead = player.currentTime } }
    }

    func favorite(_ track: LoungeTrack) {
        update { state in
            if let index = state.tracks.firstIndex(where: { $0.id == track.id }) { state.tracks[index].favorite.toggle() }
        }
    }

    func makePlaylist(_ name: String) {
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        update { $0.playlists.append(LoungePlaylist(name: label, trackIDs: [])) }
    }

    func assign(_ track: LoungeTrack, to playlist: LoungePlaylist, remove: Bool = false) {
        update { state in
            guard let index = state.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
            if remove { state.playlists[index].trackIDs.removeAll { $0 == track.id } }
            else if !state.playlists[index].trackIDs.contains(track.id) { state.playlists[index].trackIDs.append(track.id) }
        }
    }

    func remove(_ playlist: LoungePlaylist) { update { $0.playlists.removeAll { $0.id == playlist.id } } }

    func remove(_ track: LoungeTrack) {
        let file = audioDirectory.appendingPathComponent(track.filename)
        let stage = audioDirectory.appendingPathComponent("removed-" + track.filename)
        do {
            let exists = FileManager.default.fileExists(atPath: file.path)
            if exists { try FileManager.default.moveItem(at: file, to: stage) }
            guard update({ state in
                state.tracks.removeAll { $0.id == track.id }
                if state.lastTrackID == track.id { state.lastTrackID = nil; state.playhead = nil }
                for index in state.playlists.indices { state.playlists[index].trackIDs.removeAll { $0 == track.id } }
            }) else {
                if exists { try FileManager.default.moveItem(at: stage, to: file) }
                return
            }
            if player?.url == file { player?.stop(); player = nil; playing = false }
            if exists { try FileManager.default.removeItem(at: stage) }
        } catch { message = error.localizedDescription }
    }

    private var drawInterval: Int {
        (UserDefaults.standard.object(forKey: "loungeDrawInterval") as? Int) ?? 30
    }

    func reminderPreferencesChanged() { scheduleNotification() }

    func refreshRecommendationSchedule() {
        let deadline = Date.now.addingTimeInterval(Double(max(5, drawInterval) * 60))
        update { state in
            for kind in LoungePromptKind.allCases { state.nextDraw[kind.rawValue] = deadline }
        }
    }

    func prompts(_ kind: LoungePromptKind) -> [LoungePrompt] { disk.prompts.filter { $0.kind == kind } }
    func recent(_ kind: LoungePromptKind) -> [LoungePrompt] {
        (disk.draws[kind.rawValue] ?? []).compactMap { id in disk.prompts.first { $0.id == id } }
    }
    func draw(_ kind: LoungePromptKind) {
        let items = prompts(kind)
        guard !items.isEmpty else { return }
        let history = disk.draws[kind.rawValue] ?? []
        let excluded = Set(history.prefix(min(5, max(0, items.count - 1))))
        guard let pick = items.filter({ !excluded.contains($0.id) }).randomElement() else { return }
        let delay = TimeInterval(max(5, drawInterval) * 60)
        update { state in
            state.draws[kind.rawValue] = Array(([pick.id] + history).prefix(30))
            state.nextDraw[kind.rawValue] = .now.addingTimeInterval(delay)
        }
    }
    func save(_ prompt: LoungePrompt) {
        guard !prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        update {
            if let index = $0.prompts.firstIndex(where: { $0.id == prompt.id }) { $0.prompts[index] = prompt }
            else { $0.prompts.append(prompt) }
        }
    }
    func remove(_ prompt: LoungePrompt) {
        update { $0.prompts.removeAll { $0.id == prompt.id } }
    }
    func favorite(_ prompt: LoungePrompt) {
        var changed = prompt
        changed.favorite.toggle()
        save(changed)
    }

    func importPrompts(_ url: URL, kind: LoungePromptKind) async {
        do {
            let entries = try await Task.detached(priority: .userInitiated) {
                try Self.readPrompts(url, kind: kind)
            }.value
            update { state in
                for entry in entries where !state.prompts.contains(where: {
                    $0.kind == entry.kind && $0.title == entry.title && $0.text == entry.text
                }) { state.prompts.append(entry) }
            }
            if recent(kind).isEmpty { draw(kind) }
        } catch { message = error.localizedDescription }
    }

    nonisolated private static func readPrompts(_ url: URL, kind: LoungePromptKind) throws -> [LoungePrompt] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576, let raw = String(data: data, encoding: .utf8) else {
            throw LibraryError.invalid("请选择 1 MB 以内的 UTF-8 清单")
        }
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        let csv = url.pathExtension.lowercased() == "csv"
        let lines = csv ? try LoungeCSV.rows(text) : text.components(separatedBy: .newlines).map { [$0] }
        let prompts = lines.enumerated().compactMap { index, row -> LoungePrompt? in
            let fields = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let first = fields.first, !first.isEmpty else { return nil }
            if csv, index == 0, ["title", "标题", "主题"].contains(first.lowercased()) { return nil }
            let body = fields.count > 1 && !fields[1].isEmpty ? fields[1] : first
            let link = fields.count > 2 ? URL(string: fields[2]) : nil
            return LoungePrompt(kind: kind, title: body == first ? "" : first, text: body,
                source: link?.scheme == "https" ? link : nil)
        }
        guard !prompts.isEmpty else { throw LibraryError.invalid("清单中没有可导入的内容") }
        return Array(prompts.prefix(2_000))
    }
}

struct WikipediaNote: Identifiable, Sendable {
    var id: URL { url }
    let title: String
    let extract: String
    let url: URL
    let fetchedAt: Date
}

extension LoungeHub {
    func lookup(_ query: String) async throws -> WikipediaNote {
        let term = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !term.isEmpty else { throw LibraryError.invalid("请输入想了解的主题") }
        let language = term.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) ? "zh" : "en"
        let key = language + ":" + term.lowercased()
        if let cached = wikiCache[key], Date.now.timeIntervalSince(cached.fetchedAt) < 86_400 { return cached }
        guard Date.now.timeIntervalSince(lastWikiRequest) >= 3 else {
            throw LibraryError.invalid("请稍后再查。休息室清单仍可离线使用。")
        }
        lastWikiRequest = .now
        var components = URLComponents()
        components.scheme = "https"
        components.host = language + ".wikipedia.org"
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: term), URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "gsrlimit", value: "1"), URLQueryItem(name: "prop", value: "extracts|info"),
            URLQueryItem(name: "exintro", value: "1"), URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exchars", value: "650"), URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "formatversion", value: "2"),
        ]
        guard let url = components.url else { throw LibraryError.invalid("查询无效") }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("KnowledgeStudio/3.6 iPadOS (https://github.com/slaythefishordie-droid/Stuido)",
            forHTTPHeaderField: "User-Agent")
        struct Reply: Decodable {
            struct Query: Decodable {
                struct Page: Decodable {
                    let title: String
                    let extract: String?
                    let fullurl: URL?
                }
                let pages: [Page]
            }
            let query: Query?
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 256_000,
            let page = try JSONDecoder().decode(Reply.self, from: data).query?.pages.first,
            let extract = page.extract, !extract.isEmpty, let link = page.fullurl, link.scheme == "https",
            link.host == components.host
        else { throw LibraryError.invalid("百科暂时没有可用摘要") }
        let result = WikipediaNote(title: page.title, extract: extract, url: link, fetchedAt: .now)
        if wikiCache.count >= 40, let oldest = wikiCache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt }) {
            wikiCache.removeValue(forKey: oldest.key)
        }
        wikiCache[key] = result
        return result
    }
}

@MainActor
final class LoungeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool
    {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async
    {
        if response.notification.request.identifier == "knowledge-studio.lounge.timer" {
            await LoungeHub.shared.openFromNotification()
        }
    }
}
