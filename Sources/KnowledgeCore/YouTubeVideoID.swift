import Foundation

public struct YouTubeVideoID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard rawValue.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil else {
            throw VideoError.invalidURL
        }
        self.rawValue = rawValue
    }

    public init(urlString: String) throws {
        guard let url = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { throw VideoError.invalidURL }
        let parts = url.path.split(separator: "/").map(String.init)
        let id: String?
        switch host {
        case "youtu.be":
            id = parts.count == 1 ? parts.first : nil
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            if url.path == "/watch" {
                let values = (url.queryItems ?? []).filter { $0.name == "v" }
                id = values.count == 1 ? values.first?.value : nil
            } else if parts.count == 2 && ["embed", "shorts", "live"].contains(parts[0]) {
                id = parts[1]
            } else { id = nil }
        default:
            id = nil
        }
        guard let id else { throw VideoError.invalidURL }
        try self.init(id)
    }

    public var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(rawValue)")! }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum VideoError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL, notReady, invalidTime, staleSession, unknownSource, corruptStore, unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "请输入有效的 HTTPS YouTube 视频链接。"
        case .notReady: "播放器尚未就绪，请先在播放器内开始播放。"
        case .invalidTime: "未取得有效播放时间，本次未保存 Mark。"
        case .staleSession: "视频或页面已切换，本次操作已取消。"
        case .unknownSource: "找不到对应的资料，未保存更改。"
        case .corruptStore: "本地标记数据损坏或引用不完整，已保留原文件。"
        case .unsupportedVersion: "本地数据版本不受支持，已保留原文件。"
        }
    }
}
