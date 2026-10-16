import Foundation

/// Turns links to notes into footnotes the reader can show in place.
///
/// Books mark notes in many ways: FB2 notes bodies (`<section id>`), comment lists where a
/// numbered `<subtitle id>` is followed by the note's paragraphs, EPUB `<aside epub:type="footnote">`,
/// or an `<a id>` backlink at the start of the note's paragraph. `resolve` finds the note's
/// text from the element a link points to and remembers it under the link's key.
final class FootnoteResolver {
    private(set) var footnotes: [String: Footnote] = [:]
    private var rejected: Set<String> = []
    private let lookup: (String) -> MarkupNode?

    /// `lookup` returns the element a link key points to.
    init(lookup: @escaping (String) -> MarkupNode?) {
        self.lookup = lookup
    }

    /// Returns `key` if the link is a footnote reference. `explicit` means the markup says so
    /// (FB2 `type="note"`, EPUB `noteref`); otherwise the link text must look like a note mark.
    func resolve(key: String, label: String, explicit: Bool) -> String? {
        if footnotes[key] != nil { return key }
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rejected.contains(key), explicit || Self.isMark(label),
              let node = lookup(key), let text = Self.noteText(at: node, label: label) else {
            rejected.insert(key)
            return nil
        }
        footnotes[key] = Footnote(label: label, text: text)
        return key
    }

    /// "1", "12", "*", "[3]", "4)" — short marks used for footnote references.
    static func isMark(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 6 else { return false }
        let core = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]()."))
        guard !core.isEmpty else { return false }
        return core.allSatisfy { $0.isNumber || "*†‡§¹²³⁴⁵⁶⁷⁸⁹⁰".contains($0) }
    }

    // MARK: - Finding the note's text

    private static let headingNames: Set<String> = ["title", "subtitle", "h1", "h2", "h3", "h4", "h5", "h6", "dt"]
    private static let containerNames: Set<String> = ["section", "aside", "li", "div", "dd", "note", "footnote", "blockquote", "td"]
    private static let blockNames: Set<String> = containerNames.union(["p", "body"])
    private static let maxLength = 4_000

    static func noteText(at node: MarkupNode, label: String) -> String? {
        var text: String
        if headingNames.contains(node.name) {
            // A numbered heading: the note is in the paragraphs that follow it.
            text = followingText(after: node)
        } else if !blockNames.contains(node.name) {
            // An inline anchor (often a backlink) inside the note's paragraph.
            var block = node.parent
            while let current = block, !blockNames.contains(current.name) { block = current.parent }
            guard let block else { return nil }
            text = isMarkOnly(block.textContent, label: label) ? followingText(after: block) : block.textContent
        } else if containerNames.contains(node.name) {
            let parts = node.elements.filter { !headingNames.contains($0.name) }.map(\.textContent).filter { !$0.isEmpty }
            text = parts.isEmpty ? node.textContent : parts.joined(separator: "\n")
        } else {
            text = isMarkOnly(node.textContent, label: label) ? followingText(after: node) : node.textContent
        }
        text = stripMark(text, label: label).trimmingCharacters(in: .whitespacesAndNewlines)
        // Backlinks to the reference ("↩︎") have no use in a popup.
        let backlink = CharacterSet(charactersIn: "↩↑^\u{FE0E}\u{FE0F}").union(.whitespacesAndNewlines)
        var scalars = text.unicodeScalars
        while let last = scalars.last, backlink.contains(last) { scalars.removeLast() }
        text = String(scalars)
        guard !text.isEmpty else { return nil }
        if text.count > maxLength { text = String(text.prefix(maxLength)) + "…" }
        return text
    }

    /// Text of the siblings after `node`, up to the next marked element or heading.
    private static func followingText(after node: MarkupNode) -> String {
        guard let siblings = node.parent?.elements, let index = siblings.firstIndex(where: { $0 === node }) else { return "" }
        var parts: [String] = []
        for sibling in siblings[(index + 1)...] {
            if sibling.name == "empty-line" || sibling.name == "br" { continue }
            if sibling["id"] != nil || headingNames.contains(sibling.name) || sibling.name == "section" { break }
            let text = sibling.textContent
            if !text.isEmpty { parts.append(text) }
            if parts.count >= 12 { break }
        }
        return parts.joined(separator: "\n")
    }

    private static func isMarkOnly(_ text: String, label: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == label || isMark(trimmed)
    }

    /// Drops the note's own number from its start: "60 …" → "…".
    private static func stripMark(_ text: String, label: String) -> String {
        guard !label.isEmpty else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for mark in [label, "[\(label)]", "\(label).", "\(label))"] where trimmed.hasPrefix(mark) {
            let rest = trimmed.dropFirst(mark.count)
            if let next = rest.first, next.isWhitespace || next == "\u{00A0}" || next.isPunctuation && next != "," {
                return String(rest.drop { $0.isWhitespace || $0 == "\u{00A0}" || $0 == "." || $0 == ")" })
            }
            if rest.isEmpty { return "" }
        }
        return trimmed
    }
}
