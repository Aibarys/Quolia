import SwiftUI

struct ProgressBar: View {
    var progress: Double
    var height: CGFloat = 3
    var tint: Color = .qAccent
    var track: Color = .qHairline

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: max(proxy.size.width * min(max(progress, 0), 1), progress > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(progress.percentText)
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var tint: Color = .qAccent

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.qSpring, value: progress)
        }
    }
}

struct FilterChip: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .foregroundStyle(isSelected ? Color.qBackground.opacity(0.7) : .qMuted)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.qBackground : .qInk)
            .background(isSelected ? Color.qInk : Color.qSurfaceSecondary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.qQuick, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TagChip: View {
    let tag: String
    var isSelected = false

    var body: some View {
        Text("#\(tag)")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.qBackground : Color.qAccent)
            .background(isSelected ? Color.qAccent : Color.qAccentSoft, in: Capsule())
    }
}

struct ColorDot: View {
    let color: HighlightColor
    var isSelected = false
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay {
                Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
                    .padding(-4)
            }
            .padding(4)
            .accessibilityLabel(color.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.qSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.qHairline, lineWidth: 0.5)
            }
    }
}

/// Floating control surface: Liquid Glass on iOS 26, material elsewhere.
struct FloatingSurface<S: Shape>: ViewModifier {
    var shape: S
    var interactive = true

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Color.qHairline, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 18) -> some View { modifier(CardBackground(padding: padding)) }

    func floatingSurface<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        modifier(FloatingSurface(shape: shape, interactive: interactive))
    }

    /// The main action on a screen: an ink-filled button. Ink turns light in dark mode, and the
    /// prominent style always draws a white label, so the label takes the background color.
    func inkProminentButtonStyle() -> some View {
        buttonStyle(.borderedProminent)
            .tint(.qInk)
            .foregroundStyle(Color.qBackground)
    }
}

/// Simple wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension Date {
    /// "Today", "Yesterday", "3 days ago", "Mar 4" — localized.
    var quietRelative: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return String(localized: "Today") }
        if calendar.isDateInYesterday(self) { return String(localized: "Yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 7 {
            return RelativeFormat.string(from: DateComponents(day: -days)).capitalizedFirstLetter
        }
        return formatted(.dateTime.month(.abbreviated).day().year(calendar.isDate(self, equalTo: .now, toGranularity: .year) ? .omitted : .defaultDigits))
    }
}

enum RelativeFormat {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    static func string(from components: DateComponents) -> String {
        formatter.localizedString(from: components)
    }
}

extension Double {
    /// Locale-aware whole percent: "42%" / "42 %".
    var percentText: String { formatted(.percent.precision(.fractionLength(0))) }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

enum DurationFormat {
    private static let minutesFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.minute]
        return formatter
    }()

    private static let hoursFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// "27 min", "4h 32m" (localized by the system: "27 мин", "4 ч 32 мин").
    static func short(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 {
            return seconds > 0 ? String(localized: "<1 min") : (minutesFormatter.string(from: 0) ?? "0")
        }
        let interval = TimeInterval(minutes * 60)
        if minutes < 60 { return minutesFormatter.string(from: interval) ?? "\(minutes)" }
        return hoursFormatter.string(from: interval) ?? "\(minutes)"
    }

    /// Remaining-time estimate, rounded up.
    static func compactRemaining(minutes: Double) -> String {
        minutes < 1 ? String(localized: "<1 min") : short(minutes.rounded(.up) * 60)
    }
}
