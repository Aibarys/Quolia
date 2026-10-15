import PDFKit
import UIKit

/// Renders PDF pages in the reader's theme.
///
/// PDFKit draws page tiles on background threads, so the active theme lives in a
/// lock-protected box. Annotations (highlights) are drawn after the color blend,
/// so they keep their true colors on dark pages.
final class ThemedPDFPage: PDFPage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _theme: ReaderTheme = .light

    static var theme: ReaderTheme {
        get { lock.withLock { _theme } }
        set { lock.withLock { _theme = newValue } }
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        let rect = bounds(for: box)
        let theme = Self.theme

        context.saveGState()
        switch theme {
        case .light:
            break
        case .sepia:
            // Paper becomes sepia; ink stays dark.
            context.setBlendMode(.multiply)
            context.setFillColor(theme.background.cgColor)
            context.fill(rect)
        case .dark, .black:
            // 1. Invert: white paper → black, black ink → white.
            context.setBlendMode(.difference)
            context.setFillColor(UIColor.white.cgColor)
            context.fill(rect)
            // 2. Soften the ink to the theme's text color.
            context.setBlendMode(.multiply)
            context.setFillColor(theme.text.cgColor)
            context.fill(rect)
            // 3. Lift black paper to the theme's background.
            context.setBlendMode(.lighten)
            context.setFillColor(theme.background.cgColor)
            context.fill(rect)
        }
        context.restoreGState()

        // Annotations are hidden from `super` (see `displaysAnnotations`) and drawn on top, untouched by the blend.
        for annotation in annotations where annotation.shouldDisplay {
            if annotation.type == PDFAnnotationSubtype.highlight.rawValue.replacingOccurrences(of: "/", with: ""),
               annotation.value(forAnnotationKey: PDFReaderController.annotationKey) != nil {
                drawHighlight(annotation, theme: theme, in: context)
            } else {
                annotation.draw(with: box, in: context)
            }
        }
    }

    /// Quolia highlights: soft rounded marks matching the reflowable reader.
    private func drawHighlight(_ annotation: PDFAnnotation, theme: ReaderTheme, in context: CGContext) {
        let color = annotation.color.withAlphaComponent(1)
        context.saveGState()
        if theme.isDark {
            // Translucent wash over light-on-dark text.
            context.setBlendMode(.normal)
            context.setFillColor(color.withAlphaComponent(0.34).cgColor)
        } else {
            // Marker effect: tints the paper, keeps ink crisp.
            context.setBlendMode(.multiply)
            context.setFillColor(color.withAlphaComponent(0.55).cgColor)
        }
        let rect = annotation.bounds.insetBy(dx: -1, dy: -0.5)
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: min(3, rect.height / 4)).cgPath)
        context.fillPath()
        context.restoreGState()
    }

    /// `super` must not draw annotations — `draw(with:to:)` draws them after the color blend.
    override var displaysAnnotations: Bool {
        get { false }
        set {}
    }
}

extension PDFSelection {
    /// One rect per visual line. PDFKit's line bounds are usually right, but some PDFs
    /// report them a whole paragraph tall; glyph boxes then give the true vertical extent.
    func glyphLineRects(on page: PDFPage) -> [CGRect] {
        let lineBounds = selectionsByLine().map { $0.bounds(for: page) }.filter { $0.width > 0 }
        let glyphLines = Self.glyphLines(of: self, on: page)
        guard !glyphLines.isEmpty else { return lineBounds }
        guard lineBounds.count == glyphLines.count else { return glyphLines }
        return zip(lineBounds, glyphLines).map { line, glyphs in
            guard line.height > glyphs.height * 1.8 else { return line }
            return CGRect(x: line.minX, y: glyphs.minY - 1, width: line.width, height: glyphs.height + 2)
        }
    }

    private static func glyphLines(of selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        var lines: [CGRect] = []
        for index in 0..<selection.numberOfTextRanges(on: page) {
            let range = selection.range(at: index, on: page)
            guard range.location != NSNotFound else { continue }
            for character in range.location..<NSMaxRange(range) {
                let glyph = page.characterBounds(at: character)
                guard glyph.width > 0, glyph.height > 0 else { continue }
                if let last = lines.last {
                    let overlap = min(last.maxY, glyph.maxY) - max(last.minY, glyph.minY)
                    if overlap > min(last.height, glyph.height) * 0.5 {
                        lines[lines.count - 1] = last.union(glyph)
                        continue
                    }
                }
                lines.append(glyph)
            }
        }
        return lines
    }
}
