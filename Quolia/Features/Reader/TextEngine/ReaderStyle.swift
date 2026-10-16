import UIKit

/// Fully resolved typography for the text engine.
struct ReaderStyle: Equatable {
    let preferences: ReaderPreferences
    let theme: ReaderTheme

    var fontSize: CGFloat { CGFloat(preferences.fontSize) }

    var bodyFont: UIFont { preferences.font.uiFont(size: fontSize) }

    /// Extra space between lines, derived from the line-height multiple.
    var lineSpacing: CGFloat { max(bodyFont.lineHeight * CGFloat(preferences.lineSpacing - 1), 0) }

    var paragraphSpacing: CGFloat { fontSize * 0.72 }

    var alignment: NSTextAlignment { preferences.alignment == .justified ? .justified : .natural }

    var hyphenation: Float { preferences.hyphenation || preferences.alignment == .justified ? 0.85 : 0 }

    /// Horizontal inset so lines never exceed the chosen text width.
    func horizontalInset(forWidth width: CGFloat) -> CGFloat {
        let margin = CGFloat(preferences.margins)
        let maxText = preferences.textWidth.maxWidth
        return max(margin, (width - maxText) / 2).rounded()
    }

    func textWidth(forWidth width: CGFloat) -> CGFloat {
        max(width - horizontalInset(forWidth: width) * 2, 120)
    }

    var signature: String { preferences.layoutSignature }

    static func == (lhs: ReaderStyle, rhs: ReaderStyle) -> Bool {
        lhs.preferences == rhs.preferences && lhs.theme == rhs.theme
    }
}

extension NSAttributedString.Key {
    /// Marks characters belonging to a highlight (value: UUID string).
    static let quoliaHighlight = NSAttributedString.Key("QuoliaHighlight")
    /// Marks the temporary spotlight shown after jumping to a quote.
    static let quoliaSpotlight = NSAttributedString.Key("QuoliaSpotlight")
    /// Marks a footnote reference (value: the footnote's key in `BookContent.footnotes`).
    static let quoliaFootnote = NSAttributedString.Key("QuoliaFootnote")
}
