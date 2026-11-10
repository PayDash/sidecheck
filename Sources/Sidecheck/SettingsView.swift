import ServiceManagement
import SwiftUI
import UserNotifications

/// In-panel settings: appearance, panel customization (size/animation),
/// home widget slots, and about. Rendered inside the Settings app page.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var controller: PanelController
    @EnvironmentObject var home: HomeStore
    @EnvironmentObject var perf: PerfStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Appearance")
                themeGrid

                sectionLabel("Panel")
                panelControls

                sectionLabel("Edge zone")
                edgeControls

                sectionLabel("Home widgets")
                slotControls

                sectionLabel("Alerts")
                alertControls

                sectionLabel("Diagnostics")
                diagnosticsControls

                Text("Sidecheck v0.13.1 — audit fixes: stats.fm crash, repeat-listen counting, off-main process scan")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.textTertiary)
    }

    // MARK: Appearance

    private var themeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            ForEach(ThemeID.allCases) { id in
                ThemeSwatch(themes: themes, id: id, isSelected: themes.current == id)
            }
        }
    }

    // MARK: Panel

    private var panelControls: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Size")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text("\(Int((controller.panelScale * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .contentTransition(.numericText())
                }
                PanelSlider(value: $controller.panelScale, range: Config.panelScaleRange)

                Text("Open / close animation")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                // SwiftUI pills — the AppKit segmented picker re-ran Auto
                // Layout during panel transitions like the sliders did.
                HStack(spacing: 8) {
                    ForEach(PanelAnimationStyle.allCases) { style in
                        animationPill(style)
                    }
                }

                HStack {
                    Text("Speed")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(String(format: "%.2f s", controller.animationSpeed))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .contentTransition(.numericText())
                }
                PanelSlider(value: $controller.animationSpeed, range: Config.animationSpeedRange)
            }
        }
    }

    private func animationPill(_ style: PanelAnimationStyle) -> some View {
        let isSelected = controller.animationStyle == style
        return Button {
            controller.animationStyle = style
        } label: {
            Text(style.displayName)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? theme.accent.opacity(0.15) : theme.cardFill, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? theme.accent.opacity(0.6) : theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Edge zone

    private var edgeControls: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                sliderRow(
                    title: "Zone width",
                    value: $controller.hotZoneWidth,
                    range: Config.hotZoneWidthRange,
                    display: { String(format: "%.0f pt", $0) }
                )
                sliderRow(
                    title: "Zone height",
                    value: $controller.hotZoneSpan,
                    range: Config.hotZoneSpanRange,
                    display: { String(format: "%.0f %%", $0 * 100) }
                )
                sliderRow(
                    title: "Show delay",
                    value: $controller.showDwellDelay,
                    range: Config.dwellDelayRange,
                    display: { String(format: "%.2f s", $0) }
                )
                sliderRow(
                    title: "Hide delay",
                    value: $controller.hideDwellDelay,
                    range: Config.dwellDelayRange,
                    display: { String(format: "%.2f s", $0) }
                )
                Text("The zone hugs the screen's right edge; delays smooth out accidental grazes.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .contentTransition(.numericText())
            }
            PanelSlider(value: value, range: range)
        }
    }

    // MARK: Home widget slots

    private var slotControls: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Widget slots")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text("\(home.slotCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                        .contentTransition(.numericText())
                }
                if home.activeLimit > Config.slotCountRange.lowerBound {
                    Slider(
                        value: Binding(
                            get: { Double(home.slotCount) },
                            set: { home.slotCount = Int($0.rounded()) }
                        ),
                        in: Double(Config.slotCountRange.lowerBound)...Double(home.activeLimit),
                        step: 1
                    )
                } else {
                    // Slider requires lower < upper — a phone theme caps at 2.
                    Text("2 slots — the max for this theme's width")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.cardStroke, lineWidth: 1)
            )

            ForEach(home.effectiveSlots.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text("Slot \(index + 1)")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    slotMoveButtons(index: index)
                    slotMenu(index: index)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                )
            }
            Text("Long-press a home widget to rebind it; use the chevrons to reorder.")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func slotMoveButtons(index: Int) -> some View {
        HStack(spacing: 2) {
            slotMoveButton(index: index, direction: -1, enabled: index > 0)
            slotMoveButton(index: index, direction: 1, enabled: index < home.effectiveSlots.count - 1)
        }
    }

    private func slotMoveButton(index: Int, direction: Int, enabled: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                home.move(slot: index, direction: direction)
            }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary.opacity(0.35))
                .padding(4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(direction < 0 ? "Move left" : "Move right")
    }

    // MARK: Alerts

    private var alertControls: some View {
        ThemedCard {
            HStack(spacing: 10) {
                Image(systemName: "battery.25percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Low-battery alerts")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Text("Notify at 20% and 10% while on battery")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                ThemeSwitch(isOn: Binding(
                    get: { controller.alerter.isEnabled },
                    set: { controller.alerter.isEnabled = $0 }
                ))
            }
        }
    }

    // MARK: Diagnostics

    private var diagnosticsControls: some View {
        VStack(spacing: 8) {
            liveProcessCard
            healthCard
            permissionsCard
        }
    }

    private var liveProcessCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "waveform.path.ecg", title: "Live process", tint: theme.accent2)
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
                        metric("CPU", String(format: "%.1f%%", snapshot.cpuPercent))
                        metric("Memory", Format.bytes(snapshot.footprintBytes))
                        metric("Wakeups", String(format: "%.0f/s", snapshot.idleWakeupsPerSec))
                    }
                    HStack(spacing: 14) {
                        metric("Syscalls", String(format: "%.0f/s", snapshot.syscallsPerSec))
                        metric("Ctx switches", String(format: "%.0f/s", snapshot.contextSwitchesPerSec))
                        metric("Threads", "\(snapshot.threads)")
                    }
                    if let baseline = perf.hiddenBaseline {
                        HStack(spacing: 6) {
                            Image(systemName: "moon.zzz")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                            Text("Hidden baseline")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f%% · %.0f wakeups/s", baseline.cpuPercent, baseline.idleWakeupsPerSec))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textPrimary)
                                .contentTransition(.numericText())
                        }
                    }
                    Text("Sparkline is 0–10% CPU. While hidden expect ≈0% CPU and single-digit wakeups/s; visible UI (animated backgrounds, 1 Hz stats) legitimately raises both.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    Text("Measuring — rates appear on the next tick…")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private var healthCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(icon: "checkmark.shield", title: "Health")
                healthRow("Edge tracker", controller.edgeTracker.isRunning ? "Active" : "STOPPED",
                          ok: controller.edgeTracker.isRunning)
                healthRow("Clipboard capture",
                          controller.clipboard.isPolling ? "On · \(controller.clipboard.items.count) items" : "OFF",
                          ok: controller.clipboard.isPolling)
                healthRow("Stats sampling",
                          controller.statsStore.isSampling ? "Active (visible)" : "Idle (hidden)",
                          ok: true)
                healthRow("Process sampling",
                          controller.processes.isSampling
                              ? (controller.processes.isScanEnabled ? "Active (visible)" : "Paused (performance)")
                              : "Idle (hidden)",
                          ok: true)
                healthRow("Music",
                          controller.music.isPolling ? "Recording plays" : "Off",
                          ok: controller.music.isPolling)
                healthRow("Token scanner",
                          controller.tokscale.state.healthText,
                          ok: controller.tokscale.state.isHealthy)
                healthRow("Battery alerts",
                          controller.alerter.isEnabled ? "On — 20% / 10%" : "Off",
                          ok: true)
                healthRow("Screen Time tracker",
                          controller.screenTime.trackingEnabled
                              ? (controller.screenTime.isTracking ? "Recording" : "Starting…")
                              : "Off",
                          ok: controller.screenTime.trackingEnabled)
                healthRow("Panel", controller.isVisible ? "Visible" : "Hidden", ok: true)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
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

    private func healthRow(_ name: String, _ state: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(state)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ok ? theme.textSecondary : Color.red)
        }
    }

    // MARK: Permissions

    /// Shows every system permission Sidecheck can touch and whether it's
    /// been granted. Sidecheck is deliberately permission-light: edge
    /// tracking uses NSEvent monitors (no Accessibility) and wallpapers use
    /// NSOpenPanel (no sandbox prompts) — notifications and the login item
    /// are the only two.
    private var permissionsCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(icon: "lock.shield", title: "Permissions")
                notificationsRow
                loginItemRow
                Text("Files picked for wallpapers are read directly — no sandbox permission needed.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .task { refreshNotificationStatus() }
        .onChange(of: controller.alerter.isEnabled) { _, _ in refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshNotificationStatus()
        }
    }

    @State private var notificationStatus: UNAuthorizationStatus?

    private var notificationsRow: some View {
        let status = notificationStatus
        let state: String
        let denied: Bool
        if status == nil, Bundle.main.bundleIdentifier == nil {
            state = "N/A (dev build)"
            denied = false
        } else {
            switch status ?? .notDetermined {
            case .authorized, .provisional:
                state = "Granted"
                denied = false
            case .denied:
                state = "Denied"
                denied = true
            case .notDetermined:
                state = "Not requested"
                denied = false
            @unknown default:
                state = "Unknown"
                denied = false
            }
        }
        return HStack(spacing: 8) {
            Circle()
                .fill(denied ? Color.red : Color.green)
                .frame(width: 7, height: 7)
            Text("Notifications")
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(state)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(denied ? Color.red : theme.textSecondary)
            if denied {
                systemSettingsButton("Open Settings", pane: "x-apple.systempreferences:com.apple.preference.notifications")
            }
        }
    }

    private var loginItemRow: some View {
        let status = SMAppService.mainApp.status
        let state: String
        let color: Color
        let action: (String, String)?
        switch status {
        case .enabled:
            state = "Granted"
            color = .green
            action = nil
        case .requiresApproval:
            state = "Approval pending"
            color = .orange
            action = ("Approve", "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        case .notRegistered:
            state = "Off"
            color = .gray
            action = nil
        case .notFound:
            state = "N/A (dev build)"
            color = .gray
            action = nil
        @unknown default:
            state = "Unknown"
            color = .gray
            action = nil
        }
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("Launch at Login")
                .font(.system(size: 13))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(state)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color == .gray ? theme.textSecondary : color)
            if let action {
                systemSettingsButton(action.0, pane: action.1)
            }
        }
    }

    private func systemSettingsButton(_ title: String, pane: String) -> some View {
        Button {
            if let url = URL(string: pane) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func refreshNotificationStatus() {
        guard let center = UNUserNotificationCenter.sidecheck else { return }
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    notificationStatus = settings.authorizationStatus
                }
            }
        }
    }

    private func slotMenu(index: Int) -> some View {
        Menu {
            ForEach(WidgetKind.allCases) { kind in
                Button(kind.name) {
                    home.assign(slot: index, kind: kind)
                }
            }
            Divider()
            Button("None") {
                home.assign(slot: index, kind: nil)
            }
        } label: {
            HStack(spacing: 6) {
                if let kind = home.widgetSlots[index] {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                    Text(kind.name)
                        .foregroundStyle(theme.textPrimary)
                } else {
                    Text("Empty")
                        .foregroundStyle(theme.textTertiary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// One selectable theme preview in the picker.
private struct ThemeSwatch: View {
    @Environment(\.theme) private var theme
    let themes: ThemeStore
    let id: ThemeID
    let isSelected: Bool

    var body: some View {
        Button {
            // Plain assignment — the crossfade timing is owned by
            // PanelView's `.animation(_:value: themes.current)`.
            themes.current = id
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(id.previewGradient)
                    .frame(height: 44)
                    .overlay {
                        Image(systemName: id.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(theme.accent, lineWidth: 2.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.accent)
                                .background(Circle().fill(.white))
                                .offset(x: 5, y: -5)
                        }
                    }
                Text(id.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}
