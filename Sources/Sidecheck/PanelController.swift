import AppKit
import SwiftUI
import Combine

/// Open/close animation presets for the panel.
enum PanelAnimationStyle: String, CaseIterable, Identifiable {
    case slide // slides out of the screen edge
    case pop   // fades in place; content springs bouncily
    case zoom  // grows from the screen edge, Control Center-ish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slide: "Slide"
        case .pop: "Pop"
        case .zoom: "Zoom"
        }
    }
}

/// Owns the pop-out NSPanel, the stores, the pin state, and the panel
/// customization (size scale + animation presets).
@MainActor
final class PanelController: ObservableObject {
    private lazy var panel: NSPanel = {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: currentFrameSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Sidecheck"
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.isMovable = false
        p.becomesKeyOnlyIfNeeded = true
        p.acceptsMouseMovedEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }()

    let statsStore = StatsStore()
    let themeStore = ThemeStore()
    let homeStore = HomeStore()
    let clipboard = ClipboardStore()
    let alerter = BatteryAlerter()
    let perf = PerfStore()
    let edgeTracker = EdgeTracker()

    @Published private(set) var isVisible = false
    @Published var isPinned = false

    /// Test hook: the SwiftUI root navigates to this app when set.
    @Published var requestedApp: AppID?

    @Published var panelScale: Double {
        didSet {
            UserDefaults.standard.set(panelScale, forKey: "panelScale")
            // Instant, not animated: the SwiftUI content re-renders on the
            // same tick, so window and content stay in lockstep during
            // slider drags.
            refreshFrame(animated: false)
        }
    }
    @Published var animationStyle: PanelAnimationStyle {
        didSet { UserDefaults.standard.set(animationStyle.rawValue, forKey: "panelAnimationStyle") }
    }
    @Published var animationSpeed: Double {
        didSet { UserDefaults.standard.set(animationSpeed, forKey: "panelAnimationSpeed") }
    }

    // Live edge/hot-zone tuning — EdgeTracker reads these values through
    // Config, so each didSet also pushes into the static Config vars.
    @Published var hotZoneWidth: Double {
        didSet {
            Config.hotZoneWidth = hotZoneWidth
            UserDefaults.standard.set(hotZoneWidth, forKey: "hotZoneWidth")
        }
    }
    @Published var hotZoneSpan: Double {
        didSet {
            Config.hotZoneVerticalSpan = hotZoneSpan
            UserDefaults.standard.set(hotZoneSpan, forKey: "hotZoneSpan")
        }
    }
    @Published var showDwellDelay: Double {
        didSet {
            Config.showDwellDelay = showDwellDelay
            UserDefaults.standard.set(showDwellDelay, forKey: "showDwellDelay")
        }
    }
    @Published var hideDwellDelay: Double {
        didSet {
            Config.hideDwellDelay = hideDwellDelay
            UserDefaults.standard.set(hideDwellDelay, forKey: "hideDwellDelay")
        }
    }

    private var currentScreen: NSScreen?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let defaults = UserDefaults.standard
        // Accept numeric strings too (e.g. `defaults write` writes strings).
        let scaleObject = defaults.object(forKey: "panelScale")
        panelScale = (scaleObject as? Double) ?? (scaleObject as? NSString)?.doubleValue ?? 1.0
        animationStyle = defaults.string(forKey: "panelAnimationStyle").flatMap(PanelAnimationStyle.init(rawValue:)) ?? .slide
        let speedObject = defaults.object(forKey: "panelAnimationSpeed")
        animationSpeed = (speedObject as? Double) ?? (speedObject as? NSString)?.doubleValue ?? 0.25

        func loadNumber(_ key: String, _ fallback: Double) -> Double {
            let object = defaults.object(forKey: key)
            return (object as? Double) ?? (object as? NSString)?.doubleValue ?? fallback
        }
        hotZoneWidth = loadNumber("hotZoneWidth", Double(Config.hotZoneWidth))
        hotZoneSpan = loadNumber("hotZoneSpan", Double(Config.hotZoneVerticalSpan))
        showDwellDelay = loadNumber("showDwellDelay", Config.showDwellDelay)
        hideDwellDelay = loadNumber("hideDwellDelay", Config.hideDwellDelay)
        // didSet doesn't fire during init — push the loaded values into
        // Config explicitly so EdgeTracker reads the persisted tuning.
        Config.hotZoneWidth = hotZoneWidth
        Config.hotZoneVerticalSpan = hotZoneSpan
        Config.showDwellDelay = showDwellDelay
        Config.hideDwellDelay = hideDwellDelay

        // Theme switch while visible: on the next runloop tick (when the
        // published change has settled) morph the window to the new theme's
        // exact frame — animated, in sync with the SwiftUI content crossfade
        // (PanelView keys its transition on the same theme change). No
        // snapshots, no competing animations; both halves share
        // Config.themeMorphDuration.
        themeStore.$current
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.applySystemAppearance()
                    self.refreshFrame(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                }
            }
            .store(in: &cancellables)
    }

    /// Called once by the app delegate after init, when `self` is fully
    /// initialized and can be captured by the SwiftUI root view.
    func attachPanel() {
        let hostingView = NSHostingView(
            rootView: PanelView(controller: self, stats: statsStore, themes: themeStore, home: homeStore)
        )
        // The window is the single sizing authority (edge-anchored, centered).
        // Without this, the hosting view pushes its SwiftUI ideal size into
        // `window.setContentSize`, which resizes anchored to the TOP-LEFT and
        // wrecks the edge-flush position on every theme/frame change.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        applySystemAppearance()
    }

    /// Light themes draw light system controls: without this, the segmented
    /// picker/sliders/menus render with the system (dark) appearance and
    /// their labels vanish on light backgrounds.
    private func applySystemAppearance() {
        panel.appearance = NSAppearance(named: themeStore.current.spec.isLight ? .aqua : .darkAqua)
    }

    /// The panel's frame while visible — the pointer may rest inside it
    /// without triggering a hide.
    var panelFrameIfVisible: CGRect? {
        isVisible ? panel.frame : nil
    }

    /// True while a panel control holds keyboard focus (e.g. the clipboard
    /// search field) — auto-hide should wait until the user clicks away.
    var panelIsKeyWindow: Bool {
        panel.isKeyWindow
    }

    /// Current on-screen panel size: theme frame × user scale, clamped to
    /// the target screen's usable height.
    var currentFrameSize: CGSize {
        let base = themeStore.current.spec.frameSize
        let scaled = CGSize(width: base.width * panelScale, height: base.height * panelScale)
        if let screen = currentScreen ?? NSScreen.main {
            let maxHeight = screen.visibleFrame.height - 40
            if scaled.height > maxHeight, scaled.height > 0 {
                let factor = maxHeight / scaled.height
                return CGSize(width: scaled.width * factor, height: maxHeight)
            }
        }
        return scaled
    }

    func showPanel(on screen: NSScreen? = nil) {
        guard !isVisible else { return }
        guard let target = screen ?? NSScreen.withMouse ?? NSScreen.main else { return }

        isVisible = true
        currentScreen = target
        let shown = shownFrame(on: target)
        statsStore.startSampling()

        switch animationStyle {
        case .slide:
            let hidden = shown.offsetBy(dx: shown.width + Config.edgeMargin + 8, dy: 0)
            panel.setFrame(hidden, display: false)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            animateFrame(to: shown, timing: .easeOut)
        case .pop, .zoom:
            panel.setFrame(shown, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animateAlpha(to: 1, timing: .easeOut)
        }
        fputs("[Sidecheck] panel shown on \(target.localizedName)\n", stderr)
    }

    func hidePanel(force: Bool = false) {
        guard isVisible else { return }
        guard force || !isPinned else { return } // pinned panels stay put
        isVisible = false

        switch animationStyle {
        case .slide:
            let hidden = panel.frame.offsetBy(dx: panel.frame.width + 8, dy: 0)
            animateFrame(to: hidden, timing: .easeIn) {
                guard !self.isVisible else { return } // re-shown mid-animation
                self.panel.orderOut(nil)
                self.statsStore.stopSampling()
            }
        case .pop, .zoom:
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = animationSpeed
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isVisible else { return } // re-shown mid-animation
                    self.panel.orderOut(nil)
                    self.panel.alphaValue = 1
                    self.statsStore.stopSampling()
                }
            })
        }
        fputs("[Sidecheck] panel hidden\n", stderr)
    }

    /// Re-frames the visible panel. Instant for scrubbing-style changes
    /// (panel scale) where content re-renders on the same tick; animated for
    /// theme switches, where the SwiftUI content is crossfading over the same
    /// `Config.themeMorphDuration` — the two morph together as one panel.
    func refreshFrame(animated: Bool) {
        guard isVisible, let screen = currentScreen else { return }
        let target = shownFrame(on: screen)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateFrame(to: target, timing: .easeInEaseOut, duration: Config.themeMorphDuration)
        } else {
            panel.setFrame(target, display: true)
            panel.invalidateShadow()
        }
    }

    // MARK: - Animation plumbing

    private func animateFrame(to frame: CGRect, timing: CAMediaTimingFunctionName, duration: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration ?? animationSpeed
            context.timingFunction = CAMediaTimingFunction(name: timing)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.invalidateShadow()
                completion?()
            }
        })
    }

    private func animateAlpha(to value: CGFloat, timing: CAMediaTimingFunctionName) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationSpeed
            context.timingFunction = CAMediaTimingFunction(name: timing)
            panel.animator().alphaValue = value
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        })
    }

    private func shownFrame(on screen: NSScreen) -> CGRect {
        let size = currentFrameSize
        let x = screen.frame.maxX - size.width - Config.edgeMargin
        let y = screen.frame.midY - size.height / 2
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

extension NSScreen {
    /// The screen the pointer is currently on, if any.
    static var withMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) }
    }
}
