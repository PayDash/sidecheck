import SwiftUI

// MARK: - App icon tile (home grid + dock)

struct AppIconTile: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: PanelApp
    var size: CGFloat = 56
    var showsLabel = true

    @State private var hovered = false

    /// Monochrome themes (Noir): white-on-dark tiles — color is reserved for
    /// status, so the grid stays black & white.
    private var tileFill: LinearGradient {
        if theme.monochromeTiles {
            return LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [app.tint.opacity(0.9), app.tint.opacity(0.55)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var tileShadow: Color {
        theme.monochromeTiles
            ? Color.white.opacity(0.35)
            : app.tint.opacity(theme.isLight ? 0.35 : 0.45)
    }

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: size * theme.iconCornerRadiusRatio, style: .continuous)
                .fill(tileFill)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: app.symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .top) {
                    // top gloss, iOS-icon style
                    RoundedRectangle(cornerRadius: size * theme.iconCornerRadiusRatio, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(height: size * 0.45)
                        .allowsHitTesting(false)
                }
                .shadow(
                    color: tileShadow,
                    radius: hovered ? 8 : 5,
                    y: hovered ? 4 : 3
                )
                .scaleEffect(hovered ? 1.04 : 1)

            if showsLabel {
                Text(app.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.iconLabelIsWhite ? Color.white : theme.textPrimary)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(theme.iconLabelIsWhite ? 0.45 : 0.0), radius: 2, y: 1)
            }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : PanelMotion.hover, value: hovered)
    }
}

// MARK: - Home widget slot

/// One assignable home-screen widget slot: shows the bound app's compact
/// widget; in edit mode it becomes a picker with a remove badge.
struct WidgetSlot: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var home: HomeStore
    let index: Int
    let onOpen: (AppID) -> Void
    /// True when this is the single full-width slot — wide widget variants.
    var wide = false
    /// Hero sizing from HomeScreen: the slot's minimum height and the scale
    /// its widget's visuals render at (bigger slot → bigger widget).
    var heroHeight: CGFloat = 120
    var heroScale: CGFloat = 1

    private var kind: WidgetKind? {
        home.widgetSlots.indices.contains(index) ? home.widgetSlots[index] : nil
    }

    var body: some View {
        Group {
            if home.isEditMode {
                // The card is a plain view (not a Menu label) so the full
                // widget content renders — rebinding lives in the badge row's
                // menu button. macOS Menu labels won't render a tall card.
                slotChrome(kind: kind)
                    .overlay(alignment: .topTrailing) { removeBadge }
            } else if let kind {
                Button {
                    // A completed long press has already flipped edit mode on —
                    // don't also open the app when the finger lifts.
                    guard !home.isEditMode else { return }
                    onOpen(kind.app)
                } label: {
                    slotChrome(kind: kind)
                }
                .buttonStyle(.pressable)
                // Simultaneous, not chained: the long press completes at 0.45 s
                // even while the tap gesture owns the touch, so holding still
                // enters edit mode instead of opening the app on release.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            withAnimation(.snappy) { home.isEditMode = true }
                        }
                )
            } else {
                pickerMenu { emptyChrome }
            }
        }
    }

    // MARK: chrome

    @ViewBuilder
    private func slotChrome(kind: WidgetKind?) -> some View {
        // Stretch to the row height — the row sizes to the tallest sibling,
        // so every card in a multi-slot row matches. Cards are hero-sized: a
        // minimum height keeps one-line widgets (Performance, Settings)
        // substantial, and their content centers vertically so a card never
        // looks half-empty. Edit mode pins content to the top below the
        // badge rows.
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                // Widgets render pure content — the badge + name row exists
                // only in edit mode, where it identifies the slot, carries the
                // move chevrons and the rebind menu button.
                if home.isEditMode {
                    // Two rows: badge + name on one line, controls on the
                    // next — a half-width slot can't fit all four in one row.
                    HStack(spacing: 8) {
                        WidgetBadge(kind: kind ?? .monitor)
                        Text(kind?.name ?? "Widget")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        bindMenu
                        Spacer()
                        moveButton(direction: -1, enabled: index > 0)
                        moveButton(direction: 1, enabled: index < home.effectiveSlots.count - 1)
                    }
                }
                if let kind {
                    if wide {
                        kind.wideWidget
                            .environment(\.widgetScale, max(heroScale, 1.1))
                    } else {
                        kind.homeWidget
                            .environment(\.widgetScale, heroScale)
                    }
                }
            }
            // Flexible content — without this the card's visual only paints
            // the natural content height, centered inside the stretched slot.
            .frame(maxHeight: .infinity, alignment: home.isEditMode ? .top : .center)
        }
        .frame(minHeight: home.isEditMode ? 0 : heroHeight)
        .frame(maxHeight: .infinity)
    }

    private func moveButton(direction: Int, enabled: Bool) -> some View {
        Button {
            home.move(slot: index, direction: direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary.opacity(0.35))
                .padding(4)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .help(direction < 0 ? "Move left" : "Move right")
    }

    private var emptyChrome: some View {
        RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
            .strokeBorder(theme.cardStroke, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            .frame(minHeight: 96, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text("Add Widget")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
            }
    }

    private var removeBadge: some View {
        Button {
            home.assign(slot: index, kind: nil)
        } label: {
            Image(systemName: "minus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.pressable)
        .offset(x: 7, y: -7)
        .help("Remove widget")
    }

    /// The rebind menu button in the edit-mode badge row — a small, fixed-size
    /// label (same affordance as Settings' slot menu). Small labels render
    /// fine; the tall card-as-label variant was what macOS clipped to a row.
    private var bindMenu: some View {
        Menu {
            Section("Bind widget") {
                ForEach(WidgetKind.allCases) { kind in
                    Button {
                        home.assign(slot: index, kind: kind)
                    } label: {
                        Label(kind.name, systemImage: kind.symbol)
                    }
                }
                Divider()
                Button("None") {
                    home.assign(slot: index, kind: nil)
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(5)
                .background(Capsule().fill(theme.cardFill))
                .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Rebind this slot")
    }

    private func pickerMenu<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        Menu {
            Section("Bind widget") {
                ForEach(WidgetKind.allCases) { kind in
                    Button {
                        home.assign(slot: index, kind: kind)
                    } label: {
                        Label(kind.name, systemImage: kind.symbol)
                    }
                }
                Divider()
                Button("None") {
                    home.assign(slot: index, kind: nil)
                }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

/// Tiny rounded glyph badge used in widget title rows.
struct WidgetBadge: View {
    @Environment(\.theme) private var theme
    let kind: WidgetKind

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(kind.tint)
            .frame(width: 18, height: 18)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Compact home widgets

struct MonitorHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        if theme.typographicWidgets {
            noirContent
        } else {
            monitorContent
        }
    }

    /// Noir: pure typography — CPU as the hero value, memory and temperature
    /// as one caption line. No ring, no graph.
    private var noirContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CPU")
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            Text("\(Int(stats.cpuUsage.rounded()))%")
                .font(.system(size: 30, weight: .regular, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .themeGlow(theme)
            statsLine
                .font(.system(size: 10.5, design: theme.fontDesign))
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var monitorContent: some View {
        // Ring + CPU row on top, sparkline, then a full-width stats caption —
        // a half-width card can't fit "MEM 61% · 4.2 GB · 63°C" beside the
        // ring, which is where the truncation came from.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                RingGauge(progress: stats.cpuUsage / 100, lineWidth: 6) { EmptyView() }
                    .frame(width: 44 * widgetScale, height: 44 * widgetScale)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                        Spacer()
                        Text("\(Int(stats.cpuUsage.rounded()))%")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                    MeterBar(progress: stats.memoryUsage / 100)
                }
            }
            Sparkline(values: stats.cpuHistory, height: 22 * widgetScale)
            Text(statsLineString)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var statsLineString: String {
        var parts = ["MEM \(Int(stats.memoryUsage.rounded()))%", Format.bytes(stats.usedMemoryBytes)]
        if let temp = stats.cpuTempC {
            parts.append(String(format: "%.0f°C", temp))
        }
        return parts.joined(separator: " · ")
    }

    /// Temperature wears the traffic lights — yellow warm, red throttling.
    private var statsLine: Text {
        let mem = "MEM \(Int(stats.memoryUsage.rounded()))% · \(Format.bytes(stats.usedMemoryBytes))"
        guard let temp = stats.cpuTempC else { return Text(mem) }
        let tempText: Text
        if temp >= 85 {
            tempText = Text(String(format: "%.0f°C", temp))
                .foregroundColor(.red)
        } else if temp >= 60 {
            tempText = Text(String(format: "%.0f°C", temp))
                .foregroundColor(.yellow)
        } else {
            tempText = Text(String(format: "%.0f°C", temp))
        }
        return Text(mem + " · ") + tempText
    }
}

struct BatteryHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var performance: PerformanceStore

    var body: some View {
        if let percent = stats.batteryPercent {
            if theme.typographicWidgets {
                noirContent(percent)
            } else {
                classicContent(percent)
            }
        } else {
            Text("No battery detected")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// Traffic-light semantics: green while charging, red below 20%, white otherwise.
    private func levelColor(_ percent: Int) -> Color {
        if stats.isCharging { return .green }
        if percent <= 20 { return .red }
        return theme.textPrimary
    }

    /// Noir: typographic — the percentage is the card, no ring.
    private func noirContent(_ percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(percent)")
                    .font(.system(size: 30, weight: .regular, design: theme.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(levelColor(percent))
                    .themeGlow(theme)
                    .contentTransition(.numericText())
                Text("%")
                    .font(.system(size: 14, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
            MeterBar(progress: Double(percent) / 100, colors: [levelColor(percent)])
            HStack(spacing: 5) {
                if stats.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                        .repeatingPulse(performance.isOn(.microAnimations))
                }
                Text(stats.isCharging ? "Charging" : "On battery")
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func classicContent(_ percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RingGauge(progress: Double(percent) / 100, lineWidth: 6) {
                    Text("\(percent)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                .frame(width: 44 * widgetScale, height: 44 * widgetScale)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if stats.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                                .repeatingPulse(performance.isOn(.microAnimations))
                        }
                        Text(stats.isCharging ? "Charging" : "On battery")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text("from macOS")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
            }
        }
    }
}

/// Noir's stacked home renders battery full-width — one long status line.
struct BatteryWideWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var performance: PerformanceStore

    var body: some View {
        if let percent = stats.batteryPercent {
            HStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(percent)")
                        .font(.system(size: 30, weight: .regular, design: theme.fontDesign))
                        .monospacedDigit()
                        .foregroundStyle(
                            stats.isCharging ? Color.green : (percent <= 20 ? Color.red : theme.textPrimary)
                        )
                        .themeGlow(theme)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 14, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
                MeterBar(progress: Double(percent) / 100,
                         colors: [stats.isCharging ? .green : (percent <= 20 ? .red : theme.accent)])
                HStack(spacing: 5) {
                    if stats.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                            .repeatingPulse(performance.isOn(.microAnimations))
                    }
                    Text(stats.isCharging ? "Charging" : "On battery")
                        .font(.system(size: 12, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        } else {
            Text("No battery detected")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

struct NetworkHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(Format.rate(stats.netDownBps))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
                Text(Format.rate(stats.netUpBps))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Sparkline(values: stats.netDownHistory, color: .blue, height: 20 * widgetScale)
            Sparkline(values: stats.netUpHistory, color: .purple, height: 20 * widgetScale)
        }
    }
}

struct AwakeHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var awake: AwakeStore
    @EnvironmentObject var performance: PerformanceStore

    var body: some View {
        // Ticking timer only while a session runs — same reasoning as the
        // Awake page: an idle-state TimelineView re-rendered every second and
        // re-armed the display-rate layout loop through panel transitions.
        // Saver mode keeps it static too.
        Group {
            if awake.isActive && performance.isOn(.liveTickers) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    awakeContent(context.date)
                }
            } else {
                awakeContent(Date())
            }
        }
    }

    private func awakeContent(_ contextDate: Date) -> some View {
        HStack(spacing: 12) {
            if awake.isActive {
                let remaining = awake.endDate.map { max(0, $0.timeIntervalSince(contextDate)) }
                RingGauge(progress: ringProgress(remaining: remaining, now: contextDate), lineWidth: 6) {
                    Group {
                        if let remaining {
                            Text(Format.clock(remaining))
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                        } else {
                            Image(systemName: "infinity")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .themeGlow(theme)
                        }
                    }
                }
                .frame(width: 42 * widgetScale, height: 42 * widgetScale)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awake")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(endLabel)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            } else {
                Image(systemName: "cup.and.saucer")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                Text("Mac sleeps normally")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }
        }
    }

    private func ringProgress(remaining: TimeInterval?, now: Date) -> Double {
        guard let remaining else { return 1 }
        guard awake.endDate != nil, let total = awake.sessionDuration, total > 0 else { return 1 }
        _ = now
        return remaining / total
    }

    private var endLabel: String {
        if let endDate = awake.endDate {
            return "until " + endDate.formatted(date: .omitted, time: .shortened)
        }
        return "until stopped"
    }
}

struct ScreenTimeHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var screenTime: ScreenTimeStore

    var body: some View {
        // Reads only the published snapshot (refreshed ≤1/min + on app
        // switches) — no timers; a per-second-changing text in a home slot
        // re-arms the AppKit layout storm.
        if !screenTime.trackingEnabled {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                Text("Screen Time off")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }
        } else if theme.typographicWidgets {
            noirContent
        } else {
            classicContent
        }
    }

    /// Noir: today's total + the top 3 apps with their times.
    private var noirContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .tracking(1.4)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Text(Format.duration(screenTime.snapshot.todayTotal))
                    .font(.system(size: 19, weight: .regular, design: theme.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .themeGlow(theme)
            }
            ForEach(topApps) { app in
                HStack {
                    Text(app.usage.name)
                        .font(.system(size: 11, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(Format.duration(app.usage.seconds))
                        .font(.system(size: 10.5, design: theme.fontDesign))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private var topApps: [AppUsageEntry] {
        Array(screenTime.snapshot.todayApps.prefix(3))
    }

    private var classicContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34 * widgetScale, height: 34 * widgetScale)
                .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.duration(screenTime.snapshot.todayTotal))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(topAppLine)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
        }
    }

    private var topAppLine: String {
        if let top = screenTime.snapshot.todayApps.first {
            return "Top · \(top.usage.name)"
        }
        return "No activity yet"
    }
}

struct ClipboardHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var clipboard: ClipboardStore

    var body: some View {
        if let latest = clipboard.items.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: latest.text.lowercased().hasPrefix("http") ? "link" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .padding(.top, 2)
                    Text(latest.text)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text("\(clipboard.items.count) in history · \(Text(latest.date, format: .relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
        } else {
            Text("Copies land here automatically")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

// MARK: - Top processes

struct TopProcessesHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var processes: ProcessStore

    var body: some View {
        // Updates at the store's 2 s cadence while the panel is visible only
        // — the same accepted cost class as MonitorHomeWidget.
        if let top = processes.processes.first {
            VStack(alignment: .leading, spacing: 6) {
                row(top, primary: true)
                if let second = processes.processes.dropFirst().first {
                    row(second, primary: false)
                }
            }
        } else {
            Text("Sampling processes…")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func row(_ sample: ProcessSample, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(sample.name)
                .font(.system(size: primary ? 11 : 10, weight: primary ? .semibold : .regular))
                .foregroundStyle(primary ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(value(sample))
                .font(.system(size: primary ? 11 : 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(primary ? theme.textPrimary : theme.textTertiary)
        }
    }

    private func value(_ sample: ProcessSample) -> String {
        switch processes.metric {
        case .cpu: String(format: "%.0f%%", sample.cpuPercent)
        case .memory: Format.bytes(sample.memBytes)
        }
    }
}

// MARK: - Music

struct MusicHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var music: MusicStore

    var body: some View {
        if let track = music.track {
            // Artwork on top, text below at full card width — hero-card
            // layout; titles get room instead of fighting the artwork.
            VStack(alignment: .leading, spacing: 8) {
                artworkThumb
                    .frame(width: 44 * widgetScale, height: 44 * widgetScale)
                Text(track.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                Text("Nothing playing")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var artworkThumb: some View {
        if let image = music.artwork {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.cardFill)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        }
    }
}


/// Four glowing bars bouncing out of phase — reads as "this is playing"
/// at a glance. Flat and dimmed when paused. Heights are computed straight
/// from the timeline clock (no implicit animations to interrupt), and the
/// timeline pauses itself when music stops, motion is reduced, or
/// micro-animations are off.
struct MusicVisualizer: View {
    let playing: Bool
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var performance: PerformanceStore

    private let tall: [CGFloat] = [22, 12, 19, 9, 16]
    private let base: [CGFloat] = [6, 10, 5, 12, 8]
    private let phases: [Double] = [0, 1.3, 2.6, 3.9, 5.2]

    var body: some View {
        let animates = playing && performance.isOn(.microAnimations) && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !animates)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<tall.count, id: \.self) { index in
                    Capsule()
                        .fill(playing ? theme.textPrimary : theme.textTertiary.opacity(0.6))
                        .frame(width: 3.5, height: barHeight(index, t: t, animate: animates))
                        .themeGlow(theme)
                }
            }
            .frame(height: 24)
        }
    }

    private func barHeight(_ index: Int, t: Double, animate: Bool) -> CGFloat {
        let lo = base[index] * 0.8
        let hi = tall[index]
        guard animate else { return lo }
        let wave = 0.5 + 0.5 * sin(t * (2.6 + Double(index) * 0.55) + phases[index])
        return lo + (hi - lo) * wave
    }
}

// MARK: - Wide variants (single full-width slot)

struct MonitorWideWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        HStack(spacing: 14) {
            RingGauge(progress: stats.cpuUsage / 100, lineWidth: 6) { EmptyView() }
                .frame(width: 42 * widgetScale, height: 42 * widgetScale)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CPU").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                    Spacer()
                    Text("\(Int(stats.cpuUsage.rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                }
                MeterBar(progress: stats.memoryUsage / 100)
                Text("MEM \(Int(stats.memoryUsage.rounded()))% · \(Format.bytes(stats.usedMemoryBytes))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
            Divider().overlay(theme.divider).frame(height: 36)
            VStack(alignment: .leading, spacing: 4) {
                rateRow("arrow.down", color: .blue, value: stats.netDownBps)
                rateRow("arrow.up", color: .purple, value: stats.netUpBps)
                if let temp = stats.cpuTempC {
                    Text(String(format: "%.0f°C", temp))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Sparkline(values: stats.cpuHistory, height: 30 * widgetScale)
                .frame(width: 88)
        }
    }

    private func rateRow(_ symbol: String, color: Color, value: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(Format.rate(value))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
        }
    }
}

struct ScreenTimeWideWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var screenTime: ScreenTimeStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34 * widgetScale, height: 34 * widgetScale)
                .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.duration(screenTime.snapshot.todayTotal))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(topAppLine)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            MiniBars(values: screenTime.snapshot.todayHourly)
                .frame(width: 150, height: 34)
        }
    }

    private var topAppLine: String {
        if let top = screenTime.snapshot.todayApps.first {
            return "Top · \(top.usage.name)"
        }
        return "No activity yet"
    }
}

/// Tiny bar chart for the wide Screen Time widget — 24 silent hour bars.
struct MiniBars: View {
    @Environment(\.theme) private var theme
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            let count = values.count
            guard count > 0 else { return }
            let maxValue = max((values.max() ?? 0) * 1.05, 1)
            let slot = size.width / CGFloat(count)
            let barWidth = min(slot * 0.62, 5)
            for (index, value) in values.enumerated() {
                let height = size.height * CGFloat(min(value / maxValue, 1))
                guard height > 0.8 else { continue }
                let x = CGFloat(index) * slot + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous),
                    with: .linearGradient(
                        Gradient(colors: [theme.accent2, theme.accent.opacity(0.55)]),
                        startPoint: CGPoint(x: 0, y: size.height - height),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
    }
}

struct MusicWideWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var music: MusicStore

    var body: some View {
        if let track = music.track {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    artworkThumb
                        .frame(width: 46 * widgetScale, height: 46 * widgetScale)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    // Live equalizer — bars dance while playing, sit flat when
                    // paused. Replaces the old play/pause badge (it was a
                    // decoration, not a control).
                    MusicVisualizer(playing: music.isPlaying)
                }
                if track.duration > 0 {
                    // Short glide on each store publish — a continuous tween in a
                    // slot would run display-rate layout (the layout-storm rule).
                    MeterBar(progress: min(max(music.positionNow() / track.duration, 0), 1),
                             animation: .easeOut(duration: 0.5))
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                Text("Nothing playing")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var artworkThumb: some View {
        if let image = music.artwork {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.cardFill)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                )
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        }
    }
}

struct PerformanceHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var performance: PerformanceStore
    @EnvironmentObject var wallpaper: WallpaperStore
    @EnvironmentObject var themes: ThemeStore

    var body: some View {
        if theme.typographicWidgets {
            noirContent
        } else {
            classicContent
        }
    }

    private var currentKind: BackgroundKind {
        wallpaper.spec(for: themes.current).kind
    }

    /// Noir: mode + effect + the impact estimate below, so the card answers
    /// "what does this mode cost me" without opening the app.
    private var noirContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Performance")
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(performance.mode.label)
                    .font(.system(size: 15, weight: .regular, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .themeGlow(theme)
                Text(performance.mode.effectCaption)
                    .font(.system(size: 10.5, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
            Text(impact)
                .font(.system(size: 10.5, design: theme.fontDesign))
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var impact: String {
        let cpu = PerformanceStore.estimate(features: performance.activeFeatures, kind: currentKind)
        let value = cpu >= 1 ? "~\(Int(cpu))%" : String(format: "~%.1f%%", cpu)
        return "\(value) CPU while open"
    }

    private var classicContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34 * widgetScale, height: 34 * widgetScale)
                .background(Circle().fill(performance.mode.tint))
                .themeGlow(theme)
            VStack(alignment: .leading, spacing: 3) {
                Text(performance.mode.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(performance.mode.effectCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

// MARK: - Tokens

struct TokenHomeWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var tokscale: TokscaleStore

    var body: some View {
        if theme.typographicWidgets {
            noirContent
        } else {
            classicContent
        }
    }

    /// Noir: today's usage above the cache hit — both readable at a glance.
    @ViewBuilder
    private var noirContent: some View {
        if let today = tokscale.todaySummary {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .tracking(1.4)
                    .foregroundStyle(theme.textTertiary)
                Text(Format.compactCount(today.tokens))
                    .font(.system(size: 26, weight: .regular, design: theme.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .themeGlow(theme)
                    .contentTransition(.numericText())
                Text(cacheLine(today))
                    .font(.system(size: 10.5, design: theme.fontDesign))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            Text("Install tokscale for token usage")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func cacheLine(_ today: (tokens: Int, cacheHitRate: Double?)) -> String {
        var parts: [String] = []
        if let rate = today.cacheHitRate { parts.append(String(format: "%.1f%% cache hit", rate * 100)) }
        if let model = tokscale.snapshot?.topModel { parts.append(model) }
        return parts.joined(separator: " · ")
    }

    private var classicContent: some View {
        Group {
            if let today = tokscale.todaySummary {
                HStack(spacing: 12) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 34 * widgetScale, height: 34 * widgetScale)
                        .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Format.compactCount(today.tokens))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())
                        // Single caption line — a half-width slot can't fit a
                        // trailing cache column without truncating everything.
                        Text(today.cacheHitRate.map { String(format: "%.0f%% cache hit", $0 * 100) } ?? "tokens today")
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textTertiary)
                    Text("Install tokscale for token usage")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
            }
        }
    }
}

struct TokenWideWidget: View {
    @Environment(\.widgetScale) private var widgetScale
    @Environment(\.theme) private var theme
    @EnvironmentObject var tokscale: TokscaleStore

    var body: some View {
        if theme.typographicWidgets {
            noirWide
        } else {
            classicWide
        }
    }

    /// Noir stacked home: usage on the left, cache story on the right —
    /// no chip, no chart (the daily trend lives in the Tokens app).
    @ViewBuilder
    private var noirWide: some View {
        if let today = tokscale.todaySummary {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Today")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .tracking(1.4)
                        .foregroundStyle(theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Format.compactCount(today.tokens))
                            .font(.system(size: 26, weight: .regular, design: theme.fontDesign))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                            .themeGlow(theme)
                            .contentTransition(.numericText())
                        Text("tokens")
                            .font(.system(size: 11, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let rate = today.cacheHitRate {
                        Text(String(format: "%.1f%% cache hit", rate * 100))
                            .font(.system(size: 11, design: theme.fontDesign))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .contentTransition(.numericText())
                        MeterBar(progress: rate)
                            .frame(width: 120)
                    }
                    if let model = tokscale.snapshot?.topModel {
                        Text("top · \(model)")
                            .font(.system(size: 10.5, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        } else {
            Text("Install tokscale for token usage")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var classicWide: some View {
        Group {
            if let today = tokscale.todaySummary, let snapshot = tokscale.snapshot {
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 34 * widgetScale, height: 34 * widgetScale)
                        .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Format.compactCount(today.tokens))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("tokens today")
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        if let rate = today.cacheHitRate {
                            Text(String(format: "%.0f%% cache hit", rate * 100))
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textSecondary)
                                .contentTransition(.numericText())
                            MeterBar(progress: rate)
                                .frame(width: 90)
                        }
                        if let topModel = snapshot.topModel {
                            Text("top · \(topModel)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    MiniBars(values: snapshot.daily.suffix(7).map { Double($0.tokens) })
                        .frame(width: 150, height: 34)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textTertiary)
                    Text("Install tokscale for token usage")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
            }
        }
    }
}
