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
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.cardFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                            .transition(.opacity)
                    }
                    Text("\(Int(stats.cpuUsage.rounded()))%")
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                        .themeGlow(theme)
                }
                HStack(spacing: 18) {
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
                    HStack(alignment: .bottom, spacing: 3) {
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
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                MeterBar(progress: stats.memoryUsage / 100)
                Text("\(Format.bytes(stats.usedMemoryBytes)) of \(Format.bytes(stats.totalMemoryBytes))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - Battery

struct BatteryCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject var stats: StatsStore

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
                        HStack(spacing: 3) {
                            if stats.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.green)
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                            Text("\(percent)%")
                                .font(.system(size: 14, weight: .bold))
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
                        .font(.system(size: 10.5))
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
                .font(.system(size: 11, weight: .bold))
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
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                MeterBar(
                    progress: stats.diskUsedFraction,
                    colors: stats.diskUsedFraction > 0.9 ? [.orange, .red] : [theme.accent, theme.accent2]
                )
                Text("\(Format.bytes(stats.diskFreeBytes)) free of \(Format.bytes(stats.diskTotalBytes))")
                    .font(.system(size: 10.5))
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
        .padding(.vertical, 7)
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
            context.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.3), .clear]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ))
            // soft glow pass, then the crisp line on top
            context.stroke(line, with: .color(tint.opacity(0.25)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared meter bar

struct MeterBar: View {
    @Environment(\.theme) private var theme
    let progress: Double
    var colors: [Color]

    init(progress: Double, colors: [Color]? = nil) {
        self.progress = progress
        self.colors = colors ?? []
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.divider)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: colors.isEmpty ? [theme.accent, theme.accent2] : colors,
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                    .themeGlow(theme)
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: progress)
    }
}
