import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]

    @State private var filter: LibraryFilter = .all
    @State private var search = ""
    @State private var isImporterPresented = false
    @State private var detailsBook: Book?
    @State private var bookPendingDeletion: Book?

    private var visibleBooks: [Book] {
        LibraryQuery.apply(books, filter: filter, search: search, sort: settings.librarySort)
    }

    private var continueBook: Book? {
        books.filter { $0.status == .reading && $0.lastOpenedAt != nil }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyLibrary
                } else {
                    content
                }
            }
            .background(Color.qBackground.ignoresSafeArea())
            .navigationTitle("Library")
            .toolbar { toolbar }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Title or author")
            .bookImporter(isPresented: $isImporterPresented)
            .sheet(item: $detailsBook) { book in
                BookDetailsSheet(book: book)
            }
            .confirmationDialog("Delete this book?", isPresented: deletionBinding, titleVisibility: .visible,
                                presenting: bookPendingDeletion) { book in
                Button("Delete “\(book.title)”", role: .destructive) {
                    withAnimation(.qSpring) { BookImporter.delete(book, context: context) }
                    Haptics.warning()
                }
            } message: { _ in
                Text("Its highlights, notes and bookmarks will be deleted on all your devices.")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if settings.libraryLayout == .grid {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if visibleBooks.isEmpty { noResults } else { grid }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
        } else {
            List {
                header
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                if visibleBooks.isEmpty {
                    noResults
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(visibleBooks) { book in
                    BookListRow(book: book) { open(book) }
                        .contextMenu { menu(for: book) }
                        .listRowInsets(EdgeInsets(top: 0, leading: Metrics.gutter, bottom: 0, trailing: Metrics.gutter))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { bookPendingDeletion = book } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { detailsBook = book } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            let target: ReadingStatus = book.status == .finished ? .reading : .finished
                            Button {
                                withAnimation(.qSpring) { book.status = target }
                                Haptics.success()
                            } label: {
                                Label(target == .finished ? "Finished" : "Reading", systemImage: target.symbol)
                            }
                            .tint(.qAccent)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .animation(.qSpring, value: visibleBooks.map(\.id))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let continueBook, filter == .all, search.isEmpty {
                ContinueReadingCard(book: continueBook)
                    .padding(.horizontal, Metrics.gutter)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LibraryFilter.allCases) { item in
                        FilterChip(title: item.title,
                                   count: item == .all ? nil : books.filter(item.includes).count,
                                   isSelected: filter == item) {
                            withAnimation(.qSpring) { filter = item }
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
        }
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label(search.isEmpty ? "Nothing here yet" : "No results", systemImage: search.isEmpty ? "books.vertical" : "magnifyingglass")
        } description: {
            Text(search.isEmpty ? "Books marked “\(filter.title)” will appear here." : "No books match “\(search)”.")
        }
        .padding(.top, 40)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 210), spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 30) {
            ForEach(visibleBooks) { book in
                BookGridItem(book: book) { open(book) }
                    .contextMenu { menu(for: book) } preview: {
                        BookCoverView(book: book, showsShadow: false).frame(width: 220)
                    }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .animation(.qSpring, value: visibleBooks.map(\.id))
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Your library is quiet", systemImage: "books.vertical")
        } description: {
            Text("Import EPUB, PDF or TXT books from Files, or AirDrop and share them to Quolia.")
        } actions: {
            Button {
                isImporterPresented = true
            } label: {
                Text("Add a Book").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.qInk)
            Button("Try the sample book") {
                Task {
                    let outcome = await BookImporter(context: context).importSampleBook()
                    if let book = outcome.imported.first { router.open(book) }
                }
            }
            .tint(.qAccent)
        }
    }

    // MARK: - Toolbar & menus

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                router.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Layout", selection: Binding(get: { settings.libraryLayout }, set: { settings.libraryLayout = $0 })) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                    Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
                }
                Picker("Sort By", selection: Binding(get: { settings.librarySort }, set: { settings.librarySort = $0 })) {
                    ForEach(LibrarySort.allCases) { Text($0.name).tag($0) }
                }
            } label: {
                Image(systemName: settings.libraryLayout == .grid ? "square.grid.2x2" : "list.bullet")
            }
            .accessibilityLabel("View options")

            Button {
                isImporterPresented = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Book")
        }
    }

    @ViewBuilder
    private func menu(for book: Book) -> some View {
        Button { open(book) } label: { Label("Read", systemImage: "book") }
        Button { router.open(book, readingFlow: true) } label: { Label("Start Reading Flow", systemImage: "play.circle") }
        Divider()
        ForEach(ReadingStatus.allCases.filter { $0 != book.status }) { status in
            Button {
                withAnimation(.qSpring) { book.status = status }
                Haptics.selection()
            } label: {
                Label("Mark as \(status.title)", systemImage: status.symbol)
            }
        }
        Divider()
        Button { detailsBook = book } label: { Label("Details", systemImage: "info.circle") }
        Button(role: .destructive) { bookPendingDeletion = book } label: { Label("Delete", systemImage: "trash") }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { bookPendingDeletion != nil }, set: { if !$0 { bookPendingDeletion = nil } })
    }

    private func open(_ book: Book) {
        Haptics.light()
        router.open(book, fromCover: settings.libraryLayout == .grid)
    }
}
