import Darwin
import Foundation

/// Samples system stats from Mach/IOKit/getifaddrs and publishes the results
/// for SwiftUI. Sampling runs only while the panel is visible.
@MainActor
final class StatsStore: ObservableObject {
    // CPU
    @Published private(set) var cpuUsage: Double = 0 // 0...100
    @Published private(set) var cpuCores: [Double] = [] // per-core 0...100

    // Memory
    @Published private(set) var memoryUsage: Double = 0 // 0...100
    @Published private(set) var usedMemoryBytes: UInt64 = 0
    @Published private(set) var totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    // Battery (nil on desktop Macs without one)
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var isCharging: Bool = false

    // Network (bytes/sec, aggregated over physical interfaces)
    @Published private(set) var netDownBps: Double = 0
    @Published private(set) var netUpBps: Double = 0

    // Disk
    @Published private(set) var diskUsedFraction: Double = 0 // 0...1
    @Published private(set) var diskFreeBytes: UInt64 = 0
    @Published private(set) var diskTotalBytes: UInt64 = 0

    // Uptime
    @Published private(set) var uptimeSeconds: TimeInterval = 0

    // CPU temperature (°C, via SMC; nil when no sensor answers)
    @Published private(set) var cpuTempC: Double?

    /// Rolling history for sparklines (last `historyCapacity` samples, 2 s apart).
    @Published private(set) var cpuHistory: [Double] = [] // 0...1
    @Published private(set) var netDownHistory: [Double] = [] // log-normalized 0...1
    @Published private(set) var netUpHistory: [Double] = [] // log-normalized 0...1

    private let historyCapacity = 60

    private var timer: Timer?
    private var slowTick: Int = 0
    private var previousLoads: [CPULoad]?
    private var previousNet: (rx: UInt64, tx: UInt64, at: Date)?

    /// Diagnostics: sampling runs only while the panel is visible.
    var isSampling: Bool { timer != nil }

    struct CPULoad {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        var total: UInt64 { user + system + idle + nice }
        var busy: UInt64 { user + system + nice }
    }

    func startSampling() {
        guard timer == nil else { return }
        sample() // prime the baselines; real values arrive on the next tick
        // 0.5 Hz: every published tick re-renders the home widgets, and each
        // change arms a display-rate layout pass (measured ~20% CPU at 1 Hz).
        // Two-second samples keep the widgets glanceable at half the cost.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() } // timer runs on the main runloop
        }
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
        previousLoads = nil
        previousNet = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        slowTick += 1
        if slowTick % 5 == 1 { // temperature changes slowly
            cpuTempC = SMCTemp.cpuTemperature()
        }
        if slowTick % 15 == 1 { // battery/disk/uptime change slowly
            sampleBattery()
            sampleDisk()
            uptimeSeconds = ProcessInfo.processInfo.systemUptime
        }
        recordHistory()
    }

    private func recordHistory() {
        func append(_ array: [Double], _ value: Double) -> [Double] {
            var result = array
            result.append(value)
            if result.count > historyCapacity {
                result.removeFirst(result.count - historyCapacity)
            }
            return result
        }
        cpuHistory = append(cpuHistory, min(max(cpuUsage / 100, 0), 1))
        netDownHistory = append(netDownHistory, min(max(log10(1 + netDownBps) / 7, 0), 1))
        netUpHistory = append(netUpHistory, min(max(log10(1 + netUpBps) / 7, 0), 1))
    }

    private func sampleCPU() {
        var processorCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard kr == KERN_SUCCESS, let info = processorInfo else { return }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        var loads: [CPULoad] = []
        loads.reserveCapacity(Int(processorCount))
        for i in 0..<Int(processorCount) {
            let base = i * Int(CPU_STATE_MAX)
            loads.append(CPULoad(
                user: UInt64(info[base + Int(CPU_STATE_USER)]),
                system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[base + Int(CPU_STATE_NICE)])
            ))
        }

        if let previous = previousLoads, previous.count == loads.count {
            var coreLoads: [Double] = []
            coreLoads.reserveCapacity(loads.count)
            var busyDelta: UInt64 = 0
            var totalDelta: UInt64 = 0

            for (p, c) in zip(previous, loads) {
                let dTotal = c.total > p.total ? c.total - p.total : 0
                let dBusy = c.busy > p.busy ? c.busy - p.busy : 0
                busyDelta += dBusy
                totalDelta += dTotal
                coreLoads.append(dTotal > 0 ? min(Double(dBusy) / Double(dTotal) * 100, 100) : 0)
            }

            cpuCores = coreLoads
            cpuUsage = totalDelta > 0 ? Double(busyDelta) / Double(totalDelta) * 100 : 0
        }

        previousLoads = loads
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutableBytes(of: &stats) { buffer in
            host_statistics64(
                mach_host_self(),
                HOST_VM_INFO64,
                buffer.baseAddress!.assumingMemoryBound(to: integer_t.self),
                &count
            )
        }
        guard kr == KERN_SUCCESS else { return }

        // Approximates Activity Monitor's "Memory Used":
        // active (app) + wired + compressed pages.
        let pageSize = UInt64(vm_kernel_page_size)
        usedMemoryBytes = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize

        totalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        memoryUsage = totalMemoryBytes > 0 ? Double(usedMemoryBytes) / Double(totalMemoryBytes) * 100 : 0
    }

    private func sampleNetwork() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let item = current.pointee
            if let addr = item.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = item.ifa_data,
               let name = item.ifa_name.map({ String(cString: $0) }),
               !name.hasPrefix("lo"), !name.hasPrefix("awdl"), !name.hasPrefix("llw"), !name.hasPrefix("bridge") {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(ifData.ifi_ibytes)
                tx += UInt64(ifData.ifi_obytes)
            }
            cursor = item.ifa_next
        }

        if let previous = previousNet {
            let dt = previous.at.distance(to: Date())
            if dt > 0.2 {
                netDownBps = rx > previous.rx ? Double(rx - previous.rx) / dt : 0
                netUpBps = tx > previous.tx ? Double(tx - previous.tx) / dt : 0
            }
        }
        previousNet = (rx, tx, Date())
    }

    private func sampleBattery() {
        if let battery = BatteryInfo.current() {
            batteryPercent = battery.percent
            isCharging = battery.isCharging
        } else {
            batteryPercent = nil // desktop Mac, no battery
        }
    }

    private func sampleDisk() {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacity else { return }
        diskTotalBytes = UInt64(max(0, total))
        diskFreeBytes = UInt64(max(0, available))
        diskUsedFraction = total > 0 ? Double(total - available) / Double(total) : 0
    }
}
