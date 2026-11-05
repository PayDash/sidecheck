import SwiftUI

// MARK: - Theme IDs

enum ThemeID: String, CaseIterable, Identifiable {
    case liquidGlass
    case ipad
    case cyberdeck

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .ipad: "iPad"
        case .cyberdeck: "Cyberdeck"
        }
    }

    var symbol: String {
        switch self {
        case .liquidGlass: "drop"
        case .ipad: "ipad.landscape"
        case .cyberdeck: "cpu"
        }
    }
}

// MARK: - Theme spec (design tokens)

/// How the home screen renders its app launcher. Themes pick a template so
/// new themes reuse the same base machinery.
enum HomeStyle {
    case iconTiles    // iPadOS-like grid of rounded icon tiles
    case terminalList // text rows (cyberdeck)
}

struct ThemeSpec {
    let id: ThemeID
    let panelRadius: CGFloat
    let cardRadius: CGFloat
    let fontDesign: Font.Design
    let accent: Color
    let accent2: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let cardFill: Color
    let cardStroke: Color
    let divider: Color
    let glow: Color? // text/element glow (cyberdeck)
    let isLight: Bool

    // Home-screen / frame template
    let frameSize: CGSize                       // base panel size before user scale
    let homeStyle: HomeStyle                    // which home template renders
    let iconCornerRadiusRatio: CGFloat          // 0.224 = Apple squircle feel, 0.5 = circles
    let showsDock: Bool
    let showsSearchPill: Bool
    let showsClockInHeader: Bool
    let iconLabelIsWhite: Bool // white labels with shadow (dark wallpapers)

    static let liquidGlass = ThemeSpec(
        id: .liquidGlass,
        panelRadius: 34,
        cardRadius: 16,
        fontDesign: .rounded,
        accent: .blue,
        accent2: .cyan,
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.62),
        textTertiary: Color.white.opacity(0.5),
        cardFill: Color.white.opacity(0.07),
        cardStroke: Color.white.opacity(0.16),
        divider: Color.white.opacity(0.08),
        glow: nil,
        isLight: false,

        // home template
        frameSize: CGSize(width: 380, height: 680),
        homeStyle: .iconTiles,
        iconCornerRadiusRatio: 0.24,
        showsDock: true,
        showsSearchPill: false,
        showsClockInHeader: false,
        iconLabelIsWhite: true,
    )

    static let ipad = ThemeSpec(
        id: .ipad,
        panelRadius: 32,
        cardRadius: 20,
        fontDesign: .rounded,
        accent: Color(red: 0.15, green: 0.45, blue: 0.98),
        accent2: .teal,
        textPrimary: Color(red: 0.12, green: 0.13, blue: 0.16),
        textSecondary: Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.62),
        textTertiary: Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.55),
        cardFill: Color.white.opacity(0.62),
        cardStroke: Color.white.opacity(0.65),
        divider: Color.black.opacity(0.07),
        glow: nil,
        isLight: true,

        // home template
        frameSize: CGSize(width: 720, height: 540),
        homeStyle: .iconTiles,
        iconCornerRadiusRatio: 0.224,
        showsDock: true,
        showsSearchPill: false,
        showsClockInHeader: true,
        iconLabelIsWhite: true,
    )

    static let cyberdeck = ThemeSpec(
        id: .cyberdeck,
        panelRadius: 14,
        cardRadius: 6,
        fontDesign: .monospaced,
        accent: Color(red: 0.22, green: 1.0, blue: 0.42),
        accent2: Color(red: 1.0, green: 0.72, blue: 0.18),
        textPrimary: Color(red: 0.55, green: 1.0, blue: 0.62),
        textSecondary: Color(red: 0.55, green: 1.0, blue: 0.62).opacity(0.6),
        textTertiary: Color(red: 0.55, green: 1.0, blue: 0.62).opacity(0.45),
        cardFill: Color(red: 0.02, green: 0.09, blue: 0.04).opacity(0.85),
        cardStroke: Color(red: 0.22, green: 1.0, blue: 0.42).opacity(0.35),
        divider: Color(red: 0.22, green: 1.0, blue: 0.42).opacity(0.2),
        glow: Color(red: 0.22, green: 1.0, blue: 0.42),
        isLight: false,

        // home template
        frameSize: CGSize(width: 380, height: 680),
        homeStyle: .terminalList,
        iconCornerRadiusRatio: 0.2,
        showsDock: false,
        showsSearchPill: false,
        showsClockInHeader: false,
        iconLabelIsWhite: false,
    )
}

extension ThemeID {
    var spec: ThemeSpec {
        switch self {
        case .liquidGlass: .liquidGlass
        case .ipad: .ipad
        case .cyberdeck: .cyberdeck
        }
    }

    /// Small gradient used by the settings swatches.
    var previewGradient: Gradient {
        switch self {
        case .liquidGlass: Gradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.06), Color.blue.opacity(0.5)])
        case .ipad: Gradient(colors: [Color.white, Color(red: 0.75, green: 0.88, blue: 1.0)])
        case .cyberdeck: Gradient(colors: [Color.black, Color(red: 0.02, green: 0.2, blue: 0.08), Color(red: 0.22, green: 1.0, blue: 0.42)])
        }
    }
}

// MARK: - Store

@MainActor
final class ThemeStore: ObservableObject {
    static let defaultsKey = "themeID"

    @Published var current: ThemeID {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.defaultsKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        current = ThemeID(rawValue: raw) ?? .liquidGlass
    }

    var spec: ThemeSpec { current.spec }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemeSpec = .liquidGlass
}

extension EnvironmentValues {
    var theme: ThemeSpec {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Backgrounds

/// Full-bleed themed background for the panel.
struct ThemeBackground: View {
    let id: ThemeID
    var paused: Bool = false // Reduce Motion freezes all background animation

    var body: some View {
        switch id {
        case .liquidGlass: LiquidGlassBackground(paused: paused)
        case .ipad: IPadBackground(paused: paused)
        case .cyberdeck: CyberdeckBackground(paused: paused)
        }
    }
}

/// Vibrancy + two slow-drifting aurora glows.
private struct LiquidGlassBackground: View {
    let paused: Bool

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    auroraCircle(color: .blue.opacity(0.35), radius: 180,
                                 offset: CGPoint(x: sin(t * 0.21) * 90, y: cos(t * 0.17) * 70 - 120))
                    auroraCircle(color: .cyan.opacity(0.28), radius: 150,
                                 offset: CGPoint(x: cos(t * 0.16) * 110, y: sin(t * 0.23) * 90 + 130))
                    auroraCircle(color: .purple.opacity(0.2), radius: 130,
                                 offset: CGPoint(x: sin(t * 0.11 + 2) * 70, y: cos(t * 0.19 + 1) * 110))
                }
            }
        }
    }

    private func auroraCircle(color: Color, radius: CGFloat, offset: CGPoint) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: offset.x, y: offset.y)
            .blur(radius: 30)
    }
}

/// Self-contained light wallpaper + slow pastel blobs (iPadOS light mode).
private struct IPadBackground: View {
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
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { context in
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

/// Phosphor terminal: scanlines, drifting refresh band, vignette, CRT flicker.
private struct CyberdeckBackground: View {
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

            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: paused)) { context in
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
