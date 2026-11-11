import SwiftUI
import AppKit

// MARK: - Vibrancy layer

/// Wraps NSVisualEffectView so supported themes get real system vibrancy.
struct VisualEffectBackground: View {
    var material: NSVisualEffectView.Material

    var body: some View {
        VisualEffectRepresentable(material: material)
    }

    struct VisualEffectRepresentable: NSViewRepresentable {
        let material: NSVisualEffectView.Material

        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = material
            view.blendingMode = .behindWindow
            view.state = .active
            view.wantsLayer = true
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {
            view.material = material
        }
    }
}

// MARK: - Motion language

/// The panel's motion tokens — calm and precise: one press feel, one entrance
/// feel, reused everywhere so the whole panel moves as one object.
enum PanelMotion {
    /// Press feedback (direct manipulation — not gated, it's state, not decoration).
    static let press = Animation.spring(response: 0.2, dampingFraction: 0.7)
    /// Hover lifts.
    static let hover = Animation.spring(response: 0.25, dampingFraction: 0.8)
    /// Entrance settles (staggered groups, rings drawing in).
    static let entrance = Animation.spring(response: 0.32, dampingFraction: 0.85)
    /// Per-group delay in the open choreography.
    static let staggerStep: TimeInterval = 0.045
}

/// Button style with press-down feedback — replaces `.plain` for every
/// tappable element so nothing on the panel feels dead under the pointer.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(PanelMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { .init() }
}

/// One group in the open choreography. `shown` flips once per panel show;
/// each group fades + rises with its own stagger delay. The flag resets
/// silently on hide and on theme remounts (State resets to `true`), so it
/// never re-animates outside the open transition.
struct EntranceGroup: ViewModifier {
    let shown: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .animation(
                shown ? PanelMotion.entrance.delay(Double(index) * PanelMotion.staggerStep) : nil,
                value: shown
            )
    }
}

extension View {
    /// `shown` already incorporates the performance/reduce-motion gates.
    func entranceGroup(shown: Bool, index: Int) -> some View {
        modifier(EntranceGroup(shown: shown, index: index))
    }
}

// MARK: - Widget sizing

/// Hero widget content scales its visuals (rings, artwork, sparklines,
/// chips) with the slot height — a taller slot grows the widget, it doesn't
/// grow the empty space around it. Text sizes stay put: more visual, less
/// texty. WidgetSlot sets this from the hero height it was given.
private struct WidgetScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var widgetScale: CGFloat {
        get { self[WidgetScaleKey.self] }
        set { self[WidgetScaleKey.self] = newValue }
    }
}

// MARK: - Themed card

/// A widget card that styles itself from the active theme and lifts slightly on hover.
/// Glass themes declare `litCardEdges`: the card rim is directional (top-lit,
/// dimming downward) so the whole panel reads as one lit glass object.
struct ThemedCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var mounted = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .fill(theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                            .strokeBorder(cardRim, lineWidth: 1)
                    )
            )
            .overlay {
                if theme.showsCornerBrackets {
                    CornerBrackets(color: theme.accent.opacity(0.7))
                }
            }
            .shadow(
                color: theme.glow.map { $0.opacity(0.25) } ?? Color.black.opacity(theme.isLight ? 0.08 : 0.3),
                radius: theme.isLight ? 6 : 8,
                y: theme.isLight ? 2 : 4
            )
            .scaleEffect(hovered && !reduceMotion ? 1.015 : 1)
            .opacity(mounted ? 1 : 0)
            .onHover { hovered = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: hovered)
            .onAppear {
                // Soft content settle on mount (page open) — one-shot, skipped
                // under Reduce Motion.
                if reduceMotion {
                    mounted = true
                } else {
                    withAnimation(.easeOut(duration: 0.22)) { mounted = true }
                }
            }
    }

    /// Lit themes: directional rim (bright at the top, fading downward) —
    /// light comes from above. Flat themes keep their declared stroke.
    private var cardRim: some ShapeStyle {
        if theme.litCardEdges {
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.17), Color.white.opacity(0.04)],
                startPoint: .top, endPoint: .bottom
            ))
        }
        return AnyShapeStyle(theme.cardStroke)
    }
}

/// Four L-shaped corner brackets, cyberdeck style. They "acquire" on mount —
/// fade + settle inward over a third of a second, like a targeting HUD
/// locking on. One-shot; Reduce Motion shows them settled immediately.
struct CornerBrackets: View {
    let color: Color
    var length: CGFloat = 9
    var lineWidth: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var acquired = false

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width, h = geo.size.height
                // top-left
                path.move(to: CGPoint(x: 0, y: length)); path.addLine(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: length, y: 0))
                // top-right
                path.move(to: CGPoint(x: w - length, y: 0)); path.addLine(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: length))
                // bottom-right
                path.move(to: CGPoint(x: w, y: h - length)); path.addLine(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w - length, y: h))
                // bottom-left
                path.move(to: CGPoint(x: length, y: h)); path.addLine(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: h - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .opacity(acquired ? 1 : 0)
        .scaleEffect(acquired ? 1 : 1.12)
        .onAppear {
            if reduceMotion {
                acquired = true
            } else {
                withAnimation(.easeOut(duration: 0.35)) { acquired = true }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ring gauge

/// Animated circular gauge with a gradient stroke and centered text. The arc
/// draws in from zero on mount (one-shot) so panel open feels alive.
struct RingGauge<Value: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let progress: Double // 0...1
    var lineWidth: CGFloat = 11
    let content: () -> Value

    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.divider, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(drawn ? progress : 0, 0.002), 1)))
                .stroke(
                    AngularGradient(
                        colors: [theme.accent, theme.accent2, theme.accent],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .themeGlow(theme)
        }
        .overlay(content())
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: progress)
        .onAppear {
            if reduceMotion {
                drawn = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { drawn = true }
            }
        }
    }
}

extension View {
    /// Adds the theme's phosphor glow when the theme defines one. Flattened
    /// when micro-animations are off (performance Saver/Custom).
    @ViewBuilder
    func themeGlow(_ theme: ThemeSpec? = nil) -> some View {
        modifier(ThemeGlowModifier(theme: theme))
    }

    /// `.symbolEffect(.pulse, options: .repeating)` only when ambient
    /// micro-animations are on (performance microAnimations feature).
    @ViewBuilder
    func repeatingPulse(_ active: Bool) -> some View {
        if active {
            self.symbolEffect(.pulse, options: .repeating)
        } else {
            self
        }
    }
}

/// Modifier form of `themeGlow` so it can read the performance store from the
/// environment.
private struct ThemeGlowModifier: ViewModifier {
    var theme: ThemeSpec?
    @EnvironmentObject var performance: PerformanceStore

    func body(content: Content) -> some View {
        if let glow = theme?.glow, performance.isOn(.microAnimations) {
            content.shadow(color: glow.opacity(0.6), radius: 4)
        } else {
            content
        }
    }
}

// MARK: - Widget scaffolding

/// Title row used inside cards.
struct CardTitle: View {
    @Environment(\.theme) private var theme
    let icon: String
    let title: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? theme.accent)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    static func rate(_ bps: Double) -> String {
        switch bps {
        case ..<1024: String(format: "%.0f B/s", bps)
        case ..<1_048_576: String(format: "%.1f KB/s", bps / 1024)
        default: String(format: "%.2f MB/s", bps / 1_048_576)
        }
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Usage-style duration ("3h 42m", "45m") — Screen Time totals.
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        return "\(minutes)m"
    }

    /// "987", "314K", "1.86M", "7.73B" — token-count formatting.
    static func compactCount(_ value: Int) -> String {
        let double = Double(value)
        switch abs(value) {
        case 0..<1_000: return "\(value)"
        case 1_000..<1_000_000: return String(format: "%.1fK", double / 1_000)
        case 1_000_000..<1_000_000_000: return String(format: "%.2fM", double / 1_000_000)
        default: return String(format: "%.2fB", double / 1_000_000_000)
        }
    }

    /// "$55.12" / "$0.03" — tokscale cost estimates.
    static func dollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// "3:42" / "1:02:03" — countdown rings (Awake) and the music progress clock.
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - SwiftUI-native panel controls

/// SwiftUI-only slider for panel pages: the AppKit-backed `Slider` re-runs its
/// Auto Layout engine on every frame of the window slide animation, stalling
/// transitions (~500 ms measured). This one is pure shapes + drag.
struct PanelSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.divider)
                    .frame(height: 6)
                Capsule()
                    .fill(theme.accent)
                    .frame(width: max(0, geo.size.width * CGFloat(fraction)), height: 6)
                Circle()
                    .fill(theme.textPrimary)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: max(0, (geo.size.width - 16) * CGFloat(fraction)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    var f = (gesture.location.x - 8) / max(geo.size.width - 16, 1)
                    f = min(max(f, 0), 1)
                    var next = range.lowerBound + f * span
                    if let step {
                        next = (next / step).rounded() * step
                    }
                    value = min(max(next, range.lowerBound), range.upperBound)
                }
            )
        }
        .frame(height: 20)
        .accessibilityLabel("Slider")
    }
}

/// SwiftUI-only switch — same reason as PanelSlider: no AppKit control inside
/// the sliding panel.
struct ThemeSwitch: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool
    var tint: Color? = nil

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? (tint ?? theme.accent).opacity(0.8) : theme.cardFill)
                .frame(width: 34, height: 19)
                .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 15, height: 15)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: isOn ? 16 : 2)
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Toggle")
    }
}
