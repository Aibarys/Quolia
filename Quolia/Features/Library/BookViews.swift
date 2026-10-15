import SwiftUI

struct BookGridItem: View {
    let book: Book
    let action: () -> Void
    @Environment(\.readerTransitionNamespace) private var namespace

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                cover
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(book.displayAuthor)
                        .font(.footnote)
                        .foregroundStyle(Color.qMuted)
                        .lineLimit(1)
                }
                BookProgressLine(book: book)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    @ViewBuilder
    private var cover: some View {
        let view = BookCoverView(book: book)
            .overlay(alignment: .topTrailing) {
                if book.status == .finished {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.qAccent)
                        .font(.title3)
                        .padding(6)
                }
            }
        if let namespace {
            view.matchedTransitionSource(id: book.id, in: namespace)
        } else {
            view
        }
    }
}

struct BookListRow: View {
    let book: Book
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                BookCoverView(book: book, showsShadow: false)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(Color.qInk)
                        .lineLimit(2)
                    Text(book.displayAuthor)
                        .font(.subheadline)
                        .foregroundStyle(Color.qMuted)
                        .lineLimit(1)
                    BookProgressLine(book: book)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Progress bar plus "42% · Yesterday".
struct BookProgressLine: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if book.status == .finished {
                Group {
                    if let finishedAt = book.finishedAt {
                        Text("Finished · \(finishedAt.quietRelative)")
                    } else {
                        Text("Finished", comment: "Reading status")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.qMuted)
            } else if book.progress > 0 {
                ProgressBar(progress: book.progress, height: 3)
                HStack(spacing: 4) {
                    Text(book.progress.percentText)
                        .monospacedDigit()
                    if let last = book.lastOpenedAt {
                        Text("·")
                        Text(last.quietRelative)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.qMuted)
            } else {
                Text(book.status == .wantToRead ? "Want to Read · \(book.format.displayName)" : "New · \(book.format.displayName)")
                    .font(.caption)
                    .foregroundStyle(Color.qMuted)
            }
        }
    }
}

struct ContinueReadingCard: View {
    let book: Book
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            BookCoverView(book: book)
                .frame(width: 92)
                .onTapGesture { router.open(book) }
            VStack(alignment: .leading, spacing: 6) {
                Text("CONTINUE READING")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.qAccent)
                Text(book.title)
                    .font(.qSerif(.title3, weight: .semibold))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(2)
                if !book.currentChapterTitle.isEmpty {
                    Text(book.currentChapterTitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.qMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                ProgressBar(progress: book.progress, height: 4)
                Text(remainingText)
                    .font(.caption)
                    .foregroundStyle(Color.qMuted)
                HStack(spacing: 10) {
                    Button {
                        Haptics.light()
                        router.open(book)
                    } label: {
                        Text(String(localized: "continue.resume", defaultValue: "Resume", comment: "Continue reading a book from the library card"))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .foregroundStyle(Color.qBackground)
                            .background(Color.qInk, in: Capsule())
                    }
                    Button {
                        Haptics.light()
                        router.open(book, readingFlow: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Flow")
                        }
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(Color.qInk)
                            .background(Color.qSurfaceSecondary, in: Capsule())
                    }
                    .accessibilityLabel("Start Reading Flow")
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .cardStyle()
    }

    private var remainingText: String {
        let percent = book.progress.formatted(.percent.precision(.fractionLength(0)))
        guard book.totalWords > 0 else { return percent }
        let remaining = Double(book.totalWords) * (1 - book.progress)
        let minutes = remaining / max(settings.measuredWPM, 80)
        return String(localized: "\(percent) · \(DurationFormat.compactRemaining(minutes: minutes)) left")
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.qQuick, value: configuration.isPressed)
    }
}
