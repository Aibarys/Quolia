import SwiftUI
import SwiftData

/// Presents the Files picker (iCloud Drive, On My iPhone, providers) and imports the selection.
struct BookImportModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onImported: ([Book]) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @State private var isImporting = false

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented,
                          allowedContentTypes: BookFormat.importableTypes,
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return }
                isImporting = true
                Task {
                    let outcome = await BookImporter(context: context).importBooks(from: urls)
                    isImporting = false
                    toasts.show(outcome, context: context)
                    if !outcome.imported.isEmpty { onImported(outcome.imported) }
                }
            }
            .overlay {
                if isImporting {
                    ImportingIndicator()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.qQuick, value: isImporting)
    }
}

private struct ImportingIndicator: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing your book…")
                .font(.subheadline)
                .foregroundStyle(Color.qMuted)
        }
        .padding(28)
        .floatingSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
    }
}

extension View {
    func bookImporter(isPresented: Binding<Bool>, onImported: @escaping ([Book]) -> Void = { _ in }) -> some View {
        modifier(BookImportModifier(isPresented: isPresented, onImported: onImported))
    }
}
