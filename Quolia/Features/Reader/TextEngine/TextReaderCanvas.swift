import SwiftUI

/// Hosts the UIKit text engine inside SwiftUI and forwards its events to the view model.
struct TextReaderCanvas: UIViewControllerRepresentable {
    let model: ReaderViewModel
    let content: BookContent
    let state: TextReaderState

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> TextReaderController {
        let controller = TextReaderController(content: content, imagesDirectory: model.imagesDirectory,
                                              state: state, locator: model.startLocator)
        controller.initialSpotlight = model.initialSpotlight
        controller.delegate = context.coordinator
        model.commands = controller
        return controller
    }

    func updateUIViewController(_ controller: TextReaderController, context: Context) {
        context.coordinator.model = model
        controller.apply(state)
    }

    @MainActor
    final class Coordinator: NSObject, TextReaderDelegate {
        var model: ReaderViewModel

        init(model: ReaderViewModel) { self.model = model }

        func textReader(didMoveTo range: VisibleRange, page: Int?, pageCount: Int?) {
            model.textDidMove(to: range, page: page, pageCount: pageCount)
        }

        func textReaderDidTapCenter() {
            if model.isAutoScrollActive {
                model.tapWhileAutoScrolling()
            } else if model.speech.isActive {
                model.speech.togglePause()
            } else {
                model.toggleChrome()
            }
        }

        func textReader(didTapHighlight id: UUID, rect: CGRect) {
            model.presentHighlightTap(id: id, rect: rect)
        }

        func textReader(didTapNoteMarker id: UUID) {
            guard let highlight = model.highlight(withID: id) else { return }
            model.activeSheet = .noteCard(highlight)
        }

        func textReader(didTapFootnote key: String) {
            guard let footnote = model.content?.footnotes[key] else { return }
            model.activeSheet = .footnote(footnote)
        }

        func textReader(perform command: SelectionCommand, selection: TextSelectionInfo) {
            model.handle(command, selection: selection)
        }

        func textReaderAutoScrollDidReachEnd() {
            model.autoScrollReachedEnd()
        }

        func textReaderDidInteract() {
            model.userDidInteract()
        }

        func textReader(didMeasureChapter index: Int, height: CGFloat) {}
    }
}
