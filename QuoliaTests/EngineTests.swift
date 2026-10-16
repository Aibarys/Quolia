import XCTest
@testable import Quolia

final class EngineTests: XCTestCase {
    private var sampleURL: URL {
        get throws {
            try XCTUnwrap(Bundle.main.url(forResource: "On Reading Slowly", withExtension: "epub"))
        }
    }

    func testZipReadsStoredAndDeflatedEntries() throws {
        let archive = try ZipArchive(url: try sampleURL)
        XCTAssertEqual(try archive.string(for: "mimetype"), "application/epub+zip")
        let opf = try archive.string(for: "OEBPS/content.opf")
        XCTAssertTrue(opf.contains("<dc:title>On Reading Slowly</dc:title>"))
        XCTAssertGreaterThan(try archive.data(for: "OEBPS/images/cover.jpg").count, 10_000)
    }

    func testEPUBParserBuildsChaptersFromTOC() throws {
        let images = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = try EPUBParser(url: try sampleURL, imagesDirectory: images).parse()
        let content = result.content
        XCTAssertEqual(content.title, "On Reading Slowly")
        XCTAssertEqual(content.author, "Quolia Editions")
        XCTAssertEqual(content.chapters.map(\.title), ["The Quiet Hour", "Marginalia", "The Art of Forgetting", "Rereading", "A Library of One"])
        XCTAssertNotNil(result.coverData)
        let first = content.chapters[0]
        XCTAssertEqual(first.blocks.first?.kind, .heading)
        XCTAssertTrue(first.blocks.contains { $0.kind == .separator })
        XCTAssertTrue(first.blocks.contains { !$0.spans.isEmpty && $0.spans[0].style == .italic })
        XCTAssertGreaterThan(content.totalWords, 1_200)
    }

    func testMarkupParserToleratesHTMLEntitiesAndUnclosedTags() {
        let root = MarkupParser.parse("<html><body><p>One&nbsp;two &mdash; three<br>four &amp; &#233;&#x41;</p><p>Unclosed<p>Next</body></html>")
        let blocks = HTMLContentExtractor(resolveImage: { _ in nil }).extract(from: root)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].text, "One\u{00A0}two — three\nfour & éA")
        XCTAssertEqual(blocks[1].text, "Unclosed")
        XCTAssertEqual(blocks[2].text, "Next")
    }

    func testInlineSpansSurviveWhitespaceCollapsing() {
        let root = MarkupParser.parse("<p>  A <em>quiet</em>   <strong>hour</strong>  </p>")
        let block = HTMLContentExtractor(resolveImage: { _ in nil }).extract(from: root)[0]
        XCTAssertEqual(block.text, "A quiet hour")
        let text = block.text as NSString
        XCTAssertEqual(text.substring(with: block.spans[0].range), "quiet")
        XCTAssertEqual(text.substring(with: block.spans[1].range), "hour")
    }

    func testPlainTextDetectsChapters() {
        let text = "Chapter 1\n\nIt began quietly.\nStill the same paragraph.\n\nSecond paragraph.\n\nChapter 2\n\nAnother part begins."
        let content = PlainTextParser.parse(text: text, title: "T", author: "A")
        XCTAssertEqual(content.chapters.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(content.chapters[0].blocks[1].text, "It began quietly. Still the same paragraph.")
    }

    func testPlainTextDecodesWindows1251() throws {
        let original = "Глава 1\n\nЖил-был читатель, который любил медленные книги и долгие вечера."
        let data = try XCTUnwrap(original.data(using: .windowsCP1251))
        XCTAssertEqual(try PlainTextParser.decode(data), original)
    }

    func testTitleAndAuthorFromFileName() {
        XCTAssertEqual(PlainTextParser.titleAndAuthor(fromFileName: "Leo Tolstoy - War and Peace").0, "War and Peace")
        XCTAssertEqual(PlainTextParser.titleAndAuthor(fromFileName: "Leo Tolstoy - War and Peace").1, "Leo Tolstoy")
    }

    func testPDFParagraphReconstruction() {
        let text = "This is a line that wraps\nonto the next line and ends.\nA short one.\n42\ninfor-\nmation flows."
        let paragraphs = PDFBookParser.paragraphs(from: text)
        XCTAssertEqual(paragraphs.first, "This is a line that wraps onto the next line and ends. A short one.")
        XCTAssertTrue(paragraphs.last?.contains("information flows.") ?? false)
        XCTAssertFalse(paragraphs.joined().contains("42"))
    }

    func testEPUBPathResolution() {
        XCTAssertEqual(EPUBParser.resolve("../images/a%20b.jpg#x", relativeTo: "OEBPS/text"), "OEBPS/images/a b.jpg")
        XCTAssertEqual(EPUBParser.resolve("ch1.xhtml", relativeTo: ""), "ch1.xhtml")
    }
}

final class PositionTests: XCTestCase {
    private func makeContent() -> BookContent {
        BookContent(title: "B", author: "A", language: "en", chapters: [
            Chapter(id: 0, title: "One", blocks: [ContentBlock(kind: .heading, text: "One", level: 1),
                                                  ContentBlock(kind: .paragraph, text: "alpha beta gamma delta"),
                                                  ContentBlock(kind: .paragraph, text: "epsilon zeta")]),
            Chapter(id: 1, title: "Two", blocks: [ContentBlock(kind: .paragraph, text: "eta theta iota kappa"),
                                                  ContentBlock(kind: .paragraph, text: "SECRET ENDING lambda mu")]),
        ])
    }

    func testProgressRoundTrip() {
        let content = makeContent()
        let index = ContentIndex(content: content)
        XCTAssertEqual(index.totalWords, 15)
        XCTAssertEqual(index.progress(of: .start, content: content), 0)
        let locator = ReadingLocator(chapter: 1, block: 0)
        XCTAssertEqual(index.wordsBefore(locator, content: content), 7)
        XCTAssertEqual(index.locator(forProgress: index.progress(of: locator, content: content), content: content), locator)
        XCTAssertEqual(index.remainingWords(inChapterFrom: ReadingLocator(chapter: 0, block: 2), content: content), 2)
    }

    @MainActor
    func testRenderedChapterAnchorsAreStable() {
        let content = makeContent()
        let style = ReaderStyle(preferences: ReaderPreferences(), theme: .light)
        let rendered = ChapterRenderer.render(content.chapters[0], style: style, imagesDirectory: nil, contentWidth: 300, maxImageHeight: 400)
        let range = (rendered.attributed.string as NSString).range(of: "beta gamma")
        let anchor = rendered.anchor(for: range)
        XCTAssertEqual(anchor, TextAnchor(chapter: 0, startBlock: 1, startOffset: 6, endBlock: 1, endOffset: 16))
        XCTAssertEqual(rendered.range(for: anchor), range)

        // A selection ending exactly at a paragraph boundary stays in the earlier block.
        let whole = rendered.blockRanges[1]
        XCTAssertEqual(rendered.anchor(for: whole).endBlock, 1)
    }

    /// Each page gets its own TextKit stack (so text selection works on every page); its layout
    /// must show exactly the page's characters, or the page silently falls back to the shared one.
    @MainActor
    func testEveryPageHasItsOwnMatchingTextStack() {
        let words = ["тишина", "страница", "медленно", "возвращаться", "внимание", "читатель", "reading", "a", "и", "—"]
        var blocks: [ContentBlock] = [ContentBlock(kind: .heading, text: "Глава первая", level: 1)]
        for index in 0..<60 {
            let length = 12 + (index * 37) % 140
            let text = (0..<length).map { words[($0 * 7 + index) % words.count] }.joined(separator: " ")
            switch index % 9 {
            case 3: blocks.append(ContentBlock(kind: .quote, text: text))
            case 5: blocks.append(ContentBlock(kind: .quote, text: "Строка стиха,\nещё одна строка,\nи третья."))
            case 7: blocks.append(ContentBlock(kind: .heading, text: "Часть \(index)", level: 2))
            default: blocks.append(ContentBlock(kind: .paragraph, text: text + "."))
            }
        }
        let chapter = Chapter(id: 0, title: "Глава первая", blocks: blocks)

        for (font, size, alignment) in [(ReaderFont.newYork, 19.0, TextAlignmentOption.leading),
                                        (.sanFrancisco, 15, .justified), (.georgia, 24, .justified)] {
            var preferences = ReaderPreferences()
            preferences.font = font
            preferences.fontSize = size
            preferences.alignment = alignment
            let style = ReaderStyle(preferences: preferences, theme: .light)
            let rendered = ChapterRenderer.render(chapter, style: style, imagesDirectory: nil, contentWidth: 340, maxImageHeight: 500)
            let layout = ChapterLayout(rendered: rendered, pageSize: CGSize(width: 340, height: 620))
            XCTAssertGreaterThan(layout.pageCount, 3)
            for page in 0..<layout.pageCount {
                let stack = layout.makePageStack(page)
                XCTAssertNotNil(stack, "\(font) \(size) \(alignment): page \(page) has no matching stack")
                XCTAssertEqual(stack?.characterOffset, layout.range(ofPage: page).location)
            }
        }
    }

    func testHTMLNoteReferencesBecomeFootnotes() throws {
        let html = """
        <html><body><p>Text<a epub:type="noteref" href="#fn1">1</a>, and <a href="#sec">see the section</a>.</p>
        <p>More<a href="#fn2"><sup>2</sup></a>.</p>
        <aside epub:type="footnote" id="fn1"><p><a href="#r1">1</a> First note. ↩︎</p></aside>
        <p><a id="fn2" href="#r2">2.</a> Second note.</p><h2 id="sec">Section</h2></body></html>
        """
        let root = MarkupParser.parse(html)
        var ids: [String: MarkupNode] = [:]
        var stack = [root]
        while let node = stack.popLast() {
            for element in node.elements {
                if let id = element["id"] { ids[id] = element }
                stack.append(element)
            }
        }
        let resolver = FootnoteResolver { ids[$0] }
        let extractor = HTMLContentExtractor(resolveImage: { _ in nil }, resolveNote: { href, label, explicit in
            resolver.resolve(key: String(href.dropFirst()), label: label, explicit: explicit)
        })
        let blocks = extractor.extract(from: root)
        XCTAssertEqual(blocks[0].spans.filter { $0.style == .noteRef }.map(\.target), ["fn1"])
        XCTAssertEqual(blocks[1].spans.filter { $0.style == .noteRef }.map(\.target), ["fn2"])
        XCTAssertEqual(resolver.footnotes["fn1"]?.text, "First note.")
        XCTAssertEqual(resolver.footnotes["fn2"]?.text, "Second note.")
        XCTAssertNil(resolver.footnotes["sec"])
    }

    @MainActor
    func testOmittedBlocksKeepBlockIndicesStable() {
        let chapter = Chapter(id: 0, title: "C", blocks: [
            .omitted, ContentBlock(kind: .paragraph, text: "alpha"), .omitted, ContentBlock(kind: .paragraph, text: "beta"), .omitted,
        ])
        let style = ReaderStyle(preferences: ReaderPreferences(), theme: .light)
        let rendered = ChapterRenderer.render(chapter, style: style, imagesDirectory: nil, contentWidth: 300, maxImageHeight: 400)
        XCTAssertEqual(rendered.attributed.string, "alpha\nbeta")
        XCTAssertEqual(rendered.blockRanges.count, 5)
        let string = rendered.attributed.string as NSString
        XCTAssertEqual(string.substring(with: rendered.blockRanges[1]), "alpha")
        XCTAssertEqual(string.substring(with: rendered.blockRanges[3]), "beta")
        XCTAssertEqual(rendered.blockIndex(containing: 0), 1)
        XCTAssertEqual(rendered.blockIndex(containing: rendered.blockRanges[3].location), 3)
        XCTAssertEqual(rendered.blockIndex(containing: 5), 1, "the newline after alpha belongs to alpha")
    }

    @MainActor
    func testRendererMarksFootnoteReferences() {
        let block = ContentBlock(kind: .paragraph, text: "Word1.", spans: [InlineSpan(location: 4, length: 1, style: .noteRef, target: "n1")])
        let style = ReaderStyle(preferences: ReaderPreferences(), theme: .light)
        let rendered = ChapterRenderer.render(Chapter(id: 0, title: "C", blocks: [block]), style: style, imagesDirectory: nil,
                                              contentWidth: 300, maxImageHeight: 400)
        XCTAssertEqual(rendered.attributed.attribute(.quoliaFootnote, at: 4, effectiveRange: nil) as? String, "n1")
        XCTAssertNil(rendered.attributed.attribute(.quoliaFootnote, at: 3, effectiveRange: nil))
    }

    func testSameBookIdentityIgnoresNameOrderAndPunctuation() {
        XCTAssertEqual(BookImporter.identity(title: "Шум и ярость", author: "Уильям Фолкнер"),
                       BookImporter.identity(title: "Шум и ярость.", author: "Фолкнер Уильям"))
        XCTAssertEqual(BookImporter.identity(title: "Ёлка", author: ""), BookImporter.identity(title: "елка", author: ""))
        XCTAssertNotEqual(BookImporter.identity(title: "Шум и ярость", author: "Уильям Фолкнер"),
                          BookImporter.identity(title: "Шум и ярость", author: "Другой Автор"))
        XCTAssertNil(BookImporter.identity(title: "Untitled", author: ""))
    }

    func testSpoilerSafeContextNeverPassesFrontier() {
        let content = makeContent()
        let frontier = ReadingLocator(chapter: 1, block: 0, offset: 9) // "eta theta"
        let context = SpoilerSafeContext.build(content: content, frontier: frontier, progress: 0.5,
                                               question: "What is the ending?", focus: nil, budget: 10_000)
        XCTAssertTrue(context.contains("eta theta"))
        XCTAssertFalse(context.contains("iota"))
        XCTAssertFalse(context.contains("SECRET"))

        // Even when the budget forces excerpting, nothing beyond the frontier appears.
        let tight = SpoilerSafeContext.build(content: content, frontier: frontier, progress: 0.5,
                                             question: "SECRET ENDING", focus: nil, budget: 40)
        XCTAssertFalse(tight.contains("SECRET"))
        XCTAssertFalse(tight.contains("kappa"))
    }
}

@MainActor
final class MemoryAndStatsTests: XCTestCase {
    func testMemoryIntervalsGrowAndQueuePrefersDue() {
        let due = Highlight(text: "Due", color: .yellow, anchor: TextAnchor(chapter: 0, startBlock: 0, startOffset: 0, endBlock: 0, endOffset: 3), chapterTitle: "", progress: 0)
        let later = Highlight(text: "Later", color: .blue, anchor: TextAnchor(chapter: 0, startBlock: 0, startOffset: 0, endBlock: 0, endOffset: 3), chapterTitle: "", progress: 0)
        let book = Book(title: "B", author: "A", format: .epub, fileName: "")
        due.book = book
        later.book = book
        due.nextReviewAt = .now.addingTimeInterval(-60)
        later.nextReviewAt = .now.addingTimeInterval(86_400 * 5)
        XCTAssertEqual(MemoryScheduler.queue(from: [later, due]).map(\.text), ["Due"])

        let now = Date()
        MemoryScheduler.markSeen(due, now: now, jitter: 1)
        let first = due.nextReviewAt!.timeIntervalSince(now)
        MemoryScheduler.markSeen(due, now: now, jitter: 1)
        XCTAssertGreaterThan(due.nextReviewAt!.timeIntervalSince(now), first)
    }

    func testStreakCountsConsecutiveDaysEndingYesterdayOrToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9))!
        func session(daysAgo: Int, minutes: Double) -> ReadingSession {
            let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
            let s = ReadingSession(startedAt: start, book: nil)
            s.duration = minutes * 60
            s.wordsRead = Int(minutes * 250)
            return s
        }
        let sessions = [session(daysAgo: 1, minutes: 12), session(daysAgo: 2, minutes: 5), session(daysAgo: 4, minutes: 30)]
        let stats = ReadingStats(sessions: sessions, books: [], goalMinutes: 20, now: now, calendar: calendar)
        XCTAssertEqual(stats.streak, 2) // today not read yet; yesterday + the day before
        XCTAssertEqual(stats.todayMinutes, 0)
        XCTAssertEqual(stats.totalPages, Int((47.0 * 250 / ReadingMath.wordsPerPage).rounded()))
        XCTAssertEqual(stats.heatmap(weeks: 4).count, 4)
        XCTAssertEqual(stats.level(for: 25), 4)
        XCTAssertEqual(stats.level(for: 0), 0)
    }
}

@MainActor
final class ClaudeProviderTests: XCTestCase {
    func testParsesDocumentedStreamEvents() {
        XCTAssertNil(ClaudeStreamEvent(line: "event: content_block_delta"))
        XCTAssertNil(ClaudeStreamEvent(line: ""))
        XCTAssertEqual(ClaudeStreamEvent(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#), .text("Hello"))
        XCTAssertEqual(ClaudeStreamEvent(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#), .other)
        XCTAssertEqual(ClaudeStreamEvent(line: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#), .refusal)
        XCTAssertEqual(ClaudeStreamEvent(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}"#), .other)
        XCTAssertEqual(ClaudeStreamEvent(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#), .error("Overloaded"))
    }

    func testRequestShape() throws {
        let conversation = ClaudeConversation(apiKey: "test-key", model: "claude-opus-5-5", instructions: "Be calm.")
        let request = try conversation.makeRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["thinking"]) // Opus 5.5 always thinks; effort is the control.
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")

        let haiku = try ClaudeConversation(apiKey: "k", model: "claude-haiku-5-5", instructions: "").makeRequest()
        XCTAssertNil(haiku.value(forHTTPHeaderField: "anthropic-beta"))
    }
}
