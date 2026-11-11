import SwiftUI

// MARK: - Theme IDs

enum ThemeID: String, CaseIterable, Identifiable, Codable {
    case liquidGlass
    case cyberdeck
    case noir

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .cyberdeck: "Cyberdeck"
        case .noir: "Noir"
        }
    }

    var symbol: String {
        switch self {
        case .liquidGlass: "drop"
        case .cyberdeck: "cpu"
        case .noir: "moon.stars"
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
    let glow: Color? // text/element glow (cyberdeck, noir)
    let isLight: Bool

    // Home-screen / frame template
    let frameSize: CGSize                       // base panel size before user scale
    let homeStyle: HomeStyle                    // which home template renders
    let iconCornerRadiusRatio: CGFloat          // 0.224 = Apple squircle feel, 0.5 = circles
    let showsDock: Bool
    let showsSearchPill: Bool
    let showsClockInHeader: Bool
    let iconLabelIsWhite: Bool // white labels with shadow (dark wallpapers)

    // Per-theme declarations — the last hardcodes that used to live in
    // view/store code. A new theme declares these instead of editing callers.
    let showsCornerBrackets: Bool               // ThemedCard decoration (cyberdeck)
    let defaultBackground: BackgroundKind       // out-of-box wallpaper (WallpaperStore.defaultSpec)
    let litCardEdges: Bool                      // cards get a directional top-lit edge instead of a flat stroke
    let litPanelBorder: Bool                    // the panel rim is a lit gradient instead of a flat stroke
    let bootShimmer: Bool                       // one CRT power-on sweep when the panel opens
    let meterSegments: Int                      // widget meters as N phosphor segments (0 = smooth glass capsule)
    let stacksWideWidgets: Bool                 // home renders every slot as a stacked full-width wide widget
    let typographicWidgets: Bool                // home widgets render the serif typographic variants
    let monochromeTiles: Bool                   // app tiles render white-on-dark instead of their tint gradient
    let accentIsLight: Bool                     // glyphs on accent fills flip to dark for contrast

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

        showsCornerBrackets: false,
        defaultBackground: .bubbles,

        litCardEdges: true,
        litPanelBorder: true,
        bootShimmer: false,
        meterSegments: 0,
        stacksWideWidgets: false,
        typographicWidgets: false,
        monochromeTiles: false,
        accentIsLight: false,
    )

    /// How many home-widget slots fit this frame without crushing widget
    /// content — side-by-side cards are capped by the frame's width (phone-card
    /// frames get 2, a future wide theme gets the full range), but a stacked
    /// theme has no horizontal crowding, so it unlocks the full range and the
    /// home simply scrolls.
    var maxHomeSlots: Int {
        if stacksWideWidgets { return Config.slotCountRange.upperBound }
        return frameSize.width >= 500 ? Config.slotCountRange.upperBound : 2
    }

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

        showsCornerBrackets: true,
        defaultBackground: .crt,

        litCardEdges: false,
        litPanelBorder: false,
        bootShimmer: true,
        meterSegments: 6,
        stacksWideWidgets: false,
        typographicWidgets: false,
        monochromeTiles: false,
        accentIsLight: false,
    )

    /// Black & white with serif glow — color reserved for status (green/yellow/red).
    /// Widgets stack as full-width cards; no dock.
    static let noir = ThemeSpec(
        id: .noir,
        panelRadius: 30,
        cardRadius: 14,
        fontDesign: .serif,
        accent: .white,
        accent2: Color.white.opacity(0.7),
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.55),
        textTertiary: Color.white.opacity(0.35),
        cardFill: Color.white.opacity(0.055),
        cardStroke: Color.white.opacity(0.16),
        divider: Color.white.opacity(0.1),
        glow: Color.white.opacity(0.85),
        isLight: false,

        // home template
        frameSize: CGSize(width: 380, height: 680),
        homeStyle: .iconTiles,
        iconCornerRadiusRatio: 0.24,
        showsDock: false,
        showsSearchPill: false,
        showsClockInHeader: true,
        iconLabelIsWhite: true,

        showsCornerBrackets: false,
        defaultBackground: .glow,

        litCardEdges: true,
        litPanelBorder: true,
        bootShimmer: false,
        meterSegments: 0,
        stacksWideWidgets: true,
        typographicWidgets: true,
        monochromeTiles: true,
        accentIsLight: true,
    )
}

extension ThemeID {
    var spec: ThemeSpec {
        switch self {
        case .liquidGlass: .liquidGlass
        case .cyberdeck: .cyberdeck
        case .noir: .noir
        }
    }

    /// Small gradient used by the settings swatches.
    var previewGradient: Gradient {
        switch self {
        case .liquidGlass: Gradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.06), Color.blue.opacity(0.5)])
        case .cyberdeck: Gradient(colors: [Color.black, Color(red: 0.02, green: 0.2, blue: 0.08), Color(red: 0.22, green: 1.0, blue: 0.42)])
        case .noir: Gradient(colors: [Color.black, Color.white.opacity(0.22), Color.black])
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

// Encodes `[ThemeID: BackgroundSpec]` as a plain JSON object keyed by raw
// value — without this, Swift falls back to an array-of-keys representation.
extension ThemeID: CodingKeyRepresentable {}

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

// Backgrounds moved to Backgrounds.swift — they are now spec-driven
// (PanelBackgroundView) so the Wallpaper app can override them per theme.
