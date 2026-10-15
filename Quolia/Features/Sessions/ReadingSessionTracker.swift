import Foundation
import SwiftData

/// Measures one sitting with a book. Only *active* time counts: if the reader
/// is idle for more than 90 seconds (and nothing is auto-scrolling or speaking),
/// the clock stops until the next interaction.
@MainActor
final class ReadingSessionTracker {
    static let idleThreshold: TimeInterval = 90
    static let minimumDuration: TimeInterval = 30

    let startedAt = Date()
    private(set) var activeSeconds: Double = 0
    private(set) var startWords: Int
    private(set) var furthestWords: Int
    private(set) var chaptersCompleted = 0
    private(set) var highlightsCreated = 0
    private(set) var notesCreated = 0
    var isFlow = false
    /// Returns true while something keeps the session alive without touches (auto scroll, speech).
    var keepsAlive: () -> Bool = { false }

    private var lastActivity = Date()
    private var lastTick = Date()
    private var timer: Timer?
    private var isPaused = false
    private var lastChapter: Int

    init(startWords: Int, chapter: Int) {
        self.startWords = startWords
        self.furthestWords = startWords
        self.lastChapter = chapter
    }

    var wordsRead: Int { max(furthestWords - startWords, 0) }

    func start() {
        lastTick = Date()
        lastActivity = Date()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        tick()
        isPaused = true
    }

    func resume() {
        isPaused = false
        lastTick = Date()
        lastActivity = Date()
    }

    func markActivity() { lastActivity = Date() }

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        guard !isPaused else { return }
        let idle = now.timeIntervalSince(lastActivity) > Self.idleThreshold
        if !idle || keepsAlive() {
            activeSeconds += min(now.timeIntervalSince(lastTick), 2)
        }
    }

    /// Records the reader's position. Only forward movement counts as reading.
    func record(words: Int, chapter: Int) {
        // Ignore big jumps (TOC, search) — they aren't reading.
        let plausible = Double(abs(words - furthestWords)) < max(activeSeconds, 30) * 20
        if words > furthestWords, plausible { furthestWords = words }
        if words < startWords - 2_000 { startWords = words; furthestWords = max(furthestWords, words) }
        if chapter == lastChapter + 1 { chaptersCompleted += 1 }
        lastChapter = chapter
    }

    func didCreateHighlight() { highlightsCreated += 1; markActivity() }
    func didCreateNote() { notesCreated += 1; markActivity() }

    /// Persists the session if it was long enough to matter.
    @discardableResult
    func finish(book: Book, context: ModelContext, settings: AppSettings) -> ReadingSession? {
        timer?.invalidate()
        timer = nil
        tick()
        guard activeSeconds >= Self.minimumDuration else { return nil }
        let session = ReadingSession(startedAt: startedAt, book: book)
        session.endedAt = .now
        session.duration = activeSeconds
        session.wordsRead = wordsRead
        session.chaptersCompleted = chaptersCompleted
        session.highlightsCreated = highlightsCreated
        session.notesCreated = notesCreated
        session.isFlow = isFlow
        context.insert(session)
        try? context.save()
        settings.recordReadingSpeed(words: wordsRead, seconds: activeSeconds)
        return session
    }
}

/// Stats for one Reading Flow run, shown when the flow ends.
struct FlowSummary: Identifiable, Equatable {
    let id = UUID()
    var seconds: Double
    var words: Int
    var chapters: Int
    var highlights: Int
    var notes: Int

    var pages: Int { Int((Double(words) / ReadingMath.wordsPerPage).rounded()) }
    var minutes: Int { max(Int((seconds / 60).rounded()), seconds >= 30 ? 1 : 0) }
}
