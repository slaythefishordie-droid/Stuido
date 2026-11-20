import Foundation

/// PencilKit bytes in top-left CropBox coordinates, with one record per file revision and page.
public struct PDFPageInk: Codable, Equatable, Sendable {
    public let fingerprint: String
    public let page: Int
    public let drawing: Data

    public init(fingerprint: String, page: Int, drawing: Data) {
        self.fingerprint = fingerprint
        self.page = page
        self.drawing = drawing
    }
}
