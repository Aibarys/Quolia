import SwiftUI
import Observation

/// Lightweight, non-blocking confirmations ("Bookmark added").
@Observable
@MainActor
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var symbol: String
        var message: String
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill", duration: Duration = .seconds(2.2)) {
        dismissTask?.cancel()
        withAnimation(.qSpring) { current = Toast(symbol: symbol, message: message) }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.qSpring) { self?.current = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.symbol)
                        .foregroundStyle(Color.qAccent)
                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .floatingSurface(Capsule(), interactive: false)
                .padding(.top, 8)
                .padding(.horizontal, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .accessibilityAddTraits(.isStaticText)
            }
        }
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
