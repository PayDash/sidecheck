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
                        .font(.system(size: size * 0.4, weight: .semibold))
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
                HStack(spacing: 8) {
                    WidgetBadge(kind: kind ?? .settings)
                    Text(kind?.name ?? "Widget")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    if home.isEditMode {
                        HStack(spacing: 2) {
                            moveButton(direction: -1, enabled: index > 0)
                            moveButton(direction: 1, enabled: index < home.widgetSlots.count - 1)
                        }
                    }
                }
                if let kind {
                    kind.homeWidget
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
                            .contentTransition(.numericText())
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
                                .symbolEffect(.pulse, options: .repeating)
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
