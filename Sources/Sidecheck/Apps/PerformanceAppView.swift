import SwiftUI

/// The Performance app: three graphics/power modes (Pretty / Balanced / Saver)
/// with per-mode impact readouts and the live process numbers from PerfStore.
struct PerformanceAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var performance: PerformanceStore
    @EnvironmentObject var wallpaper: WallpaperStore
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var perf: PerfStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("MODE")
                modeCards
                sectionLabel("RIGHT NOW")
                liveCard
                Text("Estimates are for the current wallpaper (\(kindLabel)) while the panel is open. Hidden, Sidecheck idles at ≈0% regardless of mode — animated backgrounds pause themselves.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
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

    private var currentKind: BackgroundKind {
        wallpaper.spec(for: themes.current).kind
    }

    private var kindLabel: String {
        switch currentKind {
        case .bubbles: "Bubbles"
        case .crt: "CRT"
        case .solid: "Solid color"
        case .gradient: GradientPresets.byID(wallpaper.spec(for: themes.current).gradientID)?.name ?? "Gradient"
        case .image: "Picture"
        case .video: "Video"
        }
    }

    // MARK: Mode cards

    private var modeCards: some View {
        VStack(spacing: 10) {
            ForEach(PerformanceMode.allCases) { mode in
                modeCard(mode)
            }
        }
    }

    private func modeCard(_ mode: PerformanceMode) -> some View {
        let selected = performance.mode == mode
        let cpu = mode.visibleCPUPercent(kind: currentKind)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                performance.mode = mode
            }
        } label: {
            ThemedCard {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(mode.tint)
                        .frame(width: 34, height: 34)
                        .background(mode.tint.opacity(0.14), in: Circle())
                        .themeGlow(theme)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mode.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                        Text(mode.tagline)
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.textSecondary)
                        Text(mode.effectCaption)
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(cpu >= 1 ? "~\(Int(cpu))%" : String(format: "~%.1f%%", cpu))
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(selected ? mode.tint : theme.textSecondary)
                        Text("while open")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.textTertiary)
                        MeterBar(progress: min(cpu / 20, 1), colors: [mode.tint])
                            .frame(width: 52)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .strokeBorder(selected ? mode.tint.opacity(0.85) : theme.cardStroke, lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(mode.tint)
                        .background(Circle().fill(theme.cardFill))
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Live readout

    private var liveCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "waveform.path.ecg", title: "Right now", tint: theme.accent2)
                    Spacer()
                    Text("1 Hz")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.cardFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                }
                if let snapshot = perf.current {
                    Sparkline(values: perf.samples.map { min($0.snapshot.cpuPercent / 10, 1) }, color: theme.accent2, height: 26)
                    HStack(spacing: 14) {
                        liveStat("CPU", String(format: "%.1f%%", snapshot.cpuPercent))
                        liveStat("Wakeups", String(format: "%.0f/s", snapshot.idleWakeupsPerSec))
                        liveStat("Memory", Format.bytes(snapshot.footprintBytes))
                    }
                    if let baseline = perf.hiddenBaseline {
                        Text(String(format: "Hidden baseline: %.1f%% · %.0f wakeups/s", baseline.cpuPercent, baseline.idleWakeupsPerSec))
                            .font(.system(size: 9.5))
                            .monospacedDigit()
                            .foregroundStyle(theme.textTertiary)
                    }
                } else {
                    emptyCaption("Measuring…")
                }
            }
        }
    }

    private func liveStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5))
                .tracking(0.6)
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}
