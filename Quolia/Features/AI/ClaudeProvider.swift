import Foundation

enum ClaudeModels {
    static let defaultModel = "claude-opus-5-5"

    static let all: [(id: String, name: String, detail: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5", String(localized: "Most capable · default")),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5", String(localized: "Fast and capable")),
        ("claude-haiku-5-5", "Claude Haiku 5.5", String(localized: "Fastest, lowest cost")),
    ]

    /// Server-side refusal fallback is supported on Opus 5.5 and Sonnet 5.5 (not Haiku).
    static func supportsFallback(_ model: String) -> Bool {
        model == "claude-opus-5-5" || model == "claude-sonnet-5-5"
    }
}

/// Claude via the Messages API with the user's own key (stored in the keychain).
/// Swift has no official Anthropic SDK, so this speaks HTTPS + server-sent events directly.
@MainActor
struct ClaudeProvider: AIProvider {
    static let keychainKey = "anthropic-api-key"

    let apiKey: String
    let model: String

    var displayName: String { ClaudeModels.all.first { $0.id == model }?.name ?? "Claude" }
    /// Large context window — still bounded to keep requests quick and affordable.
    var contextBudget: Int { 360_000 }

    func makeConversation(instructions: String) -> AIConversation {
        ClaudeConversation(apiKey: apiKey, model: model, instructions: instructions)
    }
}

/// One server-sent event line from the Messages API stream.
enum ClaudeStreamEvent: Equatable {
    case text(String)
    case refusal
    case error(String)
    case other

    /// Parses a `data: {...}` line; returns nil for `event:` lines, blanks and keep-alives.
    init?(line: String) {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }
        switch type {
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { self = .other; return }
            self = .text(text)
        case "message_delta":
            let delta = event["delta"] as? [String: Any]
            self = delta?["stop_reason"] as? String == "refusal" ? .refusal : .other
        case "error":
            let error = event["error"] as? [String: Any]
            self = .error(error?["message"] as? String ?? String(localized: "Claude reported an error."))
        default:
            self = .other
        }
    }
}

@MainActor
final class ClaudeConversation: AIConversation {
    private let apiKey: String
    private let model: String
    private let instructions: String
    private var messages: [[String: Any]] = []

    init(apiKey: String, model: String, instructions: String) {
        self.apiKey = apiKey
        self.model = model
        self.instructions = instructions
    }

    func send(_ message: String) -> AsyncThrowingStream<String, Error> {
        messages.append(["role": "user", "content": message])
        let request: URLRequest
        do {
            request = try makeRequest()
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                var reply = ""
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw AIError.server(String(localized: "No response from Claude.")) }
                    guard http.statusCode == 200 else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw AIError.server(Self.errorMessage(status: http.statusCode, body: body))
                    }

                    for try await line in bytes.lines {
                        switch ClaudeStreamEvent(line: line) {
                        case .text(let text):
                            reply += text
                            continuation.yield(text)
                        case .refusal:
                            throw AIError.refused
                        case .error(let message):
                            throw AIError.server(message)
                        case .none, .other:
                            break
                        }
                    }
                    self.messages.append(["role": "assistant", "content": reply])
                    continuation.finish()
                } catch {
                    // Keep the transcript valid for a retry: drop the unanswered user turn.
                    if self.messages.last?["role"] as? String == "user" { self.messages.removeLast() }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest() throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 64_000,
            "stream": true,
            "system": instructions,
            "messages": messages,
            "output_config": ["effort": "medium"],
            // The book context in the first turn is reused by every follow-up question.
            "cache_control": ["type": "ephemeral"],
        ]
        if ClaudeModels.supportsFallback(model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func errorMessage(status: Int, body: String) -> String {
        let apiMessage = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
        switch status {
        case 401: return String(localized: "Your Anthropic API key was rejected. Check it in Settings → AI.")
        case 403: return apiMessage ?? String(localized: "This API key doesn't have access to the selected model.")
        case 429: return String(localized: "Claude is receiving too many requests right now. Please try again shortly.")
        case 500...599: return String(localized: "Claude is temporarily unavailable. Please try again.")
        default: return apiMessage ?? String(localized: "Claude returned an error (\(status)).")
        }
    }
}
