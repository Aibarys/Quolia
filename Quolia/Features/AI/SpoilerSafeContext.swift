import Foundation
import NaturalLanguage

/// Builds the only book text the AI is ever allowed to see: everything up to
/// the reader's frontier, never a single character beyond it.
///
/// When the read portion is larger than the provider's budget, the context is
/// composed of (1) an outline of chapters read so far, (2) the earlier passages
/// most relevant to the question, and (3) the most recent text, which ends
/// exactly at the reader's position.
enum SpoilerSafeContext {
    struct Passage {
        let chapter: Int
        let chapterTitle: String
        let text: String
    }

    /// All text the reader has seen, in order, cut exactly at `frontier`.
    static func readPassages(content: BookContent, frontier: ReadingLocator) -> [Passage] {
        var passages: [Passage] = []
        for chapter in content.chapters where chapter.id <= frontier.chapter {
            for (index, block) in chapter.blocks.enumerated() where block.isTextual {
                if chapter.id == frontier.chapter {
                    if index > frontier.block { break }
                    if index == frontier.block {
                        let text = block.text as NSString
                        let cut = min(max(frontier.offset, 0), text.length)
                        if cut > 0 { passages.append(Passage(chapter: chapter.id, chapterTitle: chapter.title, text: text.substring(to: cut))) }
                        break
                    }
                }
                passages.append(Passage(chapter: chapter.id, chapterTitle: chapter.title, text: block.text))
            }
        }
        return passages
    }

    static func build(content: BookContent, frontier: ReadingLocator, progress: Double,
                      question: String?, focus: String?, budget: Int) -> String {
        let passages = readPassages(content: content, frontier: frontier)
        let chapterTitle = content.chapter(frontier.chapter)?.title ?? ""
        var header = """
        BOOK: \(content.title)\(content.author.isEmpty ? "" : " — \(content.author)")
        READER POSITION: \(chapterTitle.isEmpty ? "" : "“\(chapterTitle)”, ")about \(Int((progress * 100).rounded()))% through the book.
        The text below ends exactly where the reader stopped. Nothing after this point has been read.

        """

        let total = passages.reduce(0) { $0 + $1.text.count + 1 }
        if total <= budget {
            header += render(passages, includeHeadings: true)
            return header
        }

        // Outline of chapters read so far.
        var seen = Set<Int>()
        let outline = passages.compactMap { passage -> String? in
            guard seen.insert(passage.chapter).inserted else { return nil }
            return "– \(passage.chapterTitle)"
        }.joined(separator: "\n")
        let outlineText = "CHAPTERS READ SO FAR:\n\(outline)\n\n"

        let remaining = max(budget - outlineText.count, budget / 2)
        let recentBudget = Int(Double(remaining) * 0.55)
        let relevantBudget = remaining - recentBudget

        // Most recent text, walking backwards from the frontier.
        var recent: [Passage] = []
        var used = 0
        var cursor = passages.count - 1
        while cursor >= 0 {
            let passage = passages[cursor]
            if used + passage.text.count > recentBudget {
                if recent.isEmpty {
                    recent.insert(Passage(chapter: passage.chapter, chapterTitle: passage.chapterTitle,
                                          text: "…" + String(passage.text.suffix(recentBudget))), at: 0)
                }
                break
            }
            recent.insert(passage, at: 0)
            used += passage.text.count + 1
            cursor -= 1
        }

        // Relevant earlier passages, scored against the question and focus text.
        let earlier = Array(passages.prefix(max(cursor, 0)))
        let terms = keywords(in: [question, focus].compactMap { $0 }.joined(separator: " "))
        var relevant: [(index: Int, passage: Passage)] = []
        if !terms.isEmpty, relevantBudget > 200 {
            let scored = earlier.enumerated().map { ($0.offset, $0.element, score($0.element.text, terms: terms)) }
                .filter { $0.2 > 0 }
                .sorted { $0.2 > $1.2 }
            var relevantUsed = 0
            for (index, passage, _) in scored {
                let text = passage.text.count > 900 ? String(passage.text.prefix(900)) + "…" : passage.text
                if relevantUsed + text.count > relevantBudget { continue }
                relevant.append((index, Passage(chapter: passage.chapter, chapterTitle: passage.chapterTitle, text: text)))
                relevantUsed += text.count + 1
            }
            relevant.sort { $0.index < $1.index }
        } else if relevantBudget > 200 {
            // No question: sample the openings of earlier chapters for orientation.
            var relevantUsed = 0
            var sampled = Set<Int>()
            for (index, passage) in earlier.enumerated() where !sampled.contains(passage.chapter) {
                let text = String(passage.text.prefix(500))
                if relevantUsed + text.count > relevantBudget { break }
                sampled.insert(passage.chapter)
                relevant.append((index, Passage(chapter: passage.chapter, chapterTitle: passage.chapterTitle, text: text)))
                relevantUsed += text.count + 1
            }
        }

        header += outlineText
        if !relevant.isEmpty {
            header += "EARLIER PASSAGES (excerpts):\n"
            header += relevant.map { "[\($0.passage.chapterTitle)] \($0.passage.text)" }.joined(separator: "\n\n")
            header += "\n\n"
        }
        header += "MOST RECENT TEXT (ends at the reader's position):\n"
        header += render(recent, includeHeadings: true)
        return header
    }

    private static func render(_ passages: [Passage], includeHeadings: Bool) -> String {
        var output = ""
        var lastChapter: Int?
        for passage in passages {
            if includeHeadings, passage.chapter != lastChapter {
                output += "\n## \(passage.chapterTitle)\n"
                lastChapter = passage.chapter
            }
            output += passage.text + "\n"
        }
        return output
    }

    // MARK: - Keyword scoring

    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "for", "with", "is", "are", "was", "were",
        "be", "been", "it", "this", "that", "these", "those", "what", "who", "whom", "why", "how", "when", "where",
        "does", "did", "do", "here", "there", "author", "mean", "means", "about", "so", "far", "me", "i", "you", "he",
        "she", "they", "his", "her", "their", "its", "as", "by", "from", "has", "have", "had", "not", "no", "can",
        "и", "в", "на", "что", "это", "как", "не", "кто", "о", "об", "по", "из", "за", "к", "у", "же", "ли", "автор",
    ]

    static func keywords(in text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result = Set<String>()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].lowercased()
            if word.count > 2, !stopwords.contains(word) { result.insert(word) }
            return true
        }
        return result
    }

    private static func score(_ text: String, terms: Set<String>) -> Double {
        let lower = text.lowercased()
        var score = 0.0
        for term in terms {
            var count = 0
            var range = lower.startIndex..<lower.endIndex
            while let found = lower.range(of: term, range: range) {
                count += 1
                range = found.upperBound..<lower.endIndex
            }
            if count > 0 { score += 1 + log(Double(count)) }
        }
        return score / sqrt(Double(max(text.count, 200)) / 200)
    }
}
