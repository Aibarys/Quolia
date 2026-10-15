import SwiftUI

/// A gentle daily intention — not a game.
struct GoalSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var isCustom = false
    @State private var custom = 45

    private let presets = [10, 20, 30]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text("How long would you like to read each day?")
                    .font(.qSerif(.title3, weight: .semibold))
                VStack(spacing: 10) {
                    ForEach(presets, id: \.self) { minutes in
                        option(title: "\(minutes) minutes", subtitle: subtitle(for: minutes),
                               selected: !isCustom && settings.dailyGoalMinutes == minutes) {
                            isCustom = false
                            settings.dailyGoalMinutes = minutes
                            Haptics.selection()
                        }
                    }
                    option(title: "Custom", subtitle: isCustom ? "\(custom) minutes a day" : "Choose your own rhythm", selected: isCustom) {
                        isCustom = true
                        settings.dailyGoalMinutes = custom
                        Haptics.selection()
                    }
                    if isCustom {
                        Stepper("\(custom) minutes", value: $custom, in: 5...240, step: 5)
                            .onChange(of: custom) { _, value in settings.dailyGoalMinutes = value }
                            .padding(.horizontal, 4)
                    }
                }
                Text("Quolia shows a quiet ring for today. Missing a day is fine — reading is not a race.")
                    .font(.footnote)
                    .foregroundStyle(Color.qMuted)
                Spacer()
            }
            .padding(24)
            .navigationTitle("Daily Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if !presets.contains(settings.dailyGoalMinutes) {
                    isCustom = true
                    custom = settings.dailyGoalMinutes
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func subtitle(for minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 10: "A few pages with your coffee"
        case 20: "A chapter a day"
        default: "A deeper daily habit"
        }
    }

    private func option(title: LocalizedStringKey, subtitle: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.qInk)
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.qMuted)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.qAccent : Color.qHairline)
            }
            .cardStyle(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
