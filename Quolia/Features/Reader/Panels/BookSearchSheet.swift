import SwiftUI

/// Full-text search inside the open book.
struct BookSearchSheet: View {
    let model: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BookSearch.Result] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                if model.content == nil {
                    ContentUnavailableView("Search isn't ready", systemImage: "magnifyingglass",
                                           description: Text("The text of this book is still being prepared."))
                } else if query.count < 2 {
                    ContentUnavailableView("Search this book", systemImage: "text.magnifyingglass",
                                           description: Text("Find words, names and phrases."))
                } else if results.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { result in
                        Button {
                            open(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.chapterTitle).font(.caption.weight(.semibold)).foregroundStyle(Color.qAccent)
                                Text(result.snippet).font(.qSerif(.subheadline)).foregroundStyle(Color.qInk).lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                    .overlay(alignment: .top) {
                        if isSearching { ProgressView().padding() }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search in book")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: query) {
                guard let content = model.content, query.count >= 2 else { results = []; return }
                isSearching = true
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let term = query
                let found = await Task.detached(priority: .userInitiated) { BookSearch.search(term, in: content) }.value
                guard !Task.isCancelled else { return }
                results = found
                isSearching = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func open(_ result: BookSearch.Result) {
        if model.engine == .pdf, let page = result.page {
            model.go(to: ReadingLocator(page: page))
        } else {
            model.go(to: result.anchor.startLocator, spotlight: result.anchor)
        }
        dismiss()
    }
}

enum BookSearch {
    struct Result: Identifiable, Sendable {
        let id = UUID()
        let anchor: TextAnchor
        let chapterTitle: String
        let snippet: AttributedString
        let page: Int?
    }

    static func search(_ term: String, in content: BookContent, limit: Int = 300) -> [Result] {
        var results: [Result] = []
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for chapter in content.chapters {
            for (blockIndex, block) in chapter.blocks.enumerated() where block.isTextual {
                let text = block.text as NSString
                var searchRange = NSRange(location: 0, length: text.length)
                while searchRange.length > 0 {
                    let found = text.range(of: term, options: options, range: searchRange)
                    guard found.location != NSNotFound else { break }
                    let anchor = TextAnchor(chapter: chapter.id, startBlock: blockIndex, startOffset: found.location,
                                            endBlock: blockIndex, endOffset: NSMaxRange(found))
                    results.append(Result(anchor: anchor, chapterTitle: chapter.title,
                                          snippet: snippet(text, match: found), page: block.page))
                    if results.count >= limit { return results }
                    let next = NSMaxRange(found)
                    searchRange = NSRange(location: next, length: text.length - next)
                }
            }
        }
        return results
    }

    private static func snippet(_ text: NSString, match: NSRange) -> AttributedString {
        let start = max(match.location - 60, 0)
        let end = min(NSMaxRange(match) + 90, text.length)
        let before = text.substring(with: NSRange(location: start, length: match.location - start))
        let hit = text.substring(with: match)
        let after = text.substring(with: NSRange(location: NSMaxRange(match), length: end - NSMaxRange(match)))
        var result = AttributedString((start > 0 ? "…" : "") + before)
        var highlighted = AttributedString(hit)
        highlighted.font = .system(.subheadline, design: .serif).bold()
        highlighted.backgroundColor = HighlightColor.yellow.color.opacity(0.35)
        result += highlighted
        result += AttributedString(after + (end < text.length ? "…" : ""))
        return result
    }
}
