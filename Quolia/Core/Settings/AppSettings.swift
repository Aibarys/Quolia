import SwiftUI
import Observation

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: String(localized: "appearance.system", defaultValue: "System")
        case .light: String(localized: "appearance.light", defaultValue: "Light")
        case .dark: String(localized: "appearance.dark", defaultValue: "Dark")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum LibraryLayout: String, Codable, CaseIterable {
    case grid, list
}

enum LibrarySort: String, Codable, CaseIterable, Identifiable {
    case recent, added, title, author, progress
    var id: String { rawValue }
    var name: String {
        switch self {
        case .recent: String(localized: "Recently Read")
        case .added: String(localized: "Recently Added")
        case .title: String(localized: "Title", comment: "Sort by title")
        case .author: String(localized: "Author", comment: "Sort by author")
        case .progress: String(localized: "Progress", comment: "Sort by progress")
        }
    }
}

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case appleIntelligence, claude, off
    var id: String { rawValue }
    var name: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .claude: "Claude"
        case .off: String(localized: "Off", comment: "AI assistant turned off")
        }
    }
}

/// App-wide preferences. Backed by UserDefaults and mirrored to iCloud
/// key-value storage so reading preferences follow the user across devices.
@Observable
@MainActor
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var applyingCloudChange = false

    var hasCompletedOnboarding: Bool { didSet { store(hasCompletedOnboarding, .onboarding) } }
    var appearance: AppAppearance { didSet { store(appearance, .appearance) } }
    var libraryLayout: LibraryLayout { didSet { store(libraryLayout, .libraryLayout) } }
    var librarySort: LibrarySort { didSet { store(librarySort, .librarySort) } }
    var dailyGoalMinutes: Int { didSet { store(dailyGoalMinutes, .dailyGoal) } }
    var reader: ReaderPreferences { didSet { store(reader, .reader) } }
    var autoScrollWPM: Double { didSet { store(autoScrollWPM, .autoScrollWPM) } }
    /// Personal reading speed, learned from reading sessions.
    var measuredWPM: Double { didSet { store(measuredWPM, .measuredWPM) } }
    var aiProvider: AIProviderKind { didSet { store(aiProvider, .aiProvider) } }
    var claudeModel: String { didSet { store(claudeModel, .claudeModel) } }
    var translationLanguage: String { didSet { store(translationLanguage, .translationLanguage) } }
    var rememberNotificationsEnabled: Bool { didSet { store(rememberNotificationsEnabled, .rememberNotifications) } }
    var rememberNotificationHour: Int { didSet { store(rememberNotificationHour, .rememberHour) } }
    var iCloudSyncEnabled: Bool { didSet { store(iCloudSyncEnabled, .iCloudSync) } }

    enum Key: String, CaseIterable {
        case onboarding, appearance, libraryLayout, librarySort, dailyGoal, reader, autoScrollWPM, measuredWPM
        case aiProvider, claudeModel, translationLanguage, rememberNotifications, rememberHour, iCloudSync

        /// Keys mirrored to iCloud.
        var syncs: Bool {
            switch self {
            case .appearance, .libraryLayout, .librarySort, .dailyGoal, .reader, .autoScrollWPM, .measuredWPM,
                 .translationLanguage, .claudeModel:
                true
            default:
                false
            }
        }

        var storageKey: String { "quolia." + rawValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let preferredLanguage = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"

        hasCompletedOnboarding = Self.load(.onboarding, defaults) ?? false
        appearance = Self.load(.appearance, defaults) ?? .system
        libraryLayout = Self.load(.libraryLayout, defaults) ?? .grid
        librarySort = Self.load(.librarySort, defaults) ?? .recent
        dailyGoalMinutes = Self.load(.dailyGoal, defaults) ?? 20
        reader = Self.load(.reader, defaults) ?? ReaderPreferences()
        autoScrollWPM = Self.load(.autoScrollWPM, defaults) ?? 220
        measuredWPM = Self.load(.measuredWPM, defaults) ?? ReadingMath.defaultWPM
        aiProvider = Self.load(.aiProvider, defaults) ?? .appleIntelligence
        claudeModel = Self.load(.claudeModel, defaults) ?? ClaudeModels.defaultModel
        translationLanguage = Self.load(.translationLanguage, defaults) ?? (preferredLanguage == "en" ? "es" : preferredLanguage)
        rememberNotificationsEnabled = Self.load(.rememberNotifications, defaults) ?? false
        rememberNotificationHour = Self.load(.rememberHour, defaults) ?? 9
        iCloudSyncEnabled = Self.load(.iCloudSync, defaults) ?? true

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullFromCloud() }
        }
        cloud.synchronize()
    }

    // MARK: - Persistence

    private static func load<T: Codable>(_ key: Key, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key.storageKey) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func store<T: Codable>(_ value: T, _ key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.storageKey)
        if key.syncs && iCloudSyncEnabled && !applyingCloudChange {
            cloud.set(data, forKey: key.storageKey)
        }
    }

    private func pullFromCloud() {
        guard iCloudSyncEnabled else { return }
        applyingCloudChange = true
        defer { applyingCloudChange = false }
        func value<T: Codable>(_ key: Key) -> T? {
            guard let data = cloud.data(forKey: key.storageKey) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        if let v: AppAppearance = value(.appearance), v != appearance { appearance = v }
        if let v: LibraryLayout = value(.libraryLayout), v != libraryLayout { libraryLayout = v }
        if let v: LibrarySort = value(.librarySort), v != librarySort { librarySort = v }
        if let v: Int = value(.dailyGoal), v != dailyGoalMinutes { dailyGoalMinutes = v }
        if let v: ReaderPreferences = value(.reader), v != reader { reader = v }
        if let v: Double = value(.autoScrollWPM), v != autoScrollWPM { autoScrollWPM = v }
        if let v: Double = value(.measuredWPM), v != measuredWPM { measuredWPM = v }
        if let v: String = value(.translationLanguage), v != translationLanguage { translationLanguage = v }
        if let v: String = value(.claudeModel), v != claudeModel { claudeModel = v }
    }

    /// Blends a newly observed reading speed into the personal estimate.
    func recordReadingSpeed(words: Int, seconds: Double) {
        guard seconds >= 120, words > 50 else { return }
        let wpm = Double(words) / (seconds / 60)
        guard (60...900).contains(wpm) else { return }
        measuredWPM = (measuredWPM * 0.8 + wpm * 0.2).rounded()
    }
}
