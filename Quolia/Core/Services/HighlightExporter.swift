import SwiftUI
import UniformTypeIdentifiers

/// Exports highlights and notes as Markdown (for Notes, Obsidian, Notion…) or PDF,
/// grouped by book and chapter in reading order.
enum HighlightExporter {
    struct Item: Sendable, Hashable {
        var text: String
        var note: String?
        var tags: [String]
        var color: HighlightColor
        var chapter: String
        var createdAt: Date
    }

    struct BookGroup: Sendable, Hashable {
        var title: String
        var author: String
        var items: [Item]
    }

    // MARK: - Snapshot

    /// Books and their highlights in reading order, as plain values that can leave the main actor.
    @MainActor
    static func groups(from highlights: [Highlight]) -> [BookGroup] {
        Dictionary(grouping: highlights) { $0.book?.id }.values.compactMap { list -> BookGroup? in
            guard let book = list.first?.book else { return nil }
            let items = list.sorted(by: isBefore).map { highlight in
                Item(text: highlight.text, note: highlight.hasNote ? highlight.note : nil, tags: highlight.tags,
                     color: highlight.color, chapter: highlight.chapterTitle, createdAt: highlight.createdAt)
            }
            return BookGroup(title: book.title, author: book.author, items: items)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    @MainActor
    private static func isBefore(_ a: Highlight, _ b: Highlight) -> Bool {
        let first = (a.isPDFAnchored ? a.pageIndex : a.chapterIndex, a.startBlock, a.startOffset)
        let second = (b.isPDFAnchored ? b.pageIndex : b.chapterIndex, b.startBlock, b.startOffset)
        return first == second ? a.progress < b.progress : first < second
    }

    /// "Шум и ярость" for one book, "Highlights and Notes" for several.
    static func title(of groups: [BookGroup]) -> String {
        groups.count == 1 ? groups[0].title : String(localized: "Highlights and Notes")
    }

    private static func summary(of groups: [BookGroup], date: Date) -> String {
        let items = groups.flatMap(\.items)
        let notes = items.filter { $0.note != nil }.count
        var parts = [String(localized: "Exported from Quolia on \(date.formatted(date: .long, time: .omitted))"),
                     String(localized: "\(items.count) highlights")]
        if notes > 0 { parts.append(String(localized: "\(notes) notes")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Markdown

    static func markdown(_ groups: [BookGroup], date: Date = .now) -> String {
        var lines: [String] = []
        let single = groups.count == 1
        let bookLevel = single ? "#" : "##"
        if !single {
            lines += ["# \(title(of: groups))", "", "_\(summary(of: groups, date: date))_", ""]
        }
        for group in groups {
            lines.append("\(bookLevel) \(escapedLine(group.title))")
            if !group.author.isEmpty { lines.append("**\(escapedLine(group.author))**") }
            lines.append("")
            if single { lines += ["_\(summary(of: groups, date: date))_", ""] }

            var chapter: String?
            for item in group.items {
                if item.chapter != chapter {
                    chapter = item.chapter
                    if !item.chapter.isEmpty { lines += ["\(bookLevel)# \(escapedLine(item.chapter))", ""] }
                }
                lines += item.text.components(separatedBy: .newlines).map { "> " + escapedLine($0) }
                lines.append("")
                if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let label = String(localized: "Note:", comment: "Label before a note in an export")
                    lines += ["**\(label)** " + note, ""]
                }
                lines.append("_\(item.color.name) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))_")
                if !item.tags.isEmpty {
                    lines.append(item.tags.map { "#" + $0.replacingOccurrences(of: " ", with: "-") }.joined(separator: " "))
                }
                lines.append("")
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Keeps a line from turning into a heading, list or rule when rendered.
    private static func escapedLine(_ line: String) -> String {
        guard let first = line.first else { return line }
        if "#>+-*=|".contains(first) { return "\\" + line }
        if let dot = line.firstIndex(where: { !$0.isNumber }), dot != line.startIndex,
           line[dot] == "." || line[dot] == ")" {
            return line.replacingCharacters(in: dot...dot, with: "\\" + String(line[dot]))
        }
        return line
    }

    // MARK: - PDF

    static func html(_ groups: [BookGroup], date: Date = .now) -> String {
        var body = ""
        if groups.count > 1 {
            body += "<h1>\(escaped(title(of: groups)))</h1><p class=\"meta\">\(escaped(summary(of: groups, date: date)))</p>"
        }
        for (index, group) in groups.enumerated() {
            body += "<section class=\"book\(index > 0 ? " next" : "")\">"
            body += groups.count == 1 ? "<h1>\(escaped(group.title))</h1>" : "<h2 class=\"book-title\">\(escaped(group.title))</h2>"
            if !group.author.isEmpty { body += "<p class=\"author\">\(escaped(group.author))</p>" }
            if groups.count == 1 { body += "<p class=\"meta\">\(escaped(summary(of: groups, date: date)))</p>" }
            var chapter: String?
            for item in group.items {
                if item.chapter != chapter {
                    chapter = item.chapter
                    if !item.chapter.isEmpty { body += "<h3>\(escaped(item.chapter))</h3>" }
                }
                body += "<blockquote style=\"border-color: \(hex(item.color))\">\(escaped(item.text, keepingLines: true))</blockquote>"
                if let note = item.note {
                    body += "<p class=\"note\">\(escaped(note, keepingLines: true))</p>"
                }
                var details = "\(item.color.name) · \(item.createdAt.formatted(date: .abbreviated, time: .omitted))"
                if !item.tags.isEmpty { details += " · " + item.tags.map { "#" + $0 }.joined(separator: " ") }
                body += "<p class=\"details\">\(escaped(details))</p>"
            }
            body += "</section>"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: "New York", "Iowan Old Style", Georgia, serif; font-size: 12pt; line-height: 1.45; color: #1f1d1a; }
        h1 { font-size: 24pt; font-weight: 600; margin: 0 0 4pt; }
        h2.book-title { font-size: 18pt; font-weight: 600; margin: 0 0 2pt; }
        .next { page-break-before: always; }
        .author { font-size: 13pt; color: #6b655d; margin: 0 0 6pt; }
        .meta { font-family: -apple-system, Helvetica, sans-serif; font-size: 8.5pt; color: #9a938a; margin: 0 0 22pt; }
        h3 { font-family: -apple-system, Helvetica, sans-serif; font-size: 9pt; font-weight: 600; letter-spacing: 0.8pt;
             text-transform: uppercase; color: #8a8379; margin: 20pt 0 10pt; }
        blockquote { margin: 0 0 6pt; padding: 1pt 0 1pt 12pt; border-left: 3pt solid; }
        .note { font-family: -apple-system, Helvetica, sans-serif; font-size: 10.5pt; color: #3a3631; margin: 0 0 4pt 15pt; }
        .details { font-family: -apple-system, Helvetica, sans-serif; font-size: 8pt; color: #a59e94; margin: 0 0 16pt 15pt; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// Renders the HTML on A4 pages with a footer and page numbers.
    @MainActor
    static func pdf(_ groups: [BookGroup], date: Date = .now) -> Data {
        let renderer = PageRenderer(footer: "\(title(of: groups)) · Quolia")
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html(groups, date: date)), startingAtPageAt: 0)
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, renderer.paperRect, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    private final class PageRenderer: UIPrintPageRenderer {
        private let footer: String
        private static let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4

        init(footer: String) {
            self.footer = footer
            super.init()
            footerHeight = 28
        }

        override var paperRect: CGRect { Self.paper }
        override var printableRect: CGRect { Self.paper.insetBy(dx: 54, dy: 50) }

        override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = "\(footer) · \(pageIndex + 1)" as NSString
            text.draw(in: footerRect.offsetBy(dx: 0, dy: 8), withAttributes: [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.62, alpha: 1),
                .paragraphStyle: style,
            ])
        }
    }

    private static func escaped(_ text: String, keepingLines: Bool = false) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        if keepingLines { result = result.replacingOccurrences(of: "\n", with: "<br>") }
        return result
    }

    private static func hex(_ color: HighlightColor) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        color.uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    // MARK: - Files

    static func writeMarkdown(_ groups: [BookGroup]) throws -> URL {
        let url = try fileURL(for: groups, extension: "md")
        try markdown(groups).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    static func writePDF(_ groups: [BookGroup]) throws -> URL {
        let url = try fileURL(for: groups, extension: "pdf")
        try pdf(groups).write(to: url, options: .atomic)
        return url
    }

    /// A fresh folder per export, so the shared file keeps a readable name.
    private static func fileURL(for groups: [BookGroup], extension ext: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = title(of: groups)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return folder.appendingPathComponent(String((name.isEmpty ? "Quolia" : name).prefix(80))).appendingPathExtension(ext)
    }
}

/// Highlights shared as a Markdown file, written when the share sheet asks for it.
struct MarkdownHighlightsExport: Transferable {
    let groups: [HighlightExporter.BookGroup]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            SentTransferredFile(try HighlightExporter.writeMarkdown(export.groups))
        }
    }
}

/// Highlights shared as a PDF, rendered when the share sheet asks for it.
struct PDFHighlightsExport: Transferable {
    let groups: [HighlightExporter.BookGroup]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { export in
            SentTransferredFile(try await MainActor.run { try HighlightExporter.writePDF(export.groups) })
        }
    }
}

/// "Export as Markdown / PDF" buttons for a set of highlights.
struct HighlightExportButtons: View {
    let groups: [HighlightExporter.BookGroup]

    var body: some View {
        let title = HighlightExporter.title(of: groups)
        ShareLink(item: MarkdownHighlightsExport(groups: groups), preview: SharePreview(title)) {
            Label("Export as Markdown", systemImage: "doc.plaintext")
        }
        ShareLink(item: PDFHighlightsExport(groups: groups), preview: SharePreview(title)) {
            Label("Export as PDF", systemImage: "doc.richtext")
        }
    }
}
