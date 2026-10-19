import SwiftUI

enum QuoteCardFormat: String, CaseIterable, Identifiable {
    case story, square, post

    var id: String { rawValue }

    var name: String {
        switch self {
        case .story: String(localized: "Story", comment: "Quote card format (Instagram Story)")
        case .square: String(localized: "Square", comment: "Quote card format")
        case .post: "Threads / X"
        }
    }

    /// Logical size in points; rendered at 3× (1080 px wide).
    var size: CGSize {
        switch self {
        case .story: CGSize(width: 360, height: 640)
        case .square: CGSize(width: 360, height: 360)
        case .post: CGSize(width: 360, height: 450)
        }
    }
}

enum QuoteCardTemplate: String, CaseIterable, Identifiable {
    case paper, night, sepia, mist, ember, cover

    var id: String { rawValue }
    var name: String {
        switch self {
        case .paper: String(localized: "Paper", comment: "Quote card template")
        case .night: String(localized: "Night", comment: "Quote card template")
        case .sepia: String(localized: "Sepia", comment: "Quote card template")
        case .mist: String(localized: "Mist", comment: "Quote card template")
        case .ember: String(localized: "Ember", comment: "Quote card template")
        case .cover: String(localized: "Cover", comment: "Quote card template using the book cover")
        }
    }

    var background: AnyShapeStyle {
        switch self {
        case .paper: AnyShapeStyle(Color(red: 0.98, green: 0.97, blue: 0.95))
        case .night: AnyShapeStyle(Color(red: 0.07, green: 0.07, blue: 0.08))
        case .sepia: AnyShapeStyle(Color(red: 0.95, green: 0.91, blue: 0.82))
        case .mist: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.88, green: 0.91, blue: 0.95), Color(red: 0.96, green: 0.92, blue: 0.90)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ember: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.76, green: 0.38, blue: 0.21), Color(red: 0.55, green: 0.24, blue: 0.16)],
                                                  startPoint: .top, endPoint: .bottom))
        case .cover: AnyShapeStyle(Color(red: 0.1, green: 0.1, blue: 0.11))
        }
    }

    var ink: Color {
        switch self {
        case .paper, .mist: Color(red: 0.12, green: 0.12, blue: 0.13)
        case .sepia: Color(red: 0.30, green: 0.22, blue: 0.15)
        case .night, .ember, .cover: Color(red: 0.97, green: 0.95, blue: 0.91)
        }
    }

    var accent: Color {
        switch self {
        case .paper, .mist, .sepia: Color(red: 0.78, green: 0.41, blue: 0.23)
        case .night, .cover: Color(red: 0.93, green: 0.62, blue: 0.40)
        case .ember: Color(red: 1, green: 0.88, blue: 0.75)
        }
    }
}

/// The card itself — also used as the ImageRenderer source.
struct QuoteCardView: View {
    let draft: QuoteDraft
    let template: QuoteCardTemplate
    let format: QuoteCardFormat
    var coverImage: UIImage?

    private var fontSize: CGFloat {
        let count = draft.text.count
        let base: CGFloat = format == .square ? 22 : (format == .post ? 24 : 27)
        switch count {
        case ..<90: return base
        case ..<180: return base * 0.84
        case ..<300: return base * 0.72
        case ..<500: return base * 0.6
        default: return base * 0.5
        }
    }

    var body: some View {
        let size = format.size
        ZStack {
            Rectangle().fill(template.background)
            if template == .cover, let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.55))
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 0)
                Text("“")
                    .font(.system(size: 64, weight: .regular, design: .serif))
                    .foregroundStyle(template.accent)
                    .frame(height: 34, alignment: .top)
                Text(draft.text)
                    .font(.system(size: fontSize, weight: .regular, design: .serif))
                    .lineSpacing(fontSize * 0.28)
                    .foregroundStyle(template.ink)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: false)
                Rectangle().fill(template.accent).frame(width: 28, height: 1.5)
                VStack(alignment: .leading, spacing: 4) {
                    if !draft.author.isEmpty {
                        Text(draft.author.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(template.ink.opacity(0.85))
                    }
                    Text(draft.bookTitle)
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(template.ink.opacity(0.7))
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Text("Quolia")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .tracking(2)
                        .foregroundStyle(template.ink.opacity(0.4))
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, format == .story ? 56 : 30)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

/// Pick a format and template, preview, then share as an image or as text.
struct QuoteCardComposer: View {
    let draft: QuoteDraft
    var coverData: Data?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var format: QuoteCardFormat = .story
    @State private var template: QuoteCardTemplate = .paper
    @State private var rendered: Image?

    private var coverImage: UIImage? { CoverImageCache.shared.image(for: coverData) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Format", selection: $format) {
                    ForEach(QuoteCardFormat.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                GeometryReader { proxy in
                    let size = format.size
                    let scale = min(proxy.size.width / size.width, proxy.size.height / size.height, 1.2)
                    QuoteCardView(draft: draft, template: template, format: format, coverImage: coverImage)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .scaleEffect(scale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .animation(.qSpring, value: format)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(availableTemplates) { item in
                            Button {
                                template = item
                                Haptics.selection()
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(item.background)
                                        .frame(width: 52, height: 52)
                                        .overlay {
                                            Text("Aa").font(.system(size: 16, design: .serif)).foregroundStyle(item.ink)
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(template == item ? Color.qAccent : Color.qHairline, lineWidth: template == item ? 2.5 : 1)
                                        }
                                    Text(item.name).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                HStack(spacing: 12) {
                    ShareLink(item: HighlightService.shareText(for: draft.text, bookTitle: draft.bookTitle, author: draft.author)) {
                        Label("Text", systemImage: "text.quote")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if let rendered {
                        ShareLink(item: rendered, preview: SharePreview("Quote from \(draft.bookTitle)", image: rendered)) {
                            Label("Share Image", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .inkProminentButtonStyle()
                    }
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .navigationTitle("Quote Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: "\(format.rawValue)-\(template.rawValue)") { render() }
        }
        .presentationDetents([.large])
    }

    private var availableTemplates: [QuoteCardTemplate] {
        QuoteCardTemplate.allCases.filter { $0 != .cover || coverImage != nil }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: QuoteCardView(draft: draft, template: template, format: format, coverImage: coverImage))
        renderer.scale = 3
        if let image = renderer.uiImage {
            rendered = Image(uiImage: image)
        }
    }
}
