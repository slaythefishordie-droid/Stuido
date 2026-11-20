import Foundation
import KnowledgeCore
import PDFKit
import Vision

struct RecognizedPDFRegion: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let rect: HighlightRect
}

enum PDFRecognition {
    /// Recognize only one explicitly requested page. OCR text is never a verified text anchor.
    static func recognize(url: URL, pageNumber: Int) async throws -> [RecognizedPDFRegion] {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url), let page = document.page(at: pageNumber - 1),
                let reference = page.pageRef
            else { throw LibraryError.invalid("无法读取待识别页面") }
            let crop = reference.getBoxRect(.cropBox)
            guard crop.width > 0, crop.height > 0 else { throw LibraryError.invalid("书页尺寸无效") }
            let quarterTurn = abs(reference.rotationAngle) % 180 == 90
            let width = quarterTurn ? crop.height : crop.width
            let height = quarterTurn ? crop.width : crop.height
            let scale = min(2.0, 2048.0 / max(width, height))
            let pixelWidth = max(1, Int(width * scale))
            let pixelHeight = max(1, Int(height * scale))
            guard
                let context = CGContext(
                    data: nil, width: pixelWidth, height: pixelHeight,
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw LibraryError.invalid("无法创建识别图像") }
            let imageBounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(imageBounds)
            let transform = reference.getDrawingTransform(
                .cropBox, rect: imageBounds, rotate: 0, preserveAspectRatio: true)
            context.concatenate(transform)
            context.drawPDFPage(reference)
            guard let image = context.makeImage() else { throw LibraryError.invalid("无法渲染识别图像") }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "zh-Hans"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let inverse = transform.inverted()
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.6 else {
                    return nil
                }
                let box = observation.boundingBox
                let pixels = CGRect(
                    x: box.minX * Double(pixelWidth), y: box.minY * Double(pixelHeight),
                    width: box.width * Double(pixelWidth), height: box.height * Double(pixelHeight))
                let region = pixels.applying(inverse).intersection(crop)
                guard !region.isNull, !region.isEmpty else { return nil }
                return RecognizedPDFRegion(
                    text: candidate.string,
                    rect: HighlightRect(
                        page: pageNumber, x: region.minX, y: region.minY, width: region.width,
                        height: region.height))
            }
        }.value
    }
}
