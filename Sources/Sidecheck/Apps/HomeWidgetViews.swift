import SwiftUI

// MARK: - App icon tile (home grid + dock)

struct AppIconTile: View {
    @Environment(\.theme) private var theme
    let app: PanelApp
    var size: CGFloat = 56
    var showsLabel = true

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: size * theme.iconCornerRadiusRatio, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [app.tint.opacity(0.9), app.tint.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
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
                .shadow(color: app.tint.opacity(theme.isLight ? 0.35 : 0.45), radius: 5, y: 3)

            if showsLabel {
                Text(app.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.iconLabelIsWhite ? Color.white : theme.textPrimary)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(theme.iconLabelIsWhite ? 0.45 : 0.0), radius: 2, y: 1)
            }
        }
    }
}

// MARK: - Edit-mode jiggle

struct JiggleEffect: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active, !reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.36)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate / 0.36
                content.rotationEffect(.degrees(sin(phase * 2 * .pi) * 1.1))
            }
        } else {
            content
        }
    }
}

extension View {
    func jiggle(active: Bool) -> some View { modifier(JiggleEffect(active: active)) }
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

    private var kind: WidgetKind? {
        home.widgetSlots.indices.contains(index) ? home.widgetSlots[index] : nil
    }

    var body: some View {
        Group {
            if home.isEditMode {
                pickerMenu { slotChrome(kind: kind) }
                    .overlay(alignment: .topTrailing) { removeBadge }
            } else if let kind {
                Button {
                    onOpen(kind.app)
                } label: {
                    slotChrome(kind: kind)
                }
                .buttonStyle(.plain)
                .onLongPressGesture(minimumDuration: 0.45) {
                    withAnimation(.snappy) { home.isEditMode = true }
                }
            } else {
                pickerMenu { emptyChrome }
            }
        }
        .jiggle(active: home.isEditMode)
    }

    // MARK: chrome

    @ViewBuilder
    private func slotChrome(kind: WidgetKind?) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                // Music's widget is a self-contained now-playing bar — no
                // badge row (edit mode keeps it for slot identification).
                if home.isEditMode || (kind?.showsSlotHeader ?? true) {
                    HStack(spacing: 8) {
                        WidgetBadge(kind: kind ?? .settings)
                        Text(kind?.name ?? "Widget")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        if home.isEditMode {
                            HStack(spacing: 2) {
                                moveButton(direction: -1, enabled: index > 0)
                                moveButton(direction: 1, enabled: index < home.effectiveSlots.count - 1)
                            }
                        }
                    }
                }
                if let kind {
                    if wide {
                        kind.wideWidget
                    } else {
                        kind.homeWidget
                    }
                }
            }
        }
    }

    private func moveButton(direction: Int, enabled: Bool) -> some View {
        Button {
            home.move(slot: index, direction: direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary.opacity(0.35))
                .padding(4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(direction < 0 ? "Move left" : "Move right")
    }

    private var emptyChrome: some View {
        RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
            .strokeBorder(theme.cardStroke, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            .frame(height: 96)
            .frame(maxWidth: .infinity)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(Circle().fill(Color.red))
        }
        .buttonStyle(.plain)
        .offset(x: 7, y: -7)
        .help("Remove widget")
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
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Tiny rounded glyph badge used in widget title rows.
struct WidgetBadge: View {
    @Environment(\.theme) private var theme
    let kind: WidgetKind

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: [kind.tint.opacity(0.9), kind.tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
            .frame(width: 18, height: 18)
            .overlay {
                Image(systemName: kind.symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - Compact home widgets

struct MonitorHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        monitorContent
    }

    private var monitorContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                RingGauge(progress: stats.cpuUsage / 100, lineWidth: 6) { EmptyView() }
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("CPU").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                        Spacer()
                        Text("\(Int(stats.cpuUsage.rounded()))%")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                    MeterBar(progress: stats.memoryUsage / 100)
                    Text(tempLine)
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Sparkline(values: stats.cpuHistory, height: 22)
        }
    }

    private var tempLine: String {
        var parts = ["MEM \(Int(stats.memoryUsage.rounded()))%", Format.bytes(stats.usedMemoryBytes)]
        if let temp = stats.cpuTempC {
            parts.append(String(format: "%.0f°C", temp))
        }
        return parts.joined(separator: " · ")
    }
}

struct BatteryHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var performance: PerformanceStore

    var body: some View {
        if let percent = stats.batteryPercent {
            HStack(spacing: 14) {
                RingGauge(progress: Double(percent) / 100, lineWidth: 6) {
                    Text("\(percent)")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if stats.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.green)
                                .repeatingPulse(performance.isOn(.microAnimations))
                        }
                        Text(stats.isCharging ? "Charging" : "On battery")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    Text("Reported by macOS")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            }
        } else {
            Text("No battery detected")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

struct NetworkHomeWidget: View {
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)
                Text(Format.rate(stats.netDownBps))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.purple)
                Text(Format.rate(stats.netUpBps))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Sparkline(values: stats.netDownHistory, color: .blue, height: 20)
            Sparkline(values: stats.netUpHistory, color: .purple, height: 20)
        }
    }
}

struct DiskHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Int(stats.diskUsedFraction * 100))% used")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())
                Spacer()
                Text("\(Format.bytes(stats.diskFreeBytes)) free")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
            }
            MeterBar(progress: stats.diskUsedFraction)
        }
    }
}

struct WallpaperHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var wallpaper: WallpaperStore

    private var spec: BackgroundSpec { wallpaper.spec(for: themes.current) }

    var body: some View {
        HStack(spacing: 10) {
            swatchFill
                .frame(width: 30, height: 30)
                .overlay(
                    Group {
                        if spec.kind == .video {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        } else if spec.kind == .image, let image = WallpaperStore.cachedImage(spec.filePath) {
                            Image(nsImage: image).resizable().scaledToFill()
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text("Wallpaper")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(kindName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var kindName: String {
        switch spec.kind {
        case .bubbles: "Bubbles"
        case .crt: "CRT"
        case .solid: "Solid color"
        case .gradient: GradientPresets.byID(spec.gradientID)?.name ?? "Gradient"
        case .image: "Picture"
        case .video: "Video"
        }
    }

    @ViewBuilder
    private var swatchFill: some View {
        switch spec.kind {
        case .bubbles:
            LinearGradient(colors: [Color.white.opacity(0.25), Color.blue.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        case .crt:
            LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.3, blue: 0.12)], startPoint: .top, endPoint: .bottom)
        case .solid:
            let color = spec.color?.color ?? .black
            LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom)
        case .gradient:
            let preset = GradientPresets.byID(spec.gradientID) ?? GradientPresets.all[0]
            LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .image, .video:
            LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct AwakeHomeWidget: View {
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
                            Text(Self.shortDuration(remaining))
                                .font(.system(size: 8.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                        } else {
                            Image(systemName: "infinity")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.textPrimary)
                                .themeGlow(theme)
                        }
                    }
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awake")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(endLabel)
                        .font(.system(size: 9.5))
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

    private static func shortDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ScreenTimeHomeWidget: View {
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
        } else {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.duration(screenTime.snapshot.todayTotal))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(topAppLine)
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var topAppLine: String {
        if let top = screenTime.snapshot.todayApps.first {
            return "Top · \(top.usage.name)"
        }
        return "No activity yet"
    }
}

struct SettingsHomeWidget: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14))
                .foregroundStyle(theme.accent)
            Text("Theme, panel size & animation")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
        }
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
                    .font(.system(size: 9.5))
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
    @Environment(\.theme) private var theme
    @EnvironmentObject var music: MusicStore

    var body: some View {
        if let track = music.track {
            HStack(spacing: 10) {
                artworkThumb
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: music.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accent)
                    .themeGlow(theme)
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
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.cardFill)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                )
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        }
    }
}

// MARK: - Wide variants (single full-width slot)

struct MonitorWideWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var stats: StatsStore

    var body: some View {
        HStack(spacing: 14) {
            RingGauge(progress: stats.cpuUsage / 100, lineWidth: 6) { EmptyView() }
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("CPU").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                    Spacer()
                    Text("\(Int(stats.cpuUsage.rounded()))%")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                }
                MeterBar(progress: stats.memoryUsage / 100)
                Text("MEM \(Int(stats.memoryUsage.rounded()))% · \(Format.bytes(stats.usedMemoryBytes))")
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
            Divider().overlay(theme.divider).frame(height: 36)
            VStack(alignment: .leading, spacing: 4) {
                rateRow("arrow.down", color: .blue, value: stats.netDownBps)
                rateRow("arrow.up", color: .purple, value: stats.netUpBps)
                if let temp = stats.cpuTempC {
                    Text(String(format: "%.0f°C", temp))
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Sparkline(values: stats.cpuHistory, height: 30)
                .frame(width: 88)
        }
    }

    private func rateRow(_ symbol: String, color: Color, value: Double) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(Format.rate(value))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
        }
    }
}

struct ScreenTimeWideWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var screenTime: ScreenTimeStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.duration(screenTime.snapshot.todayTotal))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(topAppLine)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
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
    @Environment(\.theme) private var theme
    @EnvironmentObject var music: MusicStore

    var body: some View {
        if let track = music.track {
            VStack(spacing: 9) {
                HStack(spacing: 12) {
                    artworkThumb
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    // Mini version of the app page's gradient transport button.
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(LinearGradient(
                                colors: [theme.accent, theme.accent2],
                                startPoint: .top, endPoint: .bottom
                            ))
                        )
                        .themeGlow(theme)
                }
                if track.duration > 0 {
                    MeterBar(progress: min(max(music.positionNow() / track.duration, 0), 1))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                )
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        }
    }
}

struct PerformanceHomeWidget: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var performance: PerformanceStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(LinearGradient(
                        colors: [performance.mode.tint.opacity(0.9), performance.mode.tint.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                )
                .themeGlow(theme)
            VStack(alignment: .leading, spacing: 3) {
                Text(performance.mode.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(performance.mode.effectCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
