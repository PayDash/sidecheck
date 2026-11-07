import Foundation

// MARK: - Listening stats provider layer
//
// The Music app's stats tabs render any `ListeningStatsProvider`. Two ship:
// the always-on local history (ListeningStore) and stats.fm
// (StatsFmProvider) — new backends (Last.fm, Apple Music replay, …) plug in
// by conforming. Nothing about stats.fm is hardcoded outside its own file.

/// How far back a stats query looks. Raw values are stats.fm's lowercase
/// query parameters; local aggregation maps them to windows.
enum StatsRange: String, CaseIterable, Identifiable {
    case today
    case days
    case weeks
    case months
    case lifetime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .days: "Days"
        case .weeks: "Weeks"
        case .months: "Months"
        case .lifetime: "Lifetime"
        }
    }

    /// Start of the window for local aggregation (nil = everything).
    var windowStart: Date? {
        let calendar = Calendar.current
        switch self {
        case .today: return calendar.startOfDay(for: Date())
        case .days: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .weeks: return calendar.date(byAdding: .day, value: -28, to: Date())
        case .months: return calendar.date(byAdding: .day, value: -180, to: Date())
        case .lifetime: return nil
        }
    }
}

/// A ranked track ("Top songs").
struct TrackRank: Identifiable {
    let id: String
    let title: String
    let artist: String
    var artworkURL: String?
    var playCount: Int?
}

/// A ranked artist ("Top artists").
struct ArtistRank: Identifiable {
    let id: String
    let name: String
    var artworkURL: String?
    var playCount: Int?
}

/// One played track in the History list.
struct StreamEntry: Identifiable {
    let id: String
    let title: String
    let artist: String
    var album: String?
    var artworkURL: String?
    let playedAt: Date
    var duration: TimeInterval
    var source: String // "Spotify" / "Music" / "stats.fm"
}

/// Aggregate listening totals.
struct ListenSummary {
    var minutes: Int?
    var streams: Int?
}

/// The favorite key for a track — normalized across sources so a song starred
/// in stats.fm history and the same song heard locally share one favorite.
func trackFavoriteKey(title: String, artist: String) -> String {
    "\(title.lowercased())|\(artist.lowercased())"
}

protocol ListeningStatsProvider {
    var id: String { get }
    var displayName: String { get }
    var isConfigured: Bool { get }
    func topTracks(range: StatsRange) async throws -> [TrackRank]
    func topArtists(range: StatsRange) async throws -> [ArtistRank]
    func recentStreams(limit: Int) async throws -> [StreamEntry]
    func summary(range: StatsRange) async throws -> ListenSummary?
}
