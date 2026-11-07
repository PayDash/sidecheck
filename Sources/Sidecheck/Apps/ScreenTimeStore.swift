import AppKit
import CoreGraphics
import Foundation

// MARK: - Data model

/// One app's usage within a day. The dictionary key holding it is the app's
/// bundle identifier, or "exec:<name>" for processes without a bundle.
struct AppUsage: Codable, Equatable {
    var name: String
    var seconds: Double = 0
    /// Seconds per hour-of-day (24 buckets) for the hourly chart.
    var hourly: [Double] = Array(repeating: 0, count: 24)

    private enum CodingKeys: String, CodingKey { case name, seconds, hourly }

    init(name: String) {
        self.name = name
    }

    // Hand-rolled decode with decodeIfPresent: synthesized Codable demands
    // every non-optional key, so a field added later would brick persisted
    // data. Encodable stays synthesized. (Backgrounds.swift precedent.)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        hourly = try container.decodeIfPresent([Double].self, forKey: .hourly)
            ?? Array(repeating: 0, count: 24)
    }
}

/// A calendar day's usage, persisted under the "yyyy-MM-dd" key.
struct UsageDay: Codable, Equatable {
    var date: String
    var apps: [String: AppUsage] = [:]

    private enum CodingKeys: String, CodingKey { case date, apps }

    init(date: String) {
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        apps = try container.decodeIfPresent([String: AppUsage].self, forKey: .apps) ?? [:]
    }
}

// MARK: - Read model

/// An app's usage entry ready for the UI.
struct AppUsageEntry: Identifiable {
    let key: String
    let usage: AppUsage
    var id: String { key }
}

/// One bar of the week chart.
struct DayPoint: Identifiable, Equatable {
    let dayKey: String
    let total: Double
    var id: String { dayKey }
}

/// Immutable aggregates recomputed on the store's slow publish cadence
/// (app switches + the 30 s flush cycle — never at tick rate; a home slot
/// with rapidly changing text arms a display-rate AppKit layout loop).
struct ActivitySnapshot {
    var todayKey = ""
    var todayTotal = 0.0
    var todayHourly: [Double] = Array(repeating: 0, count: 24)
    var todayApps: [AppUsageEntry] = []
    var week: [DayPoint] = []
    var weekTotal = 0.0
    var weekApps: [AppUsageEntry] = []
    var nowApp: String?
    var pauseNote: String?
}

// MARK: - Store

/// Tracks which app is frontmost and credits it seconds, ScreenTime-style.
///
/// Model: NSWorkspace's `didActivateApplicationNotification` fires on every
/// switch; a 1 s heartbeat credits elapsed time to the current app and checks
/// idle. Nothing here needs a TCC permission (same approach as ActivityWatch):
/// app identity comes from NSWorkspace, idle from CGEventSource, and screen
/// lock/sleep/fast-user-switch notifications pause the clock. Runs for the
/// app's lifetime (ClipboardStore model) — usage accrues while the panel is
/// closed. Everything stays in UserDefaults on this Mac.
@MainActor
final class ScreenTimeStore: ObservableObject {
    static let daysKey = "screenTimeDays"
    static let enabledKey = "screenTimeEnabled"
    static let idleMinutesKey = "screenTimeIdleMinutes"
    static let retentionDays = 90
    private static let tickInterval: TimeInterval = 1.0
    private static let flushTicks = 30
    /// One credit never exceeds this — bounds damage from clock jumps or a
    /// coalesced timer firing late after sleep.
    private static let maxCreditChunk: TimeInterval = 60

    @Published private(set) var snapshot = ActivitySnapshot()
    @Published var trackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(trackingEnabled, forKey: Self.enabledKey)
            if trackingEnabled {
                suspensions.remove(.disabled)
                startTracking()
            } else {
                creditPending()
                suspensions.insert(.disabled)
                stopTimer()
                flushNow()
                refreshSnapshot()
            }
        }
    }
    /// Minutes without keyboard/mouse input before the clock pauses.
    @Published var idleMinutes: Int {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: Self.idleMinutesKey) }
    }

    private var days: [String: UsageDay] = [:]
    private var timer: Timer?
    private var dirty = false
    private var ticksSinceFlush = 0

    // Live tracking state.
    private var currentKey: String?
    private var currentName: String?
    private var lastCredit: Date?
    private var isIdle = false
    private var didSeed = false
    private enum SuspendReason: String {
        case locked, sleeping, userSwitch, disabled
    }
    private var suspensions: Set<SuspendReason> = []

    // Icons resolve through LaunchServices (filesystem work) — done off the
    // view-body path, memoized here; views read the cache only.
    private var iconCache: [String: NSImage] = [:]
    private var resolvedIconKeys: Set<String> = []

    private var wsObserverTokens: [NSObjectProtocol] = []
    private var distributedObserverTokens: [NSObjectProtocol] = []
    private let logEnabled: Bool

    /// Diagnostics: the tracker runs for the app's lifetime while enabled.
    var isTracking: Bool { timer != nil }

    init() {
        let defaults = UserDefaults.standard
        trackingEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        idleMinutes = defaults.object(forKey: Self.idleMinutesKey) as? Int ?? 2
        logEnabled = ProcessInfo.processInfo.environment["SIDECHECK_SCREENTIME_LOG"] == "1"
        if let data = defaults.data(forKey: Self.daysKey)
            ?? defaults.string(forKey: Self.daysKey)?.data(using: .utf8),
           let saved = try? JSONDecoder().decode([String: UsageDay].self, from: data) {
            days = saved
        }
        pruneOldDays()
        installObservers()
        refreshSnapshot()
    }

    deinit {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for token in wsObserverTokens { wsCenter.removeObserver(token) }
        let distCenter = DistributedNotificationCenter.default()
        for token in distributedObserverTokens { distCenter.removeObserver(token) }
    }

    // MARK: Lifecycle

    func startTracking() {
        guard trackingEnabled else { return }
        installObservers()
        applySeedIfNeeded()
        guard timer == nil else { return }
        adoptFrontmost()
        lastCredit = Date()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        fputs("[Sidecheck] screentime: tracking started\n", stderr)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Installs the switch/sleep/lock observers once per process.
    private func installObservers() {
        guard wsObserverTokens.isEmpty, distributedObserverTokens.isEmpty else { return }
        let wsCenter = NSWorkspace.shared.notificationCenter
        func wsObserver(for name: NSNotification.Name, _ handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
            wsCenter.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            }
        }
        wsObserverTokens.append(wsObserver(for: NSWorkspace.didActivateApplicationNotification) { [weak self] in
            self?.handleActivation($0)
        })
        wsObserverTokens.append(wsObserver(for: NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.suspend(.sleeping)
        })
        wsObserverTokens.append(wsObserver(for: NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.resume(.sleeping)
        })
        wsObserverTokens.append(wsObserver(for: NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in
            self?.suspend(.userSwitch)
        })
        wsObserverTokens.append(wsObserver(for: NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in
            self?.resume(.userSwitch)
        })
        let distCenter = DistributedNotificationCenter.default()
        distributedObserverTokens.append(distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend(.locked) }
        })
        distributedObserverTokens.append(distCenter.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume(.locked) }
        })
    }

    // MARK: Event handlers

    private func handleActivation(_ note: Notification) {
        guard trackingEnabled,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        // Sidecheck is a hover panel, not a real frontmost app — if it ever
        // activates, pause rather than track ourselves.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            creditPending()
            currentKey = nil
            currentName = nil
            lastCredit = Date()
            return
        }
        let key = Self.key(for: app)
        if key == currentKey {
            currentName = currentName ?? app.localizedName
            return
        }
        creditPending()
        currentKey = key
        currentName = app.localizedName
        lastCredit = Date()
        bumpSnapshot()
        if logEnabled {
            fputs("[Sidecheck] screentime: switched → \(app.localizedName ?? key)\n", stderr)
        }
    }

    private func adoptFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        currentKey = Self.key(for: app)
        currentName = app.localizedName
    }

    private func suspend(_ reason: SuspendReason) {
        guard suspensions.insert(reason).inserted else { return }
        creditPending()
        flushNow()
        refreshSnapshot()
        if logEnabled { fputs("[Sidecheck] screentime: paused (\(reason.rawValue))\n", stderr) }
    }

    private func resume(_ reason: SuspendReason) {
        guard suspensions.remove(reason) != nil else { return }
        if suspensions.isEmpty {
            lastCredit = Date()
            refreshSnapshot()
        }
        if logEnabled { fputs("[Sidecheck] screentime: resumed (\(reason.rawValue))\n", stderr) }
    }

    // MARK: Heartbeat

    private func tick() {
        guard trackingEnabled else { return }
        let now = Date()

        // Midnight rollover: point "today" at the new day.
        if Self.dayKey(now) != snapshot.todayKey {
            refreshSnapshot()
        }

        let idle = Self.secondsSinceInput()
        let idleThreshold = Double(idleMinutes) * 60

        if isIdle {
            if idle < idleThreshold {
                isIdle = false
                lastCredit = now
                refreshSnapshot()
                if logEnabled { fputs("[Sidecheck] screentime: back from idle\n", stderr) }
            }
            return
        }

        guard suspensions.isEmpty, let key = currentKey, let last = lastCredit else { return }

        if idle >= idleThreshold {
            // Went idle: credit only up to the last input event, then pause.
            let lastInput = now.addingTimeInterval(-idle)
            let chunk = min(max(0, lastInput.timeIntervalSince(last)), Self.maxCreditChunk)
            if chunk > 0 {
                credit(chunk, key: key, name: currentName, at: lastInput)
            }
            isIdle = true
            lastCredit = nil
            flushNow()
            refreshSnapshot()
            if logEnabled { fputs("[Sidecheck] screentime: idle — clock paused\n", stderr) }
            return
        }

        let chunk = min(max(0, now.timeIntervalSince(last)), Self.maxCreditChunk)
        if chunk > 0.05 {
            credit(chunk, key: key, name: currentName, at: now)
            lastCredit = now
        }

        ticksSinceFlush += 1
        if ticksSinceFlush >= Self.flushTicks {
            ticksSinceFlush = 0
            flushNow()
            refreshSnapshot() // ≤1/min publish — the layout-storm rule
        }
    }

    // MARK: Crediting

    private func creditPending() {
        guard let key = currentKey, let last = lastCredit else {
            lastCredit = nil
            return
        }
        let now = Date()
        let chunk = min(max(0, now.timeIntervalSince(last)), Self.maxCreditChunk)
        if chunk > 0 {
            credit(chunk, key: key, name: currentName, at: now)
        }
        lastCredit = nil
    }

    private func credit(_ seconds: Double, key: String, name: String?, at date: Date) {
        let dayKey = Self.dayKey(date)
        var day = days[dayKey] ?? UsageDay(date: dayKey)
        var usage = day.apps[key] ?? AppUsage(name: name ?? Self.defaultName(for: key))
        if let name { usage.name = name }
        usage.seconds += seconds
        let hour = Calendar.current.component(.hour, from: date)
        if usage.hourly.indices.contains(hour) {
            usage.hourly[hour] += seconds
        }
        day.apps[key] = usage
        days[dayKey] = day
        dirty = true
    }

    private func bumpSnapshot() {
        refreshSnapshot()
    }

    // MARK: Snapshots & queries

    private func refreshSnapshot() {
        var snap = ActivitySnapshot()
        let now = Date()
        snap.todayKey = Self.dayKey(now)
        if let today = days[snap.todayKey] {
            snap.todayTotal = today.apps.values.reduce(0) { $0 + $1.seconds }
            snap.todayHourly = Self.hourlySum(of: today)
            snap.todayApps = today.apps
                .map { AppUsageEntry(key: $0.key, usage: $0.value) }
                .sorted { $0.usage.seconds > $1.usage.seconds }
        }

        let calendar = Calendar.current
        var points: [DayPoint] = []
        for offset in -6...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let key = Self.dayKey(date)
            let total = days[key]?.apps.values.reduce(0.0) { $0 + $1.seconds } ?? 0
            points.append(DayPoint(dayKey: key, total: total))
        }
        snap.week = points
        snap.weekTotal = points.reduce(0) { $0 + $1.total }

        var merged: [String: AppUsage] = [:]
        for point in points {
            for (key, usage) in days[point.dayKey]?.apps ?? [:] {
                var entry = merged[key] ?? AppUsage(name: usage.name)
                entry.seconds += usage.seconds
                merged[key] = entry
            }
        }
        snap.weekApps = merged
            .map { AppUsageEntry(key: $0.key, usage: $0.value) }
            .sorted { $0.usage.seconds > $1.usage.seconds }

        if trackingEnabled, suspensions.isEmpty, !isIdle {
            snap.nowApp = currentName ?? currentKey.map(Self.defaultName(for:))
        } else {
            snap.pauseNote = !trackingEnabled
                ? "Tracking off"
                : suspensions.contains(.locked) ? "Screen locked"
                : suspensions.contains(.sleeping) ? "Mac asleep"
                : suspensions.contains(.userSwitch) ? "Switched away"
                : isIdle ? "Idle — clock paused" : nil
        }
        snapshot = snap

        warmIcons(for: snap.todayApps.prefix(10).map(\.key) + snap.weekApps.prefix(10).map(\.key))
    }

    private static func hourlySum(of day: UsageDay) -> [Double] {
        var totals = Array(repeating: 0.0, count: 24)
        for usage in day.apps.values {
            for (hour, value) in usage.hourly.enumerated() where totals.indices.contains(hour) {
                totals[hour] += value
            }
        }
        return totals
    }

    /// Per-app entries for an arbitrary day (e.g. a tapped week bar).
    func apps(onDay dayKey: String) -> [AppUsageEntry] {
        (days[dayKey]?.apps ?? [:])
            .map { AppUsageEntry(key: $0.key, usage: $0.value) }
            .sorted { $0.usage.seconds > $1.usage.seconds }
    }

    func total(onDay dayKey: String) -> Double {
        days[dayKey]?.apps.values.reduce(0.0) { $0 + $1.seconds } ?? 0
    }

    func hourly(onDay dayKey: String) -> [Double] {
        guard let day = days[dayKey] else { return Array(repeating: 0, count: 24) }
        return Self.hourlySum(of: day)
    }

    // MARK: Icons & names

    /// LaunchServices lookups happen here (refresh/selection paths), never in
    /// a view body — bodies re-evaluate on every publish.
    func warmIcons(for keys: [String]) {
        for key in keys where !key.hasPrefix("exec:") && !resolvedIconKeys.contains(key) {
            resolvedIconKeys.insert(key)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
                iconCache[key] = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }

    /// Cache-only lookup for view bodies (nil → placeholder glyph).
    func cachedIcon(for key: String) -> NSImage? {
        iconCache[key]
    }

    static func key(for app: NSRunningApplication) -> String {
        if let bundle = app.bundleIdentifier { return bundle }
        return "exec:" + (app.executableURL?.lastPathComponent ?? app.localizedName ?? "unknown")
    }

    static func defaultName(for key: String) -> String {
        if key.hasPrefix("exec:") { return String(key.dropFirst(5)) }
        return key.split(separator: ".").last.map(String.init) ?? key
    }

    // MARK: Persistence

    func flushNow() {
        guard dirty else { return }
        dirty = false
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: Self.daysKey)
        }
        if logEnabled {
            fputs("[Sidecheck] screentime: flushed \(days.count) days\n", stderr)
        }
    }

    private func pruneOldDays() {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: Date()) else { return }
        let cutoff = Self.dayKey(cutoffDate)
        let stale = days.keys.filter { $0 < cutoff }
        guard !stale.isEmpty else { return }
        for key in stale { days.removeValue(forKey: key) }
        dirty = true
        if logEnabled { fputs("[Sidecheck] screentime: pruned \(stale.count) old days\n", stderr) }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        return formatter
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Seconds since the last keyboard/mouse event, system-wide. No
    /// permission required (kCGAnyInputEventType over the HID session state).
    private static func secondsSinceInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    }

    // MARK: Dev hook

    /// SIDECHECK_SCREENTIME_SEED=<days> fills history with deterministic
    /// synthetic data so charts can be verified without waiting a week.
    private func applySeedIfNeeded() {
        guard !didSeed,
              let raw = ProcessInfo.processInfo.environment["SIDECHECK_SCREENTIME_SEED"],
              let dayCount = Int(raw), dayCount > 0 else { return }
        didSeed = true

        // (bundle id, display name, share of the workload)
        let catalog: [(String, String, Double)] = [
            ("com.apple.Safari", "Safari", 1.0),
            ("com.google.Chrome", "Chrome", 0.7),
            ("com.apple.dt.Xcode", "Xcode", 0.8),
            ("com.apple.Terminal", "Terminal", 0.5),
            ("com.tinyspeck.slackmacgap", "Slack", 0.45),
            ("com.apple.finder", "Finder", 0.3),
            ("com.apple.mail", "Mail", 0.25),
            ("com.spotify.client", "Spotify", 0.35),
            ("com.apple.Notes", "Notes", 0.15),
            ("us.zoom.xos", "Zoom", 0.2),
        ]
        var state: UInt64 = 0x9E3779B97F4A7C15 ^ UInt64(dayCount)
        func nextFraction() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0xFFFF) / Double(0xFFFF)
        }

        let calendar = Calendar.current
        for offset in (1 - dayCount)...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) else { continue }
            let dayKey = Self.dayKey(date)
            let weekendDamp = calendar.isDateInWeekend(date) ? 0.45 : 1.0
            let todayDamp = offset == 0 ? 0.55 : 1.0 // leave room for real tracking today
            var day = days[dayKey] ?? UsageDay(date: dayKey)
            for (key, name, share) in catalog {
                var hourly = Array(repeating: 0.0, count: 24)
                for hour in 0..<24 {
                    let activity: Double
                    switch hour {
                    case 9...18: activity = 1.0
                    case 7...8, 19...23: activity = 0.4
                    default: activity = 0.05
                    }
                    hourly[hour] = nextFraction() * activity * weekendDamp * todayDamp * 900 * share
                }
                let seconds = hourly.reduce(0, +)
                guard seconds > 120 else { continue }
                var usage = day.apps[key] ?? AppUsage(name: name)
                usage.name = name
                usage.seconds = seconds
                usage.hourly = hourly
                day.apps[key] = usage
            }
            days[dayKey] = day
        }
        dirty = true
        flushNow()
        refreshSnapshot()
        fputs("[Sidecheck] screentime: seeded \(dayCount) days of synthetic history\n", stderr)
    }
}
