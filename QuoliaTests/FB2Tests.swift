import XCTest
@testable import Quolia

final class FB2Tests: XCTestCase {
    private let imagesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// A tiny 1×1 PNG used as the cover binary.
    private let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private func sample(encoding: String = "utf-8") -> String {
        """
        <?xml version="1.0" encoding="\(encoding)"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
          <description>
            <title-info>
              <author><first-name>Лев</first-name><middle-name>Николаевич</middle-name><last-name>Толстой</last-name></author>
              <book-title>Тестовая книга</book-title>
              <lang>ru</lang>
              <coverpage><image l:href="#cover.png"/></coverpage>
            </title-info>
          </description>
          <body>
            <title><p>Тестовая книга</p></title>
            <section>
              <title><p>Часть первая</p></title>
              <epigraph><p>Всё смешалось.</p><text-author>Автор</text-author></epigraph>
              <section>
                <title><p>Глава I</p></title>
                <p>Первый <emphasis>курсивный</emphasis> и <strong>жирный</strong> абзац<a l:href="#n1" type="note">1</a>.</p>
                <empty-line/>
                <poem><stanza><v>Строка один,</v><v>строка два.</v></stanza></poem>
              </section>
              <section>
                <title><p>Глава II</p></title>
                <p>Второй абзац &mdash; с тире.</p>
              </section>
            </section>
          </body>
          <body name="notes">
            <title><p>Примечания</p></title>
            <section id="n1"><title><p>1</p></title><p>Текст сноски.</p></section>
          </body>
          <binary id="cover.png" content-type="image/png">\(pixel)</binary>
        </FictionBook>
        """
    }

    func testParsesStructureMetadataAndStyles() throws {
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let result = try parser.parse(data: Data(sample().utf8))
        let content = result.content
        XCTAssertEqual(content.title, "Тестовая книга")
        XCTAssertEqual(content.author, "Лев Николаевич Толстой")
        XCTAssertEqual(content.language, "ru")
        XCTAssertNotNil(result.coverData)
        XCTAssertEqual(content.chapters.map(\.title), ["Глава I", "Глава II", "Примечания"])

        let first = content.chapters[0].blocks
        // The part title and its epigraph open the first chapter.
        XCTAssertTrue(first.contains { $0.kind == .heading && $0.text == "Часть первая" && $0.level == 1 })
        XCTAssertTrue(first.contains { $0.kind == .quote && $0.text == "Всё смешалось." })
        XCTAssertTrue(first.contains { $0.kind == .caption && $0.text == "— Автор" })
        let paragraph = try XCTUnwrap(first.first { $0.kind == .paragraph })
        XCTAssertEqual(paragraph.text, "Первый курсивный и жирный абзац1.")
        let text = paragraph.text as NSString
        XCTAssertEqual(paragraph.spans.map { text.substring(with: $0.range) }, ["курсивный", "жирный", "1", "1"])
        XCTAssertEqual(paragraph.spans.map(\.style), [.italic, .bold, .superscript, .noteRef])
        XCTAssertTrue(first.contains { $0.kind == .quote && $0.text == "Строка один,\nстрока два." })
        XCTAssertEqual(content.chapters[1].blocks.last?.text, "Второй абзац — с тире.")
        XCTAssertTrue(content.chapters[2].blocks.contains { $0.text == "Текст сноски." })
    }

    func testHonorsWindows1251Declaration() throws {
        let data = try XCTUnwrap(sample(encoding: "windows-1251").data(using: .windowsCP1251))
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let content = try parser.parse(data: data).content
        XCTAssertEqual(content.author, "Лев Николаевич Толстой")
        XCTAssertEqual(content.chapters.first?.title, "Глава I")
    }

    func testReadsZippedFB2() throws {
        let zipped = "UEsDBBQAAAAIAJF8T11UA7K7BQEAAKkBAAAIAAAAYm9vay5mYjJVkF1KxDAUhbcS+t5e9UnkNgM+uI/+pJ1gJylJatUnFXwX3IErKIVBUXQNtzsyndIxkpdwz3fPOVzc3O4adiOMlVql0WlyEjGhCl1KVadR56r4PNpwvJKF88Cl1tfMLyibRlvn2guAvu+T2si8s8IkpgOvQrXQuafhzDtyLIUtjGznKUcnXSNiqSrNMevcVhuOlTTWxSrbCU4v9O3fgBAMscmO+hvtp8fpiX5onKk/BWG1m6PjQ463mx6mZ/qgESEYe0NVc9PN+/6DELaCf31zXd5xtKII6nNsOb3SFw1zCUYjo2HNoT1CuzoeQN+YPufOzOvv7F62cYAPycIfE2BJhODq/BdQSwECFAMUAAAACACRfE9dVAOyuwUBAACpAQAACAAAAAAAAAAAAAAAgAEAAAAAYm9vay5mYjJQSwUGAAAAAAEAAQA2AAAAKwEAAAAA"
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let content = try parser.parse(data: try XCTUnwrap(Data(base64Encoded: zipped))).content
        XCTAssertEqual(content.title, "Архив")
        XCTAssertEqual(content.author, "Анна Тестова")
        XCTAssertEqual(content.chapters.first?.blocks.last?.text, "Текст из zip-архива.")
    }

    func testUsesSubtitleWhenSectionRepeatsBookTitle() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook><description><title-info><book-title>Шум и ярость</book-title></title-info></description>
        <body><section><title><p>Уильям Фолкнер</p><p>Шум и ярость</p></title><subtitle>7 апреля 1928 года</subtitle><p>Текст.</p></section>
        <section><title><p>Часть вторая</p><p>Утро</p></title><p>Ещё текст.</p></section></body></FictionBook>
        """
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let content = try parser.parse(data: Data(xml.utf8)).content
        XCTAssertEqual(content.chapters.map(\.title), ["7 апреля 1928 года", "Часть вторая. Утро"])
    }

    func testNoteLinksBecomeFootnotes() throws {
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let content = try parser.parse(data: Data(sample().utf8)).content
        let paragraph = try XCTUnwrap(content.chapters[0].blocks.first { $0.kind == .paragraph })
        let reference = try XCTUnwrap(paragraph.spans.first { $0.style == .noteRef })
        XCTAssertEqual(content.footnotes[try XCTUnwrap(reference.target)], Footnote(label: "1", text: "Текст сноски."))
    }

    /// Some editions link plain "1" marks to numbered subtitles in a comments section of the main body.
    func testCommentLinksWithoutNoteTypeBecomeFootnotes() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><book-title>Книга</book-title></title-info></description>
        <body><section><title><p>Глава</p></title>
        <p>Подай клюшки<a l:href="#c1">1</a>! Смотри <a l:href="#c2">вторую главу</a> и <a l:href="http://example.com">сайт</a>.</p></section>
        <section><title><p>Комментарии</p></title><empty-line/><subtitle id="c1">1</subtitle><empty-line/>
        <p><emphasis>…клюшки</emphasis> — пояснение.</p><empty-line/><subtitle id="c2">2</subtitle><p>Второе.</p></section></body></FictionBook>
        """
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let content = try parser.parse(data: Data(xml.utf8)).content
        let paragraph = try XCTUnwrap(content.chapters[0].blocks.first { $0.kind == .paragraph })
        let text = paragraph.text as NSString
        let references = paragraph.spans.filter { $0.style == .noteRef }
        XCTAssertEqual(references.map { text.substring(with: $0.range) }, ["1"], "only the mark-like link is a footnote")
        XCTAssertTrue(paragraph.spans.contains { $0.style == .superscript && $0.range == references[0].range })
        XCTAssertEqual(content.footnotes["c1"], Footnote(label: "1", text: "…клюшки — пояснение."))
        XCTAssertEqual(content.footnotes.count, 1)
    }

    func testRemovesDownloadSiteAdsAndMakesTitlePage() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>
        <author><first-name>Уильям</first-name><last-name>Фолкнер</last-name></author><book-title>Шум и ярость</book-title>
        </title-info></description><body>
        <p>Спасибо, что скачали книгу в <a l:href="http://example.com">бесплатной электронной библиотеке Example</a></p>
        <p><a l:href="http://example.com/a">Все книги автора</a></p><p>Эта же книга в других форматах</p><empty-line/><p>Приятного чтения!</p>
        <section><title><p>Уильям Фолкнер</p><empty-line/><p>Шум и ярость</p></title><subtitle>7 апреля 1928 года</subtitle>
        <p>Через забор.</p><p>Приятного чтения!</p></section></body></FictionBook>
        """
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        let blocks = try parser.parse(data: Data(xml.utf8)).content.chapters[0].blocks
        // Ads become empty placeholders, so the indices of the blocks after them don't change.
        XCTAssertEqual(blocks.map(\.kind), [.omitted, .omitted, .omitted, .omitted, .title, .heading, .paragraph, .paragraph])
        XCTAssertTrue(blocks.prefix(4).allSatisfy { $0.text.isEmpty && $0.wordCount == 0 })
        XCTAssertEqual(blocks[4].text, "Уильям Фолкнер\nШум и ярость")
        XCTAssertEqual(blocks[4].spans.map(\.style), [.byline])
        XCTAssertEqual((blocks[4].text as NSString).substring(with: blocks[4].spans[0].range), "Уильям Фолкнер")
        XCTAssertEqual(blocks[7].text, "Приятного чтения!", "the same words inside the story stay")
    }

    func testRecognizesFB2Files() {
        XCTAssertEqual(BookFormat(url: URL(fileURLWithPath: "/tmp/Война и мир.fb2")), .fb2)
        XCTAssertEqual(BookFormat(url: URL(fileURLWithPath: "/tmp/Война и мир.fb2.zip")), .fb2)
    }
}
