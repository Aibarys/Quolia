import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// BCP-47 language code of the dominant language, e.g. "en" or "ru".
    static func dominantLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    static func language(for content: BookContent) -> String? {
        if let language = content.language, !language.isEmpty { return String(language.prefix(2)) }
        let sample = content.chapters.prefix(3).flatMap(\.blocks).prefix(40).map(\.text).joined(separator: " ")
        return dominantLanguage(of: String(sample.prefix(4_000)))
    }
}
