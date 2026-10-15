#if DEBUG
import Foundation
import SwiftData
import PDFKit

/// Launch arguments for driving the app into specific states during development
/// and automated screenshots, e.g. `-tab stats` or `-openBook -readerLayout scroll -focus line`.
@MainActor
enum DebugLaunch {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func value(_ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func has(_ flag: String) -> Bool { arguments.contains(flag) }

    /// A reader sheet to open once the book is loaded (`-readerSheet settings|contents|search|ask`).
    static var pendingReaderSheet: String? = value("-readerSheet")

    /// Highlights a few phrases in the first PDF (yellow, and green with a note).
    private static func addPDFDemoHighlights(context: ModelContext) {
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        guard let book = books.first(where: { $0.format == .pdf }),
              let url = BookFileStore.shared.existingURL(for: book.fileName),
              let document = PDFDocument(url: url) else { return }
        let service = HighlightService(context: context)
        book.allHighlights.filter(\.isPDFAnchored).forEach(service.delete)
        for (phrase, color, note) in [("reconstructs paragraphs", HighlightColor.yellow, nil as String?),
                                      ("highlights live on the original layout", .green, "Check this in dark mode.")] {
            guard let selection = document.findString(phrase, withOptions: .caseInsensitive).first,
                  let page = selection.pages.first else { continue }
            let rects = selection.glyphLineRects(on: page)
            let highlight = service.createPDFHighlight(in: book, page: document.index(for: page), rects: rects,
                                                       text: phrase, progress: 0, color: color)
            if let note { highlight.setNote(note, tags: []) }
        }
        try? context.save()
    }

    static func apply(router: AppRouter, settings: AppSettings, context: ModelContext) async {
        if let layout = value("-readerLayout").flatMap(ReaderLayout.init(rawValue:)) { settings.reader.layout = layout }
        if let focus = value("-focus").flatMap(FocusMode.init(rawValue:)) { settings.reader.focusMode = focus }
        if let theme = value("-theme").flatMap(ReaderTheme.init(rawValue:)) {
            settings.reader.theme = theme
            settings.reader.matchesSystemAppearance = false
        }
        if let library = value("-libraryLayout").flatMap(LibraryLayout.init(rawValue:)) { settings.libraryLayout = library }
        if let tab = value("-tab").flatMap(AppTab.init(rawValue:)) { router.selectedTab = tab }
        if has("-showSettings") { router.isSettingsPresented = true }
        if has("-completeOnboarding") { settings.hasCompletedOnboarding = true }

        // `-importFile <path>` (repeatable) imports host files as if picked in Files.
        let files = arguments.indices.filter { arguments[$0] == "-importFile" && arguments.indices.contains($0 + 1) }
            .map { URL(fileURLWithPath: arguments[$0 + 1]) }
        if !files.isEmpty {
            let outcome = await BookImporter(context: context).importBooks(from: files)
            print("DebugLaunch import:", outcome.summary ?? "nothing")
        }

        if has("-pdfDemoHighlight") { addPDFDemoHighlights(context: context) }

        if let title = value("-openTitle") {
            try? await Task.sleep(for: .milliseconds(400))
            let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
            if let book = books.first(where: { $0.title.localizedCaseInsensitiveContains(title) }) {
                router.open(book)
            }
        }

        if has("-openBook") || has("-flow") {
            try? await Task.sleep(for: .milliseconds(600))
            var descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.addedAt)])
            descriptor.fetchLimit = 1
            if let book = try? context.fetch(descriptor).first {
                router.open(book, readingFlow: has("-flow"))
            }
        }
    }
}
#endif
