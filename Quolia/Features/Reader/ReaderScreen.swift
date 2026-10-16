import SwiftUI
import SwiftData
import Translation

/// Full-screen reader presented over the library.
struct ReaderScreen: View {
    let request: ReaderRequest

    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var systemScheme
    @State private var model: ReaderViewModel?

    var body: some View {
        let theme = settings.reader.effectiveTheme(for: systemScheme)
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            if let model {
                ReaderContentView(model: model, theme: theme)
            }
        }
        .task {
            guard model == nil else { return }
            let model = ReaderViewModel(request: request, settings: settings, context: context)
            model.toasts = toasts
            self.model = model
            await model.load()
        }
    }
}

private struct ReaderContentView: View {
    @Bindable var model: ReaderViewModel
    let theme: ReaderTheme

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            switch model.loadState {
            case .loading(let progress):
                LoadingBookView(title: model.book.title, progress: progress, theme: theme)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open this book", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Close") { close() }
                }
            case .ready:
                readingSurface
                overlays
            }
        }
        .foregroundStyle(theme.textColor)
        .environment(\.colorScheme, theme.colorScheme)
        .statusBarHidden(!model.isChromeVisible)
        .persistentSystemOverlays(model.isChromeVisible ? .automatic : .hidden)
        .sheet(item: $model.activeSheet) { sheet in
            // The sheet's own container and UIKit controls follow the presentation's trait,
            // not the SwiftUI environment, so set both to the reader theme's scheme.
            sheetContent(sheet)
                .environment(\.colorScheme, theme.colorScheme)
                .preferredColorScheme(theme.colorScheme)
        }
        .translationPresentation(isPresented: $model.isTranslationPresented, text: model.translationText)
        .onChange(of: scenePhase) { _, phase in model.scenePhaseChanged(phase) }
        .onDisappear { model.close() }
    }

    @ViewBuilder
    private var readingSurface: some View {
        switch model.engine {
        case .text:
            if let content = model.content {
                TextReaderCanvas(model: model, content: content, state: model.textState(theme: theme))
                    .ignoresSafeArea()
            }
        case .pdf:
            if let url = model.pdfURL {
                PDFReaderCanvas(model: model, url: url, theme: theme, layout: model.effectiveLayout,
                                autoScrollWPM: model.isAutoScrollRunning ? settings.autoScrollWPM : nil)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if !model.isChromeVisible && model.effectiveLayout == .scroll {
            ScrollEdgeFade(theme: theme)
                .allowsHitTesting(false)
                .transition(.opacity)
        }

        if !model.isChromeVisible && !model.isFlowActive && settings.reader.showsProgressWhileReading && !model.isAutoScrollActive {
            QuietProgressOverlay(model: model, theme: theme)
                .allowsHitTesting(false)
                .transition(.opacity)
        }

        if model.isContinuingSelection {
            VStack {
                ContinueSelectionBanner { model.commands?.cancelContinuedSelection() }
                    .padding(.top, 8)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(2)
        }

        if model.isChromeVisible && !model.isFlowActive {
            ReaderChrome(model: model, theme: theme, onClose: close)
                .transition(.opacity)
        }

        if let palette = model.palette {
            HighlightPaletteOverlay(model: model, state: palette, theme: theme)
        }

        VStack {
            Spacer()
            if model.reachedChapterEnd {
                ChapterEndCard(model: model, theme: theme)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.isFlowActive {
                FlowControls(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.isAutoScrollActive {
                AutoScrollControls(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.speech.isActive && !model.isChromeVisible {
                SpeechControls(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 12)
        .animation(.qSpring, value: model.reachedChapterEnd)
        .animation(.qSpring, value: model.isAutoScrollActive)
        .animation(.qSpring, value: model.isFlowActive)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ReaderSheet) -> some View {
        switch sheet {
        case .settings:
            ReaderSettingsSheet(model: model)
        case .contents:
            ContentsSheet(model: model)
        case .search:
            BookSearchSheet(model: model)
        case .ask(let request):
            AskBookView(model: model, request: request)
        case .noteEditor(let highlight):
            NoteEditorSheet(highlight: highlight) { text, tags in
                model.saveNote(text, tags: tags, for: highlight)
            }
        case .noteCard(let highlight):
            NoteCardSheet(highlight: highlight,
                          onEdit: { model.activeSheet = .noteEditor(highlight) },
                          onDelete: { model.deleteHighlight(id: highlight.id); model.activeSheet = nil },
                          onShare: {
                              model.activeSheet = .quoteCard(QuoteDraft(text: highlight.text, bookTitle: model.book.title,
                                                                        author: model.book.author, chapterTitle: highlight.chapterTitle))
                          })
        case .define(let request):
            WordLookupSheet(request: request)
        case .quoteCard(let draft):
            QuoteCardComposer(draft: draft, coverData: model.book.coverImageData)
        case .flowSummary(let summary):
            FlowSummaryView(summary: summary, bookTitle: model.book.title) {
                model.activeSheet = nil
            }
        case .footnote(let footnote):
            FootnoteSheet(footnote: footnote)
        }
    }

    private func close() {
        model.close()
        dismiss()
    }
}

/// Shown while a selection continues onto the next page: the reader picks where it ends.
private struct ContinueSelectionBanner: View {
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .foregroundStyle(Color.qAccent)
            Text("Select where it ends")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button("Cancel", action: onCancel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.qAccent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .floatingSurface(Capsule(), interactive: false)
        .padding(.horizontal, 20)
    }
}

/// Softens the top and bottom edges where scrolling text meets the screen edge.
private struct ScrollEdgeFade: View {
    let theme: ReaderTheme

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [theme.backgroundColor, theme.backgroundColor.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
            Spacer()
            LinearGradient(colors: [theme.backgroundColor.opacity(0), theme.backgroundColor], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
        }
        .ignoresSafeArea()
    }
}

private struct LoadingBookView: View {
    let title: String
    let progress: Double?
    let theme: ReaderTheme

    var body: some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 160)
                    .tint(theme.accentColor)
                Text("Recognizing text… \(progress.percentText)")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryTextColor)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.qSerif(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
