import UIKit

/// Focus Mode: keeps the current line or paragraph bright and softly dims the rest.
extension TextReaderController {
    /// Vertical position of the "reading line" in scroll mode, as a fraction of the screen.
    static let readingLineFraction: CGFloat = 0.38

    private var effectiveFocus: FocusMode { state.speech != nil ? .paragraph : state.focus }

    func updateFocus(animated: Bool) {
        let mode = effectiveFocus
        guard mode != .off else {
            focusOverlay.update(nil, unitChanged: true, animated: animated)
            focusedUnit = nil
            return
        }
        let unit: (key: Int, rect: CGRect)?
        if let textView = scrollTextView, let rendered = scrollRenderedChapter {
            unit = scrollFocusUnit(textView: textView, rendered: rendered, mode: mode)
        } else if let page = currentPage {
            let units = pagedFocusUnits(page: page, mode: mode)
            if let speech = state.speech, speech.chapter == page.layout.chapterIndex,
               let match = units.first(where: { $0.key == speech.block }) {
                unit = match
            } else if units.isEmpty {
                unit = nil
            } else {
                pagedFocusIndex = min(max(pagedFocusIndex, 0), units.count - 1)
                unit = units[pagedFocusIndex]
            }
        } else {
            unit = nil
        }
        guard let unit else {
            focusOverlay.update(nil, unitChanged: true, animated: animated)
            return
        }
        let changed = unit.key != focusedUnit
        focusedUnit = unit.key
        focusOverlay.update(unit.rect, unitChanged: changed, animated: animated)
    }

    /// Moves focus to the next/previous line or paragraph, turning pages at the edges.
    func moveFocus(by delta: Int) {
        guard let page = currentPage else { return }
        let units = pagedFocusUnits(page: page, mode: effectiveFocus)
        let next = min(max(pagedFocusIndex, 0), max(units.count - 1, 0)) + delta
        if next < 0 {
            turnPage(forward: false)
        } else if next >= units.count {
            turnPage(forward: true)
        } else {
            pagedFocusIndex = next
            Haptics.selection()
            updateFocus(animated: true)
        }
    }

    // MARK: - Geometry

    private func glyphBand(_ rect: CGRect, character: Int, storage: NSTextStorage) -> CGFloat {
        guard character < storage.length else { return rect.height }
        let font = (storage.attribute(.font, at: character, effectiveRange: nil) as? UIFont) ?? state.style.bodyFont
        return min(rect.height, font.lineHeight + 4)
    }

    private func trimmedParagraphRect(_ rect: CGRect, endsBlock: Bool) -> CGRect {
        var result = rect
        let trim = state.style.lineSpacing + (endsBlock ? state.style.paragraphSpacing : 0)
        result.size.height = max(rect.height - trim, min(rect.height, state.style.bodyFont.lineHeight))
        return result
    }

    private func scrollFocusUnit(textView: UITextView, rendered: RenderedChapter, mode: FocusMode) -> (key: Int, rect: CGRect)? {
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let inset = textView.textContainerInset
        let storage = textView.textStorage

        var key: Int
        var rect: CGRect
        if let speech = state.speech, speech.chapter == rendered.index, rendered.blockRanges.indices.contains(speech.block) {
            let range = rendered.blockRanges[speech.block]
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            rect = trimmedParagraphRect(layoutManager.boundingRect(forGlyphRange: glyphs, in: container), endsBlock: true)
            key = speech.block
        } else {
            let used = layoutManager.usedRect(for: container)
            let readingY = textView.contentOffset.y + view.bounds.height * Self.readingLineFraction - inset.top
            let y = min(max(readingY, 0), max(used.maxY - 1, 0))
            let glyph = layoutManager.glyphIndex(for: CGPoint(x: 4, y: y), in: container)
            switch mode {
            case .line:
                var lineRange = NSRange()
                let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &lineRange)
                let character = layoutManager.characterIndexForGlyph(at: lineRange.location)
                rect = CGRect(x: 0, y: line.minY, width: container.size.width,
                              height: glyphBand(line, character: character, storage: storage))
                key = lineRange.location
            case .paragraph, .off:
                let character = layoutManager.characterIndexForGlyph(at: glyph)
                let block = rendered.blockIndex(containing: character)
                let range = rendered.blockRanges[block]
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                rect = trimmedParagraphRect(layoutManager.boundingRect(forGlyphRange: glyphs, in: container), endsBlock: true)
                rect.origin.x = 0
                rect.size.width = container.size.width
                key = block
            }
        }
        let contentRect = rect.offsetBy(dx: inset.left, dy: inset.top)
        return (key, textView.convert(contentRect, to: view))
    }

    func pagedFocusUnits(page: TextPageViewController, mode: FocusMode) -> [(key: Int, rect: CGRect)] {
        let layout = page.layout
        let layoutManager = layout.layoutManager
        guard layout.containers.indices.contains(page.pageIndex) else { return [] }
        let container = layout.containers[page.pageIndex]
        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return [] }

        var units: [(Int, CGRect)] = []
        if mode == .line && state.speech == nil {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, used, _, lineGlyphs, _ in
                let character = layoutManager.characterIndexForGlyph(at: lineGlyphs.location)
                let rect = CGRect(x: 0, y: used.minY, width: container.size.width,
                                  height: self.glyphBand(used, character: character, storage: layout.storage))
                units.append((lineGlyphs.location, rect))
            }
        } else {
            let characters = page.characterRange
            let rendered = layout.rendered
            let first = rendered.blockIndex(containing: characters.location)
            let last = rendered.blockIndex(containing: max(NSMaxRange(characters) - 1, characters.location))
            for block in first...max(first, last) where rendered.blockRanges.indices.contains(block) {
                let blockRange = rendered.blockRanges[block]
                let intersection = NSIntersectionRange(blockRange, characters)
                guard intersection.length > 0 else { continue }
                let glyphs = layoutManager.glyphRange(forCharacterRange: intersection, actualCharacterRange: nil)
                var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
                rect = trimmedParagraphRect(rect, endsBlock: NSMaxRange(intersection) == NSMaxRange(blockRange))
                rect.origin.x = 0
                rect.size.width = container.size.width
                units.append((block, rect))
            }
        }
        return units.map { ($0.0, page.textView.convert($0.1, to: view)) }
    }
}
