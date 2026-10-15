import SwiftUI
import SwiftData

@main
struct QuoliaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettings
    @State private var router = AppRouter()
    @State private var toasts = ToastCenter()
    @State private var sync: SyncMonitor
    private let container: ModelContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetQuolia") {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        }
        let settings = AppSettings()
        let result = ModelContainerFactory.make(iCloudEnabled: settings.iCloudSyncEnabled,
                                                inMemory: arguments.contains("-inMemoryStore"))
        container = result.container
        _settings = State(initialValue: settings)
        _sync = State(initialValue: SyncMonitor(isCloudBacked: result.isCloudBacked))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(router)
                .environment(toasts)
                .environment(sync)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(.qAccent)
                .task {
                    await BookFileStore.shared.prepare(iCloudEnabled: settings.iCloudSyncEnabled)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-seedDemoData") {
                        await DemoData.seedIfNeeded(context: container.mainContext, settings: settings)
                    }
                    await DebugLaunch.apply(router: router, settings: settings, context: container.mainContext)
                    #endif
                    RememberNotifications.refresh(settings: settings, context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications() // CloudKit silent pushes
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            NotificationCenter.default.post(name: .quoliaOpenRemember, object: nil)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

extension Notification.Name {
    static let quoliaOpenRemember = Notification.Name("quolia.openRemember")
}
