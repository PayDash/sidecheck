import SwiftUI

/// The Awake app: keep the Mac awake (and survive lid closure on AC power)
/// for 1h / 2h / 4h / ∞ or a custom duration, powered by /usr/bin/caffeinate.
struct AwakeAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var awake: AwakeStore
    @EnvironmentObject var stats: StatsStore

    @State private var customHours = 6.0
    @State private var customMinutes = 0.0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("STATUS")
                statusCard

                sectionLabel("DURATION")
                durationCard

                if onBattery {
                    batteryNote
                }
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.textTertiary)
    }

    private var onBattery: Bool {
        let battery = BatteryInfo.current()
        return battery != nil && battery?.isCharging == false
    }

    // MARK: Status

    private var statusCard: some View {
        ThemedCard {
            HStack(spacing: 16) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statusRing(context.date)
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 5) {
                    Text(awake.isActive ? "Awake" : "Off")
                        .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .themeGlow(theme)
                    Text(statusDetail)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                    if awake.isActive {
                        Button {
                            awake.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.red.opacity(0.85), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func statusRing(_ now: Date) -> some View {
        if awake.isActive {
            let remaining = awake.endDate.map { max(0, $0.timeIntervalSince(now)) }
            RingGauge(progress: ringProgress(now: now, remaining: remaining), lineWidth: 7) {
                VStack(spacing: 0) {
                    if let remaining {
                        Text(Self.shortDuration(remaining))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    } else {
                        Image(systemName: "infinity")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .themeGlow(theme)
                    }
                }
            }
        } else {
            ZStack {
                Circle().stroke(theme.divider, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                Image(systemName: "zzz")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func ringProgress(now: Date, remaining: TimeInterval?) -> Double {
        guard let remaining else { return 1 } // infinite = full ring
        guard let total = awake.sessionDuration, total > 0 else { return 1 }
        return remaining / total // ring drains as the session burns down
    }

    private var statusDetail: String {
        if !awake.isActive {
            return "Mac sleeps normally"
        }
        if let endDate = awake.endDate {
            let time = endDate.formatted(date: .omitted, time: .shortened)
            return "Until \(time)"
        }
        return "Until you stop it"
    }

    // MARK: Duration

    private var durationCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    durationPill("1h", 3600)
                    durationPill("2h", 7200)
                    durationPill("4h", 14400)
                    durationPill("∞", nil)
                }

                Divider().overlay(theme.divider)

                Text("Custom")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hours")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                        Slider(value: $customHours, in: 0...12, step: 1)
                        Text("\(Int(customHours)) h")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Minutes")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                        Slider(value: $customMinutes, in: 0...59, step: 1)
                        Text("\(Int(customMinutes)) min")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
                Button {
                    awake.start(duration: customHours * 3600 + customMinutes * 60)
                } label: {
                    Label(startLabel, systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                                .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(customDuration < 60)

                Toggle(isOn: $awake.keepsDisplayAwake) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep display awake")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.textPrimary)
                        Text("Off = screen may sleep, Mac stays awake")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private var startLabel: String {
        let hours = Int(customHours)
        let minutes = Int(customMinutes)
        if hours == 0, minutes == 0 { return "Start" }
        if hours == 0 { return "Start — \(minutes) min" }
        if minutes == 0 { return "Start — \(hours) h" }
        return "Start — \(hours) h \(minutes) min"
    }

    private var customDuration: TimeInterval {
        customHours * 3600 + customMinutes * 60
    }

    private func durationPill(_ label: String, _ duration: TimeInterval?) -> some View {
        Button {
            awake.start(duration: duration)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(theme.cardFill, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(1)
        .help(duration.map { "Stay awake for \(Int($0 / 3600)) hours" } ?? "Stay awake until stopped")
    }

    private var batteryNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "battery.50percent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("On battery — lid closed still sleeps the Mac. Plug in for clamshell mode.")
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

    private static func shortDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
