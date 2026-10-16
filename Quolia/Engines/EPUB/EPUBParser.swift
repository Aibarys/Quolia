import Foundation

/// Parses EPUB 2 and EPUB 3 books into `BookContent`.
struct EPUBParser {
    struct ManifestItem {
        let id: String
        let path: String // resolved path inside the archive
        let mediaType: String
        let properties: String
    }

    struct TOCEntry {
        let title: String
        let path: String // archive path without fragment
        let depth: Int
    }

    enum EPUBError: LocalizedError {
        case missingContainer
        case missingPackage
        case emptyBook

        var errorDescription: String? {
            switch self {
            case .missingContainer: String(localized: "This EPUB is missing its container description.")
            case .missingPackage: String(localized: "This EPUB's package file could not be read.")
            case .emptyBook: String(localized: "This book doesn't contain any readable text.")
            }
        }
    }

    struct Result {
        var content: BookContent
        var coverData: Data?
    }

    let archive: ZipArchive
    /// Directory where extracted images are written.
    let imagesDirectory: URL

    init(url: URL, imagesDirectory: URL) throws {
        self.archive = try ZipArchive(url: url)
        self.imagesDirectory = imagesDirectory
    }

    func parse() throws -> Result {
        let opfPath = try packagePath()
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        let package = MarkupParser.parse(try archive.data(for: opfPath))

        guard let packageNode = package.first("package") else { throw EPUBError.missingPackage }

        // Metadata
        let metadata = packageNode.child("metadata") ?? packageNode.first("metadata")
        let title = metadata?.first("title")?.textContent.nonEmpty ?? "Untitled"
        let creators = metadata?.all("creator").map(\.textContent).filter { !$0.isEmpty } ?? []
        let language = metadata?.first("language")?.textContent.nonEmpty

        // Manifest
        var manifest: [String: ManifestItem] = [:]
        for item in packageNode.first("manifest")?.all("item") ?? [] {
            guard let id = item["id"], let href = item["href"] else { continue }
            manifest[id] = ManifestItem(
                id: id,
                path: Self.resolve(href, relativeTo: opfDir),
                mediaType: item["media-type"]?.lowercased() ?? "",
                properties: item["properties"]?.lowercased() ?? ""
            )
        }

        // Spine
        let spineNode = packageNode.first("spine")
        let spine: [ManifestItem] = (spineNode?.all("itemref") ?? []).compactMap { ref in
            guard let idref = ref["idref"], let item = manifest[idref] else { return nil }
            if ref["linear"]?.lowercased() == "no" { return nil }
            guard item.mediaType.contains("html") || item.path.hasSuffix("html") || item.path.hasSuffix("htm") else { return nil }
            return item
        }

        // Table of contents
        var toc = navTOC(manifest: manifest)
        if toc.isEmpty, let ncxID = spineNode?["toc"], let ncx = manifest[ncxID] {
            toc = ncxTOC(path: ncx.path)
        }
        if toc.isEmpty, let ncx = manifest.values.first(where: { $0.mediaType.contains("ncx") }) {
            toc = ncxTOC(path: ncx.path)
        }

        // Cover
        let coverItem = coverManifestItem(metadata: metadata, manifest: manifest)
        let coverData = coverItem.flatMap { try? archive.data(for: $0.path) }

        // Content
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        var extractedImages: [String: String] = [:]
        var chapters: [Chapter] = []
        let tocByPath = Dictionary(toc.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let documents = NoteDocuments(archive: archive)
        let footnotes = FootnoteResolver(lookup: documents.element)

        for (spineIndex, item) in spine.enumerated() {
            guard let data = try? archive.data(for: item.path) else { continue }
            let documentDir = (item.path as NSString).deletingLastPathComponent
            let root = MarkupParser.parse(data)
            documents.setCurrent(root, path: item.path)
            let extractor = HTMLContentExtractor(resolveImage: { src in
                let path = Self.resolve(src, relativeTo: documentDir)
                if let existing = extractedImages[path] { return existing }
                guard let imageData = try? archive.data(for: path) else { return nil }
                let ext = (path as NSString).pathExtension.lowercased()
                let fileName = "img\(extractedImages.count).\(ext.isEmpty ? "img" : ext)"
                try? imageData.write(to: imagesDirectory.appendingPathComponent(fileName))
                extractedImages[path] = fileName
                return fileName
            }, resolveNote: { href, label, explicit in
                guard let hash = href.firstIndex(of: "#") else { return nil }
                let fragment = String(href[href.index(after: hash)...])
                let path = hash == href.startIndex ? item.path : Self.resolve(href, relativeTo: documentDir)
                guard !fragment.isEmpty else { return nil }
                return footnotes.resolve(key: "\(path)#\(fragment)", label: label, explicit: explicit)
            })
            var blocks = extractor.extract(from: root)

            // Skip a cover page that only repeats the cover image.
            let words = blocks.reduce(0) { $0 + $1.wordCount }
            if spineIndex == 0, words == 0, !toc.contains(where: { $0.path == item.path }) { continue }
            if blocks.isEmpty { continue }

            if let entry = tocByPath[item.path] {
                chapters.append(Chapter(id: chapters.count, title: entry.title, blocks: blocks))
            } else if !toc.isEmpty, var previous = chapters.popLast() {
                // A file without a TOC entry continues the previous chapter (split files).
                previous.blocks.append(contentsOf: blocks)
                chapters.append(previous)
            } else {
                let heading = blocks.first(where: { $0.kind == .heading })?.text
                let fallback = heading.map { String($0.prefix(80)) } ?? String(localized: "Section \(chapters.count + 1)")
                if words == 0 { blocks = blocks.filter { $0.kind == .image } }
                chapters.append(Chapter(id: chapters.count, title: fallback, blocks: blocks))
            }
        }

        guard !chapters.isEmpty else { throw EPUBError.emptyBook }

        var content = BookContent(
            title: title,
            author: creators.joined(separator: ", "),
            language: language,
            chapters: chapters
        )
        content.footnotes = footnotes.footnotes
        LibraryBoilerplate.clean(&content)
        return Result(content: content, coverData: coverData)
    }

    // MARK: - Package

    private func packagePath() throws -> String {
        guard let container = try? archive.data(for: "META-INF/container.xml") else {
            // Some broken books omit the container — fall back to the first OPF.
            if let opf = archive.paths.first(where: { $0.lowercased().hasSuffix(".opf") }) { return opf }
            throw EPUBError.missingContainer
        }
        let root = MarkupParser.parse(container)
        guard let path = root.first("rootfile")?["full-path"] else { throw EPUBError.missingPackage }
        return path
    }

    private func coverManifestItem(metadata: MarkupNode?, manifest: [String: ManifestItem]) -> ManifestItem? {
        if let item = manifest.values.first(where: { $0.properties.contains("cover-image") }) { return item }
        if let meta = metadata?.all("meta").first(where: { $0["name"]?.lowercased() == "cover" }),
           let id = meta["content"], let item = manifest[id], item.mediaType.hasPrefix("image") {
            return item
        }
        return manifest.values.first {
            $0.mediaType.hasPrefix("image") && ($0.id.lowercased().contains("cover") || $0.path.lowercased().contains("cover"))
        }
    }

    // MARK: - Table of contents

    private func navTOC(manifest: [String: ManifestItem]) -> [TOCEntry] {
        guard let navItem = manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") }),
              let data = try? archive.data(for: navItem.path) else { return [] }
        let root = MarkupParser.parse(data)
        let navs = root.all("nav")
        guard let nav = navs.first(where: { ($0["epub:type"] ?? "").contains("toc") }) ?? navs.first,
              let list = nav.first("ol") else { return [] }
        let baseDir = (navItem.path as NSString).deletingLastPathComponent
        var entries: [TOCEntry] = []
        collectNav(list, depth: 0, baseDir: baseDir, into: &entries)
        return entries
    }

    private func collectNav(_ list: MarkupNode, depth: Int, baseDir: String, into entries: inout [TOCEntry]) {
        for li in list.elements where li.name == "li" {
            if let link = li.child("a") ?? li.first("a"), let href = link["href"] {
                let title = link.textContent
                if !title.isEmpty {
                    entries.append(TOCEntry(title: title, path: Self.resolve(href, relativeTo: baseDir), depth: depth))
                }
            } else if let span = li.child("span"), !span.textContent.isEmpty, let nested = li.child("ol"),
                      let firstHref = nested.first("a")?["href"] {
                entries.append(TOCEntry(title: span.textContent, path: Self.resolve(firstHref, relativeTo: baseDir), depth: depth))
            }
            if let nested = li.child("ol") {
                collectNav(nested, depth: depth + 1, baseDir: baseDir, into: &entries)
            }
        }
    }

    private func ncxTOC(path: String) -> [TOCEntry] {
        guard let data = try? archive.data(for: path) else { return [] }
        let root = MarkupParser.parse(data)
        guard let navMap = root.first("navmap") else { return [] }
        let baseDir = (path as NSString).deletingLastPathComponent
        var entries: [TOCEntry] = []
        collectNCX(navMap, depth: 0, baseDir: baseDir, into: &entries)
        return entries
    }

    private func collectNCX(_ node: MarkupNode, depth: Int, baseDir: String, into entries: inout [TOCEntry]) {
        for point in node.elements where point.name == "navpoint" {
            let title = point.child("navlabel")?.first("text")?.textContent ?? ""
            if let src = point.child("content")?["src"], !title.isEmpty {
                entries.append(TOCEntry(title: title, path: Self.resolve(src, relativeTo: baseDir), depth: depth))
            }
            collectNCX(point, depth: depth + 1, baseDir: baseDir, into: &entries)
        }
    }

    // MARK: - Paths

    /// Resolves an href relative to a directory inside the archive, dropping fragments
    /// and normalizing `.` / `..` segments.
    static func resolve(_ href: String, relativeTo base: String) -> String {
        var clean = href
        if let hash = clean.firstIndex(of: "#") { clean = String(clean[..<hash]) }
        clean = clean.removingPercentEncoding ?? clean
        let combined = clean.hasPrefix("/") ? String(clean.dropFirst()) : (base.isEmpty ? clean : base + "/" + clean)
        var parts: [Substring] = []
        for part in combined.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(part)
        }
        return parts.joined(separator: "/")
    }
}

/// Finds elements by "path#id" across the book's documents, for footnote lookup.
/// Keeps the document being extracted plus a few others (notes usually live in one or two files).
private final class NoteDocuments {
    private let archive: ZipArchive
    private var current: (path: String, root: MarkupNode)?
    /// Roots are kept alongside the index: nodes only hold their parents weakly.
    private var cache: [String: (root: MarkupNode, ids: [String: MarkupNode])] = [:]
    private var currentIDs: [String: MarkupNode]?

    init(archive: ZipArchive) {
        self.archive = archive
    }

    func setCurrent(_ root: MarkupNode, path: String) {
        current = (path, root)
        currentIDs = nil
    }

    func element(_ key: String) -> MarkupNode? {
        guard let hash = key.lastIndex(of: "#") else { return nil }
        let path = String(key[..<hash]), id = String(key[key.index(after: hash)...])
        if let current, current.path == path {
            if currentIDs == nil { currentIDs = Self.index(current.root) }
            return currentIDs?[id]
        }
        if cache[path] == nil {
            if cache.count >= 8 { cache.removeAll() }
            guard let data = try? archive.data(for: path) else { return nil }
            let root = MarkupParser.parse(data)
            cache[path] = (root, Self.index(root))
        }
        return cache[path]?.ids[id]
    }

    private static func index(_ root: MarkupNode) -> [String: MarkupNode] {
        var result: [String: MarkupNode] = [:]
        var stack = [root]
        while let node = stack.popLast() {
            for element in node.elements {
                if let id = element["id"], result[id] == nil { result[id] = element }
                stack.append(element)
            }
        }
        return result
    }
}

extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
