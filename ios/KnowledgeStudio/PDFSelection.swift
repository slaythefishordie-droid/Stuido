import KnowledgeCore
import PDFKit

@MainActor
final class StudyPDFView: PDFView {
    var capture: ((CardKind, Bool) -> Void)?
    var captureReady = false
    var dictionary: ((String) -> Void)?
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        let commands: [UIMenuElement] = [
            UICommand(title: "单词高亮", action: #selector(markWord)),
            UICommand(title: "语料高亮", action: #selector(markExpression)),
            UICommand(title: "关键词高亮", action: #selector(markKeyword)),
            UICommand(title: "关键句高亮", action: #selector(markSentence)),
            UICommand(title: "批注", action: #selector(annotate)),
            UICommand(title: "词典", action: #selector(lookupWord)),
            UICommand(title: "听发音", action: #selector(pronounce)),
        ]
        builder.insertChild(
            UIMenu(title: "", options: .displayInline, children: commands), atStartOfMenu: .root)
    }
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if [
            #selector(markWord), #selector(markExpression), #selector(markKeyword), #selector(markSentence),
            #selector(annotate), #selector(lookupWord), #selector(pronounce),
        ].contains(action) {
            let readingAction = [#selector(lookupWord), #selector(pronounce)].contains(action)
            return (readingAction || captureReady) && currentSelection?.string?.isEmpty == false
        }
        return super.canPerformAction(action, withSender: sender)
    }
    @objc private func markWord() { capture?(.word, false) }
    @objc private func markExpression() { capture?(.expression, false) }
    @objc private func markKeyword() { capture?(.keyword, false) }
    @objc private func markSentence() { capture?(.key_sentence, false) }
    @objc private func annotate() { capture?(.expression, true) }
    @objc private func lookupWord() { if let text = currentSelection?.string { dictionary?(text) } }
    @objc private func pronounce() { WordPronunciation.shared.speak(currentSelection?.string ?? "") }
}

extension PDFSelection {
    func studioLocator(document: PDFDocument, fallbackPage: Int, fingerprint: String) -> ReadingLocator {
        var locator = ReadingLocator(
            kind: "pdf", page: pages.first.map { document.index(for: $0) + 1 } ?? fallbackPage)
        locator.fileFingerprint = fingerprint
        locator.anchorText = string
        var anchors: [PDFTextAnchor] = []
        for page in pages {
            guard let text = page.string else { continue }
            let value = text as NSString
            for index in 0..<numberOfTextRanges(on: page) {
                let range = range(at: index, on: page)
                guard range.location != NSNotFound, range.location <= value.length, range.length > 0,
                    range.length <= value.length - range.location
                else { continue }
                let beforeStart = max(0, range.location - 48)
                let end = range.location + range.length
                anchors.append(
                    PDFTextAnchor(
                        page: document.index(for: page) + 1, location: range.location,
                        length: range.length, text: value.substring(with: range),
                        before: value.substring(
                            with: NSRange(location: beforeStart, length: range.location - beforeStart)),
                        after: value.substring(
                            with: NSRange(location: end, length: min(48, value.length - end)))))
            }
        }
        locator.pdfTextAnchors = anchors.isEmpty ? nil : anchors
        for line in selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page).intersection(page.bounds(for: .cropBox))
                guard !bounds.isNull, !bounds.isEmpty else { continue }
                locator.rectangles.append(
                    HighlightRect(
                        page: document.index(for: page) + 1,
                        x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height))
            }
        }
        locator.pdfTextQuads = locator.rectangles.map(PDFTextQuad.init)
        return locator
    }
}
