import SwiftUI

/// The panel's home screen: swappable widget slots, the app launcher, and a
/// dock. Layout follows the theme's home template so every theme reuses the
/// same machinery.
struct HomeScreen: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var home: HomeStore
    @EnvironmentObject var controller: PanelController
    let onOpenApp: (AppID) -> Void

    var body: some View {
        homeContent
    }

    private var homeContent: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if home.isEditMode {
                        Text("Rebind a widget with its menu button · long-press to leave edit mode")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                    widgetRow
                    appArea
                    if theme.showsSearchPill {
                        searchPill
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            if theme.showsDock {
                dock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(.snappy) { home.isEditMode = true }
        }
    }

    // MARK: widgets

    private var widgetRow: some View {
        // A single slot spans the full width and renders the widget's wide
        // variant; 2+ slots use the compact layouts. EqualHeightRow (not
        // HStack/Grid) so every card gets the row's tallest height proposed
        // back to it — HStack and Grid align smaller siblings instead of
        // proposing the computed height, so `maxHeight: .infinity` alone
        // never equalized bare (non-Button) cards.
        let wide = home.effectiveSlots.count == 1
        return EqualHeightRow(spacing: 12) {
            ForEach(home.effectiveSlots.indices, id: \.self) { index in
                WidgetSlot(index: index, onOpen: onOpenApp, wide: wide)
            }
        }
        .compositingGroup()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: home.widgetSlots)
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 64), spacing: 14)],
            spacing: 14
        ) {
            ForEach(AppID.allCases) { id in
                Button {
                    onOpenApp(id)
                } label: {
                    AppIconTile(app: PanelApp.app(id))
                }
                .buttonStyle(.plain)
                .jiggle(active: home.isEditMode)
            }
        }
    }

    private var terminalList: some View {
        VStack(spacing: 8) {
            ForEach(AppID.allCases) { id in
                Button {
                    onOpenApp(id)
                } label: {
                    HStack(spacing: 10) {
                        Text("»")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.accent)
                        Text(PanelApp.app(id).name.uppercased())
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.cardStroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
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
                .buttonStyle(.plain)
                .jiggle(active: home.isEditMode)
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
