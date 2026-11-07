import Foundation
import SwiftUI

/// The individual switches behind the performance modes. This enum IS the
/// integration template for future apps:
///
/// 1. Add a case here with a name/description/cost caption.
/// 2. In your store or view, read `performance.isOn(.yourCase)` (or take a
///    `featuresProvider: (() -> Set<PerformanceFeature>)?` closure like
///    StatsStore/ProcessStore/MusicStore — wire it in PanelController.init).
/// 3. Presets and the Custom mode pick your feature up automatically — cards,
///    toggles and the cost estimate all render from the registry.
enum PerformanceFeature: String, CaseIterable, Codable, Identifiable {
    case animatedBackgrounds
    case videoPlayback
    case panelMovement
    case microAnimations
    case liveTickers
    case fastStatsPolling
    case processScanning
    case fastMusicPolling

    var id: String { rawValue }

    var name: String {
        switch self {
        case .animatedBackgrounds: "Animated wallpapers"
        case .videoPlayback: "Video playback"
        case .panelMovement: "Panel & page animations"
        case .microAnimations: "Micro-animations & glow"
        case .liveTickers: "Live tickers (1 Hz)"
        case .fastStatsPolling: "Fast stats polling"
        case .processScanning: "Process scanning"
        case .fastMusicPolling: "Fast music polling"
        }
    }

    var description: String {
        switch self {
        case .animatedBackgrounds: "Bubbles/CRT animate instead of freezing"
        case .videoPlayback: "Video wallpapers keep playing"
        case .panelMovement: "Slide/zoom + theme morph + page transitions"
        case .microAnimations: "Hover lift, charging pulses, phosphor glow"
        case .liveTickers: "Awake countdown + music progress tick every second"
        case .fastStatsPolling: "CPU/memory/network sample every 2 s (10 s off)"
        case .processScanning: "Top-process list scans every 2 s (Monitor page)"
        case .fastMusicPolling: "Now-playing poll every 3 s while open (15 s off)"
        }
    }

    /// Caption for the toggle row. `kind` refines wallpaper-kind-dependent
    /// costs (bubbles/crt are the expensive animated ones).
    func costCaption(kind: BackgroundKind) -> String {
        switch self {
        case .animatedBackgrounds:
            return (kind == .bubbles || kind == .crt) ? "~8% · animated" : "free · static kind"
        case .videoPlayback:
            return kind == .video ? "~20% · playing" : "free · no video"
        case .panelMovement:
            return "~transient"
        case .microAnimations:
            return "~0.2%"
        case .liveTickers:
            return "~0.3%"
        case .fastStatsPolling:
            return "~0.2%"
        case .processScanning:
            return "~0.4%"
        case .fastMusicPolling:
            return "~0.1%"
        }
    }
}

/// How much visual candy the panel allows. The mode drives every ambient
/// cost: animated backgrounds (bubbles/CRT freeze in Saver), video playback
/// (paused in Balanced+Saver), panel movement animations (instant in Saver),
/// and the 1 Hz tickers (static in Saver). Polling is untouched — it's
/// already visible-gated or adaptive, and history capture must keep running.
enum PerformanceMode: String, CaseIterable, Identifiable {
    case pretty
    case balanced
    case saver
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pretty: "Pretty"
        case .balanced: "Balanced"
        case .saver: "Saver"
        case .custom: "Custom"
        }
    }

    var tagline: String {
        switch self {
        case .pretty: "Everything on"
        case .balanced: "Videos pause, the rest dances"
        case .saver: "Backgrounds frozen, instant everything"
        case .custom: "Pick exactly what runs"
        }
    }

    /// One-line effect summary for the widget.
    var effectCaption: String {
        switch self {
        case .pretty: "Everything on"
        case .balanced: "Videos paused"
        case .saver: "Backgrounds frozen"
        case .custom: "Custom mix"
        }
    }

    /// Accent for cards and the home widget.
    var tint: Color {
        switch self {
        case .pretty: .pink
        case .balanced: .yellow
        case .saver: .green
        case .custom: .cyan
        }
    }

    /// The feature set this preset enables. Custom resolves through the
    /// store's persisted set instead.
    func features() -> Set<PerformanceFeature> {
        switch self {
        case .pretty:
            return Set(PerformanceFeature.allCases)
        case .balanced:
            return Set(PerformanceFeature.allCases).subtracting([.videoPlayback])
        case .saver, .custom:
            return []
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
    static let customKey = "performanceCustom"
    static let autoPowerKey = "performanceAutoPower"
    private static let autoPowerInterval: TimeInterval = 30

    @Published var mode: PerformanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            // Entering Custom seeds the toggles with whatever was running, so
            // "Custom" starts as "same as before, now tuneable".
            if mode == .custom, oldValue != .custom {
                customFeatures = oldValue.features()
            }
        }
    }
    @Published var customFeatures: Set<PerformanceFeature> {
        didSet { UserDefaults.standard.set(Array(customFeatures).map(\.rawValue), forKey: Self.customKey) }
    }
    /// Saver on battery, Pretty on power — zero-maintenance modes.
    @Published var autoPower: Bool {
        didSet {
            UserDefaults.standard.set(autoPower, forKey: Self.autoPowerKey)
            syncAutoTimer()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: Self.modeKey)
        mode = raw.flatMap(PerformanceMode.init(rawValue:)) ?? .pretty
        if let data = defaults.data(forKey: Self.customKey)
            ?? defaults.string(forKey: Self.customKey)?.data(using: .utf8),
           let saved = try? JSONDecoder().decode([PerformanceFeature].self, from: data) {
            customFeatures = Set(saved)
        } else {
            customFeatures = PerformanceMode.balanced.features()
        }
        autoPower = defaults.object(forKey: Self.autoPowerKey) as? Bool ?? false
        syncAutoTimer()
    }

    /// The switches currently in effect.
    var activeFeatures: Set<PerformanceFeature> {
        mode == .custom ? customFeatures : mode.features()
    }

    func isOn(_ feature: PerformanceFeature) -> Bool {
        activeFeatures.contains(feature)
    }

    /// Toggle a feature; flips the mode to Custom first (seeding from the
    /// current set) so presets stay pristine.
    func setFeature(_ feature: PerformanceFeature, on: Bool) {
        if mode != .custom {
            customFeatures = activeFeatures
            mode = .custom
        }
        if on {
            customFeatures.insert(feature)
        } else {
            customFeatures.remove(feature)
        }
    }

    /// Estimated visible CPU% — base + enabled features, wallpaper-kind
    /// dependent where it matters. The numbers the mode cards show (from the
    /// project's own measurements).
    static func estimate(features: Set<PerformanceFeature>, kind: BackgroundKind) -> Double {
        var total = 0.5
        if features.contains(.animatedBackgrounds), kind == .bubbles || kind == .crt { total += 8 }
        if features.contains(.videoPlayback), kind == .video { total += 20 }
        if features.contains(.panelMovement) { total += 0.3 }
        if features.contains(.microAnimations) { total += 0.2 }
        if features.contains(.liveTickers) { total += 0.3 }
        if features.contains(.fastStatsPolling) { total += 0.2 }
        if features.contains(.processScanning) { total += 0.4 }
        if features.contains(.fastMusicPolling) { total += 0.1 }
        return total
    }

    // MARK: Auto-by-power

    private var autoTimer: Timer?

    private func syncAutoTimer() {
        if autoPower, autoTimer == nil {
            evaluatePower()
            autoTimer = Timer.scheduledTimer(withTimeInterval: Self.autoPowerInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluatePower() }
            }
        } else if !autoPower, let autoTimer {
            autoTimer.invalidate()
            self.autoTimer = nil
        }
    }

    private func evaluatePower() {
        guard autoPower, let battery = BatteryInfo.current() else { return }
        let target: PerformanceMode = battery.isCharging ? .pretty : .saver
        if mode != target {
            mode = target
        }
    }
}
