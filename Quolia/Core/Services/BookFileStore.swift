import Foundation

/// Owns the book files. When iCloud is available, files live in the app's
/// iCloud container so they follow the user to every device; otherwise they
/// stay in Application Support.
final class BookFileStore: @unchecked Sendable {
    static let shared = BookFileStore()
    static let containerIdentifier = "iCloud.com.quolia.reader"

    enum StoreError: LocalizedError {
        case missingFile
        case downloadTimedOut
        var errorDescription: String? {
            switch self {
            case .missingFile: String(localized: "The book file is missing. Try importing it again.")
            case .downloadTimedOut: String(localized: "The book is still downloading from iCloud. Please try again in a moment.")
            }
        }
    }

    let localRoot: URL
    private let lock = NSLock()
    private var _ubiquityRoot: URL?
    private var _iCloudEnabled = false

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        localRoot = support.appendingPathComponent("Books", isDirectory: true)
        try? FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
    }

    var ubiquityRoot: URL? {
        lock.withLock { _iCloudEnabled ? _ubiquityRoot : nil }
    }

    var isUsingICloud: Bool { ubiquityRoot != nil }

    /// Resolves the iCloud container. Must not run on the main thread.
    func prepare(iCloudEnabled: Bool) async {
        let root: URL? = await Task.detached(priority: .utility) {
            guard iCloudEnabled, FileManager.default.ubiquityIdentityToken != nil,
                  let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerIdentifier)
            else { return nil }
            let books = container.appendingPathComponent("Books", isDirectory: true)
            try? FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
            return books
        }.value
        lock.withLock {
            _ubiquityRoot = root
            _iCloudEnabled = iCloudEnabled
        }
    }

    /// Copies a file into the store and returns its store-relative name.
    func store(fileAt source: URL, format: BookFormat) throws -> String {
        let name = "\(UUID().uuidString).\(format.fileExtension)"
        let destination = (ubiquityRoot ?? localRoot).appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return name
    }

    /// Location of a stored file, if it is present on this device.
    func existingURL(for fileName: String) -> URL? {
        for root in [ubiquityRoot, localRoot].compactMap({ $0 }) {
            let url = root.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Returns a readable local URL, downloading from iCloud if needed.
    func availableURL(for fileName: String) async throws -> URL {
        if let url = existingURL(for: fileName) { return url }
        guard let root = ubiquityRoot else { throw StoreError.missingFile }
        let url = root.appendingPathComponent(fileName)
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            throw StoreError.missingFile
        }
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(500))
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        throw StoreError.downloadTimedOut
    }

    func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        for root in [ubiquityRoot, localRoot].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(fileName))
        }
    }
}
