import Foundation

/// One track heard on this Mac, accumulated from the MusicStore poll.
struct HeardTrack: Codable, Identifiable {
    var key: String // player|title|artist
    var title: String
    var artist: String
    var album: String
    var artworkURL: String?
    var player: String
    var firstHeard: Date
    var lastHeard: Date
    var seconds: Double
    var playCount: Int

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, title, artist, album, artworkURL, player, firstHeard, lastHeard, seconds, playCount
    }

    init(key: String, title: String, artist: String, album: String, artworkURL: String?, player: String, firstHeard: Date, lastHeard: Date, seconds: Double, playCount: Int) {
        self.key = key
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.player = player
        self.firstHeard = firstHeard
        self.lastHeard = lastHeard
        self.seconds = seconds
        self.playCount = playCount
    }

    // Hand-rolled decode with decodeIfPresent — synthesized Codable would
    // brick persisted history whenever a field ships. (Backgrounds.swift
    // precedent.)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unknown"
        artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        artworkURL = try container.decodeIfPresent(String.self, forKey: .artworkURL)
        player = try container.decodeIfPresent(String.self, forKey: .player) ?? ""
        firstHeard = try container.decodeIfPresent(Date.self, forKey: .firstHeard) ?? Date()
        lastHeard = try container.decodeIfPresent(Date.self, forKey: .lastHeard) ?? Date()
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        playCount = try container.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
    }
}

/// The always-on listening history: every track the MusicStore poll observes
/// (panel open or closed) accumulates here, with play counts. Also serves as
/// the "This Mac" ListeningStatsProvider — Top/History/Stats work with zero
/// setup, and stats.fm just enriches them.
@MainActor
final class ListeningStore: ObservableObject {
    static let historyKey = "listeningHistory"
    static let retentionDays = 180
    static let capacity = 500
    /// A session must reach this to count as a play (skips skipped songs).
    private static let minPlaySeconds: Double = 20

    @Published private(set) var history: [HeardTrack] = [] // lastHeard desc

    private var heard: [String: HeardTrack] = [:]
    /// The track currently accumulating.
    private var currentKey: String?
    private var currentSessionSeconds: Double = 0
    private var lastNote: Date?
    private var dirty = false
    private var lastWrite = Date.distantPast

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.historyKey)
            ?? defaults.string(forKey: Self.historyKey)?.data(using: .utf8),
           let saved = try? JSONDecoder().decode([String: HeardTrack].self, from: data) {
            heard = saved
        }
        prune()
        republishHistory()
    }

    // MARK: Accumulation (called by MusicStore on every poll)

    func note(track: TrackInfo, isPlaying: Bool, at date: Date) {
        let key = "\(track.player)|\(track.title)|\(track.artist)"

        if key != currentKey {
            finalizeCurrent(at: date)
            writeHistory(force: true) // bound crash/SIGTERM loss to the current track
            currentKey = key
            currentSessionSeconds = 0
            var entry = heard[key] ?? HeardTrack(
                key: key,
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkURL: track.artworkURL,
                player: track.player,
                firstHeard: date,
                lastHeard: date,
                seconds: 0,
                playCount: 0
            )
            entry.album = track.album // titles update (e.g. after metadata loads)
            entry.artworkURL = entry.artworkURL ?? track.artworkURL
            entry.lastHeard = date
            heard[key] = entry
            dirty = true
            republishHistory()
        }

        if isPlaying, let last = lastNote, key == currentKey {
            let chunk = min(date.timeIntervalSince(last), 30)
            if chunk > 0, var entry = heard[key] {
                // Never credit more than 1.25× the track's own length.
                let cap = max(track.duration * 1.25, 30)
                let credited = min(chunk, max(0, cap - entry.seconds))
                if credited > 0 {
                    entry.seconds += credited
                    currentSessionSeconds += credited
                    entry.lastHeard = date
                    heard[key] = entry
                    dirty = true
                }
            }
        }
        lastNote = date
        // Periodic durability: SIGTERM kills skip applicationWillTerminate,
        // so writes can't rely on quit — throttle to one encode per 30 s.
        writeHistory()
    }

    /// Called when the observed track changes: count a play if the session
    /// earned it.
    private func finalizeCurrent(at date: Date) {
        guard let key = currentKey, currentSessionSeconds >= Self.minPlaySeconds, var entry = heard[key] else {
            currentSessionSeconds = 0
            return
        }
        entry.playCount += 1
        entry.lastHeard = date
        heard[key] = entry
        currentSessionSeconds = 0
        dirty = true
    }

    // MARK: ListeningStatsProvider (This Mac)

    func recentStreams(limit: Int) async throws -> [StreamEntry] {
        history.prefix(limit).map { entry in
            StreamEntry(
                id: "local-\(entry.key)",
                title: entry.title,
                artist: entry.artist,
                album: entry.album.isEmpty ? nil : entry.album,
                artworkURL: entry.artworkURL,
                playedAt: entry.lastHeard,
                duration: 0,
                source: entry.player.isEmpty ? "This Mac" : entry.player
            )
        }
    }

    func topTracks(range: StatsRange) async throws -> [TrackRank] {
        localTopTracks(range: range)
    }

    /// Sync variant for view bodies (local data is in-memory already).
    func localTopTracks(range: StatsRange) -> [TrackRank] {
        let cutoff = range.windowStart
        return heard.values
            .filter { cutoff == nil || $0.lastHeard >= cutoff! }
            .sorted { ($0.seconds, $0.playCount) > ($1.seconds, $1.playCount) }
            .prefix(8)
            .map {
                TrackRank(id: $0.key, title: $0.title, artist: $0.artist, artworkURL: $0.artworkURL, playCount: $0.playCount)
            }
    }

    func topArtists(range: StatsRange) async throws -> [ArtistRank] {
        localTopArtists(range: range)
    }

    func localTopArtists(range: StatsRange) -> [ArtistRank] {
        let cutoff = range.windowStart
        var grouped: [String: (seconds: Double, plays: Int, artwork: String?)] = [:]
        for entry in heard.values where cutoff == nil || entry.lastHeard >= cutoff! {
            let name = entry.artist
            var bucket = grouped[name] ?? (0, 0, nil)
            bucket.seconds += entry.seconds
            bucket.plays += entry.playCount
            bucket.artwork = bucket.artwork ?? entry.artworkURL
            grouped[name] = bucket
        }
        return grouped
            .sorted { ($0.value.seconds, $0.value.plays) > ($1.value.seconds, $1.value.plays) }
            .prefix(8)
            .map { ArtistRank(id: $0.key.lowercased(), name: $0.key, artworkURL: $0.value.artwork, playCount: $0.value.plays) }
    }

    func summary(range: StatsRange) async throws -> ListenSummary? {
        let cutoff = range.windowStart
        let window = heard.values.filter { cutoff == nil || $0.lastHeard >= cutoff! }
        let seconds = window.reduce(0) { $0 + $1.seconds }
        let plays = window.reduce(0) { $0 + $1.playCount }
        return ListenSummary(minutes: Int(seconds / 60), streams: plays)
    }

    /// Total tracked listening seconds (all time) for the Stats card.
    var totalTrackedSeconds: Double {
        heard.values.reduce(0) { $0 + $1.seconds }
    }

    var totalTrackCount: Int { heard.count }

    // MARK: Persistence

    func flushNow() {
        finalizeCurrent(at: Date()) // the track playing at quit still counts
        writeHistory(force: true)
    }

    private func writeHistory(force: Bool = false) {
        guard dirty else { return }
        guard force || Date().timeIntervalSince(lastWrite) >= 30 else { return }
        lastWrite = Date()
        dirty = false
        if let data = try? JSONEncoder().encode(heard) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date())
        for (key, entry) in heard where entry.lastHeard < cutoff ?? .distantPast {
            heard.removeValue(forKey: key)
        }
        if heard.count > Self.capacity {
            let keep = Set(heard.values.sorted { $0.lastHeard > $1.lastHeard }.prefix(Self.capacity).map(\.key))
            heard = heard.filter { keep.contains($0.key) }
        }
    }

    private func republishHistory() {
        history = heard.values.sorted { $0.lastHeard > $1.lastHeard }
    }
}
