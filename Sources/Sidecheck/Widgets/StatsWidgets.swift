import SwiftUI

// MARK: - CPU

struct CPUCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore

    private var coreBarWidth: CGFloat { stats.cpuCores.count > 12 ? 5 : 7 }

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardTitle(icon: "cpu", title: "CPU")
                    Spacer()
                    if let temp = stats.cpuTempC {
                        Text(String(format: "%.0f°C", temp))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.accent2)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.cardFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                            .transition(.opacity)
                    }
                    Text("\(Int(stats.cpuUsage.rounded()))%")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                        .themeGlow(theme)
                }
                HStack(spacing: 16) {
                    RingGauge(progress: stats.cpuUsage / 100, lineWidth: 10) {
                        VStack(spacing: 0) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .themeGlow(theme)
                        }
                    }
                    .frame(width: 64, height: 64)

                    // per-core mini bars
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(stats.cpuCores.indices, id: \.self) { index in
                            Capsule()
                                .fill(coreColor(stats.cpuCores[index]))
                                .frame(width: coreBarWidth, height: 44)
                                .opacity(stats.cpuCores[index] < 2 ? 0.28 : 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Sparkline(values: stats.cpuHistory)
                Text("\(stats.cpuCores.count) cores · last \(stats.cpuHistory.count)s")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func coreColor(_ load: Double) -> Color {
        switch load {
        case ..<40: theme.accent
        case ..<75: theme.accent2
        default: Color.red
        }
    }
}

// MARK: - Memory

struct MemoryCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "memorychip", title: "Memory")
                    Spacer()
                    Text("\(Int(stats.memoryUsage.rounded()))%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                MeterBar(progress: stats.memoryUsage / 100)
                Text("\(Format.bytes(stats.usedMemoryBytes)) of \(Format.bytes(stats.totalMemoryBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - Battery

struct BatteryCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore
    @EnvironmentObject var performance: PerformanceStore

    var body: some View {
        if let percent = stats.batteryPercent {
            ThemedCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardTitle(
                            icon: stats.isCharging ? "bolt.badge.clock" : "battery.75percent",
                            title: "Battery",
                            tint: stats.isCharging ? .green : nil
                        )
                        Spacer()
                        HStack(spacing: 4) {
                            if stats.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .repeatingPulse(performance.isOn(.microAnimations))
                            }
                            Text("\(percent)%")
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                                .contentTransition(.numericText())
                        }
                    }
                    MeterBar(
                        progress: Double(percent) / 100,
                        colors: percent <= 20 ? [.red, .orange] : [.green, .mint]
                    )
                    Text(stats.isCharging ? "Charging" : "On battery")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }
}

// MARK: - Network

struct NetworkCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "wifi", title: "Network")
                rateRow(symbol: "arrow.down", value: stats.netDownBps, history: stats.netDownHistory, tint: theme.accent)
                rateRow(symbol: "arrow.up", value: stats.netUpBps, history: stats.netUpHistory, tint: theme.accent2)
            }
        }
    }

    private func rateRow(symbol: String, value: Double, history: [Double], tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .themeGlow(theme)
            Text(Format.rate(value))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())
                .frame(width: 74, alignment: .leading)
            Sparkline(values: history, color: tint)
        }
    }
}

// MARK: - Disk

struct DiskCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "internaldrive", title: "Disk")
                    Spacer()
                    Text("\(Int(stats.diskUsedFraction * 100).clamped())%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                MeterBar(
                    progress: stats.diskUsedFraction,
                    colors: stats.diskUsedFraction > 0.9 ? [.orange, .red] : [theme.accent, theme.accent2]
                )
                Text("\(Format.bytes(stats.diskFreeBytes)) free of \(Format.bytes(stats.diskTotalBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

extension Int {
    func clamped() -> Int { Swift.min(Swift.max(self, 0), 100) }
}

// MARK: - Uptime

struct UptimeChip: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
            Text("up \(Format.uptime(stats.uptimeSeconds))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.cardFill, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
    }
}

// MARK: - Sparkline

/// Streaming area chart for 1 Hz samples (chart-engine recommendation:
/// streaming data shows history + current value, not a single frame).
struct Sparkline: View {
    @Environment(\.theme) private var theme
    let values: [Double] // 0...1, oldest first
    var color: Color?
    var height: CGFloat = 30

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)

            var line = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height * (1 - CGFloat(Swift.min(Swift.max(value, 0), 1)) * 0.92) - 1
                if index == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            let tint = color ?? theme.accent
            context.fill(area, with: .color(tint.opacity(0.15)))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Processes card

/// Top processes by CPU or memory, with a two-tap kill (first tap arms a
/// 3-second confirm so a mis-tap can't SIGTERM anything).
struct ProcessesCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var processes: ProcessStore
    @State private var confirmKill: Int32?

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "cpu", title: "Processes")
                    Spacer()
                    HStack(spacing: 6) {
                        metricPill("CPU", .cpu)
                        metricPill("MEM", .memory)
                    }
                }
                if processes.processes.isEmpty {
                    Text("Sampling…")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    let maxValue = processes.processes.map(value).max() ?? 0
                    ForEach(processes.processes) { sample in
                        row(sample, maxValue: maxValue)
                    }
                }
            }
        }
    }

    private var metric: ProcessMetric { processes.metric }

    private func metricPill(_ label: String, _ candidate: ProcessMetric) -> some View {
        Button {
            processes.metric = candidate
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(metric == candidate ? theme.accent : theme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(theme.accent.opacity(metric == candidate ? 0.14 : 0), in: Capsule())
                .overlay(Capsule().strokeBorder(metric == candidate ? theme.accent.opacity(0.5) : theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    private func value(_ sample: ProcessSample) -> Double {
        switch metric {
        case .cpu: sample.cpuPercent
        case .memory: Double(sample.memBytes)
        }
    }

    private func valueText(_ sample: ProcessSample) -> String {
        switch metric {
        case .cpu: String(format: "%.0f%%", sample.cpuPercent)
        case .memory: Self.compactBytes(sample.memBytes)
        }
    }

    /// "778M" / "1.2G" — Format.bytes wraps inside the card's value column.
    private static func compactBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1fG", mb / 1024) }
        return "\(Int(mb.rounded()))M"
    }

    private func row(_ sample: ProcessSample, maxValue: Double) -> some View {
        let armed = confirmKill == sample.pid
        return HStack(spacing: 10) {
            Text(sample.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer()
            MeterBar(progress: maxValue > 0 ? value(sample) / maxValue : 0)
                .frame(width: 74)
            Text(valueText(sample))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
                .frame(width: 52, alignment: .trailing)
            Button {
                if armed {
                    confirmKill = nil
                    processes.terminate(sample)
                } else {
                    confirmKill = sample.pid
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        if confirmKill == sample.pid { confirmKill = nil }
                    }
                }
            } label: {
                Text(armed ? "Sure?" : "Kill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(armed ? .white : theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        armed ? Color.red.opacity(0.85) : theme.cardFill,
                        in: Capsule()
                    )
                    .overlay(Capsule().strokeBorder(armed ? Color.red : theme.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
    }
}

// MARK: - Shared meter bar

struct MeterBar: View {
    @Environment(\.theme) private var theme
    let progress: Double
    var colors: [Color]
    /// Optional tween applied on progress changes (e.g. `.linear(duration: 1.05)`
    /// under a 1 Hz TimelineView reads as one gliding bar). nil = instant jump.
    var animation: Animation?

    init(progress: Double, colors: [Color]? = nil, animation: Animation? = nil) {
        self.progress = progress
        self.colors = colors ?? []
        self.animation = animation
    }

    var body: some View {
        if theme.meterSegments > 0 {
            segmented
        } else {
            smooth
        }
    }

    /// Glass themes: one glossy capsule filling left to right.
    private var smooth: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.divider)
                Capsule()
                    .fill(colors.first ?? theme.accent)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                    .animation(animation, value: progress)
            }
        }
        .frame(height: 8)
    }

    /// Phosphor themes: N discrete segments lighting up like a terminal VU
    /// meter — the theme declares the count in `meterSegments`.
    private var segmented: some View {
        let segments = theme.meterSegments
        let filled = Int((min(max(progress, 0), 1) * Double(segments)).rounded())
        return GeometryReader { geo in
            HStack(spacing: max(2, geo.size.width * 0.07)) {
                ForEach(0..<segments, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? (colors.first ?? theme.accent) : theme.divider)
                }
                .frame(maxWidth: .infinity)
            }
            .animation(animation, value: progress)
        }
        .frame(height: 8)
    }
}
