import Foundation

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, reading, finished, wantToRead

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All", comment: "Library filter")
        case .reading: ReadingStatus.reading.title
        case .finished: ReadingStatus.finished.title
        case .wantToRead: ReadingStatus.wantToRead.title
        }
    }

    func includes(_ book: Book) -> Bool {
        switch self {
        case .all: true
        case .reading: book.status == .reading
        case .finished: book.status == .finished
        case .wantToRead: book.status == .wantToRead
        }
    }
}

enum LibraryQuery {
    static func apply(_ books: [Book], filter: LibraryFilter, search: String, sort: LibrarySort) -> [Book] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = books.filter { book in
            guard filter.includes(book) else { return false }
            guard !query.isEmpty else { return true }
            return book.title.localizedCaseInsensitiveContains(query)
                || book.author.localizedCaseInsensitiveContains(query)
        }
        return filtered.sorted { a, b in
            switch sort {
            case .recent:
                return (a.lastOpenedAt ?? a.addedAt) > (b.lastOpenedAt ?? b.addedAt)
            case .added:
                return a.addedAt > b.addedAt
            case .title:
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .author:
                return a.author.localizedStandardCompare(b.author) == .orderedAscending
            case .progress:
                return a.progress > b.progress
            }
        }
    }
}
