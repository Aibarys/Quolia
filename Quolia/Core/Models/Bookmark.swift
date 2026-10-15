import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var chapterIndex: Int = 0
    var chapterTitle: String = ""
    var block: Int = 0
    var offset: Int = 0
    var pageIndex: Int = 0
    /// A short excerpt of the text at the bookmarked position.
    var preview: String = ""
    var progress: Double = 0
    var book: Book?

    init(locator: ReadingLocator, chapterTitle: String, preview: String, progress: Double) {
        self.id = UUID()
        self.createdAt = .now
        self.chapterIndex = locator.chapter
        self.block = locator.block
        self.offset = locator.offset
        self.pageIndex = locator.page
        self.chapterTitle = chapterTitle
        self.preview = preview
        self.progress = progress
    }

    var locator: ReadingLocator {
        ReadingLocator(chapter: chapterIndex, block: block, offset: offset, page: pageIndex)
    }
}

@Model
final class ReadingSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    /// Active reading time in seconds (idle time excluded).
    var duration: Double = 0
    var wordsRead: Int = 0
    var chaptersCompleted: Int = 0
    var highlightsCreated: Int = 0
    var notesCreated: Int = 0
    var isFlow: Bool = false
    var book: Book?

    init(startedAt: Date, book: Book?) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = startedAt
        self.book = book
    }

    var pagesRead: Int { Int((Double(wordsRead) / ReadingMath.wordsPerPage).rounded()) }
}

@Model
final class SavedWord {
    var id: UUID = UUID()
    var word: String = ""
    var translation: String?
    var definition: String?
    var context: String?
    var bookTitle: String?
    var language: String?
    var createdAt: Date = Date()

    init(word: String, translation: String? = nil, definition: String? = nil,
         context: String? = nil, bookTitle: String? = nil, language: String? = nil) {
        self.id = UUID()
        self.word = word
        self.translation = translation
        self.definition = definition
        self.context = context
        self.bookTitle = bookTitle
        self.language = language
        self.createdAt = .now
    }
}

enum ReadingMath {
    /// Normalized "page" used for stats and locations, independent of font size.
    static let wordsPerPage: Double = 250
    static let defaultWPM: Double = 230

    static func pages(forWords words: Int) -> Int {
        Int((Double(words) / wordsPerPage).rounded(.up))
    }
}
