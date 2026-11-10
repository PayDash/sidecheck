import Darwin
import Foundation

/// Keeps the Mac awake by running /usr/bin/caffeinate as a child process.
///
/// Flags: `-i` (idle sleep), `-m` (disk), `-s` (system sleep — the assertion
/// that survives lid closure, honored by macOS only on AC power) and
/// optionally `-d` (display). Timed sessions pass `-t <seconds>`; infinite
/// sessions run without it. Sessions stop when Sidecheck quits; a stale child
/// from a crashed run is cleaned up on the next launch.
@MainActor
final class AwakeStore: ObservableObject {
    static let keepsDisplayKey = "awakeKeepsDisplay"
    static let pidKey = "awakePID"
    static let caffeinatePath = "/usr/bin/caffeinate"

    @Published private(set) var isActive = false
    /// nil while active means "infinite".
    @Published private(set) var endDate: Date?
    /// Total length of the current timed session (nil = infinite), for the countdown ring.
    @Published private(set) var sessionDuration: TimeInterval?
    @Published var keepsDisplayAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepsDisplayAwake, forKey: Self.keepsDisplayKey)
            // Apply immediately — restart the assertion with the new flags.
            if isActive {
                restart()
            }
        }
    }

    private var process: Process?

    init() {
        keepsDisplayAwake = UserDefaults.standard.object(forKey: Self.keepsDisplayKey) as? Bool ?? true
        Self.terminateStaleChild()
    }

    /// Duration nil = infinite.
    func start(duration: TimeInterval?) {
        stop()
        spawn(duration: duration)
    }

    func stop() {
        guard let process else {
            isActive = false
            endDate = nil
            sessionDuration = nil
            return
        }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
        isActive = false
        endDate = nil
        sessionDuration = nil
        UserDefaults.standard.removeObject(forKey: Self.pidKey)
        fputs("[Sidecheck] awake: stopped\n", stderr)
    }

    var remaining: TimeInterval? {
        guard isActive, let endDate else { return nil }
        return max(0, endDate.timeIntervalSinceNow)
    }

    private func restart() {
        guard isActive else { return }
        let duration = endDate.map { $0.timeIntervalSinceNow }
        spawn(duration: (duration ?? 0) > 1 ? duration : nil)
    }

    private func spawn(duration: TimeInterval?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.caffeinatePath)
        var arguments = ["-i", "-m", "-s"]
        if keepsDisplayAwake {
            arguments.append("-d")
        }
        if let duration {
            arguments += ["-t", String(Int(duration.rounded()))]
        }
        process.arguments = arguments
        // The termination handler fires on a Foundation background thread —
        // hop to the main actor with a Task (MainActor.assumeIsolated traps
        // off-main, which killed the app on every stop/restart).
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, self.process === process else { return } // replaced or already stopped
                self.process = nil
                self.isActive = false
                self.endDate = nil
                self.sessionDuration = nil
                UserDefaults.standard.removeObject(forKey: Self.pidKey)
                fputs("[Sidecheck] awake: session ended (status \(process.terminationStatus))\n", stderr)
            }
        }
        do {
            try process.run()
        } catch {
            fputs("[Sidecheck] awake: failed to launch caffeinate — \(error)\n", stderr)
            return
        }
        self.process = process
        isActive = true
        endDate = duration.map { Date().addingTimeInterval($0) }
        sessionDuration = duration
        UserDefaults.standard.set(process.processIdentifier, forKey: Self.pidKey)
        fputs("[Sidecheck] awake: started pid \(process.processIdentifier) (\(arguments.joined(separator: " ")))\n", stderr)
    }

    /// If a previous run crashed (or the user force-killed Sidecheck) while a
    /// session was active, the caffeinate child may still be alive — kill it.
    /// The stored pid may have been recycled by any other process in the
    /// meantime, so it is killed only if it still is caffeinate.
    private static func terminateStaleChild() {
        let defaults = UserDefaults.standard
        let pid = defaults.integer(forKey: pidKey)
        guard pid > 0 else { return }
        defaults.removeObject(forKey: pidKey)
        var path = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid_t(pid), &path, UInt32(path.count)) > 0 else {
            fputs("[Sidecheck] awake: stale pid \(pid) is gone — nothing to clean up\n", stderr)
            return
        }
        guard String(cString: path).split(separator: "/").last == "caffeinate" else {
            fputs("[Sidecheck] awake: stale pid \(pid) was recycled — not killing\n", stderr)
            return
        }
        kill(pid_t(pid), SIGTERM)
        fputs("[Sidecheck] awake: cleaned up stale session (pid \(pid))\n", stderr)
    }
}
