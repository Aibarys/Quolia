import UIKit

/// Subtle, purposeful haptics. Never used for decoration.
@MainActor
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func selection() { selectionGenerator.selectionChanged() }
    static func light() { lightGenerator.impactOccurred() }
    static func soft() { softGenerator.impactOccurred(intensity: 0.7) }
    static func success() { notificationGenerator.notificationOccurred(.success) }
    static func warning() { notificationGenerator.notificationOccurred(.warning) }
}
