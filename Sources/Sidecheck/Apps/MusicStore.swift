import AppKit
import Foundation

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var artworkURL: String?
    var player: String // "Spotify" or "Music"
}

/// Now-playing state for the Music app. Apple removed third-party access to
/// the system-wide MediaRemote info on macOS 15.4+, so this polls Spotify and
/// Music.app through osascript (one Automation prompt per player, on first
/// use). Polling runs on a background queue and only while the panel is
/// visible; track changes publish immediately, position is interpolated
/// client-side between polls so the page's progress bar can tick at 1 s
/// without extra Apple Events.
@MainActor
final class MusicStore: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var isPlaying = false
    /// Position (s) as of `positionDate` — interpolate with positionNow().
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var artwork: NSImage?
    /// Set when Apple Events were denied (TCC) for a running player.
    @Published private(set) var accessDeniedTo: String?

    private static let players = ["Spotify", "Music"]
    private static let pollInterval: TimeInterval = 3.0

    private var timer: Timer?
    private var queue = DispatchQueue(label: "sidecheck.music-poll", qos: .utility)
    private var pollInFlight = false
    private var trackKey: String?
    private var artworkKey: String?
    private var lastSpawn = Date.distantPast

    /// Performance features drive the visible cadence (3 s fast / 15 s
    /// throttled). Wired in PanelController.init.
    var featuresProvider: (() -> Set<PerformanceFeature>)?

    /// Set from AppDelegate: whether the panel is visible. Drives the adaptive
    /// cadence — 3 s visible, 15 s hidden.
    var visibilityProvider: (() -> Bool)?
    /// Fires on every poll with the current track; ListeningStore accumulates
    /// listening history from it.
    var onTrackObserved: ((TrackInfo, Bool, Date) -> Void)?

    var isPolling: Bool { timer != nil }

    func startPolling() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Position including client-side interpolation since the last poll.
    func positionNow() -> Double {
        guard let track else { return 0 }
        let elapsed = isPlaying ? Date().timeIntervalSince(positionDate) : 0
        return min(max(position + elapsed, 0), track.duration)
    }

    // MARK: Transport (same AppleScript channel as the poll)

    func playPause() {
        send("playpause")
        isPlaying.toggle() // optimistic; the next poll confirms
        positionDate = Date()
    }

    func next() {
        send("next track")
    }

    func previous() {
        send("previous track")
    }

    private func send(_ command: String) {
        guard let player = track?.player else { return }
        queue.async { [weak self] in
            _ = Self.runOSA("tell application \"\(player)\" to \(command)")
        }
    }

    // MARK: Polling

    private func poll() {
        guard !pollInFlight else { return }
        // App-lifetime tracking with an adaptive cadence: 3 s while the panel
        // is visible (15 s with fastMusicPolling off), 15 s hidden, and
        // nothing at all when no player is running (an NSWorkspace check is
        // free next to an osascript spawn).
        let visible = visibilityProvider?() ?? true
        let fast = featuresProvider?().contains(.fastMusicPolling) ?? true
        let interval: TimeInterval = visible ? (fast ? 3 : 15) : 15
        guard Date().timeIntervalSince(lastSpawn) >= interval else { return }
        if !visible {
            guard Self.playerIsRunning() else { return }
        }
        lastSpawn = Date()
        pollInFlight = true
        queue.async { [weak self] in
            let result = Self.runOSA(Self.queryScript)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pollInFlight = false
                self.apply(result)
            }
        }
    }

    private static func playerIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.spotify.client" || app.bundleIdentifier == "com.apple.Music"
        }
    }

    private func apply(_ result: (status: Int32, out: String, err: String)) {
        if result.status != 0, result.err.contains("-1743") {
            accessDeniedTo = result.err.contains("Spotify") ? "Spotify" : "Music"
        }

        var candidates: [TrackInfo] = []
        var playing: [TrackInfo] = []
        for row in result.out.split(separator: "\n") {
            let fields = row.components(separatedBy: "\t")
            guard fields.count >= 7 else { continue }
            let info = TrackInfo(
                title: fields[2].trimmingCharacters(in: .whitespaces),
                artist: fields[3].trimmingCharacters(in: .whitespaces),
                album: fields[4].trimmingCharacters(in: .whitespaces),
                duration: Double(fields[5]) ?? 0,
                artworkURL: fields.count > 7 && fields[7].hasPrefix("http") ? fields[7] : nil,
                player: fields[0]
            )
            guard !info.title.isEmpty, info.duration > 0 else { continue }
            candidates.append(info)
            if fields[1] == "true" { playing.append(info) }
        }

        let current = playing.first ?? candidates.first
        apply(track: current, isPlaying: current != nil && playing.first != nil)

        let positionValue = current.flatMap { info in
            result.out.split(separator: "\n")
                .first { $0.components(separatedBy: "\t").first == info.player }
                .map { Double($0.components(separatedBy: "\t")[6]) ?? 0 }
        } ?? 0
        position = positionValue
        positionDate = Date()
    }

    private func apply(track newTrack: TrackInfo?, isPlaying newIsPlaying: Bool) {
        let key = newTrack.map { "\($0.player)|\($0.title)|\($0.artist)" }
        if key != trackKey {
            trackKey = key
            track = newTrack
            artwork = nil
            artworkKey = nil
            if let urlString = newTrack?.artworkURL {
                loadArtwork(from: urlString, key: key ?? "")
            }
        }
        if isPlaying != newIsPlaying {
            isPlaying = newIsPlaying
        }
        if let current = track {
            onTrackObserved?(current, isPlaying, Date())
        }
    }

    private func loadArtwork(from urlString: String, key: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.artworkKey == key else { return } // superseded
                self.artwork = image
            }
        }.resume()
        artworkKey = key
    }

    // MARK: AppleScript plumbing

    private static func runOSA(_ source: String) -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return (127, "", "\(error)")
        }
        // Read before waitUntilExit so full pipes can't deadlock the child.
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Queries both players; the `is running` check never launches an app, and
    /// each player is wrapped in try so a missing app or a denied Automation
    /// permission just skips that row.
    private static let queryScript = """
    set output to ""
    try
    	if application "Spotify" is running then
    		tell application "Spotify"
    			if player state is playing or player state is paused then
    				set tDur to duration of current track
    				if tDur > 50000 then set tDur to tDur / 1000
    				set output to output & "Spotify" & tab & (player state is playing) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & tDur & tab & (player position) & tab & (artwork url of current track) & linefeed
    			end if
    		end tell
    	end if
    end try
    try
    	if application "Music" is running then
    		tell application "Music"
    			if player state is playing or player state is paused then
    				set output to output & "Music" & tab & (player state is playing) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (duration of current track) & tab & (player position) & tab & "" & linefeed
    			end if
    		end tell
    	end if
    end try
    return output
    """
}
