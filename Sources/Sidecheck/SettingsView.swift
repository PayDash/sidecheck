import SwiftUI

/// In-panel settings: appearance, panel customization (size/animation),
/// home widget slots, and about. Rendered inside the Settings app page.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var controller: PanelController
    @EnvironmentObject var home: HomeStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("APPEARANCE")
                themeGrid

                sectionLabel("PANEL")
                panelControls

                sectionLabel("EDGE ZONE")
                edgeControls

                sectionLabel("HOME WIDGETS")
                slotControls

                sectionLabel("ALERTS")
                alertControls

                Text("Sidecheck v0.4 — clipboard, morphing themes, edge tuning")
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
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
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
                Slider(value: $controller.panelScale, in: Config.panelScaleRange)

                Text("Open / close animation")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Picker("", selection: $controller.animationStyle) {
                    ForEach(PanelAnimationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

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
                Slider(value: $controller.animationSpeed, in: Config.animationSpeedRange)
            }
        }
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
            Slider(value: value, in: range)
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
                Slider(
                    value: Binding(
                        get: { Double(home.slotCount) },
                        set: { home.slotCount = Int($0.rounded()) }
                    ),
                    in: Double(Config.slotCountRange.lowerBound)...Double(Config.slotCountRange.upperBound),
                    step: 1
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.cardFill, in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                    .strokeBorder(theme.cardStroke, lineWidth: 1)
            )

            ForEach(home.widgetSlots.indices, id: \.self) { index in
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
                .background(theme.cardFill, in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
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
            slotMoveButton(index: index, direction: 1, enabled: index < home.widgetSlots.count - 1)
        }
    }

    private func slotMoveButton(index: Int, direction: Int, enabled: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                home.move(slot: index, direction: direction)
            }
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

    // MARK: Alerts

    private var alertControls: some View {
        ThemedCard {
            Toggle(isOn: Binding(
                get: { controller.alerter.isEnabled },
                set: { controller.alerter.isEnabled = $0 }
            )) {
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
                }
            }
            .toggleStyle(.switch)
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
                    .font(.system(size: 8, weight: .bold))
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
                            .foregroundStyle(
                                id == .ipad
                                    ? Color.black.opacity(0.55)
                                    : Color.white.opacity(0.9)
                            )
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
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}
