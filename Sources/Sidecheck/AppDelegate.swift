import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let panelController = PanelController()
    private let edgeTracker = EdgeTracker()
    private var isEnabled = true
    private var themeMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController.attachPanel()

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
        // A pinned panel vetoes auto-hide.
        edgeTracker.canHideProvider = { [weak self] in
            guard let self else { return true }
            return !self.panelController.isPinned
        }
        edgeTracker.start()
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
