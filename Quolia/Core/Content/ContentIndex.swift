import Foundation

/// Precomputed word offsets so position ↔ progress conversions are O(log n).
struct ContentIndex: Sendable {
    let totalWords: Int
    /// Words before each chapter.
    let chapterStart: [Int]
    /// Words before each block, per chapter.
    let blockStart: [[Int]]
    private let chapterWords: [Int]

    init(content: BookContent) {
        var chapterStart: [Int] = []
        var blockStart: [[Int]] = []
        var chapterWords: [Int] = []
        var running = 0
        for chapter in content.chapters {
            chapterStart.append(running)
            var inChapter = 0
            var starts: [Int] = []
            starts.reserveCapacity(chapter.blocks.count)
            for block in chapter.blocks {
                starts.append(inChapter)
                inChapter += block.wordCount
            }
            blockStart.append(starts)
            chapterWords.append(inChapter)
            running += inChapter
        }
        self.totalWords = running
        self.chapterStart = chapterStart
        self.blockStart = blockStart
        self.chapterWords = chapterWords
    }

    func words(inChapter chapter: Int) -> Int {
        chapterWords.indices.contains(chapter) ? chapterWords[chapter] : 0
    }

    /// Number of words that come before `locator`.
    func wordsBefore(_ locator: ReadingLocator, content: BookContent) -> Int {
        guard chapterStart.indices.contains(locator.chapter) else {
            return locator.chapter >= chapterStart.count ? totalWords : 0
        }
        var words = chapterStart[locator.chapter]
        let starts = blockStart[locator.chapter]
        guard starts.indices.contains(locator.block) else {
            return words + (locator.block >= starts.count ? chapterWords[locator.chapter] : 0)
        }
        words += starts[locator.block]
        if let block = content.chapters[locator.chapter].block(locator.block) {
            let length = max((block.text as NSString).length, 1)
            let fraction = min(max(Double(locator.offset) / Double(length), 0), 1)
            words += Int(Double(block.wordCount) * fraction)
        }
        return words
    }

    func progress(of locator: ReadingLocator, content: BookContent) -> Double {
        guard totalWords > 0 else {
            let count = max(content.chapters.count, 1)
            return min(Double(locator.chapter) / Double(count), 1)
        }
        return min(max(Double(wordsBefore(locator, content: content)) / Double(totalWords), 0), 1)
    }

    /// Locator at the start of the block containing the given progress fraction.
    func locator(forProgress progress: Double, content: BookContent) -> ReadingLocator {
        guard totalWords > 0, !content.chapters.isEmpty else { return .start }
        let target = Int(min(max(progress, 0), 1) * Double(totalWords))
        let chapter = max((chapterStart.lastIndex { $0 <= target }) ?? 0, 0)
        let local = target - chapterStart[chapter]
        let starts = blockStart[chapter]
        let block = max((starts.lastIndex { $0 <= local }) ?? 0, 0)
        return ReadingLocator(chapter: chapter, block: block, offset: 0)
    }

    func remainingWords(inChapterFrom locator: ReadingLocator, content: BookContent) -> Int {
        guard chapterStart.indices.contains(locator.chapter) else { return 0 }
        let chapterEnd = chapterStart[locator.chapter] + chapterWords[locator.chapter]
        return max(chapterEnd - wordsBefore(locator, content: content), 0)
    }
}
