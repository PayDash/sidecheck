import AppKit

// @main form (not top-level main.swift code) so the executable module is
// importable from the test target. Runs on the main thread — made explicit
// for the main-actor-isolated app classes.
@main
struct SidecheckApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let appDelegate = AppDelegate()
            app.delegate = appDelegate
            app.setActivationPolicy(.accessory) // menu-bar app, no Dock icon
            app.run()
        }
    }
}
