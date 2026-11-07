import Foundation
import SwiftUI

/// How much visual candy the panel allows. The mode drives every ambient
/// cost: animated backgrounds (bubbles/CRT freeze in Saver), video playback
/// (paused in Balanced+Saver), panel movement animations (instant in Saver),
/// and the 1 Hz tickers (static in Saver). Polling is untouched — it's
/// already visible-gated or adaptive, and history capture must keep running.
enum PerformanceMode: String, CaseIterable, Identifiable {
    case pretty
    case balanced
    case saver

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pretty: "Pretty"
        case .balanced: "Balanced"
        case .saver: "Saver"
        }
    }

    var tagline: String {
        switch self {
        case .pretty: "Everything on"
        case .balanced: "Videos pause, the rest dances"
        case .saver: "Backgrounds frozen, instant everything"
        }
    }

    /// Accent for cards and the home widget.
    var tint: Color {
        switch self {
        case .pretty: .pink
        case .balanced: .yellow
        case .saver: .green
        }
    }

    /// One-line effect summary for the widget.
    var effectCaption: String {
        switch self {
        case .pretty: "Everything on"
        case .balanced: "Videos paused"
        case .saver: "Backgrounds frozen"
        }
    }

    /// Estimated visible CPU% for a background kind under THIS mode — the
    /// numbers the mode cards show (from the project's own measurements).
    func visibleCPUPercent(kind: BackgroundKind) -> Double {
        switch kind {
        case .video:
            return self == .pretty ? 20 : 0.5
        case .bubbles, .crt:
            return self == .saver ? 0.5 : 8
        case .solid, .gradient, .image:
            return 0.5
        }
    }
}

/// Owns the performance mode and exposes the derived switches consumers read.
/// Measured impact (visible, from the project's diagnostics): animated
/// backgrounds ~8% CPU, video ~20%, static ~0.5%; frozen backgrounds ~0.5%;
/// everything ≈0.1% while the panel is hidden.
@MainActor
final class PerformanceStore: ObservableObject {
    static let modeKey = "performanceMode"

    @Published var mode: PerformanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.modeKey)
        mode = raw.flatMap(PerformanceMode.init(rawValue:)) ?? .pretty
    }

    /// Bubbles/CRT render a single frame instead of animating at 30 fps.
    var freezeAnimatedBackgrounds: Bool { mode == .saver }

    /// Video wallpapers pause to a still (Balanced + Saver); the spec and
    /// player survive, so switching back resumes playback.
    var pauseVideos: Bool { mode != .pretty }

    /// Micro-animations off + instant window movement (reuses the
    /// Reduce-Motion pathways).
    var reduceEffects: Bool { mode == .saver }
}
