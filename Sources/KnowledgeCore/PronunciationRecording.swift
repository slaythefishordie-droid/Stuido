import Foundation

/// Remote metadata is data, never HTML to render or arbitrary URLs to open.
public struct PronunciationRecording: Codable, Equatable, Sendable {
    public let title: String
    public let accent: String
    public let author: String
    public let license: String
    public let licenseURL: URL
    public let sourceURL: URL
    public let audioURL: URL

    public static func trustedURL(_ value: String, hosts: Set<String>) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host,
            hosts.contains(host), url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        return url
    }
    public static func candidates(word: String, images: [String]) -> [(title: String, accent: String)] {
        let word = word.lowercased().replacingOccurrences(of: " ", with: "_")
        guard !word.isEmpty, word.count <= 80,
            word.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz_'-").contains($0)
            })
        else { return [] }
        return images.compactMap { title in
            let name = title.lowercased().replacingOccurrences(of: " ", with: "_")
            for (prefix, accent) in [
                ("file:en-us-", "en-US"), ("file:en-uk-", "en-GB"), ("file:en-gb-", "en-GB"),
            ] {
                for suffix in ["", "-1", "-2"]
                where ["ogg", "oga", "mp3", "wav"].contains(where: {
                    name == prefix + word + suffix + "." + $0
                }) {
                    return (title, accent)
                }
            }
            return nil
        }
    }
    public static func parse(title: String, accent: String, info: [String: Any]) -> Self? {
        let metadata = info["extmetadata"] as? [String: [String: Any]] ?? [:]
        func plain(_ key: String) -> String {
            let raw = metadata[key]?["value"] as? String ?? ""
            return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let author = plain("Artist")
        let license = plain("LicenseShortName")
        let description = plain("ImageDescription").lowercased()
        let provenance = description + " " + (info["comment"] as? String ?? "").lowercased()
        let knownRecorder = ["Dvortygirl", "EncycloPetey", "Celestianpower"].contains(author)
        guard ["en-US", "en-GB"].contains(accent), !author.isEmpty,
            description.contains("pronunciation") || description.contains("audio of"),
            knownRecorder || provenance.contains("recorded by"),
            !provenance.contains("synthe"), !provenance.contains("text-to-speech"),
            !provenance.contains("ai-generated"),
            license == "Public domain" || license == "CC0" || license.hasPrefix("CC BY ")
                || license.hasPrefix("CC BY-SA "),
            let source = trustedURL(info["descriptionurl"] as? String ?? "", hosts: ["commons.wikimedia.org"])
        else { return nil }
        let licenseValue = plain("LicenseUrl")
        let licenseURL =
            trustedURL(
                licenseValue.hasPrefix("//") ? "https:" + licenseValue : licenseValue,
                hosts: ["creativecommons.org", "commons.wikimedia.org"])
            ?? (license == "Public domain"
                ? URL(string: "https://commons.wikimedia.org/wiki/Help:Public_domain") : nil)
        guard let licenseURL else { return nil }
        let derivatives = info["derivatives"] as? [[String: Any]] ?? []
        let raw =
            derivatives.first(where: { ($0["type"] as? String)?.hasPrefix("audio/mpeg") == true })?["src"]
            as? String
            ?? info["url"] as? String ?? ""
        guard let audio = trustedURL(raw, hosts: ["upload.wikimedia.org"]),
            ["mp3", "wav", "m4a"].contains(audio.pathExtension.lowercased())
        else { return nil }
        return Self(
            title: title, accent: accent, author: author, license: license, licenseURL: licenseURL,
            sourceURL: source, audioURL: audio)
    }
}
