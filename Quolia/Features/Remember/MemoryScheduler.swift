import Foundation

/// A gentle spaced-repetition schedule for Reading Memory. There are no grades
/// or streaks — seeing a highlight simply pushes its next appearance further out.
enum MemoryScheduler {
    /// Days until the next appearance after each review.
    static let intervals: [Double] = [3, 7, 16, 35, 75, 150, 300]
    static let day: TimeInterval = 86_400

    static func scheduleNew(_ highlight: Highlight) {
        highlight.nextReviewAt = highlight.createdAt.addingTimeInterval(intervals[0] * day)
    }

    static func markSeen(_ highlight: Highlight, now: Date = .now, jitter: Double = Double.random(in: 0.85...1.15)) {
        highlight.reviewCount += 1
        highlight.lastReviewedAt = now
        let days = intervals[min(highlight.reviewCount, intervals.count - 1)]
        highlight.nextReviewAt = now.addingTimeInterval(days * jitter * day)
    }

    static func showLessOften(_ highlight: Highlight, now: Date = .now) {
        highlight.reviewCount += 2
        markSeen(highlight, now: now, jitter: 1)
    }

    /// Highlights to resurface, most deserving first: due items (oldest due first),
    /// then — if nothing is due — the ones seen least recently.
    static func queue(from highlights: [Highlight], now: Date = .now) -> [Highlight] {
        let eligible = highlights.filter { !$0.isHiddenFromMemory && $0.book != nil && !$0.text.isEmpty }
        let due = eligible
            .filter { ($0.nextReviewAt ?? $0.createdAt) <= now }
            .sorted { ($0.nextReviewAt ?? $0.createdAt) < ($1.nextReviewAt ?? $1.createdAt) }
        if !due.isEmpty { return due }
        return eligible.sorted { ($0.lastReviewedAt ?? $0.createdAt) < ($1.lastReviewedAt ?? $1.createdAt) }
    }

    /// "6 months ago you highlighted this".
    static func ageDescription(of date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Earlier today") }
        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day], from: date, to: now)
        let relative: DateComponents
        if let years = components.year, years > 0 { relative = DateComponents(year: -years) }
        else if let months = components.month, months > 0 { relative = DateComponents(month: -months) }
        else if let weeks = components.weekOfYear, weeks > 0 { relative = DateComponents(weekOfMonth: -weeks) }
        else { relative = DateComponents(day: -max(components.day ?? 1, 1)) }
        // "6 months ago", "last week", "yesterday" — grammatically correct in every language.
        return RelativeFormat.string(from: relative).capitalizedFirstLetter
    }
}
