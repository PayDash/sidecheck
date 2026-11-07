import Foundation

/// Tunables for the edge-hover panel. Everything is in points / seconds.
///
/// Hot-zone values are `var`: they're the live values EdgeTracker reads, kept
/// in sync with PanelController's persisted settings (loaded at launch,
/// written by the Settings sliders).
enum Config {
    /// How close the pointer must be to a screen's right edge to count as
    /// "in the hot zone".
    static var hotZoneWidth: CGFloat = 12

    /// The hot zone is vertically centered on each screen and spans this
    /// fraction of the screen height.
    static var hotZoneVerticalSpan: CGFloat = 0.4

    /// How long the pointer must dwell in the hot zone before the panel
    /// slides out. Keeps accidental edge grazes from popping the panel.
    static var showDwellDelay: TimeInterval = 0.18

    /// How long the pointer must be away from both the hot zone and the
    /// panel before it hides.
    static var hideDwellDelay: TimeInterval = 0.25

    /// Distance between the panel's right edge and the screen edge when shown.
    static let edgeMargin: CGFloat = 8

    /// Panel size scale range for the settings slider (× theme frame size).
    static let panelScaleRange: ClosedRange<Double> = 0.75...1.25

    /// Open/close animation duration range (seconds).
    static let animationSpeedRange: ClosedRange<Double> = 0.15...0.5

    /// Duration of the theme-switch morph: the window resize (PanelController)
    /// and the content crossfade (PanelView) share this so they land together.
    static let themeMorphDuration: TimeInterval = 0.32

    // Settings ranges
    static let hotZoneWidthRange: ClosedRange<Double> = 4...60
    static let hotZoneSpanRange: ClosedRange<Double> = 0.1...1.0
    static let dwellDelayRange: ClosedRange<Double> = 0...1.0
    static let slotCountRange: ClosedRange<Int> = 1...6
}
