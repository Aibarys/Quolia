import Foundation

/// Removes the ads that download sites add to the start or end of books
/// ("Спасибо, что скачали книгу в бесплатной электронной библиотеке…", "Все книги автора").
///
/// Only short paragraphs near the start or end of the book are considered, and only runs that
/// contain a clear marker. Removed blocks become `.omitted` placeholders, so block indices
/// (and highlights anchored to them) stay the same. "Конец ознакомительного фрагмента" is kept:
/// it tells the reader the text is incomplete.
enum LibraryBoilerplate {
    /// Phrases that only appear in site ads.
    private static let markers = [
        "скачали книгу", "электронной библиотеке", "электронной библиотеки", "полную легальную версию",
        "купив полную версию", "текст предоставлен ооо", "текст предоставлен правообладателем",
        "thank you for downloading", "downloaded from",
    ]
    /// Short lines that accompany those ads.
    private static let companions: Set<String> = [
        "все книги автора", "эта же книга в других форматах", "приятного чтения", "оставить отзыв о книге",
        "перейти на страницу книги", "читать онлайн", "скачать книгу", "купить книгу",
    ]
    private static let window = 15
    private static let maxLength = 260

    static func clean(_ content: inout BookContent) {
        guard !content.chapters.isEmpty else { return }
        clean(&content.chapters[0].blocks, fromStart: true)
        clean(&content.chapters[content.chapters.count - 1].blocks, fromStart: false)
    }

    private static func clean(_ blocks: inout [ContentBlock], fromStart: Bool) {
        let indices = fromStart ? Array(blocks.indices.prefix(window)) : Array(blocks.indices.suffix(window))
        let kinds = indices.map { classify(blocks[$0]) }
        for (position, kind) in kinds.enumerated() where kind == .marker {
            // Extend over neighbouring ad lines.
            var low = position, high = position
            while low > 0, kinds[low - 1] != .text { low -= 1 }
            while high < kinds.count - 1, kinds[high + 1] != .text { high += 1 }
            for index in indices[low...high] where blocks[index].kind != .omitted { blocks[index] = .omitted }
        }
    }

    private enum Kind { case marker, companion, text }

    private static func classify(_ block: ContentBlock) -> Kind {
        guard block.kind == .paragraph || block.kind == .caption || block.kind == .heading else {
            return block.kind == .omitted ? .companion : .text
        }
        guard block.text.count <= maxLength else { return .text }
        let normalized = block.text.lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if markers.contains(where: normalized.contains) { return .marker }
        return companions.contains(normalized) ? .companion : .text
    }
}
