import SwiftUI

/// The apps that live inside the panel. Adding an app = one enum case plus a
/// `fullView` branch — the home screen, dock, and settings pick it up.
enum AppID: String, CaseIterable, Identifiable {
    case monitor
    case clipboard
    case wallpaper
    case awake
    case screenTime
    case music
    case performance
    case settings

    var id: String { rawValue }
}

/// The compact widgets that can occupy a home-screen slot. Battery, network
/// and disk widgets belong to the Monitor app — tapping one opens it.
enum WidgetKind: String, CaseIterable, Identifiable {
    case monitor
    case battery
    case network
    case disk
    case topProcesses
    case clipboard
    case wallpaper
    case awake
    case screenTime
    case music
    case performance
    case settings

    var id: String { rawValue }

    var app: AppID {
        switch self {
        case .monitor, .battery, .network, .disk, .topProcesses: .monitor
        case .clipboard: .clipboard
        case .wallpaper: .wallpaper
        case .awake: .awake
        case .screenTime: .screenTime
        case .music: .music
        case .performance: .performance
        case .settings: .settings
        }
    }

    var name: String {
        switch self {
        case .monitor: "Monitor"
        case .battery: "Battery"
        case .network: "Network"
        case .disk: "Disk"
        case .topProcesses: "Processes"
        case .clipboard: "Clipboard"
        case .wallpaper: "Wallpaper"
        case .awake: "Awake"
        case .screenTime: "Screen Time"
        case .music: "Music"
        case .performance: "Performance"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .monitor: "waveform.path.ecg"
        case .battery: "battery.75percent"
        case .network: "wifi"
        case .disk: "internaldrive"
        case .topProcesses: "cpu"
        case .clipboard: "doc.on.clipboard"
        case .wallpaper: "paintpalette.fill"
        case .awake: "cup.and.saucer.fill"
        case .screenTime: "hourglass"
        case .music: "music.note"
        case .performance: "bolt.fill"
        case .settings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .monitor: .blue
        case .battery: .green
        case .network: .purple
        case .disk: .orange
        case .topProcesses: .mint
        case .clipboard: .pink
        case .wallpaper: .teal
        case .awake: .orange
        case .screenTime: .indigo
        case .music: .red
        case .performance: .yellow
        case .settings: .gray
        }
    }

    /// The compact widget shown in a home-screen slot.
    @ViewBuilder
    var homeWidget: some View {
        switch self {
        case .monitor: MonitorHomeWidget()
        case .battery: BatteryHomeWidget()
        case .network: NetworkHomeWidget()
        case .disk: DiskHomeWidget()
        case .topProcesses: TopProcessesHomeWidget()
        case .clipboard: ClipboardHomeWidget()
        case .wallpaper: WallpaperHomeWidget()
        case .awake: AwakeHomeWidget()
        case .screenTime: ScreenTimeHomeWidget()
        case .music: MusicHomeWidget()
        case .performance: PerformanceHomeWidget()
        case .settings: SettingsHomeWidget()
        }
    }

    /// The layout used when the home screen shows a single full-width slot.
    @ViewBuilder
    var wideWidget: some View {
        switch self {
        case .monitor: MonitorWideWidget()
        case .screenTime: ScreenTimeWideWidget()
        case .music: MusicWideWidget()
        default: homeWidget
        }
    }
}

struct PanelApp: Identifiable {
    let id: AppID
    let name: String
    let symbol: String
    let tint: Color

    static let registry: [AppID: PanelApp] = [
        .monitor: PanelApp(id: .monitor, name: "Monitor", symbol: "waveform.path.ecg", tint: .blue),
        .clipboard: PanelApp(id: .clipboard, name: "Clipboard", symbol: "doc.on.clipboard", tint: .pink),
        .wallpaper: PanelApp(id: .wallpaper, name: "Wallpaper", symbol: "paintpalette.fill", tint: .teal),
        .awake: PanelApp(id: .awake, name: "Awake", symbol: "cup.and.saucer.fill", tint: .orange),
        .screenTime: PanelApp(id: .screenTime, name: "Screen Time", symbol: "hourglass", tint: .indigo),
        .music: PanelApp(id: .music, name: "Music", symbol: "music.note", tint: .red),
        .performance: PanelApp(id: .performance, name: "Performance", symbol: "bolt.fill", tint: .yellow),
        .settings: PanelApp(id: .settings, name: "Settings", symbol: "gearshape.fill", tint: .gray),
    ]

    static func app(_ id: AppID) -> PanelApp { registry[id] ?? registry[.monitor]! }
}

extension AppID {
    /// The full-page app view.
    @ViewBuilder
    var fullView: some View {
        switch self {
        case .monitor: MonitorAppView()
        case .clipboard: ClipboardAppView()
        case .wallpaper: WallpaperAppView()
        case .awake: AwakeAppView()
        case .screenTime: ScreenTimeAppView()
        case .music: MusicAppView()
        case .performance: PerformanceAppView()
        case .settings: SettingsAppView()
        }
    }
}
