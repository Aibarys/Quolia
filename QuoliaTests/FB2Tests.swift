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
        XCTAssertEqual(paragraph.spans.map { text.substring(with: $0.range) }, ["курсивный", "жирный", "1"])
        XCTAssertEqual(paragraph.spans.map(\.style), [.italic, .bold, .superscript])
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

    func testRecognizesFB2Files() {
        XCTAssertEqual(BookFormat(url: URL(fileURLWithPath: "/tmp/Война и мир.fb2")), .fb2)
        XCTAssertEqual(BookFormat(url: URL(fileURLWithPath: "/tmp/Война и мир.fb2.zip")), .fb2)
    }
}
