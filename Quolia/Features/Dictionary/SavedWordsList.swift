import SwiftUI
import SwiftData

/// The user's personal vocabulary, collected while reading.
struct SavedWordsList: View {
    let search: String
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedWord.createdAt, order: .reverse) private var words: [SavedWord]
    @State private var lookup: WordLookupRequest?

    private var filtered: [SavedWord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return words }
        return words.filter {
            $0.word.localizedCaseInsensitiveContains(query) || ($0.translation?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Group {
            if words.isEmpty {
                ContentUnavailableView("No saved words yet", systemImage: "character.book.closed",
                                       description: Text("Select a word while reading, tap Define, then save it."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(filtered) { word in
                        Button {
                            lookup = WordLookupRequest(term: word.word, context: word.context, language: word.language, bookTitle: word.bookTitle)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(word.word)
                                        .font(.qSerif(.title3, weight: .semibold))
                                        .foregroundStyle(Color.qInk)
                                    if let translation = word.translation {
                                        Text(translation).font(.subheadline).foregroundStyle(Color.qAccent)
                                    }
                                    Spacer()
                                    Button {
                                        Pronouncer.speak(word.word, language: word.language)
                                    } label: {
                                        Image(systemName: "speaker.wave.2")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Pronounce \(word.word)")
                                }
                                if let sentence = word.context {
                                    Text(sentence).font(.qSerif(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
                                }
                                HStack(spacing: 4) {
                                    if let book = word.bookTitle { Text(book) ; Text("·") }
                                    Text(word.createdAt.quietRelative)
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(word)
                                try? context.save()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $lookup) { WordLookupSheet(request: $0) }
    }
}
