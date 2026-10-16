import SwiftUI
import SwiftData

struct BookDetailsSheet: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        BookCoverView(book: book).frame(width: 90)
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Title", text: $book.title, axis: .vertical)
                                .font(.qSerif(.title3, weight: .semibold))
                            TextField("Author", text: $book.author)
                                .foregroundStyle(Color.qMuted)
                            Text(book.format.displayName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.qSurfaceSecondary, in: Capsule())
                                .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Picker("Status", selection: Binding(get: { book.status }, set: { book.status = $0 })) {
                        ForEach(ReadingStatus.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Button {
                        dismiss()
                        router.open(book)
                    } label: {
                        Label(book.progress > 0 ? "Continue Reading" : "Start Reading", systemImage: "book")
                    }
                }

                if !book.allHighlights.isEmpty {
                    Section {
                        HighlightExportButtons(groups: HighlightExporter.groups(from: book.allHighlights))
                    } header: {
                        Text("Highlights & Notes")
                    }
                }

                Section("About") {
                    LabeledContent("Progress", value: book.progress.formatted(.percent.precision(.fractionLength(0))))
                    if book.totalWords > 0 {
                        LabeledContent("Length", value: String(localized: "\(book.totalWords.formatted()) words · ~\(ReadingMath.pages(forWords: book.totalWords)) pages"))
                    }
                    if book.format == .pdf {
                        LabeledContent("PDF pages", value: book.pageCount.formatted())
                    }
                    LabeledContent("Chapters", value: book.chapterCount.formatted())
                    LabeledContent("Highlights", value: book.allHighlights.count.formatted())
                    LabeledContent("Added", value: book.addedAt.formatted(date: .abbreviated, time: .omitted))
                    if let last = book.lastOpenedAt {
                        LabeledContent("Last read", value: last.quietRelative)
                    }
                    if book.fileSize > 0 {
                        LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
                    }
                }

                Section {
                    Button("Delete Book", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete this book?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    BookImporter.delete(book, context: context)
                }
            } message: {
                Text("Highlights, notes and bookmarks for this book will also be deleted.")
            }
        }
        .presentationDetents([.large])
    }
}
