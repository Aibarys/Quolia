import Foundation
import SwiftData
import CoreGraphics

/// A highlighted passage. A note is simply a highlight with `note` text —
/// every note is attached to the passage it comments on.
@Model
final class Highlight {
    var id: UUID = UUID()
    var text: String = ""
    var colorRaw: String = HighlightColor.yellow.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var chapterIndex: Int = 0
    var chapterTitle: String = ""
    var startBlock: Int = 0
    var startOffset: Int = 0
    var endBlock: Int = 0
    var endOffset: Int = 0

    /// Original-layout PDF anchor: page index and line rects in page space.
    var pageIndex: Int = -1
    var pdfRectsData: Data?

    /// Position in the book (0...1) for sorting and display.
    var progress: Double = 0

    var note: String?
    var noteUpdatedAt: Date?
    var tags: [String] = []

    // Reading Memory (spaced repetition)
    var reviewCount: Int = 0
    var nextReviewAt: Date?
    var lastReviewedAt: Date?
    var isHiddenFromMemory: Bool = false

    var book: Book?

    init(text: String, color: HighlightColor, anchor: TextAnchor, chapterTitle: String, progress: Double) {
        self.id = UUID()
        self.text = text
        self.colorRaw = color.rawValue
        self.chapterIndex = anchor.chapter
        self.chapterTitle = chapterTitle
        self.startBlock = anchor.startBlock
        self.startOffset = anchor.startOffset
        self.endBlock = anchor.endBlock
        self.endOffset = anchor.endOffset
        self.progress = progress
        self.createdAt = .now
        self.updatedAt = .now
    }

    init(text: String, color: HighlightColor, pageIndex: Int, rects: [CGRect], progress: Double) {
        self.id = UUID()
        self.text = text
        self.colorRaw = color.rawValue
        self.pageIndex = pageIndex
        self.chapterTitle = String(localized: "Page \(pageIndex + 1)")
        self.pdfRectsData = try? JSONEncoder().encode(rects)
        self.progress = progress
        self.createdAt = .now
        self.updatedAt = .now
    }

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue; updatedAt = .now }
    }

    var anchor: TextAnchor {
        TextAnchor(chapter: chapterIndex, startBlock: startBlock, startOffset: startOffset,
                   endBlock: endBlock, endOffset: endOffset)
    }

    var isPDFAnchored: Bool { pageIndex >= 0 && pdfRectsData != nil }

    var pdfRects: [CGRect] {
        guard let pdfRectsData else { return [] }
        return (try? JSONDecoder().decode([CGRect].self, from: pdfRectsData)) ?? []
    }

    var hasNote: Bool { !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }

    var locator: ReadingLocator {
        isPDFAnchored
            ? ReadingLocator(page: max(pageIndex, 0))
            : ReadingLocator(chapter: chapterIndex, block: startBlock, offset: startOffset, page: max(pageIndex, 0))
    }

    func setNote(_ text: String?, tags newTags: [String]) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        tags = newTags
        noteUpdatedAt = .now
        updatedAt = .now
    }
}
