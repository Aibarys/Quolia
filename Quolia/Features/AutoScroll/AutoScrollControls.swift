import SwiftUI

/// Floating auto-scroll controls. They fade back while scrolling runs so the page stays calm.
struct AutoScrollControls: View {
    @Bindable var model: ReaderViewModel
    @Environment(AppSettings.self) private var settings
    @State private var showsSpeedPanel = false
    @State private var isDimmed = false

    var body: some View {
        VStack(spacing: 10) {
            if showsSpeedPanel {
                SpeedPanel(model: model)
                    .transition(.scale(scale: 0.95, anchor: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 2) {
                RoundIconButton(symbol: "minus", label: "Slower") { model.adjustSpeed(by: -ReadingSpeed.step) }
                RoundIconButton(symbol: model.isAutoScrollRunning ? "pause.fill" : "play.fill",
                                label: model.isAutoScrollRunning ? "Pause" : "Resume", prominent: true) {
                    model.toggleAutoScrollRunning()
                }
                RoundIconButton(symbol: "plus", label: "Faster") { model.adjustSpeed(by: ReadingSpeed.step) }
                Button {
                    withAnimation(.qSpring) { showsSpeedPanel.toggle() }
                    Haptics.selection()
                } label: {
                    VStack(spacing: 0) {
                        Text("\(Int(settings.autoScrollWPM))")
                            .font(.headline.monospacedDigit())
                            .contentTransition(.numericText())
                        Text("wpm").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(width: 56, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(Int(settings.autoScrollWPM)) words per minute")
                RoundIconButton(symbol: "xmark", label: "Stop Auto Scroll") {
                    withAnimation(.qSpring) { model.stopAutoScroll() }
                }
            }
            .padding(6)
            .floatingSurface(Capsule())
        }
        .opacity(isDimmed ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.6), value: isDimmed)
        .onTapGesture { isDimmed = false }
        .task(id: "\(model.isAutoScrollRunning)-\(showsSpeedPanel)-\(settings.autoScrollWPM)") {
            isDimmed = false
            guard model.isAutoScrollRunning, !showsSpeedPanel else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { isDimmed = true }
        }
    }
}

struct SpeedPanel: View {
    let model: ReaderViewModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reading speed").font(.subheadline.weight(.semibold))
                Spacer()
                Text(label(for: settings.autoScrollWPM)).font(.caption).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { settings.autoScrollWPM }, set: { model.setSpeed($0) }),
                   in: ReadingSpeed.wpmRange, step: 10) {
                Text("Words per minute")
            } minimumValueLabel: {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "hare").foregroundStyle(.secondary)
            }
            Text("≈ \(Int(settings.autoScrollWPM)) words per minute · your usual pace is \(Int(settings.measuredWPM))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: 360)
        .floatingSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .padding(.horizontal, 20)
    }

    private func label(for wpm: Double) -> String {
        switch wpm {
        case ..<160: String(localized: "Relaxed", comment: "Reading speed")
        case ..<260: String(localized: "Steady", comment: "Reading speed")
        case ..<380: String(localized: "Brisk", comment: "Reading speed")
        default: String(localized: "Skimming", comment: "Reading speed")
        }
    }
}

struct RoundIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 15, weight: .semibold))
                .foregroundStyle(prominent ? Color.qBackground : .primary)
                .frame(width: 44, height: 44)
                .background {
                    if prominent { Circle().fill(Color.qInk) }
                }
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Shown when auto scroll stops at the end of a chapter.
struct ChapterEndCard: View {
    let model: ReaderViewModel
    let theme: ReaderTheme

    private var nextTitle: String? { model.content?.chapter(model.chapterIndex + 1)?.title }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("End of chapter")
                    .font(.headline)
                if let nextTitle {
                    Text("Next: \(nextTitle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else {
                    Text("You've reached the end of the book.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button(model.isFlowActive ? "Finish" : "Stop") {
                    withAnimation(.qSpring) {
                        if model.isFlowActive { model.endFlow() } else { model.stopAutoScroll() }
                    }
                }
                .buttonStyle(.bordered)
                if nextTitle != nil {
                    Button("Continue") { model.continueToNextChapter() }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accentColor)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 340)
        .floatingSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

/// Minimal controls while listening with the interface hidden.
struct SpeechControls: View {
    let model: ReaderViewModel

    var body: some View {
        HStack(spacing: 2) {
            RoundIconButton(symbol: model.speech.isPaused ? "play.fill" : "pause.fill",
                            label: model.speech.isPaused ? "Resume" : "Pause", prominent: true) {
                model.speech.togglePause()
            }
            Menu {
                ForEach(SpeechController.rates, id: \.1) { name, rate in
                    Button(name) {
                        model.speech.rate = rate
                        model.speech.applyRate()
                    }
                }
            } label: {
                Text(SpeechController.rates.first { $0.1 == model.speech.rate }?.0 ?? "1×")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(width: 56, height: 44)
            }
            .accessibilityLabel("Speaking rate")
            RoundIconButton(symbol: "stop.fill", label: "Stop listening") { model.speech.stop() }
        }
        .padding(6)
        .floatingSurface(Capsule())
    }
}
