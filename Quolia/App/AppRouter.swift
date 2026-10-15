import SwiftUI
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case library, notes, remember, stats
}

/// A request to open the reader, optionally at a specific place.
struct ReaderRequest: Identifiable, Equatable {
    let id = UUID()
    let book: Book
    var locator: ReadingLocator?
    /// Highlight to spotlight after opening.
    var highlightID: UUID?
    var startsReadingFlow = false
    /// Whether the reader should zoom out of the library cover.
    var zoomsFromCover = false

    static func == (lhs: ReaderRequest, rhs: ReaderRequest) -> Bool { lhs.id == rhs.id }
}

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .library
    var reader: ReaderRequest?
    var isImportPickerPresented = false
    var isFirstBookPromptPresented = false
    var isSettingsPresented = false

    func open(_ book: Book, at locator: ReadingLocator? = nil, highlightID: UUID? = nil,
              readingFlow: Bool = false, fromCover: Bool = false) {
        reader = ReaderRequest(book: book, locator: locator, highlightID: highlightID,
                               startsReadingFlow: readingFlow, zoomsFromCover: fromCover)
    }

    func open(_ highlight: Highlight) {
        guard let book = highlight.book else { return }
        open(book, at: highlight.locator, highlightID: highlight.id)
    }

    func open(_ bookmark: Bookmark) {
        guard let book = bookmark.book else { return }
        open(book, at: bookmark.locator)
    }
}

extension EnvironmentValues {
    /// Namespace for the cover → reader zoom transition.
    @Entry var readerTransitionNamespace: Namespace.ID?
}
