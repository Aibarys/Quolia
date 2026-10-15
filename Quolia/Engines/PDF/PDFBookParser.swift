import Foundation
import PDFKit
import Vision
import UIKit

/// Reads PDFs: metadata and cover for the library, and a reflowable text
/// representation (with OCR for scanned pages) for reflow mode, search, stats and AI.
struct PDFBookParser {
    struct Metadata {
        var title: String
        var author: String
        var pageCount: Int
        var coverData: Data?
    }

    enum PDFError: LocalizedError {
        case unreadable
        case locked
        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "This PDF couldn't be opened.")
            case .locked: String(localized: "This PDF is password protected.")
            }
        }
    }

    static let pagesPerSyntheticChapter = 10

    /// - Parameter fallbackName: The original file name, used when the PDF has no title metadata.
    static func metadata(url: URL, fallbackName: String? = nil) throws -> Metadata {
        guard let document = PDFDocument(url: url) else { throw PDFError.unreadable }
        if document.isLocked { throw PDFError.locked }
        let attributes = document.documentAttributes ?? [:]
        let fileTitle = PlainTextParser.titleAndAuthor(fromFileName: fallbackName ?? url.deletingPathExtension().lastPathComponent)
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?.nonEmpty ?? fileTitle.0
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?.nonEmpty ?? fileTitle.1
        var cover: Data?
        if let page = document.page(at: 0) {
            let image = page.thumbnail(of: CGSize(width: 600, height: 900), for: .mediaBox)
            cover = image.jpegData(compressionQuality: 0.85)
        }
        return Metadata(title: title, author: author, pageCount: document.pageCount, coverData: cover)
    }

    /// Extracts reflowable text. Pages without a text layer are OCR'd when `allowOCR` is true.
    static func extractContent(
        url: URL,
        title: String,
        author: String,
        allowOCR: Bool,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> (content: BookContent, needsOCR: Bool) {
        guard let document = PDFDocument(url: url) else { throw PDFError.unreadable }
        if document.isLocked { throw PDFError.locked }

        var pageBlocks: [[ContentBlock]] = []
        var emptyPages = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { pageBlocks.append([]); continue }
            var text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 {
                if allowOCR, let recognized = recognizeText(on: page) {
                    text = recognized
                } else {
                    emptyPages += 1
                }
            }
            pageBlocks.append(paragraphs(from: text).map { ContentBlock(kind: .paragraph, text: $0, page: index) })
            progress?(Double(index + 1) / Double(max(document.pageCount, 1)))
        }

        let ranges = chapterRanges(document: document)
        var chapters: [Chapter] = []
        for range in ranges {
            let blocks = range.pages.flatMap { pageBlocks[$0] }
            guard !blocks.isEmpty else { continue }
            chapters.append(Chapter(id: chapters.count, title: range.title, blocks: blocks, sourcePage: range.pages.lowerBound))
        }
        if chapters.isEmpty {
            chapters = [Chapter(id: 0, title: title, blocks: [ContentBlock(kind: .paragraph, text: String(localized: "This PDF has no selectable text."), page: 0)], sourcePage: 0)]
        }
        let sample = chapters.prefix(2).flatMap(\.blocks).prefix(30).map(\.text).joined(separator: " ")
        let content = BookContent(title: title, author: author,
                                  language: LanguageDetector.dominantLanguage(of: sample), chapters: chapters)
        let needsOCR = !allowOCR && emptyPages > document.pageCount / 2
        return (content, needsOCR)
    }

    // MARK: - Chapters

    struct ChapterRange {
        var title: String
        var pages: Range<Int>
    }

    static func chapterRanges(document: PDFDocument) -> [ChapterRange] {
        let pageCount = document.pageCount
        guard pageCount > 0 else { return [] }

        var starts: [(String, Int)] = []
        if let root = document.outlineRoot {
            var level = (0..<root.numberOfChildren).compactMap { root.child(at: $0) }
            // A single top-level entry usually wraps the real chapters.
            if level.count == 1, let only = level.first, only.numberOfChildren > 1 {
                level = (0..<only.numberOfChildren).compactMap { only.child(at: $0) }
            }
            for item in level {
                guard let page = item.destination?.page else { continue }
                let index = document.index(for: page)
                let label = item.label?.nonEmpty ?? String(localized: "Page \(index + 1)")
                if index >= 0, index < pageCount, !starts.contains(where: { $0.1 == index }) {
                    starts.append((label, index))
                }
            }
            starts.sort { $0.1 < $1.1 }
        }

        if starts.count >= 2 {
            var ranges: [ChapterRange] = []
            if let first = starts.first, first.1 > 0 {
                ranges.append(ChapterRange(title: String(localized: "Opening", comment: "PDF pages before the first outline entry"), pages: 0..<first.1))
            }
            for (i, start) in starts.enumerated() {
                let end = i + 1 < starts.count ? starts[i + 1].1 : pageCount
                if end > start.1 { ranges.append(ChapterRange(title: start.0, pages: start.1..<end)) }
            }
            return ranges
        }

        return stride(from: 0, to: pageCount, by: pagesPerSyntheticChapter).map { start in
            let end = min(start + pagesPerSyntheticChapter, pageCount)
            let title = end - start == 1 ? String(localized: "Page \(start + 1)") : String(localized: "Pages \(start + 1)–\(end)")
            return ChapterRange(title: title, pages: start..<end)
        }
    }

    // MARK: - Paragraph reconstruction

    /// PDF text comes as hard-wrapped lines. Rebuild paragraphs: join wrapped lines,
    /// undo end-of-line hyphenation and drop bare page numbers.
    static func paragraphs(from text: String) -> [String] {
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Typical full-line width: the 75th percentile, ignoring bare page numbers.
        let lengths = lines.filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }.map(\.count).sorted()
        let fullLine = lengths.isEmpty ? 0 : lengths[min(lengths.count * 3 / 4, lengths.count - 1)]

        var result: [String] = []
        var current = ""
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { result.append(current); current = "" }
                continue
            }
            if line.allSatisfy(\.isNumber) && line.count <= 4 { continue }

            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"), let first = line.first, first.isLowercase {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }

            let terminal = line.last.map { ".!?:;”\"»…)".contains($0) } ?? false
            if terminal && Double(line.count) < Double(fullLine) * 0.8 {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
    }

    // MARK: - OCR

    static func recognizeText(on page: PDFPage) -> String? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = min(2.0, 2000 / max(bounds.width, bounds.height, 1))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
