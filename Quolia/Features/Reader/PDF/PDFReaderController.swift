import UIKit
import PDFKit
import SwiftUI

@MainActor
protocol PDFReaderDelegate: AnyObject {
    func pdfReader(didShowPage index: Int, of count: Int)
    func pdfReaderDidTapCenter()
    func pdfReader(didTapHighlight id: UUID, rect: CGRect)
    func pdfReader(perform command: SelectionCommand, page: Int, rects: [CGRect], text: String, screenRect: CGRect)
    func pdfReaderDidReachEnd()
    func pdfReaderDidInteract()
}

/// PDFView with Quolia's selection menu.
final class QuoliaPDFView: PDFView {
    var menuProvider: (() -> UIMenu?)?

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let menu = menuProvider?() else { return }
        builder.remove(menu: .lookup)
        builder.remove(menu: .share)
        builder.insertChild(menu, atStartOfMenu: .root)
    }
}

/// Original-layout PDF reading surface.
final class PDFReaderController: UIViewController, UIGestureRecognizerDelegate, PDFDocumentDelegate {
    weak var delegate: PDFReaderDelegate?
    let pdfView = QuoliaPDFView()
    private let url: URL
    private var document: PDFDocument?
    private var initialPage: Int
    private(set) var layout: ReaderLayout
    private var theme: ReaderTheme
    private var highlights: [Highlight] = []
    private let autoScroll = AutoScrollEngine()
    private var autoScrollWPM: Double?
    var wordsPerPage: Double = 300

    static let annotationKey = PDFAnnotationKey(rawValue: "/QuoliaID")

    init(url: URL, page: Int, layout: ReaderLayout, theme: ReaderTheme) {
        self.url = url
        self.initialPage = page
        self.layout = layout
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        pdfView.frame = view.bounds
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdfView.backgroundColor = theme.background
        pdfView.pageShadowsEnabled = !theme.isDark
        pdfView.menuProvider = { [weak self] in self?.selectionMenu() }
        view.addSubview(pdfView)

        ThemedPDFPage.theme = theme
        let document = PDFDocument(url: url)
        // Must be set before any page is created so pages use the themed class.
        document?.delegate = self
        self.document = document
        pdfView.document = document
        applyLayout()
        if let page = document?.page(at: min(initialPage, max((document?.pageCount ?? 1) - 1, 0))) {
            pdfView.go(to: page)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        pdfView.addGestureRecognizer(tap)

        autoScroll.onReachEnd = { [weak self] in self?.delegate?.pdfReaderDidReachEnd() }
        autoScroll.onTick = { [weak self] in self?.delegate?.pdfReaderDidInteract() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pageChanged()
    }

    // MARK: - Configuration

    func update(layout: ReaderLayout, theme: ReaderTheme, highlights: [Highlight], autoScrollWPM: Double?) {
        if theme != self.theme {
            self.theme = theme
            view.backgroundColor = theme.background
            pdfView.backgroundColor = theme.background
            pdfView.pageShadowsEnabled = !theme.isDark
            redrawPages()
        }
        if layout != self.layout {
            let page = pdfView.currentPage
            self.layout = layout
            applyLayout()
            if let page { pdfView.go(to: page) }
        }
        let ids = highlights.map { "\($0.id)-\($0.colorRaw)-\($0.hasNote)" }
        if ids != self.highlights.map({ "\($0.id)-\($0.colorRaw)-\($0.hasNote)" }) {
            self.highlights = highlights
            syncAnnotations()
        }
        if autoScrollWPM != self.autoScrollWPM {
            self.autoScrollWPM = autoScrollWPM
            syncAutoScroll()
        }
    }

    // MARK: - Theme

    func classForPage() -> AnyClass { ThemedPDFPage.self }

    /// PDFView caches rendered tiles; re-attaching the document redraws them in the new theme.
    private func redrawPages() {
        ThemedPDFPage.theme = theme
        let page = pdfView.currentPage
        let document = pdfView.document
        pdfView.document = nil
        pdfView.document = document
        applyLayout()
        if let page { pdfView.go(to: page) }
    }

    private func applyLayout() {
        switch layout {
        case .paged:
            pdfView.displayMode = .singlePage
            pdfView.displayDirection = .horizontal
            pdfView.usePageViewController(true, withViewOptions: [UIPageViewController.OptionsKey.interPageSpacing: 16])
        case .scroll:
            pdfView.usePageViewController(false)
            pdfView.displayMode = .singlePageContinuous
            pdfView.displayDirection = .vertical
        }
        pdfView.autoScales = true
    }

    // MARK: - Highlights

    private func syncAnnotations() {
        guard let document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.value(forAnnotationKey: Self.annotationKey) != nil {
                page.removeAnnotation(annotation)
            }
        }
        for highlight in highlights where highlight.isPDFAnchored {
            guard let page = document.page(at: highlight.pageIndex) else { continue }
            for rect in highlight.pdfRects {
                let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                annotation.color = highlight.color.uiColor.withAlphaComponent(0.45)
                annotation.setValue(highlight.id.uuidString, forAnnotationKey: Self.annotationKey)
                page.addAnnotation(annotation)
            }
            if highlight.hasNote, let first = highlight.pdfRects.first {
                let pageBounds = page.bounds(for: .cropBox)
                // In the right margin, level with the highlight's first line.
                let marker = CGRect(x: pageBounds.maxX - 22, y: first.midY - 8, width: 16, height: 16)
                let note = PDFAnnotation(bounds: marker, forType: .text, withProperties: nil)
                note.color = highlight.color.uiColor
                note.contents = highlight.note
                note.setValue(highlight.id.uuidString, forAnnotationKey: Self.annotationKey)
                page.addAnnotation(note)
            }
        }
    }


    // MARK: - Selection

    private func selectionMenu() -> UIMenu? {
        guard let selection = pdfView.currentSelection, let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, let page = selection.pages.first, let document else { return nil }
        let pageIndex = document.index(for: page)
        let rects = selection.glyphLineRects(on: page).filter { $0.width > 1 }
        let screenRect = pdfView.convert(pdfView.convert(selection.bounds(for: page), from: page), to: view)

        func action(_ title: String, _ symbol: String, _ command: SelectionCommand) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                self?.delegate?.pdfReader(perform: command, page: pageIndex, rects: rects, text: text, screenRect: screenRect)
                if case .copy = command {} else { self?.pdfView.clearSelection() }
            }
        }
        let ai = UIMenu(title: String(localized: "Ask AI"), image: UIImage(systemName: "sparkles"),
                        children: [AIAction.explain, .simplify, .summarize, .ask].map { action($0.title, $0.symbol, .ai($0)) })
        return UIMenu(options: .displayInline, children: [
            action(String(localized: "Highlight", comment: "Text selection menu"), "highlighter", .highlight),
            action(String(localized: "Note", comment: "Text selection menu"), "note.text.badge.plus", .note),
            action(String(localized: "Translate", comment: "Text selection menu"), "translate", .translate),
            action(String(localized: "Define", comment: "Text selection menu"), "character.book.closed", .define),
            action(String(localized: "Share", comment: "Text selection menu"), "square.and.arrow.up", .share),
            ai,
        ])
    }

    // MARK: - Navigation

    @objc private func pageChanged() {
        guard let document, let page = pdfView.currentPage else { return }
        delegate?.pdfReader(didShowPage: document.index(for: page), of: document.pageCount)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard pdfView.currentSelection?.string?.isEmpty ?? true else { return }
        let point = gesture.location(in: view)
        // Taps on a Quolia highlight open its palette or note card.
        if let page = pdfView.page(for: gesture.location(in: pdfView), nearest: false) {
            let pagePoint = pdfView.convert(gesture.location(in: pdfView), to: page)
            if let annotation = page.annotations.first(where: {
                   $0.value(forAnnotationKey: Self.annotationKey) != nil && $0.bounds.insetBy(dx: -4, dy: -4).contains(pagePoint)
               }),
               let raw = annotation.value(forAnnotationKey: Self.annotationKey) as? String,
               let id = UUID(uuidString: raw) {
                let rect = pdfView.convert(pdfView.convert(annotation.bounds, from: page), to: view)
                delegate?.pdfReader(didTapHighlight: id, rect: rect)
                return
            }
        }
        delegate?.pdfReaderDidInteract()
        let x = point.x / max(view.bounds.width, 1)
        if autoScrollWPM == nil, layout == .paged {
            if x < 0.25 { pdfView.goToPreviousPage(nil); return }
            if x > 0.75 { pdfView.goToNextPage(nil); return }
        }
        delegate?.pdfReaderDidTapCenter()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: - Auto scroll

    private var scrollView: UIScrollView? {
        func find(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            for subview in view.subviews { if let found = find(subview) { return found } }
            return nil
        }
        return find(pdfView)
    }

    private func syncAutoScroll() {
        guard let wpm = autoScrollWPM, layout == .scroll, let scrollView, let document, document.pageCount > 0 else {
            autoScroll.stop()
            return
        }
        autoScroll.scrollView = scrollView
        let pageHeight = scrollView.contentSize.height / CGFloat(document.pageCount)
        autoScroll.pointsPerSecond = CGFloat(wpm / 60 / max(wordsPerPage, 50)) * pageHeight
        autoScroll.stopOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        autoScroll.resync()
        if !autoScroll.isRunning { autoScroll.start() }
    }
}

extension PDFReaderController: ReaderCommands {
    func go(to locator: ReadingLocator, spotlight: TextAnchor?) {
        guard let page = document?.page(at: locator.page) else { return }
        pdfView.go(to: page)
    }

    func turnPage(forward: Bool) {
        forward ? pdfView.goToNextPage(nil) : pdfView.goToPreviousPage(nil)
    }

    func changeChapter(by delta: Int) {
        guard let document, let current = pdfView.currentPage else { return }
        let target = min(max(document.index(for: current) + delta, 0), document.pageCount - 1)
        if let page = document.page(at: target) { pdfView.go(to: page) }
    }

    func clearSelection() { pdfView.clearSelection() }
}

struct PDFReaderCanvas: UIViewControllerRepresentable {
    let model: ReaderViewModel
    let url: URL
    let theme: ReaderTheme
    let layout: ReaderLayout
    let autoScrollWPM: Double?

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> PDFReaderController {
        let controller = PDFReaderController(url: url, page: model.pdfPage, layout: layout, theme: theme)
        controller.delegate = context.coordinator
        if model.book.pageCount > 0, model.book.totalWords > 0 {
            controller.wordsPerPage = Double(model.book.totalWords) / Double(model.book.pageCount)
        }
        model.commands = controller
        return controller
    }

    func updateUIViewController(_ controller: PDFReaderController, context: Context) {
        context.coordinator.model = model
        _ = model.highlightsVersion
        controller.update(layout: layout, theme: theme, highlights: model.book.allHighlights, autoScrollWPM: autoScrollWPM)
    }

    @MainActor
    final class Coordinator: NSObject, PDFReaderDelegate {
        var model: ReaderViewModel
        init(model: ReaderViewModel) { self.model = model }

        func pdfReader(didShowPage index: Int, of count: Int) { model.pdfDidMove(toPage: index, pageCount: count) }
        func pdfReaderDidTapCenter() {
            if model.isAutoScrollActive { model.tapWhileAutoScrolling() } else { model.toggleChrome() }
        }
        func pdfReader(didTapHighlight id: UUID, rect: CGRect) { model.presentHighlightTap(id: id, rect: rect) }
        func pdfReader(perform command: SelectionCommand, page: Int, rects: [CGRect], text: String, screenRect: CGRect) {
            model.handlePDF(command, page: page, rects: rects, text: text, screenRect: screenRect)
        }
        func pdfReaderDidReachEnd() { model.autoScrollReachedEnd() }
        func pdfReaderDidInteract() { model.userDidInteract() }
    }
}
