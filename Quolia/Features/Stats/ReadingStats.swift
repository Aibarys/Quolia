import Foundation

/// Pure statistics over reading sessions — no UI, easy to test.
struct ReadingStats {
    struct Day: Identifiable, Hashable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    let calendar: Calendar
    let now: Date
    let goalMinutes: Int
    let minutesByDay: [Date: Double]
    let wordsByDay: [Date: Int]
    let todayMinutes: Double
    let streak: Int
    let totalSeconds: Double
    let totalPages: Int
    let booksFinished: Int
    let weekSeconds: Double
    let weekPages: Int
    let weekActiveBooks: Int

    init(sessions: [ReadingSession], books: [Book], goalMinutes: Int, now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        self.now = now
        self.goalMinutes = goalMinutes

        var minutes: [Date: Double] = [:]
        var words: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            minutes[day, default: 0] += session.duration / 60
            words[day, default: 0] += session.wordsRead
        }
        minutesByDay = minutes
        wordsByDay = words

        let today = calendar.startOfDay(for: now)
        todayMinutes = minutes[today] ?? 0

        // Streak: consecutive days with at least a minute of reading, ending today
        // (or yesterday, if today's reading hasn't happened yet).
        var streak = 0
        var cursor = (minutes[today] ?? 0) >= 1 ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while (minutes[cursor] ?? 0) >= 1 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        self.streak = streak

        totalSeconds = sessions.reduce(0) { $0 + $1.duration }
        totalPages = Int((Double(sessions.reduce(0) { $0 + $1.wordsRead }) / ReadingMath.wordsPerPage).rounded())
        booksFinished = books.filter { $0.status == .finished }.count

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let weekSessions = sessions.filter { $0.startedAt >= weekStart }
        weekSeconds = weekSessions.reduce(0) { $0 + $1.duration }
        weekPages = Int((Double(weekSessions.reduce(0) { $0 + $1.wordsRead }) / ReadingMath.wordsPerPage).rounded())
        weekActiveBooks = Set(weekSessions.compactMap { $0.book?.id }).count
    }

    var goalProgress: Double { goalMinutes > 0 ? min(todayMinutes / Double(goalMinutes), 1) : 0 }
    var goalReached: Bool { goalMinutes > 0 && todayMinutes >= Double(goalMinutes) }

    /// The current calendar week, day by day.
    var thisWeek: [Day] {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Day(date: date, minutes: minutesByDay[date] ?? 0)
        }
    }

    /// Columns of weeks (oldest first); each column holds 7 days starting on the
    /// calendar's first weekday. Days after today are nil.
    func heatmap(weeks: Int) -> [[Day?]] {
        let today = calendar.startOfDay(for: now)
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).reversed().map { back in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -back, to: currentWeekStart)!
            return (0..<7).map { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                return date > today ? nil : Day(date: date, minutes: minutesByDay[date] ?? 0)
            }
        }
    }

    /// Intensity level 0...4 relative to the daily goal.
    func level(for minutes: Double) -> Int {
        guard minutes >= 1 else { return 0 }
        let goal = Double(max(goalMinutes, 10))
        switch minutes / goal {
        case ..<0.34: return 1
        case ..<0.67: return 2
        case ..<1: return 3
        default: return 4
        }
    }
}
