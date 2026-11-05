import SwiftUI

// MARK: - Background specs (owned by WallpaperStore, rendered here)

/// What kind of background a panel theme shows. `.theme` = the theme's own
/// animated look; the other kinds override it (a wallpaper can use any theme's
/// animated style, a solid, a gradient, a picture or a video on any theme).
enum BackgroundKind: String, Codable, CaseIterable {
    case theme
    case bubbles
    case blobs
    case crt
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
    var kind: BackgroundKind = .theme
    var color: RGBA?
    var gradientID: String?
    var gradientAngle: Double = 0
    var filePath: String?
    var crop = CropSpec()
    var isMuted = true

    static let themeDefault = BackgroundSpec()

    // Hand-rolled decode with decodeIfPresent: synthesized Codable demands
    // every non-optional key, so persisted specs would break whenever a new
    // field ships. Encodable stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case kind, color, gradientID, gradientAngle, filePath, crop, isMuted
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(BackgroundKind.self, forKey: .kind) ?? .theme
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

    init() {}

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

    var body: some View {
        switch spec.kind {
        case .theme:
            ThemeNativeBackground(id: themeID, paused: paused)
        case .bubbles:
            GlassBubblesBackground(paused: paused)
        case .blobs:
            IPadBackground(paused: paused)
        case .crt:
            CyberdeckBackground(paused: paused)
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
                ThemeNativeBackground(id: themeID, paused: paused)
            }
        case .video:
            if WallpaperStore.mediaExists(spec.filePath) {
                WallpaperMediaView(path: spec.filePath, crop: spec.crop, paused: paused, video: true, muted: spec.isMuted)
            } else {
                ThemeNativeBackground(id: themeID, paused: paused)
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

/// The per-theme default animated background (spec kind `.theme`).
struct ThemeNativeBackground: View {
    let id: ThemeID
    var paused: Bool = false

    var body: some View {
        switch id {
        case .liquidGlass: GlassBubblesBackground(paused: paused)
        case .ipad: IPadBackground(paused: paused)
        case .cyberdeck: CyberdeckBackground(paused: paused)
        }
    }
}

// MARK: - Glass bubbles (Liquid Glass native)

/// Translucent glass bubbles rising slowly over the vibrancy layer — rim-lit,
/// softly shaded, with a small top sheen. Replaces the aurora. One Canvas
/// draw per frame (30 fps), fully deterministic (no per-frame randomness).
struct GlassBubblesBackground: View {
    let paused: Bool

    private struct Bubble {
        let xFrac: CGFloat      // horizontal anchor, 0...1
        let radius: CGFloat
        let speed: CGFloat      // pt/s upward
        let phase: Double       // phase offset in the rise cycle + wobble
        let wobbleAmp: CGFloat
        let wobbleSpeed: Double
    }

    private static let bubbles: [Bubble] = [
        Bubble(xFrac: 0.18, radius: 34, speed: 17, phase: 0.00, wobbleAmp: 12, wobbleSpeed: 0.31),
        Bubble(xFrac: 0.52, radius: 14, speed: 26, phase: 0.31, wobbleAmp: 9, wobbleSpeed: 0.53),
        Bubble(xFrac: 0.78, radius: 24, speed: 20, phase: 0.58, wobbleAmp: 14, wobbleSpeed: 0.24),
        Bubble(xFrac: 0.36, radius: 9, speed: 31, phase: 0.77, wobbleAmp: 7, wobbleSpeed: 0.68),
        Bubble(xFrac: 0.90, radius: 12, speed: 24, phase: 0.42, wobbleAmp: 10, wobbleSpeed: 0.44),
        Bubble(xFrac: 0.64, radius: 18, speed: 15, phase: 0.88, wobbleAmp: 11, wobbleSpeed: 0.36),
        Bubble(xFrac: 0.08, radius: 11, speed: 28, phase: 0.65, wobbleAmp: 8, wobbleSpeed: 0.60),
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
        var y = size.height + bubble.radius - (t * bubble.speed + bubble.phase * travel)
            .truncatingRemainder(dividingBy: travel)

        // fade out near the top edge / in near the bottom
        let edge = min(1, (y + bubble.radius) / 44, (size.height - y + bubble.radius) / 44)
        guard edge > 0 else { return }

        let rect = CGRect(x: x - bubble.radius, y: y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2)
        // body: soft white sphere shading
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.13 * edge), .white.opacity(0.05 * edge), .clear]),
                center: CGPoint(x: x - bubble.radius * 0.35, y: y - bubble.radius * 0.4),
                startRadius: 1, endRadius: bubble.radius * 1.35
            )
        )
        // rim light
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(.white.opacity(0.20 * edge)),
            lineWidth: 1.2
        )
        // top sheen
        let sheen = CGRect(x: x - bubble.radius * 0.45, y: y - bubble.radius * 0.62, width: bubble.radius * 0.72, height: bubble.radius * 0.42)
        context.fill(
            Path(ellipseIn: sheen),
            with: .color(.white.opacity(0.15 * edge))
        )
    }
}

// MARK: - iPad blobs

/// Self-contained light wallpaper + slow pastel blobs (iPadOS light mode).
struct IPadBackground: View {
    let paused: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.95, blue: 0.98),
                    Color(red: 0.88, green: 0.91, blue: 0.96),
                    Color(red: 0.90, green: 0.93, blue: 0.97),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    blob(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.4), radius: 170,
                         offset: CGPoint(x: sin(t * 0.13) * 100, y: cos(t * 0.11) * 80 - 160))
                    blob(Color(red: 1.0, green: 0.75, blue: 0.7).opacity(0.3), radius: 150,
                         offset: CGPoint(x: cos(t * 0.17 + 1) * 90, y: sin(t * 0.14 + 2) * 100 + 150))
                    blob(Color(red: 0.65, green: 0.95, blue: 0.85).opacity(0.3), radius: 140,
                         offset: CGPoint(x: sin(t * 0.09 + 3) * 110, y: cos(t * 0.2 + 0.5) * 60))
                }
            }
        }
    }

    private func blob(_ color: Color, radius: CGFloat, offset: CGPoint) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: offset.x, y: offset.y)
            .blur(radius: 40)
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
                LinearGradient(
                    colors: [.clear, Color(red: 0.3, green: 1.0, blue: 0.5).opacity(0.06), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 140)
                .offset(y: bandY)
                .frame(maxHeight: .infinity, alignment: .top)
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
        Preset(id: "sunset", name: "Sunset", colors: [Color(red: 1.0, green: 0.42, blue: 0.34), Color(red: 0.98, green: 0.56, blue: 0.42), Color(red: 0.56, green: 0.32, blue: 0.72)]),
        Preset(id: "ocean", name: "Ocean", colors: [Color(red: 0.10, green: 0.46, blue: 0.82), Color(red: 0.13, green: 0.72, blue: 0.79), Color(red: 0.06, green: 0.25, blue: 0.45)]),
        Preset(id: "midnight", name: "Midnight", colors: [Color(red: 0.05, green: 0.07, blue: 0.18), Color(red: 0.13, green: 0.10, blue: 0.30), Color(red: 0.02, green: 0.03, blue: 0.08)]),
        Preset(id: "candy", name: "Candy", colors: [Color(red: 1.0, green: 0.60, blue: 0.78), Color(red: 0.66, green: 0.80, blue: 1.0), Color(red: 0.85, green: 0.64, blue: 1.0)]),
        Preset(id: "ember", name: "Ember", colors: [Color(red: 0.55, green: 0.09, blue: 0.05), Color(red: 0.92, green: 0.35, blue: 0.10), Color(red: 0.98, green: 0.71, blue: 0.25)]),
        Preset(id: "forest", name: "Forest", colors: [Color(red: 0.06, green: 0.29, blue: 0.20), Color(red: 0.15, green: 0.50, blue: 0.34), Color(red: 0.03, green: 0.15, blue: 0.12)]),
        Preset(id: "grape", name: "Grape", colors: [Color(red: 0.29, green: 0.10, blue: 0.44), Color(red: 0.52, green: 0.22, blue: 0.66), Color(red: 0.16, green: 0.05, blue: 0.26)]),
        Preset(id: "peach", name: "Peach", colors: [Color(red: 1.0, green: 0.84, blue: 0.70), Color(red: 1.0, green: 0.64, blue: 0.60), Color(red: 0.99, green: 0.87, blue: 0.82)]),
        Preset(id: "slate", name: "Slate", colors: [Color(red: 0.14, green: 0.16, blue: 0.20), Color(red: 0.25, green: 0.28, blue: 0.34), Color(red: 0.08, green: 0.09, blue: 0.12)]),
        Preset(id: "neon", name: "Neon", colors: [Color(red: 0.10, green: 0.95, blue: 0.70), Color(red: 0.16, green: 0.55, blue: 0.95), Color(red: 0.75, green: 0.25, blue: 0.90)]),
    ]

    static func byID(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
