import AVFoundation
import Observation

/// Reads the book aloud paragraph by paragraph. The reader follows along by
/// focusing the paragraph being spoken.
@Observable
@MainActor
final class SpeechController: NSObject {
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var currentLocator: ReadingLocator?
    var rate: Float = 0.5 {
        didSet { UserDefaults.standard.set(rate, forKey: "quolia.speechRate") }
    }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var content: BookContent?
    @ObservationIgnored private var language: String?

    override init() {
        super.init()
        let stored = UserDefaults.standard.float(forKey: "quolia.speechRate")
        rate = stored > 0 ? stored : AVSpeechUtteranceDefaultSpeechRate
        synthesizer.delegate = self
    }

    static let rates: [(String, Float)] = [("0.75×", 0.42), ("1×", 0.5), ("1.25×", 0.55), ("1.5×", 0.6)]

    func start(content: BookContent, from locator: ReadingLocator, language: String?) {
        self.content = content
        self.language = language
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        isActive = true
        isPaused = false
        currentLocator = ReadingLocator(chapter: locator.chapter, block: locator.block)
        speakCurrent()
    }

    func togglePause() {
        guard isActive else { return }
        if isPaused {
            synthesizer.continueSpeaking()
        } else {
            synthesizer.pauseSpeaking(at: .word)
        }
        isPaused.toggle()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        isPaused = false
        currentLocator = nil
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func applyRate() {
        guard isActive, !isPaused else { return }
        synthesizer.stopSpeaking(at: .immediate) // didCancel is ignored; restart current block
        speakCurrent()
    }

    private func speakCurrent() {
        guard isActive, let content, var locator = currentLocator else { return }
        // Skip images, separators and empty blocks.
        while let chapter = content.chapter(locator.chapter) {
            if let block = chapter.block(locator.block), block.isTextual, !block.text.isEmpty {
                let utterance = AVSpeechUtterance(string: block.text)
                utterance.rate = rate
                utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: nil)
                utterance.postUtteranceDelay = block.kind == .heading ? 0.35 : 0.12
                currentLocator = locator
                synthesizer.speak(utterance)
                return
            }
            locator.block += 1
            if locator.block >= chapter.blocks.count {
                locator = ReadingLocator(chapter: locator.chapter + 1, block: 0)
            }
        }
        stop()
    }

    private func advance() {
        guard isActive, let content, var locator = currentLocator else { return }
        locator.block += 1
        if let chapter = content.chapter(locator.chapter), locator.block >= chapter.blocks.count {
            locator = ReadingLocator(chapter: locator.chapter + 1, block: 0)
        }
        currentLocator = locator
        speakCurrent()
    }
}

extension SpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.advance() }
    }
}

/// One-off pronunciation for the dictionary.
@MainActor
enum Pronouncer {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String, language: String?) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.42
        synthesizer.speak(utterance)
    }
}
