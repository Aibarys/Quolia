import Foundation

/// A running conversation with a model. `send` streams text deltas.
@MainActor
protocol AIConversation: AnyObject {
    func send(_ message: String) -> AsyncThrowingStream<String, Error>
}

@MainActor
protocol AIProvider {
    var displayName: String { get }
    /// How many characters of book text this provider may receive per conversation.
    var contextBudget: Int { get }
    func makeConversation(instructions: String) -> AIConversation
}

enum AIError: LocalizedError {
    case unavailable(String)
    case refused
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .refused: String(localized: "The assistant declined to answer this request.")
        case .server(let message): message
        }
    }
}

/// Picks the provider the user chose and explains why one isn't available.
@MainActor
enum AIService {
    enum Resolution {
        case ready(AIProvider)
        case unavailable(String)
    }

    static func resolve(settings: AppSettings) -> Resolution {
        switch settings.aiProvider {
        case .off:
            return .unavailable(String(localized: "AI features are turned off. You can enable them in Settings."))
        case .claude:
            guard let key = KeychainStore.string(for: ClaudeProvider.keychainKey), !key.isEmpty else {
                return .unavailable(String(localized: "Add your Anthropic API key in Settings → AI to use Claude."))
            }
            return .ready(ClaudeProvider(apiKey: key, model: settings.claudeModel))
        case .appleIntelligence:
            if #available(iOS 26.0, *) {
                #if canImport(FoundationModels)
                if let reason = AppleIntelligenceProvider.unavailableReason {
                    return .unavailable(reason)
                }
                return .ready(AppleIntelligenceProvider())
                #else
                return .unavailable(String(localized: "Apple Intelligence isn't available in this build."))
                #endif
            }
            return .unavailable(String(localized: "Apple Intelligence requires iOS 26 or later. You can use Claude instead in Settings → AI."))
        }
    }

    static let instructions = """
    You are the reading companion inside Quolia, a book reading app. You help one reader understand the book they are reading right now.

    No spoilers — this is the most important rule. You only know the part of the book provided to you, and it ends exactly at the reader's current position. Never reveal, hint at, or speculate about anything that happens later, even if you recognize the book and know how it continues. If a question can only be answered by later parts, say gently that the book hasn't revealed that yet at this point.

    Ground every answer in the provided text, quoting short phrases when it helps. Be calm, clear and concise — a few short paragraphs at most. Use plain prose without headings or tables. Reply in the reader's interface language (stated with the request) unless the reader writes in a different language — then reply in theirs.
    """

    /// The opening message of a conversation: book context plus the first request.
    static func openingMessage(context: String, request: AIRequest, translationLanguage: String) -> String {
        "<book_context>\n\(context)\n</book_context>\n\n"
            + "Reader's interface language: \(interfaceLanguageName).\n\n"
            + prompt(for: request, translationLanguage: translationLanguage)
    }

    /// English name of the app's current language ("Russian"), for the model.
    static var interfaceLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }

    static func prompt(for request: AIRequest, translationLanguage: String) -> String {
        let passage = request.selection.map { "\"\"\"\n\($0)\n\"\"\"" } ?? ""
        switch request.action {
        case .explain:
            return "Explain this passage in plain language — what it says and why it matters given what I've read so far:\n\(passage)"
        case .simplify:
            return "Rewrite this passage in simpler, clearer language while keeping its meaning. Then add one sentence naming its key idea:\n\(passage)"
        case .summarize:
            if request.selection != nil {
                return "Summarize this passage in two to four sentences:\n\(passage)"
            }
            return "Summarize what has happened in the book so far, up to my current position. Keep it short and organized in order."
        case .translate:
            let language = Locale(identifier: "en").localizedString(forLanguageCode: translationLanguage) ?? translationLanguage
            return "Translate this passage into \(language), preserving its tone:\n\(passage)"
        case .ask:
            return "About this passage:\n\(passage)\n\n\(request.question ?? "What does it mean?")"
        case nil:
            if let selection = request.selection {
                return "About this passage:\n\"\"\"\n\(selection)\n\"\"\"\n\n\(request.question ?? "")"
            }
            return request.question ?? ""
        }
    }
}
