import Foundation

/// A request to the AI assistant. `selection` is the passage the reader picked, if any.
struct AIRequest: Identifiable, Equatable {
    let id = UUID()
    var action: AIAction?
    var selection: String?
    var question: String?
}

struct WordLookupRequest: Identifiable, Equatable {
    let id = UUID()
    var term: String
    var context: String?
    var language: String?
    var bookTitle: String?
}

/// Everything needed to compose a quote card or share a quote.
struct QuoteDraft: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var bookTitle: String
    var author: String
    var chapterTitle: String?
}

struct HighlightPaletteState: Equatable {
    let highlightID: UUID
    /// Bounds of the highlighted text in the reader's coordinate space.
    let rect: CGRect
}

enum ReaderSheet: Identifiable {
    case settings
    case contents
    case search
    case ask(AIRequest)
    case noteEditor(Highlight)
    case noteCard(Highlight)
    case define(WordLookupRequest)
    case quoteCard(QuoteDraft)
    case flowSummary(FlowSummary)

    var id: String {
        switch self {
        case .settings: "settings"
        case .contents: "contents"
        case .search: "search"
        case .ask(let request): "ask-\(request.id)"
        case .noteEditor(let highlight): "note-\(highlight.id)"
        case .noteCard(let highlight): "card-\(highlight.id)"
        case .define(let request): "define-\(request.id)"
        case .quoteCard(let draft): "quote-\(draft.id)"
        case .flowSummary(let summary): "flow-\(summary.id)"
        }
    }
}
