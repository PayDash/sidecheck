import SwiftUI

/// The Music app: now-playing info + transport for Spotify and Music.app.
/// Progress interpolates between MusicStore's polls (TimelineView only while
/// something is playing AND the panel is visible — the Awake gating rule).
struct MusicAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var music: MusicStore
    @EnvironmentObject var controller: PanelController

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
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.textTertiary)
    }

    // MARK: Now playing

    private func nowPlayingCard(_ track: TrackInfo) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    artworkView(track)
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .themeGlow(theme)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                            Text(track.player)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
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
        if music.isPlaying && controller.isVisible {
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
            MeterBar(progress: fraction)
            HStack {
                Text(Self.clock(current))
                Spacer()
                Text("-" + Self.clock(max(track.duration - current, 0)))
            }
            .font(.system(size: 9.5))
            .monospacedDigit()
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
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(LinearGradient(
                            colors: [theme.accent, theme.accent2],
                            startPoint: .top, endPoint: .bottom
                        ))
                    )
                    .themeGlow(theme)
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
                .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                .fill(theme.cardFill)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                        .strokeBorder(theme.cardStroke, lineWidth: 1)
                )
        }
    }

    private var emptyCard: some View {
        ThemedCard {
            VStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .themeGlow(theme)
                Text("Nothing playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Play something in Spotify or Music — it shows up here.")
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
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
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
