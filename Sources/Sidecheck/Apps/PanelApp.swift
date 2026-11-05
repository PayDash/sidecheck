import SwiftUI

/// The apps that live inside the panel. Adding an app = one enum case plus a
/// `fullView` branch — the home screen, dock, and settings pick it up.
enum AppID: String, CaseIterable, Identifiable {
    case monitor
    case clipboard
    case wallpaper
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
    case clipboard
    case wallpaper
    case settings

    var id: String { rawValue }

    var app: AppID {
        switch self {
        case .monitor, .battery, .network, .disk: .monitor
        case .clipboard: .clipboard
        case .wallpaper: .wallpaper
        case .settings: .settings
        }
    }

    var name: String {
        switch self {
        case .monitor: "Monitor"
        case .battery: "Battery"
        case .network: "Network"
        case .disk: "Disk"
        case .clipboard: "Clipboard"
        case .wallpaper: "Wallpaper"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .monitor: "gauge.with.dots.needle.bottom.50percent"
        case .battery: "battery.75percent"
        case .network: "wifi"
        case .disk: "internaldrive"
        case .clipboard: "doc.on.clipboard"
        case .wallpaper: "paintpalette.fill"
        case .settings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .monitor: .blue
        case .battery: .green
        case .network: .purple
        case .disk: .orange
        case .clipboard: .pink
        case .wallpaper: .teal
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
        case .clipboard: ClipboardHomeWidget()
        case .wallpaper: WallpaperHomeWidget()
        case .settings: SettingsHomeWidget()
        }
    }
}

struct PanelApp: Identifiable {
    let id: AppID
    let name: String
    let symbol: String
    let tint: Color

    static let registry: [AppID: PanelApp] = [
        .monitor: PanelApp(id: .monitor, name: "Monitor", symbol: "gauge.with.dots.needle.bottom.50percent", tint: .blue),
        .clipboard: PanelApp(id: .clipboard, name: "Clipboard", symbol: "doc.on.clipboard", tint: .pink),
        .wallpaper: PanelApp(id: .wallpaper, name: "Wallpaper", symbol: "paintpalette.fill", tint: .teal),
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
        case .settings: SettingsAppView()
        }
    }
}
