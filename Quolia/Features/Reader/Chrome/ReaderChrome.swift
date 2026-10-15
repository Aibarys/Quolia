import SwiftUI

/// The reader's interface: appears on a center tap, otherwise out of the way.
struct ReaderChrome: View {
    @Bindable var model: ReaderViewModel
    let theme: ReaderTheme
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 10) {
            ChromeButton(symbol: "chevron.down", label: "Close book", action: onClose)
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(model.book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !model.chapterTitle.isEmpty {
                    Text(model.chapterTitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                ChromeButton(symbol: "magnifyingglass", label: "Search in book") { model.activeSheet = .search }
                ChromeButton(symbol: model.isBookmarked ? "bookmark.fill" : "bookmark",
                             label: model.isBookmarked ? "Remove bookmark" : "Add bookmark",
                             tint: model.isBookmarked ? theme.accentColor : nil) { model.toggleBookmark() }
                ChromeButton(symbol: "textformat.size", label: "Reading settings") { model.activeSheet = .settings }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 26)
        .background(alignment: .top) {
            LinearGradient(stops: [
                .init(color: theme.backgroundColor, location: 0),
                .init(color: theme.backgroundColor.opacity(0.95), location: 0.6),
                .init(color: theme.backgroundColor.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Bottom

    private var bottomBar: some View {
        VStack(spacing: 14) {
            toolRow
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryInfo)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        Text(secondaryInfo)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryTextColor)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(model.progress.percentText)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.qQuick, value: Int(model.progress * 100))
                }
                ProgressScrubber(model: model, theme: theme)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 52)
        .padding(.bottom, 8)
        .background(alignment: .bottom) {
            LinearGradient(stops: [
                .init(color: theme.backgroundColor.opacity(0), location: 0),
                .init(color: theme.backgroundColor.opacity(0.96), location: 0.3),
                .init(color: theme.backgroundColor, location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var primaryInfo: String {
        if let minutes = model.minutesLeftInChapter {
            return String(localized: "\(DurationFormat.compactRemaining(minutes: minutes)) left in chapter")
        }
        return model.locationText
    }

    private var secondaryInfo: String {
        var parts: [String] = []
        if model.engine == .text {
            if let pages = model.pagesLeftInChapterText { parts.append(pages) } else { parts.append(model.locationText) }
        }
        if let book = model.minutesLeftInBook { parts.append(String(localized: "\(DurationFormat.compactRemaining(minutes: book)) left in book")) }
        return parts.joined(separator: " · ")
    }

    private var toolRow: some View {
        HStack(spacing: 0) {
            ToolButton(symbol: "list.bullet", label: "Contents") { model.activeSheet = .contents }
            Menu {
                Picker("Focus", selection: Binding(get: { model.effectiveFocus }, set: { model.setFocusMode($0) })) {
                    ForEach(FocusMode.allCases) { mode in
                        Label(mode.name, systemImage: mode.symbol).tag(mode)
                    }
                }
            } label: {
                ToolIcon(symbol: model.effectiveFocus == .off ? "scope" : "scope", active: model.effectiveFocus != .off, theme: theme)
            }
            .accessibilityLabel("Focus mode")
            ToolButton(symbol: "gauge.with.dots.needle.33percent", label: "Auto Scroll") { model.startAutoScroll() }
            ToolButton(symbol: "play.fill", label: "Start Reading Flow", prominent: true, theme: theme) { model.startFlow() }
            ToolButton(symbol: model.speech.isActive ? "headphones.circle.fill" : "headphones",
                       label: model.speech.isActive ? "Stop listening" : "Listen",
                       active: model.speech.isActive, theme: theme) { model.toggleListening() }
                .opacity(model.engine == .text ? 1 : 0.35)
                .disabled(model.engine != .text)
            ToolButton(symbol: "sparkles", label: "Ask the Book") { model.activeSheet = .ask(AIRequest()) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .floatingSurface(Capsule())
        .padding(.horizontal, 20)
    }
}

// MARK: - Controls

struct ChromeButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .floatingSurface(Circle())
        .accessibilityLabel(label)
    }
}

private struct ToolIcon: View {
    let symbol: String
    var active = false
    var prominent = false
    var theme: ReaderTheme?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: prominent ? 15 : 17, weight: .semibold))
            .foregroundStyle(prominent ? (theme?.backgroundColor ?? .white) : (active ? (theme?.accentColor ?? .accentColor) : .primary))
            .frame(width: prominent ? 40 : 44, height: prominent ? 40 : 44)
            .background {
                if prominent { Circle().fill(theme?.accentColor ?? .accentColor) }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }
}

private struct ToolButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var active = false
    var prominent = false
    var theme: ReaderTheme?
    let action: () -> Void

    init(symbol: String, label: LocalizedStringKey, active: Bool = false, prominent: Bool = false, theme: ReaderTheme? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.active = active
        self.prominent = prominent
        self.theme = theme
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ToolIcon(symbol: symbol, active: active, prominent: prominent, theme: theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Book-level scrubber with chapter ticks and a live preview while dragging.
struct ProgressScrubber: View {
    let model: ReaderViewModel
    let theme: ReaderTheme
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let value = dragValue ?? model.progress
            ZStack(alignment: .leading) {
                Capsule().fill(theme.textColor.opacity(0.12)).frame(height: 4)
                ForEach(Array(model.chapterMarkers.enumerated()), id: \.offset) { _, marker in
                    Capsule().fill(theme.textColor.opacity(0.28))
                        .frame(width: 1.5, height: 8)
                        .offset(x: width * marker)
                }
                Capsule().fill(theme.accentColor).frame(width: max(width * value, 4), height: 4)
                Circle()
                    .fill(theme.accentColor)
                    .frame(width: dragValue == nil ? 14 : 22, height: dragValue == nil ? 14 : 22)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .offset(x: min(max(width * value - (dragValue == nil ? 7 : 11), -2), width - 12))
                    .animation(.qQuick, value: dragValue == nil)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let next = min(max(gesture.location.x / max(width, 1), 0), 1)
                        if dragValue == nil { Haptics.selection() }
                        dragValue = next
                    }
                    .onEnded { _ in
                        if let dragValue { model.go(toProgress: dragValue) }
                        dragValue = nil
                    }
            )
            .overlay(alignment: .topLeading) {
                if let dragValue {
                    Text(previewTitle(dragValue))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .floatingSurface(Capsule(), interactive: false)
                        .fixedSize()
                        .offset(x: min(max(width * dragValue - 60, 0), max(width - 160, 0)), y: -40)
                }
            }
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityLabel("Book position")
        .accessibilityValue(model.progress.percentText)
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            model.go(toProgress: min(max(model.progress + (direction == .increment ? step : -step), 0), 1))
        }
    }

    private func previewTitle(_ value: Double) -> String {
        let percent = value.percentText
        if model.engine == .pdf {
            return String(localized: "Page \(min(Int(value * Double(model.pdfPageCount)) + 1, model.pdfPageCount)) · \(percent)")
        }
        guard let content = model.content, let index = model.index else { return percent }
        let locator = index.locator(forProgress: value, content: content)
        let title = content.chapter(locator.chapter)?.title ?? ""
        return title.isEmpty ? percent : "\(title) · \(percent)"
    }
}

/// Faint chapter title and position while the interface is hidden.
struct QuietProgressOverlay: View {
    let model: ReaderViewModel
    let theme: ReaderTheme

    var body: some View {
        VStack {
            Text(model.engine == .pdf ? "" : model.chapterTitle)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 60)
                .padding(.top, 14)
            Spacer()
            Text(bottomText)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .padding(.bottom, 10)
        }
        .foregroundStyle(theme.secondaryTextColor.opacity(0.85))
    }

    private var bottomText: String {
        if model.engine == .pdf { return model.locationText }
        if let page = model.pageInChapter, let count = model.pagesInChapter {
            return String(localized: "\(page + 1) of \(count)")
        }
        return model.progress.percentText
    }
}
