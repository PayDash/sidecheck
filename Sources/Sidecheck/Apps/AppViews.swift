import SwiftUI
import IOKit

// MARK: - System info helpers

enum SystemInfo {
    /// GPU model names from the IORegistry ("IOAccelerator" services).
    /// Utilization is NOT exposed by public macOS APIs, so only identity here.
    static let gpuNames: [String] = {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var names: [String] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let raw = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "Model" as CFString, kCFAllocatorDefault,
                UInt32(kIORegistryIterateRecursively | kIORegistryIterateParents)
            ) {
                let name: String
                if let data = raw as? Data {
                    let bytes = data.prefix { $0 != 0 }
                    name = String(decoding: bytes, as: UTF8.self)
                } else if let string = raw as? String {
                    name = string
                } else {
                    name = ""
                }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { names.append(trimmed) }
            }
            service = IOIteratorNext(iterator)
        }
        return names
    }()
}

// MARK: - Monitor app

struct MonitorAppView: View {
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var processes: ProcessStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                CPUCard(stats: stats)
                HStack(alignment: .top, spacing: 12) {
                    MemoryCard(stats: stats)
                    BatteryCard(stats: stats)
                }
                ProcessesCard(processes: processes)
                NetworkCard(stats: stats)
                DiskCard(stats: stats)
                GPUCard()
                UptimeChip(stats: stats)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(14)
        }
    }
}

struct GPUCard: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "display", title: "GPU")
                if SystemInfo.gpuNames.isEmpty {
                    Text("GPU information unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    ForEach(SystemInfo.gpuNames, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "cpu")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.accent)
                            Text(name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
                Text("Utilization isn't exposed by public macOS APIs")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - Settings app

struct SettingsAppView: View {
    var body: some View {
        SettingsView()
    }
}
