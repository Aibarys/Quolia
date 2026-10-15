import Foundation

/// A tiny DOM node produced by `MarkupParser`.
final class MarkupNode {
    enum Kind { case document, element, text }

    let kind: Kind
    /// Lowercased local name without namespace prefix (e.g. `title` for `dc:title`).
    let name: String
    /// Lowercased qualified name (e.g. `dc:title`).
    let qualifiedName: String
    /// Attribute names are lowercased and keep their prefix (`epub:type`, `xlink:href`).
    let attributes: [String: String]
    let text: String
    private(set) var children: [MarkupNode] = []
    private(set) weak var parent: MarkupNode?

    init(kind: Kind, qualifiedName: String = "", attributes: [String: String] = [:], text: String = "") {
        self.kind = kind
        let lower = qualifiedName.lowercased()
        self.qualifiedName = lower
        self.name = lower.split(separator: ":").last.map(String.init) ?? lower
        self.attributes = attributes
        self.text = text
    }

    func append(_ child: MarkupNode) {
        child.parent = self
        children.append(child)
    }

    subscript(attribute: String) -> String? {
        if let value = attributes[attribute] { return value }
        // Match regardless of namespace prefix.
        return attributes.first { $0.key.split(separator: ":").last.map(String.init) == attribute }?.value
    }

    var elements: [MarkupNode] { children.filter { $0.kind == .element } }

    func first(_ name: String) -> MarkupNode? {
        for child in children where child.kind == .element {
            if child.name == name { return child }
            if let found = child.first(name) { return found }
        }
        return nil
    }

    func all(_ name: String) -> [MarkupNode] {
        var result: [MarkupNode] = []
        collect(name, into: &result)
        return result
    }

    private func collect(_ name: String, into result: inout [MarkupNode]) {
        for child in children where child.kind == .element {
            if child.name == name { result.append(child) }
            child.collect(name, into: &result)
        }
    }

    func child(_ name: String) -> MarkupNode? {
        children.first { $0.kind == .element && $0.name == name }
    }

    /// Concatenated text content of all descendants, whitespace-collapsed.
    var textContent: String {
        var raw = ""
        appendText(into: &raw)
        return raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func appendText(into result: inout String) {
        if kind == .text { result += text; return }
        for child in children { child.appendText(into: &result) }
    }
}

/// Forgiving HTML/XML tokenizer that builds a `MarkupNode` tree.
/// It never throws: malformed markup is repaired the way browsers do it.
enum MarkupParser {
    private static let voidElements: Set<String> = [
        "br", "img", "hr", "meta", "link", "input", "col", "area", "base", "wbr", "source", "embed", "param", "track"
    ]
    private static let rawTextElements: Set<String> = ["script", "style"]

    static func parse(_ data: Data) -> MarkupNode {
        parse(bytes: [UInt8](data))
    }

    static func parse(_ string: String) -> MarkupNode {
        parse(bytes: Array(string.utf8))
    }

    private static func parse(bytes: [UInt8]) -> MarkupNode {
        let root = MarkupNode(kind: .document)
        var stack: [MarkupNode] = [root]
        let n = bytes.count
        var i = 0
        var textStart = 0

        func flushText(upTo end: Int) {
            guard end > textStart else { return }
            let raw = String(decoding: bytes[textStart..<end], as: UTF8.self)
            stack[stack.count - 1].append(MarkupNode(kind: .text, text: decodeEntities(raw)))
        }

        func hasPrefix(_ prefix: String, at index: Int) -> Bool {
            let p = Array(prefix.utf8)
            guard index + p.count <= n else { return false }
            for k in 0..<p.count where bytes[index + k] != p[k] { return false }
            return true
        }

        func find(_ needle: String, from index: Int) -> Int? {
            let p = Array(needle.utf8)
            guard !p.isEmpty, n >= p.count else { return nil }
            var j = index
            while j <= n - p.count {
                if bytes[j] == p[0] {
                    var match = true
                    for k in 1..<p.count where bytes[j + k] != p[k] { match = false; break }
                    if match { return j }
                }
                j += 1
            }
            return nil
        }

        while i < n {
            guard bytes[i] == UInt8(ascii: "<") else { i += 1; continue }

            if hasPrefix("<!--", at: i) {
                flushText(upTo: i)
                i = (find("-->", from: i + 4).map { $0 + 3 }) ?? n
                textStart = i
                continue
            }
            if hasPrefix("<![CDATA[", at: i) {
                flushText(upTo: i)
                let end = find("]]>", from: i + 9) ?? n
                let raw = String(decoding: bytes[(i + 9)..<end], as: UTF8.self)
                stack[stack.count - 1].append(MarkupNode(kind: .text, text: raw))
                i = min(end + 3, n)
                textStart = i
                continue
            }
            if i + 1 < n, bytes[i + 1] == UInt8(ascii: "!") || bytes[i + 1] == UInt8(ascii: "?") {
                flushText(upTo: i)
                i = (find(">", from: i).map { $0 + 1 }) ?? n
                textStart = i
                continue
            }
            if i + 1 < n, bytes[i + 1] == UInt8(ascii: "/") {
                // Closing tag
                flushText(upTo: i)
                let close = find(">", from: i) ?? n
                let name = String(decoding: bytes[(i + 2)..<close], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let matchIndex = stack.lastIndex(where: { $0.qualifiedName == name }), matchIndex > 0 {
                    stack.removeSubrange(matchIndex...)
                }
                i = min(close + 1, n)
                textStart = i
                continue
            }
            if i + 1 < n, isNameStart(bytes[i + 1]) {
                flushText(upTo: i)
                guard let (node, selfClosing, end) = parseTag(bytes, from: i) else { i += 1; continue }
                stack[stack.count - 1].append(node)
                i = end
                if rawTextElements.contains(node.name) {
                    // Skip contents of script/style entirely.
                    let closing = find("</\(node.qualifiedName)", from: i) ?? n
                    i = (find(">", from: closing).map { $0 + 1 }) ?? n
                } else if !selfClosing && !voidElements.contains(node.name) {
                    stack.append(node)
                }
                textStart = i
                continue
            }
            i += 1
        }
        flushText(upTo: n)
        return root
    }

    private static func isNameStart(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == UInt8(ascii: "_")
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12
    }

    /// Parses `<name attr="v" ...>` starting at `start` (pointing at `<`).
    private static func parseTag(_ b: [UInt8], from start: Int) -> (MarkupNode, Bool, Int)? {
        let n = b.count
        var i = start + 1
        let nameStart = i
        while i < n, !isWhitespace(b[i]), b[i] != UInt8(ascii: ">"), b[i] != UInt8(ascii: "/") { i += 1 }
        let name = String(decoding: b[nameStart..<i], as: UTF8.self)
        var attributes: [String: String] = [:]
        var selfClosing = false

        while i < n {
            while i < n, isWhitespace(b[i]) { i += 1 }
            guard i < n else { break }
            if b[i] == UInt8(ascii: ">") { i += 1; return (MarkupNode(kind: .element, qualifiedName: name, attributes: attributes), selfClosing, i) }
            if b[i] == UInt8(ascii: "/") { selfClosing = true; i += 1; continue }

            let keyStart = i
            while i < n, !isWhitespace(b[i]), b[i] != UInt8(ascii: "="), b[i] != UInt8(ascii: ">"), b[i] != UInt8(ascii: "/") { i += 1 }
            let key = String(decoding: b[keyStart..<i], as: UTF8.self).lowercased()
            while i < n, isWhitespace(b[i]) { i += 1 }
            var value = ""
            if i < n, b[i] == UInt8(ascii: "=") {
                i += 1
                while i < n, isWhitespace(b[i]) { i += 1 }
                if i < n, b[i] == UInt8(ascii: "\"") || b[i] == UInt8(ascii: "'") {
                    let quote = b[i]
                    i += 1
                    let valueStart = i
                    while i < n, b[i] != quote { i += 1 }
                    value = String(decoding: b[valueStart..<min(i, n)], as: UTF8.self)
                    i += 1
                } else {
                    let valueStart = i
                    while i < n, !isWhitespace(b[i]), b[i] != UInt8(ascii: ">") { i += 1 }
                    value = String(decoding: b[valueStart..<i], as: UTF8.self)
                }
            }
            if !key.isEmpty { attributes[key] = decodeEntities(value) }
        }
        return (MarkupNode(kind: .element, qualifiedName: name, attributes: attributes), selfClosing, n)
    }

    // MARK: - Entities

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex
        while index < string.endIndex {
            let char = string[index]
            guard char == "&", let semicolon = string[index...].prefix(12).firstIndex(of: ";") else {
                result.append(char)
                index = string.index(after: index)
                continue
            }
            let entity = string[string.index(after: index)..<semicolon]
            if let decoded = decode(entity: entity) {
                result += decoded
                index = string.index(after: semicolon)
            } else {
                result.append(char)
                index = string.index(after: index)
            }
        }
        return result
    }

    private static func decode(entity: Substring) -> String? {
        if entity.hasPrefix("#") {
            let body = entity.dropFirst()
            let value: UInt32?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                value = UInt32(body.dropFirst(), radix: 16)
            } else {
                value = UInt32(body, radix: 10)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return namedEntities[String(entity)]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "zwnj": "\u{200C}", "zwj": "\u{200D}", "shy": "\u{00AD}",
        "mdash": "—", "ndash": "–", "hellip": "…", "minus": "−",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "bull": "•", "middot": "·", "prime": "′", "Prime": "″", "dagger": "†", "Dagger": "‡",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶", "deg": "°",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup1": "¹", "sup2": "²", "sup3": "³", "micro": "µ",
        "cent": "¢", "pound": "£", "euro": "€", "yen": "¥", "curren": "¤",
        "iexcl": "¡", "iquest": "¿", "ordf": "ª", "ordm": "º",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å", "aelig": "æ",
        "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
        "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "ntilde": "ñ",
        "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "yuml": "ÿ", "szlig": "ß",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å", "AElig": "Æ",
        "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë",
        "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï", "Ntilde": "Ñ",
        "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø",
        "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "Yacute": "Ý",
        "oelig": "œ", "OElig": "Œ", "scaron": "š", "Scaron": "Š",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "pi": "π", "sigma": "σ", "omega": "ω",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔",
    ]
}
