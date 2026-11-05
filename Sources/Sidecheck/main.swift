import AppKit

// Top-level code runs on the main thread; make that explicit for the
// main-actor-isolated app classes.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
    app.run()
}
