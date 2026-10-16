import UIKit

/// A chapter rendered to an attributed string, plus the mapping between
/// content blocks (stable anchors) and character offsets (layout-specific).
struct RenderedChapter {
    let index: Int
    let attributed: NSAttributedString
    /// Range of each block's rendered text (newline separators excluded).
    let blockRanges: [NSRange]
    let wordCount: Int

    var length: Int { attributed.length }

    func blockIndex(containing location: Int) -> Int {
        guard !blockRanges.isEmpty else { return 0 }
        var low = 0, high = blockRanges.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if blockRanges[mid].location <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func characterIndex(for locator: ReadingLocator) -> Int {
        guard blockRanges.indices.contains(locator.block) else {
            return locator.block >= blockRanges.count ? max(length - 1, 0) : 0
        }
        let range = blockRanges[locator.block]
        return range.location + min(max(locator.offset, 0), range.length)
    }

    func locator(forCharacterIndex index: Int) -> ReadingLocator {
        let block = blockIndex(containing: index)
        let range = blockRanges.indices.contains(block) ? blockRanges[block] : NSRange(location: 0, length: 0)
        return ReadingLocator(chapter: self.index, block: block, offset: min(max(index - range.location, 0), range.length))
    }

    func range(for anchor: TextAnchor) -> NSRange? {
        guard anchor.chapter == index,
              blockRanges.indices.contains(anchor.startBlock),
              blockRanges.indices.contains(anchor.endBlock) else { return nil }
        let start = blockRanges[anchor.startBlock].location + min(anchor.startOffset, blockRanges[anchor.startBlock].length)
        let end = blockRanges[anchor.endBlock].location + min(anchor.endOffset, blockRanges[anchor.endBlock].length)
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    func anchor(for range: NSRange) -> TextAnchor {
        let start = locator(forCharacterIndex: range.location)
        let end = locator(forCharacterIndex: NSMaxRange(range))
        // A range that ends exactly at a block boundary belongs to the previous block.
        var endBlock = end.block, endOffset = end.offset
        if endBlock > start.block, endOffset == 0, blockRanges.indices.contains(endBlock - 1) {
            endBlock -= 1
            endOffset = blockRanges[endBlock].length
        }
        return TextAnchor(chapter: index, startBlock: start.block, startOffset: start.offset,
                          endBlock: endBlock, endOffset: endOffset)
    }

    func paragraphRange(containing location: Int) -> NSRange {
        let block = blockIndex(containing: location)
        return blockRanges.indices.contains(block) ? blockRanges[block] : NSRange(location: 0, length: 0)
    }
}

enum ChapterRenderer {
    static func render(_ chapter: Chapter, style: ReaderStyle, imagesDirectory: URL?,
                       contentWidth: CGFloat, maxImageHeight: CGFloat) -> RenderedChapter {
        let output = NSMutableAttributedString()
        var ranges: [NSRange] = []
        ranges.reserveCapacity(chapter.blocks.count)

        let theme = style.theme
        let size = style.fontSize
        // The newline ending the previous block, appended once the next visible block starts.
        var pendingSeparator: NSAttributedString?

        for block in chapter.blocks {
            guard block.kind != .omitted else {
                // Nothing to show; a zero-length range at the next block's start keeps indices stable.
                ranges.append(NSRange(location: output.length + (pendingSeparator == nil ? 0 : 1), length: 0))
                continue
            }
            if let separator = pendingSeparator { output.append(separator) }
            let isFirst = output.length == 0
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = style.lineSpacing
            paragraph.paragraphSpacing = style.paragraphSpacing
            paragraph.alignment = style.alignment
            paragraph.hyphenationFactor = style.hyphenation
            paragraph.lineBreakStrategy = .pushOut

            var font = style.bodyFont
            var color = theme.text
            var text = block.text

            switch block.kind {
            case .paragraph:
                break
            case .heading:
                let scale: CGFloat = block.level <= 1 ? 1.5 : (block.level == 2 ? 1.32 : 1.12)
                font = style.preferences.font.uiFont(size: (size * scale).rounded(), bold: true)
                paragraph.alignment = .natural
                paragraph.hyphenationFactor = 0
                paragraph.paragraphSpacingBefore = isFirst ? size * 0.4 : size * 1.4
                paragraph.paragraphSpacing = size * 0.9
                paragraph.lineSpacing = style.lineSpacing * 0.5
            case .quote:
                font = style.preferences.font.uiFont(size: size, italic: true)
                paragraph.firstLineHeadIndent = size * 1.2
                paragraph.headIndent = size * 1.2
                paragraph.tailIndent = -size * 0.6
                color = theme.text.withAlphaComponent(0.85)
            case .listItem:
                paragraph.headIndent = size * 1.25
                paragraph.firstLineHeadIndent = size * 0.25
                paragraph.paragraphSpacing = style.paragraphSpacing * 0.5
            case .preformatted:
                font = UIFont.monospacedSystemFont(ofSize: size * 0.82, weight: .regular)
                paragraph.alignment = .natural
                paragraph.hyphenationFactor = 0
                paragraph.lineSpacing = style.lineSpacing * 0.4
            case .caption:
                font = style.preferences.font.uiFont(size: size * 0.82, italic: true)
                paragraph.alignment = .center
                color = theme.secondaryText
            case .separator:
                text = "⁂"
                paragraph.alignment = .center
                paragraph.paragraphSpacingBefore = size * 0.6
                paragraph.paragraphSpacing = size * 1.2
                color = theme.secondaryText
            case .image:
                text = "\u{FFFC}"
                paragraph.alignment = .center
                paragraph.paragraphSpacingBefore = size * 0.5
                paragraph.paragraphSpacing = size
            case .title:
                font = style.preferences.font.uiFont(size: (size * 1.75).rounded())
                paragraph.alignment = .center
                paragraph.hyphenationFactor = 0
                paragraph.lineSpacing = style.lineSpacing * 0.4
                paragraph.paragraphSpacingBefore = isFirst ? size * 2.4 : size * 3
                paragraph.paragraphSpacing = size * 2.6
            case .omitted:
                break
            }

            let start = output.length
            if block.kind == .image {
                if let attachment = imageAttachment(block, directory: imagesDirectory, width: contentWidth, maxHeight: maxImageHeight) {
                    let attachmentString = NSMutableAttributedString(attachment: attachment)
                    attachmentString.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attachmentString.length))
                    output.append(attachmentString)
                } else {
                    output.append(NSAttributedString(string: "·", attributes: [.font: font, .foregroundColor: theme.secondaryText, .paragraphStyle: paragraph]))
                }
            } else {
                let piece = NSMutableAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph,
                ])
                if block.kind == .title {
                    styleTitlePage(piece, block: block, style: style, paragraph: paragraph)
                } else if block.kind != .heading {
                    applySpans(block.spans, to: piece, style: style, base: font)
                }
                output.append(piece)
            }
            ranges.append(NSRange(location: start, length: output.length - start))
            let lastParagraph = output.attribute(.paragraphStyle, at: max(output.length - 1, 0), effectiveRange: nil) ?? paragraph
            pendingSeparator = NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: lastParagraph])
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: " ", attributes: [.font: style.bodyFont]))
        }
        if ranges.isEmpty { ranges = [NSRange(location: 0, length: 0)] }
        return RenderedChapter(index: chapter.id, attributed: output, blockRanges: ranges, wordCount: chapter.wordCount)
    }

    private static func applySpans(_ spans: [InlineSpan], to string: NSMutableAttributedString, style: ReaderStyle, base: UIFont) {
        let length = string.length
        for span in spans {
            let range = NSRange(location: span.location, length: min(span.length, length - span.location))
            guard range.location >= 0, range.location < length, range.length > 0 else { continue }
            switch span.style {
            case .italic:
                string.enumerateAttribute(.font, in: range) { value, sub, _ in
                    let current = (value as? UIFont) ?? base
                    let bold = current.fontDescriptor.symbolicTraits.contains(.traitBold)
                    string.addAttribute(.font, value: style.preferences.font.uiFont(size: current.pointSize, bold: bold, italic: true), range: sub)
                }
            case .bold:
                string.enumerateAttribute(.font, in: range) { value, sub, _ in
                    let current = (value as? UIFont) ?? base
                    let italic = current.fontDescriptor.symbolicTraits.contains(.traitItalic)
                    string.addAttribute(.font, value: style.preferences.font.uiFont(size: current.pointSize, bold: true, italic: italic), range: sub)
                }
            case .code:
                string.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: base.pointSize * 0.88, weight: .regular), range: range)
            case .superscript:
                string.addAttribute(.font, value: base.withSize(base.pointSize * 0.68), range: range)
                string.addAttribute(.baselineOffset, value: base.pointSize * 0.32, range: range)
            case .noteRef:
                guard let target = span.target else { continue }
                string.addAttribute(.quoliaFootnote, value: target, range: range)
                string.addAttribute(.foregroundColor, value: style.theme.accent, range: range)
            case .byline:
                break
            }
        }
    }

    /// Title page: centered lines, the book title large and the author's name small and spaced.
    private static func styleTitlePage(_ piece: NSMutableAttributedString, block: ContentBlock, style: ReaderStyle,
                                       paragraph: NSParagraphStyle) {
        let size = style.fontSize
        let lines = (piece.string as NSString).components(separatedBy: "\n")
        var location = 0
        for (index, line) in lines.enumerated() {
            let range = NSRange(location: location, length: (line as NSString).length)
            location = NSMaxRange(range) + 1
            guard let lineStyle = paragraph.mutableCopy() as? NSMutableParagraphStyle else { continue }
            // Spacing before belongs to the first line and after to the last; lines in between stay close.
            if index > 0 { lineStyle.paragraphSpacingBefore = 0 }
            if index < lines.count - 1 { lineStyle.paragraphSpacing = size * 0.7 }
            let paragraphRange = NSRange(location: range.location, length: min(range.length + 1, piece.length - range.location))
            piece.addAttribute(.paragraphStyle, value: lineStyle, range: paragraphRange)
        }
        for span in block.spans where span.style == .byline {
            let range = NSRange(location: span.location, length: min(span.length, piece.length - span.location))
            guard range.location >= 0, range.length > 0 else { continue }
            piece.addAttributes([
                .font: style.preferences.font.uiFont(size: (size * 0.95).rounded()),
                .foregroundColor: style.theme.secondaryText,
                .kern: size * 0.08,
            ], range: range)
        }
    }

    private static func imageAttachment(_ block: ContentBlock, directory: URL?, width: CGFloat, maxHeight: CGFloat) -> NSTextAttachment? {
        guard let name = block.image, let directory else { return nil }
        let path = directory.appendingPathComponent(name).path
        let scale = UIScreen.main.scale
        guard let image = ImageDownsampler.image(atPath: path, maxPixelSize: Int(max(width, maxHeight) * scale)) else { return nil }
        let pixelSize = image.size
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        // EPUB images are authored in CSS pixels, which map to points.
        let natural = pixelSize
        let fit = min(width / natural.width, maxHeight / natural.height, 1)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: 0, width: (natural.width * fit).rounded(.down), height: (natural.height * fit).rounded(.down))
        return attachment
    }
}
