import SwiftUI
import UniformTypeIdentifiers

enum BookFormat: String, Codable, CaseIterable, Sendable {
    case epub
    case pdf
    case txt

    var displayName: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .txt: String(localized: "Text", comment: "Book format: plain text file")
        }
    }

    var fileExtension: String { rawValue }

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "epub": self = .epub
        case "pdf": self = .pdf
        case "txt", "text", "md": self = .txt
        default:
            guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
            if type.conforms(to: .pdf) { self = .pdf }
            else if type.conforms(to: .epub) { self = .epub }
            else if type.conforms(to: .plainText) { self = .txt }
            else { return nil }
        }
    }

    static var importableTypes: [UTType] { [.epub, .pdf, .plainText] }
}

extension UTType {
    static let epub = UTType(importedAs: "org.idpf.epub-container", conformingTo: .data)
}

enum ReadingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case wantToRead
    case reading
    case finished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wantToRead: String(localized: "Want to Read")
        case .reading: String(localized: "Reading", comment: "Reading status")
        case .finished: String(localized: "Finished", comment: "Reading status")
        }
    }

    var symbol: String {
        switch self {
        case .wantToRead: "bookmark"
        case .reading: "book"
        case .finished: "checkmark.circle"
        }
    }
}

enum HighlightColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow, green, blue, pink, purple

    var id: String { rawValue }

    var name: String {
        switch self {
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        }
    }

    /// Solid swatch color used in UI chrome.
    var color: Color { Color(uiColor: uiColor) }

    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor(red: 0.99, green: 0.80, blue: 0.23, alpha: 1)
        case .green: UIColor(red: 0.45, green: 0.80, blue: 0.47, alpha: 1)
        case .blue: UIColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1)
        case .pink: UIColor(red: 0.98, green: 0.47, blue: 0.62, alpha: 1)
        case .purple: UIColor(red: 0.68, green: 0.52, blue: 0.96, alpha: 1)
        }
    }

    /// Translucent fill drawn behind highlighted text in the reader.
    func fill(isDarkTheme: Bool) -> UIColor {
        uiColor.withAlphaComponent(isDarkTheme ? 0.34 : 0.38)
    }
}

/// A position inside a book. Reflowable formats use chapter/block/offset,
/// fixed-layout PDFs use `page`.
struct ReadingLocator: Codable, Hashable, Sendable {
    var chapter: Int = 0
    var block: Int = 0
    /// UTF-16 offset inside the block's text.
    var offset: Int = 0
    var page: Int = 0

    static let start = ReadingLocator()

    func isBefore(_ other: ReadingLocator) -> Bool {
        if chapter != other.chapter { return chapter < other.chapter }
        if block != other.block { return block < other.block }
        return offset < other.offset
    }
}

/// A text range anchored to content blocks — stable across font, size and layout changes.
struct TextAnchor: Codable, Hashable, Sendable {
    var chapter: Int
    var startBlock: Int
    var startOffset: Int
    var endBlock: Int
    var endOffset: Int

    var startLocator: ReadingLocator {
        ReadingLocator(chapter: chapter, block: startBlock, offset: startOffset)
    }

    func contains(block: Int, offset: Int) -> Bool {
        if block < startBlock || block > endBlock { return false }
        if block == startBlock && offset < startOffset { return false }
        if block == endBlock && offset >= endOffset { return false }
        return true
    }
}
