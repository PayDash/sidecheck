import Darwin
import Foundation

/// One process row for the Monitor page and the home widget.
struct ProcessSample: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpuPercent: Double // Activity-Monitor style: 100% = one full core
    let memBytes: UInt64

    var id: Int32 { pid }
}

enum ProcessMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"

    var id: String { rawValue }
}

/// Samples every process's CPU% and memory while the panel is visible
/// (StatsStore gating — nothing runs hidden). CPU% comes from the delta of
/// per-pid CPU time between ticks, Activity-Monitor style (100% = one core).
@MainActor
final class ProcessStore: ObservableObject {
    @Published private(set) var processes: [ProcessSample] = []
    @Published var metric: ProcessMetric = .cpu {
        didSet { republishSorted() }
    }

    /// Rows shown on the Monitor page and mirrored in the widget.
    private static let capacity = 6
    /// Names resolve through proc_pidpath/proc_name — cached per pid so each
    /// tick only pays for newly seen processes.
    private var names: [Int32: String] = [:]
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousAt: Date?
    private var timer: Timer?

    /// Performance features drive whether the scan runs at all (2 s / paused).
    /// Wired in PanelController.init.
    var featuresProvider: (() -> Set<PerformanceFeature>)?

    var isSampling: Bool { timer != nil }
    var isScanEnabled: Bool { featuresProvider?().contains(.processScanning) ?? true }

    func startSampling() {
        guard timer == nil else { return }
        sample() // prime the CPU-time baselines; real values arrive next tick
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stopSampling() {
        timer?.invalidate()
        timer = nil
        previousCPU = [:]
        previousAt = nil
    }

    /// SIGTERM to a user-owned process (proc_listallpids only ever sees the
    /// calling user's processes without privileges).
    func terminate(_ sample: ProcessSample) {
        kill(sample.pid, SIGTERM)
        fputs("[Sidecheck] processes: SIGTERM → \(sample.name) (pid \(sample.pid))\n", stderr)
    }

    private func sample() {
        guard isScanEnabled else { return } // paused by performance mode
        let profile = ProcessInfo.processInfo.environment["SIDECHECK_SAMPLETIME"] == "1"
        let t0 = profile ? Date() : nil
        defer {
            if let t0 {
                let ms = Date().timeIntervalSince(t0) * 1000
                if ms > 25 { fputs("[Sidecheck] processes.sample: \(Int(ms)) ms\n", stderr) }
            }
        }

        let now = Date()
        let requested = proc_listallpids(nil, 0)
        guard requested > 0 else { return }
        // Headroom for processes that appeared since the count call.
        var pids = [pid_t](repeating: 0, count: Int(requested) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        var cpuNow: [Int32: UInt64] = [:]
        var memNow: [Int32: UInt64] = [:]
        cpuNow.reserveCapacity(Int(count))
        memNow.reserveCapacity(Int(count))

        for index in 0..<Int(count) {
            let pid = pids[index]
            if pid <= 1 || pid == selfPID { continue }
            guard let usage = Self.readUsage(pid: pid) else { continue } // exited / kernel
            cpuNow[pid] = usage.cpuNS
            memNow[pid] = usage.memBytes
        }


        var cpuPercent: [Int32: Double] = [:]
        if let previousAt, !previousCPU.isEmpty {
            let dt = now.timeIntervalSince(previousAt)
            if dt > 0.5 {
                for (pid, cpu) in cpuNow {
                    let previous = previousCPU[pid] ?? cpu
                    let delta = cpu > previous ? cpu - previous : 0
                    // ri_user_time/system_time are lifetime NANOSECONDS
                    // (proc_taskinfo's pti_total_* turned out to be unreliable
                    // on this OS build — a 98%-CPU burner read as 2%).
                    cpuPercent[pid] = Double(delta) / dt / 1_000_000_000 * 100
                }
            }
        }
        previousCPU = cpuNow
        previousAt = now

        // Sort by the current metric, then resolve names for just the top rows
        // (proc_pidpath is the expensive call; only the top 6 are shown).
        let metric = self.metric
        let topPIDs = cpuNow.keys.sorted { a, b in
            switch metric {
            case .cpu: (cpuPercent[a] ?? 0, memNow[a] ?? 0) > (cpuPercent[b] ?? 0, memNow[b] ?? 0)
            case .memory: memNow[a] ?? 0 > memNow[b] ?? 0
            }
        }
        .prefix(Self.capacity)

        var samples: [ProcessSample] = []
        samples.reserveCapacity(Self.capacity)
        for pid in topPIDs {
            samples.append(ProcessSample(
                pid: pid,
                name: self.name(for: pid),
                cpuPercent: min(cpuPercent[pid] ?? 0, 999),
                memBytes: memNow[pid] ?? 0
            ))
        }
        processes = samples
    }

    /// CPU (ns) + phys footprint (bytes, Activity-Monitor-style).
    ///
    /// The task-level CPU counters (proc_pid_rusage's ri_user_time etc. and
    /// PROC_PIDTASKINFO's pti_total_*) are billing-clamped for other
    /// processes on this OS build — a 98%-CPU burner reads as ~2%. Per-THREAD
    /// times (PROC_PIDTHREADINFO) are honest (verified: 99.3% on the same
    /// burner), so CPU = the sum of per-thread times. Top's own method
    /// (mach task ports) needs the com.apple.system-task-ports.read
    /// entitlement, which AMFI strips from ad-hoc-signed apps.
    ///
    /// The rusage buffer is a plain void* the kernel writes the struct INTO —
    /// pass the struct's own address (PerfStore precedent).
    private static func readUsage(pid: Int32) -> (cpuNS: UInt64, memBytes: UInt64)? {
        var rinfo = rusage_info_v4()
        let rresult = withUnsafeMutableBytes(of: &rinfo) { raw -> Int32 in
            proc_pid_rusage(
                pid, RUSAGE_INFO_V4,
                raw.baseAddress!.assumingMemoryBound(to: rusage_info_t?.self)
            )
        }
        guard rresult == 0 else { return nil }

        var threads = [UInt64](repeating: 0, count: 1024)
        let threadBytes = proc_pidinfo(
            pid, PROC_PIDLISTTHREADS, 0,
            &threads, Int32(threads.count * MemoryLayout<UInt64>.stride)
        )
        guard threadBytes > 0 else { return nil }
        let threadCount = Int(threadBytes) / MemoryLayout<UInt64>.size

        var cpuNS: UInt64 = 0
        for index in 0..<min(threadCount, threads.count) {
            var tinfo = proc_threadinfo()
            let read = proc_pidinfo(
                pid, PROC_PIDTHREADINFO, threads[index],
                &tinfo, Int32(MemoryLayout<proc_threadinfo>.size)
            )
            if read == Int32(MemoryLayout<proc_threadinfo>.size) {
                cpuNS += tinfo.pth_user_time + tinfo.pth_system_time
            }
        }
        return (cpuNS, rinfo.ri_phys_footprint)
    }

    private func republishSorted() {
        let metric = self.metric
        processes.sort { a, b in
            switch metric {
            case .cpu: a.cpuPercent > b.cpuPercent
            case .memory: a.memBytes > b.memBytes
            }
        }
    }

    /// PROC_PIDPATHINFO_MAXSIZE is a C macro and doesn't cross into Swift.
    private static let pathBufferSize = 4096

    private func name(for pid: Int32) -> String {
        if let cached = names[pid] { return cached }
        var path = [CChar](repeating: 0, count: Self.pathBufferSize)
        var resolved: String?
        if proc_pidpath(pid, &path, UInt32(Self.pathBufferSize)) > 0 {
            let full = String(cString: path)
            let base = full.split(separator: "/").last.map(String.init)
            resolved = base
        }
        if resolved == nil || resolved?.isEmpty == true {
            var comm = [CChar](repeating: 0, count: 128)
            if proc_name(pid, &comm, UInt32(comm.count)) > 0 {
                resolved = String(cString: comm)
            }
        }
        let value = resolved ?? "pid \(pid)"
        names[pid] = value
        return value
    }
}
