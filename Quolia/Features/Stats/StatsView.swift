import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \ReadingSession.startedAt) private var sessions: [ReadingSession]
    @Query private var books: [Book]
    @State private var isGoalSheetPresented = false

    private var stats: ReadingStats {
        ReadingStats(sessions: sessions, books: books, goalMinutes: settings.dailyGoalMinutes)
    }

    var body: some View {
        let stats = stats
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayGoalCard(stats: stats) { isGoalSheetPresented = true }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(label: "Reading streak", value: String(localized: "\(stats.streak) days"), symbol: "flame")
                        StatTile(label: "Pages read", value: stats.totalPages.formatted(.number.notation(.compactName)), symbol: "book.pages")
                        StatTile(label: "Books finished", value: stats.booksFinished.formatted(), symbol: "checkmark.seal")
                        StatTile(label: "Total reading time", value: DurationFormat.short(stats.totalSeconds), symbol: "clock")
                    }
                    ThisWeekCard(stats: stats)
                    HeatmapCard(stats: stats)
                    Text("Your reading pace is about \(Int(settings.measuredWPM)) words per minute.")
                        .font(.footnote)
                        .foregroundStyle(Color.qMuted)
                        .padding(.top, 4)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.qBackground.ignoresSafeArea())
            .navigationTitle("Stats")
            .sheet(isPresented: $isGoalSheetPresented) { GoalSheet() }
        }
    }
}

// MARK: - Today

private struct TodayGoalCard: View {
    let stats: ReadingStats
    let onEditGoal: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                ProgressRing(progress: stats.goalProgress, lineWidth: 12)
                VStack(spacing: 0) {
                    Text("\(Int(stats.todayMinutes.rounded(.down)))")
                        .font(.system(size: 48, weight: .semibold))
                        .contentTransition(.numericText())
                    Text("min").font(.subheadline).foregroundStyle(Color.qMuted)
                }
            }
            .frame(width: 132, height: 132)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Minutes read today")
            .accessibilityValue("\(Int(stats.todayMinutes)) of \(stats.goalMinutes) minutes")

            VStack(alignment: .leading, spacing: 8) {
                Text("Today")
                    .font(.headline)
                if stats.goalReached {
                    Label("Daily goal reached", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk)
                        .labelStyle(GoalLabelStyle())
                } else {
                    Text("\(max(stats.goalMinutes - Int(stats.todayMinutes), 0)) min to your \(stats.goalMinutes)-minute goal")
                        .font(.subheadline)
                        .foregroundStyle(Color.qMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Change goal", action: onEditGoal)
                    .font(.subheadline.weight(.medium))
                    .tint(.qAccent)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .cardStyle(padding: 20)
    }
}

private struct GoalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color.qAccent)
            configuration.title
        }
    }
}

struct StatTile: View {
    let label: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(Color.qAccent)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.qInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.qMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - This week

private struct ThisWeekCard: View {
    let stats: ReadingStats
    @State private var selectedDate: Date?

    private var selectedDay: ReadingStats.Day? {
        guard let selectedDate else { return nil }
        return stats.thisWeek.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This week").font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.qMuted)
            }

            Chart {
                ForEach(stats.thisWeek) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Minutes", day.minutes),
                        width: .fixed(22)
                    )
                    .foregroundStyle(selectedDay == nil || selectedDay == day ? Color.qAccent : Color.qAccent.opacity(0.35))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 4))
                }
                if stats.goalMinutes > 0 {
                    RuleMark(y: .value("Goal", stats.goalMinutes))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.qMuted.opacity(0.5))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("Goal").font(.caption2).foregroundStyle(Color.qMuted)
                        }
                }
                if let selectedDay {
                    RuleMark(x: .value("Day", selectedDay.date, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 1) {
                                Text(DurationFormat.short(selectedDay.minutes * 60))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.qInk)
                                Text(selectedDay.date.formatted(.dateTime.weekday(.wide)))
                                    .font(.caption2)
                                    .foregroundStyle(Color.qMuted)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.qSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.qHairline) }
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .foregroundStyle(Color.qMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.qHairline)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text("\(Int(minutes))m") }
                    }
                    .foregroundStyle(Color.qMuted)
                }
            }
            .chartYScale(domain: 0...max(Double(stats.goalMinutes) * 1.2, (stats.thisWeek.map(\.minutes).max() ?? 0) * 1.15, 10))
            .frame(height: 170)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Minutes read each day this week")
            .accessibilityValue(stats.thisWeek.map { "\($0.date.formatted(.dateTime.weekday(.wide))) \(Int($0.minutes)) minutes" }.joined(separator: ", "))
        }
        .cardStyle(padding: 20)
    }

    private var summary: String {
        [
            String(localized: "\(DurationFormat.short(stats.weekSeconds)) read"),
            String(localized: "\(stats.weekPages) pages"),
            String(localized: "\(stats.weekActiveBooks) books active"),
        ].joined(separator: " · ")
    }
}

// MARK: - Heatmap

private struct HeatmapCard: View {
    let stats: ReadingStats
    @State private var selected: ReadingStats.Day?
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let cell: CGFloat = 15
    private let gap: CGFloat = 3

    private var weekCount: Int { sizeClass == .regular ? 30 : 17 }

    var body: some View {
        let weeks = stats.heatmap(weeks: weekCount)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading activity").font(.headline)
                Spacer()
                Text(selectedText)
                    .font(.caption)
                    .foregroundStyle(Color.qMuted)
                    .contentTransition(.opacity)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        weekdayLabels
                        ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { row in
                                    if let day = week[row] {
                                        cellView(day)
                                    } else {
                                        Color.clear.frame(width: cell, height: cell)
                                    }
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(weeks.count - 1, anchor: .trailing) }
            }

            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(Color.qMuted)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.caption2).foregroundStyle(Color.qMuted)
            }
            .accessibilityHidden(true)
        }
        .cardStyle(padding: 20)
    }

    private var weekdayLabels: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        return VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 0 ? symbols[(first + row) % 7] : "")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.qMuted)
                    .frame(width: 12, height: cell)
            }
        }
        .accessibilityHidden(true)
    }

    private func cellView(_ day: ReadingStats.Day) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        return RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(color(for: stats.level(for: day.minutes)))
            .frame(width: cell, height: cell)
            .overlay {
                if selected == day || isToday {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(Color.qInk.opacity(selected == day ? 0.8 : 0.35), lineWidth: 1.2)
                }
            }
            .contentShape(Rectangle().inset(by: -1.5))
            .onTapGesture {
                withAnimation(.qQuick) { selected = selected == day ? nil : day }
                Haptics.selection()
            }
            .accessibilityElement()
            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
            .accessibilityValue("\(Int(day.minutes)) minutes")
            .accessibilityAddTraits(.isButton)
    }

    /// One-hue sequential ramp: more reading, stronger terracotta.
    private func color(for level: Int) -> Color {
        switch level {
        case 0: Color.qSurfaceSecondary
        case 1: Color.qAccent.opacity(0.25)
        case 2: Color.qAccent.opacity(0.48)
        case 3: Color.qAccent.opacity(0.72)
        default: Color.qAccent
        }
    }

    private var selectedText: String {
        guard let selected else { return String(localized: "Tap a day") }
        return "\(selected.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(DurationFormat.short(selected.minutes * 60))"
    }
}
