import SwiftUI
import SwiftData

/// Shown right after onboarding: get a book into the library immediately.
struct FirstBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var isPickerPresented = false
    @State private var isLoadingSample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add your first book")
                    .font(.qTitle)
                    .foregroundStyle(Color.qInk)
                Text("Quolia reads EPUB, FB2, PDF and TXT files. Your books stay private and sync through your iCloud.")
                    .font(.body)
                    .foregroundStyle(Color.qMuted)
            }

            VStack(spacing: 12) {
                option(symbol: "folder", title: "Import from Files", subtitle: "iCloud Drive, On My iPhone, or any provider") {
                    isPickerPresented = true
                }
                option(symbol: "book.closed", title: "Try a sample book", subtitle: "“On Reading Slowly” — five short essays",
                       isLoading: isLoadingSample) {
                    loadSample()
                }
            }

            Label("Tip: AirDrop a book or use Share → Quolia from any app.", systemImage: "square.and.arrow.down")
                .font(.footnote)
                .foregroundStyle(Color.qMuted)

            Spacer(minLength: 0)

            Button("Maybe later") { dismiss() }
                .font(.subheadline)
                .foregroundStyle(Color.qMuted)
                .frame(maxWidth: .infinity)
        }
        .padding(28)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.qBackground)
        .bookImporter(isPresented: $isPickerPresented) { books in
            dismiss()
            if let first = books.first { openSoon(first) }
        }
    }

    private func option(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, isLoading: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.qAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.qAccentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.qInk)
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.qMuted)
                }
                Spacer()
                if isLoading { ProgressView() } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.qMuted)
                }
            }
            .cardStyle(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func loadSample() {
        isLoadingSample = true
        Task {
            let outcome = await BookImporter(context: context).importSampleBook()
            isLoadingSample = false
            if let book = outcome.imported.first {
                dismiss()
                openSoon(book)
            } else if let summary = outcome.summary {
                toasts.show(summary, symbol: "info.circle.fill")
                dismiss()
            }
        }
    }

    private func openSoon(_ book: Book) {
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            router.open(book)
        }
    }
}
