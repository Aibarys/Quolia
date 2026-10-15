import Foundation
import SwiftData

/// A book in the user's library. Synced through CloudKit, so every stored
/// property has a default value and relationships are optional.
@Model
final class Book {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var formatRaw: String = BookFormat.epub.rawValue
    /// File name relative to `BookFileStore`'s root directory.
    var fileName: String = ""
    var fileSize: Int64 = 0
    @Attribute(.externalStorage) var coverImageData: Data?
    var language: String?
    var statusRaw: String = ReadingStatus.wantToRead.rawValue

    var addedAt: Date = Date()
    var lastOpenedAt: Date?
    var finishedAt: Date?

    /// Reading progress through the whole book, 0...1.
    var progress: Double = 0
    var totalWords: Int = 0
    var chapterCount: Int = 0
    var pageCount: Int = 0

    // Current reading position (flattened ReadingLocator, CloudKit friendly).
    var locChapter: Int = 0
    var locBlock: Int = 0
    var locOffset: Int = 0
    var locPage: Int = 0
    var currentChapterTitle: String = ""

    /// PDFs can be read either in their original layout or as reflowed text.
    var prefersReflow: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight]? = []

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]? = []

    @Relationship(deleteRule: .nullify, inverse: \ReadingSession.book)
    var sessions: [ReadingSession]? = []

    init(title: String, author: String, format: BookFormat, fileName: String) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.fileName = fileName
        self.addedAt = .now
    }

    var format: BookFormat {
        get { BookFormat(rawValue: formatRaw) ?? .epub }
        set { formatRaw = newValue.rawValue }
    }

    var status: ReadingStatus {
        get { ReadingStatus(rawValue: statusRaw) ?? .wantToRead }
        set {
            statusRaw = newValue.rawValue
            if newValue == .finished { finishedAt = finishedAt ?? .now } else { finishedAt = nil }
        }
    }

    var locator: ReadingLocator {
        get { ReadingLocator(chapter: locChapter, block: locBlock, offset: locOffset, page: locPage) }
        set {
            locChapter = newValue.chapter
            locBlock = newValue.block
            locOffset = newValue.offset
            locPage = newValue.page
        }
    }

    var displayAuthor: String { author.isEmpty ? String(localized: "Unknown Author") : author }

    var allHighlights: [Highlight] { highlights ?? [] }
    var allBookmarks: [Bookmark] { bookmarks ?? [] }

    /// Whether this book should be rendered with the reflowable text engine.
    var usesTextEngine: Bool { format != .pdf || prefersReflow }
}
