import SwiftUI

/// "Ask the Book" — a quiet conversation about the text, limited to what has been read.
struct AskBookView: View {
    let model: ReaderViewModel
    let request: AIRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var chat = AskBookChat()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var suggestions: [String] {
        if request.selection != nil {
            return [String(localized: "What did the author mean here?"),
                    String(localized: "Why does this matter?"),
                    String(localized: "Who is speaking here?")]
        }
        return [String(localized: "Summarize what happened so far"),
                String(localized: "Who are the main characters so far?"),
                String(localized: "What is the central idea so far?")]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            spoilerBadge
                            if let selection = request.selection {
                                QuoteBlock(text: selection, color: .yellow, lineLimit: 6)
                            }
                            if let unavailable = chat.unavailableReason {
                                unavailableView(unavailable)
                            } else if chat.turns.isEmpty {
                                suggestionList
                            }
                            ForEach(chat.turns) { turn in
                                TurnView(turn: turn)
                                    .id(turn.id)
                            }
                            if let error = chat.error {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chat.scrollToken) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                if chat.unavailableReason == nil { inputBar }
            }
            .navigationTitle(request.action?.title ?? String(localized: "Ask the Book"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            chat.configure(model: model, settings: settings)
            if request.action != nil {
                chat.ask(request)
            }
            #if DEBUG
            if let question = DebugLaunch.value("-askQuestion") { send(question) }
            #endif
        }
        .onDisappear { chat.cancel() }
    }

    private var spoilerBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
            Text("Knows only what you've read — up to \(model.progress.percentText)")
            Spacer()
            if let name = chat.providerName {
                Text(name).foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    HStack {
                        Text(suggestion).font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func unavailableView(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI isn't available", systemImage: "sparkles")
                .font(.headline)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open AI Settings") {
                // Replaces this sheet; the app-level settings sheet can't show over the reader.
                model.activeSheet = .appSettings(.ai)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(request.selection == nil ? "Ask about the book…" : "Ask about this passage…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { send(input) }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button {
                if chat.isResponding { chat.cancel() } else { send(input) }
            } label: {
                Image(systemName: chat.isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.qBackground)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend || chat.isResponding ? Color.qInk : Color.secondary.opacity(0.4)))
            }
            .disabled(!canSend && !chat.isResponding)
            .accessibilityLabel(chat.isResponding ? "Stop" : "Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !chat.isResponding else { return }
        input = ""
        var next = request
        next.action = request.selection == nil ? nil : .ask
        next.question = question
        chat.ask(next)
    }
}

private struct TurnView: View {
    let turn: AskBookChat.Turn

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.qAccentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if turn.text.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading…").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text(LocalizedStringKey(turn.text))
                        .font(.system(.body, design: .serif))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Conversation state for Ask the Book.
@Observable
@MainActor
final class AskBookChat {
    struct Turn: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    private(set) var turns: [Turn] = []
    private(set) var isResponding = false
    private(set) var error: String?
    private(set) var unavailableReason: String?
    private(set) var providerName: String?
    private(set) var scrollToken = 0

    @ObservationIgnored private var provider: AIProvider?
    @ObservationIgnored private var conversation: AIConversation?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private weak var model: ReaderViewModel?
    @ObservationIgnored private var translationLanguage = "en"

    func configure(model: ReaderViewModel, settings: AppSettings) {
        self.model = model
        translationLanguage = settings.translationLanguage
        switch AIService.resolve(settings: settings) {
        case .ready(let provider):
            self.provider = provider
            providerName = provider.displayName
        case .unavailable(let reason):
            unavailableReason = reason
        }
        if model.content == nil, unavailableReason == nil {
            unavailableReason = String(localized: "The text of this book is still being prepared. Try again in a moment.")
        }
    }

    func ask(_ request: AIRequest) {
        guard let provider, let model, let content = model.content, !isResponding else { return }
        error = nil
        let displayText = request.question ?? request.action?.title ?? ""
        if !displayText.isEmpty { turns.append(Turn(role: .user, text: displayText)) }

        let message: String
        let isFirstTurn = conversation == nil
        if isFirstTurn {
            // First turn: attach the spoiler-safe book context.
            let context = SpoilerSafeContext.build(
                content: content, frontier: model.readingFrontier, progress: model.progress,
                question: request.question, focus: request.selection, budget: provider.contextBudget
            )
            conversation = provider.makeConversation(instructions: AIService.instructions)
            message = AIService.openingMessage(context: context, request: request, translationLanguage: translationLanguage)
        } else {
            message = AIService.prompt(for: request, translationLanguage: translationLanguage)
        }

        guard let conversation else { return }
        turns.append(Turn(role: .assistant, text: ""))
        let index = turns.count - 1
        isResponding = true
        scrollToken += 1
        task = Task { [weak self] in
            do {
                for try await delta in conversation.send(message) {
                    guard let self else { return }
                    self.turns[index].text += delta
                    self.scrollToken += 1
                }
            } catch is CancellationError {
            } catch {
                self?.error = error.localizedDescription
                if self?.turns[index].text.isEmpty == true { self?.turns.remove(at: index) }
                // The book context travels with the first turn; resend it next time.
                if isFirstTurn { self?.conversation = nil }
            }
            self?.isResponding = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isResponding = false
    }
}
