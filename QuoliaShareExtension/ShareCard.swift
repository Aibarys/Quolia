import SwiftUI

/// The calm confirmation card shown inside the Share Sheet.
struct ShareCard: View {
    let model: ShareModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text(verbatim: "Quolia")
                    .font(.qSerif(.headline, weight: .semibold))
                Spacer()
                Button(model.state == .working ? "Cancel" : "Done", action: onClose)
                    .font(.subheadline.weight(.medium))
                    .tint(.qAccent)
            }

            Spacer(minLength: 0)

            Group {
                switch model.state {
                case .working:
                    ProgressView().controlSize(.large)
                case .added:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.qAccent)
                        .transition(.scale.combined(with: .opacity))
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(Color.qMuted)
                }
            }
            .frame(height: 60)

            VStack(spacing: 8) {
                Text(title)
                    .font(.qSerif(.title3, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.qMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.qBackground.ignoresSafeArea())
        .foregroundStyle(Color.qInk)
        .animation(.qSpring, value: model.state)
        .sensoryFeedback(.success, trigger: model.state) { _, new in
            if case .added = new { return true } else { return false }
        }
    }

    private var title: String {
        switch model.state {
        case .working: String(localized: "Adding to your library…")
        case .added(let names): names.count == 1 ? String(localized: "Added to Quolia") : String(localized: "\(names.count) books added to Quolia")
        case .failed: String(localized: "Couldn't add this file")
        }
    }

    private var subtitle: String {
        switch model.state {
        case .working: ""
        case .added(let names): names.count == 1
            ? String(localized: "“\(names[0])” will be waiting in your library.")
            : String(localized: "They'll be waiting in your library.")
        case .failed(let message): message
        }
    }
}
