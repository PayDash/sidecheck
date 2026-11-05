@preconcurrency import AppKit

/// Watches the pointer system-wide and fires show/hide callbacks when it
/// dwells in the right-edge hot zone or wanders away from the panel.
///
/// Uses NSEvent monitors only, so no Accessibility/CGEventTap permission is
/// needed. Global monitors don't fire while the pointer is over our own
/// windows (i.e. the panel), which the local monitor covers.
@MainActor
final class EdgeTracker {
    var onShowRequested: ((_ screen: NSScreen) -> Void)?
    var onHideRequested: (() -> Void)?

    /// Returns the panel's current frame (or nil) so the pointer can rest on
    /// the panel without triggering a hide.
    var keepAliveRectProvider: (() -> CGRect?)?

    /// Return false to veto a pending hide (e.g. while the panel is pinned).
    var canHideProvider: (() -> Bool)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var showTimer: Timer?
    private var hideTimer: Timer?

    /// Diagnostics: whether the event monitors are installed.
    private(set) var isRunning = false

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .otherMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async { self?.handlePointerMove() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async { self?.handlePointerMove() }
            return event
        }
        isRunning = true
    }

    func stop() {
        isRunning = false
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        showTimer?.invalidate()
        hideTimer?.invalidate()
        showTimer = nil
        hideTimer = nil
    }

    private func handlePointerMove() {
        let location = NSEvent.mouseLocation

        if let screen = hotZoneScreen(at: location) {
            // Cancel any pending hide and (re)arm the show dwell. If the
            // pointer is already inside the visible panel's edge strip this
            // just re-arms a show that the controller will no-op.
            hideTimer?.invalidate()
            hideTimer = nil
            if showTimer == nil {
                let zoneFrame = screen.frame // CGRect is Sendable; resolve back at fire time
                showTimer = Timer.scheduledTimer(withTimeInterval: Config.showDwellDelay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { // timer runs on the main runloop
                        self?.showTimer = nil
                        let target = NSScreen.screens.first { $0.frame == zoneFrame }
                            ?? NSScreen.withMouse
                            ?? NSScreen.main
                        if let target {
                            self?.onShowRequested?(target)
                        }
                    }
                }
            }
            return
        }

        showTimer?.invalidate()
        showTimer = nil

        if let rect = keepAliveRectProvider?(), rect.contains(location) {
            // Pointer is resting on the panel itself — keep it open.
            hideTimer?.invalidate()
            hideTimer = nil
            return
        }

        // Outside both the hot zone and the panel: hide after a short grace
        // period (a no-op when nothing is visible).
        if hideTimer == nil {
            hideTimer = Timer.scheduledTimer(withTimeInterval: Config.hideDwellDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { // timer runs on the main runloop
                    self?.hideTimer = nil
                    if self?.canHideProvider?() ?? true {
                        self?.onHideRequested?()
                    }
                }
            }
        }
    }

    private func hotZoneScreen(at location: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let halfBand = frame.height * Config.hotZoneVerticalSpan / 2
            let inBand = abs(location.y - frame.midY) <= halfBand
            let atEdge = location.x >= frame.maxX - Config.hotZoneWidth && location.x <= frame.maxX + 1
            if inBand && atEdge {
                return screen
            }
        }
        return nil
    }
}
