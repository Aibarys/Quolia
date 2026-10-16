import XCTest
import SwiftData
@testable import Quolia

final class ExportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private var sample: [HighlightExporter.BookGroup] {
        [HighlightExporter.BookGroup(title: "On Reading Slowly", author: "Quolia Editions", items: [
            .init(text: "Reading is a way of returning.", note: "Like rereading letters.", tags: ["slow reading"],
                  color: .yellow, chapter: "Chapter 1", createdAt: date),
            .init(text: "- not a list\n1. not a number", note: nil, tags: [], color: .blue, chapter: "Chapter 1", createdAt: date),
            .init(text: "<Attention> & care", note: nil, tags: [], color: .green, chapter: "Chapter 2", createdAt: date),
        ])]
    }

    func testMarkdownGroupsByChapterWithNotesAndTags() {
        let markdown = HighlightExporter.markdown(sample, date: date)
        let lines = markdown.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "# On Reading Slowly")
        XCTAssertTrue(lines.contains("**Quolia Editions**"))
        XCTAssertEqual(lines.filter { $0 == "## Chapter 1" }.count, 1, "one heading per chapter")
        XCTAssertTrue(lines.contains("## Chapter 2"))
        XCTAssertTrue(lines.contains("> Reading is a way of returning."))
        // Labels come from the app's catalog, so compare in whatever language the simulator uses.
        let noteLabel = String(localized: "Note:", bundle: .main)
        XCTAssertTrue(lines.contains("**\(noteLabel)** Like rereading letters."))
        XCTAssertTrue(lines.contains("#slow-reading"))
        // Quoted lines never turn into lists.
        XCTAssertTrue(lines.contains("> \\- not a list"))
        XCTAssertTrue(lines.contains("> 1\\. not a number"))
        XCTAssertLessThan(lines.firstIndex(of: "## Chapter 1")!, lines.firstIndex(of: "## Chapter 2")!)
    }

    func testSeveralBooksGetADocumentTitle() {
        let second = HighlightExporter.BookGroup(title: "Second", author: "", items: sample[0].items)
        let markdown = HighlightExporter.markdown(sample + [second], date: date)
        XCTAssertTrue(markdown.hasPrefix("# \(String(localized: "Highlights and Notes", bundle: .main))\n"))
        XCTAssertTrue(markdown.contains("\n## On Reading Slowly\n"))
        XCTAssertTrue(markdown.contains("\n### Chapter 1\n"))
    }

    func testHTMLEscapesText() {
        let html = HighlightExporter.html(sample, date: date)
        XCTAssertTrue(html.contains("&lt;Attention&gt; &amp; care"))
        XCTAssertFalse(html.contains("<Attention>"))
    }

    @MainActor
    func testRendersPDF() {
        let data = HighlightExporter.pdf(sample, date: date)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
        XCTAssertGreaterThan(data.count, 2_000)
    }

    @MainActor
    func testGroupsFollowReadingOrder() throws {
        let container = try ModelContainer(for: ModelContainerFactory.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let book = Book(title: "B", author: "A", format: .epub, fileName: "b.epub")
        context.insert(book)
        func add(_ text: String, chapter: Int, block: Int) {
            let highlight = Highlight(text: text, color: .yellow,
                                      anchor: TextAnchor(chapter: chapter, startBlock: block, startOffset: 0, endBlock: block, endOffset: 3),
                                      chapterTitle: "Chapter \(chapter)", progress: 0)
            highlight.book = book
            context.insert(highlight)
        }
        add("third", chapter: 2, block: 1)
        add("first", chapter: 0, block: 5)
        add("second", chapter: 1, block: 0)
        let groups = HighlightExporter.groups(from: try context.fetch(FetchDescriptor<Highlight>()))
        XCTAssertEqual(groups.map(\.title), ["B"])
        XCTAssertEqual(groups[0].items.map(\.text), ["first", "second", "third"])
    }
}
