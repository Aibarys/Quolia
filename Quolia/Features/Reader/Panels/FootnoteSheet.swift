import SwiftUI

/// The text of a footnote, shown over the page when its mark is tapped.
/// The sheet sizes itself to short notes and can grow for long ones.
struct FootnoteSheet: View {
    let footnote: Footnote

    @Environment(AppSettings.self) private var settings
    @State private var contentHeight: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Footnote \(footnote.label)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(footnote.text)
                    .font(Font(settings.reader.font.uiFont(size: 18)))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 26)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(min(max(contentHeight, 160), 520)), .large])
        .presentationDragIndicator(.visible)
    }
}
