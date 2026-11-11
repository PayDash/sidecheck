import SwiftUI

/// The panel's home screen: swappable widget slots, the app launcher, and a
/// dock. Layout follows the theme's home template so every theme reuses the
/// same machinery. Hero widgets flex to fill their share of the frame, the
/// launcher sits right below them, and leftover space collects above the
/// dock; overflow scrolls from the top as usual.
struct HomeScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var home: HomeStore
    @EnvironmentObject var controller: PanelController
    @EnvironmentObject var performance: PerformanceStore
    let onOpenApp: (AppID) -> Void
    /// Open choreography flag handed down by PanelView (index 2+ continue
    /// the header/page stagger). Always true when motion is off.
    var entrance = true

    @State private var dockHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        homeContent
    }

    /// Hero widgets flex to fill: the row takes up to ~30% of the space
    /// between header and dock (120–210pt), and the widgets' visuals scale
    /// with it — a taller slot grows the widget, not the empty card. The
    /// launcher sits right below the widgets; leftover space collects at the
    /// bottom, above the dock (home-screen balance).
    private var heroHeight: CGFloat {
        let chrome = theme.showsDock ? dockHeight : 0
        let available = max(0, viewportHeight - chrome - 32)
        return min(max(120, available * 0.30), 210)
    }

    private var heroScale: CGFloat {
        min(1.4, max(1, heroHeight / 130))
    }

    private var homeContent: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        VStack(spacing: 16) {
                            if home.isEditMode {
                                Text("Rebind a widget with its menu button · long-press to leave edit mode")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            widgetRow
                        }
                        .entranceGroup(shown: entrance, index: 2)

                        appArea
                            .entranceGroup(shown: entrance, index: 3)

                        if theme.showsSearchPill {
                            searchPill
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }

                if theme.showsDock {
                    dock
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .background(dockHeightReader)
                        .entranceGroup(shown: entrance, index: 4)
                }
            }
            .onPreferenceChange(DockHeightKey.self) { dockHeight = $0 }
            .onAppear { viewportHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, newValue in viewportHeight = newValue }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(.snappy) { home.isEditMode = true }
        }
    }

    // MARK: height plumbing

    private struct DockHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    private var dockHeightReader: some View {
        GeometryReader { inner in
            Color.clear.preference(key: DockHeightKey.self, value: inner.size.height)
        }
    }

    // MARK: widgets

    @ViewBuilder
    private var widgetRow: some View {
        if theme.stacksWideWidgets {
            // Noir: every slot renders its wide variant, stacked full-width —
            // the two long cards rather than two small ones side by side.
            VStack(spacing: 12) {
                ForEach(home.effectiveSlots.indices, id: \.self) { index in
                    WidgetSlot(index: index, onOpen: onOpenApp, wide: true, heroHeight: 0, heroScale: 1)
                }
            }
            .compositingGroup()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: home.widgetSlots)
        } else {
            // A single slot spans the full width and renders the widget's wide
            // variant; 2+ slots use the compact layouts. EqualHeightRow (not
            // HStack/Grid) so every card gets the row's tallest height proposed
            // back to it — HStack and Grid align smaller siblings instead of
            // proposing the computed height, so `maxHeight: .infinity` alone
            // never equalized bare (non-Button) cards.
            let wide = home.effectiveSlots.count == 1
            EqualHeightRow(spacing: 12) {
                ForEach(home.effectiveSlots.indices, id: \.self) { index in
                    WidgetSlot(index: index, onOpen: onOpenApp, wide: wide, heroHeight: heroHeight, heroScale: heroScale)
                }
            }
            .compositingGroup()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: home.widgetSlots)
        }
    }

    // MARK: app launcher

    /// An HStack whose cells all receive the row's tallest height as their
    /// proposal, so `maxHeight: .infinity` inside any cell stretches it to
    /// match. HStack/Grid align smaller siblings within the row area instead
    /// of proposing the computed height, which is why bare cards (no Button
    /// wrapper) never equalized.
    private struct EqualHeightRow: Layout {
        var spacing: CGFloat = 12

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let width = proposal.width ?? subviews.reduce(0) {
                $0 + $1.sizeThatFits(.unspecified).width
            } + spacing * CGFloat(max(subviews.count - 1, 0))
            let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let maxHeight = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            let cellWidth = (bounds.width - spacing * CGFloat(max(subviews.count - 1, 0)))
                / CGFloat(max(subviews.count, 1))
            var x = bounds.minX
            for subview in subviews {
                subview.place(
                    at: CGPoint(x: x, y: bounds.minY),
                    proposal: ProposedViewSize(width: cellWidth, height: maxHeight)
                )
                x += cellWidth + spacing
            }
        }
    }

    @ViewBuilder
    private var appArea: some View {
        switch theme.homeStyle {
        case .iconTiles: iconGrid
        case .terminalList: terminalList
        }
    }

    private var iconGrid: some View {
        // Tiles scale with the panel-size slider so a larger panel fills with
        // larger icons, not just more empty air (the dock already does this).
        let scale = controller.panelScale
        let cell = 64 * scale
        let spacing: CGFloat = 14
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cell), spacing: spacing)],
            spacing: spacing
        ) {
            ForEach(AppID.allCases) { id in
                Button {
                    onOpenApp(id)
                } label: {
                    AppIconTile(app: PanelApp.app(id), size: 56 * scale)
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var terminalList: some View {
        VStack(spacing: 8) {
            ForEach(AppID.allCases) { id in
                TerminalRow(app: PanelApp.app(id), cursorBlinks: performance.isOn(.microAnimations)) {
                    onOpenApp(id)
                }
            }
        }
    }

    /// One phosphor terminal row. Hovering lights the row and swaps the
    /// chevron for a blinking block cursor — the terminal answering you.
    private struct TerminalRow: View {
        @Environment(\.theme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let app: PanelApp
        let cursorBlinks: Bool
        let action: () -> Void

        @State private var hovered = false
        @State private var blink = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Text("»")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(hovered ? theme.accent : theme.accent.opacity(0.7))
                        .themeGlow(theme)
                    Text(app.name.uppercased())
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    if hovered {
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: 7, height: 12)
                            .opacity(blink ? 0.15 : 1)
                            .animation(
                                cursorBlinks && !reduceMotion
                                    ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                                    : nil,
                                value: blink
                            )
                            .onAppear { blink = true }
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    hovered ? theme.accent.opacity(0.10) : theme.cardFill,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(hovered ? theme.accent.opacity(0.4) : theme.cardStroke, lineWidth: 1)
                )
            }
            .buttonStyle(.pressable)
            .onHover { hovered = $0 }
            .animation(PanelMotion.hover, value: hovered)
        }
    }

    // MARK: decorations

    private var searchPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text("Search")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(theme.cardFill))
        .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
        .help("Just for the vibe")
    }

    /// Quick-launch dock. Settings lives in the panel header's gear instead.
    private static let dockApps: [AppID] = [.monitor, .clipboard, .wallpaper, .awake]

    private var dock: some View {
        // Tile size adapts to the app count (and panel scale) so this HStack
        // always fits: its fixed-width tiles are incompressible, and an
        // oversized dock widens the whole home VStack — clipping every page
        // ~20 pt per side (the six-icon regression).
        let count = CGFloat(Self.dockApps.count)
        let spacing: CGFloat = Self.dockApps.count > 5 ? 14 : 20
        let available = theme.frameSize.width * controller.panelScale - 76 // outer 16×2 + dock padding 22×2
        let size = min(46, max(30, (available - spacing * (count - 1)) / count))
        return HStack(spacing: spacing) {
            ForEach(Self.dockApps) { id in
                Button {
                    onOpenApp(id)
                } label: {
                    AppIconTile(app: PanelApp.app(id), size: size, showsLabel: false)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.cardFill)
                .shadow(color: .black.opacity(theme.isLight ? 0.08 : 0.3), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }
}
