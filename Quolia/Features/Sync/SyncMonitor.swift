import Foundation
import CoreData
import CloudKit
import Observation

/// Surfaces CloudKit mirroring activity (SwiftData runs on NSPersistentCloudKitContainer).
@Observable
@MainActor
final class SyncMonitor {
    enum State: Equatable {
        case localOnly
        /// Sync is on, but the device isn't signed in to iCloud.
        case noAccount
        case idle
        case syncing
        case failed(String)
    }

    let isCloudBacked: Bool
    private(set) var state: State
    private(set) var lastSync: Date?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(isCloudBacked: Bool) {
        self.isCloudBacked = isCloudBacked
        self.state = isCloudBacked ? .idle : .localOnly
        guard isCloudBacked else { return }
        Task { [weak self] in
            let status = try? await CKContainer(identifier: BookFileStore.containerIdentifier).accountStatus()
            if status != .available, self?.state == .idle { self?.state = .noAccount }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let ended = event.endDate
            let error = event.error?.localizedDescription
            MainActor.assumeIsolated {
                guard let self else { return }
                if ended == nil {
                    self.state = .syncing
                } else if let error {
                    self.state = .failed(error)
                } else {
                    self.state = .idle
                    self.lastSync = ended
                }
            }
        }
    }

    var statusText: String {
        switch state {
        case .localOnly:
            String(localized: "Sync is off. Books stay on this device.")
        case .noAccount:
            String(localized: "Sign in to iCloud to sync your library.")
        case .idle:
            lastSync.map { String(localized: "Up to date · \($0.formatted(.relative(presentation: .named)))") }
                ?? String(localized: "Connected to iCloud")
        case .syncing:
            String(localized: "Syncing…")
        case .failed(let message):
            String(localized: "Sync paused: \(message)")
        }
    }
}
