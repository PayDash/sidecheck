import SwiftUI

/// The Screen Time app: today/week usage with an hour/day bar chart, a Most
/// Used list, and tracking settings. All data is local (ScreenTimeStore).
struct ScreenTimeAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var screenTime: ScreenTimeStore

    private enum Range: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        var id: String { rawValue }
    }

    private enum ChartMode {
        case dayBars([DayPoint])
        case hourBars([Double])
    }

    @State private var range: Range = .today
    @State private var selectedHour: Int?
    @State private var selectedDayKey: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if !screenTime.trackingEnabled {
                    pausedNote
                }

                pills

                headerCard
                chartCard

                sectionLabel("MOST USED")
                mostUsedCard

                sectionLabel("TRACKING")
                settingsCard
            }
            .padding(16)
        }
        .onChange(of: selectedDayKey) { _, key in
            // Icons resolve outside view bodies; warm the newly selected day.
            if let key {
                screenTime.warmIcons(for: screenTime.apps(onDay: key).map(\.key))
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.textTertiary)
    }

    // MARK: Range pills

    private var pills: some View {
        HStack(spacing: 8) {
            ForEach(Range.allCases) { candidate in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        range = candidate
                        selectedHour = nil
                        selectedDayKey = nil
                    }
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(range == candidate ? theme.accent : theme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(theme.accent.opacity(range == candidate ? 0.16 : 0), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                range == candidate ? theme.accent.opacity(0.55) : theme.cardStroke,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Header

    private var headerCard: some View {
        ThemedCard {
            HStack(spacing: 14) {
                Image(systemName: "hourglass")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 46, height: 46)
                    .background(
                        theme.accent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                    )
                    .themeGlow(theme)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.duration(displayedTotal))
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .themeGlow(theme)
                    Text(headerCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                    if let note = liveNote {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
    }

    private var displayedTotal: Double {
        switch range {
        case .today:
            return screenTime.snapshot.todayTotal
        case .week:
            guard let key = selectedDayKey else { return screenTime.snapshot.weekTotal }
            return screenTime.total(onDay: key)
        }
    }

    private var headerCaption: String {
        switch range {
        case .today:
            return "Today · " + Self.monthDay(Date())
        case .week:
            if let key = selectedDayKey { return Self.dayCaption(key) }
            let points = screenTime.snapshot.week
            if let first = points.first, let last = points.last,
               let start = Self.dayFormatter.date(from: first.dayKey),
               let end = Self.dayFormatter.date(from: last.dayKey) {
                return Self.monthDay(start) + " – " + Self.monthDay(end)
            }
            return "This week"
        }
    }

    /// Live line under the total: what's counted right now, or why not.
    private var liveNote: String? {
        if let nowApp = screenTime.snapshot.nowApp {
            return "Now · \(nowApp)"
        }
        return screenTime.snapshot.pauseNote
    }

    // MARK: Chart

    private var chartCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "chart.bar.fill", title: chartTitle)
                    if let caption = selectionCaption {
                        Text(caption)
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    if range == .week, selectedDayKey != nil {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedDayKey = nil
                                selectedHour = nil
                            }
                        } label: {
                            Label("Whole week", systemImage: "chevron.left")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                chart
            }
        }
    }

    private var chartMode: ChartMode {
        if range == .today { return .hourBars(screenTime.snapshot.todayHourly) }
        if let key = selectedDayKey { return .hourBars(screenTime.hourly(onDay: key)) }
        return .dayBars(screenTime.snapshot.week)
    }

    private var chartTitle: String {
        switch chartMode {
        case .dayBars:
            return "This week by day"
        case .hourBars:
            if range == .week, let key = selectedDayKey {
                return Self.dayCaption(key) + " by hour"
            }
            return "Today by hour"
        }
    }

    private var selectionCaption: String? {
        guard let hour = selectedHour else { return nil }
        switch chartMode {
        case .dayBars:
            return nil
        case .hourBars(let values):
            guard hour < values.count else { return nil }
            return Self.hourLabel(hour) + " · " + Format.duration(values[hour])
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch chartMode {
        case .dayBars(let points):
            BarChart(values: points.map(\.total), labels: points.map { Self.weekdayLabel($0.dayKey) }) { index in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    selectedDayKey = points[index].dayKey
                    selectedHour = nil
                }
            }
        case .hourBars(let values):
            BarChart(values: values, labels: Self.hourlyLabels, selectedIndex: selectedHour) { index in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    selectedHour = selectedHour == index ? nil : index
                }
            }
        }
    }

    // MARK: Most Used

    private var mostUsedCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 11) {
                CardTitle(icon: "list.bullet", title: "Most Used")
                let entries = displayedApps
                if entries.isEmpty {
                    Text("Nothing recorded yet — use some apps and check back.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    let top = entries.first?.usage.seconds ?? 0
                    ForEach(entries.prefix(8)) { entry in
                        appRow(entry, maxSeconds: top)
                    }
                    if entries.count > 8 {
                        Text("+ \(entries.count - 8) more")
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }

    /// Entries for the current scope; when an hour bar is tapped, narrowed to
    /// that hour's slice of each app.
    private var displayedApps: [AppUsageEntry] {
        let base: [AppUsageEntry]
        switch range {
        case .today:
            base = screenTime.snapshot.todayApps
        case .week:
            if let key = selectedDayKey {
                base = screenTime.apps(onDay: key)
            } else {
                base = screenTime.snapshot.weekApps
            }
        }
        guard let hour = selectedHour, hour < 24 else { return base }
        return base
            .compactMap { entry -> AppUsageEntry? in
                let seconds = hour < entry.usage.hourly.count ? entry.usage.hourly[hour] : 0
                guard seconds > 0 else { return nil }
                var usage = entry.usage
                usage.seconds = seconds
                return AppUsageEntry(key: entry.key, usage: usage)
            }
            .sorted { $0.usage.seconds > $1.usage.seconds }
    }

    private func appRow(_ entry: AppUsageEntry, maxSeconds: Double) -> some View {
        HStack(spacing: 10) {
            iconView(entry.key)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.usage.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(Format.duration(entry.usage.seconds))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                MeterBar(
                    progress: maxSeconds > 0 ? entry.usage.seconds / maxSeconds : 0,
                    colors: [Self.tint(for: entry.key)]
                )
            }
        }
    }

    @ViewBuilder
    private func iconView(_ key: String) -> some View {
        if let image = screenTime.cachedIcon(for: key) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 15))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Tracking settings

    private var settingsCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track app activity")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.textPrimary)
                        Text("Counts the frontmost app while you're active")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    ThemeSwitch(isOn: $screenTime.trackingEnabled)
                }

                Divider().overlay(theme.divider)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Pause clock after idle")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text("\(screenTime.idleMinutes) min")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    PanelSlider(value: idleMinutesBinding, range: 1...15, step: 1)
                    Text("No keyboard or mouse input for this long stops the clock.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                }

                Text("Everything stays on this Mac — nothing is uploaded.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var idleMinutesBinding: Binding<Double> {
        Binding(
            get: { Double(screenTime.idleMinutes) },
            set: { screenTime.idleMinutes = Int($0.rounded()) }
        )
    }

    private var pausedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Tracking is off — nothing is being recorded.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Formatting helpers

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let dayCaptionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    /// "Wed, Nov 5" caption for a "yyyy-MM-dd" key.
    private static func dayCaption(_ dayKey: String) -> String {
        guard let date = dayFormatter.date(from: dayKey) else { return dayKey }
        return dayCaptionFormatter.string(from: date)
    }

    private static func weekdayLabel(_ dayKey: String) -> String? {
        guard let date = dayFormatter.date(from: dayKey) else { return nil }
        let weekday = Calendar.current.component(.weekday, from: date)
        return Calendar.current.veryShortWeekdaySymbols[weekday - 1]
    }

    private static func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }

    /// Sparse x labels: 12a / 6a / 12p / 6p.
    private static let hourlyLabels: [String?] = (0..<24).map { hour in
        [0, 6, 12, 18].contains(hour) ? hourLabel(hour) : nil
    }

    /// Stable muted color per app, hashed from its key.
    static func tint(for key: String) -> Color {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        let hue = Double(hash % 1000) / 1000
        return Color(hue: hue, saturation: 0.42, brightness: 0.78)
    }
}

// MARK: - Bar chart

/// Theme-aware Canvas bar chart (no Swift Charts — matches the Sparkline/
/// MeterBar approach). Bars are rounded capsules with an accent gradient;
/// tapping selects the bar under the pointer.
private struct BarChart: View {
    @Environment(\.theme) private var theme
    let values: [Double]
    /// One optional x-axis label per bar (nil = skip).
    let labels: [String?]
    var selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            // Floor the scale so near-empty data still renders a baseline.
            let maxValue = max((values.max() ?? 0) * 1.08, 60)
            Canvas { context, size in
                let labelSpace: CGFloat = labels.contains { $0 != nil } ? 13 : 0
                let chartHeight = size.height - labelSpace

                for fraction in [0.25, 0.5, 0.75] {
                    let y = chartHeight * CGFloat(fraction)
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(theme.divider.opacity(0.6)), lineWidth: 1)
                }

                let count = values.count
                guard count > 0 else { return }
                let slot = size.width / CGFloat(count)
                let barWidth = min(slot * 0.6, 14)
                for (index, value) in values.enumerated() {
                    let height = chartHeight * CGFloat(min(value / maxValue, 1))
                    guard height > 1.5 else { continue }
                    let x = CGFloat(index) * slot + (slot - barWidth) / 2
                    let rect = CGRect(x: x, y: chartHeight - height, width: barWidth, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous)
                    let isSelected = selectedIndex == index
                    let dimmed = selectedIndex != nil && !isSelected
                    let base = dimmed ? theme.accent.opacity(0.25) : theme.accent
                    let top = isSelected ? theme.accent2 : base.opacity(0.95)
                    context.fill(path, with: .linearGradient(
                        Gradient(colors: [top, base.opacity(0.5)]),
                        startPoint: CGPoint(x: 0, y: chartHeight - height),
                        endPoint: CGPoint(x: 0, y: chartHeight)
                    ))
                }

                if labelSpace > 0 {
                    for (index, label) in labels.enumerated() {
                        guard let label else { continue }
                        let x = CGFloat(index) * slot + slot / 2
                        context.draw(
                            Text(label)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(theme.textTertiary),
                            at: CGPoint(x: x, y: chartHeight + labelSpace / 2 + 1)
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard !values.isEmpty, geo.size.width > 0 else { return }
                let slot = geo.size.width / CGFloat(values.count)
                let index = min(max(Int(location.x / slot), 0), values.count - 1)
                onSelect(index)
            }
        }
        .frame(height: 118)
    }
}
