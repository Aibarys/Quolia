import Foundation

/// A Sendable description of a book, used to load content off the main thread.
struct BookSource: Sendable, Hashable {
    let id: UUID
    let format: BookFormat
    let fileName: String
    let title: String
    let author: String

    init(book: Book) {
        id = book.id
        format = book.format
        fileName = book.fileName
        title = book.title
        author = book.author
    }

    init(id: UUID, format: BookFormat, fileName: String, title: String, author: String) {
        self.id = id
        self.format = format
        self.fileName = fileName
        self.title = title
        self.author = author
    }
}

/// On-disk cache of parsed content. Parsing happens once per book per device.
enum ContentCache {
    static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Content", isDirectory: true)
    }

    static func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func imagesDirectory(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("images", isDirectory: true)
    }

    private static func contentURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("content-v\(BookContent.schemaVersion).json")
    }

    static func load(_ id: UUID) -> BookContent? {
        guard let data = try? Data(contentsOf: contentURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(BookContent.self, from: data)
    }

    static func save(_ content: BookContent, for id: UUID) {
        let directory = directory(for: id)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(content) {
            try? data.write(to: contentURL(for: id), options: .atomic)
        }
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }
}

/// Loads `BookContent` for a book: memory → disk cache → parse.
actor ContentLoader {
    static let shared = ContentLoader()

    private var memory: [UUID: BookContent] = [:]
    private var order: [UUID] = []

    func content(for source: BookSource, allowOCR: Bool = false,
                 progress: (@Sendable (Double) -> Void)? = nil) async throws -> BookContent {
        if let cached = memory[source.id] { return cached }
        if let disk = ContentCache.load(source.id), !(allowOCR && disk.isOCRPlaceholder) {
            remember(disk, for: source.id)
            return disk
        }
        let url = try await BookFileStore.shared.availableURL(for: source.fileName)
        let content = try Self.parse(source: source, url: url, allowOCR: allowOCR, progress: progress)
        ContentCache.save(content, for: source.id)
        remember(content, for: source.id)
        return content
    }

    func invalidate(_ id: UUID) {
        memory[id] = nil
        order.removeAll { $0 == id }
    }

    private func remember(_ content: BookContent, for id: UUID) {
        memory[id] = content
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > 3 { memory[order.removeFirst()] = nil }
    }

    static func parse(source: BookSource, url: URL, allowOCR: Bool,
                      progress: (@Sendable (Double) -> Void)? = nil) throws -> BookContent {
        switch source.format {
        case .epub:
            let parser = try EPUBParser(url: url, imagesDirectory: ContentCache.imagesDirectory(for: source.id))
            return try parser.parse().content
        case .fb2:
            return try FB2Parser.parse(url: url, imagesDirectory: ContentCache.imagesDirectory(for: source.id)).content
        case .txt:
            var content = try PlainTextParser.parse(url: url)
            content.title = source.title.isEmpty ? content.title : source.title
            content.author = source.author.isEmpty ? content.author : source.author
            return content
        case .pdf:
            var result = try PDFBookParser.extractContent(url: url, title: source.title, author: source.author,
                                                          allowOCR: allowOCR, progress: progress)
            if result.needsOCR { result.content.language = BookContent.ocrPlaceholderMarker }
            return result.content
        }
    }
}

extension BookContent {
    static let ocrPlaceholderMarker = "x-needs-ocr"
    /// True for scanned PDFs whose text hasn't been recognized yet.
    var isOCRPlaceholder: Bool { language == Self.ocrPlaceholderMarker }
}
