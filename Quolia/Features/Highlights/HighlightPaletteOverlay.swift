import SwiftUI

/// Compact floating palette shown after highlighting or tapping a highlight:
/// colors, note, share, delete.
struct HighlightPaletteOverlay: View {
    let model: ReaderViewModel
    let state: HighlightPaletteState
    let theme: ReaderTheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let paletteWidth: CGFloat = 330
            let showAbove = state.rect.minY > 150
            let x = min(max(state.rect.midX, paletteWidth / 2 + 12), size.width - paletteWidth / 2 - 12)
            let y = showAbove ? state.rect.minY - 36 : min(state.rect.maxY + 36, size.height - 60)

            ZStack {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.qQuick) { model.palette = nil } }

                if let highlight = model.highlight(withID: state.highlightID) {
                    palette(for: highlight)
                        .position(x: x, y: y)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
    }

    private func palette(for highlight: Highlight) -> some View {
        HStack(spacing: 2) {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    model.setColor(color, for: highlight.id)
                } label: {
                    ColorDot(color: color, isSelected: highlight.color == color, size: 22)
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 24).padding(.horizontal, 4)
            iconButton("note.text", label: highlight.hasNote ? "Edit note" : "Add note") {
                model.palette = nil
                model.activeSheet = .noteEditor(highlight)
            }
            iconButton("square.and.arrow.up", label: "Share") {
                model.palette = nil
                model.activeSheet = .quoteCard(QuoteDraft(text: highlight.text, bookTitle: model.book.title,
                                                          author: model.book.author, chapterTitle: highlight.chapterTitle))
            }
            iconButton("trash", label: "Delete highlight") {
                withAnimation(.qQuick) { model.deleteHighlight(id: highlight.id) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .floatingSurface(Capsule())
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
