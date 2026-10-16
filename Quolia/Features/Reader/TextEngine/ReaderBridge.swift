import UIKit

/// Value snapshot of a highlight for rendering in the text engine.
struct HighlightMark: Equatable, Sendable {
    let id: UUID
    let anchor: TextAnchor
    let color: HighlightColor
    let hasNote: Bool
}

struct VisibleRange: Equatable {
    var start: ReadingLocator
    var end: ReadingLocator
}

struct TextSelectionInfo {
    let anchor: TextAnchor
    let text: String
    /// Selection bounds in the reader canvas coordinate space.
    let rect: CGRect
    /// The paragraph surrounding the selection, for dictionary/AI context.
    let context: String
    /// Highlights overlapping the selection.
    let overlappingHighlights: [UUID]
}

enum AIAction: String, CaseIterable, Identifiable {
    case explain, simplify, summarize, translate, ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: String(localized: "Explain", comment: "AI action")
        case .simplify: String(localized: "Simplify", comment: "AI action")
        case .summarize: String(localized: "Summarize", comment: "AI action")
        case .translate: String(localized: "Translate", comment: "AI action")
        case .ask: String(localized: "Ask About This", comment: "AI action")
        }
    }

    var symbol: String {
        switch self {
        case .explain: "lightbulb"
        case .simplify: "text.badge.minus"
        case .summarize: "text.append"
        case .translate: "character.bubble"
        case .ask: "questionmark.bubble"
        }
    }
}

enum SelectionCommand {
    case highlight
    case note
    case copy
    case translate
    case define
    case share
    case removeHighlights([UUID])
    case ai(AIAction)
}

@MainActor
protocol TextReaderDelegate: AnyObject {
    func textReader(didMoveTo range: VisibleRange, page: Int?, pageCount: Int?)
    /// Pages in each chapter with the current layout (paged mode), or nil while unknown.
    func textReader(didCountBookPages counts: [Int]?)
    func textReaderDidTapCenter()
    func textReader(didTapHighlight id: UUID, rect: CGRect)
    func textReader(didTapNoteMarker id: UUID)
    func textReader(didTapFootnote key: String)
    /// A selection is being continued on the next pages (paged mode).
    func textReader(didContinueSelection active: Bool)
    func textReader(perform command: SelectionCommand, selection: TextSelectionInfo)
    func textReaderAutoScrollDidReachEnd()
    func textReaderDidInteract()
    /// Approximate scroll height of the chapter in points, for WPM ↔ speed conversion.
    func textReader(didMeasureChapter index: Int, height: CGFloat)
}

/// Imperative commands the view model sends to a reading surface.
/// Continuous state (style, focus, auto scroll, speech) flows through `TextReaderState`.
@MainActor
protocol ReaderCommands: AnyObject {
    func go(to locator: ReadingLocator, spotlight: TextAnchor?)
    func turnPage(forward: Bool)
    func changeChapter(by delta: Int)
    func clearSelection()
    func cancelContinuedSelection()
}

extension TextReaderController: ReaderCommands {}
