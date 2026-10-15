import SwiftUI

/// "Aa" — typography, theme and layout. Changes apply live behind the sheet.
struct ReaderSettingsSheet: View {
    let model: ReaderViewModel
    @Environment(AppSettings.self) private var settings
    @State private var brightness: Double = Double(Self.currentScreen?.brightness ?? 0.5)

    private static var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                brightnessRow
                themeRow(settings: settings)

                if model.engine == .pdf {
                    pdfSection
                } else {
                    section("Text") {
                        fontSizeRow(settings: settings)
                        fontPicker(settings: settings)
                    }
                    section("Spacing") {
                        sliderRow(symbolLow: "text.line.first.and.arrowtriangle.forward", symbolHigh: "text.line.last.and.arrowtriangle.forward",
                                  label: "Line spacing", value: $settings.reader.lineSpacing, range: ReaderPreferences.lineSpacingRange, step: 0.05)
                        sliderRow(symbolLow: "rectangle.portrait", symbolHigh: "rectangle.portrait.inset.filled",
                                  label: "Margins", value: $settings.reader.margins, range: ReaderPreferences.marginRange, step: 2)
                        Picker("Text width", selection: $settings.reader.textWidth) {
                            ForEach(TextWidth.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Alignment", selection: $settings.reader.alignment) {
                            ForEach(TextAlignmentOption.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    section("Layout") {
                        Picker("Layout", selection: $settings.reader.layout) {
                            ForEach(ReaderLayout.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if settings.reader.layout == .paged {
                            Picker("Page turn", selection: $settings.reader.pageTurn) {
                                ForEach(PageTurnStyle.allCases) { Text($0.name).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                if model.book.format == .pdf && model.engine == .text {
                    Button {
                        model.setReflow(false)
                    } label: {
                        Label("Show original PDF layout", systemImage: "doc.richtext")
                    }
                }

                section("Focus") {
                    Picker("Focus", selection: Binding(get: { settings.reader.focusMode }, set: { model.setFocusMode($0) })) {
                        ForEach(FocusMode.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Keeps the current line or paragraph bright and gently dims the rest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                section("Other") {
                    Toggle("Hyphenation", isOn: $settings.reader.hyphenation)
                        .disabled(model.engine == .pdf)
                    Toggle("Show progress while reading", isOn: $settings.reader.showsProgressWhileReading)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
        .presentationDetents([.height(470), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(470)))
        .tint(.qAccent)
        .sensoryFeedback(.selection, trigger: settings.reader)
    }

    // MARK: - Rows

    private var brightnessRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: $brightness, in: 0...1) { Text("Brightness") }
                .onChange(of: brightness) { _, value in Self.currentScreen?.brightness = CGFloat(value) }
            Image(systemName: "sun.max").foregroundStyle(.secondary)
        }
    }

    private func themeRow(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ForEach(ReaderTheme.allCases) { theme in
                    Button {
                        settings.reader.theme = theme
                        settings.reader.matchesSystemAppearance = false
                    } label: {
                        VStack(spacing: 6) {
                            Text("Aa")
                                .font(.system(size: 19, weight: .medium, design: .serif))
                                .foregroundStyle(theme.textColor)
                                .frame(width: 58, height: 58)
                                .background(theme.backgroundColor, in: Circle())
                                .overlay {
                                    Circle().strokeBorder(settings.reader.theme == theme ? Color.qAccent : Color.primary.opacity(0.15),
                                                          lineWidth: settings.reader.theme == theme ? 2.5 : 1)
                                }
                            Text(theme.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(theme.name) theme")
                    .accessibilityAddTraits(settings.reader.theme == theme ? .isSelected : [])
                }
            }
            Toggle("Match system appearance", isOn: Binding(get: { settings.reader.matchesSystemAppearance },
                                                           set: { settings.reader.matchesSystemAppearance = $0 }))
                .font(.subheadline)
        }
    }

    private func fontSizeRow(settings: AppSettings) -> some View {
        HStack(spacing: 0) {
            Button {
                settings.reader.fontSize = max(settings.reader.fontSize - 1, ReaderPreferences.fontSizeRange.lowerBound)
            } label: {
                Image(systemName: "textformat.size.smaller").frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Smaller text")
            Divider().frame(height: 24)
            Text("\(Int(settings.reader.fontSize))")
                .font(.headline.monospacedDigit())
                .frame(width: 64)
                .contentTransition(.numericText())
            Divider().frame(height: 24)
            Button {
                settings.reader.fontSize = min(settings.reader.fontSize + 1, ReaderPreferences.fontSizeRange.upperBound)
            } label: {
                Image(systemName: "textformat.size.larger").frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Larger text")
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fontPicker(settings: AppSettings) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReaderFont.allCases) { font in
                    let selected = settings.reader.font == font
                    Button {
                        settings.reader.font = font
                    } label: {
                        Text(font.name)
                            .font(font.swiftUIFont(size: 16))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selected ? Color.qAccent.opacity(0.15) : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(selected ? Color.qAccent : .clear, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func sliderRow(symbolLow: String, symbolHigh: String, label: LocalizedStringKey, value: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbolLow).foregroundStyle(.secondary).frame(width: 22)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = (($0 / step).rounded() * step) }),
                   in: range) { Text(label) }
            Image(systemName: symbolHigh).foregroundStyle(.secondary).frame(width: 22)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var pdfSection: some View {
        section("PDF") {
            Picker("Layout", selection: Binding(get: { settings.reader.layout }, set: { settings.reader.layout = $0 })) {
                ForEach(ReaderLayout.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                model.setReflow(true)
            } label: {
                Label("Reflow as text", systemImage: "text.alignleft")
            }
            Text("Reflow turns the PDF into resizable text with all typography, focus and highlight features.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .textCase(.uppercase)
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
