import Foundation

/// Tunables for the edge-hover panel. Everything is in points / seconds.
enum Config {
    /// How close the pointer must be to a screen's right edge to count as
    /// "in the hot zone".
    static let hotZoneWidth: CGFloat = 12

    /// The hot zone is vertically centered on each screen and spans this
    /// fraction of the screen height.
    static let hotZoneVerticalSpan: CGFloat = 0.4

    /// How long the pointer must dwell in the hot zone before the panel
    /// slides out. Keeps accidental edge grazes from popping the panel.
    static let showDwellDelay: TimeInterval = 0.18

    /// How long the pointer must be away from both the hot zone and the
    /// panel before it hides.
    static let hideDwellDelay: TimeInterval = 0.25

    /// Slide in/out animation duration.
    static let slideDuration: TimeInterval = 0.25

    /// Distance between the panel's right edge and the screen edge when shown.
    static let edgeMargin: CGFloat = 8

    /// Panel size scale range for the settings slider (× theme frame size).
    static let panelScaleRange: ClosedRange<Double> = 0.75...1.25

    /// Open/close animation duration range (seconds).
    static let animationSpeedRange: ClosedRange<Double> = 0.15...0.5
}
