import SwiftUI

// MARK: - Background specs (owned by WallpaperStore, rendered here)

/// What kind of background a panel theme shows: an animated style (bubbles or
/// CRT), a solid, a gradient, a picture or a video — usable on any theme.
/// (`theme`/`blobs` were removed in v0.9 — their looks live on as `.bubbles`
/// and `.crt`; stale persisted values decode as `.bubbles`.)
enum BackgroundKind: String, Codable, CaseIterable {
    case bubbles
    case crt
    case glow
    case solid
    case gradient
    case image
    case video
}

/// A color stored as sRGB components — SwiftUI's `Color` isn't Codable at our
/// macOS 14 deployment target.
struct RGBA: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        red = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue = Double(ns.blueComponent)
        alpha = Double(ns.alphaComponent)
    }
}
struct BackgroundSpec: Codable, Equatable, Hashable {
    var kind: BackgroundKind = .bubbles
    var color: RGBA?
    var gradientID: String?
    var gradientAngle: Double = 0
    var filePath: String?
    var crop = CropSpec()
    var isMuted = true

    init(kind: BackgroundKind = .bubbles) {
        self.kind = kind
    }

    // Hand-rolled decode with decodeIfPresent: synthesized Codable demands
    // every non-optional key, so persisted specs would break whenever a new
    // field ships. Encodable stays synthesized. The kind decodes through the
    // raw String so kinds removed later (theme/blobs in v0.9) fall back to
    // .bubbles instead of failing the whole persisted dictionary.
    private enum CodingKeys: String, CodingKey {
        case kind, color, gradientID, gradientAngle, filePath, crop, isMuted
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kind)
        kind = rawKind.flatMap(BackgroundKind.init(rawValue:)) ?? .bubbles
        color = try container.decodeIfPresent(RGBA.self, forKey: .color)
        gradientID = try container.decodeIfPresent(String.self, forKey: .gradientID)
        gradientAngle = try container.decodeIfPresent(Double.self, forKey: .gradientAngle) ?? 0
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        crop = try container.decodeIfPresent(CropSpec.self, forKey: .crop) ?? .default
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
    }
}

/// Pan/zoom crop for picture & video wallpapers. `scale` 1 = media exactly
/// covers the viewport; `offsetX/Y` are normalized to the viewport size and
/// clamped so the media never shows a gap.
struct CropSpec: Codable, Equatable, Hashable {
    var scale: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0

    static let `default` = CropSpec()

    private enum CodingKeys: String, CodingKey { case scale, offsetX, offsetY }

    /// Memberwise with defaults — the explicit `init()` would otherwise
    /// suppress it (tests build variants directly).
    init(scale: CGFloat = 1, offsetX: CGFloat = 0, offsetY: CGFloat = 0) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scale = try container.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1
        offsetX = try container.decodeIfPresent(CGFloat.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(CGFloat.self, forKey: .offsetY) ?? 0
    }
}

// MARK: - Spec-driven panel background

struct PanelBackgroundView: View {
    let spec: BackgroundSpec
    let themeID: ThemeID
    var paused: Bool = false // Reduce Motion or hidden window freezes everything
    var features: Set<PerformanceFeature> = PerformanceMode.pretty.features()

    var body: some View {
        switch spec.kind {
        case .bubbles:
            GlassBubblesBackground(paused: paused || !features.contains(.animatedBackgrounds))
        case .crt:
            CyberdeckBackground(paused: paused || !features.contains(.animatedBackgrounds))
        case .glow:
            GlowBackground(paused: paused || !features.contains(.animatedBackgrounds))
        case .solid:
            (spec.color?.color ?? Color(red: 0.08, green: 0.09, blue: 0.12))
                .ignoresSafeArea()
        case .gradient:
            gradientBackground
        case .image:
            // cachedImage (not just mediaExists): an existing but undecodable
            // file would otherwise render nothing over a transparent panel.
            if WallpaperStore.cachedImage(spec.filePath) != nil {
                WallpaperMediaView(path: spec.filePath, crop: spec.crop, paused: paused)
            } else {
                GlassBubblesBackground(paused: paused)
            }
        case .video:
            if WallpaperStore.mediaExists(spec.filePath) {
                WallpaperMediaView(path: spec.filePath, crop: spec.crop, paused: paused || !features.contains(.videoPlayback), video: true, muted: spec.isMuted)
            } else {
                GlassBubblesBackground(paused: paused)
            }
        }
    }

    private var gradientBackground: some View {
        let gradient = GradientPresets.byID(spec.gradientID) ?? GradientPresets.all[0]
        let angle = (spec.gradientAngle - 90) * .pi / 180 // 0° = top→bottom
        return LinearGradient(
            colors: gradient.colors,
            startPoint: UnitPoint(x: 0.5 - cos(angle) / 2, y: 0.5 - sin(angle) / 2),
            endPoint: UnitPoint(x: 0.5 + cos(angle) / 2, y: 0.5 + sin(angle) / 2)
        )
        .ignoresSafeArea()
    }
}

// MARK: - Glass bubbles (Liquid Glass native)

/// Translucent glass bubbles rising slowly over the vibrancy layer — soft
/// bokeh light with no hard rims (a crisp rim reads as a solid ball against
/// the material; a rimless light pool reads as glass). Two depth layers
/// drift at different speeds. One Canvas draw per frame (30 fps), fully
/// deterministic (no per-frame randomness).
struct GlassBubblesBackground: View {
    let paused: Bool

    private struct Bubble {
        let xFrac: CGFloat      // horizontal anchor, 0...1
        let radius: CGFloat
        let speed: CGFloat      // pt/s upward
        let phase: Double       // phase offset in the rise cycle + wobble
        let wobbleAmp: CGFloat
        let wobbleSpeed: Double
        let depth: Double       // 0 = far (dim, slow), 1 = near
    }

    private static let bubbles: [Bubble] = [
        // far layer — large, slow, faint
        Bubble(xFrac: 0.18, radius: 24, speed: 9, phase: 0.00, wobbleAmp: 12, wobbleSpeed: 0.31, depth: 0),
        Bubble(xFrac: 0.52, radius: 18, speed: 13, phase: 0.31, wobbleAmp: 9, wobbleSpeed: 0.53, depth: 0),
        Bubble(xFrac: 0.78, radius: 21, speed: 11, phase: 0.58, wobbleAmp: 14, wobbleSpeed: 0.24, depth: 0),
        // near layer — smaller, livelier, brighter
        Bubble(xFrac: 0.36, radius: 10, speed: 24, phase: 0.77, wobbleAmp: 7, wobbleSpeed: 0.68, depth: 1),
        Bubble(xFrac: 0.90, radius: 12, speed: 20, phase: 0.42, wobbleAmp: 10, wobbleSpeed: 0.44, depth: 1),
        Bubble(xFrac: 0.64, radius: 14, speed: 17, phase: 0.88, wobbleAmp: 11, wobbleSpeed: 0.36, depth: 1),
        Bubble(xFrac: 0.08, radius: 9, speed: 26, phase: 0.65, wobbleAmp: 8, wobbleSpeed: 0.60, depth: 1),
    ]

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for bubble in Self.bubbles {
                        draw(bubble, time: t, in: context, size: size)
                    }
                }
            }
        }
    }

    private func draw(_ bubble: Bubble, time t: Double, in context: GraphicsContext, size: CGSize) {
        let x = bubble.xFrac * size.width + sin(t * bubble.wobbleSpeed + bubble.phase * 7) * bubble.wobbleAmp
        let travel = size.height + bubble.radius * 2
        let y = size.height + bubble.radius - (t * bubble.speed + bubble.phase * travel)
            .truncatingRemainder(dividingBy: travel)

        // fade out near the top edge / in near the bottom — wide band so
        // bubbles never pop in at the boundaries
        let edge = min(1, (y + bubble.radius) / 90, (size.height - y + bubble.radius) / 90)
        guard edge > 0 else { return }

        let scale = 0.6 + 0.4 * bubble.depth // far bubbles sit back
        let rect = CGRect(x: x - bubble.radius, y: y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2)
        // body: a soft light pool, brightest just above center, dissolving
        // into the material at the edge — no rim to fake an object boundary
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(0.14 * scale * edge), location: 0),
                    .init(color: .white.opacity(0.06 * scale * edge), location: 0.45),
                    .init(color: .clear, location: 1),
                ]),
                center: CGPoint(x: x - bubble.radius * 0.3, y: y - bubble.radius * 0.35),
                startRadius: 1, endRadius: bubble.radius * 1.25
            )
        )
        // sheen: a small soft highlight near the top, itself rimless
        let sheenRect = CGRect(
            x: x - bubble.radius * 0.5, y: y - bubble.radius * 0.7,
            width: bubble.radius * 0.8, height: bubble.radius * 0.5
        )
        context.fill(
            Path(ellipseIn: sheenRect),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.18 * scale * edge), .clear]),
                center: CGPoint(x: x - bubble.radius * 0.25, y: y - bubble.radius * 0.55),
                startRadius: 1, endRadius: bubble.radius * 0.6
            )
        )
    }
}

// MARK: - Glow (Noir native)

/// Soft white light fields drifting over near-black — the Noir theme's
/// native background. Deterministic (no per-frame randomness), one Canvas
/// draw per frame (30 fps), pauses like the other animated kinds.
struct GlowBackground: View {
    let paused: Bool

    private struct Orb {
        let xFrac: CGFloat
        let yFrac: CGFloat      // vertical anchor, 0...1
        let radius: CGFloat
        let drift: CGFloat      // horizontal wander amplitude
        let period: Double      // seconds per sway cycle
        let phase: Double
        let alpha: Double
    }

    private static let orbs: [Orb] = [
        Orb(xFrac: 0.20, yFrac: 0.75, radius: 95, drift: 26, period: 26, phase: 0.0, alpha: 0.10),
        Orb(xFrac: 0.82, yFrac: 0.25, radius: 70, drift: 20, period: 34, phase: 0.4, alpha: 0.08),
        Orb(xFrac: 0.55, yFrac: 0.50, radius: 55, drift: 32, period: 42, phase: 0.75, alpha: 0.07),
        Orb(xFrac: 0.10, yFrac: 0.20, radius: 45, drift: 18, period: 38, phase: 0.9, alpha: 0.06),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.028, green: 0.028, blue: 0.034)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for orb in Self.orbs {
                        let x = orb.xFrac * size.width + sin(t / orb.period + orb.phase * 6) * orb.drift
                        let y = orb.yFrac * size.height + cos(t / (orb.period * 1.4) + orb.phase * 4) * orb.drift * 0.6
                        let rect = CGRect(x: x - orb.radius, y: y - orb.radius, width: orb.radius * 2, height: orb.radius * 2)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(stops: [
                                    .init(color: .white.opacity(orb.alpha), location: 0),
                                    .init(color: .white.opacity(orb.alpha * 0.35), location: 0.5),
                                    .init(color: .clear, location: 1),
                                ]),
                                center: CGPoint(x: x, y: y),
                                startRadius: 1, endRadius: orb.radius
                            )
                        )
                    }
                }
            }
            // vignette — keeps the edges black so cards float
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.5)],
                center: .center, startRadius: 140, endRadius: 430
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Cyberdeck CRT

/// Phosphor terminal: scanlines, drifting refresh band, vignette, CRT flicker.
struct CyberdeckBackground: View {
    let paused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.015, green: 0.035, blue: 0.02)

            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.black.opacity(0.30))
                    )
                    y += 4
                }
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let bandY = (t * 60).truncatingRemainder(dividingBy: 1000) - 200
                let deepY = (t * 22).truncatingRemainder(dividingBy: 1000) - 200
                ZStack {
                    // deep sweep — slow and faint, gives the tube depth
                    LinearGradient(
                        colors: [.clear, Color(red: 0.3, green: 1.0, blue: 0.5).opacity(0.03), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 220)
                    .offset(y: deepY)
                    .frame(maxHeight: .infinity, alignment: .top)

                    // refresh band
                    LinearGradient(
                        colors: [.clear, Color(red: 0.3, green: 1.0, blue: 0.5).opacity(0.06), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 140)
                    .offset(y: bandY)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }

            // vignette
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                center: .center, startRadius: 120, endRadius: 420
            )

            // CRT flicker (disabled entirely under Reduce Motion)
            if !paused {
                TimelineView(.periodic(from: .now, by: 0.12)) { _ in
                    Color.white.opacity(Double.random(in: 0...0.02))
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Gradient presets

enum GradientPresets {
    struct Preset: Identifiable, Equatable {
        let id: String
        let name: String
        let colors: [Color]
    }

    static let all: [Preset] = [
        Preset(id: "ocean", name: "Ocean", colors: [Color(red: 0.10, green: 0.46, blue: 0.82), Color(red: 0.13, green: 0.72, blue: 0.79), Color(red: 0.06, green: 0.25, blue: 0.45)]),
        Preset(id: "midnight", name: "Midnight", colors: [Color(red: 0.05, green: 0.07, blue: 0.18), Color(red: 0.13, green: 0.10, blue: 0.30), Color(red: 0.02, green: 0.03, blue: 0.08)]),
        Preset(id: "forest", name: "Forest", colors: [Color(red: 0.06, green: 0.29, blue: 0.20), Color(red: 0.15, green: 0.50, blue: 0.34), Color(red: 0.03, green: 0.15, blue: 0.12)]),
        Preset(id: "grape", name: "Grape", colors: [Color(red: 0.29, green: 0.10, blue: 0.44), Color(red: 0.52, green: 0.22, blue: 0.66), Color(red: 0.16, green: 0.05, blue: 0.26)]),
        Preset(id: "slate", name: "Slate", colors: [Color(red: 0.14, green: 0.16, blue: 0.20), Color(red: 0.25, green: 0.28, blue: 0.34), Color(red: 0.08, green: 0.09, blue: 0.12)]),
    ]

    static func byID(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
