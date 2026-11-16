import SwiftUI
import TipKit

/// Feature tips. Each appears where its feature lives, once, until the reader closes it or uses the feature.
/// "Show Tips Again" in Settings brings them all back, along with the reader guide.
@MainActor
enum QuoliaTips {
    nonisolated static let generationKey = "quolia.tips.generation"

    /// Bumped by "Show Tips Again". Tips carry it in their identifiers, so TipKit sees them as new
    /// without resetting its datastore, which is only possible before `Tips.configure()`.
    nonisolated private static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }

    nonisolated static func id(_ name: String) -> String { "\(name).\(generation)" }

    static func configure() {
        #if DEBUG
        if DebugLaunch.has("-hideTips") { Tips.hideAllTipsForTesting() }
        if DebugLaunch.has("-showTips") { showAgain() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    static func showAgain() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
        ReaderGuide.reset()
    }
}

// MARK: - Reader

struct ReadingFlowTip: Tip {
    var id: String { QuoliaTips.id("readingFlow") }
    var title: Text { Text("Reading Flow") }
    var message: Text? { Text("The text moves on by itself at your reading speed. Change the pace with − and +.") }
    var image: Image? { Image(systemName: "play.circle") }
}

struct FocusTip: Tip {
    var id: String { QuoliaTips.id("focus") }
    var title: Text { Text("Focus") }
    var message: Text? { Text("Keep one line or paragraph bright and dim the rest. Tap the edges of the page to move it.") }
    var image: Image? { Image(systemName: "scope") }
}

struct AskBookTip: Tip {
    var id: String { QuoliaTips.id("askBook") }
    var title: Text { Text("Ask the Book") }
    var message: Text? { Text("Ask about a character or an idea. Answers use only what you've read, so there are no spoilers.") }
    var image: Image? { Image(systemName: "sparkles") }
}

// MARK: - Tabs

struct BookMenuTip: Tip {
    var id: String { QuoliaTips.id("bookMenu") }
    var title: Text { Text("More for every book") }
    var message: Text? { Text("Press and hold a book to start Reading Flow, mark it as finished or see its details.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

struct NotesTip: Tip {
    var id: String { QuoliaTips.id("notes") }
    var title: Text { Text("All your highlights") }
    var message: Text? { Text("Search quotes and notes, filter them by book, tag or color, and export them to Markdown or PDF.") }
    var image: Image? { Image(systemName: "text.quote") }
}

struct RememberTip: Tip {
    var id: String { QuoliaTips.id("remember") }
    var title: Text { Text("Highlights come back") }
    var message: Text? { Text("Each highlight returns in a few days, then in a week, a month and later, so it stays with you. Press and hold a card to see it less often.") }
    var image: Image? { Image(systemName: "memories") }
}

// MARK: - Style

/// Quolia's tip: an accent badge whose symbol moves now and then, a serif title and a quiet close button.
struct QuoliaTipStyle: TipViewStyle {
    /// Popovers take the system's light or dark appearance, not the reader theme's,
    /// so tips in the reader pass the theme's colors explicitly.
    struct Palette {
        var ink = Color.qInk
        var muted = Color.qMuted
        var accent = Color.qAccent
    }

    var palette = Palette()

    func makeBody(configuration: Configuration) -> some View {
        QuoliaTipBody(configuration: configuration, palette: palette)
    }
}

private struct QuoliaTipBody: View {
    let configuration: TipViewStyle.Configuration
    let palette: QuoliaTipStyle.Palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // TipKit caps a popover at about 320 points, so the close button shares the title's row
        // and the message gets the full width beneath it.
        HStack(alignment: .top, spacing: 12) {
            if let image = configuration.image {
                image
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2.2)), isActive: !reduceMotion)
                    .frame(width: 36, height: 36)
                    .background(palette.accent.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    configuration.title
                        .font(.qSerif(.headline, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    Button {
                        configuration.tip.invalidate(reason: .tipClosed)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.muted)
                            .frame(width: 24, height: 24)
                            .background(palette.ink.opacity(0.08), in: Circle())
                            .contentShape(Circle().inset(by: -8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                if let message = configuration.message {
                    message
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) { action.label() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
    }
}

/// An inline tip that comes back as soon as the reader asks for tips again in Settings,
/// even on a screen that is already open.
struct InlineTip<T: Tip>: View {
    let tip: T
    @AppStorage(QuoliaTips.generationKey) private var generation = 0

    var body: some View {
        TipView(tip).id(generation)
    }
}

extension View {
    /// An inline tip in Quolia's style, placed above a screen's content.
    func quoliaTipStyle() -> some View {
        tipViewStyle(QuoliaTipStyle())
            .tipBackground(Color.qSurface)
            .tipCornerRadius(Metrics.cornerRadius)
    }
}
