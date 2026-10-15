#if DEBUG
import Foundation
import SwiftData
import NaturalLanguage

/// Seeds realistic history for development and screenshots (`-seedDemoData` launch argument).
@MainActor
enum DemoData {
    static func seedIfNeeded(context: ModelContext, settings: AppSettings) async {
        let existing = (try? context.fetchCount(FetchDescriptor<Book>())) ?? 0
        guard existing == 0 else { return }
        settings.hasCompletedOnboarding = true

        let outcome = await BookImporter(context: context).importSampleBook()
        guard let book = outcome.imported.first,
              let content = try? await ContentLoader.shared.content(for: BookSource(book: book)) else { return }
        let index = ContentIndex(content: content)

        // Reading sessions over the last ~4 months.
        let calendar = Calendar.current
        var generator = SystemRandomNumberGenerator()
        for daysAgo in 0..<120 {
            let chance = daysAgo < 9 ? 1.0 : 0.55
            guard Double.random(in: 0...1, using: &generator) < chance else { continue }
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now),
                  let start = calendar.date(bySettingHour: Int.random(in: 7...22), minute: Int.random(in: 0...59), second: 0, of: day)
            else { continue }
            let minutes = daysAgo == 0 ? 14.0 : Double.random(in: 6...48, using: &generator)
            let session = ReadingSession(startedAt: start, book: book)
            session.duration = minutes * 60
            session.endedAt = start.addingTimeInterval(minutes * 60)
            session.wordsRead = Int(minutes * Double.random(in: 190...260))
            session.chaptersCompleted = minutes > 30 ? 1 : 0
            context.insert(session)
        }

        // A few highlights from earlier months.
        let samples: [(chapter: Int, block: Int, color: HighlightColor, monthsAgo: Int, note: String?, tags: [String])] = [
            (0, 2, .yellow, 6, "This is why I read in the mornings.", ["habits"]),
            (1, 3, .green, 4, nil, []),
            (2, 2, .blue, 2, "Forgetting as a feature, not a bug.", ["memory", "ideas"]),
            (3, 3, .pink, 1, nil, []),
            (4, 2, .purple, 0, "Build the library slowly.", ["library"]),
        ]
        let service = HighlightService(context: context)
        for sample in samples {
            guard let chapter = content.chapter(sample.chapter), let block = chapter.block(sample.block) else { continue }
            let text = block.text as NSString
            // Highlight the paragraph's first sentence.
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = block.text
            let firstSentence = tokenizer.tokenRange(at: block.text.startIndex)
            let end = min(NSRange(firstSentence, in: block.text).length, text.length)
            let anchor = TextAnchor(chapter: sample.chapter, startBlock: sample.block, startOffset: 0, endBlock: sample.block, endOffset: end)
            let highlight = service.createHighlight(in: book, anchor: anchor, text: text.substring(to: end),
                                                    chapterTitle: chapter.title,
                                                    progress: index.progress(of: anchor.startLocator, content: content),
                                                    color: sample.color)
            highlight.createdAt = calendar.date(byAdding: .month, value: -sample.monthsAgo, to: .now) ?? .now
            highlight.text = text.substring(to: end).trimmingCharacters(in: .whitespaces)
            highlight.nextReviewAt = sample.monthsAgo > 0 ? .now.addingTimeInterval(-3600) : nil
            if sample.note != nil || !sample.tags.isEmpty { highlight.setNote(sample.note, tags: sample.tags) }
        }

        book.status = .reading
        book.locator = ReadingLocator(chapter: 2, block: 0)
        book.progress = index.progress(of: book.locator, content: content)
        book.currentChapterTitle = content.chapter(2)?.title ?? ""
        book.lastOpenedAt = .now.addingTimeInterval(-3600)
        try? context.save()
    }
}
#endif
