import SwiftUI

/// The first time a book opens: how to turn pages, bring up the tools and highlight,
/// each shown by a hand on a small animated page.
@MainActor
enum ReaderGuide {
    private static let seenKey = "quolia.readerGuide.seen"

    static var shouldShow: Bool {
        #if DEBUG
        if DebugLaunch.has("-hideTips") { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }
    static func reset() { UserDefaults.standard.removeObject(forKey: seenKey) }
}

enum ReaderGuideStep: Hashable {
    case pages, scroll, tools, highlight

    var title: LocalizedStringKey {
        switch self {
        case .pages: "Turn the page"
        case .scroll: "Scroll to read"
        case .tools: "Tools are in the middle"
        case .highlight: "Highlight and take notes"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .pages: "Tap the right edge for the next page and the left edge to go back. You can swipe too."
        case .scroll: "Swipe up to keep reading. Quolia remembers your place."
        case .tools: "Tap the middle of the page for contents, focus, Reading Flow, listening and settings. Tap again to hide them."
        case .highlight: "Press and hold a word, then drag to select. Highlight the passage, add a note, look up a word or ask about it."
        }
    }
}

struct ReaderGuideView: View {
    let layout: ReaderLayout
    let theme: ReaderTheme
    let onFinish: () -> Void

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var steps: [ReaderGuideStep] { [layout == .paged ? .pages : .scroll, .tools, .highlight] }
    private var step: ReaderGuideStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(theme.colorScheme == .dark ? 0.55 : 0.3)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {} // The page underneath waits until the guide is done.
            // With large Dynamic Type the card can outgrow a short screen; then it scrolls.
            ViewThatFits(in: .vertical) {
                card.padding(20)
                ScrollView { card.padding(20) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 440)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(spacing: 0) {
            ZStack {
                GuideIllustration(step: step, theme: theme, animated: !reduceMotion)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 244)
            .background(theme.textColor.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(step.title)
                    .font(.qSerif(.title2, weight: .semibold))
                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 22)
            .padding(.horizontal, 4)
            .id(index)
            .transition(.opacity)

            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { item in
                    Capsule()
                        .fill(item == index ? theme.textColor : theme.textColor.opacity(0.18))
                        .frame(width: item == index ? 20 : 7, height: 7)
                }
            }
            .padding(.top, 18)
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                if !isLast {
                    Button("Skip", action: finish)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.secondaryTextColor)
                        .frame(minWidth: 88, minHeight: 50)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
                Button(action: next) {
                    Text(isLast ? "Start Reading" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(theme.backgroundColor)
                        .background(theme.textColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        }
        .padding(18)
        .foregroundStyle(theme.textColor)
        .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            // On dark themes the card and the dimmed page are nearly the same color.
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(theme.textColor.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
    }

    private func next() {
        guard !isLast else { return finish() }
        Haptics.light()
        withAnimation(.qSpring) { index += 1 }
    }

    private func finish() {
        Haptics.success()
        onFinish()
    }
}

// MARK: - Illustration

/// A small page in the reader's theme, drawn with lines of "text".
private enum MockPage {
    static let size = CGSize(width: 152, height: 212)
    static let inset: CGFloat = 16
    static let top: CGFloat = 24
    static let pitch: CGFloat = 14
    static let lineHeight: CGFloat = 4.5
    static let textWidth = size.width - inset * 2
    /// Body-line widths; the pattern repeats every `pattern.count` lines, so scrolling by that many loops seamlessly.
    static let pattern: [CGFloat] = [1, 0.94, 0.98, 0.62, 1, 0.9, 0.97]
    static let otherPattern: [CGFloat] = [0.96, 1, 0.7, 1, 0.93, 0.99, 0.55]

    /// Vertical center of body line `index`, below the chapter heading.
    static func lineY(_ index: Int) -> CGFloat { top + 24 + CGFloat(index) * pitch }

    /// Draws a chapter heading (when `heading` has a color) and body lines `firstLine..<firstLine + rows`.
    static func drawLines(in context: GraphicsContext, color: Color, offset: CGPoint, heading: Color?,
                          pattern: [CGFloat], firstLine: Int = 0, rows: Int = 12) {
        if let heading {
            let rect = CGRect(x: offset.x + inset, y: offset.y + top, width: textWidth * 0.5, height: 7)
            context.fill(Path(roundedRect: rect, cornerRadius: 3.5), with: .color(heading))
        }
        for row in firstLine..<(firstLine + rows) {
            let width = pattern[((row % pattern.count) + pattern.count) % pattern.count] * textWidth
            let rect = CGRect(x: offset.x + inset, y: offset.y + lineY(row) - lineHeight / 2, width: width, height: lineHeight)
            context.fill(Path(roundedRect: rect, cornerRadius: lineHeight / 2), with: .color(color))
        }
    }
}

/// Everything that moves in an illustration. Hand coordinates are fractions of the page.
private struct GuideMotion {
    var handX = 0.5
    var handY = 0.7
    var handOpacity = 0.0
    var press = 0.0
    var ripple = 0.0
    /// A ring that fills while the finger holds.
    var ring = 0.0
    var progress = 0.0
    var word = 0.0
    var menu = 0.0
}

private struct GuideIllustration: View {
    let step: ReaderGuideStep
    let theme: ReaderTheme
    let animated: Bool

    var body: some View {
        Group {
            switch step {
            case .pages: PagesScene(theme: theme, animated: animated)
            case .scroll: ScrollScene(theme: theme, animated: animated)
            case .tools: ToolsScene(theme: theme, animated: animated)
            case .highlight: HighlightScene(theme: theme, animated: animated)
            }
        }
        .frame(width: MockPage.size.width, height: MockPage.size.height)
    }
}

/// The page itself: a sheet of paper with its content clipped to it, and the hand above everything.
private struct PageFrame<Content: View, Overlay: View>: View {
    let theme: ReaderTheme
    let motion: GuideMotion
    @ViewBuilder let content: Content
    @ViewBuilder let overlay: Overlay

    var body: some View {
        content
            .frame(width: MockPage.size.width, height: MockPage.size.height)
            .background(theme.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.textColor.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .overlay(alignment: .topLeading) { overlay }
            .overlay(alignment: .topLeading) { GuideHand(motion: motion, theme: theme) }
    }
}

private struct GuideHand: View {
    let motion: GuideMotion
    let theme: ReaderTheme

    var body: some View {
        let point = CGPoint(x: motion.handX * MockPage.size.width, y: motion.handY * MockPage.size.height)
        ZStack(alignment: .topLeading) {
            Circle()
                .stroke(theme.accentColor, lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(0.4 + motion.ripple * 1.1)
                .opacity(motion.ripple > 0 ? 1 - motion.ripple : 0)
                .position(point)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.textColor)
                .shadow(color: theme.backgroundColor, radius: 0.8)
                .shadow(color: theme.backgroundColor, radius: 0.8)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                .scaleEffect(1 - motion.press * 0.12, anchor: .topLeading)
                // The fingertip, not the symbol's center, sits on the point.
                .position(x: point.x + 14, y: point.y + 18)
        }
        .frame(width: MockPage.size.width, height: MockPage.size.height, alignment: .topLeading)
        .opacity(motion.handOpacity)
        .allowsHitTesting(false)
    }
}

/// Tap zones: the edges turn pages, the middle shows the tools.
private struct TapZone: View {
    let range: ClosedRange<CGFloat>
    let theme: ReaderTheme
    let pressed: Double
    var symbol: String?

    var body: some View {
        Rectangle()
            .fill(theme.accentColor.opacity(0.07 + pressed * 0.16))
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accentColor)
                }
            }
            .frame(width: (range.upperBound - range.lowerBound) * MockPage.size.width, height: MockPage.size.height)
            .offset(x: range.lowerBound * MockPage.size.width)
    }
}

private struct PagesScene: View {
    let theme: ReaderTheme
    let animated: Bool

    var body: some View {
        if animated {
            KeyframeAnimator(initialValue: GuideMotion(), repeating: true) { scene($0) } keyframes: { _ in
                KeyframeTrack(\.handOpacity) {
                    LinearKeyframe(1, duration: 0.3); LinearKeyframe(1, duration: 4.6)
                    LinearKeyframe(0, duration: 0.3); LinearKeyframe(0, duration: 0.4)
                }
                KeyframeTrack(\.handX) {
                    MoveKeyframe(0.56)
                    CubicKeyframe(0.84, duration: 0.6); LinearKeyframe(0.84, duration: 1.9)
                    CubicKeyframe(0.16, duration: 0.7); LinearKeyframe(0.16, duration: 2.4)
                }
                KeyframeTrack(\.handY) {
                    MoveKeyframe(0.66)
                    CubicKeyframe(0.56, duration: 0.6); LinearKeyframe(0.56, duration: 5.0)
                }
                KeyframeTrack(\.press) {
                    LinearKeyframe(0, duration: 0.7); CubicKeyframe(1, duration: 0.12); CubicKeyframe(0, duration: 0.16)
                    LinearKeyframe(0, duration: 2.32); CubicKeyframe(1, duration: 0.12); CubicKeyframe(0, duration: 0.16)
                    LinearKeyframe(0, duration: 2.02)
                }
                KeyframeTrack(\.ripple) {
                    LinearKeyframe(0, duration: 0.78); LinearKeyframe(1, duration: 0.6); MoveKeyframe(0)
                    LinearKeyframe(0, duration: 2.0); LinearKeyframe(1, duration: 0.6); MoveKeyframe(0)
                    LinearKeyframe(0, duration: 1.62)
                }
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 0.86); CubicKeyframe(1, duration: 0.5); LinearKeyframe(1, duration: 2.1)
                    CubicKeyframe(0, duration: 0.5); LinearKeyframe(0, duration: 1.64)
                }
            }
        } else {
            scene(GuideMotion(handX: 0.84, handY: 0.56, handOpacity: 1))
        }
    }

    private func scene(_ motion: GuideMotion) -> some View {
        let width = MockPage.size.width
        let ink = theme.textColor.opacity(0.22)
        let headingInk = theme.textColor.opacity(0.4)
        return PageFrame(theme: theme, motion: motion) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    let shift = motion.progress * width
                    MockPage.drawLines(in: context, color: ink, offset: CGPoint(x: -shift, y: 0), heading: headingInk,
                                       pattern: MockPage.pattern, rows: 11)
                    MockPage.drawLines(in: context, color: ink, offset: CGPoint(x: width - shift, y: -24), heading: nil,
                                       pattern: MockPage.otherPattern, rows: 13)
                }
                TapZone(range: 0...0.27, theme: theme, pressed: motion.handX < 0.5 ? motion.press : 0, symbol: "chevron.left")
                TapZone(range: 0.73...1, theme: theme, pressed: motion.handX > 0.5 ? motion.press : 0, symbol: "chevron.right")
            }
        } overlay: {
            EmptyView()
        }
    }
}

private struct ScrollScene: View {
    let theme: ReaderTheme
    let animated: Bool

    var body: some View {
        if animated {
            KeyframeAnimator(initialValue: GuideMotion(), repeating: true) { scene($0) } keyframes: { _ in
                KeyframeTrack(\.handOpacity) {
                    LinearKeyframe(1, duration: 0.25); LinearKeyframe(1, duration: 1.45)
                    LinearKeyframe(0, duration: 0.3); LinearKeyframe(0, duration: 1.6)
                }
                KeyframeTrack(\.handX) { MoveKeyframe(0.62); LinearKeyframe(0.62, duration: 3.6) }
                KeyframeTrack(\.handY) {
                    MoveKeyframe(0.8)
                    LinearKeyframe(0.8, duration: 0.35); CubicKeyframe(0.34, duration: 1.0); LinearKeyframe(0.34, duration: 2.25)
                }
                KeyframeTrack(\.press) {
                    LinearKeyframe(0, duration: 0.25); CubicKeyframe(1, duration: 0.1); LinearKeyframe(1, duration: 1.0)
                    CubicKeyframe(0, duration: 0.15); LinearKeyframe(0, duration: 2.1)
                }
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 0.35); CubicKeyframe(1, duration: 1.0); LinearKeyframe(1, duration: 2.25)
                }
            }
        } else {
            scene(GuideMotion(handX: 0.62, handY: 0.5, handOpacity: 1))
        }
    }

    private func scene(_ motion: GuideMotion) -> some View {
        // One full pattern of lines per swipe: the finger travels the same distance, so the loop is seamless.
        let cycle = CGFloat(MockPage.pattern.count) * MockPage.pitch
        let ink = theme.textColor.opacity(0.22)
        return PageFrame(theme: theme, motion: motion) {
            Canvas { context, _ in
                MockPage.drawLines(in: context, color: ink, offset: CGPoint(x: 0, y: -motion.progress * cycle - 24),
                                   heading: nil, pattern: MockPage.pattern, firstLine: -3, rows: 25)
            }
        } overlay: {
            EmptyView()
        }
    }
}

private struct ToolsScene: View {
    let theme: ReaderTheme
    let animated: Bool

    var body: some View {
        if animated {
            KeyframeAnimator(initialValue: GuideMotion(), repeating: true) { scene($0) } keyframes: { _ in
                KeyframeTrack(\.handOpacity) {
                    LinearKeyframe(1, duration: 0.3); LinearKeyframe(1, duration: 3.9)
                    LinearKeyframe(0, duration: 0.3); LinearKeyframe(0, duration: 0.7)
                }
                KeyframeTrack(\.handX) { MoveKeyframe(0.64); CubicKeyframe(0.5, duration: 0.6); LinearKeyframe(0.5, duration: 4.6) }
                KeyframeTrack(\.handY) { MoveKeyframe(0.74); CubicKeyframe(0.5, duration: 0.6); LinearKeyframe(0.5, duration: 4.6) }
                KeyframeTrack(\.press) {
                    LinearKeyframe(0, duration: 0.7); CubicKeyframe(1, duration: 0.12); CubicKeyframe(0, duration: 0.16)
                    LinearKeyframe(0, duration: 2.12); CubicKeyframe(1, duration: 0.12); CubicKeyframe(0, duration: 0.16)
                    LinearKeyframe(0, duration: 1.82)
                }
                KeyframeTrack(\.ripple) {
                    LinearKeyframe(0, duration: 0.78); LinearKeyframe(1, duration: 0.6); MoveKeyframe(0)
                    LinearKeyframe(0, duration: 1.8); LinearKeyframe(1, duration: 0.6); MoveKeyframe(0)
                    LinearKeyframe(0, duration: 1.42)
                }
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 0.86); CubicKeyframe(1, duration: 0.4); LinearKeyframe(1, duration: 1.94)
                    CubicKeyframe(0, duration: 0.35); LinearKeyframe(0, duration: 1.65)
                }
            }
        } else {
            scene(GuideMotion(handX: 0.5, handY: 0.5, handOpacity: 1, progress: 1))
        }
    }

    private func scene(_ motion: GuideMotion) -> some View {
        let ink = theme.textColor.opacity(0.22)
        let headingInk = theme.textColor.opacity(0.4)
        let surface = theme.backgroundColor
        let edge = theme.textColor.opacity(0.14)
        return PageFrame(theme: theme, motion: motion) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    MockPage.drawLines(in: context, color: ink, offset: .zero, heading: headingInk, pattern: MockPage.pattern, rows: 11)
                }
                .opacity(1 - motion.progress * 0.4)
                TapZone(range: 0.27...0.73, theme: theme, pressed: motion.press)
                // The reader's top bar and tool row, sliding in.
                VStack {
                    HStack(spacing: 5) {
                        Circle().fill(edge).frame(width: 13, height: 13)
                        Spacer()
                        Capsule().fill(edge).frame(width: 44, height: 5)
                        Spacer()
                        ForEach(0..<2, id: \.self) { _ in Circle().fill(edge).frame(width: 13, height: 13) }
                    }
                    .padding(.horizontal, 9)
                    .padding(.top, 9)
                    .offset(y: (1 - motion.progress) * -30)
                    Spacer()
                    HStack(spacing: 9) {
                        ForEach(0..<6, id: \.self) { item in
                            Circle()
                                .fill(item == 3 ? theme.accentColor : edge)
                                .frame(width: item == 3 ? 12 : 8, height: item == 3 ? 12 : 8)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(edge, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(.bottom, 12)
                    .offset(y: (1 - motion.progress) * 40)
                }
                .frame(width: MockPage.size.width, height: MockPage.size.height)
                .opacity(motion.progress)
            }
        } overlay: {
            EmptyView()
        }
    }
}

private struct HighlightScene: View {
    let theme: ReaderTheme
    let animated: Bool

    /// The line the finger selects.
    private static let line = 3
    private static let start = 0.2
    private static let end = 0.82
    private static var lineFraction: Double { MockPage.lineY(line) / MockPage.size.height }

    var body: some View {
        if animated {
            KeyframeAnimator(initialValue: GuideMotion(), repeating: true) { scene($0) } keyframes: { _ in
                KeyframeTrack(\.handOpacity) {
                    LinearKeyframe(1, duration: 0.3); LinearKeyframe(1, duration: 2.6)
                    LinearKeyframe(0, duration: 0.3); LinearKeyframe(0, duration: 2.4)
                }
                KeyframeTrack(\.handX) {
                    MoveKeyframe(0.42)
                    CubicKeyframe(Self.start + 0.06, duration: 0.5); LinearKeyframe(Self.start + 0.06, duration: 0.95)
                    CubicKeyframe(Self.end, duration: 0.8); LinearKeyframe(Self.end, duration: 3.35)
                }
                KeyframeTrack(\.handY) {
                    MoveKeyframe(0.72)
                    CubicKeyframe(Self.lineFraction, duration: 0.5); LinearKeyframe(Self.lineFraction, duration: 5.1)
                }
                KeyframeTrack(\.press) {
                    LinearKeyframe(0, duration: 0.55); CubicKeyframe(1, duration: 0.12); LinearKeyframe(1, duration: 1.58)
                    CubicKeyframe(0, duration: 0.15); LinearKeyframe(0, duration: 3.2)
                }
                KeyframeTrack(\.ring) {
                    LinearKeyframe(0, duration: 0.67); LinearKeyframe(1, duration: 0.75); MoveKeyframe(0)
                    LinearKeyframe(0, duration: 4.18)
                }
                KeyframeTrack(\.word) {
                    LinearKeyframe(0, duration: 1.42); MoveKeyframe(1); LinearKeyframe(1, duration: 3.38)
                    LinearKeyframe(0, duration: 0.3); LinearKeyframe(0, duration: 0.5)
                }
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 1.45); CubicKeyframe(1, duration: 0.8); LinearKeyframe(1, duration: 3.35)
                }
                KeyframeTrack(\.menu) {
                    LinearKeyframe(0, duration: 2.4); CubicKeyframe(1, duration: 0.35); LinearKeyframe(1, duration: 1.85)
                    LinearKeyframe(0, duration: 0.25); LinearKeyframe(0, duration: 0.75)
                }
            }
        } else {
            scene(GuideMotion(handX: Self.end, handY: Self.lineFraction, handOpacity: 1, progress: 1, word: 1, menu: 1))
        }
    }

    private func scene(_ motion: GuideMotion) -> some View {
        let width = MockPage.size.width
        let ink = theme.textColor.opacity(0.22)
        let headingInk = theme.textColor.opacity(0.4)
        let y = MockPage.lineY(Self.line)
        let firstWord = 0.12
        let selectionEnd = Self.start + motion.word * firstWord + motion.progress * (Self.end - Self.start - firstWord)
        return PageFrame(theme: theme, motion: motion) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(HighlightColor.yellow.color.opacity(0.55))
                    .frame(width: max((selectionEnd - Self.start) * width, 0), height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: Self.start * width, y: y - 6)
                    .opacity(motion.word)
                Canvas { context, _ in
                    MockPage.drawLines(in: context, color: ink, offset: .zero, heading: headingInk, pattern: MockPage.pattern, rows: 11)
                }
            }
        } overlay: {
            ZStack(alignment: .topLeading) {
                // The finger's hold ring.
                Circle()
                    .trim(from: 0, to: motion.ring)
                    .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)
                    .opacity(motion.ring > 0 ? 1 : 0)
                    .position(x: motion.handX * width, y: y)
                // The selection menu: highlight, note, define, ask.
                HStack(spacing: 10) {
                    ForEach(["highlighter", "note.text", "character.book.closed", "sparkles"], id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(symbol == "highlighter" ? theme.accentColor : theme.backgroundColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.textColor.opacity(0.88), in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .fixedSize()
                .scaleEffect(0.6 + motion.menu * 0.4, anchor: .bottom)
                .opacity(motion.menu)
                .position(x: (Self.start + Self.end) / 2 * width, y: y - 26)
            }
            .frame(width: width, height: MockPage.size.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}
