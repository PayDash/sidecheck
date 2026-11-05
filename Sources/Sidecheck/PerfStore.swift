import Combine
import Darwin
import Foundation

/// Self-performance monitor for the diagnostics panel. Samples this process
/// once per second: CPU time (task_info), then memory footprint, idle
/// wakeups, syscalls and context switches (proc_pid_rusage). Two cheap
/// syscalls per tick, run for the app's lifetime so the "while hidden"
/// baseline is captured long before Settings is ever opened.
@MainActor
final class PerfStore: ObservableObject {
    struct Snapshot: Equatable {
        var cpuPercent: Double            // % of one core (all threads summed)
        var footprintBytes: UInt64        // phys footprint, Activity-Monitor-style
        var syscallsPerSec: Double        // mach + unix
        var contextSwitchesPerSec: Double
        var idleWakeupsPerSec: Double     // the classic menubar-app battery sin
        var threads: Int
    }

    /// One recorded sample; `panelWasVisible` tags the state it was taken in.
    struct Sample: Equatable {
        var snapshot: Snapshot
        var panelWasVisible: Bool
    }

    static let historyCapacity = 120 // 2 minutes of 1 Hz samples

    @Published private(set) var current: Snapshot?
    @Published private(set) var samples: [Sample] = []

    /// Returns whether the panel is visible right now — samples are tagged so
    /// the hidden baseline can be separated from visible UI cost.
    var visibilityProvider: (() -> Bool)?

    private var timer: Timer?
    private var lastCPUTimeMicro: Int64?
    private var lastRusage: rusage_info_v4?
    private var lastTaskInfo: proc_taskinfo?
    private var lastSampleDate: Date?
    private var logToStderr = false
    private var logTick = 0
    private let startedAt = Date()

    var appUptime: TimeInterval { Date().timeIntervalSince(startedAt) }

    func start() {
        guard timer == nil else { return }
        logToStderr = ProcessInfo.processInfo.environment["SIDECHECK_PERFLOG"] == "1"
        sample() // prime the counters; rates start on the next tick
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    /// Mean CPU% / idle wakeups over recent hidden samples — the number that
    /// answers "is this app burning battery while I'm not using it?".
    /// Needs at least 10 hidden samples to say anything.
    var hiddenBaseline: (cpuPercent: Double, idleWakeupsPerSec: Double)? {
        let hidden = samples.suffix(60).filter { !$0.panelWasVisible }
        guard hidden.count >= 10 else { return nil }
        let cpu = hidden.map(\.snapshot.cpuPercent).reduce(0, +) / Double(hidden.count)
        let wakeups = hidden.map(\.snapshot.idleWakeupsPerSec).reduce(0, +) / Double(hidden.count)
        return (cpu, wakeups)
    }

    // MARK: - Sampling

    private func sample() {
        let now = Date()
        let cpuTime = currentCPUTimeMicro()
        let rusage = currentRusage()
        let taskInfo = currentTaskInfo()

        defer {
            lastCPUTimeMicro = cpuTime
            lastRusage = rusage
            lastTaskInfo = taskInfo
            lastSampleDate = now
        }
        guard let cpuTime, let rusage else { return }

        var snapshot = Snapshot(
            cpuPercent: 0,
            footprintBytes: rusage.ri_phys_footprint,
            syscallsPerSec: 0,
            contextSwitchesPerSec: 0,
            idleWakeupsPerSec: 0,
            threads: Int(taskInfo?.pti_threadnum ?? 0)
        )

        if let last = lastRusage, let lastDate = lastSampleDate {
            let dt = now.timeIntervalSince(lastDate)
            if dt > 0.2 {
                let cpuDelta = Double(cpuTime - (lastCPUTimeMicro ?? cpuTime))
                snapshot.cpuPercent = min(max(cpuDelta / (dt * 1_000_000) * 100, 0), 800)
                func rate(_ keyPath: KeyPath<rusage_info_v4, UInt64>) -> Double {
                    Double(rusage[keyPath: keyPath] &- last[keyPath: keyPath]) / dt
                }
                snapshot.idleWakeupsPerSec = rate(\.ri_pkg_idle_wkups) + rate(\.ri_interrupt_wkups)
                if let lastTaskInfo = lastTaskInfo, let taskInfo {
                    func taskRate(_ keyPath: KeyPath<proc_taskinfo, Int32>) -> Double {
                        Double(taskInfo[keyPath: keyPath] &- lastTaskInfo[keyPath: keyPath]) / dt
                    }
                    snapshot.syscallsPerSec = taskRate(\.pti_syscalls_mach) + taskRate(\.pti_syscalls_unix)
                    snapshot.contextSwitchesPerSec = taskRate(\.pti_csw)
                }
            }
        }

        current = snapshot
        samples.append(Sample(snapshot: snapshot, panelWasVisible: visibilityProvider?() ?? false))
        if samples.count > Self.historyCapacity {
            samples.removeFirst(samples.count - Self.historyCapacity)
        }

        // SIDECHECK_PERFLOG=1: one stderr line per 5 s for headless checks.
        logTick += 1
        if logToStderr, logTick % 5 == 0 {
            fputs(String(
                format: "[Sidecheck] perf: cpu %.2f%% mem %.1fMB wakeups %.1f/s syscalls %.0f/s csw %.0f/s threads %d visible=%@\n",
                snapshot.cpuPercent,
                Double(snapshot.footprintBytes) / 1_048_576,
                snapshot.idleWakeupsPerSec,
                snapshot.syscallsPerSec,
                snapshot.contextSwitchesPerSec,
                snapshot.threads,
                samples.last?.panelWasVisible == true ? "yes" : "no"
            ), stderr)
        }
    }

    /// Total user+system CPU time of all the task's threads, in microseconds
    /// (time_value_t is explicitly seconds + microseconds — no unit guessing).
    private func currentCPUTimeMicro() -> Int64? {
        var times = task_thread_times_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_thread_times_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &times) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        func micro(_ value: time_value_t) -> Int64 {
            Int64(value.seconds) * 1_000_000 + Int64(value.microseconds)
        }
        return micro(times.user_time) + micro(times.system_time)
    }

    /// proc_pid_rusage's buffer is a plain void* — the kernel writes the
    /// struct straight into the address you pass (C callers cast `&struct`
    /// to it), NOT into a pointer-to-pointer slot.
    private func currentRusage() -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutableBytes(of: &info) { raw -> Int32 in
            proc_pid_rusage(
                getpid(), RUSAGE_INFO_V4,
                raw.baseAddress!.assumingMemoryBound(to: rusage_info_t?.self)
            )
        }
        guard result == 0 else { return nil }
        return info
    }

    /// Syscalls, context switches and thread count (rusage doesn't carry them).
    private func currentTaskInfo() -> proc_taskinfo? {
        var info = proc_taskinfo()
        let written = proc_pidinfo(
            getpid(), PROC_PIDTASKINFO, 0, &info,
            Int32(MemoryLayout<proc_taskinfo>.size)
        )
        guard written == Int32(MemoryLayout<proc_taskinfo>.size) else { return nil }
        return info
    }
}
