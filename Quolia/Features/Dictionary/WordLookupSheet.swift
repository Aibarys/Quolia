import SwiftUI
import SwiftData
import Translation
import NaturalLanguage

/// Definition, translation, pronunciation and "save word" for a selected term.
struct WordLookupSheet: View {
    let request: WordLookupRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Query private var savedWords: [SavedWord]

    @State private var translation: String?
    @State private var translationFailed = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var showsDictionary = false
    @State private var contextMeaning: String?
    @State private var isExplaining = false

    private var term: String { request.term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
    private var isPhrase: Bool { term.split(separator: " ").count > 3 }
    private var hasDefinition: Bool { UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) }
    private var isSaved: Bool { savedWords.contains { $0.word.caseInsensitiveCompare(term) == .orderedSame } }

    private var sourceLanguage: String? { request.language.map { String($0.prefix(2)) } }
    private var targetLanguage: String {
        let preferred = settings.translationLanguage
        if let sourceLanguage, sourceLanguage == preferred { return preferred == "en" ? "es" : "en" }
        return preferred
    }

    private var contextSentence: String? {
        guard let paragraph = request.context, !paragraph.isEmpty else { return nil }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        var match: String?
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let sentence = String(paragraph[range])
            if sentence.localizedCaseInsensitiveContains(term) {
                match = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                return false
            }
            return true
        }
        return match
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    translationSection
                    if !isPhrase { definitionSection }
                    if let contextSentence, !isPhrase {
                        section("In context") {
                            Text(highlighted(contextSentence))
                                .font(.qSerif(.body))
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(22)
            }
            .navigationTitle("Dictionary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showsDictionary) {
                DictionaryView(term: term).ignoresSafeArea()
            }
            .translationTask(configuration) { session in
                do {
                    let response = try await session.translate(term)
                    translation = response.targetText
                } catch {
                    translationFailed = true
                }
            }
            .onAppear {
                configuration = TranslationSession.Configuration(
                    source: sourceLanguage.map { Locale.Language(identifier: $0) },
                    target: Locale.Language(identifier: targetLanguage)
                )
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(term)
                .font(.system(isPhrase ? .title3 : .largeTitle, design: .serif, weight: .semibold))
                .lineLimit(isPhrase ? 6 : 2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                Pronouncer.speak(term, language: request.language)
                Haptics.light()
            } label: {
                Image(systemName: "speaker.wave.2.fill").frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .accessibilityLabel("Pronounce")
            Button(action: toggleSave) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark").frame(width: 40, height: 40)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .tint(isSaved ? .qAccent : .primary)
            .accessibilityLabel(isSaved ? "Remove from Saved Words" : "Save word")
        }
    }

    private var translationSection: some View {
        section("Translation · \(languageName(targetLanguage))") {
            if let translation {
                Text(translation)
                    .font(.title3)
                    .textSelection(.enabled)
            } else if translationFailed {
                Text("Translation isn't available for this language pair on this device yet. Language packs can be downloaded in Settings → Apps → Translate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Translating…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var definitionSection: some View {
        section("Definition") {
            VStack(alignment: .leading, spacing: 12) {
                if hasDefinition {
                    Button {
                        showsDictionary = true
                    } label: {
                        Label("Open in Dictionary", systemImage: "character.book.closed")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("No offline dictionary entry. You can add dictionaries in Settings → General → Dictionary.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let contextMeaning {
                    Text(contextMeaning)
                        .font(.body)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.qAccentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if request.context != nil {
                    Button {
                        explainInContext()
                    } label: {
                        if isExplaining {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…") }
                        } else {
                            Label("Meaning in this context", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExplaining)
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalizedFirstLetter ?? code
    }

    private func highlighted(_ sentence: String) -> AttributedString {
        var result = AttributedString(sentence)
        if let range = result.range(of: term, options: .caseInsensitive) {
            result[range].backgroundColor = HighlightColor.yellow.color.opacity(0.4)
            result[range].font = .system(.body, design: .serif).bold()
        }
        return result
    }

    private func toggleSave() {
        if let existing = savedWords.first(where: { $0.word.caseInsensitiveCompare(term) == .orderedSame }) {
            context.delete(existing)
            Haptics.light()
        } else {
            let word = SavedWord(word: term, translation: translation, definition: contextMeaning,
                                 context: contextSentence, bookTitle: request.bookTitle, language: request.language)
            context.insert(word)
            Haptics.success()
            toasts.show(String(localized: "Saved to your words"), symbol: "bookmark.fill")
        }
        try? context.save()
    }

    /// A one-line, spoiler-free meaning of the word in its sentence (uses the chosen AI provider).
    private func explainInContext() {
        guard case .ready(let provider) = AIService.resolve(settings: settings) else {
            contextMeaning = "AI isn't available. Choose a provider in Settings → AI."
            return
        }
        isExplaining = true
        let conversation = provider.makeConversation(instructions: "You are a concise dictionary. Explain what a word means in the given sentence in one or two short sentences. Reply in the language of the sentence unless told otherwise.")
        let prompt = "Word: \(term)\nSentence: \(contextSentence ?? request.context ?? "")"
        Task {
            var text = ""
            do {
                for try await delta in conversation.send(prompt) { text += delta; contextMeaning = text }
            } catch {
                contextMeaning = error.localizedDescription
            }
            isExplaining = false
        }
    }
}

/// System dictionary (the same one used by "Look Up").
struct DictionaryView: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
