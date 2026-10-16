import SwiftUI
import SwiftData

/// Everything the reader has kept: highlights, notes, bookmarks and saved words.
struct KnowledgeView: View {
    enum Section: String, CaseIterable, Identifiable {
        case highlights, notes, bookmarks, words
        var id: String { rawValue }
        var title: String {
            switch self {
            case .highlights: String(localized: "Highlights")
            case .notes: String(localized: "Notes")
            case .bookmarks: String(localized: "Bookmarks")
            case .words: String(localized: "Words", comment: "Saved dictionary words")
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case newest, oldest, book, color
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: String(localized: "Newest")
            case .oldest: String(localized: "Oldest")
            case .book: String(localized: "Book", comment: "Sort by book")
            case .color: String(localized: "Color", comment: "Sort by highlight color")
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \Bookmark.createdAt, order: .reverse) private var bookmarks: [Bookmark]

    @State private var section: Section = .highlights
    @State private var search = ""
    @State private var sort: Sort = .newest
    @State private var bookFilter: UUID?
    @State private var tagFilter: String?
    @State private var colorFilter: HighlightColor?
    @State private var editing: Highlight?
    @State private var quoteDraft: (QuoteDraft, Data?)?

    private var service: HighlightService { HighlightService(context: context) }

    private var books: [Book] {
        var seen = Set<UUID>()
        return (highlights.compactMap(\.book) + bookmarks.compactMap(\.book))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var allTags: [String] { Array(Set(highlights.flatMap(\.tags))).sorted() }

    private var filteredHighlights: [Highlight] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let items = highlights.filter { highlight in
            if section == .notes && !highlight.hasNote { return false }
            if let bookFilter, highlight.book?.id != bookFilter { return false }
            if let tagFilter, !highlight.tags.contains(tagFilter) { return false }
            if let colorFilter, highlight.color != colorFilter { return false }
            guard !query.isEmpty else { return true }
            return highlight.text.localizedCaseInsensitiveContains(query)
                || (highlight.note?.localizedCaseInsensitiveContains(query) ?? false)
                || (highlight.book?.title.localizedCaseInsensitiveContains(query) ?? false)
                || highlight.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .newest: return items
        case .oldest: return items.reversed()
        case .book:
            return items.sorted {
                let a = $0.book?.title ?? "", b = $1.book?.title ?? ""
                return a == b ? $0.progress < $1.progress : a.localizedStandardCompare(b) == .orderedAscending
            }
        case .color:
            let order = HighlightColor.allCases
            return items.sorted { order.firstIndex(of: $0.color)! < order.firstIndex(of: $1.color)! }
        }
    }

    private var filteredBookmarks: [Bookmark] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return bookmarks.filter { bookmark in
            if let bookFilter, bookmark.book?.id != bookFilter { return false }
            guard !query.isEmpty else { return true }
            return bookmark.preview.localizedCaseInsensitiveContains(query)
                || bookmark.chapterTitle.localizedCaseInsensitiveContains(query)
                || (bookmark.book?.title.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var hasActiveFilter: Bool { bookFilter != nil || tagFilter != nil || colorFilter != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 8)

                if hasActiveFilter { activeFilters }

                Group {
                    switch section {
                    case .highlights, .notes: highlightList
                    case .bookmarks: bookmarkList
                    case .words: SavedWordsList(search: search)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color.qBackground.ignoresSafeArea())
            .navigationTitle("Quotes & Notes")
            .searchable(text: $search, prompt: "Search quotes, notes, tags")
            .toolbar {
                if section == .highlights || section == .notes, !filteredHighlights.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { exportMenu }
                }
                if section != .words {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu }
                }
            }
            .sheet(item: $editing) { highlight in
                NoteEditorSheet(highlight: highlight) { text, tags in
                    service.setNote(text, tags: tags, for: highlight)
                }
            }
            .sheet(isPresented: Binding(get: { quoteDraft != nil }, set: { if !$0 { quoteDraft = nil } })) {
                if let (draft, cover) = quoteDraft {
                    QuoteCardComposer(draft: draft, coverData: cover)
                }
            }
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private var highlightList: some View {
        let items = filteredHighlights
        if highlights.isEmpty {
            ContentUnavailableView {
                Label(section == .notes ? "No notes yet" : "No highlights yet", systemImage: section == .notes ? "note.text" : "highlighter")
            } description: {
                Text(section == .notes ? "Add a note to any highlight while reading." : "Select text while reading to save a quote.")
            }
        } else if items.isEmpty {
            ContentUnavailableView(search.isEmpty ? "Nothing matches these filters" : "No results",
                                   systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text(search.isEmpty ? "Try clearing a filter." : "No quotes match “\(search)”."))
        } else {
            List {
                ForEach(items) { highlight in
                    HighlightRow(highlight: highlight, notesFirst: section == .notes) { tag in
                        withAnimation(.qSpring) { tagFilter = tag }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { router.open(highlight) }
                    .contextMenu { menu(for: highlight) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { withAnimation { service.delete(highlight) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editing = highlight } label: { Label("Note", systemImage: "note.text") }
                            .tint(.qAccent)
                    }
                    .swipeActions(edge: .leading) {
                        Button { share(highlight) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .tint(.blue)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 14, leading: Metrics.gutter, bottom: 14, trailing: Metrics.gutter))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .animation(.qSpring, value: items.map(\.id))
        }
    }

    @ViewBuilder
    private var bookmarkList: some View {
        let items = filteredBookmarks
        if items.isEmpty {
            ContentUnavailableView("No bookmarks", systemImage: "bookmark",
                                   description: Text("Bookmarks you add while reading appear here."))
        } else {
            List {
                ForEach(items) { bookmark in
                    Button { router.open(bookmark) } label: {
                        HStack(alignment: .top, spacing: 14) {
                            if let book = bookmark.book {
                                BookCoverView(book: book, showsShadow: false).frame(width: 40)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookmark.book?.title ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(Color.qInk)
                                Text(bookmark.chapterTitle).font(.caption).foregroundStyle(Color.qAccent)
                                if !bookmark.preview.isEmpty {
                                    Text(bookmark.preview).font(.qSerif(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(bookmark.progress.percentText + " · " + bookmark.createdAt.quietRelative)
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { service.delete(bookmark) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Filters

    /// Exports what the list shows: the current section, filters and search.
    private var exportMenu: some View {
        Menu {
            HighlightExportButtons(groups: HighlightExporter.groups(from: filteredHighlights))
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Export")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(Sort.allCases) { Text($0.title).tag($0) }
            }
            Menu("Book") {
                checkedButton(String(localized: "All Books"), isOn: bookFilter == nil) { bookFilter = nil }
                ForEach(books) { book in
                    checkedButton(book.title, isOn: bookFilter == book.id) { bookFilter = book.id }
                }
            }
            if !allTags.isEmpty {
                Menu("Tag") {
                    checkedButton(String(localized: "All Tags"), isOn: tagFilter == nil) { tagFilter = nil }
                    ForEach(allTags, id: \.self) { tag in
                        checkedButton("#\(tag)", isOn: tagFilter == tag) { tagFilter = tag }
                    }
                }
            }
            Menu("Color") {
                checkedButton(String(localized: "All Colors"), isOn: colorFilter == nil) { colorFilter = nil }
                ForEach(HighlightColor.allCases) { color in
                    Button { colorFilter = color } label: { Label(color.name, systemImage: colorFilter == color ? "checkmark" : "circle.fill") }
                }
            }
            if hasActiveFilter {
                Button("Clear Filters", role: .destructive) { clearFilters() }
            }
        } label: {
            Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
    }

    @ViewBuilder
    private func checkedButton(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let bookFilter, let book = books.first(where: { $0.id == bookFilter }) {
                    filterPill(book.title) { self.bookFilter = nil }
                }
                if let tagFilter { filterPill("#\(tagFilter)") { self.tagFilter = nil } }
                if let colorFilter { filterPill(colorFilter.name) { self.colorFilter = nil } }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .padding(.bottom, 8)
    }

    private func filterPill(_ title: String, onRemove: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.qSpring) { onRemove() }
        } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(Color.qBackground)
            .background(Color.qInk, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func clearFilters() {
        withAnimation(.qSpring) {
            bookFilter = nil
            tagFilter = nil
            colorFilter = nil
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func menu(for highlight: Highlight) -> some View {
        Button { router.open(highlight) } label: { Label("Open in Book", systemImage: "book") }
        Button { editing = highlight } label: { Label(highlight.hasNote ? "Edit Note" : "Add Note", systemImage: "note.text") }
        Button {
            UIPasteboard.general.string = HighlightService.shareText(for: highlight.text, book: highlight.book)
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        Button { share(highlight) } label: { Label("Create Quote Card", systemImage: "photo.on.rectangle") }
        Menu {
            ForEach(HighlightColor.allCases) { color in
                Button { service.setColor(color, for: highlight) } label: { Label(color.name, systemImage: highlight.color == color ? "checkmark.circle.fill" : "circle.fill") }
            }
        } label: { Label("Color", systemImage: "paintpalette") }
        Divider()
        Button(role: .destructive) { service.delete(highlight) } label: { Label("Delete", systemImage: "trash") }
    }

    private func share(_ highlight: Highlight) {
        let draft = QuoteDraft(text: highlight.text, bookTitle: highlight.book?.title ?? "",
                               author: highlight.book?.author ?? "", chapterTitle: highlight.chapterTitle)
        quoteDraft = (draft, highlight.book?.coverImageData)
    }
}

struct HighlightRow: View {
    let highlight: Highlight
    var notesFirst = false
    var onTagTap: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if notesFirst, let note = highlight.note {
                Text(note)
                    .font(.body)
                    .foregroundStyle(Color.qInk)
            }
            QuoteBlock(text: highlight.text, color: highlight.color, lineLimit: notesFirst ? 3 : 6)
                .opacity(notesFirst ? 0.8 : 1)
            if !notesFirst, let note = highlight.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text").font(.caption)
                    Text(note).font(.subheadline).lineLimit(4)
                }
                .foregroundStyle(Color.qAccent)
                .padding(.leading, 18)
            }
            if !highlight.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(highlight.tags, id: \.self) { tag in
                        Button { onTagTap(tag) } label: { TagChip(tag: tag) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 18)
            }
            HStack(spacing: 4) {
                Text(highlight.book?.title ?? "Removed book").fontWeight(.medium)
                if let author = highlight.book?.author, !author.isEmpty { Text("· \(author)") }
                Spacer(minLength: 8)
                Text(highlight.createdAt.quietRelative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.leading, 18)
            if !highlight.chapterTitle.isEmpty {
                Text(highlight.chapterTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 18)
                    .padding(.top, -6)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
