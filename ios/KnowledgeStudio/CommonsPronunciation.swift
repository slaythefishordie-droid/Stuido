import CryptoKit
import Foundation
import KnowledgeCore

private final class CommonsRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let allowed =
            request.url.flatMap {
                PronunciationRecording.trustedURL(
                    $0.absoluteString,
                    hosts: ["en.wiktionary.org", "commons.wikimedia.org", "upload.wikimedia.org"])
            } != nil
        completionHandler(allowed ? request : nil)
    }
}

actor CommonsPronunciation {
    static let shared = CommonsPronunciation()
    struct Cached: Codable, Sendable {
        let word: String
        let recording: PronunciationRecording
        let audio: Data
    }
    private let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Pronunciation", isDirectory: true)
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration, delegate: CommonsRedirectPolicy(), delegateQueue: nil)
    }()
    private func cacheURL(word: String, accent: String) -> URL {
        let key = SHA256.hash(data: Data((word.lowercased() + "|" + accent).utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        return root.appendingPathComponent(key + ".json")
    }
    private func cached(word: String, accent: String) -> Cached? {
        let url = cacheURL(word: word, accent: accent)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            (values.fileSize ?? Int.max) <= 3_000_000,
            let data = try? Data(contentsOf: url),
            let entry = try? JSONDecoder().decode(Cached.self, from: data),
            entry.word == word.lowercased(), entry.recording.accent == accent,
            !entry.audio.isEmpty, entry.audio.count <= 2_000_000
        else { return nil }
        return entry
    }
    func recording(word: String, preferredAccent: String) async -> Cached? {
        let word = word.lowercased()
        let other = preferredAccent == "en-US" ? "en-GB" : "en-US"
        // Offline-first: reuse either recorded accent, always label the actual accent.
        if let entry = cached(word: word, accent: preferredAccent) ?? cached(word: word, accent: other) {
            return entry
        }
        guard !PronunciationRecording.candidates(word: word, images: ["File:En-us-\(word).ogg"]).isEmpty
        else { return nil }
        do {
            let json = try await query(
                host: "en.wiktionary.org",
                parameters: ["action": "query", "titles": word, "prop": "images", "imlimit": "max"])
            let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
            let titles = pages.flatMap { $0["images"] as? [[String: Any]] ?? [] }.compactMap {
                $0["title"] as? String
            }
            let candidates = PronunciationRecording.candidates(word: word, images: titles).sorted {
                ($0.accent == preferredAccent ? 0 : 1) < ($1.accent == preferredAccent ? 0 : 1)
            }
            guard !candidates.isEmpty else { return nil }
            let selected = Array(candidates.prefix(6))
            let result = try await query(
                host: "commons.wikimedia.org",
                parameters: [
                    "action": "query", "titles": selected.map(\.title).joined(separator: "|"),
                    "prop": "videoinfo", "viprop": "url|extmetadata|derivatives|comment", "vilimit": "1",
                ])
            let files = (result["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
            for candidate in selected {
                try Task.checkCancellation()
                guard
                    let file = files.first(where: {
                        ($0["title"] as? String)?.lowercased() == candidate.title.lowercased()
                    }),
                    let info = (file["videoinfo"] as? [[String: Any]])?.first,
                    let metadata = PronunciationRecording.parse(
                        title: candidate.title, accent: candidate.accent, info: info)
                else { continue }
                let audio = try await fetch(metadata.audioURL)
                let entry = Cached(word: word, recording: metadata, audio: audio)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try JSONEncoder().encode(entry).write(
                    to: cacheURL(word: word, accent: candidate.accent), options: .atomic)
                trimCache()
                return entry
            }
        } catch { /* Missing, blocked, offline, or unlicensed: caller uses explicitly labeled TTS. */  }
        return nil
    }
    private func query(host: String, parameters: [String: String]) async throws -> [String: Any] {
        var url = URLComponents()
        url.scheme = "https"
        url.host = host
        url.path = "/w/api.php"
        url.queryItems = (parameters.merging(["format": "json", "formatversion": "2"]) { _, new in new }).map
        { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = url.url else { throw URLError(.badURL) }
        return try JSONSerialization.jsonObject(with: await fetch(url)) as? [String: Any] ?? [:]
    }
    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "KnowledgeStudio/2.0 (https://github.com/slaythefishordie-droid/Stuido)",
            forHTTPHeaderField: "User-Agent")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
            response.expectedContentLength <= 2_000_000
        else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
    private func trimCache() {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        let sorted = files.sorted {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast)
        }
        var bytes = 0
        for (index, url) in sorted.enumerated() {
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if index >= 100 || bytes > 50_000_000 { try? FileManager.default.removeItem(at: url) }
        }
    }
}
