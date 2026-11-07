import AppKit
import ServiceManagement

/// Logs main-runloop frame gaps — objective stutter measurement for
/// transition profiling (SIDECHECK_FRAMERATE=1).
final class FrameGapRecorder: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var totalHitches = 0

    func install() {
        // macOS: display links come from NSScreen, not CADisplayLink's iOS init.
        guard let screen = NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        guard last > 0 else { return }
        let gap = now - last
        if gap > 0.025 {
            totalHitches += 1
            fputs(String(format: "[Sidecheck] frame gap %.0f ms (#%d)\n", gap * 1000, totalHitches), stderr)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let panelController = PanelController()
    private var isEnabled = true
    private var themeMenu: NSMenu?
    private var frameGapRecorder: FrameGapRecorder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController.attachPanel()

        let edgeTracker = panelController.edgeTracker
        edgeTracker.onShowRequested = { [weak self] screen in
            guard let self, self.isEnabled else { return }
            self.panelController.showPanel(on: screen)
        }
        edgeTracker.onHideRequested = { [weak self] in
            self?.panelController.hidePanel()
        }
        // Let the pointer rest on the panel itself without triggering a hide.
        edgeTracker.keepAliveRectProvider = { [weak self] in
            self?.panelController.panelFrameIfVisible
        }
        // A pinned panel (or one with keyboard focus) vetoes auto-hide.
        edgeTracker.canHideProvider = { [weak self] in
            guard let self else { return true }
            return !self.panelController.isPinned && !self.panelController.panelIsKeyWindow
        }
        edgeTracker.start()
        panelController.clipboard.startPolling()
        panelController.perf.visibilityProvider = { [weak self] in
            self?.panelController.isVisible ?? false
        }
        panelController.perf.start()
        // Dev/test hook: SIDECHECK_AWAKE=<seconds> starts an Awake session at
        // launch (0 = infinite).
        if let raw = ProcessInfo.processInfo.environment["SIDECHECK_AWAKE"],
           let seconds = TimeInterval(raw) {
            panelController.awake.start(duration: seconds > 0 ? seconds : nil)
        }
        // Dev/test hook: SIDECHECK_FRAMERATE=1 logs main-thread frame gaps
        // (>25 ms = a dropped frame at 30-60 fps) for transition profiling.
        if ProcessInfo.processInfo.environment["SIDECHECK_FRAMERATE"] == "1" {
            let recorder = FrameGapRecorder()
            self.frameGapRecorder = recorder
            recorder.install()
        }
        // Dev/test hook: SIDECHECK_CYCLE=<seconds> toggles the panel every
        // <seconds> after launch, for profiling open/close transitions.
        if let raw = ProcessInfo.processInfo.environment["SIDECHECK_CYCLE"],
           let seconds = TimeInterval(raw), seconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                var show = false
                Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        show.toggle()
                        fputs("[Sidecheck] cycle: \(show ? "show" : "hide")\n", stderr)
                        if show {
                            self.panelController.showPanel()
                        } else {
                            self.panelController.hidePanel(force: true)
                        }
                    }
                }
            }
        }
        setupStatusItem()

        // Dev/test hooks: SIDECHECK_AUTOSHOW=1 pops (and pins) the panel
        // shortly after launch; SIDECHECK_OPENAPP=<appId> navigates there;
        // SIDECHECK_SETTHEME=<themeId> live-switches the theme while open.
        if ProcessInfo.processInfo.environment["SIDECHECK_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.panelController.isPinned = true
                self.panelController.showPanel()
                if let raw = ProcessInfo.processInfo.environment["SIDECHECK_OPENAPP"],
                   let appID = AppID(rawValue: raw) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.panelController.requestedApp = appID
                    }
                }
                if let raw = ProcessInfo.processInfo.environment["SIDECHECK_SETTHEME"],
                   let theme = ThemeID(rawValue: raw) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                        fputs("[Sidecheck] settheme hook: assigning \(theme)\n", stderr)
                        self?.panelController.themeStore.current = theme
                    }
                }
            }
        }
    }

    /// Stop-on-quit policy: an Awake session never outlives the app.
    func applicationWillTerminate(_ notification: Notification) {
        panelController.awake.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "sidebar.trailing",
                accessibilityDescription: "Sidecheck"
            )
        }

        let menu = NSMenu()
        menu.delegate = self // keep toggle states fresh

        let showItem = NSMenuItem(title: "Show panel", action: #selector(showPanelManually), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        let themeMenu = NSMenu(title: "Theme")
        for (index, theme) in ThemeID.allCases.enumerated() {
            let themeItem = NSMenuItem(title: theme.displayName, action: #selector(setTheme(_:)), keyEquivalent: "")
            themeItem.tag = index
            themeItem.target = self
            themeMenu.addItem(themeItem)
        }
        let themeRoot = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeRoot.submenu = themeMenu
        menu.addItem(themeRoot)
        self.themeMenu = themeMenu

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Sidecheck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        refreshMenuStates()
    }

    /// Refreshes Enabled/Theme/Launch states every time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuStates()
    }

    private func refreshMenuStates() {
        for item in (statusItem?.menu?.items ?? []) {
            switch item.title {
            case "Enabled":
                item.state = isEnabled ? .on : .off
            case "Launch at Login":
                item.state = SMAppService.mainApp.status == .enabled ? .on : .off
                item.isEnabled = SMAppService.mainApp.status != .notFound
            default: break
            }
        }
        for (index, theme) in ThemeID.allCases.enumerated() {
            themeMenu?.items[index].state = panelController.themeStore.current == theme ? .on : .off
        }
    }

    @objc private func showPanelManually() {
        panelController.showPanel()
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        if !isEnabled {
            panelController.hidePanel(force: true) // Enabled=off always closes, even when pinned
        }
    }

    @objc private func setTheme(_ sender: NSMenuItem) {
        let all = ThemeID.allCases
        guard sender.tag >= 0 && sender.tag < all.count else { return }
        panelController.themeStore.current = all[sender.tag]
        refreshMenuStates()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            try? service.unregister()
        case .notRegistered, .requiresApproval:
            try? service.register()
        case .notFound:
            break // running outside an app bundle (e.g. `swift run`)
        @unknown default:
            break
        }
        refreshMenuStates()
    }
}
