import SwiftUI

// MARK: - Theme IDs

enum ThemeID: String, CaseIterable, Identifiable, Codable {
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

    /// How many home-widget slots fit this frame without crushing widget
    /// content — phone-card themes get 2, the wide iPad gets the full range.
    var maxHomeSlots: Int {
        frameSize.width >= 500 ? Config.slotCountRange.upperBound : 2
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
