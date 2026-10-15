import Foundation
import SwiftData

enum ModelContainerFactory {
    static let schema = Schema([
        Book.self,
        Highlight.self,
        Bookmark.self,
        ReadingSession.self,
        SavedWord.self,
    ])

    struct Result {
        let container: ModelContainer
        let isCloudBacked: Bool
    }

    /// Uses the CloudKit private database when the user is signed in to iCloud
    /// and sync is enabled; otherwise a local store with the same schema.
    static func make(iCloudEnabled: Bool, inMemory: Bool = false) -> Result {
        // The store lives in Application Support, which doesn't exist on first launch.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return Result(container: try! ModelContainer(for: schema, configurations: config), isCloudBacked: false)
        }

        if iCloudEnabled, FileManager.default.ubiquityIdentityToken != nil {
            let config = ModelConfiguration("Quolia", schema: schema,
                                            cloudKitDatabase: .private(BookFileStore.containerIdentifier))
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return Result(container: container, isCloudBacked: true)
            }
        }

        let config = ModelConfiguration("Quolia", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: config) {
            return Result(container: container, isCloudBacked: false)
        }
        // Last resort so the app still launches; data won't persist.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return Result(container: try! ModelContainer(for: schema, configurations: memory), isCloudBacked: false)
    }
}
