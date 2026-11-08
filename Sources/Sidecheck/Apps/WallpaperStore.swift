import AVFoundation
import SwiftUI

/// Owns per-theme wallpaper specs (see `BackgroundSpec` in Backgrounds.swift).
/// Every theme keeps its own background; specs persist as JSON in
/// UserDefaults. Media files are referenced by path (the app is not
/// sandboxed) and rendered with a pan/zoom `CropSpec`.
@MainActor
final class WallpaperStore: ObservableObject {
    static let specsKey = "wallpaperSpecs"

    @Published private(set) var specs: [ThemeID: BackgroundSpec] {
        didSet { persist() }
    }

    init() {
        // Accept both Data and string-persisted JSON (`defaults write` writes strings).
        let object = UserDefaults.standard.object(forKey: Self.specsKey)
        let data: Data?
        if let asData = object as? Data {
            data = asData
        } else if let asString = object as? String {
            data = asString.data(using: .utf8)
        } else {
            data = nil
        }
        // Decode keyed by raw String and map manually: a theme removed from
        // the app (e.g. the iPad) must not fail the whole dictionary — its
        // entry is simply dropped. Persist the mapping explicitly: didSet
        // doesn't fire for assignments in init, and stale kinds (theme/blobs,
        // removed in v0.9) should be rewritten as their decoded values.
        if let data,
           let saved = try? JSONDecoder().decode([String: BackgroundSpec].self, from: data) {
            var mapped: [ThemeID: BackgroundSpec] = [:]
            for (raw, spec) in saved {
                if let theme = ThemeID(rawValue: raw) {
                    mapped[theme] = spec
                }
            }
            specs = mapped
            persist()
        } else {
            specs = [:]
        }
    }

    /// Pre-creates the AVPlayer for the active theme's video wallpaper so the
    /// first hover-open doesn't stall on media loading.
    func warmUp(for theme: ThemeID) {
        let spec = self.spec(for: theme)
        guard spec.kind == .video, let path = spec.filePath, Self.mediaExists(path) else { return }
        _ = Self.videoPlayer(for: URL(fileURLWithPath: path))
    }

    func spec(for theme: ThemeID) -> BackgroundSpec {
        specs[theme] ?? Self.defaultSpec(for: theme)
    }

    /// Out-of-box look per theme — preserves what the removed theme-native
    /// kind used to render (liquidGlass bubbles / cyberdeck CRT).
    static func defaultSpec(for theme: ThemeID) -> BackgroundSpec {
        BackgroundSpec(kind: theme == .cyberdeck ? .crt : .bubbles)
    }

    func set(_ spec: BackgroundSpec, for theme: ThemeID) {
        specs[theme] = spec
        // Evict players this spec no longer needs — a video that was replaced
        // (or a switch away from video entirely) releases its buffers here.
        // A still-mounted VideoLayerNSView retains its player until SwiftUI
        // reassigns it, so nothing freezes mid-transition.
        Self.releaseVideoPlayers(except: Self.videoURL(for: spec))
    }

    func reset(for theme: ThemeID) {
        set(Self.defaultSpec(for: theme), for: theme)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(specs) {
            UserDefaults.standard.set(data, forKey: Self.specsKey)
        }
    }

    // MARK: - Media caches (rendering must never decode per frame)

    static func mediaExists(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private static var imageCache: [String: NSImage] = [:]

    static func cachedImage(_ path: String?) -> NSImage? {
        guard let path, mediaExists(path) else { return nil }
        if let cached = imageCache[path] { return cached }
        let image = NSImage(contentsOfFile: path)
        if let image { imageCache[path] = image }
        return image
    }

    func applyToAllThemes(_ spec: BackgroundSpec) {
        for theme in ThemeID.allCases { specs[theme] = spec }
        Self.releaseVideoPlayers(except: Self.videoURL(for: spec))
    }

    // MARK: - Video players

    private static var videoPlayers: [URL: AVQueuePlayer] = [:]
    private static var videoLoopers: [URL: AVPlayerLooper] = [:]

    /// The video URL a spec still needs (nil when it isn't a video spec).
    private static func videoURL(for spec: BackgroundSpec) -> URL? {
        spec.kind == .video ? spec.filePath.map(URL.init(fileURLWithPath:)) : nil
    }

    /// One looping, muted-by-default player per video, kept alive for the app
    /// lifetime so re-selecting a wallpaper resumes instantly. Players for
    /// media the specs no longer reference are released on every spec change.
    static func videoPlayer(for url: URL) -> AVQueuePlayer {
        if let player = videoPlayers[url] { return player }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.actionAtItemEnd = .none
        videoLoopers[url] = AVPlayerLooper(player: player, templateItem: item)
        videoPlayers[url] = player
        return player
    }

    /// Drops every cached player except `keep` — evicted players deallocate
    /// (and pause) once nothing mounted still holds them.
    static func releaseVideoPlayers(except keep: URL?) {
        for url in videoPlayers.keys where url != keep {
            videoLoopers[url] = nil
            videoPlayers[url] = nil
        }
    }
}

// MARK: - Picture / video wallpaper renderer

/// Renders an image or looping video wallpaper inside the viewport, applying
/// the pan/zoom crop. Used by the panel background AND the crop editor
/// preview, so what you compose in the editor is exactly what shows behind
/// the panel.
struct WallpaperMediaView: View {
    let path: String?
    let crop: CropSpec
    var paused = false
    var video = false
    var muted = true

    var body: some View {
        GeometryReader { geo in
            if video {
                WallpaperVideoRepresentable(
                    path: path, crop: crop, muted: muted, paused: paused, viewport: geo.size
                )
                .frame(width: geo.size.width, height: geo.size.height)
            } else if let image = WallpaperStore.cachedImage(path) {
                let size = image.size
                let base = max(geo.size.width / max(size.width, 1), geo.size.height / max(size.height, 1))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width * base * crop.scale, height: size.height * base * crop.scale)
                    .position(
                        x: geo.size.width / 2 + crop.offsetX * geo.size.width,
                        y: geo.size.height / 2 + crop.offsetY * geo.size.height
                    )
            }
        }
        .clipped()
    }
}

/// AVPlayerLayer host for video wallpapers. The layer's frame is the viewport
/// scaled by `crop.scale` and shifted by the normalized crop offset; the
/// aspect-fill gravity + container clipping produce the pan/zoom effect.
private struct WallpaperVideoRepresentable: NSViewRepresentable {
    let path: String?
    let crop: CropSpec
    let muted: Bool
    let paused: Bool
    let viewport: CGSize

    func makeNSView(context: Context) -> VideoLayerNSView {
        VideoLayerNSView()
    }

    func updateNSView(_ view: VideoLayerNSView, context: Context) {
        view.apply(path: path, crop: crop, muted: muted, paused: paused, viewport: viewport)
    }
}

private final class VideoLayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var appliedPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    // match SwiftUI's top-left geometry for crop math
    override var isFlipped: Bool { true }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func apply(path: String?, crop: CropSpec, muted: Bool, paused: Bool, viewport: CGSize) {
        if path != appliedPath {
            appliedPath = path
            if let path {
                let player = WallpaperStore.videoPlayer(for: URL(fileURLWithPath: path))
                player.isMuted = muted
                playerLayer.player = player
            } else {
                playerLayer.player = nil
            }
        } else if let player = playerLayer.player {
            player.isMuted = muted
        }

        let width = viewport.width * crop.scale
        let height = viewport.height * crop.scale
        playerLayer.frame = CGRect(
            x: viewport.width / 2 + crop.offsetX * viewport.width - width / 2,
            y: viewport.height / 2 + crop.offsetY * viewport.height - height / 2,
            width: width,
            height: height
        )

        if let player = playerLayer.player {
            let shouldPlay = !paused && path != nil
            if shouldPlay, player.rate == 0, player.timeControlStatus != .playing {
                player.play()
            } else if !shouldPlay, player.rate > 0 {
                player.pause()
            }
        }
    }
}
