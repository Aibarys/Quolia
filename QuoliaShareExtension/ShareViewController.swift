import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point of "Share → Quolia". Hosts a small SwiftUI card.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model) { [weak self] in self?.finish() })
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        model.onFinished = { [weak self] in self?.finish() }
        model.process(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@Observable
@MainActor
final class ShareModel {
    enum State: Equatable {
        case working
        case added([String])
        case failed(String)
    }

    private(set) var state: State = .working
    @ObservationIgnored var onFinished: (() -> Void)?

    private static let bookTypes = ["org.idpf.epub-container", "org.fictionbook.fb2", "dyn.ah62d4rv4ge80q2vw",
                                    UTType.pdf.identifier, UTType.zip.identifier, UTType.plainText.identifier]

    func process(_ items: [NSExtensionItem]) {
        Task {
            var added: [String] = []
            var lastError: Error?
            for item in items {
                for provider in item.attachments ?? [] {
                    guard let type = Self.bookTypes.first(where: provider.hasItemConformingToTypeIdentifier) else { continue }
                    do {
                        if let name = try await save(provider, type: type, item: item) { added.append(name) }
                    } catch {
                        lastError = error
                    }
                }
            }
            if added.isEmpty {
                state = .failed(lastError == nil
                                ? String(localized: "Quolia can import EPUB, FB2, PDF and TXT files.")
                                : String(localized: "Something went wrong while saving the file."))
            } else {
                state = .added(added)
                try? await Task.sleep(for: .seconds(1.6))
                onFinished?()
            }
        }
    }

    /// Copies the shared file into the App Group inbox. Returns a display name.
    private func save(_ provider: NSItemProvider, type: String, item: NSExtensionItem) async throws -> String? {
        let fileExtension = UTType(type)?.preferredFilenameExtension
            ?? ["org.idpf.epub-container": "epub", "org.fictionbook.fb2": "fb2", "dyn.ah62d4rv4ge80q2vw": "fb2"][type] ?? "txt"
        let suggested = provider.suggestedName.map { name -> String in
            (name as NSString).pathExtension.isEmpty ? "\(name).\(fileExtension)" : name
        }

        // Files (from Files, Mail, Safari downloads, messengers…)
        if let stored = try? await copyFileRepresentation(provider, type: type, suggestedName: suggested) {
            return stored.deletingPathExtension().lastPathComponent
        }

        // Plain text shared as a string (e.g. a selection) becomes a .txt book.
        let loaded = try await provider.loadItem(forTypeIdentifier: type)
        if let url = loaded as? URL, url.isFileURL {
            return try SharedInbox.enqueue(fileAt: url, suggestedName: suggested).deletingPathExtension().lastPathComponent
        }
        let text = (loaded as? String) ?? (loaded as? Data).flatMap { String(data: $0, encoding: .utf8) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let title = item.attributedContentText?.string.nonEmptyLine
            ?? item.attributedTitle?.string.nonEmptyLine
            ?? text.nonEmptyLine
            ?? String(localized: "Shared Text")
        return try SharedInbox.enqueue(text: text, title: String(title.prefix(60))).deletingPathExtension().lastPathComponent
    }

    private func copyFileRepresentation(_ provider: NSItemProvider, type: String, suggestedName: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                // The temporary file disappears when this closure returns — copy it now.
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    continuation.resume(returning: try SharedInbox.enqueue(fileAt: url, suggestedName: suggestedName))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension String {
    var nonEmptyLine: String? {
        split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
