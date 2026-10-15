import Foundation
import SwiftData

/// Imports EPUB, PDF and TXT files from Files, iCloud Drive, AirDrop or the Share Sheet.
@MainActor
final class BookImporter {
    struct Outcome {
        var imported: [Book] = []
        var duplicates: [String] = []
        var failures: [(name: String, message: String)] = []

        var summary: String? {
            var parts: [String] = []
            if imported.count == 1 {
                parts.append(String(localized: "Added “\(imported[0].title)”"))
            } else if imported.count > 1 {
                parts.append(String(localized: "Added \(imported.count) books"))
            }
            if duplicates.count == 1 {
                parts.append(String(localized: "“\(duplicates[0])” is already in your library"))
            } else if duplicates.count > 1 {
                parts.append(String(localized: "\(duplicates.count) books were already in your library"))
            }
            if let failure = failures.first { parts.append(String(localized: "Couldn't import \(failure.name): \(failure.message)")) }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
    }

    private struct Parsed: Sendable {
        var title: String
        var author: String
        var language: String?
        var cover: Data?
        var totalWords: Int
        var chapterCount: Int
        var pageCount: Int
        var content: BookContent
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func importBooks(from urls: [URL]) async -> Outcome {
        var outcome = Outcome()
        for url in urls {
            do {
                if let book = try await importBook(from: url) {
                    outcome.imported.append(book)
                } else {
                    outcome.duplicates.append(url.deletingPathExtension().lastPathComponent)
                }
            } catch {
                outcome.failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }
        if !outcome.imported.isEmpty { Haptics.success() }
        return outcome
    }

    /// Returns `nil` when the book is already in the library.
    func importBook(from url: URL) async throws -> Book? {
        guard let format = BookFormat(url: url) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: String(localized: "Only EPUB, PDF and TXT files are supported.")])
        }

        // Copy into a private temp location so security-scoped access can end quickly.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        try FileManager.default.copyItem(at: url, to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let fileSize = (try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let bookID = UUID()
        let fallbackName = url.deletingPathExtension().lastPathComponent

        let parsed = try await Task.detached(priority: .userInitiated) {
            try Self.parse(url: temp, format: format, bookID: bookID, fallbackName: fallbackName)
        }.value

        if isDuplicate(title: parsed.title, author: parsed.author, format: format, size: fileSize) {
            ContentCache.remove(bookID)
            return nil
        }

        let fileName = try BookFileStore.shared.store(fileAt: temp, format: format)
        ContentCache.save(parsed.content, for: bookID)

        let book = Book(title: parsed.title, author: parsed.author, format: format, fileName: fileName)
        book.id = bookID
        book.fileSize = fileSize
        book.language = parsed.language
        book.coverImageData = parsed.cover
        book.totalWords = parsed.totalWords
        book.chapterCount = parsed.chapterCount
        book.pageCount = parsed.pageCount
        context.insert(book)
        try? context.save()
        return book
    }

    private func isDuplicate(title: String, author: String, format: BookFormat, size: Int64) -> Bool {
        let formatRaw = format.rawValue
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.title == title && $0.author == author && $0.formatRaw == formatRaw })
        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.contains { $0.fileSize == size || size == 0 }
    }

    nonisolated private static func parse(url: URL, format: BookFormat, bookID: UUID, fallbackName: String) throws -> Parsed {
        switch format {
        case .epub:
            let parser = try EPUBParser(url: url, imagesDirectory: ContentCache.imagesDirectory(for: bookID))
            let result = try parser.parse()
            var content = result.content
            if content.title == "Untitled" || content.title == String(localized: "Untitled") { content.title = fallbackName }
            return Parsed(
                title: content.title,
                author: content.author,
                language: LanguageDetector.language(for: content),
                cover: result.coverData.flatMap { ImageDownsampler.jpegData(from: $0, maxPixelSize: 900) },
                totalWords: content.totalWords,
                chapterCount: content.chapters.count,
                pageCount: ReadingMath.pages(forWords: content.totalWords),
                content: content
            )
        case .txt:
            let content = try PlainTextParser.parse(url: url)
            var named = content
            let names = PlainTextParser.titleAndAuthor(fromFileName: fallbackName)
            named.title = names.0
            named.author = names.1
            return Parsed(title: named.title, author: named.author, language: content.language, cover: nil,
                          totalWords: content.totalWords, chapterCount: content.chapters.count,
                          pageCount: ReadingMath.pages(forWords: content.totalWords), content: named)
        case .pdf:
            let metadata = try PDFBookParser.metadata(url: url, fallbackName: fallbackName)
            var extracted = try PDFBookParser.extractContent(url: url, title: metadata.title, author: metadata.author, allowOCR: false)
            if extracted.needsOCR { extracted.content.language = BookContent.ocrPlaceholderMarker }
            return Parsed(title: metadata.title, author: metadata.author,
                          language: extracted.content.isOCRPlaceholder ? nil : extracted.content.language,
                          cover: metadata.coverData, totalWords: extracted.content.totalWords,
                          chapterCount: extracted.content.chapters.count, pageCount: metadata.pageCount,
                          content: extracted.content)
        }
    }

    /// Imports the bundled sample book.
    func importSampleBook() async -> Outcome {
        guard let url = Bundle.main.url(forResource: "On Reading Slowly", withExtension: "epub") else {
            return Outcome(failures: [(String(localized: "Sample book"), String(localized: "The sample book is missing from the app."))])
        }
        return await importBooks(from: [url])
    }
}

extension BookImporter {
    /// Removes a book, its file and cached content.
    static func delete(_ book: Book, context: ModelContext) {
        BookFileStore.shared.delete(fileName: book.fileName)
        ContentCache.remove(book.id)
        let id = book.id
        Task { await ContentLoader.shared.invalidate(id) }
        context.delete(book)
        try? context.save()
    }
}
