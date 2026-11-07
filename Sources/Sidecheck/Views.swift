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

// MARK: - Themed card

/// A widget card that styles itself from the active theme and lifts slightly on hover.
struct ThemedCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .fill(theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                            .strokeBorder(theme.cardStroke, lineWidth: 1)
                    )
            )
            .overlay {
                if theme.id == .cyberdeck {
                    CornerBrackets(color: theme.accent.opacity(0.7))
                }
            }
            .shadow(
                color: theme.glow.map { $0.opacity(0.25) } ?? Color.black.opacity(theme.isLight ? 0.08 : 0.3),
                radius: theme.isLight ? 6 : 8,
                y: theme.isLight ? 2 : 4
            )
            .scaleEffect(hovered && !reduceMotion ? 1.015 : 1)
            .onHover { hovered = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovered)
    }
}

/// Four L-shaped corner brackets, cyberdeck style.
struct CornerBrackets: View {
    let color: Color
    var length: CGFloat = 9
    var lineWidth: CGFloat = 1.5

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
        .allowsHitTesting(false)
    }
}

// MARK: - Ring gauge

/// Animated circular gauge with a gradient stroke and centered text.
struct RingGauge<Value: View>: View {
    @Environment(\.theme) private var theme

    let progress: Double // 0...1
    var lineWidth: CGFloat = 11
    let content: () -> Value

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.divider, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0.002), 1)))
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
        .animation(.spring(response: 0.6, dampingFraction: 0.9), value: progress)
    }
}

extension View {
    /// Adds the theme's phosphor glow when the theme defines one.
    @ViewBuilder
    func themeGlow(_ theme: ThemeSpec? = nil) -> some View {
        if let glow = theme?.glow {
            self.shadow(color: glow.opacity(0.6), radius: 4)
        } else {
            self
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
                .font(.system(size: 12, weight: .semibold))
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
                    .fill(LinearGradient(colors: [theme.accent, theme.accent2], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * CGFloat(fraction)), height: 6)
                    .themeGlow(theme)
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
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle")
    }
}
