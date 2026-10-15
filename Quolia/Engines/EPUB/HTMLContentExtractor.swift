import Foundation

/// Converts an (X)HTML document into Quolia content blocks.
/// Publisher CSS is intentionally ignored: the reader applies its own calm,
/// consistent typography, keeping only semantic structure and inline emphasis.
struct HTMLContentExtractor {
    /// Called for every `<img>` to map a document-relative `src` to an image file name.
    var resolveImage: (String) -> String?

    private static let blockElements: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li", "pre", "figure", "figcaption",
        "section", "article", "header", "footer", "aside", "dd", "dt", "tr", "table", "ul", "ol", "dl",
        "address", "center", "body", "main", "hgroup", "caption", "td", "th", "nav", "details", "summary"
    ]
    private static let skippedElements: Set<String> = ["head", "script", "style", "title", "template", "noscript"]

    private enum Context: Equatable {
        case heading(Int), quote, listItem, preformatted, caption
    }

    private struct Builder {
        var blocks: [ContentBlock] = []
        var text = ""
        var length = 0 // UTF-16 length of `text`
        var spans: [InlineSpan] = []
        var lastWasSpace = true
        var contexts: [Context] = []
        var listCounters: [Int?] = [] // nil = unordered

        var preformatted: Bool { contexts.contains(.preformatted) }

        mutating func append(_ raw: String) {
            if preformatted {
                text += raw
                length += raw.utf16.count
                lastWasSpace = raw.last?.isWhitespace ?? lastWasSpace
                return
            }
            var piece = ""
            for char in raw {
                if char.isWhitespace && char != "\u{00A0}" {
                    if !lastWasSpace { piece.append(" "); lastWasSpace = true }
                } else if char == "\u{00AD}" {
                    continue // soft hyphen: the renderer hyphenates on its own
                } else {
                    piece.append(char)
                    lastWasSpace = false
                }
            }
            text += piece
            length += piece.utf16.count
        }

        mutating func lineBreak() {
            // Remove a trailing space before the break.
            if text.hasSuffix(" ") { text.removeLast(); length -= 1 }
            text += "\n"
            length += 1
            lastWasSpace = true
        }

        mutating func flush(page: Int?) {
            // Trim trailing whitespace/newlines.
            while let last = text.last, last.isWhitespace, last != "\u{00A0}" {
                text.removeLast()
                length -= String(last).utf16.count
            }
            // Trim leading whitespace (rare, since leading spaces are suppressed).
            var leading = 0
            while let first = text.first, first.isWhitespace, first != "\u{00A0}" {
                text.removeFirst()
                leading += String(first).utf16.count
            }
            if leading > 0 { length -= leading }

            defer {
                text = ""
                length = 0
                spans = []
                lastWasSpace = true
            }
            guard !text.isEmpty else { return }

            let clipped = spans.compactMap { span -> InlineSpan? in
                let start = max(span.location - leading, 0)
                let end = min(span.location + span.length - leading, length)
                guard end > start else { return nil }
                return InlineSpan(location: start, length: end - start, style: span.style)
            }

            // Headings win over enclosing contexts (e.g. a heading inside a blockquote).
            let headingLevel = contexts.compactMap { context -> Int? in
                if case .heading(let level) = context { return level }
                return nil
            }.last
            let kind: ContentBlock.Kind
            if headingLevel != nil {
                kind = .heading
            } else {
                switch contexts.last {
                case .preformatted: kind = .preformatted
                case .caption: kind = .caption
                case .listItem: kind = .listItem
                case .quote: kind = .quote
                case .heading, nil: kind = .paragraph
                }
            }
            blocks.append(ContentBlock(kind: kind, text: text, level: headingLevel ?? 0, spans: clipped, page: page))
        }
    }

    func extract(from root: MarkupNode, page: Int? = nil) -> [ContentBlock] {
        var builder = Builder()
        let body = root.first("body") ?? root
        walk(body, builder: &builder, page: page)
        builder.flush(page: page)
        return builder.blocks
    }

    private func walk(_ node: MarkupNode, builder: inout Builder, page: Int?) {
        for child in node.children {
            switch child.kind {
            case .text:
                builder.append(child.text)
            case .element:
                element(child, builder: &builder, page: page)
            case .document:
                walk(child, builder: &builder, page: page)
            }
        }
    }

    private func element(_ node: MarkupNode, builder: inout Builder, page: Int?) {
        let name = node.name
        if Self.skippedElements.contains(name) { return }
        if isHidden(node) { return }

        let epubType = node["epub:type"]?.lowercased() ?? node["role"]?.lowercased() ?? ""
        if epubType.contains("pagebreak") || epubType.contains("doc-pagebreak") { return }
        if name == "nav", epubType.contains("toc") || epubType.contains("landmarks") || epubType.contains("page-list") { return }

        switch name {
        case "br":
            builder.lineBreak()
            return
        case "hr":
            builder.flush(page: page)
            builder.blocks.append(ContentBlock(kind: .separator, text: "", page: page))
            return
        case "img", "image":
            let src = node["src"] ?? node["xlink:href"] ?? node["href"]
            if let src, let file = resolveImage(src) {
                builder.flush(page: page)
                builder.blocks.append(ContentBlock(kind: .image, text: "", image: file, page: page))
            }
            return
        case "svg":
            // SVG wrappers are commonly used for cover images.
            for image in node.all("image") { element(image, builder: &builder, page: page) }
            return
        default:
            break
        }

        if Self.blockElements.contains(name) {
            builder.flush(page: page)
            var pushedContext = false
            var pushedList = false
            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                builder.contexts.append(.heading(Int(name.dropFirst()) ?? 2)); pushedContext = true
            case "blockquote":
                builder.contexts.append(.quote); pushedContext = true
            case "pre":
                builder.contexts.append(.preformatted); pushedContext = true
            case "figcaption", "caption":
                builder.contexts.append(.caption); pushedContext = true
            case "ul":
                builder.listCounters.append(nil); pushedList = true
            case "ol":
                builder.listCounters.append(Int(node["start"] ?? "") ?? 1); pushedList = true
            case "li":
                builder.contexts.append(.listItem); pushedContext = true
                if let last = builder.listCounters.last, let number = last {
                    builder.append("\(number).\u{00A0}")
                    builder.listCounters[builder.listCounters.count - 1] = number + 1
                } else {
                    builder.append("•\u{00A0}")
                }
            default:
                break
            }
            walk(node, builder: &builder, page: page)
            builder.flush(page: page)
            if pushedContext { builder.contexts.removeLast() }
            if pushedList { builder.listCounters.removeLast() }
            return
        }

        // Inline element
        let style = inlineStyle(for: node)
        let start = builder.length
        walk(node, builder: &builder, page: page)
        if let style, builder.length > start {
            builder.spans.append(InlineSpan(location: start, length: builder.length - start, style: style))
        }
    }

    private func inlineStyle(for node: MarkupNode) -> InlineSpan.Style? {
        switch node.name {
        case "em", "i", "cite", "dfn", "var": return .italic
        case "strong", "b": return .bold
        case "code", "kbd", "samp", "tt": return .code
        case "sup": return .superscript
        default:
            guard let css = node["style"]?.lowercased().replacingOccurrences(of: " ", with: "") else { return nil }
            if css.contains("font-style:italic") { return .italic }
            if css.contains("font-weight:bold") || css.contains("font-weight:700") { return .bold }
            return nil
        }
    }

    private func isHidden(_ node: MarkupNode) -> Bool {
        if node.attributes["hidden"] != nil { return true }
        if let css = node["style"]?.lowercased().replacingOccurrences(of: " ", with: ""),
           css.contains("display:none") || css.contains("visibility:hidden") {
            return true
        }
        return false
    }
}
