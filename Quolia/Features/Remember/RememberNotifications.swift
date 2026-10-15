import Foundation
import SwiftData
import UserNotifications

/// Optional daily notification that brings back one highlight.
@MainActor
enum RememberNotifications {
    private static let prefix = "quolia.remember."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Reschedules the next week of reminders (called on launch and when settings change).
    static func refresh(settings: AppSettings, context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        let identifiers = (0..<7).map { "\(prefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard settings.rememberNotificationsEnabled else { return }

        let highlights = (try? context.fetch(FetchDescriptor<Highlight>())) ?? []
        let queue = MemoryScheduler.queue(from: highlights)
        guard !queue.isEmpty else { return }

        let calendar = Calendar.current
        for day in 0..<7 {
            let highlight = queue[day % queue.count]
            guard let date = calendar.date(byAdding: .day, value: day + 1, to: calendar.startOfDay(for: .now)) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = settings.rememberNotificationHour

            let content = UNMutableNotificationContent()
            content.title = String(localized: "A thought from your library")
            let text = highlight.text.count > 160 ? String(highlight.text.prefix(157)) + "…" : highlight.text
            content.body = "“\(text)”" + (highlight.book.map { " — \($0.title)" } ?? "")
            content.sound = nil
            content.userInfo = ["route": "remember"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: identifiers[day], content: content, trigger: trigger))
        }
    }
}
