import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var readerNamespace
    @State private var isImportingInbox = false

    var body: some View {
        @Bindable var router = router

        Group {
            if settings.hasCompletedOnboarding {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: settings.hasCompletedOnboarding)
        .environment(\.readerTransitionNamespace, readerNamespace)
        .fullScreenCover(item: $router.reader) { request in
            ReaderScreen(request: request)
                .modifier(ReaderZoomTransition(request: request, namespace: readerNamespace))
                .environment(settings)
                .environment(router)
                .environment(toasts)
        }
        .sheet(isPresented: $router.isFirstBookPromptPresented) {
            FirstBookSheet()
        }
        .sheet(isPresented: $router.isSettingsPresented) {
            SettingsView()
        }
        .onOpenURL(perform: handle)
        .task { await importSharedInbox() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await importSharedInbox() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quoliaOpenRemember)) { _ in
            router.reader = nil
            router.selectedTab = .remember
        }
        .toastOverlay()
    }

    /// Imports books dropped off by the Share Extension.
    private func importSharedInbox() async {
        guard !isImportingInbox else { return }
        let files = SharedInbox.pendingFiles()
        guard !files.isEmpty else { return }
        isImportingInbox = true
        defer { isImportingInbox = false }
        let outcome = await BookImporter(context: context).importBooks(from: files)
        files.forEach(SharedInbox.remove)
        if let summary = outcome.summary {
            toasts.show(summary, symbol: outcome.failures.isEmpty ? "books.vertical.fill" : "exclamationmark.triangle.fill")
        }
        if !settings.hasCompletedOnboarding, !outcome.imported.isEmpty {
            settings.hasCompletedOnboarding = true
        }
    }

    private func handle(_ url: URL) {
        if url.isFileURL {
            Task {
                let outcome = await BookImporter(context: context).importBooks(from: [url])
                // Clean up the system Inbox copy left by AirDrop / "Open in".
                if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
                if let summary = outcome.summary {
                    toasts.show(summary, symbol: outcome.failures.isEmpty ? "books.vertical.fill" : "exclamationmark.triangle.fill")
                }
                if !settings.hasCompletedOnboarding, !outcome.imported.isEmpty {
                    settings.hasCompletedOnboarding = true
                }
            }
            return
        }
        guard url.scheme == "quolia" else { return }
        switch url.host() {
        case "remember": router.selectedTab = .remember
        case "stats": router.selectedTab = .stats
        case "notes": router.selectedTab = .notes
        default: router.selectedTab = .library
        }
    }
}

/// Zooms the reader out of the tapped cover (iOS 18+).
private struct ReaderZoomTransition: ViewModifier {
    let request: ReaderRequest
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if request.zoomsFromCover {
            content.navigationTransition(.zoom(sourceID: request.book.id, in: namespace))
        } else {
            content
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab("Notes", systemImage: "text.quote", value: AppTab.notes) {
                KnowledgeView()
            }
            Tab("Remember", systemImage: "memories", value: AppTab.remember) {
                RememberView()
            }
            Tab("Stats", systemImage: "chart.bar", value: AppTab.stats) {
                StatsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: router.selectedTab) { Haptics.selection() }
    }
}
