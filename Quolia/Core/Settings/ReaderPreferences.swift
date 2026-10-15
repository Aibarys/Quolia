import SwiftUI
import UIKit

enum ReaderTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case light, sepia, dark, black

    var id: String { rawValue }

    var name: String {
        switch self {
        case .light: String(localized: "Light", comment: "Reader theme")
        case .sepia: String(localized: "Sepia", comment: "Reader theme")
        case .dark: String(localized: "Dark", comment: "Reader theme")
        case .black: String(localized: "Black", comment: "Reader theme (pure black for OLED)")
        }
    }

    var isDark: Bool { self == .dark || self == .black }

    var background: UIColor {
        switch self {
        case .light: UIColor(red: 0.992, green: 0.988, blue: 0.980, alpha: 1)
        case .sepia: UIColor(red: 0.961, green: 0.925, blue: 0.851, alpha: 1)
        case .dark: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)
        case .black: .black
        }
    }

    var text: UIColor {
        switch self {
        case .light: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .sepia: UIColor(red: 0.30, green: 0.22, blue: 0.16, alpha: 1)
        case .dark: UIColor(red: 0.88, green: 0.88, blue: 0.86, alpha: 1)
        case .black: UIColor(red: 0.74, green: 0.74, blue: 0.72, alpha: 1)
        }
    }

    var secondaryText: UIColor { text.withAlphaComponent(isDark ? 0.5 : 0.48) }

    var chrome: UIColor {
        switch self {
        case .light: UIColor(white: 1, alpha: 0.92)
        case .sepia: UIColor(red: 0.95, green: 0.91, blue: 0.83, alpha: 0.94)
        case .dark: UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 0.94)
        case .black: UIColor(white: 0.07, alpha: 0.94)
        }
    }

    var accent: UIColor {
        switch self {
        case .light, .sepia: UIColor(red: 0.80, green: 0.42, blue: 0.20, alpha: 1)
        case .dark, .black: UIColor(red: 0.95, green: 0.62, blue: 0.38, alpha: 1)
        }
    }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    var backgroundColor: Color { Color(uiColor: background) }
    var textColor: Color { Color(uiColor: text) }
    var secondaryTextColor: Color { Color(uiColor: secondaryText) }
    var accentColor: Color { Color(uiColor: accent) }
}

enum ReaderFont: String, Codable, CaseIterable, Identifiable, Sendable {
    case newYork, sanFrancisco, iowan, charter, georgia, palatino, baskerville, avenir

    var id: String { rawValue }

    var name: String {
        switch self {
        case .newYork: "New York"
        case .sanFrancisco: "San Francisco"
        case .iowan: "Iowan"
        case .charter: "Charter"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .baskerville: "Baskerville"
        case .avenir: "Avenir Next"
        }
    }

    private var familyName: String? {
        switch self {
        case .newYork, .sanFrancisco: nil
        case .iowan: "Iowan Old Style"
        case .charter: "Charter"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .baskerville: "Baskerville"
        case .avenir: "Avenir Next"
        }
    }

    func uiFont(size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
        var descriptor: UIFontDescriptor
        if let familyName {
            descriptor = UIFontDescriptor(fontAttributes: [.family: familyName])
        } else {
            let base = UIFont.systemFont(ofSize: size, weight: .regular).fontDescriptor
            descriptor = (self == .newYork ? base.withDesign(.serif) : base) ?? base
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styled = descriptor.withSymbolicTraits(traits) { descriptor = styled }
        let font = UIFont(descriptor: descriptor, size: size)
        // Fall back to the system serif if a family is unavailable on this OS.
        if familyName != nil, font.familyName != familyName {
            return ReaderFont.newYork.uiFont(size: size, bold: bold, italic: italic)
        }
        return font
    }

    func swiftUIFont(size: CGFloat) -> Font { Font(uiFont(size: size)) }
}

enum ReaderLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case paged, scroll
    var id: String { rawValue }
    var name: String { self == .paged ? String(localized: "Pages", comment: "Reader layout") : String(localized: "Scroll", comment: "Reader layout") }
    var symbol: String { self == .paged ? "book.pages" : "scroll" }
}

enum PageTurnStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case slide, curl
    var id: String { rawValue }
    var name: String { self == .slide ? String(localized: "Slide", comment: "Page turn style") : String(localized: "Curl", comment: "Page turn style") }
}

enum FocusMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, line, paragraph
    var id: String { rawValue }
    var name: String {
        switch self {
        case .off: String(localized: "Off", comment: "Focus mode off")
        case .line: String(localized: "Line", comment: "Focus mode")
        case .paragraph: String(localized: "Paragraph", comment: "Focus mode")
        }
    }
    var symbol: String {
        switch self {
        case .off: "circle.dashed"
        case .line: "text.line.first.and.arrowtriangle.forward"
        case .paragraph: "text.justify.left"
        }
    }
}

enum TextWidth: String, Codable, CaseIterable, Identifiable, Sendable {
    case narrow, medium, wide, full
    var id: String { rawValue }
    var name: String {
        switch self {
        case .narrow: String(localized: "Narrow", comment: "Text width")
        case .medium: String(localized: "Medium", comment: "Text width")
        case .wide: String(localized: "Wide", comment: "Text width")
        case .full: String(localized: "Full", comment: "Text width")
        }
    }
    /// Maximum line length in points.
    var maxWidth: CGFloat {
        switch self {
        case .narrow: 500
        case .medium: 620
        case .wide: 760
        case .full: 10_000
        }
    }
}

enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case leading, justified
    var id: String { rawValue }
    var name: String { self == .leading ? String(localized: "Left", comment: "Text alignment") : String(localized: "Justified", comment: "Text alignment") }
    var symbol: String { self == .leading ? "text.alignleft" : "text.justify" }
}

struct ReaderPreferences: Codable, Equatable, Sendable {
    var theme: ReaderTheme = .light
    var matchesSystemAppearance: Bool = true
    var font: ReaderFont = .newYork
    var fontSize: Double = 19
    /// Line height multiple, 1.1 ... 2.0.
    var lineSpacing: Double = 1.5
    var textWidth: TextWidth = .medium
    var alignment: TextAlignmentOption = .leading
    /// Horizontal page margins in points.
    var margins: Double = 26
    var layout: ReaderLayout = .paged
    var pageTurn: PageTurnStyle = .slide
    var focusMode: FocusMode = .off
    var hyphenation: Bool = true
    var showsProgressWhileReading: Bool = true

    static let fontSizeRange: ClosedRange<Double> = 13...34
    static let lineSpacingRange: ClosedRange<Double> = 1.15...2.1
    static let marginRange: ClosedRange<Double> = 12...64

    /// The theme actually used, honoring "match system appearance".
    func effectiveTheme(for scheme: ColorScheme) -> ReaderTheme {
        guard matchesSystemAppearance else { return theme }
        if scheme == .dark { return theme.isDark ? theme : .dark }
        return theme.isDark ? .light : theme
    }

    /// Identity of everything that affects text layout (not colors).
    var layoutSignature: String {
        "\(font.rawValue)-\(fontSize)-\(lineSpacing)-\(textWidth.rawValue)-\(alignment.rawValue)-\(margins)-\(hyphenation)"
    }
}
