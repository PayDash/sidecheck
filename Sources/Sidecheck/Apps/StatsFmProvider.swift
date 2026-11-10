import Foundation

// stats.fm timestamps are ISO8601, sometimes with fractional seconds. The
// formatters and decoder live at file scope: ISO8601DateFormatter is
// thread-safe, and the decoder's .custom closure is @Sendable so it can't
// touch MainActor-isolated state.
private let statsFmFractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let statsFmPlainDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

let statsFmDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = statsFmFractionalDateFormatter.date(from: raw) ?? statsFmPlainDateFormatter.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "unparseable date '\(raw)'")
    }
    return decoder
}()

/// The stats.fm backend (https://stats.fm). Works in two tiers:
/// username-only (reads the profile's public recent streams and top lists)
/// and username + personal API token (stats.fm → Settings → API token) for
/// authenticated data. Config persists; endpoints verified against
/// api.stats.fm/api/v1 (lowercase range values, raw-token Authorization
/// header — matching the official statsfm.dart SDK).
@MainActor
final class StatsFmProvider: ObservableObject {
    static let usernameKey = "statsFmUsername"
    static let tokenKey = "statsFmToken"

    enum ProviderError: LocalizedError {
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .http(401), .http(403):
                return "stats.fm wants a valid token for this"
            case .http(404):
                return "stats.fm user not found"
            case .http(let code):
                return "stats.fm error \(code)"
            case .badResponse:
                return "unexpected stats.fm response"
            }
        }
    }

    @Published var username: String {
        didSet {
            if username != oldValue {
                UserDefaults.standard.set(username, forKey: Self.usernameKey)
                invalidateCache()
                connectedUser = nil
            }
        }
    }
    @Published var token: String {
        didSet {
            if token != oldValue {
                UserDefaults.standard.set(token, forKey: Self.tokenKey)
                invalidateCache()
                connectedUser = nil
            }
        }
    }
    /// Display name once a connect attempt succeeded.
    @Published private(set) var connectedUser: String?
    @Published private(set) var lastError: String?

    var isConfigured: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty }

    // In-memory TTL cache keyed by full URL.
    private var cache: [String: (stored: Date, data: Data)] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]

    init() {
        let defaults = UserDefaults.standard
        username = defaults.string(forKey: Self.usernameKey) ?? ""
        token = defaults.string(forKey: Self.tokenKey) ?? ""
    }

    // MARK: Connect

    /// Validates what the user typed (public profile check; /me when a token
    /// is present) and persists the config.
    func connect() async throws {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            lastError = "Enter your stats.fm username"
            throw ProviderError.badResponse
        }
        do {
            if token.trimmingCharacters(in: .whitespaces).isEmpty {
                _ = try await get("/users/\(name)", query: [:], ttl: 300)
                connectedUser = name
            } else {
                let me = try await get("/me", query: [:], ttl: 0)
                let user = try statsFmDecoder.decode(StatsFmProvider.UserResponse.self, from: me)
                connectedUser = user.displayName ?? user.customId ?? name
            }
            lastError = nil
        } catch {
            connectedUser = nil
            lastError = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
            throw error
        }
    }

    // MARK: ListeningStatsProvider

    func topTracks(range: StatsRange) async throws -> [TrackRank] {
        let data = try await cached("/users/\(username)/top/tracks", range: range, ttl: 1800)
        let decoded = try statsFmDecoder.decode(StatsFmProvider.TopResponse<StatsFmProvider.TopTrackItem>.self, from: data)
        return decoded.items.compactMap { item -> TrackRank? in
            guard let track = item.track else { return nil }
            return TrackRank(
                id: "statsfm-track-\(item.position)-\(track.name)",
                title: track.name,
                artist: track.artists?.first?.name ?? "",
                artworkURL: track.artists?.first?.image ?? track.albums?.first?.image,
                playCount: item.streams
            )
        }
    }

    func topArtists(range: StatsRange) async throws -> [ArtistRank] {
        let data = try await cached("/users/\(username)/top/artists", range: range, ttl: 1800)
        let decoded = try statsFmDecoder.decode(StatsFmProvider.TopResponse<StatsFmProvider.TopArtistItem>.self, from: data)
        return decoded.items.compactMap { item -> ArtistRank? in
            guard let artist = item.artist else { return nil }
            return ArtistRank(
                id: "statsfm-artist-\(item.position)-\(artist.name)",
                name: artist.name,
                artworkURL: artist.image,
                playCount: item.streams
            )
        }
    }

    func recentStreams(limit: Int) async throws -> [StreamEntry] {
        let data = try await cached("/users/\(username)/streams/recent", query: ["limit": String(limit)], ttl: 300)
        let decoded = try statsFmDecoder.decode(StatsFmProvider.RecentStreamsResponse.self, from: data)
        return decoded.items.compactMap { item -> StreamEntry? in
            guard let track = item.track else { return nil }
            return StreamEntry(
                id: "statsfm-\(item.endTime)-\(track.name)",
                title: track.name,
                artist: track.artists?.first?.name ?? "",
                album: track.albums?.first?.name,
                artworkURL: track.artists?.first?.image ?? track.albums?.first?.image,
                playedAt: item.endTime,
                duration: Double(item.durationMs) / 1000,
                source: "stats.fm"
            )
        }
    }

    func summary(range: StatsRange) async throws -> ListenSummary? {
        let data = try await cached("/users/\(username)/streams/stats", range: range, ttl: 1800)
        let decoded = try statsFmDecoder.decode(Self.StreamStatsResponse.self, from: data)
        return ListenSummary(minutes: decoded.minutesStreamed, streams: decoded.countStreamed)
    }

    // MARK: Networking

    /// Builds the request URL from parts, not from a string: the username is
    /// interpolated into the path, and `URLComponents(string:)` returns nil —
    /// which used to crash the force-unwrap — for any character that's illegal
    /// raw in a URL (a space, non-ASCII, …). The `.path` setter percent-encodes
    /// those automatically.
    nonisolated static func makeURL(path: String, query: [String: String]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.stats.fm"
        components.path = "/api/v1" + path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    private func get(_ path: String, query: [String: String], ttl: TimeInterval) async throws -> Data {
        guard let url = Self.makeURL(path: path, query: query) else {
            throw ProviderError.badResponse
        }
        let cacheKey = url.absoluteString

        if ttl > 0, let hit = cache[cacheKey], Date().timeIntervalSince(hit.stored) < ttl {
            return hit.data
        }
        if let running = inFlight[cacheKey] {
            return try await running.value
        }

        let task = Task<Data, Error> {
            var request = URLRequest(url: url, timeoutInterval: 12)
            let trimmedToken = token.trimmingCharacters(in: .whitespaces)
            if !trimmedToken.isEmpty {
                request.setValue(trimmedToken, forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw ProviderError.http(status) }
            return data
        }
        inFlight[cacheKey] = task
        defer { inFlight[cacheKey] = nil }
        let data = try await task.value
        cache[cacheKey] = (Date(), data)
        return data
    }

    /// Top-list fetch with the lowercase range param; some endpoints reject
    /// certain ranges (400) — retry without it rather than surfacing an error.
    private func cached(_ path: String, range: StatsRange, ttl: TimeInterval) async throws -> Data {
        do {
            return try await get(path, query: ["range": range.rawValue], ttl: ttl)
        } catch ProviderError.http(400) {
            return try await get(path, query: [:], ttl: ttl)
        }
    }

    private func cached(_ path: String, query: [String: String], ttl: TimeInterval) async throws -> Data {
        try await get(path, query: query, ttl: ttl)
    }

    private func invalidateCache() {
        cache.removeAll()
    }

    // MARK: Response models (only the fields this app renders)

    struct UserResponse: Decodable {
        var id: String?
        var customId: String?
        var displayName: String?
    }

    struct TopResponse<Item: Decodable>: Decodable {
        var items: [Item]
    }

    struct TopArtistItem: Decodable {
        var position: Int
        var streams: Int?
        var artist: ArtistRef?
    }

    struct TopTrackItem: Decodable {
        var position: Int
        var streams: Int?
        var track: TrackRef?
    }

    struct ArtistRef: Decodable {
        var name: String
        var image: String?
    }

    struct TrackRef: Decodable {
        var name: String
        var artists: [ArtistRef]?
        var albums: [AlbumRef]?
    }

    struct AlbumRef: Decodable {
        var name: String?
        var image: String?
    }

    struct RecentStreamsResponse: Decodable {
        var items: [RecentStreamItem]
    }

    struct RecentStreamItem: Decodable {
        var endTime: Date
        var durationMs: Int
        var track: TrackRef?
    }

    struct StreamStatsResponse: Decodable {
        var minutesStreamed: Int?
        var countStreamed: Int?
    }
}
