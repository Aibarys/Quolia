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

    /// A full-width rect around the glyphs of `glyphRange`: from the first line's ascender to the last
    /// line's descender. Line fragments also hold line and paragraph spacing, which differ by block
    /// (headings, quotes, poems), so the band follows where the text sits, not the fragments.
    private func focusRect(glyphRange: NSRange, layoutManager: NSLayoutManager, storage: NSTextStorage,
                           width: CGFloat) -> CGRect? {
        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, used, _, lineGlyphs, _ in
            let glyphs = NSIntersectionRange(lineGlyphs, glyphRange)
            guard glyphs.length > 0 else { return }
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            var ascender: CGFloat = 0, descender: CGFloat = 0, hasAttachment = false
            storage.enumerateAttributes(in: characters) { attributes, _, _ in
                let font = attributes[.font] as? UIFont ?? self.state.style.bodyFont
                ascender = max(ascender, font.ascender)
                descender = max(descender, -font.descender)
                if attributes[.attachment] != nil { hasAttachment = true }
            }
            if hasAttachment {
                // Images rise above the font's ascender.
                top = min(top, used.minY)
                bottom = max(bottom, used.maxY)
            } else {
                let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyphs.location).y
                top = min(top, baseline - ascender)
                bottom = max(bottom, baseline + descender)
            }
        }
        guard bottom > top else { return nil }
        return CGRect(x: 0, y: top, width: width, height: bottom - top)
    }

    private func scrollFocusUnit(textView: UITextView, rendered: RenderedChapter, mode: FocusMode) -> (key: Int, rect: CGRect)? {
        let layoutManager = textView.layoutManager
        let container = textView.textContainer
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let inset = textView.textContainerInset
        let storage = textView.textStorage

        let width = container.size.width
        let key: Int
        let unitRect: CGRect?
        if let speech = state.speech, speech.chapter == rendered.index, rendered.blockRanges.indices.contains(speech.block) {
            let range = rendered.blockRanges[speech.block]
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            unitRect = focusRect(glyphRange: glyphs, layoutManager: layoutManager, storage: storage, width: width)
            key = speech.block
        } else {
            let used = layoutManager.usedRect(for: container)
            let readingY = textView.contentOffset.y + view.bounds.height * Self.readingLineFraction - inset.top
            let y = min(max(readingY, 0), max(used.maxY - 1, 0))
            let glyph = layoutManager.glyphIndex(for: CGPoint(x: 4, y: y), in: container)
            switch mode {
            case .line:
                var lineRange = NSRange()
                _ = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
                unitRect = focusRect(glyphRange: lineRange, layoutManager: layoutManager, storage: storage, width: width)
                key = lineRange.location
            case .paragraph, .off:
                let character = layoutManager.characterIndexForGlyph(at: glyph)
                let block = rendered.blockIndex(containing: character)
                let range = rendered.blockRanges[block]
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                unitRect = focusRect(glyphRange: glyphs, layoutManager: layoutManager, storage: storage, width: width)
                key = block
            }
        }
        guard let unitRect else { return nil }
        let contentRect = unitRect.offsetBy(dx: inset.left, dy: inset.top)
        return (key, textView.convert(contentRect, to: view))
    }

    func pagedFocusUnits(page: TextPageViewController, mode: FocusMode) -> [(key: Int, rect: CGRect)] {
        // The page's own text view: its layout manager may hold just this page (page-local indices).
        let layoutManager = page.textView.layoutManager
        let container = page.textView.textContainer
        let storage = page.textView.textStorage
        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return [] }

        var units: [(Int, CGRect)] = []
        if mode == .line && state.speech == nil {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphs, _ in
                let character = layoutManager.characterIndexForGlyph(at: lineGlyphs.location)
                if let rect = self.focusRect(glyphRange: lineGlyphs, layoutManager: layoutManager, storage: storage,
                                             width: container.size.width) {
                    units.append((character + page.characterOffset, rect))
                }
            }
        } else {
            let characters = page.characterRange
            let rendered = page.layout.rendered
            let first = rendered.blockIndex(containing: characters.location)
            let last = rendered.blockIndex(containing: max(NSMaxRange(characters) - 1, characters.location))
            for block in first...max(first, last) where rendered.blockRanges.indices.contains(block) {
                let blockRange = rendered.blockRanges[block]
                let intersection = NSIntersectionRange(blockRange, characters)
                guard intersection.length > 0, let local = page.localRange(intersection) else { continue }
                let glyphs = layoutManager.glyphRange(forCharacterRange: local, actualCharacterRange: nil)
                if let rect = focusRect(glyphRange: glyphs, layoutManager: layoutManager, storage: storage,
                                        width: container.size.width) {
                    units.append((block, rect))
                }
            }
        }
        return units.map { ($0.0, page.textView.convert($0.1, to: view)) }
    }
}
