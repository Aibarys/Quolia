import SwiftUI

/// The only interface during Reading Flow: pause, speed, exit.
struct FlowControls: View {
    @Bindable var model: ReaderViewModel
    @Environment(AppSettings.self) private var settings
    @State private var isDimmed = false

    var body: some View {
        HStack(spacing: 2) {
            RoundIconButton(symbol: model.isAutoScrollRunning ? "pause.fill" : "play.fill",
                            label: model.isAutoScrollRunning ? "Pause" : "Resume", prominent: true) {
                model.toggleAutoScrollRunning()
            }
            HStack(spacing: 0) {
                Button { model.adjustSpeed(by: -ReadingSpeed.step) } label: {
                    Image(systemName: "minus").frame(width: 34, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Slower")
                Text("\(Int(settings.autoScrollWPM))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 38)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(Int(settings.autoScrollWPM)) words per minute")
                Button { model.adjustSpeed(by: ReadingSpeed.step) } label: {
                    Image(systemName: "plus").frame(width: 34, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Faster")
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .semibold))
            Button {
                withAnimation(.qSpring) { model.endFlow() }
            } label: {
                Text("Exit")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit Reading Flow")
        }
        .padding(6)
        .floatingSurface(Capsule())
        .opacity(isDimmed ? 0.25 : 1)
        .animation(.easeInOut(duration: 0.8), value: isDimmed)
        .task(id: "\(model.isAutoScrollRunning)-\(settings.autoScrollWPM)") {
            isDimmed = false
            guard model.isAutoScrollRunning else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { isDimmed = true }
        }
    }
}

/// A quiet celebration after a Reading Flow.
struct FlowSummaryView: View {
    let summary: FlowSummary
    let bookTitle: String
    let onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                Image(systemName: "leaf")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.qAccent)
                    .symbolEffect(.bounce, value: appeared)
                Text("You read for \(summary.minutes) min")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                Text(bookTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                stat(value: summary.pages, label: "Pages read", symbol: "book.pages")
                stat(value: summary.chapters, label: "Chapters completed", symbol: "checkmark.circle")
                stat(value: summary.highlights, label: "Highlights", symbol: "highlighter")
                stat(value: summary.notes, label: "Notes", symbol: "note.text")
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            Spacer(minLength: 0)
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(Color.qBackground)
                    .background(Color.qInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(.qSpring.delay(0.15)) { appeared = true }
        }
    }

    /// A big number with a count-independent heading ("Pages read"), grammatical in every language.
    private func stat(value: Int, label: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Color.qAccent)
            Text("\(value)").font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.qSurfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
