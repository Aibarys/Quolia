import SwiftUI

/// A book cover with a gentle spine sheen. Books without artwork get a
/// generated typographic cover so the library always looks considered.
struct BookCoverView: View {
    let title: String
    let author: String
    let coverData: Data?
    var cornerRadius: CGFloat = Metrics.coverCornerRadius
    var showsShadow = true

    init(book: Book, cornerRadius: CGFloat = Metrics.coverCornerRadius, showsShadow: Bool = true) {
        self.title = book.title
        self.author = book.author
        self.coverData = book.coverImageData
        self.cornerRadius = cornerRadius
        self.showsShadow = showsShadow
    }

    init(title: String, author: String, coverData: Data?, cornerRadius: CGFloat = Metrics.coverCornerRadius, showsShadow: Bool = true) {
        self.title = title
        self.author = author
        self.coverData = coverData
        self.cornerRadius = cornerRadius
        self.showsShadow = showsShadow
    }

    var body: some View {
        Color.clear
            .aspectRatio(1 / Metrics.coverAspect, contentMode: .fit)
            .overlay {
                if let image = CoverImageCache.shared.image(for: coverData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    GeneratedCover(title: title, author: author)
                }
            }
            .overlay(alignment: .leading) {
                // Spine
                LinearGradient(colors: [.black.opacity(0.18), .white.opacity(0.10), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(showsShadow ? 0.16 : 0), radius: 8, x: 0, y: 5)
            .accessibilityElement()
            .accessibilityLabel("\(title) by \(author.isEmpty ? String(localized: "Unknown Author") : author)")
    }
}

/// Deterministic, minimal generated cover.
struct GeneratedCover: View {
    let title: String
    let author: String

    private var palette: (Color, Color, Color) {
        let palettes: [(Color, Color, Color)] = [
            (Color(red: 0.18, green: 0.24, blue: 0.22), Color(red: 0.25, green: 0.33, blue: 0.30), Color(red: 0.93, green: 0.89, blue: 0.80)),
            (Color(red: 0.55, green: 0.29, blue: 0.20), Color(red: 0.68, green: 0.39, blue: 0.27), Color(red: 0.98, green: 0.93, blue: 0.86)),
            (Color(red: 0.16, green: 0.20, blue: 0.33), Color(red: 0.24, green: 0.29, blue: 0.45), Color(red: 0.92, green: 0.91, blue: 0.86)),
            (Color(red: 0.86, green: 0.82, blue: 0.73), Color(red: 0.93, green: 0.90, blue: 0.83), Color(red: 0.20, green: 0.18, blue: 0.16)),
            (Color(red: 0.36, green: 0.20, blue: 0.30), Color(red: 0.47, green: 0.29, blue: 0.40), Color(red: 0.96, green: 0.90, blue: 0.90)),
            (Color(red: 0.12, green: 0.12, blue: 0.13), Color(red: 0.22, green: 0.22, blue: 0.24), Color(red: 0.93, green: 0.80, blue: 0.62)),
        ]
        var hash: UInt64 = 5381
        for byte in title.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palettes[Int(hash % UInt64(palettes.count))]
    }

    var body: some View {
        let (base, light, ink) = palette
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [light, base], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: w * 0.05) {
                    Rectangle().fill(ink.opacity(0.7)).frame(width: w * 0.16, height: max(w * 0.012, 1))
                    Text(title)
                        .font(.system(size: max(w * 0.115, 8), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(5)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    if !author.isEmpty {
                        Text(author.uppercased())
                            .font(.system(size: max(w * 0.06, 6), weight: .medium))
                            .tracking(w * 0.006)
                            .foregroundStyle(ink.opacity(0.75))
                            .lineLimit(2)
                    }
                }
                .padding(w * 0.12)
            }
        }
    }
}

/// Decodes cover thumbnails once and keeps them in memory.
final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSData, UIImage>()

    init() { cache.countLimit = 200 }

    func image(for data: Data?) -> UIImage? {
        guard let data else { return nil }
        let key = data as NSData
        if let image = cache.object(forKey: key) { return image }
        guard let cg = ImageDownsampler.cgImage(from: data, maxPixelSize: 600) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key)
        return image
    }
}
