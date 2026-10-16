import UIKit

/// Everything the text engine needs to render, as one comparable value.
struct TextReaderState: Equatable {
    var style: ReaderStyle
    var layout: ReaderLayout
    var pageTurn: PageTurnStyle
    var focus: FocusMode
    var marks: [Int: [HighlightMark]]
    /// Non-nil while auto scroll is running.
    var autoScrollWPM: Double?
    /// While true, taps pause/resume instead of toggling the interface.
    var autoScrollMode: Bool
    /// Block currently being read aloud.
    var speech: ReadingLocator?
}

/// The reflowable reading surface. Renders one chapter at a time either as a
/// continuous scroll or as pages, and reports position, taps and selections.
final class TextReaderController: UIViewController {
    weak var delegate: TextReaderDelegate?
    /// Passage to reveal and spotlight once the first layout is ready.
    var initialSpotlight: TextAnchor?

    let content: BookContent
    let imagesDirectory: URL
    private(set) var state: TextReaderState

    private(set) var chapterIndex = 0
    private var pendingLocator: ReadingLocator
    private var lastReported: VisibleRange?
    private var lastReportTime: CFTimeInterval = 0

    private var renderedCache: [Int: RenderedChapter] = [:]
    private var layoutCache: [Int: ChapterLayout] = [:]
    private var lastBoundsSize: CGSize = .zero

    // Scroll mode
    private(set) var scrollTextView: ReaderTextView?
    /// TextKit 1 ownership runs storage → layout manager → container, so the storage must be retained.
    private var scrollStorage: NSTextStorage?
    private var scrollRendered: RenderedChapter?
    var scrollRenderedChapter: RenderedChapter? { scrollRendered }
    private var footer: ChapterFooterView?
    private var resumeAutoScrollAfterDrag = false

    // Paged mode
    private(set) var pageController: UIPageViewController?
    /// Pages alive in the page controller (current and prefetched), kept in sync with highlights.
    private let livePages = NSHashTable<TextPageViewController>.weakObjects()

    // Focus
    let focusOverlay = FocusOverlayView()
    var focusedUnit: Int?
    var pagedFocusIndex = 0

    private let autoScroll = AutoScrollEngine()
    private var chapterTextHeight: CGFloat = 0
    private var spotlight: TextAnchor?
    private var lastSelectionLength = 0
    private var lastSelectionClear = Date.distantPast
    private var isChangingChapter = false

    private var theme: ReaderTheme { state.style.theme }
    private var safeTop: CGFloat { max(view.safeAreaInsets.top, view.window?.safeAreaInsets.top ?? 0, 20) }
    private var safeBottom: CGFloat { max(view.safeAreaInsets.bottom, view.window?.safeAreaInsets.bottom ?? 0) }
    private var scrollTopInset: CGFloat { safeTop + 52 }
    private var scrollBottomInset: CGFloat { 260 }

    init(content: BookContent, imagesDirectory: URL, state: TextReaderState, locator: ReadingLocator) {
        self.content = content
        self.imagesDirectory = imagesDirectory
        self.state = state
        self.pendingLocator = locator
        self.chapterIndex = min(max(locator.chapter, 0), max(content.chapters.count - 1, 0))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        focusOverlay.frame = view.bounds
        focusOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        focusOverlay.dimColor = theme.background.withAlphaComponent(theme.isDark ? 0.78 : 0.74)
        view.addSubview(focusOverlay)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        autoScroll.onTick = { [weak self] in
            self?.reportPosition()
            self?.updateFocus(animated: true)
        }
        autoScroll.onReachEnd = { [weak self] in
            self?.delegate?.textReaderAutoScrollDidReachEnd()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0, view.bounds.size != lastBoundsSize else { return }
        lastBoundsSize = view.bounds.size
        renderedCache.removeAll()
        layoutCache.removeAll()
        rebuild(at: currentLocator)
        if let spotlight = initialSpotlight {
            initialSpotlight = nil
            go(to: spotlight.startLocator, spotlight: spotlight)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard lastBoundsSize != .zero else { return }
        layoutCache.removeAll()
        rebuild(at: currentLocator)
    }

    var currentLocator: ReadingLocator { lastReported?.start ?? pendingLocator }

    // MARK: - State

    func apply(_ newState: TextReaderState) {
        let old = state
        state = newState
        guard isViewLoaded else { return }

        var needsRebuild = false
        if old.style != newState.style {
            renderedCache.removeAll()
            layoutCache.removeAll()
            view.backgroundColor = theme.background
            focusOverlay.dimColor = theme.background.withAlphaComponent(theme.isDark ? 0.78 : 0.74)
            needsRebuild = true
        }
        if old.layout != newState.layout { needsRebuild = true }
        if old.pageTurn != newState.pageTurn, newState.layout == .paged { needsRebuild = true }

        if needsRebuild {
            if lastBoundsSize != .zero { rebuild(at: currentLocator) }
        } else if old.marks != newState.marks {
            refreshMarks()
        }

        if old.focus != newState.focus || old.speech != newState.speech {
            if old.focus != newState.focus { pagedFocusIndex = 0 }
            if let speech = newState.speech, speech != old.speech { reveal(speech) }
            updateFocus(animated: true)
        }

        if old.autoScrollWPM != newState.autoScrollWPM || needsRebuild {
            syncAutoScroll()
        }
    }

    private func rebuild(at locator: ReadingLocator) {
        guard !content.chapters.isEmpty else { return }
        pendingLocator = locator
        let chapter = min(max(locator.chapter, 0), content.chapters.count - 1)
        if state.layout == .scroll {
            showScroll(chapter: chapter, locator: locator)
        } else {
            showPaged(chapter: chapter, locator: locator)
        }
    }

    // MARK: - Rendering

    func rendered(_ index: Int) -> RenderedChapter {
        if let cached = renderedCache[index] { return cached }
        let width = view.bounds.width
        let textWidth = state.style.textWidth(forWidth: width)
        let maxImageHeight = max(view.bounds.height - safeTop - safeBottom - 140, 160)
        let result = ChapterRenderer.render(content.chapters[index], style: state.style, imagesDirectory: imagesDirectory,
                                            contentWidth: textWidth, maxImageHeight: maxImageHeight)
        renderedCache[index] = result
        return result
    }

    /// Highlight and spotlight marks for a chapter, in chapter coordinates.
    private func marks(for rendered: RenderedChapter) -> [ReaderLayoutManager.Mark] {
        var marks: [ReaderLayoutManager.Mark] = []
        for mark in state.marks[rendered.index] ?? [] {
            guard let range = rendered.range(for: mark.anchor) else { continue }
            marks.append(.init(range: range, color: mark.color.fill(isDarkTheme: theme.isDark)))
        }
        if let spotlight, spotlight.chapter == rendered.index, let range = rendered.range(for: spotlight) {
            marks.append(.init(range: range, color: theme.accent.withAlphaComponent(0.30)))
        }
        return marks
    }

    private func applyMarks(to layoutManager: NSLayoutManager, rendered: RenderedChapter) {
        (layoutManager as? ReaderLayoutManager)?.marks = marks(for: rendered)
    }

    private func refreshMarks() {
        if let textView = scrollTextView, let rendered = scrollRendered {
            applyMarks(to: textView.layoutManager, rendered: rendered)
            installNoteMarkers(textView: textView, host: textView, rendered: rendered, characterRange: nil)
        }
        for layout in layoutCache.values {
            applyMarks(to: layout.layoutManager, rendered: layout.rendered)
        }
        for page in livePages.allObjects {
            page.applyMarks(marks(for: page.layout.rendered))
        }
        if let page = currentPage {
            installNoteMarkers(textView: page.textView, host: page.view, rendered: page.layout.rendered,
                               characterRange: page.characterRange, characterOffset: page.characterOffset)
        }
    }

    /// Margin indicators for highlights that carry notes. In scroll mode they live inside
    /// the scrolling text view; in paged mode inside the page, beside the text column.
    private func installNoteMarkers(textView: UITextView, host: UIView, rendered: RenderedChapter, characterRange: NSRange?,
                                    characterOffset: Int = 0) {
        host.subviews.compactMap { $0 as? NoteMarkerView }.forEach { $0.removeFromSuperview() }
        let layoutManager = textView.layoutManager
        let inset = textView.textContainerInset
        let inScrollView = host === textView
        let origin = inScrollView ? CGPoint.zero : textView.frame.origin
        for mark in state.marks[rendered.index] ?? [] where mark.hasNote {
            guard let range = rendered.range(for: mark.anchor) else { continue }
            if let characterRange, !NSLocationInRange(range.location, characterRange) { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location - characterOffset)
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let lineHeight = min(line.height, state.style.bodyFont.lineHeight)
            let y = origin.y + inset.top + line.minY + lineHeight / 2
            let x: CGFloat
            if inScrollView {
                x = textView.bounds.width - max(inset.right / 2, 12)
            } else {
                let rightMargin = view.bounds.width - textView.frame.maxX
                x = textView.frame.maxX + max(rightMargin / 2, 10)
            }
            let marker = NoteMarkerView(highlightID: mark.id, color: mark.color.uiColor)
            marker.center = CGPoint(x: x, y: y)
            marker.onTap = { [weak self] id in self?.delegate?.textReader(didTapNoteMarker: id) }
            host.addSubview(marker)
        }
    }

    // MARK: - Scroll mode

    private func teardownScroll() {
        autoScroll.stop()
        scrollTextView?.removeFromSuperview()
        scrollTextView = nil
        scrollStorage = nil
        scrollRendered = nil
        footer = nil
    }

    private func teardownPaged() {
        guard let pageController else { return }
        pageController.willMove(toParent: nil)
        pageController.view.removeFromSuperview()
        pageController.removeFromParent()
        self.pageController = nil
    }

    private func showScroll(chapter: Int, locator: ReadingLocator?, atEnd: Bool = false) {
        teardownPaged()
        teardownScroll()
        chapterIndex = chapter
        let rendered = rendered(chapter)
        let width = view.bounds.width
        let inset = state.style.horizontalInset(forWidth: width)
        let (storage, layoutManager, container) = TextStack.make(attributed: rendered.attributed,
                                                           containerSize: CGSize(width: width - inset * 2, height: .greatestFiniteMagnitude))
        let textView = ReaderTextView(frame: view.bounds, textContainer: container)
        textView.textContainerInset = UIEdgeInsets(top: scrollTopInset, left: inset, bottom: scrollBottomInset, right: inset)
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.indicatorStyle = theme.isDark ? .white : .black
        textView.delegate = self
        view.insertSubview(textView, belowSubview: focusOverlay)
        scrollTextView = textView
        scrollStorage = storage
        scrollRendered = rendered

        applyMarks(to: layoutManager, rendered: rendered)
        layoutManager.ensureLayout(for: container)
        chapterTextHeight = layoutManager.usedRect(for: container).height
        delegate?.textReader(didMeasureChapter: chapter, height: chapterTextHeight)

        let next = content.chapter(chapter + 1)
        let footer = ChapterFooterView(nextTitle: next?.title, theme: theme, font: state.style.bodyFont)
        footer.frame = CGRect(x: 0, y: scrollTopInset + chapterTextHeight + 56, width: width, height: 120)
        footer.autoresizingMask = [.flexibleWidth]
        footer.onTap = { [weak self] in self?.changeChapter(by: 1) }
        textView.addSubview(footer)
        self.footer = footer

        installNoteMarkers(textView: textView, host: textView, rendered: rendered, characterRange: nil)
        textView.layoutIfNeeded()

        if atEnd {
            textView.contentOffset.y = maxScrollOffset(textView)
        } else if let locator, locator.chapter == chapter {
            scroll(to: rendered.characterIndex(for: locator), in: textView, topFraction: nil, animated: false)
        }
        autoScroll.scrollView = textView
        lastReported = nil
        reportPosition(force: true)
        updateFocus(animated: false)
    }

    private func maxScrollOffset(_ scrollView: UIScrollView) -> CGFloat {
        max(scrollView.contentSize.height - scrollView.bounds.height, 0)
    }

    /// Scrolls so the line containing `characterIndex` sits at the reading start (or at `topFraction` of the screen).
    private func scroll(to characterIndex: Int, in textView: UITextView, topFraction: CGFloat?, animated: Bool) {
        let layoutManager = textView.layoutManager
        let length = textView.textStorage.length
        guard length > 0 else { return }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(max(characterIndex, 0), length - 1))
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        var target = line.minY + textView.textContainerInset.top - scrollTopInset
        if let topFraction { target = line.minY + textView.textContainerInset.top - textView.bounds.height * topFraction }
        if characterIndex == 0 { target = 0 }
        target = min(max(target, 0), maxScrollOffset(textView))
        textView.setContentOffset(CGPoint(x: 0, y: target), animated: animated)
    }

    // MARK: - Paged mode

    private var pageInsets: UIEdgeInsets {
        let horizontal = state.style.horizontalInset(forWidth: view.bounds.width)
        return UIEdgeInsets(top: safeTop + 50, left: horizontal, bottom: max(safeBottom, 16) + 40, right: horizontal)
    }

    private var pageSize: CGSize {
        let insets = pageInsets
        return CGSize(width: floor(view.bounds.width - insets.left - insets.right),
                      height: floor(view.bounds.height - insets.top - insets.bottom))
    }

    func chapterLayout(_ index: Int) -> ChapterLayout {
        if let cached = layoutCache[index] { return cached }
        let layout = ChapterLayout(rendered: rendered(index), pageSize: pageSize)
        applyMarks(to: layout.layoutManager, rendered: layout.rendered)
        layoutCache[index] = layout
        // Keep memory bounded: current chapter and its neighbours.
        for key in layoutCache.keys where abs(key - index) > 2 && abs(key - chapterIndex) > 1 {
            layoutCache[key] = nil
        }
        return layout
    }

    var currentPage: TextPageViewController? {
        pageController?.viewControllers?.first as? TextPageViewController
    }

    private func makePage(_ layout: ChapterLayout, _ page: Int) -> TextPageViewController {
        let insets = pageInsets
        let frame = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: layout.pageSize)
        let controller = TextPageViewController(layout: layout, pageIndex: min(page, layout.pageCount - 1),
                                                frame: frame, theme: theme, delegate: self)
        controller.loadViewIfNeeded()
        controller.applyMarks(marks(for: layout.rendered))
        livePages.add(controller)
        installNoteMarkers(textView: controller.textView, host: controller.view, rendered: layout.rendered,
                           characterRange: controller.characterRange, characterOffset: controller.characterOffset)
        return controller
    }

    private func showPaged(chapter: Int, locator: ReadingLocator?, atEnd: Bool = false) {
        teardownScroll()
        teardownPaged()
        chapterIndex = chapter

        let curl = state.pageTurn == .curl
        let controller = UIPageViewController(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl ? [.spineLocation: UIPageViewController.SpineLocation.min.rawValue] : [.interPageSpacing: 0]
        )
        controller.dataSource = self
        controller.delegate = self
        controller.view.backgroundColor = theme.background
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(controller.view, belowSubview: focusOverlay)
        controller.didMove(toParent: self)
        if curl {
            // We handle edge taps ourselves.
            controller.gestureRecognizers.filter { $0 is UITapGestureRecognizer }.forEach { $0.isEnabled = false }
        }
        pageController = controller

        let layout = chapterLayout(chapter)
        var page = 0
        if atEnd {
            page = layout.pageCount - 1
        } else if let locator, locator.chapter == chapter {
            page = layout.pageIndex(containing: layout.rendered.characterIndex(for: locator))
        }
        controller.setViewControllers([makePage(layout, page)], direction: .forward, animated: false)
        pagedFocusIndex = atEnd ? Int.max : 0
        lastReported = nil
        pageDidChange()
    }

    func turnPage(forward: Bool) {
        guard let controller = pageController, let current = controller.viewControllers?.first else { return }
        let target = forward
            ? pageViewController(controller, viewControllerAfter: current)
            : pageViewController(controller, viewControllerBefore: current)
        guard let target else {
            Haptics.warning()
            return
        }
        controller.setViewControllers([target], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
            self?.pagedFocusIndex = forward ? 0 : Int.max
            self?.pageDidChange()
        }
        delegate?.textReaderDidInteract()
    }

    func pageDidChange() {
        guard let page = currentPage else { return }
        if page.layout.chapterIndex != chapterIndex {
            chapterIndex = page.layout.chapterIndex
        }
        reportPosition(force: true)
        updateFocus(animated: false)
        // Prepare neighbours so page turns across chapters stay instant.
        let chapter = chapterIndex
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.layout == .paged else { return }
            if page.pageIndex >= page.layout.pageCount - 2, self.content.chapter(chapter + 1) != nil { _ = self.chapterLayout(chapter + 1) }
            if page.pageIndex <= 1, chapter > 0 { _ = self.chapterLayout(chapter - 1) }
        }
    }

    // MARK: - Navigation

    func go(to locator: ReadingLocator, spotlight anchor: TextAnchor?) {
        guard !content.chapters.isEmpty else { return }
        spotlight = anchor
        let chapter = min(max(locator.chapter, 0), content.chapters.count - 1)
        var target = locator
        target.chapter = chapter
        if state.layout == .scroll {
            if chapter != chapterIndex || scrollTextView == nil {
                showScroll(chapter: chapter, locator: anchor == nil ? target : nil)
            } else {
                refreshMarks()
            }
            if let textView = scrollTextView, let rendered = scrollRendered {
                scroll(to: rendered.characterIndex(for: target), in: textView,
                       topFraction: anchor == nil ? nil : 0.3, animated: chapter == chapterIndex && anchor != nil)
            }
        } else {
            if chapter != chapterIndex || pageController == nil {
                showPaged(chapter: chapter, locator: target)
            } else {
                let layout = chapterLayout(chapter)
                let page = layout.pageIndex(containing: layout.rendered.characterIndex(for: target))
                pageController?.setViewControllers([makePage(layout, page)], direction: .forward, animated: false)
                pagedFocusIndex = 0
                pageDidChange()
            }
            refreshMarks()
        }
        if anchor != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                guard let self, self.spotlight == anchor else { return }
                self.spotlight = nil
                self.refreshMarks()
            }
        }
        reportPosition(force: true)
    }

    func changeChapter(by delta: Int) {
        let target = chapterIndex + delta
        guard content.chapters.indices.contains(target), !isChangingChapter else { return }
        isChangingChapter = true
        let snapshot = view.snapshotView(afterScreenUpdates: false)
        if state.layout == .scroll {
            showScroll(chapter: target, locator: delta > 0 ? ReadingLocator(chapter: target) : nil, atEnd: delta < 0)
        } else {
            showPaged(chapter: target, locator: ReadingLocator(chapter: target), atEnd: delta < 0)
        }
        if let snapshot {
            view.insertSubview(snapshot, belowSubview: focusOverlay)
            UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseOut) {
                snapshot.alpha = 0
                snapshot.transform = CGAffineTransform(translationX: 0, y: delta > 0 ? -60 : 60)
            } completion: { _ in
                snapshot.removeFromSuperview()
            }
        }
        Haptics.soft()
        isChangingChapter = false
        syncAutoScroll()
    }

    /// Keeps the block being read aloud in view.
    private func reveal(_ locator: ReadingLocator) {
        if locator.chapter != chapterIndex {
            go(to: ReadingLocator(chapter: locator.chapter, block: locator.block), spotlight: nil)
            return
        }
        if let textView = scrollTextView, let rendered = scrollRendered {
            let range = rendered.blockRanges.indices.contains(locator.block) ? rendered.blockRanges[locator.block] : NSRange()
            let glyphs = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
            let top = rect.minY + textView.textContainerInset.top - textView.contentOffset.y
            if top < safeTop + 40 || top > textView.bounds.height * 0.6 {
                scroll(to: range.location, in: textView, topFraction: 0.28, animated: true)
            }
        } else if let page = currentPage {
            let layout = page.layout
            let index = layout.rendered.characterIndex(for: locator)
            let targetPage = layout.pageIndex(containing: index)
            if targetPage != page.pageIndex {
                pageController?.setViewControllers([makePage(layout, targetPage)], direction: targetPage > page.pageIndex ? .forward : .reverse, animated: true) { [weak self] _ in
                    self?.pageDidChange()
                }
            }
        }
    }

    // MARK: - Position reporting

    func reportPosition(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - lastReportTime > 0.12 else { return }
        lastReportTime = now

        var range: VisibleRange?
        var page: Int?
        var pageCount: Int?

        if let textView = scrollTextView, let rendered = scrollRendered {
            let layoutManager = textView.layoutManager
            let container = textView.textContainer
            let used = layoutManager.usedRect(for: container)
            let topY = min(max(textView.contentOffset.y + 2, 0), max(used.maxY - 1, 0))
            let bottomY = min(max(textView.contentOffset.y + textView.bounds.height - scrollTopInset - safeBottom - 24, topY), max(used.maxY - 1, 0))
            let start = layoutManager.characterIndex(for: CGPoint(x: 2, y: topY), in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            var end = layoutManager.characterIndex(for: CGPoint(x: container.size.width - 2, y: bottomY), in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            if textView.contentOffset.y >= maxScrollOffset(textView) - 4 { end = rendered.length }
            range = VisibleRange(start: rendered.locator(forCharacterIndex: start), end: rendered.locator(forCharacterIndex: end))
        } else if let current = currentPage {
            let characters = current.characterRange
            let rendered = current.layout.rendered
            range = VisibleRange(start: rendered.locator(forCharacterIndex: characters.location),
                                 end: rendered.locator(forCharacterIndex: NSMaxRange(characters)))
            page = current.pageIndex
            pageCount = current.layout.pageCount
        }

        guard let range, force || range != lastReported else { return }
        lastReported = range
        pendingLocator = range.start
        delegate?.textReader(didMoveTo: range, page: page, pageCount: pageCount)
    }

    // MARK: - Auto scroll

    private func syncAutoScroll() {
        guard let wpm = state.autoScrollWPM, state.layout == .scroll, let textView = scrollTextView else {
            autoScroll.stop()
            return
        }
        let words = content.chapters.indices.contains(chapterIndex) ? content.chapters[chapterIndex].wordCount : 0
        autoScroll.pointsPerSecond = ReadingSpeed.pointsPerSecond(wpm: wpm, textHeight: chapterTextHeight, words: words)
        // Stop once the last line reaches the upper part of the screen.
        autoScroll.stopOffset = max(scrollTopInset + chapterTextHeight - textView.bounds.height * 0.5, 0)
        if textView.contentOffset.y >= autoScroll.stopOffset - 1 {
            autoScroll.stop()
            if state.autoScrollWPM != nil { delegate?.textReaderAutoScrollDidReachEnd() }
            return
        }
        if !autoScroll.isRunning { autoScroll.start() }
    }

    func clearSelection() {
        scrollTextView?.selectedRange = NSRange(location: 0, length: 0)
        currentPage?.textView.selectedRange = NSRange(location: 0, length: 0)
    }

    // MARK: - Taps

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        if Date().timeIntervalSince(lastSelectionClear) < 0.45 { return }
        if activeTextView?.selectedRange.length ?? 0 > 0 { return }
        if let hit = view.hitTest(point, with: nil) {
            if hit is NoteMarkerView || hit.superview is NoteMarkerView { return }
            if let footer, hit.isDescendant(of: footer) { return }
        }

        if !state.autoScrollMode, let key = footnoteHit(at: point) {
            Haptics.selection()
            delegate?.textReader(didTapFootnote: key)
            return
        }

        if !state.autoScrollMode, let (id, rect) = highlightHit(at: point) {
            Haptics.selection()
            delegate?.textReader(didTapHighlight: id, rect: rect)
            return
        }
        delegate?.textReaderDidInteract()

        if state.autoScrollMode {
            delegate?.textReaderDidTapCenter()
            return
        }

        let x = point.x / max(view.bounds.width, 1)
        if state.layout == .paged {
            if x < 0.27 {
                state.focus == .off ? turnPage(forward: false) : moveFocus(by: -1)
                return
            }
            if x > 0.73 {
                state.focus == .off ? turnPage(forward: true) : moveFocus(by: 1)
                return
            }
        } else if state.focus != .off, x < 0.27 || x > 0.73 {
            // In scroll mode, side taps nudge the text by one line.
            if let textView = scrollTextView {
                let delta = state.style.bodyFont.lineHeight + state.style.lineSpacing
                let target = min(max(textView.contentOffset.y + (x > 0.5 ? delta : -delta), 0), maxScrollOffset(textView))
                textView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
            }
            return
        }
        delegate?.textReaderDidTapCenter()
    }

    private var activeTextView: UITextView? { scrollTextView ?? currentPage?.textView }

    /// The footnote reference under `point`. Marks are tiny, so the target extends around them.
    private func footnoteHit(at point: CGPoint) -> String? {
        guard let textView = activeTextView, textView.textStorage.length > 0 else { return nil }
        let local = view.convert(point, to: textView)
        let containerPoint = CGPoint(x: local.x - textView.textContainerInset.left, y: local.y - textView.textContainerInset.top)
        let layoutManager = textView.layoutManager
        let storage = textView.textStorage
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textView.textContainer)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        for candidate in [character, character - 1, character + 1] where candidate >= 0 && candidate < storage.length {
            var effective = NSRange()
            guard let key = storage.attribute(.quoliaFootnote, at: candidate, effectiveRange: &effective) as? String else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: effective, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
            if rect.insetBy(dx: -16, dy: -14).contains(containerPoint) { return key }
        }
        return nil
    }

    /// Returns the highlight under `point` and its bounds in view coordinates.
    private func highlightHit(at point: CGPoint) -> (UUID, CGRect)? {
        guard let textView = activeTextView else { return nil }
        let rendered: RenderedChapter
        var offset = 0
        if let scrollRendered, textView === scrollTextView { rendered = scrollRendered }
        else if let page = currentPage { rendered = page.layout.rendered; offset = page.characterOffset }
        else { return nil }

        let local = view.convert(point, to: textView)
        let containerPoint = CGPoint(x: local.x - textView.textContainerInset.left, y: local.y - textView.textContainerInset.top)
        let layoutManager = textView.layoutManager
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textView.textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textView.textContainer)
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(containerPoint) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph) + offset
        let held = NSRange(location: offset, length: textView.textStorage.length)

        for mark in state.marks[rendered.index] ?? [] {
            guard let range = rendered.range(for: mark.anchor), NSLocationInRange(character, range) else { continue }
            let visible = NSIntersectionRange(range, held)
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: visible.location - offset, length: visible.length),
                                                  actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            return (mark.id, textView.convert(rect, to: view))
        }
        return nil
    }

    // MARK: - Selection

    /// `range` is in the text view's coordinates (page-local in paged mode).
    func selectionInfo(_ textView: UITextView, range: NSRange) -> TextSelectionInfo? {
        let rendered: RenderedChapter
        var offset = 0
        if textView === scrollTextView, let scrollRendered { rendered = scrollRendered }
        else if let page = pageController?.viewControllers?.compactMap({ $0 as? TextPageViewController }).first(where: { $0.textView === textView }) {
            rendered = page.layout.rendered
            offset = page.characterOffset
        } else { return nil }

        let chapterRange = NSRange(location: range.location + offset, length: range.length)
        guard range.length > 0, NSMaxRange(chapterRange) <= rendered.length else { return nil }
        let text = (rendered.attributed.string as NSString).substring(with: chapterRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var rect = CGRect.null
        if let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
           let end = textView.position(from: start, offset: range.length),
           let textRange = textView.textRange(from: start, to: end) {
            for selectionRect in textView.selectionRects(for: textRange) where selectionRect.rect.width > 0 {
                rect = rect.union(selectionRect.rect)
            }
        }
        if rect.isNull { rect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) }

        let anchor = rendered.anchor(for: chapterRange)
        let overlapping = (state.marks[rendered.index] ?? []).filter { mark in
            guard let markRange = rendered.range(for: mark.anchor) else { return false }
            return NSIntersectionRange(markRange, chapterRange).length > 0
        }.map(\.id)
        let context = content.chapters[rendered.index].block(anchor.startBlock)?.text ?? text

        return TextSelectionInfo(anchor: anchor, text: text, rect: textView.convert(rect, to: view),
                                 context: context, overlappingHighlights: overlapping)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension TextReaderController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

// MARK: - UITextViewDelegate / UIScrollViewDelegate

extension TextReaderController: UITextViewDelegate {
    func textViewDidChangeSelection(_ textView: UITextView) {
        let length = textView.selectedRange.length
        if length == 0, lastSelectionLength > 0 { lastSelectionClear = Date() }
        lastSelectionLength = length
        if length > 0 { delegate?.textReaderDidInteract() }
    }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let info = selectionInfo(textView, range: range) else { return UIMenu(children: []) }

        func action(_ title: String, _ symbol: String, attributes: UIMenuElement.Attributes = [], _ command: SelectionCommand) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol), attributes: attributes) { [weak self] _ in
                self?.delegate?.textReader(perform: command, selection: info)
                if case .copy = command {} else { self?.clearSelection() }
            }
        }

        var children: [UIMenuElement] = [action(String(localized: "Highlight", comment: "Text selection menu"), "highlighter", .highlight)]
        if !info.overlappingHighlights.isEmpty {
            children.append(action(String(localized: "Remove", comment: "Text selection menu"), "eraser", attributes: .destructive, .removeHighlights(info.overlappingHighlights)))
        }
        children += [
            action(String(localized: "Note", comment: "Text selection menu"), "note.text.badge.plus", .note),
            action(String(localized: "Copy", comment: "Text selection menu"), "doc.on.doc", .copy),
            action(String(localized: "Translate", comment: "Text selection menu"), "translate", .translate),
            action(String(localized: "Define", comment: "Text selection menu"), "character.book.closed", .define),
            action(String(localized: "Share", comment: "Text selection menu"), "square.and.arrow.up", .share),
        ]
        let aiActions = [AIAction.explain, .simplify, .summarize, .ask].map { item in
            action(item.title, item.symbol, .ai(item))
        }
        children.append(UIMenu(title: String(localized: "Ask AI"), image: UIImage(systemName: "sparkles"), children: aiActions))
        return UIMenu(children: children)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === scrollTextView else { return }
        reportPosition()
        updateFocus(animated: true)
        if scrollView.isDragging || scrollView.isDecelerating {
            delegate?.textReaderDidInteract()
        }
        let overscroll = scrollView.contentOffset.y - maxScrollOffset(scrollView)
        footer?.setArmed(overscroll > 90 && content.chapter(chapterIndex + 1) != nil && scrollView.isDragging)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === scrollTextView else { return }
        resumeAutoScrollAfterDrag = autoScroll.isRunning
        autoScroll.stop()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === scrollTextView else { return }
        let overscroll = scrollView.contentOffset.y - maxScrollOffset(scrollView)
        if overscroll > 90, content.chapter(chapterIndex + 1) != nil {
            changeChapter(by: 1)
            return
        }
        if scrollView.contentOffset.y < -90, chapterIndex > 0 {
            changeChapter(by: -1)
            return
        }
        if !decelerate { resumeAutoScrollIfNeeded() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === scrollTextView else { return }
        resumeAutoScrollIfNeeded()
    }

    private func resumeAutoScrollIfNeeded() {
        guard resumeAutoScrollAfterDrag else { return }
        resumeAutoScrollAfterDrag = false
        autoScroll.resync()
        syncAutoScroll()
    }
}

// MARK: - UIPageViewController

extension TextReaderController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? TextPageViewController else { return nil }
        if page.pageIndex > 0 { return makePage(page.layout, page.pageIndex - 1) }
        let previous = page.layout.chapterIndex - 1
        guard previous >= 0 else { return nil }
        let layout = chapterLayout(previous)
        return makePage(layout, layout.pageCount - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? TextPageViewController else { return nil }
        if page.pageIndex + 1 < page.layout.pageCount { return makePage(page.layout, page.pageIndex + 1) }
        let next = page.layout.chapterIndex + 1
        guard content.chapters.indices.contains(next) else { return nil }
        return makePage(chapterLayout(next), 0)
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        delegate?.textReaderDidInteract()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed else { return }
        if let previous = previousViewControllers.first as? TextPageViewController, let current = currentPage {
            let forward = (current.layout.chapterIndex, current.pageIndex) > (previous.layout.chapterIndex, previous.pageIndex)
            pagedFocusIndex = forward ? 0 : Int.max
        }
        pageDidChange()
    }
}
