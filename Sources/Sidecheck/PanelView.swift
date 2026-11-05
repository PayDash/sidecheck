import SwiftUI
import AppKit

/// The panel shell: themed background, header, and a two-level page system —
/// the home screen and full app pages.
struct PanelView: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var stats: StatsStore
    @ObservedObject var themes: ThemeStore
    @ObservedObject var home: HomeStore

    private var theme: ThemeSpec { themes.current.spec }

    private enum Page: Equatable {
        case home
        case app(AppID)
    }

    @State private var page: Page = .home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Entrance choreography follows the chosen animation preset.
    private var entranceSpring: Animation {
        switch controller.animationStyle {
        case .slide: .spring(response: 0.38, dampingFraction: 0.82)
        case .pop: .spring(response: 0.4, dampingFraction: 0.7)
        case .zoom: .spring(response: 0.32, dampingFraction: 0.75)
        }
    }

    private var entranceScale: CGFloat {
        controller.animationStyle == .zoom ? 0.82 : 0.94
    }

    var body: some View {
        ZStack {
            themedPanel
                .id(themes.current)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: Config.themeMorphDuration), value: themes.current)
        }
        // Fill the hosting view rather than pinning a fixed frame: the window
        // is the sizing authority, and on a theme switch PanelController
        // animates the window frame over Config.themeMorphDuration — content
        // that fills the window morphs with it instead of fighting it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous)
                .strokeBorder(theme.isLight ? Color.white.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 1)
        )
        .environmentObject(controller)
        .environmentObject(stats)
        .environmentObject(themes)
        .environmentObject(home)
        .environmentObject(controller.clipboard)
        .environmentObject(controller.perf)
        // entrance choreography: content springs in while the window appears
        .opacity(controller.isVisible ? 1 : 0)
        .scaleEffect(controller.isVisible || reduceMotion ? 1 : entranceScale, anchor: .trailing)
        .animation(reduceMotion ? .linear(duration: 0.12) : entranceSpring, value: controller.isVisible)
        .onChange(of: controller.requestedApp) { _, newValue in
            guard let appID = newValue else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                page = .app(appID)
            }
            controller.requestedApp = nil
        }
    }

    /// Everything theme-derived lives here, keyed by theme identity: on a
    /// theme switch the old copy fades out while the new one fades in, so
    /// colors/materials morph smoothly without any snapshot or freeze.
    private var themedPanel: some View {
        let spec = themes.current.spec
        return ZStack {
            // Pause the animated backgrounds whenever the panel can't be seen
            // (hidden window) or shouldn't move (Reduce Motion) — otherwise
            // TimelineView keeps rendering at display rate for nothing, which
            // the diagnostics showed as ~8% CPU + ~60 wakeups/s while hidden.
            ThemeBackground(id: themes.current, paused: reduceMotion || !controller.isVisible)

            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(spec.divider)
                    .frame(height: 1)
                ZStack {
                    switch page {
                    case .home:
                        HomeScreen(onOpenApp: openApp)
                            .transition(pageTransition(edge: .leading))
                    case .app(let appID):
                        appID.fullView
                            .transition(pageTransition(edge: .trailing))
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.88), value: page)
            }
        }
        .foregroundStyle(spec.textPrimary)
        .environment(\.theme, spec)
    }

    // MARK: Navigation

    private func openApp(_ id: AppID) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            page = .app(id)
        }
    }

    private var pageTitle: String {
        switch page {
        case .home: "Sidecheck"
        case .app(let id): PanelApp.app(id).name
        }
    }

    private func pageTransition(edge: Edge) -> AnyTransition {
        let move = reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: edge).combined(with: .opacity)
        return .asymmetric(insertion: move, removal: move)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            pinButton
            Text(pageTitle)
                .font(.system(size: 15, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if theme.showsClockInHeader {
                clockChip
            }
            if home.isEditMode, page == .home {
                doneButton
            }
            if case .app = page {
                backButton
            }
            settingsButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var pinButton: some View {
        Button {
            controller.isPinned.toggle()
        } label: {
            Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(controller.isPinned ? theme.accent : theme.textSecondary)
                .padding(6)
                .background(
                    Circle().fill(controller.isPinned ? theme.accent.opacity(0.16) : .clear)
                )
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce, value: controller.isPinned)
        .help(controller.isPinned ? "Unpin — auto-hide on leave" : "Pin — keep panel open")
    }

    private var clockChip: some View {
        Text(Date(), style: .time)
            .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            .monospacedDigit()
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(theme.cardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
    }

    private var doneButton: some View {
        Button {
            withAnimation(.snappy) { home.isEditMode = false }
        } label: {
            Text("Done")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accent)
                .padding(6)
        }
        .buttonStyle(.plain)
        .help("Leave edit mode")
    }

    private var backButton: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { page = .home }
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.textSecondary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .help("Home")
    }

    private var settingsButton: some View {
        let settingsOpen = page == .app(.settings)
        return Button {
            openApp(.settings)
        } label: {
            Image(systemName: settingsOpen ? "gearshape.fill" : "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settingsOpen ? theme.accent : theme.textSecondary)
                .padding(6)
        }
        .buttonStyle(.plain)
        .help("Settings")
    }
}
