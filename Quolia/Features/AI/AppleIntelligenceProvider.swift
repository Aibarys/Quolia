#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// On-device model via Apple's Foundation Models framework: private, offline, free.
@available(iOS 26.0, *)
@MainActor
struct AppleIntelligenceProvider: AIProvider {
    var displayName: String { "Apple Intelligence" }
    /// The on-device model has a small context window, so book context stays compact.
    var contextBudget: Int { 6_500 }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return String(localized: "This device doesn't support Apple Intelligence. You can use Claude instead in Settings → AI.")
            case .appleIntelligenceNotEnabled:
                return String(localized: "Turn on Apple Intelligence in the Settings app to use AI features.")
            case .modelNotReady:
                return String(localized: "Apple Intelligence is still getting ready. Please try again in a little while.")
            @unknown default:
                return String(localized: "Apple Intelligence isn't available right now.")
            }
        }
    }

    func makeConversation(instructions: String) -> AIConversation {
        AppleIntelligenceConversation(instructions: instructions)
    }
}

@available(iOS 26.0, *)
@MainActor
final class AppleIntelligenceConversation: AIConversation {
    private let session: LanguageModelSession

    init(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
    }

    func send(_ message: String) -> AsyncThrowingStream<String, Error> {
        let session = session
        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    var emitted = ""
                    // Snapshots are cumulative; convert them into deltas.
                    for try await snapshot in session.streamResponse(to: message) {
                        let text = snapshot.content
                        if text.hasPrefix(emitted) {
                            continuation.yield(String(text.dropFirst(emitted.count)))
                        } else {
                            continuation.yield(text)
                        }
                        emitted = text
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.friendly(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func friendly(_ error: LanguageModelSession.GenerationError) -> AIError {
        switch error {
        case .exceededContextWindowSize:
            return .server(String(localized: "This conversation got too long for the on-device model. Close it and ask a new question."))
        case .assetsUnavailable:
            return .unavailable(String(localized: "Apple Intelligence models aren't available on this device yet. They may still be downloading — or choose Claude in Settings → AI."))
        case .guardrailViolation:
            return .refused
        case .unsupportedLanguageOrLocale:
            return .unavailable(String(localized: "Apple Intelligence doesn't support this book's language yet. You can use Claude in Settings → AI."))
        case .rateLimited:
            return .server(String(localized: "Apple Intelligence is busy right now. Please try again in a moment."))
        default:
            return .server(String(localized: "Apple Intelligence couldn't answer this time. Please try again, or choose Claude in Settings → AI."))
        }
    }
}
#endif
