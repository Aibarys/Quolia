import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SyncMonitor.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = KeychainStore.string(for: ClaudeProvider.keychainKey) ?? ""
    @State private var isGoalSheetPresented = false
    @State private var notificationsDenied = false
    private let initialSyncSetting: Bool

    init() {
        initialSyncSetting = UserDefaults.standard.data(forKey: AppSettings.Key.iCloudSync.storageKey)
            .flatMap { try? JSONDecoder().decode(Bool.self, from: $0) } ?? true
    }

    private static let languages = ["en", "ru", "kk", "es", "de", "fr", "it", "pt", "uk", "tr", "zh", "ja", "ko", "ar"]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.name).tag($0) }
                    }
                }

                Section("Reader") {
                    Button {
                        isGoalSheetPresented = true
                    } label: {
                        LabeledContent("Daily goal", value: DurationFormat.short(Double(settings.dailyGoalMinutes * 60)))
                    }
                    .foregroundStyle(Color.qInk)
                    Picker("Layout", selection: $settings.reader.layout) {
                        ForEach(ReaderLayout.allCases) { Text($0.name).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Auto Scroll speed", value: String(localized: "\(Int(settings.autoScrollWPM)) wpm"))
                        Slider(value: $settings.autoScrollWPM, in: ReadingSpeed.wpmRange, step: 10)
                    }
                    Picker("Translate into", selection: $settings.translationLanguage) {
                        ForEach(Self.languages, id: \.self) { code in
                            Text(Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                        }
                    }
                }

                Section {
                    Toggle("Daily memory", isOn: Binding(get: { settings.rememberNotificationsEnabled }, set: setReminders))
                    if settings.rememberNotificationsEnabled {
                        Picker("Time", selection: $settings.rememberNotificationHour) {
                            ForEach(6..<23, id: \.self) { hour in
                                Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
                                    .formatted(date: .omitted, time: .shortened)).tag(hour)
                            }
                        }
                        .onChange(of: settings.rememberNotificationHour) {
                            RememberNotifications.refresh(settings: settings, context: context)
                        }
                    }
                } header: {
                    Text("Remember")
                } footer: {
                    Text(notificationsDenied
                         ? "Notifications are turned off for Quolia in the Settings app."
                         : "Once a day, Quolia can bring back one of your highlights.")
                }

                aiSection(settings: settings)

                Section {
                    Toggle("iCloud Sync", isOn: $settings.iCloudSyncEnabled)
                    LabeledContent("Status", value: sync.statusText)
                        .font(.subheadline)
                } header: {
                    Text("Sync")
                } footer: {
                    Text(settings.iCloudSyncEnabled != initialSyncSetting
                         ? "Restart Quolia to apply this change."
                         : "Books, progress, highlights, notes, bookmarks, settings and reading stats sync privately through your iCloud account.")
                }

                Section("Library") {
                    Button("Add Sample Book") {
                        Task { _ = await BookImporter(context: context).importSampleBook() }
                    }
                }

                Section {
                    VStack(spacing: 6) {
                        Text("Quolia").font(.qSerif(.title3, weight: .semibold))
                        Text("Read. Highlight. Remember.").font(.footnote).foregroundStyle(Color.qMuted)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $isGoalSheetPresented) { GoalSheet() }
        }
    }

    @ViewBuilder
    private func aiSection(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section {
            Picker("Assistant", selection: $settings.aiProvider) {
                ForEach(AIProviderKind.allCases) { Text($0.name).tag($0) }
            }
            if settings.aiProvider == .claude {
                SecureField("Anthropic API key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: apiKey) { _, value in
                        KeychainStore.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: ClaudeProvider.keychainKey)
                    }
                Picker("Model", selection: $settings.claudeModel) {
                    ForEach(ClaudeModels.all, id: \.id) { model in
                        VStack(alignment: .leading) {
                            Text(model.name)
                            Text(model.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                }
            }
            if case .unavailable(let reason) = AIService.resolve(settings: settings), settings.aiProvider != .off {
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.qMuted)
            }
        } header: {
            Text("AI")
        } footer: {
            Text(aiFooter(settings.aiProvider))
        }
    }

    private func aiFooter(_ provider: AIProviderKind) -> String {
        let rule = String(localized: "AI only ever sees the part of the book you've already read — never anything beyond your position, so it can't spoil what's ahead.")
        switch provider {
        case .appleIntelligence: return String(localized: "Runs privately on your device.") + " " + rule
        case .claude: return String(localized: "Your key is kept in this device's keychain. When you ask a question, the text you've read so far is sent to Anthropic.") + " " + rule
        case .off: return String(localized: "Explain, Simplify, Summarize and Ask the Book stay unavailable until you choose an assistant.")
        }
    }

    private func setReminders(_ enabled: Bool) {
        Task {
            if enabled {
                let granted = await RememberNotifications.requestAuthorization()
                notificationsDenied = !granted
                settings.rememberNotificationsEnabled = granted
            } else {
                settings.rememberNotificationsEnabled = false
            }
            RememberNotifications.refresh(settings: settings, context: context)
        }
    }
}
