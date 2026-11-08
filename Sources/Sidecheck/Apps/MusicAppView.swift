import SwiftUI

/// The Music app: now-playing + transport, then listening stats — History,
/// Top artists/tracks, and summary Stats. Data comes from any
/// ListeningStatsProvider: the local history store always, stats.fm when
/// connected (username + optional token, nothing hardcoded).
struct MusicAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var music: MusicStore
    @EnvironmentObject var controller: PanelController
    @EnvironmentObject var listening: ListeningStore
    @EnvironmentObject var statsFm: StatsFmProvider
    @EnvironmentObject var performance: PerformanceStore

    private enum Tab: String, CaseIterable, Identifiable {
        case history = "History"
        case top = "Top"
        case stats = "Stats"

        var id: String { rawValue }
    }

    private enum TopKind: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case tracks = "Tracks"

        var id: String { rawValue }
    }

    @State private var tab: Tab = .history
    @State private var topKind: TopKind = .artists
    @State private var topRange: StatsRange = .weeks

    @State private var statsRecent: [StreamEntry]?
    @State private var statsTopTracks: [TrackRank]?
    @State private var statsTopArtists: [ArtistRank]?
    @State private var statsSummary: ListenSummary?
    @State private var statsLoadError: String?

    @State private var usernameDraft = ""
    @State private var tokenDraft = ""
    @State private var connecting = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if let denied = music.accessDeniedTo {
                    deniedNote(player: denied)
                }

                if let track = music.track {
                    nowPlayingCard(track)
                } else {
                    emptyCard
                }

                tabPills

                switch tab {
                case .history: historySection
                case .top: topSection
                case .stats: statsSection
                }
            }
            .padding(16)
        }
        .onAppear {
            usernameDraft = statsFm.username
            tokenDraft = statsFm.token
        }
        .task(id: "history-\(statsFm.username)-\(statsFm.isConfigured)") {
            guard statsFm.isConfigured else { statsRecent = nil; return }
            statsRecent = try? await statsFm.recentStreams(limit: 40)
        }
        .task(id: "top-\(topKind)-\(topRange)-\(statsFm.username)") {
            guard statsFm.isConfigured else { return }
            statsLoadError = nil
            do {
                switch topKind {
                case .tracks: statsTopTracks = try await statsFm.topTracks(range: topRange)
                case .artists: statsTopArtists = try await statsFm.topArtists(range: topRange)
                }
            } catch {
                statsLoadError = (error as? StatsFmProvider.ProviderError)?.errorDescription ?? "stats.fm unreachable"
            }
        }
        .task(id: "stats-\(statsFm.username)-\(statsFm.isConfigured)") {
            guard statsFm.isConfigured else { statsSummary = nil; return }
            statsSummary = try? await statsFm.summary(range: .weeks)
        }
    }

    // MARK: Tabs

    private var tabPills: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { candidate in
                tabPill(candidate.rawValue, selected: tab == candidate) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        tab = candidate
                    }
                }
            }
            Spacer()
        }
    }

    private func tabPill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(theme.accent.opacity(selected ? 0.16 : 0), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        selected ? theme.accent.opacity(0.55) : theme.cardStroke,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let entries = mergedHistory
            ThemedCard {
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle(icon: "clock.arrow.circlepath", title: "Recent plays")
                    if entries.isEmpty {
                        emptyCaption("Nothing yet — play something and it lands here")
                    } else {
                        ForEach(entries.prefix(12)) { entry in
                            streamRow(entry)
                        }
                    }
                }
            }
            if statsFm.isConfigured {
                Text("Merging this Mac + stats.fm")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    /// Local entries + stats.fm recent, deduped by track within a minute.
    private var mergedHistory: [StreamEntry] {
        var entries: [StreamEntry] = listening.history.prefix(30).map { entry in
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
        if let remote = statsRecent { entries += remote }
        var seen: [String: Date] = [:]
        return entries
            .sorted { $0.playedAt > $1.playedAt }
            .filter { entry in
                let key = trackMergeKey(title: entry.title, artist: entry.artist)
                if let last = seen[key], abs(last.timeIntervalSince(entry.playedAt)) < 60 {
                    return false
                }
                seen[key] = entry.playedAt
                return true
            }
    }

    private func streamRow(_ entry: StreamEntry) -> some View {
        HStack(spacing: 10) {
            RemoteThumb(url: entry.artworkURL, size: 30, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text("\(entry.artist) · \(entry.source) · \(Self.timeAgo(entry.playedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: Top

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(TopKind.allCases) { kind in
                    tabPill(kind.rawValue, selected: topKind == kind) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            topKind = kind
                        }
                    }
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(StatsRange.allCases) { range in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            topRange = range
                        }
                    } label: {
                        Text(range.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(topRange == range ? theme.accent : theme.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(theme.accent.opacity(topRange == range ? 0.14 : 0), in: Capsule())
                            .overlay(Capsule().strokeBorder(topRange == range ? theme.accent.opacity(0.5) : theme.cardStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            ThemedCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CardTitle(icon: topKind == .artists ? "mic.fill" : "music.note.list", title: "Top \(topKind.rawValue)")
                        Spacer()
                        Text(statsFm.isConfigured ? "stats.fm" : "This Mac")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                    topList
                    if let statsLoadError, statsFm.isConfigured {
                        Text(statsLoadError)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topList: some View {
        if statsFm.isConfigured {
            switch topKind {
            case .artists:
                if let artists = statsTopArtists {
                    rankedList(artists.map { rank in
                        RankedRow(
                            id: rank.id,
                            label: rank.name,
                            plays: rank.playCount,
                            artwork: rank.artworkURL
                        )
                    })
                } else {
                    emptyCaption(statsLoadError == nil ? "Loading…" : "Nothing to show")
                }
            case .tracks:
                if let tracks = statsTopTracks {
                    rankedList(tracks.map { rank in
                        RankedRow(
                            id: rank.id,
                            label: "\(rank.title) — \(rank.artist)",
                            plays: rank.playCount,
                            artwork: rank.artworkURL
                        )
                    })
                } else {
                    emptyCaption(statsLoadError == nil ? "Loading…" : "Nothing to show")
                }
            }
        } else {
            switch topKind {
            case .artists:
                let artists = listening.localTopArtists(range: topRange)
                if artists.isEmpty {
                    emptyCaption("No listening data yet — play something!")
                } else {
                    rankedList(artists.map { rank in
                        RankedRow(
                            id: rank.id,
                            label: rank.name,
                            plays: rank.playCount,
                            artwork: rank.artworkURL
                        )
                    })
                }
            case .tracks:
                let tracks = listening.localTopTracks(range: topRange)
                if tracks.isEmpty {
                    emptyCaption("No listening data yet — play something!")
                } else {
                    rankedList(tracks.map { rank in
                        RankedRow(
                            id: rank.id,
                            label: "\(rank.title) — \(rank.artist)",
                            plays: rank.playCount,
                            artwork: rank.artworkURL
                        )
                    })
                }
            }
        }
    }

    private struct RankedRow: Identifiable {
        let id: String
        let label: String
        let plays: Int?
        let artwork: String?
    }

    /// Generic ranked rows: rank #, thumb, name, optional plays, meter.
    private func rankedList(_ items: [RankedRow]) -> some View {
        let maxPlays = items.compactMap(\.plays).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                emptyCaption("No streams in this range yet")
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 14)
                    RemoteThumb(url: item.artwork, size: 26, theme: theme)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        if let plays = item.plays, plays > 0 {
                            Text("\(plays) plays")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    Spacer()
                    MeterBar(progress: maxPlays > 0 ? Double(item.plays ?? 0) / Double(maxPlays) : 1.0 / Double(index + 1))
                        .frame(width: 56)
                }
            }
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if statsFm.isConfigured {
                ThemedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        CardTitle(icon: "chart.bar.fill", title: "stats.fm")
                        if let user = statsFm.connectedUser {
                            Text("Connected as \(user)")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                        }
                        if let summary = statsSummary {
                            HStack(spacing: 16) {
                                statValue("\(summary.minutes ?? 0)", "minutes · weeks")
                                statValue("\(summary.streams ?? 0)", "streams · weeks")
                            }
                        } else if let error = statsLoadError {
                            Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                        } else {
                            emptyCaption("Loading…")
                        }
                        disconnectButton
                    }
                }
            }
            ThemedCard {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle(icon: "macwindow", title: "This Mac")
                    HStack(spacing: 16) {
                        statValue(Format.duration(listening.totalTrackedSeconds), "tracked listening")
                        statValue("\(listening.totalTrackCount)", "tracks heard")
                    }
                    Text("Accumulates in the background whenever Spotify or Music runs")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            if !statsFm.isConfigured {
                connectCard
            }
        }
    }

    private func statValue(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
                .themeGlow(theme)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var disconnectButton: some View {
        Button {
            statsFm.username = ""
            statsFm.token = ""
            statsRecent = nil
            statsTopArtists = nil
            statsTopTracks = nil
            statsSummary = nil
        } label: {
            Text("Disconnect")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var connectCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "link", title: "Connect stats.fm")
                Text("Shows your Spotify listening stats on this page. Free account works — your profile just needs to be public.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                tokenField(icon: "person", placeholder: "stats.fm username", text: $usernameDraft)
                tokenField(icon: "key", placeholder: "API token (optional — stats.fm → Settings)", text: $tokenDraft)
                HStack {
                    Button {
                        connecting = true
                        statsFm.username = usernameDraft.trimmingCharacters(in: .whitespaces)
                        statsFm.token = tokenDraft.trimmingCharacters(in: .whitespaces)
                        Task {
                            defer { connecting = false }
                            do {
                                try await statsFm.connect()
                                statsTopArtists = try? await statsFm.topArtists(range: topRange)
                                statsRecent = try? await statsFm.recentStreams(limit: 40)
                            } catch {
                                // lastError carries the message; keep the drafts
                            }
                        }
                    } label: {
                        Text(connecting ? "Connecting…" : "Connect")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                if let error = statsFm.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func tokenField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }

    private func emptyCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    // MARK: Now playing (unchanged from v0.8)

    private func nowPlayingCard(_ track: TrackInfo) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    artworkView(track)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .themeGlow(theme)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                            Text(track.player)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.cardFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                    }
                    Spacer()
                }

                progressSection(track)
                transportRow
            }
        }
    }

    /// Ticks at 1 s only while playing and the panel is visible; otherwise the
    /// bar renders once from the current position (no mounted timer).
    @ViewBuilder
    private func progressSection(_ track: TrackInfo) -> some View {
        if music.isPlaying && controller.isVisible && performance.isOn(.liveTickers) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                progressBar(track)
            }
        } else {
            progressBar(track)
        }
    }

    private func progressBar(_ track: TrackInfo) -> some View {
        let current = music.positionNow()
        let fraction = track.duration > 0 ? min(max(current / track.duration, 0), 1) : 0
        return VStack(alignment: .leading, spacing: 4) {
            // 1 Hz ticks + a 1.05 s linear tween read as one gliding bar.
            MeterBar(progress: fraction, animation: .linear(duration: 1.05))
            HStack {
                Text(Self.clock(current))
                Spacer()
                Text("-" + Self.clock(max(track.duration - current, 0)))
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(theme.textTertiary)
        }
    }

    private var transportRow: some View {
        HStack(spacing: 28) {
            Spacer()
            transportButton("backward.fill", size: 15) { music.previous() }
            Button {
                music.playPause()
            } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(theme.accent))
            }
            .buttonStyle(.plain)
            transportButton("forward.fill", size: 15) { music.next() }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func transportButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func artworkView(_ track: TrackInfo) -> some View {
        if let image = music.artwork {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.cardFill)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                )
        }
    }

    private var emptyCard: some View {
        ThemedCard {
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .themeGlow(theme)
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Play something in Spotify or Music — it shows up here")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func deniedNote(player: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Automation is denied for \(player) — allow it in System Settings → Privacy & Security → Automation.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private static func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86_400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86_400))d ago"
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Remote artwork thumbnail with an in-memory cache — History/Top rows show
/// real covers without any per-row plumbing.
private struct RemoteThumb: View {
    let url: String?
    var size: CGFloat
    let theme: ThemeSpec
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.cardFill)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        .task(id: url) {
            guard let url else { return }
            image = await ArtworkCache.shared.load(url)
        }
    }
}

@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private var cache: [String: NSImage] = [:]

    func load(_ urlString: String) async -> NSImage? {
        if let cached = cache[urlString] { return cached }
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        cache[urlString] = image
        return image
    }
}
