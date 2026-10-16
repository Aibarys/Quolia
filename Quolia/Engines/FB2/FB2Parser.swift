import Foundation

/// Parses FictionBook 2 (`.fb2`, also zipped as `.fb2.zip`) into `BookContent`.
///
/// Sections become chapters (nested sections are flattened, keeping their titles
/// as headings), epigraphs and citations become quotes, poems keep their lines,
/// embedded images are extracted, and footnotes become a final chapter. Note
/// references become tappable footnotes, and download-site ads are removed.
struct FB2Parser {
    enum FB2Error: LocalizedError {
        case unreadable
        case noBookInArchive
        case emptyBook

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "This FB2 file couldn't be read.")
            case .noBookInArchive: String(localized: "This archive doesn't contain an FB2 book.")
            case .emptyBook: String(localized: "This book doesn't contain any readable text.")
            }
        }
    }

    struct Result {
        var content: BookContent
        var coverData: Data?
    }

    let imagesDirectory: URL
    private var binaries: [String: (data: Data, type: String)] = [:]
    private var extractedImages: [String: String] = [:]
    private var elementsByID: [String: MarkupNode] = [:]
    private var footnotes: FootnoteResolver?

    init(imagesDirectory: URL) {
        self.imagesDirectory = imagesDirectory
    }

    static func parse(url: URL, imagesDirectory: URL) throws -> Result {
        var parser = FB2Parser(imagesDirectory: imagesDirectory)
        return try parser.parse(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    mutating func parse(data raw: Data) throws -> Result {
        let data = try Self.unzipIfNeeded(raw)
        guard let text = Self.decode(data) else { throw FB2Error.unreadable }
        let root = MarkupParser.parse(text)
        guard let book = root.first("fictionbook") else { throw FB2Error.unreadable }

        for binary in book.elements where binary.name == "binary" {
            guard let id = binary["id"] else { continue }
            let base64 = binary.textContent.filter { !$0.isWhitespace }
            if let decoded = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                binaries[id] = (decoded, binary["content-type"] ?? "image/jpeg")
            }
        }

        // Metadata
        let titleInfo = book.child("description")?.child("title-info")
        let title = titleInfo?.child("book-title")?.textContent.nonEmpty ?? String(localized: "Untitled")
        let authors = (titleInfo?.elements.filter { $0.name == "author" } ?? []).compactMap(Self.authorName)
        let language = titleInfo?.child("lang")?.textContent.nonEmpty
        let coverID = titleInfo?.child("coverpage")?.first("image")?["href"].map(Self.binaryID)
        let coverData = coverID.flatMap { binaries[$0]?.data }

        // Content
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        Self.indexIDs(book, into: &elementsByID)
        let index = elementsByID
        footnotes = FootnoteResolver { index[$0] }
        let bodies = book.elements.filter { $0.name == "body" }
        let mainBody = bodies.first { $0["name"] == nil } ?? bodies.first
        var chapters = mainBody.map { makeChapters(body: $0, bookTitle: title, authors: authors) } ?? []

        for notes in bodies where notes !== mainBody {
            var blocks: [ContentBlock] = []
            for section in notes.all("section") {
                blocks += convert(section, headingLevel: 3, skipSections: true)
            }
            if !blocks.isEmpty {
                let name = notes.child("title").map(Self.titleLine) ?? String(localized: "Footnotes")
                chapters.append(Chapter(id: chapters.count, title: name.isEmpty ? String(localized: "Footnotes") : name, blocks: blocks))
            }
        }

        guard chapters.contains(where: { $0.wordCount > 0 }) else { throw FB2Error.emptyBook }
        var content = BookContent(title: title, author: authors.joined(separator: ", "), language: language, chapters: chapters)
        content.footnotes = footnotes?.footnotes ?? [:]
        LibraryBoilerplate.clean(&content)
        return Result(content: content, coverData: coverData)
    }

    private static func indexIDs(_ node: MarkupNode, into index: inout [String: MarkupNode]) {
        for element in node.elements where element.name != "binary" {
            if let id = element["id"], index[id] == nil { index[id] = element }
            indexIDs(element, into: &index)
        }
    }

    // MARK: - Chapters

    private mutating func makeChapters(body: MarkupNode, bookTitle: String, authors: [String]) -> [Chapter] {
        var chapters: [Chapter] = []
        var pending: [ContentBlock] = []

        func titlePage(_ node: MarkupNode?, requiresAuthor: Bool) -> ContentBlock? {
            node.flatMap { Self.titlePageBlock($0, bookTitle: bookTitle, authors: authors, requiresAuthor: requiresAuthor) }
        }

        func visit(_ section: MarkupNode, parentTitle: String?, depth: Int, parser: inout FB2Parser) {
            let ownTitle = Self.chapterTitle(of: section, bookTitle: bookTitle)
            let children = section.elements.filter { $0.name == "section" }
            if children.isEmpty {
                var blocks = pending
                pending = []
                var sectionBlocks = parser.convert(section, headingLevel: 2, skipSections: true)
                if let title = titlePage(section.child("title"), requiresAuthor: true), sectionBlocks.first?.kind == .heading {
                    sectionBlocks[0] = title
                }
                blocks += sectionBlocks
                guard !blocks.isEmpty else { return }
                let title = ownTitle ?? parentTitle ?? String(localized: "Section \(chapters.count + 1)")
                chapters.append(Chapter(id: chapters.count, title: title, blocks: blocks))
            } else {
                // A part: its title and epigraphs open the first chapter inside it.
                for child in section.elements {
                    if child.name == "section" {
                        visit(child, parentTitle: ownTitle ?? parentTitle, depth: depth + 1, parser: &parser)
                    } else if child.name == "title", let title = titlePage(child, requiresAuthor: true) {
                        pending.append(title)
                    } else {
                        pending += parser.convert(child, headingLevel: 1, skipSections: true)
                    }
                }
            }
        }

        for child in body.elements {
            if child.name == "section" {
                visit(child, parentTitle: nil, depth: 0, parser: &self)
            } else if child.name == "title", let title = titlePage(child, requiresAuthor: false) {
                pending.append(title)
            } else {
                pending += convert(child, headingLevel: 1, skipSections: true)
            }
        }

        if !pending.isEmpty {
            if chapters.isEmpty {
                // No sections at all: split long text into parts, like plain text.
                return PlainTextParser.splitIntoParts(pending)
            }
            chapters[chapters.count - 1].blocks += pending
        }
        return chapters
    }

    // MARK: - Blocks

    /// Converts one FB2 element (or the children of a section) into blocks.
    private mutating func convert(_ node: MarkupNode, headingLevel: Int, skipSections: Bool) -> [ContentBlock] {
        switch node.name {
        case "section":
            var blocks: [ContentBlock] = []
            for child in node.elements where !(skipSections && child.name == "section") {
                blocks += convert(child, headingLevel: headingLevel, skipSections: true)
            }
            return blocks
        case "title":
            let text = Self.titleText(node)
            return text.isEmpty ? [] : [ContentBlock(kind: .heading, text: text, level: headingLevel)]
        case "subtitle":
            return Self.inline(node).map { ContentBlock(kind: .heading, text: $0.text, level: 3, spans: $0.spans) }.map { [$0] } ?? []
        case "p":
            return Self.inline(node, footnotes: footnotes).map { [ContentBlock(kind: .paragraph, text: $0.text, spans: $0.spans)] } ?? []
        case "epigraph", "cite", "annotation":
            return node.elements.flatMap { child -> [ContentBlock] in
                switch child.name {
                case "p": return Self.inline(child, footnotes: footnotes).map { [ContentBlock(kind: .quote, text: $0.text, spans: $0.spans)] } ?? []
                case "text-author": return Self.inline(child).map { [ContentBlock(kind: .caption, text: "— " + $0.text)] } ?? []
                default: return convert(child, headingLevel: 3, skipSections: true)
                }
            }
        case "poem":
            var blocks: [ContentBlock] = []
            for child in node.elements {
                switch child.name {
                case "title": blocks += convert(child, headingLevel: 3, skipSections: true)
                case "stanza":
                    if let stanzaTitle = child.child("title").map(Self.titleText)?.nonEmpty {
                        blocks.append(ContentBlock(kind: .heading, text: stanzaTitle, level: 4))
                    }
                    let lines = child.elements.filter { $0.name == "v" }.compactMap { Self.inline($0)?.text }
                    if !lines.isEmpty { blocks.append(ContentBlock(kind: .quote, text: lines.joined(separator: "\n"))) }
                case "text-author", "date":
                    if let text = Self.inline(child)?.text { blocks.append(ContentBlock(kind: .caption, text: text)) }
                default:
                    blocks += convert(child, headingLevel: 3, skipSections: true)
                }
            }
            return blocks
        case "image":
            guard let href = node["href"], let file = image(for: Self.binaryID(href)) else { return [] }
            return [ContentBlock(kind: .image, text: "", image: file)]
        case "table":
            return node.all("tr").compactMap { row in
                let cells = row.elements.compactMap { Self.inline($0)?.text }
                return cells.isEmpty ? nil : ContentBlock(kind: .paragraph, text: cells.joined(separator: " · "))
            }
        case "empty-line", "binary":
            return []
        default:
            return node.elements.flatMap { convert($0, headingLevel: headingLevel, skipSections: skipSections) }
        }
    }

    private mutating func image(for id: String) -> String? {
        if let existing = extractedImages[id] { return existing }
        guard let binary = binaries[id] else { return nil }
        let ext: String
        switch binary.type.lowercased() {
        case let type where type.contains("png"): ext = "png"
        case let type where type.contains("gif"): ext = "gif"
        default: ext = "jpg"
        }
        let name = "fb2-img\(extractedImages.count).\(ext)"
        try? binary.data.write(to: imagesDirectory.appendingPathComponent(name))
        extractedImages[id] = name
        return name
    }

    // MARK: - Text helpers

    private static func binaryID(_ href: String) -> String {
        href.hasPrefix("#") ? String(href.dropFirst()) : href
    }

    private static func authorName(_ author: MarkupNode) -> String? {
        let parts = ["first-name", "middle-name", "last-name"].compactMap { author.child($0)?.textContent.nonEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return author.child("nickname")?.textContent.nonEmpty
    }

    /// Single-line title for navigation: "Часть первая. Утро".
    private static func titleLine(_ node: MarkupNode) -> String {
        let lines = node.elements.compactMap { inline($0)?.text }
        guard !lines.isEmpty else { return node.textContent }
        return lines.dropFirst().reduce(lines[0]) { result, line in
            let ends = result.last.map { ".!?:;…".contains($0) } ?? false
            return result + (ends ? " " : ". ") + line
        }
    }

    /// Chapter name for a section. Some books repeat the book's title in a section
    /// title and put the real name (e.g. a date) in the first subtitle — prefer that.
    private static func chapterTitle(of section: MarkupNode, bookTitle: String) -> String? {
        guard let titleNode = section.child("title") else {
            return section.elements.first { $0.name == "subtitle" }.flatMap { inline($0)?.text }
        }
        let title = titleLine(titleNode)
        let repeatsBook = !bookTitle.isEmpty && title.localizedCaseInsensitiveContains(bookTitle)
        if repeatsBook,
           let subtitle = section.elements.prefix { $0.name != "p" }.first(where: { $0.name == "subtitle" }),
           let text = inline(subtitle)?.text {
            return text
        }
        return title.nonEmpty
    }

    /// A title made only of the author's name and the book's title ("Уильям Фолкнер / Шум и ярость")
    /// becomes a title page. Inside sections the author must be there too, so a story that shares
    /// the book's name keeps an ordinary heading.
    private static func titlePageBlock(_ node: MarkupNode, bookTitle: String, authors: [String], requiresAuthor: Bool) -> ContentBlock? {
        let lines = node.elements.compactMap { inline($0)?.text }
        guard !lines.isEmpty, lines.count <= 4 else { return nil }
        var text = ""
        var spans: [InlineSpan] = []
        var hasTitle = false, hasAuthor = false
        for line in lines {
            let isTitle = !bookTitle.isEmpty && normalizedName(line) == normalizedName(bookTitle)
            let isAuthor = !isTitle && authors.contains { nameWords($0) == nameWords(line) }
            guard isTitle || isAuthor else { return nil }
            hasTitle = hasTitle || isTitle
            hasAuthor = hasAuthor || isAuthor
            if !text.isEmpty { text += "\n" }
            if isAuthor { spans.append(InlineSpan(location: text.utf16.count, length: line.utf16.count, style: .byline)) }
            text += line
        }
        guard hasTitle, hasAuthor || !requiresAuthor else { return nil }
        return ContentBlock(kind: .title, text: text, spans: spans)
    }

    private static func normalizedName(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Name words in any order: "Фолкнер Уильям" matches "Уильям Фолкнер".
    private static func nameWords(_ name: String) -> Set<String> {
        Set(normalizedName(name).split(separator: " ").map(String.init))
    }

    /// Titles hold one or more `<p>`; lines are kept.
    private static func titleText(_ node: MarkupNode) -> String {
        let lines = node.elements.compactMap { inline($0)?.text }
        return lines.isEmpty ? node.textContent : lines.joined(separator: "\n")
    }

    /// Collects text and inline styles from a paragraph-like element. With `footnotes`,
    /// links to notes become tappable note references.
    static func inline(_ node: MarkupNode, footnotes: FootnoteResolver? = nil) -> (text: String, spans: [InlineSpan])? {
        var collector = InlineCollector(footnotes: footnotes)
        collector.walk(node)
        return collector.finish()
    }

    private struct InlineCollector {
        let footnotes: FootnoteResolver?
        var text = ""
        var length = 0
        var spans: [InlineSpan] = []
        var lastWasSpace = true

        mutating func walk(_ node: MarkupNode) {
            for child in node.children {
                switch child.kind {
                case .text:
                    append(child.text)
                case .element:
                    let style: InlineSpan.Style?
                    switch child.name {
                    case "emphasis": style = .italic
                    case "strong": style = .bold
                    case "code": style = .code
                    case "sup": style = .superscript
                    case "a": style = child["type"] == "note" ? .superscript : nil
                    default: style = nil
                    }
                    let start = length
                    walk(child)
                    if let style, length > start {
                        spans.append(InlineSpan(location: start, length: length - start, style: style))
                    }
                    if child.name == "a", length > start, let footnotes, let href = child["href"], href.hasPrefix("#") {
                        let label = (text as NSString).substring(with: NSRange(location: start, length: length - start))
                        let explicit = child["type"] == "note"
                        if let key = footnotes.resolve(key: String(href.dropFirst()), label: label, explicit: explicit) {
                            spans.append(InlineSpan(location: start, length: length - start, style: .noteRef, target: key))
                            // Plain "1" links read better raised, like printed footnote marks.
                            if !explicit, FootnoteResolver.isMark(label.trimmingCharacters(in: .whitespaces)) {
                                spans.append(InlineSpan(location: start, length: length - start, style: .superscript))
                            }
                        }
                    }
                case .document:
                    walk(child)
                }
            }
        }

        mutating func append(_ raw: String) {
            var piece = ""
            for char in raw {
                if char.isWhitespace && char != "\u{00A0}" {
                    if !lastWasSpace { piece.append(" "); lastWasSpace = true }
                } else if char != "\u{00AD}" {
                    piece.append(char)
                    lastWasSpace = false
                }
            }
            text += piece
            length += piece.utf16.count
        }

        mutating func finish() -> (text: String, spans: [InlineSpan])? {
            while text.hasSuffix(" ") { text.removeLast(); length -= 1 }
            guard !text.isEmpty else { return nil }
            let clipped = spans.compactMap { span -> InlineSpan? in
                let end = min(span.location + span.length, length)
                return end > span.location
                    ? InlineSpan(location: span.location, length: end - span.location, style: span.style, target: span.target) : nil
            }
            return (text, clipped)
        }
    }

    // MARK: - Container and encoding

    /// `.fb2.zip`: returns the first `.fb2` inside; plain files pass through.
    static func unzipIfNeeded(_ data: Data) throws -> Data {
        guard data.starts(with: [0x50, 0x4B, 0x03, 0x04]) else { return data }
        let archive = try ZipArchive(data: data)
        guard let entry = archive.paths.sorted().first(where: { $0.lowercased().hasSuffix(".fb2") }) else {
            throw FB2Error.noBookInArchive
        }
        return try archive.data(for: entry)
    }

    /// Honors the encoding in the XML declaration (UTF-8, Windows-1251, KOI8-R…).
    static func decode(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(256), as: UTF8.self)
        if let range = head.range(of: #"encoding\s*=\s*["']([A-Za-z0-9_\-]+)["']"#, options: .regularExpression) {
            let declared = head[range]
                .split(whereSeparator: { $0 == "\"" || $0 == "'" })
                .dropFirst().first.map { $0.lowercased() } ?? ""
            if let encoding = encoding(named: declared), let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return try? PlainTextParser.decode(data)
    }

    private static func encoding(named name: String) -> String.Encoding? {
        switch name {
        case "utf-8", "utf8": return .utf8
        case "windows-1251", "cp1251", "cp-1251": return .windowsCP1251
        case "windows-1252", "cp1252": return .windowsCP1252
        case "iso-8859-1", "latin1": return .isoLatin1
        case "utf-16", "utf16": return .utf16
        case "koi8-r":
            let koi8 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue))
            return String.Encoding(rawValue: koi8)
        default:
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
    }
}
