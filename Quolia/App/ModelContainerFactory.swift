import Foundation
import SwiftData
#if DEBUG
import CoreData
#endif

enum ModelContainerFactory {
    static let modelTypes: [any PersistentModel.Type] = [
        Book.self,
        Highlight.self,
        Bookmark.self,
        ReadingSession.self,
        SavedWord.self,
    ]
    static let schema = Schema(modelTypes)

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

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") {
            if iCloudEnabled, FileManager.default.ubiquityIdentityToken != nil {
                initializeCloudKitSchema()
            } else {
                schemaLog("skipped: iCloud is off in Quolia settings or not signed in on this device")
            }
        }
        #endif

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

    #if DEBUG
    /// With the `-initCloudKitSchema` launch argument, creates every record type in the CloudKit
    /// development environment, so the schema can be deployed to Production before a release.
    /// SwiftData only creates types as records appear, and has no API for this, so it uses Core Data
    /// with a throwaway store.
    private static func initializeCloudKitSchema() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
            schemaLog("failed: couldn't build a Core Data model from the SwiftData types")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloudKitSchema-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: BookFileStore.containerIdentifier)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        do {
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            schemaLog("initialized \(model.entities.map { $0.name ?? "?" }.sorted().joined(separator: ", "))")
        } catch {
            schemaLog("failed: \(error)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }

    /// Unbuffered, so `devicectl --console` shows it right away.
    private static func schemaLog(_ message: String) {
        FileHandle.standardError.write(Data("QuoliaCloudKitSchema: \(message)\n".utf8))
    }
    #endif
}
