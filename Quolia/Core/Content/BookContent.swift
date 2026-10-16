import Foundation

/// Format-independent representation of a reflowable book.
/// EPUB, FB2, TXT and (reflowed) PDF engines all produce this model, so the reader,
/// highlights, focus mode, search, stats and AI only ever deal with one shape.
struct BookContent: Codable, Sendable {
    static let schemaVersion = 4

    var title: String
    var author: String
    var language: String?
    var chapters: [Chapter]
    /// Notes that note-reference spans point to, keyed by `InlineSpan.target`.
    var footnotes: [String: Footnote] = [:]

    var totalWords: Int { chapters.reduce(0) { $0 + $1.wordCount } }

    func chapter(_ index: Int) -> Chapter? {
        chapters.indices.contains(index) ? chapters[index] : nil
    }

    /// First block that comes from `page` (or later) in PDF-derived content.
    func locator(forPage page: Int) -> ReadingLocator {
        for chapter in chapters {
            if let block = chapter.blocks.firstIndex(where: { ($0.page ?? 0) >= page }) {
                return ReadingLocator(chapter: chapter.id, block: block, offset: 0, page: page)
            }
        }
        return ReadingLocator(page: page)
    }
}

struct Chapter: Codable, Sendable, Identifiable, Hashable {
    var id: Int
    var title: String
    var blocks: [ContentBlock]
    /// For PDFs: first source page of the chapter.
    var sourcePage: Int?

    var wordCount: Int { blocks.reduce(0) { $0 + $1.wordCount } }

    func block(_ index: Int) -> ContentBlock? {
        blocks.indices.contains(index) ? blocks[index] : nil
    }
}

struct ContentBlock: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable {
        case paragraph
        case heading
        case quote
        case listItem
        case preformatted
        case caption
        case image
        case separator
        /// Title page lines (author and book title); `.byline` spans mark the author.
        case title
        /// Removed during import (e.g. a download site's ad). Kept as an empty placeholder
        /// so later block indices, and the highlights anchored to them, stay stable.
        case omitted
    }

    var kind: Kind
    var text: String
    /// Heading level (1...6) for `.heading`.
    var level: Int = 0
    var spans: [InlineSpan] = []
    /// Image file name inside the book's content cache directory.
    var image: String?
    /// Source page for PDF-derived blocks.
    var page: Int?
    var wordCount: Int

    init(kind: Kind, text: String, level: Int = 0, spans: [InlineSpan] = [], image: String? = nil, page: Int? = nil) {
        self.kind = kind
        self.text = text
        self.level = level
        self.spans = spans
        self.image = image
        self.page = page
        self.wordCount = TextStats.wordCount(text)
    }

    var isTextual: Bool { kind != .image && kind != .separator && kind != .omitted }

    /// An empty placeholder for a block removed during import.
    static var omitted: ContentBlock { ContentBlock(kind: .omitted, text: "") }
}

struct InlineSpan: Codable, Sendable, Hashable {
    enum Style: String, Codable, Sendable {
        case italic
        case bold
        case code
        case superscript
        /// A link to a footnote; `target` is its key in `BookContent.footnotes`.
        case noteRef
        /// The author's name on a title page.
        case byline
    }

    /// UTF-16 range within the block's text.
    var location: Int
    var length: Int
    var style: Style
    var target: String?

    var range: NSRange { NSRange(location: location, length: length) }
}

/// The text of a footnote, shown in place when its reference is tapped.
struct Footnote: Codable, Sendable, Hashable {
    /// The reference mark as printed in the text ("1", "*").
    var label: String
    var text: String
}

enum TextStats {
    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }
}
