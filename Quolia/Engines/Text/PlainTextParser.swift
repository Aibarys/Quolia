import Foundation

/// Turns plain text files into chapters and paragraphs.
struct PlainTextParser {
    enum TextError: LocalizedError {
        case unreadable
        var errorDescription: String? { String(localized: "The text file couldn't be decoded.") }
    }

    /// Target size of synthetic parts when the text has no recognizable chapters.
    static let wordsPerPart = 4_000

    static func decode(_ data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        var converted: NSString?
        var lossy: ObjCBool = false
        let encoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: [
                    String.Encoding.utf8.rawValue,
                    String.Encoding.windowsCP1251.rawValue,
                    String.Encoding.utf16.rawValue,
                    String.Encoding.windowsCP1252.rawValue,
                    String.Encoding.isoLatin1.rawValue,
                ],
                .allowLossyKey: true,
            ],
            convertedString: &converted,
            usedLossyConversion: &lossy
        )
        if encoding != 0, let converted { return converted as String }
        throw TextError.unreadable
    }

    static func parse(url: URL) throws -> BookContent {
        let text = try decode(Data(contentsOf: url))
        let (title, author) = titleAndAuthor(fromFileName: url.deletingPathExtension().lastPathComponent)
        return parse(text: text, title: title, author: author)
    }

    static func parse(text: String, title: String, author: String) -> BookContent {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let paragraphs = splitParagraphs(normalized)

        var chapters: [Chapter] = []
        var currentTitle: String?
        var currentBlocks: [ContentBlock] = []

        func closeChapter() {
            guard !currentBlocks.isEmpty else { return }
            let title = currentTitle ?? (chapters.isEmpty ? String(localized: "Beginning") : String(localized: "Part \(chapters.count + 1)"))
            chapters.append(Chapter(id: chapters.count, title: title, blocks: currentBlocks))
            currentBlocks = []
        }

        let headingCount = paragraphs.filter(isChapterHeading).count
        let usesHeadings = headingCount >= 2

        for paragraph in paragraphs {
            if usesHeadings, isChapterHeading(paragraph) {
                closeChapter()
                currentTitle = paragraph
                currentBlocks.append(ContentBlock(kind: .heading, text: paragraph, level: 2))
            } else {
                currentBlocks.append(ContentBlock(kind: .paragraph, text: paragraph))
            }
        }
        closeChapter()

        if !usesHeadings {
            chapters = splitIntoParts(chapters.flatMap(\.blocks))
        }
        if chapters.isEmpty {
            chapters = [Chapter(id: 0, title: title, blocks: [ContentBlock(kind: .paragraph, text: " ")])]
        }

        let language = LanguageDetector.dominantLanguage(of: String(normalized.prefix(4_000)))
        var content = BookContent(title: title, author: author, language: language, chapters: chapters)
        LibraryBoilerplate.clean(&content)
        return content
    }

    /// Paragraphs are separated by blank lines when the file uses them;
    /// otherwise every line is its own paragraph.
    private static func splitParagraphs(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        let blankLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let usesBlankLines = blankLines > max(lines.count / 12, 2)

        func clean(_ s: String) -> String {
            s.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        }

        if usesBlankLines {
            var result: [String] = []
            var buffer: [String] = []
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    if !buffer.isEmpty { result.append(clean(buffer.joined(separator: " "))); buffer = [] }
                } else {
                    buffer.append(trimmed)
                }
            }
            if !buffer.isEmpty { result.append(clean(buffer.joined(separator: " "))) }
            return result
        }
        return lines.map { clean($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    private static let numberWords = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|first|second|third|fourth|fifth|первая|вторая|третья|четвертая|четвёртая|пятая"
    private static let headingPattern = try! NSRegularExpression(
        pattern: #"^(chapter|part|book|глава|часть|книга)\s+([0-9]+|[ivxlcdm]+|"# + numberWords + #")\b[\s\.:—\-]*.{0,60}$"#,
        options: [.caseInsensitive]
    )
    private static let standaloneHeadingPattern = try! NSRegularExpression(
        pattern: #"^(prologue|epilogue|introduction|preface|foreword|afterword|пролог|эпилог|предисловие|послесловие|введение)\.?$"#,
        options: [.caseInsensitive]
    )
    private static let romanPattern = try! NSRegularExpression(pattern: #"^[IVXLC]{1,7}\.?$"#)

    static func isChapterHeading(_ line: String) -> Bool {
        guard line.count <= 80 else { return false }
        let range = NSRange(line.startIndex..., in: line)
        for pattern in [headingPattern, standaloneHeadingPattern, romanPattern]
        where pattern.firstMatch(in: line, range: range) != nil {
            return true
        }
        return false
    }

    static func splitIntoParts(_ blocks: [ContentBlock]) -> [Chapter] {
        var chapters: [Chapter] = []
        var current: [ContentBlock] = []
        var words = 0
        for block in blocks {
            current.append(block)
            words += block.wordCount
            if words >= wordsPerPart {
                chapters.append(Chapter(id: chapters.count, title: String(localized: "Part \(chapters.count + 1)"), blocks: current))
                current = []
                words = 0
            }
        }
        if !current.isEmpty {
            if words < wordsPerPart / 4, var last = chapters.popLast() {
                last.blocks.append(contentsOf: current)
                chapters.append(last)
            } else {
                chapters.append(Chapter(id: chapters.count, title: String(localized: "Part \(chapters.count + 1)"), blocks: current))
            }
        }
        if chapters.count == 1 { chapters[0].title = String(localized: "Text", comment: "Title of the only part of a plain text book") }
        return chapters
    }

    /// Understands "Author - Title" and "Title" file names.
    static func titleAndAuthor(fromFileName name: String) -> (String, String) {
        let cleaned = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        for separator in [" - ", " — ", " – "] {
            let parts = cleaned.components(separatedBy: separator)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                return (parts[1].trimmingCharacters(in: .whitespaces), parts[0].trimmingCharacters(in: .whitespaces))
            }
        }
        return (cleaned.isEmpty ? String(localized: "Untitled") : cleaned, "")
    }
}
