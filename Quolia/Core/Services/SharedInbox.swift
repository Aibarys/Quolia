import Foundation

/// A drop box in the App Group container. The Share Extension places files here;
/// the app imports them the next time it becomes active.
///
/// Compiled into both the app and the Share Extension.
enum SharedInbox {
    static let appGroup = "group.com.quolia.reader"

    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        let inbox = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    /// Copies a file into its own folder in the inbox, keeping the original name
    /// (Quolia uses it as a title fallback). Returns the stored URL.
    @discardableResult
    static func enqueue(fileAt source: URL, suggestedName: String? = nil) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = sanitized(suggestedName ?? source.lastPathComponent, fallbackExtension: source.pathExtension)
        let destination = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Saves shared plain text (e.g. an article selection) as a .txt book.
    @discardableResult
    static func enqueue(text: String, title: String) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(sanitized(title, fallbackExtension: "txt", forcedExtension: "txt"))
        try text.write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// Files waiting to be imported, oldest first.
    static func pendingFiles() -> [URL] {
        guard let directory,
              let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
        else { return [] }
        let sorted = folders.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
        return sorted.compactMap { folder in
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.first
        }
    }

    /// Removes an imported file and its folder.
    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private static func sanitized(_ name: String, fallbackExtension: String, forcedExtension: String? = nil) -> String {
        var base = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "Book" }
        if base.count > 120 { base = String(base.prefix(120)) }
        if let forcedExtension {
            if (base as NSString).pathExtension.lowercased() != forcedExtension { base += ".\(forcedExtension)" }
        } else if (base as NSString).pathExtension.isEmpty, !fallbackExtension.isEmpty {
            base += ".\(fallbackExtension)"
        }
        return base
    }
}
