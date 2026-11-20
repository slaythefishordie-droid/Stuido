import Foundation

/// A selected PDF text range, in UTF-16 offsets in that page's text layer.
/// Context plus geometry disambiguate repeated text; no global quote search is used.
public struct PDFTextAnchor: Codable, Equatable, Sendable {
    public var page: Int
    public var location: Int
    public var length: Int
    public var text: String
    public var before: String
    public var after: String
    public init(page: Int, location: Int, length: Int, text: String, before: String, after: String) {
        self.page = page
        self.location = location
        self.length = length
        self.text = text
        self.before = before
        self.after = after
    }
    public func matches(_ pageText: String) -> Bool {
        let value = pageText as NSString
        guard location >= 0, length > 0, location <= value.length, length <= value.length - location else {
            return false
        }
        let prefix = before as NSString
        let suffix = after as NSString
        guard prefix.length <= location, suffix.length <= value.length - location - length else {
            return false
        }
        return value.substring(with: NSRange(location: location, length: length)) == text
            && value.substring(with: NSRange(location: location - prefix.length, length: prefix.length))
                == before
            && value.substring(with: NSRange(location: location + length, length: suffix.length)) == after
    }
}

/// Page-space corners in PDF annotation order. Bounds remain available to older readers.
public struct PDFTextQuad: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double, y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }
    public var page: Int
    public var points: [Point]
    public init(rect: HighlightRect) {
        page = rect.page
        points = [
            .init(x: rect.x, y: rect.y + rect.height), .init(x: rect.x + rect.width, y: rect.y + rect.height),
            .init(x: rect.x, y: rect.y), .init(x: rect.x + rect.width, y: rect.y),
        ]
    }
}
