import Foundation
import SwiftData
import UIKit

/// Creates, edits and removes highlights, notes and bookmarks. All changes are saved
/// immediately so nothing is ever lost — and CloudKit picks them up right away.
@MainActor
struct HighlightService {
    let context: ModelContext

    nonisolated static var lastColor: HighlightColor {
        get { HighlightColor(rawValue: UserDefaults.standard.string(forKey: "quolia.lastHighlightColor") ?? "") ?? .yellow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "quolia.lastHighlightColor") }
    }

    @discardableResult
    func createHighlight(in book: Book, anchor: TextAnchor, text: String, chapterTitle: String,
                         progress: Double, color: HighlightColor = HighlightService.lastColor) -> Highlight {
        let highlight = Highlight(text: text, color: color, anchor: anchor, chapterTitle: chapterTitle, progress: progress)
        insert(highlight, into: book)
        return highlight
    }

    @discardableResult
    func createPDFHighlight(in book: Book, page: Int, rects: [CGRect], text: String, progress: Double,
                            color: HighlightColor = HighlightService.lastColor) -> Highlight {
        let highlight = Highlight(text: text, color: color, pageIndex: page, rects: rects, progress: progress)
        insert(highlight, into: book)
        return highlight
    }

    private func insert(_ highlight: Highlight, into book: Book) {
        context.insert(highlight)
        highlight.book = book
        MemoryScheduler.scheduleNew(highlight)
        save()
        Haptics.soft()
    }

    func setColor(_ color: HighlightColor, for highlight: Highlight) {
        highlight.color = color
        HighlightService.lastColor = color
        save()
        Haptics.selection()
    }

    func setNote(_ note: String?, tags: [String], for highlight: Highlight) {
        highlight.setNote(note, tags: tags)
        save()
    }

    func delete(_ highlight: Highlight) {
        context.delete(highlight)
        save()
    }

    func delete(ids: [UUID], in book: Book) {
        for highlight in book.allHighlights where ids.contains(highlight.id) {
            context.delete(highlight)
        }
        save()
        Haptics.light()
    }

    @discardableResult
    func addBookmark(to book: Book, locator: ReadingLocator, chapterTitle: String, preview: String, progress: Double) -> Bookmark {
        let bookmark = Bookmark(locator: locator, chapterTitle: chapterTitle, preview: preview, progress: progress)
        context.insert(bookmark)
        bookmark.book = book
        save()
        return bookmark
    }

    func delete(_ bookmark: Bookmark) {
        context.delete(bookmark)
        save()
    }

    func save() {
        try? context.save()
    }

    /// Text-anchored highlights grouped by chapter for the text engine.
    static func marks(for book: Book) -> [Int: [HighlightMark]] {
        var result: [Int: [HighlightMark]] = [:]
        for highlight in book.allHighlights where !highlight.isPDFAnchored {
            result[highlight.chapterIndex, default: []].append(
                HighlightMark(id: highlight.id, anchor: highlight.anchor, color: highlight.color, hasNote: highlight.hasNote)
            )
        }
        return result
    }

    static func shareText(for text: String, book: Book?) -> String {
        guard let book else { return "“\(text)”" }
        return shareText(for: text, bookTitle: book.title, author: book.author)
    }

    static func shareText(for text: String, bookTitle: String, author: String) -> String {
        "“\(text)”\n— \(author.isEmpty ? bookTitle : "\(author), \(bookTitle)")"
    }
}
