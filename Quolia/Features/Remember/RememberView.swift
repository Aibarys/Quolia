import SwiftUI
import SwiftData

/// Reading Memory: old highlights return, one card at a time.
struct RememberView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Highlight.createdAt) private var highlights: [Highlight]

    @State private var queue: [UUID] = []
    @State private var position = 0
    @State private var direction: Edge = .trailing
    @State private var shareDraft: (QuoteDraft, Data?)?
    @State private var didLoad = false

    private var current: Highlight? {
        guard queue.indices.contains(position) else { return nil }
        return highlights.first { $0.id == queue[position] }
    }

    private var dueCount: Int {
        highlights.filter { !$0.isHiddenFromMemory && ($0.nextReviewAt ?? $0.createdAt) <= .now }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.qBackground.ignoresSafeArea()
                if highlights.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to remember yet", systemImage: "memories")
                    } description: {
                        Text("Highlights you save will come back here, gently, over time.")
                    }
                } else if let current {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)
                        MemoryCard(highlight: current)
                            .id(current.id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                            .contextMenu {
                                Button { showLessOften(current) } label: { Label("Show Less Often", systemImage: "tortoise") }
                                Button(role: .destructive) { hide(current) } label: { Label("Don't Show Again", systemImage: "eye.slash") }
                            }
                            .padding(.horizontal, Metrics.gutter)
                        Spacer(minLength: 20)
                        actions(for: current)
                            .padding(.horizontal, Metrics.gutter)
                        footer
                            .padding(.top, 18)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: 600)
                } else {
                    caughtUp
                }
            }
            .navigationTitle("Remember")
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                rebuildQueue()
            }
            .onChange(of: highlights.count) { _, _ in if queue.isEmpty { rebuildQueue() } }
            .sheet(isPresented: Binding(get: { shareDraft != nil }, set: { if !$0 { shareDraft = nil } })) {
                if let (draft, cover) = shareDraft { QuoteCardComposer(draft: draft, coverData: cover) }
            }
        }
    }

    private func actions(for highlight: Highlight) -> some View {
        HStack(spacing: 12) {
            Button {
                router.open(highlight)
            } label: {
                ViewThatFits(in: .horizontal) {
                    Label("Open in book", systemImage: "book")
                    Text("Open in book")
                    Text("Open")
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                shareDraft = (QuoteDraft(text: highlight.text, bookTitle: highlight.book?.title ?? "",
                                         author: highlight.book?.author ?? "", chapterTitle: highlight.chapterTitle),
                              highlight.book?.coverImageData)
            } label: {
                Image(systemName: "square.and.arrow.up").frame(width: 20)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Share")
            Button {
                next()
            } label: {
                Text("Next").frame(width: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(.qInk)
        }
        .controlSize(.large)
        .font(.subheadline.weight(.semibold))
    }

    private var footer: some View {
        Text(queue.count > 1 ? "\(min(position + 1, queue.count)) of \(queue.count) today" : "One thought for today")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var caughtUp: some View {
        VStack(spacing: 18) {
            Image(systemName: "leaf")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.qAccent)
            Text("That's all for now")
                .font(.qTitle)
            Text("Your highlights will return when it's time to see them again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Show one more") {
                let pool = highlights.filter { !$0.isHiddenFromMemory && $0.book != nil }
                guard let random = pool.randomElement() else { return }
                withAnimation(.qSpring) {
                    queue = [random.id]
                    position = 0
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Logic

    private func rebuildQueue() {
        let due = MemoryScheduler.queue(from: highlights)
        let dueNow = due.filter { ($0.nextReviewAt ?? $0.createdAt) <= .now }
        // Keep the daily set small and calm.
        queue = Array((dueNow.isEmpty ? Array(due.prefix(1)) : dueNow).prefix(10).map(\.id))
        position = 0
    }

    private func next() {
        guard let current else { return }
        MemoryScheduler.markSeen(current)
        try? context.save()
        Haptics.selection()
        withAnimation(.qSpring) { position += 1 }
    }

    private func showLessOften(_ highlight: Highlight) {
        MemoryScheduler.showLessOften(highlight)
        try? context.save()
        withAnimation(.qSpring) { position += 1 }
    }

    private func hide(_ highlight: Highlight) {
        highlight.isHiddenFromMemory = true
        try? context.save()
        withAnimation(.qSpring) { position += 1 }
    }
}

struct MemoryCard: View {
    let highlight: Highlight
    @ScaledMetric(relativeTo: .title2) private var typeScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("\(MemoryScheduler.ageDescription(of: highlight.createdAt)) you highlighted this", systemImage: "clock.arrow.circlepath")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Text(highlight.text)
                .font(.system(size: fontSize * typeScale, weight: .regular, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(Color.qInk)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let note = highlight.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text")
                    Text(note)
                }
                .font(.subheadline)
                .foregroundStyle(Color.qAccent)
            }

            Divider()

            if let book = highlight.book {
                HStack(spacing: 12) {
                    BookCoverView(book: book, showsShadow: false).frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(book.displayAuthor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Circle().fill(highlight.color.color).frame(width: 10, height: 10)
                }
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.qSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.qHairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 24, y: 10)
    }

    private var fontSize: CGFloat {
        switch highlight.text.count {
        case ..<120: 26
        case ..<260: 22
        case ..<500: 19
        default: 17
        }
    }
}
