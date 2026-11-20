import Foundation

public enum PDFAnchorAccuracy: String, Sendable {
    case exactText, exactRegion, pageOnly, unavailable
}

extension ReadingLocator {
    /// Coordinates are only trusted for the same fingerprint. Text precision requires an actual text check.
    public func pdfAccuracy(currentFingerprint: String?, pageCount: Int, textVerified: Bool = false)
        -> PDFAnchorAccuracy
    {
        guard kind == "pdf", pageCount > 0, let page, (1...pageCount).contains(page) else {
            return .unavailable
        }
        if let fileFingerprint, fileFingerprint != currentFingerprint { return .unavailable }
        guard fileFingerprint != nil, !rectangles.isEmpty,
            rectangles.allSatisfy({ (1...pageCount).contains($0.page) && $0.isValid })
        else { return .pageOnly }
        return textVerified && !(anchorText ?? "").isEmpty ? .exactText : .exactRegion
    }
}
extension HighlightRect {
    public var isValid: Bool {
        page > 0 && [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
}
