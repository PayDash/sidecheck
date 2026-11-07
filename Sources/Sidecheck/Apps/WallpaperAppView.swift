import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// The Wallpaper app: pick what renders behind the panel for the current
/// theme — theme-native animation, another theme's animated style, a solid
/// color, a gradient, a picture or a looping video. Pictures and videos get a
/// pan/zoom crop editor so oversized media can be positioned exactly; the
/// live panel behind the page is the preview.
struct WallpaperAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var themes: ThemeStore
    @EnvironmentObject var wallpaper: WallpaperStore

    private var spec: BackgroundSpec { wallpaper.spec(for: themes.current) }

    private func update(_ transform: (inout BackgroundSpec) -> Void) {
        var next = spec
        transform(&next)
        wallpaper.set(next, for: themes.current)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                headerNote

                sectionLabel("ANIMATED")
                animatedCard

                sectionLabel("SOLID COLOR")
                solidCard

                sectionLabel("GRADIENTS")
                gradientCard

                sectionLabel("PICTURE")
                pictureCard

                sectionLabel("VIDEO")
                videoCard


                footerActions
            }
            .padding(16)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.textTertiary)
    }

    private var headerNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accent)
                .themeGlow(theme)
            Text("Customizing — \(themes.current.displayName)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(theme.cardFill, in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }

    // MARK: Animated

    private var animatedCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    animatedTile(.theme, name: "Current", colors: [theme.accent.opacity(0.7), theme.accent2.opacity(0.45)])
                    animatedTile(.bubbles, name: "Bubbles", colors: [Color.white.opacity(0.35), Color.blue.opacity(0.4)])
                    animatedTile(.blobs, name: "Blobs", colors: [Color(red: 0.93, green: 0.95, blue: 0.98), Color(red: 0.72, green: 0.82, blue: 1.0)])
                    animatedTile(.crt, name: "CRT", colors: [Color.black, Color(red: 0.05, green: 0.32, blue: 0.13)])
                }
                Text("All animations run at 30 fps and pause while the panel is hidden.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func animatedTile(_ kind: BackgroundKind, name: String, colors: [Color]) -> some View {
        kindTile(kind: kind, name: name) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// One selectable background-kind tile with a swatch + selection chrome.
    /// `select` overrides the default "just set the kind" behavior (gradient
    /// tiles also record which preset was picked); `isSelected` overrides the
    /// default kind equality — gradient tiles must compare `gradientID` too,
    /// otherwise one click highlights every preset.
    private func kindTile(kind: BackgroundKind, name: String, select: ((inout BackgroundSpec) -> Void)? = nil, isSelected overrideSelected: Bool? = nil, swatch: () -> LinearGradient) -> some View {
        let isSelected = overrideSelected ?? (spec.kind == kind)
        return Button {
            if let select {
                update(select)
            } else {
                update { $0.kind = kind }
            }
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(swatch())
                    .frame(height: 34)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(theme.accent, lineWidth: 2.5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.accent)
                                .background(Circle().fill(.white))
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }

    // MARK: Solid

    private var solidCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)], spacing: 8) {
                    ForEach(Self.solidPresets, id: \.self) { color in
                        solidSwatch(color)
                    }
                }
                HStack {
                    ColorPicker("Custom color", selection: Binding(
                        get: { spec.color?.color ?? Self.solidPresets[0] },
                        set: { newValue in
                            update {
                                $0.kind = .solid
                                $0.color = RGBA(newValue)
                            }
                        }
                    ), supportsOpacity: false)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    Spacer()
                }
            }
        }
    }

    private func solidSwatch(_ color: Color) -> some View {
        let isSelected = spec.kind == .solid && spec.color?.color == color
        return Button {
            update {
                $0.kind = .solid
                $0.color = RGBA(color)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(theme.cardStroke, lineWidth: 1))
                if isSelected {
                    Circle()
                        .strokeBorder(theme.accent, lineWidth: 2.5)
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private static let solidPresets: [Color] = [
        .white, .black,
        Color(red: 0.10, green: 0.11, blue: 0.14),
        Color(red: 0.10, green: 0.25, blue: 0.45),
        .blue, .teal, .green, .yellow,
        .orange, .red, .pink, .purple,
    ]

    // MARK: Gradients

    private var gradientCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(GradientPresets.all) { preset in
                        gradientTile(preset)
                    }
                }
                if spec.kind == .gradient {
                    HStack {
                        Text("Angle")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text(String(format: "%.0f°", spec.gradientAngle))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                    PanelSlider(value: Binding(
                        get: { spec.gradientAngle },
                        set: { newValue in update { $0.gradientAngle = newValue } }
                    ), range: 0...360)
                }
            }
        }
    }

    private func gradientTile(_ preset: GradientPresets.Preset) -> some View {
        kindTile(
            kind: .gradient,
            name: preset.name,
            select: { spec in
                spec.kind = .gradient
                spec.gradientID = preset.id
            },
            isSelected: spec.kind == .gradient && spec.gradientID == preset.id
        ) {
            LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Picture

    private var pictureCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "photo", title: "Picture")
                if spec.kind == .image, let path = spec.filePath {
                    if WallpaperStore.mediaExists(path) {
                        CropEditorView(mode: .image(path: path), crop: cropBinding)
                        HStack {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                            Spacer()
                            smallButton("Replace") { pickMedia(images: true) }
                        }
                    } else {
                        missingMediaRow
                    }
                } else {
                    chooseButton("Choose image…") { pickMedia(images: true) }
                }
            }
        }
    }

    // MARK: Video

    private var videoCard: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "film", title: "Video")
                if spec.kind == .video, let path = spec.filePath {
                    if WallpaperStore.mediaExists(path) {
                        CropEditorView(mode: .video(path: path), crop: cropBinding, muted: spec.isMuted)
                        HStack(spacing: 10) {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                            Spacer()
                            HStack(spacing: 6) {
                                Text("Sound")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textSecondary)
                                ThemeSwitch(isOn: Binding(
                                    get: { !spec.isMuted },
                                    set: { newValue in update { $0.isMuted = !newValue } }
                                ))
                            }
                            smallButton("Replace") { pickMedia(images: false) }
                        }
                    } else {
                        missingMediaRow
                    }
                } else {
                    chooseButton("Choose video…") { pickMedia(images: false) }
                }
            }
        }
    }

    private var missingMediaRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text("File is missing — showing the theme background until you pick a new one.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.textTertiary)
            Spacer()
            smallButton("Pick new") { pickMedia(images: spec.kind == .image) }
        }
    }

    private func chooseButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous)
                        .strokeBorder(theme.accent.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(theme.cardFill, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var cropBinding: Binding<CropSpec> {
        Binding(
            get: { spec.crop },
            set: { newValue in update { $0.crop = newValue } }
        )
    }

    private func pickMedia(images: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = images ? [.image] : [.movie]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            update {
                $0.kind = images ? .image : .video
                $0.filePath = url.path
                $0.crop = .default
            }
        }
    }

    // MARK: Footer

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                wallpaper.reset(for: themes.current)
            } label: {
                Label("Reset to theme", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.cardFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(spec == .themeDefault)
            .opacity(spec == .themeDefault ? 0.4 : 1)

            Button {
                wallpaper.applyToAllThemes(spec)
            } label: {
                Label("Apply to all themes", systemImage: "square.on.square.intersection.dashed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(spec == .themeDefault)
            .opacity(spec == .themeDefault ? 0.4 : 1)
            Spacer()
        }
    }
}

// MARK: - Crop editor

/// Pan/zoom editor for picture & video wallpapers. Renders the media with the
/// exact same math as the live panel background (WallpaperMediaView), locked
/// to the current theme's frame aspect. Drag to pan, pinch or use the slider
/// to zoom; offsets are clamped so the media always covers the viewport.
struct CropEditorView: View {
    enum Mode {
        case image(path: String)
        case video(path: String)
    }

    @Environment(\.theme) private var theme
    @EnvironmentObject var themes: ThemeStore
    let mode: Mode
    @Binding var crop: CropSpec
    /// Video: follow the spec's sound setting — the editor and the panel
    /// share one AVPlayer, so hardcoding either would fight the other.
    var muted: Bool = true

    @State private var gestureStart: CropSpec?

    private var aspect: CGFloat {
        let size = themes.current.spec.frameSize
        return size.width / max(size.height, 1)
    }

    var body: some View {
        GeometryReader { outer in
            let height = min(210, outer.size.width / aspect)
            let width = height * aspect
            editorContent(size: CGSize(width: width, height: height))
                .frame(width: width, height: height)
                .position(x: outer.size.width / 2, y: outer.size.height / 2)
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private func editorContent(size: CGSize) -> some View {
        VStack(spacing: 8) {
            WallpaperMediaView(
                path: mediaPath,
                crop: crop,
                paused: false, // the editor is only on screen while visible
                video: isVideo,
                muted: muted
            )
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.cardStroke, lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                Text("Drag to move · pinch or slide to zoom")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(6)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: size))
            .simultaneousGesture(magnificationGesture(size: size))

            Slider(value: Binding(
                get: { Double(crop.scale) },
                set: { newValue in
                    var next = crop
                    next.scale = CGFloat(newValue)
                    crop = Self.clamp(next, mode: mode, viewport: size)
                }
            ), in: 1...5)
            .controlSize(.mini)
        }
    }

    private var mediaPath: String? {
        switch mode {
        case .image(let path), .video(let path): path
        }
    }

    private var isVideo: Bool {
        if case .video = mode { return true }
        return false
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = gestureStart ?? crop
                gestureStart = start
                var next = start
                next.offsetX = start.offsetX + value.translation.width / size.width
                next.offsetY = start.offsetY + value.translation.height / size.height
                crop = Self.clamp(next, mode: mode, viewport: size)
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func magnificationGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let start = gestureStart ?? crop
                gestureStart = start
                var next = start
                next.scale = start.scale * value
                crop = Self.clamp(next, mode: mode, viewport: size)
            }
            .onEnded { _ in gestureStart = nil }
    }

    /// Keeps the media covering the viewport: scale 1...5, offsets clamped to
    /// the overhang (image math uses the media's own aspect; video uses the
    /// aspect-fill layer frame rule (scale-1)/2).
    static func clamp(_ crop: CropSpec, mode: Mode, viewport: CGSize) -> CropSpec {
        var next = crop
        next.scale = min(max(next.scale, 1), 5)

        let maxX: CGFloat
        let maxY: CGFloat
        switch mode {
        case .image(let path):
            if let image = WallpaperStore.cachedImage(path) {
                let size = image.size
                let base = max(viewport.width / max(size.width, 1), viewport.height / max(size.height, 1))
                maxX = max(0, (size.width * base * next.scale - viewport.width) / 2) / max(viewport.width, 1)
                maxY = max(0, (size.height * base * next.scale - viewport.height) / 2) / max(viewport.height, 1)
            } else {
                maxX = 0
                maxY = 0
            }
        case .video:
            maxX = max(0, (next.scale - 1) / 2)
            maxY = maxX
        }
        next.offsetX = min(max(next.offsetX, -maxX), maxX)
        next.offsetY = min(max(next.offsetY, -maxY), maxY)
        return next
    }
}
