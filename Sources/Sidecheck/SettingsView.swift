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

                sectionLabel("HOME WIDGETS")
                slotControls

                Text("Sidecheck v0.3 — apps, themes, endless knobs")
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

    // MARK: Home widget slots

    private var slotControls: some View {
        VStack(spacing: 8) {
            ForEach(home.widgetSlots.indices, id: \.self) { index in
                HStack {
                    Text("Slot \(index + 1)")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
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
            Text("Long-press a home widget to rebind it in place.")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
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
