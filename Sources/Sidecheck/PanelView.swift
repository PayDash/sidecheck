import SwiftUI
import AppKit

/// The panel shell: themed background, header, and a two-level page system —
/// the home screen and full app pages.
struct PanelView: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var stats: StatsStore
    @ObservedObject var themes: ThemeStore
    @ObservedObject var home: HomeStore
    @ObservedObject var wallpaper: WallpaperStore
    @ObservedObject var awake: AwakeStore
    @ObservedObject var screenTime: ScreenTimeStore
    @ObservedObject var processes: ProcessStore
    @ObservedObject var music: MusicStore
    @ObservedObject var listening: ListeningStore
    @ObservedObject var statsFm: StatsFmProvider
    @ObservedObject var performance: PerformanceStore
    @ObservedObject var tokscale: TokscaleStore

    private var theme: ThemeSpec { themes.current.spec }

    private enum Page: Equatable {
        case home
        case app(AppID)
    }

    @State private var page: Page = .home
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Open choreography: groups settle in with a stagger once per show.
    /// Resets silently while hidden; State resets to true on theme remounts,
    /// so theme morphs never replay the stagger.
    @State private var entranceShown = true
    @State private var bootShimmerActive = false

    /// Saver mode reuses the Reduce-Motion pathways: instant movement, no
    /// micro-animations. (Background freezing is handled inside
    /// PanelBackgroundView via `mode`.)
    private var effectsOff: Bool { reduceMotion || !performance.isOn(.panelMovement) }

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
                .animation(effectsOff ? nil : .easeInOut(duration: Config.themeMorphDuration), value: themes.current)
        }
        // Fill the hosting view rather than pinning a fixed frame: the window
        // is the sizing authority, and on a theme switch PanelController
        // animates the window frame over Config.themeMorphDuration — content
        // that fills the window morphs with it instead of fighting it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.panelRadius, style: .continuous)
                .strokeBorder(panelRim, lineWidth: 1)
        )
        .overlay {
            // One CRT power-on sweep per open, phosphor themes only.
            if bootShimmerActive {
                BootShimmerBand(accent: theme.accent)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .environmentObject(controller)
        .environmentObject(stats)
        .environmentObject(themes)
        .environmentObject(home)
        .environmentObject(controller.clipboard)
        .environmentObject(controller.wallpaper)
        .environmentObject(controller.awake)
        .environmentObject(controller.screenTime)
        .environmentObject(controller.processes)
        .environmentObject(controller.music)
        .environmentObject(controller.listening)
        .environmentObject(controller.statsFm)
        .environmentObject(controller.performance)
        .environmentObject(controller.tokscale)
        .environmentObject(controller.perf)
        // entrance choreography: content springs in while the window appears
        .opacity(controller.isVisible ? 1 : 0)
        .scaleEffect(controller.isVisible || effectsOff ? 1 : entranceScale, anchor: .trailing)
        .animation(effectsOff ? .linear(duration: 0.12) : entranceSpring, value: controller.isVisible)
        .onChange(of: controller.isVisible) { _, visible in
            guard visible else { return }
            if !effectsOff {
                entranceShown = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    MainActor.assumeIsolated { entranceShown = true }
                }
            }
            if themes.current.spec.bootShimmer, !effectsOff, performance.isOn(.microAnimations) {
                bootShimmerActive = true
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    bootShimmerActive = false
                }
            }
        }
        .onChange(of: controller.requestedApp) { _, newValue in
            guard let appID = newValue else { return }
            withAnimation(effectsOff ? nil : .spring(response: 0.42, dampingFraction: 0.88)) {
                page = .app(appID)
            }
            controller.requestedApp = nil
        }
    }

    /// Lit themes: a rim that catches light from the top-leading corner and
    /// falls off toward the bottom — reads as one lit glass object. Flat
    /// themes keep their declared stroke.
    private var panelRim: AnyShapeStyle {
        if themes.current.spec.litPanelBorder {
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.30), Color.white.opacity(0.10), Color.white.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        }
        if theme.isLight { return AnyShapeStyle(Color.white.opacity(0.6)) }
        return AnyShapeStyle(Color.white.opacity(0.10))
    }

    /// One phosphor band washing down the panel — CRT power-on.
    private struct BootShimmerBand: View {
        let accent: Color
        @State private var swept = false

        var body: some View {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, accent.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .offset(y: swept ? geo.size.height + 140 : -140)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { swept = true }
            }
        }
    }

    /// Everything theme-derived lives here, keyed by theme identity: on a
    /// theme switch the old copy fades out while the new one fades in, so
    /// colors/materials morph smoothly without any snapshot or freeze.
    private var themedPanel: some View {
        let spec = themes.current.spec
        return ZStack {
            // Wallpaper (per theme) drives the background; animated kinds stay
            // paused once the panel is fully hidden (or under Reduce Motion) —
            // but NOT during the open/close transition, so video wallpapers
            // keep playing through the slide instead of freezing mid-motion.
            // Fully-hidden pausing preserves the perf invariant from the
            // diagnostics era (≈0% CPU while hidden).
            let wallpaperSpec = wallpaper.spec(for: themes.current)
            PanelBackgroundView(spec: wallpaperSpec, themeID: themes.current, paused: reduceMotion || controller.isFullyHidden, features: performance.activeFeatures)
                .id(wallpaperSpec)
                .transition(.opacity)
                .animation(effectsOff ? nil : .easeInOut(duration: 0.25), value: wallpaperSpec)

            VStack(spacing: 0) {
                header
                    .entranceGroup(shown: effectsOff ? true : entranceShown, index: 0)
                Rectangle()
                    .fill(spec.divider)
                    .frame(height: 1)
                ZStack {
                    switch page {
                    case .home:
                        HomeScreen(onOpenApp: openApp, entrance: effectsOff ? true : entranceShown)
                            .transition(pageTransition(edge: .leading))
                    case .app(let appID):
                        appID.fullView
                            .transition(pageTransition(edge: .trailing))
                    }
                }
                .animation(effectsOff ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: page)
                .entranceGroup(shown: effectsOff ? true : entranceShown, index: 1)
            }
        }
        .foregroundStyle(spec.textPrimary)
        .environment(\.theme, spec)
    }

    // MARK: Navigation

    private func openApp(_ id: AppID) {
        withAnimation(effectsOff ? nil : .spring(response: 0.42, dampingFraction: 0.88)) {
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
        if effectsOff {
            return .asymmetric(insertion: .opacity, removal: .opacity)
        }
        // Incoming page slides in; outgoing slides out while receding a touch
        // in scale — depth instead of a flat swap.
        let insertion = AnyTransition.move(edge: edge).combined(with: .opacity)
        let removal = AnyTransition.move(edge: edge)
            .combined(with: .scale(scale: 0.96, anchor: .center))
            .combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    // MARK: Header

    /// Home-header clock — digits only ("4:06"); the AM/PM tail dragged the
    /// centered clock's weight off balance.
    private static let homeClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var header: some View {
        HStack(spacing: 10) {
            pinButton
            if case .home = page, theme.showsClockInHeader {
                // Noir-style home header: the wordmark trades its spot for a
                // live clock, centered between pin and gear (ticks 1 Hz while
                // visible, pauses hidden).
                Spacer(minLength: 0)
                TimelineView(.animation(minimumInterval: 1.0, paused: controller.isFullyHidden)) { context in
                    Text(Self.homeClockFormatter.string(from: context.date))
                        .font(.system(size: 22, weight: .regular, design: theme.fontDesign))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        // Softer, two-pass glow — the standard themeGlow smears
                        // serif digits at this size.
                        .shadow(color: Color.white.opacity(0.26), radius: 4)
                        .shadow(color: Color.white.opacity(0.3), radius: 1.2)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            } else {
                Text(pageTitle)
                    .font(.system(size: 15, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
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
                // A small bounce confirms the state change (Reduce Motion
                // keeps the value constant, so the effect never triggers).
                .symbolEffect(.bounce, value: controller.isPinned && !reduceMotion)
                .padding(6)
                .background(
                    Circle().fill(controller.isPinned ? theme.accent.opacity(0.16) : .clear)
                )
        }
        .buttonStyle(.pressable)
        .help(controller.isPinned ? "Unpin — auto-hide on leave" : "Pin — keep panel open")
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
        .buttonStyle(.pressable)
        .help("Leave edit mode")
    }

    private var backButton: some View {
        Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { page = .home }
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(6)
        }
        .buttonStyle(.pressable)
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
        .buttonStyle(.pressable)
        .help("Settings")
    }
}
