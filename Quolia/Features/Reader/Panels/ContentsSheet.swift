import SwiftUI

/// Table of contents, bookmarks and highlights for the open book.
struct ContentsSheet: View {
    let model: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var tab: Tab = .contents

    enum Tab: String, CaseIterable, Identifiable {
        case contents, bookmarks, highlights
        var id: String { rawValue }
        var title: String {
            switch self {
            case .contents: String(localized: "Contents")
            case .bookmarks: String(localized: "Bookmarks")
            case .highlights: String(localized: "Highlights")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .contents: contents
                case .bookmarks: bookmarks
                case .highlights: highlights
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(Color.clear)
            }
            .navigationTitle(model.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Contents

    @ViewBuilder
    private var contents: some View {
        if let content = model.content, model.engine == .text || content.chapters.contains(where: { $0.sourcePage != nil }) {
            ScrollViewReader { proxy in
                List {
                    ForEach(content.chapters) { chapter in
                        Button {
                            if model.engine == .pdf, let page = chapter.sourcePage {
                                model.go(to: ReadingLocator(page: page))
                            } else {
                                model.go(to: ReadingLocator(chapter: chapter.id))
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(isCurrent(chapter) ? Color.qAccent : .clear)
                                    .frame(width: 7, height: 7)
                                Text(chapter.title)
                                    .font(isCurrent(chapter) ? .body.weight(.semibold) : .body)
                                    .foregroundStyle(Color.qInk)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Text(chapterTrailing(chapter))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                        .id(chapter.id)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { proxy.scrollTo(model.chapterIndex, anchor: .center) }
            }
        } else {
            ContentUnavailableView("No table of contents", systemImage: "list.bullet",
                                   description: Text("Use the scrubber to move through this document."))
        }
    }

    private func isCurrent(_ chapter: Chapter) -> Bool {
        if model.engine == .pdf, let content = model.content {
            let next = content.chapter(chapter.id + 1)?.sourcePage ?? Int.max
            return (chapter.sourcePage ?? 0) <= model.pdfPage && model.pdfPage < next
        }
        return chapter.id == model.chapterIndex
    }

    private func chapterTrailing(_ chapter: Chapter) -> String {
        if model.engine == .pdf, let page = chapter.sourcePage { return "p. \(page + 1)" }
        let minutes = Double(chapter.wordCount) / max(settings.measuredWPM, 80)
        return chapter.wordCount > 0 ? DurationFormat.compactRemaining(minutes: minutes) : ""
    }

    // MARK: - Bookmarks

    @ViewBuilder
    private var bookmarks: some View {
        let items = model.book.allBookmarks.sorted { $0.progress < $1.progress }
        if items.isEmpty {
            ContentUnavailableView("No bookmarks yet", systemImage: "bookmark",
                                   description: Text("Tap the bookmark button while reading to save your place."))
        } else {
            List {
                ForEach(items) { bookmark in
                    Button {
                        model.go(to: bookmark.locator)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: "bookmark.fill").foregroundStyle(Color.qAccent).font(.caption)
                                Text(bookmark.chapterTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.qInk)
                                Spacer()
                                Text(bookmark.progress.percentText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            if !bookmark.preview.isEmpty {
                                Text(bookmark.preview)
                                    .font(.qSerif(.subheadline))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text(bookmark.createdAt.quietRelative).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.deleteBookmark(bookmark) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Highlights

    @ViewBuilder
    private var highlights: some View {
        let items = model.book.allHighlights.sorted { $0.progress < $1.progress }
        if items.isEmpty {
            ContentUnavailableView("No highlights yet", systemImage: "highlighter",
                                   description: Text("Select text to highlight a passage or add a note."))
        } else {
            List {
                ForEach(items) { highlight in
                    Button {
                        model.open(highlight)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(highlight.color.color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(highlight.text)
                                    .font(.qSerif(.body))
                                    .foregroundStyle(Color.qInk)
                                    .lineLimit(4)
                                if let note = highlight.note {
                                    Label(note, systemImage: "note.text")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.qAccent)
                                        .lineLimit(3)
                                }
                                Text(highlight.chapterTitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button(role: .destructive) { model.deleteHighlight(id: highlight.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .listStyle(.plain)
                .scrollContentBackground(.hidden)
        }
    }
}
