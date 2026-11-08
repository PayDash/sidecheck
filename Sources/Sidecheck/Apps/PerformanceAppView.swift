import SwiftUI

/// The Performance app: performance modes (Pretty / Balanced / Saver / Custom)
/// with per-mode impact readouts, a feature registry tuner for Custom, the
/// auto-by-power switch, and the live process numbers from PerfStore.
struct PerformanceAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var performance: PerformanceStore
    @EnvironmentObject var wallpaper: WallpaperStore
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var perf: PerfStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Mode")
                modeCards
                if performance.autoPower {
                    powerManagedNote
                }
                sectionLabel("Features")
                featuresSection
                sectionLabel("Power")
                powerCard
                sectionLabel("Right now")
                liveCard
                Text("Estimates are for the current wallpaper (\(kindLabel)) while the panel is open. Hidden, Sidecheck idles at ≈0% regardless of mode — animated backgrounds pause themselves.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
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
        // Custom's estimate reads the persisted toggle set; presets use their
        // own feature mapping.
        let feats = mode == .custom ? performance.customFeatures : mode.features()
        let cpu = PerformanceStore.estimate(features: feats, kind: currentKind)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                performance.autoPower = false // manual pick takes over
                performance.mode = mode
            }
        } label: {
            ThemedCard {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode.tint)
                        .frame(width: 34, height: 34)
                        .background(mode.tint.opacity(0.14), in: Circle())
                        .themeGlow(theme)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(mode.tagline)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                        Text(mode.effectCaption)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(cpu >= 1 ? "~\(Int(cpu))%" : String(format: "~%.1f%%", cpu))
                            .font(.system(size: 13, weight: .semibold))
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

    private var powerManagedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text("Managed by power — a manual change takes over.")
                .font(.system(size: 10))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Features

    private var featuresSection: some View {
        let custom = performance.mode == .custom
        let estimate = PerformanceStore.estimate(features: performance.activeFeatures, kind: currentKind)
        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardTitle(icon: "switch.2", title: "Feature switches")
                    Spacer()
                    Text("~\(estimate >= 1 ? String(Int(estimate)) : String(format: "%.1f", estimate))% while open")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(custom ? theme.accent : theme.textTertiary)
                }
                ForEach(PerformanceFeature.allCases) { feature in
                    featureRow(feature, customTuneable: custom)
                }
                if !custom {
                    Text("Switch to Custom to tune these.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func featureRow(_ feature: PerformanceFeature, customTuneable: Bool) -> some View {
        let isOn = performance.isOn(feature)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(customTuneable ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                Text(feature.costCaption(kind: currentKind))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if customTuneable {
                ThemeSwitch(isOn: Binding(
                    get: { performance.isOn(feature) },
                    set: { performance.setFeature(feature, on: $0) }
                ))
            } else {
                Image(systemName: isOn ? "checkmark.circle.fill" : "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? theme.accent : theme.textTertiary)
            }
        }
    }

    // MARK: Power

    private var powerCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Follow power")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textPrimary)
                        Text("Saver on battery · Pretty on power. Any manual change turns this off.")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    ThemeSwitch(isOn: $performance.autoPower)
                }
            }
        }
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
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
                            .font(.system(size: 10))
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
                .font(.system(size: 10))
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
