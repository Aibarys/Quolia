import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class ReaderViewModel {
    enum LoadState: Equatable {
        case loading(Double?)
        case ready
        case failed(String)
    }

    enum Engine { case text, pdf }

    let book: Book
    let settings: AppSettings
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored private let service: HighlightService
    @ObservationIgnored weak var commands: ReaderCommands?
    @ObservationIgnored weak var toasts: ToastCenter?
    @ObservationIgnored private var session: ReadingSessionTracker?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var flowStart: (date: Date, seconds: Double, words: Int, chapters: Int, highlights: Int, notes: Int)?
    @ObservationIgnored private let request: ReaderRequest
    @ObservationIgnored private var didAutoStartFlow = false
    @ObservationIgnored private var startLocatorOverride: ReadingLocator?

    private(set) var loadState: LoadState = .loading(nil)
    private(set) var engine: Engine = .text
    private(set) var content: BookContent?
    @ObservationIgnored private(set) var index: ContentIndex?
    private(set) var pdfURL: URL?
    let imagesDirectory: URL

    // Position
    private(set) var visibleRange = VisibleRange(start: .start, end: .start)
    private(set) var pageInChapter: Int?
    private(set) var pagesInChapter: Int?
    /// Pages in each chapter with the current layout, counted in the background (paged mode).
    var bookPageCounts: [Int]?
    /// A selection started on an earlier page waits for its end on a later one.
    var isContinuingSelection = false
    private(set) var progress: Double
    private(set) var pdfPage = 0
    private(set) var pdfPageCount = 0
    let initialLocator: ReadingLocator
    /// Where the text engine opens (differs from `initialLocator` for reflowed PDFs).
    private(set) var startLocator: ReadingLocator
    let initialSpotlight: TextAnchor?

    // Interface
    var isChromeVisible = true
    var activeSheet: ReaderSheet?
    var palette: HighlightPaletteState?
    var translationText = ""
    var isTranslationPresented = false

    // Modes
    private(set) var layoutOverride: ReaderLayout?
    private(set) var focusOverride: FocusMode?
    private(set) var isAutoScrollActive = false
    var isAutoScrollRunning = false
    private(set) var reachedChapterEnd = false
    private(set) var isFlowActive = false
    let speech = SpeechController()

    // Highlights
    private(set) var marks: [Int: [HighlightMark]] = [:]
    private(set) var highlightsVersion = 0

    init(request: ReaderRequest, settings: AppSettings, context: ModelContext) {
        self.request = request
        self.book = request.book
        self.settings = settings
        self.context = context
        self.service = HighlightService(context: context)
        self.progress = request.book.progress
        self.imagesDirectory = ContentCache.imagesDirectory(for: request.book.id)
        self.initialLocator = request.locator ?? request.book.locator
        self.startLocator = request.locator ?? request.book.locator
        if let id = request.highlightID, let highlight = request.book.allHighlights.first(where: { $0.id == id }), !highlight.isPDFAnchored {
            self.initialSpotlight = highlight.anchor
        } else {
            self.initialSpotlight = nil
        }
        self.pdfPage = initialLocator.page
    }

    // MARK: - Loading

    func load() async {
        book.lastOpenedAt = .now
        if book.status == .wantToRead { book.status = .reading }
        marks = HighlightService.marks(for: book)

        let source = BookSource(book: book)
        do {
            if book.format == .pdf && !book.prefersReflow {
                engine = .pdf
                pdfURL = try await BookFileStore.shared.availableURL(for: book.fileName)
                pdfPageCount = max(book.pageCount, 1)
                progress = Double(pdfPage + 1) / Double(pdfPageCount)
                loadState = .ready
                startSession(words: Int(Double(book.totalWords) * progress), chapter: 0)
                // Text layer for search, AI and stats — loaded quietly in the background.
                if let content = try? await ContentLoader.shared.content(for: source) {
                    self.content = content
                    self.index = ContentIndex(content: content)
                }
            } else {
                engine = .text
                let content = try await ContentLoader.shared.content(for: source, allowOCR: book.format == .pdf) { value in
                    Task { @MainActor [weak self] in self?.loadState = .loading(value) }
                }
                self.content = content
                let index = ContentIndex(content: content)
                self.index = index
                if book.totalWords == 0 { book.totalWords = content.totalWords }
                if book.chapterCount == 0 { book.chapterCount = content.chapters.count }
                let start = startLocatorOverride
                    ?? (book.format == .pdf && request.locator == nil ? content.locator(forPage: book.locPage) : initialLocator)
                startLocator = start
                visibleRange = VisibleRange(start: start, end: start)
                progress = index.progress(of: start, content: content)
                loadState = .ready
                startSession(words: index.wordsBefore(start, content: content), chapter: start.chapter)
            }
            #if DEBUG
            if let sheet = DebugLaunch.pendingReaderSheet {
                DebugLaunch.pendingReaderSheet = nil
                try? await Task.sleep(for: .milliseconds(500))
                switch sheet {
                case "settings": activeSheet = .settings
                case "contents": activeSheet = .contents
                case "search": activeSheet = .search
                case "ask": activeSheet = .ask(AIRequest())
                case "chromeHidden": isChromeVisible = false
                case "quote":
                    let text = book.allHighlights.first?.text ?? "A thought revisited becomes a thought kept."
                    activeSheet = .quoteCard(QuoteDraft(text: text, bookTitle: book.title, author: book.author, chapterTitle: chapterTitle))
                case "define":
                    activeSheet = .define(WordLookupRequest(term: "garden", context: content?.chapter(chapterIndex)?.block(1)?.text,
                                                            language: book.language, bookTitle: book.title))
                case "flowSummary":
                    activeSheet = .flowSummary(FlowSummary(seconds: 27 * 60, words: 6_100, chapters: 2, highlights: 3, notes: 1))
                default: break
                }
            }
            #endif
            if request.startsReadingFlow && !didAutoStartFlow {
                didAutoStartFlow = true
                try? await Task.sleep(for: .milliseconds(700))
                startFlow()
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func startSession(words: Int, chapter: Int) {
        guard session == nil else { return }
        let tracker = ReadingSessionTracker(startWords: words, chapter: chapter)
        tracker.keepsAlive = { [weak self] in
            guard let self else { return false }
            return self.isAutoScrollRunning || (self.speech.isActive && !self.speech.isPaused)
        }
        tracker.start()
        session = tracker
    }

    // MARK: - Derived state

    var effectiveLayout: ReaderLayout { layoutOverride ?? settings.reader.layout }
    var effectiveFocus: FocusMode { focusOverride ?? settings.reader.focusMode }
    var chapterIndex: Int { visibleRange.start.chapter }

    var chapterTitle: String {
        if engine == .pdf { return String(localized: "Page \(pdfPage + 1)") }
        return content?.chapter(chapterIndex)?.title ?? ""
    }

    func textState(theme: ReaderTheme) -> TextReaderState {
        TextReaderState(
            style: ReaderStyle(preferences: settings.reader, theme: theme),
            layout: effectiveLayout,
            pageTurn: settings.reader.pageTurn,
            focus: effectiveFocus,
            marks: marks,
            autoScrollWPM: isAutoScrollRunning ? settings.autoScrollWPM : nil,
            autoScrollMode: isAutoScrollActive,
            speech: speech.currentLocator
        )
    }

    private var wordsPerMinute: Double { max(settings.measuredWPM, 80) }

    var minutesLeftInChapter: Double? {
        guard engine == .text, let content, let index else { return nil }
        return Double(index.remainingWords(inChapterFrom: visibleRange.start, content: content)) / wordsPerMinute
    }

    var minutesLeftInBook: Double? {
        if engine == .pdf {
            guard book.totalWords > 0 else { return nil }
            return Double(book.totalWords) * (1 - progress) / wordsPerMinute
        }
        guard let content, let index else { return nil }
        return Double(max(index.totalWords - index.wordsBefore(visibleRange.start, content: content), 0)) / wordsPerMinute
    }

    /// Stable, font-independent location: "Page 87 of 342".
    var locationText: String {
        if engine == .pdf { return String(localized: "Page \(pdfPage + 1) of \(pdfPageCount)") }
        guard let content, let index, index.totalWords > 0 else { return "" }
        let total = ReadingMath.pages(forWords: index.totalWords)
        let current = min(Int(Double(index.wordsBefore(visibleRange.start, content: content)) / ReadingMath.wordsPerPage) + 1, total)
        return String(localized: "Page \(current) of \(total)")
    }

    /// The current page across the whole book, once every chapter has been paginated.
    var bookPage: (current: Int, total: Int)? {
        guard let counts = bookPageCounts, let page = pageInChapter else { return nil }
        let chapter = visibleRange.start.chapter
        guard counts.indices.contains(chapter) else { return nil }
        let total = counts.reduce(0, +)
        return (min(counts.prefix(chapter).reduce(0, +) + page + 1, total), total)
    }

    var pagesLeftInChapterText: String? {
        guard let page = pageInChapter, let count = pagesInChapter else { return nil }
        let left = count - page - 1
        return left == 0 ? String(localized: "Last page in chapter") : String(localized: "\(left) pages left in chapter")
    }

    /// Chapter start positions as fractions of the book, for scrubber ticks.
    var chapterMarkers: [Double] {
        guard let content, let index, index.totalWords > 0, content.chapters.count <= 80 else { return [] }
        return index.chapterStart.dropFirst().map { Double($0) / Double(index.totalWords) }
    }

    // MARK: - Position updates

    func textDidMove(to range: VisibleRange, page: Int?, pageCount: Int?) {
        guard let content, let index else { return }
        let chapterChanged = range.start.chapter != visibleRange.start.chapter
        visibleRange = range
        pageInChapter = page
        pagesInChapter = pageCount
        progress = index.progress(of: range.start, content: content)
        palette = nil
        if chapterChanged, isAutoScrollActive { reachedChapterEnd = false }

        let page = content.chapter(range.start.chapter)?.block(range.start.block)?.page ?? book.locPage
        book.locator = ReadingLocator(chapter: range.start.chapter, block: range.start.block, offset: range.start.offset, page: page)
        book.progress = progress
        book.currentChapterTitle = content.chapter(range.start.chapter)?.title ?? ""
        session?.record(words: index.wordsBefore(range.end, content: content), chapter: range.start.chapter)
        checkFinished(endProgress: index.progress(of: range.end, content: content))
        scheduleSave()
    }

    func pdfDidMove(toPage page: Int, pageCount: Int) {
        pdfPage = page
        pdfPageCount = max(pageCount, 1)
        progress = Double(page + 1) / Double(pdfPageCount)
        palette = nil
        book.locPage = page
        book.progress = progress
        book.currentChapterTitle = String(localized: "Page \(page + 1)")
        session?.record(words: Int(Double(book.totalWords) * progress), chapter: 0)
        checkFinished(endProgress: progress)
        scheduleSave()
    }

    private func checkFinished(endProgress: Double) {
        guard endProgress >= 0.995, book.status != .finished else { return }
        book.status = .finished
        book.progress = 1
        Haptics.success()
        toasts?.show(String(localized: "You finished “\(book.title)”"), symbol: "checkmark.seal.fill")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            try? self?.context.save()
        }
    }

    func userDidInteract() { session?.markActivity() }

    // MARK: - Navigation

    func go(to locator: ReadingLocator, spotlight: TextAnchor? = nil) {
        commands?.go(to: locator, spotlight: spotlight)
        Haptics.light()
    }

    func go(toProgress fraction: Double) {
        if engine == .pdf {
            let page = min(Int(fraction * Double(pdfPageCount)), pdfPageCount - 1)
            commands?.go(to: ReadingLocator(page: max(page, 0)), spotlight: nil)
            return
        }
        guard let content, let index else { return }
        commands?.go(to: index.locator(forProgress: fraction, content: content), spotlight: nil)
    }

    func open(_ highlight: Highlight) {
        activeSheet = nil
        if highlight.isPDFAnchored {
            commands?.go(to: ReadingLocator(page: highlight.pageIndex), spotlight: nil)
        } else {
            commands?.go(to: highlight.locator, spotlight: highlight.anchor)
        }
    }

    /// Switches a PDF between its original layout and reflowed text.
    func setReflow(_ enabled: Bool) {
        guard book.format == .pdf, book.prefersReflow != enabled else { return }
        if enabled {
            startLocatorOverride = nil
        } else if let content {
            let page = content.chapter(visibleRange.start.chapter)?.block(visibleRange.start.block)?.page ?? book.locPage
            pdfPage = page
            book.locPage = page
        }
        book.prefersReflow = enabled
        try? context.save()
        activeSheet = nil
        palette = nil
        stopAutoScroll()
        speech.stop()
        commands = nil
        loadState = .loading(nil)
        Task { await load() }
    }

    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.25)) { isChromeVisible.toggle() }
        palette = nil
    }

    func close() {
        speech.stop()
        if isFlowActive || isAutoScrollActive { UIApplication.shared.isIdleTimerDisabled = false }
        isAutoScrollRunning = false
        saveTask?.cancel()
        session?.finish(book: book, context: context, settings: settings)
        session = nil
        book.lastOpenedAt = .now
        try? context.save()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active: session?.resume()
        case .background, .inactive:
            session?.pause()
            try? context.save()
        @unknown default: break
        }
    }

    // MARK: - Bookmarks

    var currentBookmarks: [Bookmark] {
        book.allBookmarks.filter { bookmark in
            if engine == .pdf { return bookmark.pageIndex == pdfPage }
            let locator = bookmark.locator
            return !locator.isBefore(visibleRange.start) && (locator.isBefore(visibleRange.end) || locator == visibleRange.start)
        }
    }

    var isBookmarked: Bool { !currentBookmarks.isEmpty }

    func toggleBookmark() {
        let existing = currentBookmarks
        if !existing.isEmpty {
            existing.forEach(service.delete)
            Haptics.light()
            toasts?.show(String(localized: "Bookmark removed"), symbol: "bookmark.slash")
            return
        }
        let locator = engine == .pdf ? ReadingLocator(page: pdfPage) : visibleRange.start
        var preview = ""
        if engine == .text, let block = content?.chapter(locator.chapter)?.block(locator.block) {
            let text = block.text as NSString
            let start = min(locator.offset, text.length)
            preview = String(text.substring(from: start).prefix(140))
        }
        service.addBookmark(to: book, locator: locator, chapterTitle: chapterTitle, preview: preview, progress: progress)
        Haptics.success()
        toasts?.show(String(localized: "Bookmarked"), symbol: "bookmark.fill")
    }

    func deleteBookmark(_ bookmark: Bookmark) { service.delete(bookmark) }

    // MARK: - Highlights

    private func reloadMarks() {
        marks = HighlightService.marks(for: book)
        highlightsVersion += 1
    }

    func highlight(withID id: UUID) -> Highlight? { book.allHighlights.first { $0.id == id } }

    private func createHighlight(_ selection: TextSelectionInfo) -> Highlight {
        let progress = (content.flatMap { content in index.map { $0.progress(of: selection.anchor.startLocator, content: content) } }) ?? self.progress
        let title = content?.chapter(selection.anchor.chapter)?.title ?? chapterTitle
        let highlight = service.createHighlight(in: book, anchor: selection.anchor, text: selection.text,
                                                chapterTitle: title, progress: progress)
        session?.didCreateHighlight()
        reloadMarks()
        return highlight
    }

    func handle(_ command: SelectionCommand, selection: TextSelectionInfo) {
        userDidInteract()
        switch command {
        case .highlight:
            let highlight = createHighlight(selection)
            palette = HighlightPaletteState(highlightID: highlight.id, rect: selection.rect)
        case .note:
            let existing = selection.overlappingHighlights.first.flatMap(highlight(withID:))
            let highlight = existing ?? createHighlight(selection)
            activeSheet = .noteEditor(highlight)
        case .copy:
            UIPasteboard.general.string = selection.text
            toasts?.show(String(localized: "Copied"), symbol: "doc.on.doc.fill")
        case .translate:
            translationText = selection.text
            isTranslationPresented = true
        case .define:
            activeSheet = .define(WordLookupRequest(term: selection.text, context: selection.context,
                                                    language: book.language, bookTitle: book.title))
        case .share:
            activeSheet = .quoteCard(QuoteDraft(text: selection.text, bookTitle: book.title, author: book.author,
                                                chapterTitle: engine == .pdf ? chapterTitle : content?.chapter(selection.anchor.chapter)?.title))
        case .removeHighlights(let ids):
            service.delete(ids: ids, in: book)
            reloadMarks()
        case .ai(let action):
            activeSheet = .ask(AIRequest(action: action, selection: selection.text))
        }
    }

    /// Selection commands from the original-layout PDF view.
    func handlePDF(_ command: SelectionCommand, page: Int, rects: [CGRect], text: String, screenRect: CGRect) {
        userDidInteract()
        switch command {
        case .highlight:
            createPDFHighlight(page: page, rects: rects, text: text, screenRect: screenRect)
        case .note:
            let highlight = service.createPDFHighlight(in: book, page: page, rects: rects, text: text, progress: progress)
            session?.didCreateHighlight()
            highlightsVersion += 1
            activeSheet = .noteEditor(highlight)
        default:
            let anchor = TextAnchor(chapter: 0, startBlock: 0, startOffset: 0, endBlock: 0, endOffset: 0)
            handle(command, selection: TextSelectionInfo(anchor: anchor, text: text, rect: screenRect,
                                                         context: text, overlappingHighlights: []))
        }
    }

    /// PDF selections arrive as page + line rects.
    func createPDFHighlight(page: Int, rects: [CGRect], text: String, screenRect: CGRect) {
        let highlight = service.createPDFHighlight(in: book, page: page, rects: rects, text: text, progress: progress)
        session?.didCreateHighlight()
        highlightsVersion += 1
        palette = HighlightPaletteState(highlightID: highlight.id, rect: screenRect)
    }

    func setColor(_ color: HighlightColor, for id: UUID) {
        guard let highlight = highlight(withID: id) else { return }
        service.setColor(color, for: highlight)
        reloadMarks()
    }

    func deleteHighlight(id: UUID) {
        guard let highlight = highlight(withID: id) else { return }
        service.delete(highlight)
        palette = nil
        reloadMarks()
    }

    func saveNote(_ text: String?, tags: [String], for highlight: Highlight) {
        let hadNote = highlight.hasNote
        service.setNote(text, tags: tags, for: highlight)
        if !hadNote && highlight.hasNote { session?.didCreateNote() }
        reloadMarks()
    }

    func presentHighlightTap(id: UUID, rect: CGRect) {
        guard let highlight = highlight(withID: id) else { return }
        if highlight.hasNote {
            activeSheet = .noteCard(highlight)
        } else {
            palette = HighlightPaletteState(highlightID: id, rect: rect)
        }
    }

    // MARK: - Auto Scroll

    func startAutoScroll() {
        guard engine == .text || engine == .pdf else { return }
        speech.stop()
        layoutOverride = .scroll
        isAutoScrollActive = true
        isAutoScrollRunning = true
        reachedChapterEnd = false
        UIApplication.shared.isIdleTimerDisabled = true
        withAnimation(.easeInOut(duration: 0.25)) { isChromeVisible = false }
        Haptics.light()
    }

    func stopAutoScroll() {
        isAutoScrollActive = false
        isAutoScrollRunning = false
        reachedChapterEnd = false
        layoutOverride = nil
        if !isFlowActive { UIApplication.shared.isIdleTimerDisabled = false }
    }

    func toggleAutoScrollRunning() {
        if reachedChapterEnd { continueToNextChapter(); return }
        isAutoScrollRunning.toggle()
        Haptics.selection()
        userDidInteract()
    }

    func adjustSpeed(by delta: Double) {
        setSpeed(settings.autoScrollWPM + delta)
        Haptics.selection()
    }

    func setSpeed(_ wpm: Double) {
        settings.autoScrollWPM = min(max(wpm.rounded(), ReadingSpeed.wpmRange.lowerBound), ReadingSpeed.wpmRange.upperBound)
    }

    func autoScrollReachedEnd() {
        isAutoScrollRunning = false
        reachedChapterEnd = true
        Haptics.soft()
    }

    func continueToNextChapter() {
        reachedChapterEnd = false
        guard let content, content.chapter(chapterIndex + 1) != nil else {
            if isFlowActive { endFlow() } else { stopAutoScroll() }
            return
        }
        commands?.changeChapter(by: 1)
        isAutoScrollRunning = true
    }

    func tapWhileAutoScrolling() {
        toggleAutoScrollRunning()
    }

    // MARK: - Focus

    func setFocusMode(_ mode: FocusMode) {
        settings.reader.focusMode = mode
        focusOverride = nil
        Haptics.selection()
    }

    // MARK: - Reading Flow

    func startFlow() {
        guard loadState == .ready else { return }
        palette = nil
        activeSheet = nil
        speech.stop()
        isFlowActive = true
        session?.isFlow = true
        if settings.reader.focusMode == .off { focusOverride = .line }
        let words = session?.wordsRead ?? 0
        flowStart = (Date(), session?.activeSeconds ?? 0, words, session?.chaptersCompleted ?? 0,
                     session?.highlightsCreated ?? 0, session?.notesCreated ?? 0)
        startAutoScroll()
    }

    func endFlow() {
        guard isFlowActive else { return }
        isFlowActive = false
        focusOverride = nil
        stopAutoScroll()
        UIApplication.shared.isIdleTimerDisabled = false
        let start = flowStart
        flowStart = nil
        let summary = FlowSummary(
            seconds: max((session?.activeSeconds ?? 0) - (start?.seconds ?? 0), Date().timeIntervalSince(start?.date ?? .now) * 0.95),
            words: max((session?.wordsRead ?? 0) - (start?.words ?? 0), 0),
            chapters: max((session?.chaptersCompleted ?? 0) - (start?.chapters ?? 0), 0),
            highlights: max((session?.highlightsCreated ?? 0) - (start?.highlights ?? 0), 0),
            notes: max((session?.notesCreated ?? 0) - (start?.notes ?? 0), 0)
        )
        withAnimation { isChromeVisible = true }
        activeSheet = .flowSummary(summary)
        Haptics.success()
    }

    // MARK: - Listen

    func toggleListening() {
        if speech.isActive {
            speech.stop()
            return
        }
        guard let content else { return }
        stopAutoScroll()
        speech.start(content: content, from: visibleRange.start, language: book.language)
        withAnimation { isChromeVisible = false }
    }

    // MARK: - Spoiler-safe context

    /// The end of what the reader has seen — the AI may never look past this point.
    var readingFrontier: ReadingLocator {
        if engine == .pdf, let content {
            // Last block whose source page is on or before the current page.
            for chapter in content.chapters.reversed() {
                if let blockIndex = chapter.blocks.lastIndex(where: { ($0.page ?? 0) <= pdfPage }) {
                    let length = (chapter.blocks[blockIndex].text as NSString).length
                    return ReadingLocator(chapter: chapter.id, block: blockIndex, offset: length)
                }
            }
            return .start
        }
        return visibleRange.end
    }

    var languageCode: String? { book.language }
}
