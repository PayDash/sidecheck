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
                VStack(spacing: 18) {
                    if home.isEditMode {
                        Text("Tap a widget to rebind it · long-press to leave edit mode")
                            .font(.system(size: 10.5))
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
                    .padding(.bottom, 14)
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            withAnimation(.snappy) { home.isEditMode = true }
        }
    }

    // MARK: widgets

    private var widgetRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(home.effectiveSlots.indices, id: \.self) { index in
                WidgetSlot(index: index, onOpen: onOpenApp)
                    .frame(maxWidth: .infinity)
            }
        }
        .compositingGroup()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: home.widgetSlots)
    }

    // MARK: app launcher

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
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.accent)
                        Text(PanelApp.app(id).name.uppercased())
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.cardFill, in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardRadius * 0.6, style: .continuous)
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
        .padding(.vertical, 7)
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
