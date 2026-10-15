import SwiftUI
import UIKit

/// Quolia's calm palette: warm paper, soft ink, a single terracotta accent.
extension Color {
    static let qBackground = Color(light: UIColor(red: 0.976, green: 0.972, blue: 0.961, alpha: 1),
                                   dark: UIColor(red: 0.055, green: 0.055, blue: 0.060, alpha: 1))
    static let qSurface = Color(light: .white,
                                dark: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1))
    static let qSurfaceSecondary = Color(light: UIColor(red: 0.945, green: 0.937, blue: 0.918, alpha: 1),
                                         dark: UIColor(red: 0.150, green: 0.150, blue: 0.160, alpha: 1))
    static let qInk = Color(light: UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1),
                            dark: UIColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1))
    static let qMuted = Color(light: UIColor(red: 0.45, green: 0.44, blue: 0.42, alpha: 1),
                              dark: UIColor(red: 0.62, green: 0.61, blue: 0.59, alpha: 1))
    static let qHairline = Color(light: UIColor(white: 0, alpha: 0.08),
                                 dark: UIColor(white: 1, alpha: 0.10))
    static let qAccent = Color(light: UIColor(red: 0.78, green: 0.41, blue: 0.23, alpha: 1),
                               dark: UIColor(red: 0.93, green: 0.58, blue: 0.38, alpha: 1))
    static let qAccentSoft = Color(light: UIColor(red: 0.78, green: 0.41, blue: 0.23, alpha: 0.12),
                                   dark: UIColor(red: 0.93, green: 0.58, blue: 0.38, alpha: 0.16))

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension Font {
    /// Editorial serif for titles and quotes (New York).
    static func qSerif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static let qLargeTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let qTitle = Font.system(.title2, design: .serif, weight: .semibold)
    static let qQuote = Font.system(.title3, design: .serif)
}

enum Metrics {
    static let gutter: CGFloat = 20
    static let cornerRadius: CGFloat = 18
    static let smallCornerRadius: CGFloat = 12
    static let coverCornerRadius: CGFloat = 5
    static let coverAspect: CGFloat = 1.5
}

extension Animation {
    static let qSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let qQuick = Animation.easeOut(duration: 0.2)
}
