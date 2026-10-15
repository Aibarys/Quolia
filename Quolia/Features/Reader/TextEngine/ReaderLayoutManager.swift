import UIKit

/// Draws highlights as soft rounded marks hugging the glyphs. Highlights are
/// display-only state: changing them never invalidates layout or scroll position.
final class ReaderLayoutManager: NSLayoutManager {
    struct Mark: Equatable {
        let range: NSRange
        let color: UIColor
    }

    var marks: [Mark] = [] {
        didSet {
            guard marks != oldValue, let length = textStorage?.length else { return }
            invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length))
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !marks.isEmpty, let storage = textStorage, UIGraphicsGetCurrentContext() != nil else { return }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for mark in marks {
            let characters = NSIntersectionRange(mark.range, visible)
            guard characters.length > 0 else { continue }
            let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
            mark.color.setFill()
            enumerateLineFragments(forGlyphRange: glyphs) { _, _, container, lineGlyphs, _ in
                let segment = NSIntersectionRange(lineGlyphs, glyphs)
                guard segment.length > 0 else { return }
                var rect = self.boundingRect(forGlyphRange: segment, in: container)
                let character = self.characterIndexForGlyph(at: segment.location)
                let font = (character < storage.length ? storage.attribute(.font, at: character, effectiveRange: nil) as? UIFont : nil)
                    ?? UIFont.preferredFont(forTextStyle: .body)
                // Line/paragraph spacing sits below the glyphs; keep only the glyph band.
                rect.size.height = min(rect.height, font.lineHeight + 2)
                rect = rect.insetBy(dx: -2, dy: -1).offsetBy(dx: origin.x, dy: origin.y)
                UIBezierPath(roundedRect: rect, cornerRadius: min(4, rect.height / 4)).fill()
            }
        }
    }
}

/// Builds a TextKit 1 stack (storage → layout manager → container) for a text view.
enum TextStack {
    static func make(attributed: NSAttributedString, containerSize: CGSize) -> (NSTextStorage, ReaderLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = ReaderLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: containerSize)
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        return (storage, layoutManager, container)
    }
}

/// Splits a rendered chapter into pages using a single layout manager with one
/// text container per page, so on-screen layout matches pagination exactly.
final class ChapterLayout {
    let rendered: RenderedChapter
    let pageSize: CGSize
    let storage: NSTextStorage
    let layoutManager: ReaderLayoutManager
    private(set) var containers: [NSTextContainer] = []
    private(set) var pageRanges: [NSRange] = []

    var chapterIndex: Int { rendered.index }
    var pageCount: Int { max(pageRanges.count, 1) }

    init(rendered: RenderedChapter, pageSize: CGSize) {
        self.rendered = rendered
        self.pageSize = pageSize
        storage = NSTextStorage(attributedString: rendered.attributed)
        layoutManager = ReaderLayoutManager()
        layoutManager.usesFontLeading = true
        storage.addLayoutManager(layoutManager)
        paginate()
    }

    private func paginate() {
        var glyphIndex = 0
        let totalGlyphs = layoutManager.numberOfGlyphs
        while glyphIndex < totalGlyphs || containers.isEmpty {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let glyphRange = layoutManager.glyphRange(for: container)
            containers.append(container)
            if glyphRange.length == 0 {
                if containers.count > 1 {
                    // Nothing fits (e.g. an oversized attachment): stop to avoid looping forever.
                    layoutManager.removeTextContainer(at: containers.count - 1)
                    containers.removeLast()
                } else {
                    pageRanges.append(NSRange(location: 0, length: storage.length))
                }
                break
            }
            pageRanges.append(layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil))
            glyphIndex = NSMaxRange(glyphRange)
            if containers.count > 5_000 { break }
        }
    }

    func pageIndex(containing characterIndex: Int) -> Int {
        guard !pageRanges.isEmpty else { return 0 }
        for (index, range) in pageRanges.enumerated() where characterIndex < NSMaxRange(range) {
            return index
        }
        return pageRanges.count - 1
    }

    func range(ofPage page: Int) -> NSRange {
        pageRanges.indices.contains(page) ? pageRanges[page] : NSRange(location: 0, length: 0)
    }

    /// A standalone TextKit stack showing exactly one page. UIKit only supports text selection
    /// in a text view bound to the first container of its layout manager, so each page lays out
    /// its own copy of the text: from the page start to the end of the paragraph it breaks in,
    /// which keeps line breaks and justification identical to the shared layout.
    /// Returns nil if the result doesn't match the pagination; the page then uses the shared container.
    func makePageStack(_ page: Int) -> PageStack? {
        let pageRange = range(ofPage: page)
        guard pageRange.length > 0 else { return nil }
        let string = storage.string as NSString
        let lastCharacter = NSRange(location: NSMaxRange(pageRange) - 1, length: 0)
        let end = NSMaxRange(string.paragraphRange(for: lastCharacter))
        let text = NSMutableAttributedString(attributedString:
            storage.attributedSubstring(from: NSRange(location: pageRange.location, length: end - pageRange.location)))

        // A page that starts mid-paragraph continues it: no first-line indent or space before.
        if pageRange.location > 0, !Self.isParagraphSeparator(string.character(at: pageRange.location - 1)) {
            let firstParagraph = (text.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            if let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
               let continued = style.mutableCopy() as? NSMutableParagraphStyle {
                continued.firstLineHeadIndent = continued.headIndent
                continued.paragraphSpacingBefore = 0
                text.addAttribute(.paragraphStyle, value: continued, range: firstParagraph)
            }
        }

        let (pageStorage, pageLayoutManager, container) = TextStack.make(attributed: text, containerSize: pageSize)
        let shown = pageLayoutManager.characterRange(forGlyphRange: pageLayoutManager.glyphRange(for: container),
                                                     actualGlyphRange: nil)
        guard shown.location == 0, shown.length == pageRange.length else { return nil }
        return PageStack(storage: pageStorage, layoutManager: pageLayoutManager, container: container,
                         characterOffset: pageRange.location)
    }

    private static func isParagraphSeparator(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2029 || character == 0x85
    }
}

/// The TextKit stack behind one page's text view. Character `i` of `storage` is character
/// `i + characterOffset` of the chapter.
struct PageStack {
    /// TextKit 1 ownership runs storage → layout manager → container, so the storage must be retained.
    let storage: NSTextStorage
    let layoutManager: ReaderLayoutManager
    let container: NSTextContainer
    let characterOffset: Int
}
