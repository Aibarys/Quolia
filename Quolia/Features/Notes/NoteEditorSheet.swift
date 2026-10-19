import SwiftUI
import SwiftData

/// Write or edit the note attached to a highlight, with tags.
struct NoteEditorSheet: View {
    let highlight: Highlight
    let onSave: (String?, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allHighlights: [Highlight]
    @State private var text: String
    @State private var tags: [String]
    @State private var tagInput = ""
    @FocusState private var focusedField: Field?

    private enum Field { case note, tag }

    init(highlight: Highlight, onSave: @escaping (String?, [String]) -> Void) {
        self.highlight = highlight
        self.onSave = onSave
        _text = State(initialValue: highlight.note ?? "")
        _tags = State(initialValue: highlight.tags)
    }

    private var suggestedTags: [String] {
        let used = Set(allHighlights.flatMap(\.tags))
        let query = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
        return used.subtracting(tags)
            .filter { query.isEmpty || $0.lowercased().hasPrefix(query) }
            .sorted()
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    QuoteBlock(text: highlight.text, color: highlight.color)

                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("What does this make you think?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $text)
                            .focused($focusedField, equals: .note)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                    }
                    .font(.body)
                    .padding(10)
                    .background(Color.qSurfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TAGS").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    withAnimation(.qQuick) { tags.removeAll { $0 == tag } }
                                } label: {
                                    HStack(spacing: 4) {
                                        TagChip(tag: tag, isSelected: true)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                            TextField("Add tag", text: $tagInput)
                                .focused($focusedField, equals: .tag)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit(addTag)
                                .onChange(of: tagInput) { _, value in
                                    if value.contains(",") { addTag() }
                                }
                                .frame(width: 120)
                                .font(.subheadline)
                        }
                        if !suggestedTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(suggestedTags, id: \.self) { tag in
                                        Button {
                                            withAnimation(.qQuick) { tags.append(tag); tagInput = "" }
                                        } label: { TagChip(tag: tag) }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if highlight.hasNote {
                        Button(role: .destructive) {
                            onSave(nil, tags)
                            dismiss()
                        } label: {
                            Label("Delete Note", systemImage: "trash")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(22)
            }
            .navigationTitle(highlight.hasNote ? "Edit Note" : "New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        addTag()
                        onSave(text, tags)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { focusedField = .note }
        }
        .presentationDetents([.large])
    }

    private func addTag() {
        let cleaned = tagInput
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        tagInput = ""
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { return }
        withAnimation(.qQuick) { tags.append(cleaned) }
    }
}

/// A quote set in the editorial serif with its highlight color.
struct QuoteBlock: View {
    let text: String
    let color: HighlightColor
    var lineLimit: Int? = 8

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.color)
                .frame(width: 4)
            Text(text)
                .font(.qSerif(.body))
                .foregroundStyle(Color.qInk)
                .lineLimit(lineLimit)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Opened from a note marker in the margin.
struct NoteCardSheet: View {
    let highlight: Highlight
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            QuoteBlock(text: highlight.text, color: highlight.color, lineLimit: 6)

            if let note = highlight.note {
                Text(note)
                    .font(.body)
                    .foregroundStyle(Color.qInk)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.qAccentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if !highlight.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(highlight.tags, id: \.self) { TagChip(tag: $0) }
                }
            }

            HStack {
                Text(highlight.chapterTitle)
                Text("·")
                Text((highlight.noteUpdatedAt ?? highlight.createdAt).quietRelative)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: onEdit) { Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity) }
                    .inkProminentButtonStyle()
                Button(action: onShare) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash").frame(width: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Delete highlight")
            }
            .controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Delete this highlight and its note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
