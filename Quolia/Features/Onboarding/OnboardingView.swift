import SwiftUI

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(title: "Your books.\nYour thoughts.",
                       subtitle: "Import and read your own books.",
                       illustration: .library),
        OnboardingPage(title: "Highlight what matters.",
                       subtitle: "Save quotes and write notes while reading.",
                       illustration: .highlight),
        OnboardingPage(title: "Remember what you read.",
                       subtitle: "Quolia brings important ideas back to you.",
                       illustration: .remember),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Quolia")
                    .font(.qSerif(.headline, weight: .semibold))
                    .foregroundStyle(Color.qInk)
                Spacer()
                if page < pages.count - 1 {
                    Button("Skip") { finish() }
                        .font(.subheadline)
                        .foregroundStyle(Color.qMuted)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .frame(height: 44)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    OnboardingPageView(page: item, isActive: page == index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.qInk : Color.qHairline)
                            .frame(width: index == page ? 22 : 7, height: 7)
                    }
                }
                .animation(.qSpring, value: page)
                .accessibilityHidden(true)

                Button {
                    if page < pages.count - 1 {
                        withAnimation(.qSpring) { page += 1 }
                        Haptics.light()
                    } else {
                        finish()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Start Reading" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .foregroundStyle(Color.qBackground)
                        .background(Color.qInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Color.qBackground.ignoresSafeArea())
    }

    private func finish() {
        Haptics.success()
        settings.hasCompletedOnboarding = true
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            router.isFirstBookPromptPresented = true
        }
    }
}

private struct OnboardingPage {
    enum Illustration { case library, highlight, remember }
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let illustration: Illustration
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 12)
            Group {
                switch page.illustration {
                case .library: LibraryIllustration(isActive: isActive)
                case .highlight: HighlightIllustration(isActive: isActive)
                case .remember: RememberIllustration(isActive: isActive)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .foregroundStyle(Color.qInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(Color.qMuted)
            }
            .padding(.horizontal, 28)
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: isActive)
            Spacer(minLength: 24)
        }
    }
}

private struct LibraryIllustration: View {
    let isActive: Bool
    @State private var float = false

    var body: some View {
        ZStack {
            cover("Meditations", "Marcus Aurelius", angle: -9, x: -78, y: 16)
            cover("Walden", "H. D. Thoreau", angle: 8, x: 78, y: 20)
            cover("On Reading Slowly", "Quolia", angle: 0, x: 0, y: -6)
                .scaleEffect(1.08)
        }
        .offset(y: float ? -6 : 6)
        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: float)
        .onAppear { float = true }
        .accessibilityHidden(true)
    }

    private func cover(_ title: String, _ author: String, angle: Double, x: CGFloat, y: CGFloat) -> some View {
        BookCoverView(title: title, author: author, coverData: nil)
            .frame(width: 128)
            .rotationEffect(.degrees(isActive ? angle : 0))
            .offset(x: isActive ? x : 0, y: y)
            .animation(.spring(response: 0.7, dampingFraction: 0.75), value: isActive)
    }
}

private struct HighlightIllustration: View {
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The art of reading")
                .font(.qSerif(.caption, weight: .semibold))
                .foregroundStyle(Color.qMuted)
            Text("Some books are read once. Others are read slowly, until they become part of how we think.")
                .font(.system(size: 21, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(Color.qInk)
                .background(alignment: .topLeading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(HighlightColor.yellow.color.opacity(0.45))
                            .frame(width: isActive ? proxy.size.width * 0.82 : 0, height: 28)
                            .offset(y: 33)
                            .animation(.easeInOut(duration: 0.9).delay(0.35), value: isActive)
                    }
                }
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                Text("This is why I keep a notebook.")
                    .font(.subheadline)
            }
            .foregroundStyle(Color.qAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.qAccentSoft, in: Capsule())
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 8)
            .animation(.qSpring.delay(1.1), value: isActive)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .cardStyle(padding: 0)
        .padding(.horizontal, 28)
        .accessibilityHidden(true)
    }
}

private struct RememberIllustration: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.qSurfaceSecondary)
                .frame(width: 270, height: 200)
                .rotationEffect(.degrees(isActive ? -5 : 0))
                .offset(y: 16)
            VStack(alignment: .leading, spacing: 14) {
                Label("6 months ago you highlighted this", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.qMuted)
                Text("“A thought revisited becomes a thought kept.”")
                    .font(.system(size: 20, design: .serif))
                    .foregroundStyle(Color.qInk)
                Text("On Reading Slowly")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.qAccent)
            }
            .padding(22)
            .frame(width: 290, alignment: .leading)
            .cardStyle(padding: 0)
            .offset(y: isActive ? -6 : 20)
            .opacity(isActive ? 1 : 0.4)
            .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.15), value: isActive)
        }
        .accessibilityHidden(true)
    }
}
