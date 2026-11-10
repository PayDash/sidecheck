import Foundation

// MARK: - Wire models (tokscale CLI output — defensively decoded)

/// One entry of `tokscale models --json --group-by <strategy>`. Fields are
/// optional with defaults: the schema has changed across tokscale versions
/// and the app must never crash on drift.
struct TokscaleEntry: Decodable {
    var client: String?
    var sessionId: String?
    var workspaceKey: String?
    var workspaceLabel: String?
    var model: String
    var provider: String?
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var messageCount: Int?
    var cost: Double?

    private enum CodingKeys: String, CodingKey {
        case client, mergedClients, sessionId, workspaceKey, workspaceLabel
        case model, provider, input, output, cacheRead, cacheWrite, reasoning
        case messageCount, cost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // mergedClients ("zcode, omp") is the human-facing client list when
        // rows were merged; fall back to the raw client.
        client = try c.decodeIfPresent(String.self, forKey: .mergedClients)
            ?? c.decodeIfPresent(String.self, forKey: .client)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        workspaceKey = try c.decodeIfPresent(String.self, forKey: .workspaceKey)
        workspaceLabel = try c.decodeIfPresent(String.self, forKey: .workspaceLabel)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        reasoning = try c.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        messageCount = try c.decodeIfPresent(Int.self, forKey: .messageCount)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
    }

    init(
        client: String?, sessionId: String?, workspaceKey: String?, workspaceLabel: String?,
        model: String, provider: String?, input: Int, output: Int, cacheRead: Int,
        cacheWrite: Int, reasoning: Int, messageCount: Int?, cost: Double?
    ) {
        self.client = client
        self.sessionId = sessionId
        self.workspaceKey = workspaceKey
        self.workspaceLabel = workspaceLabel
        self.model = model
        self.provider = provider
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
        self.messageCount = messageCount
        self.cost = cost
    }

    var totalTokens: Int { input + output + cacheRead + cacheWrite + reasoning }
    var promptTokens: Int { input + cacheRead + cacheWrite }
    var cacheHitRate: Double? {
        guard promptTokens > 0 else { return nil }
        return Double(cacheRead) / Double(promptTokens)
    }
}

struct TokscaleGroupedResponse: Decodable {
    var groupBy: String?
    var entries: [TokscaleEntry]

    private enum CodingKeys: String, CodingKey { case groupBy, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groupBy = try c.decodeIfPresent(String.self, forKey: .groupBy)
        entries = try c.decodeIfPresent([TokscaleEntry].self, forKey: .entries) ?? []
    }

    init(entries: [TokscaleEntry]) {
        groupBy = nil
        self.entries = entries
    }
}

// MARK: - Graph (all-time daily contributions — the only dated CLI source)

struct TokscaleGraphDay: Decodable {
    var date: String
    var tokens: Int
    var cost: Double
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int

    private enum CodingKeys: String, CodingKey {
        case date, totals, tokenBreakdown
        case tokens, cost, input, output, cacheRead, cacheWrite, reasoning
    }
    private enum TotalsKeys: String, CodingKey { case tokens, cost }
    private enum BreakdownKeys: String, CodingKey {
        case input, output, cacheRead, cacheWrite, reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        // Three shapes across sources: graph JSON (totals{} + tokenBreakdown{}),
        // TUI cache daily (tokens{} nested object, no totals), flat integers.
        var cost = 0.0
        var tokens = 0
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var reasoning = 0
        if let totals = try? c.nestedContainer(keyedBy: TotalsKeys.self, forKey: .totals) {
            cost = try totals.decodeIfPresent(Double.self, forKey: .cost) ?? 0
            tokens = try totals.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
            if let breakdown = try? c.nestedContainer(keyedBy: BreakdownKeys.self, forKey: .tokenBreakdown) {
                input = try breakdown.decodeIfPresent(Int.self, forKey: .input) ?? 0
                output = try breakdown.decodeIfPresent(Int.self, forKey: .output) ?? 0
                cacheRead = try breakdown.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
                cacheWrite = try breakdown.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
                reasoning = try breakdown.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
            }
        } else if let tokensContainer = try? c.nestedContainer(keyedBy: BreakdownKeys.self, forKey: .tokens) {
            cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
            input = try tokensContainer.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try tokensContainer.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cacheRead = try tokensContainer.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
            cacheWrite = try tokensContainer.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
            reasoning = try tokensContainer.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
            tokens = input + output + cacheRead + cacheWrite + reasoning
        } else {
            cost = try c.decodeIfPresent(Double.self, forKey: .cost) ?? 0
            tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
            input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
            cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
            reasoning = try c.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        }
        self.cost = cost
        self.tokens = tokens
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }

    init(
        date: String, tokens: Int, cost: Double,
        input: Int, output: Int, cacheRead: Int, cacheWrite: Int, reasoning: Int
    ) {
        self.date = date
        self.tokens = tokens
        self.cost = cost
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }
}

struct TokscaleGraphResponse: Decodable {
    var contributions: [TokscaleGraphDay]

    private enum CodingKeys: String, CodingKey { case contributions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contributions = try c.decodeIfPresent([TokscaleGraphDay].self, forKey: .contributions) ?? []
    }

    init(contributions: [TokscaleGraphDay]) {
        self.contributions = contributions
    }
}

// MARK: - TUI cache fallback (~/.config/tokscale/cache/tui-data-cache.json)

/// Read only when no tokscale executable is found. The TUI rewrites this
/// after every run — fresher than nothing, with its own `timestamp` for the
/// staleness stamp. Cache shapes differ from CLI output: model entries nest
/// tokens in a sub-object and daily entries carry no per-field breakdown.
struct TokscaleTuiCache: Decodable {
    var timestamp: Double? // ms since epoch
    var models: [TokscaleTuiModel]
    var daily: [TokscaleGraphDay]

    private enum CodingKeys: String, CodingKey { case timestamp, data }
    private enum DataKeys: String, CodingKey { case models, daily }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp)
        models = []
        daily = []
        guard let data = try? c.nestedContainer(keyedBy: DataKeys.self, forKey: .data) else { return }
        models = try data.decodeIfPresent([TokscaleTuiModel].self, forKey: .models) ?? []
        daily = try data.decodeIfPresent([TokscaleGraphDay].self, forKey: .daily) ?? []
    }

    init(timestamp: Double?, models: [TokscaleTuiModel], daily: [TokscaleGraphDay]) {
        self.timestamp = timestamp
        self.models = models
        self.daily = daily
    }
}

struct TokscaleTuiModel: Decodable {
    var model: String
    var client: String?
    var provider: String?
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var cost: Double?
    var sessionCount: Int?

    private enum CodingKeys: String, CodingKey {
        case model, client, provider, tokens, cost, sessionCount
        case input, output, cacheRead, cacheWrite, reasoning
    }
    private enum TokenKeys: String, CodingKey { case input, output, cacheRead, cacheWrite, reasoning }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "unknown"
        client = try c.decodeIfPresent(String.self, forKey: .client)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount)
        if let tokens = try? c.nestedContainer(keyedBy: TokenKeys.self, forKey: .tokens) {
            input = try tokens.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try tokens.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cacheRead = try tokens.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
            cacheWrite = try tokens.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
            reasoning = try tokens.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        } else {
            input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
            cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
            reasoning = try c.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
        }
    }

    init(
        model: String, client: String?, provider: String?,
        input: Int, output: Int, cacheRead: Int, cacheWrite: Int, reasoning: Int,
        cost: Double?, sessionCount: Int?
    ) {
        self.model = model
        self.client = client
        self.provider = provider
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
        self.cost = cost
        self.sessionCount = sessionCount
    }
}

// MARK: - Pure parsing (MainActor-free, testable)

enum TokscaleParser {
    static func parseGrouped(_ data: Data) throws -> TokscaleGroupedResponse {
        try JSONDecoder().decode(TokscaleGroupedResponse.self, from: data)
    }

    static func parseGraph(_ data: Data) throws -> TokscaleGraphResponse {
        try JSONDecoder().decode(TokscaleGraphResponse.self, from: data)
    }

    static func parseTuiCache(_ data: Data) throws -> TokscaleTuiCache {
        try JSONDecoder().decode(TokscaleTuiCache.self, from: data)
    }

    /// Builds the aggregated snapshot from the scan results. Pure — the store
    /// calls it on the main thread with already-decoded values.
    /// - session entries drive totals, models, sessions
    /// - workspace entries drive projects (their tokens duplicate the
    ///   session scan's, so they are excluded from totals)
    /// - graph days drive the daily trend (windowed by range)
    static func snapshot(
        range: TokenRange,
        sessionEntries: [TokscaleEntry],
        workspaceEntries: [TokscaleEntry],
        graphDays: [TokscaleGraphDay],
        sourceLabel: String,
        scannedAt: Date = Date(),
        now: Date = Date()
    ) -> TokenSnapshot {
        var snap = TokenSnapshot(range: range, sourceLabel: sourceLabel, scannedAt: scannedAt)

        let totalSource = sessionEntries.isEmpty ? workspaceEntries : sessionEntries
        for entry in totalSource {
            snap.input += entry.input
            snap.output += entry.output
            snap.cacheRead += entry.cacheRead
            snap.cacheWrite += entry.cacheWrite
            snap.reasoning += entry.reasoning
            snap.cost += entry.cost ?? 0
        }

        var models: [String: TokenModelRow] = [:]
        for entry in sessionEntries {
            var row = models[entry.model] ?? TokenModelRow(
                model: entry.model, clients: entry.client ?? "unknown", provider: entry.provider,
                input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0,
                cost: 0, sessions: []
            )
            row.input += entry.input
            row.output += entry.output
            row.cacheRead += entry.cacheRead
            row.cacheWrite += entry.cacheWrite
            row.reasoning += entry.reasoning
            row.cost += entry.cost ?? 0
            if let sessionId = entry.sessionId { row.sessions.insert(sessionId) }
            if let client = entry.client, !row.clients.contains(client) {
                row.clients += ", \(client)"
            }
            models[entry.model] = row
        }
        snap.models = models.values
            .map { row -> TokenModelRow in
                var row = row
                let prompt = row.input + row.cacheRead + row.cacheWrite
                row.cacheHitRate = prompt > 0 ? Double(row.cacheRead) / Double(prompt) : nil
                return row
            }
            .sorted { $0.totalTokens > $1.totalTokens }

        var sessions: [String: TokenSessionRow] = [:]
        for entry in sessionEntries where entry.sessionId != nil {
            let key = entry.sessionId!
            var row = sessions[key] ?? TokenSessionRow(
                sessionId: key, client: entry.client ?? "unknown", model: entry.model,
                tokens: 0, cost: 0
            )
            row.tokens += entry.totalTokens
            row.cost += entry.cost ?? 0
            sessions[key] = row
        }
        snap.sessions = sessions.values.sorted { $0.tokens > $1.tokens }

        var projects: [String: TokenProjectRow] = [:]
        for entry in workspaceEntries {
            let key = entry.workspaceKey ?? entry.workspaceLabel ?? "unknown"
            var row = projects[key] ?? TokenProjectRow(
                workspaceKey: key,
                workspaceLabel: entry.workspaceLabel
                    ?? key.split(separator: "/").last.map(String.init) ?? key,
                tokens: 0, cost: 0
            )
            row.tokens += entry.totalTokens
            row.cost += entry.cost ?? 0
            projects[key] = row
        }
        snap.projects = projects.values.sorted { $0.tokens > $1.tokens }

        snap.sessionCount = snap.sessions.count

        let window = range.dayWindow(now: now)
        let days = graphDays
            .sorted { $0.date < $1.date }
            .filter { day in
                guard let date = Self.dayDate(day.date) else { return false }
                return window.contains(date)
            }
        snap.daily = days.map { day in
            TokenDayPoint(
                date: day.date, tokens: day.tokens, cost: day.cost,
                input: day.input, output: day.output, cacheRead: day.cacheRead,
                cacheWrite: day.cacheWrite
            )
        }

        let prompt = snap.input + snap.cacheRead + snap.cacheWrite
        snap.cacheHitRate = prompt > 0 ? Double(snap.cacheRead) / Double(prompt) : nil
        snap.totalTokens = snap.input + snap.output + snap.cacheRead + snap.cacheWrite + snap.reasoning
        snap.topModel = snap.models.first?.model
        return snap
    }

    static func dayDate(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Local midnight — the range windows (startOfDay-based) must line up
        // with parsed keys in every timezone, or "today" drops off the chart.
        formatter.timeZone = nil
        return formatter.date(from: key)
    }
}

// MARK: - Snapshot

struct TokenModelRow: Identifiable {
    let model: String
    var clients: String
    var provider: String?
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var cost: Double
    var sessions: Set<String>
    var cacheHitRate: Double?

    init(
        model: String, clients: String, provider: String?, input: Int, output: Int,
        cacheRead: Int, cacheWrite: Int, reasoning: Int, cost: Double,
        sessions: Set<String>, cacheHitRate: Double? = nil
    ) {
        self.model = model
        self.clients = clients
        self.provider = provider
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
        self.cost = cost
        self.sessions = sessions
        self.cacheHitRate = cacheHitRate
    }

    var totalTokens: Int { input + output + cacheRead + cacheWrite + reasoning }
    var id: String { model }
}

struct TokenSessionRow: Identifiable {
    let sessionId: String
    var client: String
    var model: String
    var tokens: Int
    var cost: Double

    var id: String { sessionId }
    var shortId: String {
        var stem = sessionId
        if stem.hasPrefix("sess_") { stem.removeFirst(5) }
        return String(stem.prefix(8))
    }
}

struct TokenProjectRow: Identifiable {
    let workspaceKey: String
    var workspaceLabel: String
    var tokens: Int
    var cost: Double

    var id: String { workspaceKey }
}

struct TokenDayPoint: Identifiable {
    let date: String // yyyy-MM-dd
    var tokens: Int
    var cost: Double
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int

    var id: String { date }
}

struct TokenSnapshot {
    var range: TokenRange
    var sourceLabel: String
    var scannedAt: Date
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning = 0
    var cost = 0.0
    var totalTokens = 0
    var cacheHitRate: Double?
    var sessionCount = 0
    var models: [TokenModelRow] = []
    var sessions: [TokenSessionRow] = []
    var projects: [TokenProjectRow] = []
    var daily: [TokenDayPoint] = []
    var topModel: String?
}

// MARK: - Range

enum TokenRange: String, CaseIterable, Identifiable {
    case today, week, month, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .month: "Month"
        case .all: "All"
        }
    }

    var cliFlags: [String] {
        switch self {
        case .today: ["--today"]
        case .week: ["--week"]
        case .month: ["--month"]
        case .all: []
        }
    }

    /// Inclusive date window (UTC day keys) used to slice the all-time
    /// graph contributions client-side.
    func dayWindow(now: Date = Date()) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return todayStart...todayStart.addingTimeInterval(86_400)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
            return start...start.addingTimeInterval(7 * 86_400)
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
            return start...start.addingTimeInterval(30 * 86_400)
        case .all:
            return .distantPast...Date.distantFuture
        }
    }
}

// MARK: - Store

@MainActor
final class TokscaleStore: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning
        case ready
        case notInstalled
        case failed(String)

        var healthText: String {
            switch self {
            case .idle: "Idle"
            case .scanning: "Scanning"
            case .ready: "Ready (visible)"
            case .notInstalled: "tokscale missing"
            case .failed: "Scan failed"
            }
        }

        var isHealthy: Bool {
            switch self {
            case .notInstalled, .failed: false
            default: true
            }
        }
    }

    @Published private(set) var snapshot: TokenSnapshot?
    @Published private(set) var state: State = .idle
    @Published private(set) var lastScanDate: Date?
    @Published var range: TokenRange = .today {
        didSet {
            guard range != oldValue else { return }
            scanIfStale(force: true)
        }
    }

    /// Whether the panel is visible — scans run only while open (60 s
    /// cadence), keeping the hidden state at ≈0% CPU.
    var visibilityProvider: (() -> Bool)?

    private var timer: Timer?
    private var queue = DispatchQueue(label: "sidecheck.tokscale", qos: .utility)
    private var scanInFlight = false
    /// Set when a scan request lands while another is in flight (range tap,
    /// Rescan button) — the completion re-scans with the then-current range,
    /// instead of the request silently vanishing for up to a minute.
    private var pendingRescan = false
    private var scanGeneration = 0
    private var memo: [TokenRange: TokenSnapshot] = [:]

    static let scanInterval: TimeInterval = 60

    /// "yyyy-MM-dd" for slicing today's tokens out of the daily trend —
    /// built once, not per view-body evaluation.
    private static let todayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var isScanning: Bool { state == .scanning }

    /// Today's tokens + cache hit, read from the snapshot's dated
    /// contributions (present for any range — graph data is all-time).
    /// nil only before the first successful scan.
    var todaySummary: (tokens: Int, cacheHitRate: Double?)? {
        guard let snapshot = snapshot else { return nil }
        let key = Self.todayKeyFormatter.string(from: Date())
        if let today = snapshot.daily.last(where: { $0.date == key }) {
            let prompt = today.input + today.cacheRead + today.cacheWrite
            let rate = prompt > 0 ? Double(today.cacheRead) / Double(prompt) : nil
            return (today.tokens, rate)
        }
        return (0, nil) // fresh day, nothing recorded yet
    }

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard visibilityProvider?() ?? false else { return }
        scanIfStale()
    }

    /// Scans unless a fresh-enough snapshot for the current range already
    /// exists. Called on panel show and by the 60 s visible timer.
    func scanIfStale(force: Bool = false) {
        if !force, let cached = memo[range],
           Date().timeIntervalSince(cached.scannedAt) < Self.scanInterval {
            snapshot = cached
            state = .ready
            return
        }
        scan()
    }

    // MARK: Scanning

    private func scan() {
        guard !scanInFlight else {
            pendingRescan = true // this scan request leads once the current one lands
            return
        }
        scanInFlight = true
        state = .scanning
        scanGeneration += 1
        let generation = scanGeneration
        let range = range

        queue.async { [weak self] in
            let result = TokscaleScanner.performScan(range: range)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanInFlight = false
                guard generation == self.scanGeneration else { return } // range changed mid-scan
                switch result {
                case .success(let snapshot):
                    self.memo[range] = snapshot
                    self.snapshot = snapshot
                    self.state = .ready
                    self.lastScanDate = snapshot.scannedAt
                case .failure(let message):
                    self.state = .failed(message)
                }
                if self.pendingRescan {
                    self.pendingRescan = false
                    self.scan() // runs with the current range
                }
            }
        }
    }

    // MARK: Process plumbing (static + nonisolated — runs on the queue)

    /// Env override (dev/testing) → tokscale in well-known bins → bunx → npx.
    /// GUI apps don't inherit the shell's PATH, so `which` alone can't be
    /// trusted — probe known install locations first.
    nonisolated static func resolveCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [String]? {
        if let override = environment["SIDECHECK_TOKSCALE_BIN"] {
            return override.isEmpty ? nil : [override]
        }

        func probe(_ paths: [String]) -> String? {
            paths.first { fileManager.isExecutableFile(atPath: $0) }
        }

        let home = NSHomeDirectory()
        if let tokscale = probe([
            home + "/.bun/bin/tokscale",
            "/opt/homebrew/bin/tokscale",
            "/usr/local/bin/tokscale",
        ]) {
            return [tokscale]
        }
        // `which` only helps when the app inherited a shell PATH (dev runs).
        let which = execute(["/usr/bin/which", "tokscale"])
        if which.ok, let path = String(data: which.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            fileManager.isExecutableFile(atPath: path) {
            return [path]
        }

        if let bunx = probe([
            home + "/.bun/bin/bunx",
            "/opt/homebrew/bin/bunx",
            "/usr/local/bin/bunx",
        ]) {
            return [bunx, "tokscale"]
        }
        if let npx = probe([
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
        ]) ?? nvmNpx(home: home, fileManager: fileManager) {
            return [npx, "tokscale"]
        }
        return nil
    }

    /// nvm installs live per version — pick the highest-versioned npx.
    private nonisolated static func nvmNpx(home: String, fileManager: FileManager) -> String? {
        let versionsDir = home + "/.nvm/versions/node"
        let versions = (try? fileManager.contentsOfDirectory(atPath: versionsDir)) ?? []
        return versions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .compactMap { version -> String? in
                let path = "\(versionsDir)/\(version)/bin/npx"
                return fileManager.isExecutableFile(atPath: path) ? path : nil
            }
            .first
    }

    nonisolated static func run(_ arguments: [String]) throws -> Data {
        let result = execute(arguments)
        guard result.ok else {
            throw TokscaleError.commandFailed(result.stderr)
        }
        return result.stdout
    }

    private nonisolated struct RunResult {
        var ok: Bool
        var stdout: Data
        var stderr: String
    }

    private nonisolated static func execute(_ arguments: [String]) -> RunResult {
        guard let executable = executablePath(arguments[0]) else {
            return RunResult(ok: false, stdout: Data(), stderr: "not found: \(arguments[0])")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        var environment = ProcessInfo.processInfo.environment
        // Make the runtime (node/bun) resolvable next to the launcher.
        let launcherDir = (executable as NSString).deletingLastPathComponent
        environment["PATH"] = launcherDir + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return RunResult(ok: false, stdout: Data(), stderr: "\(error)")
        }
        // Read before waitUntilExit so full pipes can't deadlock the child.
        let outData = output.fileHandleForReading.readDataToEndOfFile()
        let errData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(
            ok: process.terminationStatus == 0,
            stdout: outData,
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private nonisolated static func executablePath(_ name: String) -> String? {
        if name.contains("/") { return name }
        let result = execute(["/usr/bin/which", name])
        let path = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (result.ok && path?.isEmpty == false) ? path : nil
    }
}

// MARK: - Scanner (nonisolated — runs on the background queue)

nonisolated enum TokscaleScanner {
    enum Outcome {
        case success(TokenSnapshot)
        case failure(String)
    }

    static func performScan(range: TokenRange) -> Outcome {
        // Command chain: env override → tokscale on PATH → bunx → npx.
        guard let command = TokscaleStore.resolveCommand() else {
            return cacheFallback(range: range, missingCommand: true)
        }
        fputs("[Sidecheck] tokscale: scanning via \(command.joined(separator: " "))\n", stderr)
        do {
            // The three invocations are independent — run them concurrently
            // and wait once, so a scan costs the slowest command (~2 s) not
            // the sum of all three.
            let group = DispatchGroup()
            let scanQueue = DispatchQueue(label: "sidecheck.tokscale.scan", attributes: .concurrent)
            let lock = NSLock()
            var sessionData: Data?
            var workspaceData: Data?
            var graphData: Data?
            var failure: String?

            let graphPath = NSTemporaryDirectory() + "sidecheck-tokscale-graph.json"

            group.enter()
            scanQueue.async {
                defer { group.leave() }
                do {
                    let data = try TokscaleStore.run(
                        command + ["models", "--json", "--group-by", "client,session,model"] + range.cliFlags
                    )
                    lock.lock(); sessionData = data; lock.unlock()
                } catch {
                    lock.lock(); failure = error.localizedDescription; lock.unlock()
                }
            }
            group.enter()
            scanQueue.async {
                defer { group.leave() }
                do {
                    let data = try TokscaleStore.run(
                        command + ["models", "--json", "--group-by", "workspace,model"] + range.cliFlags
                    )
                    lock.lock(); workspaceData = data; lock.unlock()
                } catch {
                    lock.lock(); failure = error.localizedDescription; lock.unlock()
                }
            }
            group.enter()
            scanQueue.async {
                defer { group.leave() }
                do {
                    _ = try TokscaleStore.run(command + ["graph", "--output", graphPath])
                    let data = FileManager.default.contents(atPath: graphPath)
                    try? FileManager.default.removeItem(atPath: graphPath)
                    guard let data else {
                        throw TokscaleError.emptyOutput("graph")
                    }
                    lock.lock(); graphData = data; lock.unlock()
                } catch {
                    lock.lock(); failure = error.localizedDescription; lock.unlock()
                }
            }
            group.wait()
            try? FileManager.default.removeItem(atPath: graphPath)

            guard let sessionData, let workspaceData, let graphData else {
                throw TokscaleError.commandFailed(failure ?? "a scan step produced no output")
            }

            let sessionResponse = try TokscaleParser.parseGrouped(sessionData)
            let workspaceResponse = try TokscaleParser.parseGrouped(workspaceData)
            let graphResponse = try TokscaleParser.parseGraph(graphData)
            let snapshot = TokscaleParser.snapshot(
                range: range,
                sessionEntries: sessionResponse.entries,
                workspaceEntries: workspaceResponse.entries,
                graphDays: graphResponse.contributions,
                sourceLabel: sourceLabel(for: command),
                now: Date()
            )
            return .success(snapshot)
        } catch {
            // Any CLI failure falls through to the TUI cache — the last rung.
            fputs("[Sidecheck] tokscale CLI scan failed (\(error.localizedDescription)) — falling back to cache\n", stderr)
            return cacheFallback(range: range, missingCommand: false)
        }
    }

    private static func cacheFallback(range: TokenRange, missingCommand: Bool) -> Outcome {
        let cachePath = NSHomeDirectory() + "/.config/tokscale/cache/tui-data-cache.json"
        guard let cacheData = FileManager.default.contents(atPath: cachePath),
              let cache = try? TokscaleParser.parseTuiCache(cacheData) else {
            if missingCommand {
                return .failure(
                    "tokscale not found — install it with `bun install -g @tokscale/cli` or `npm i -g tokscale`"
                )
            }
            return .failure("tokscale scan failed")
        }

        let cachedAt = cache.timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        var snapshot = TokscaleParser.snapshot(
            range: range,
            sessionEntries: [],
            workspaceEntries: [],
            graphDays: cache.daily,
            sourceLabel: "tokscale cache",
            scannedAt: cachedAt,
            now: Date()
        )
        var rows = cache.models.map { entry -> TokenModelRow in
            TokenModelRow(
                model: entry.model, clients: entry.client ?? "unknown", provider: entry.provider,
                input: entry.input, output: entry.output, cacheRead: entry.cacheRead,
                cacheWrite: entry.cacheWrite, reasoning: entry.reasoning,
                cost: entry.cost ?? 0, sessions: [],
                cacheHitRate: {
                    let prompt = entry.input + entry.cacheRead + entry.cacheWrite
                    guard prompt > 0 else { return nil }
                    return Double(entry.cacheRead) / Double(prompt)
                }()
            )
        }
        rows.sort { $0.totalTokens > $1.totalTokens }
        snapshot.models = rows
        snapshot.topModel = rows.first?.model
        for row in rows {
            snapshot.input += row.input
            snapshot.output += row.output
            snapshot.cacheRead += row.cacheRead
            snapshot.cacheWrite += row.cacheWrite
            snapshot.reasoning += row.reasoning
            snapshot.cost += row.cost
        }
        snapshot.totalTokens = snapshot.input + snapshot.output + snapshot.cacheRead
            + snapshot.cacheWrite + snapshot.reasoning
        let prompt = snapshot.input + snapshot.cacheRead + snapshot.cacheWrite
        snapshot.cacheHitRate = prompt > 0 ? Double(snapshot.cacheRead) / Double(prompt) : nil
        return .success(snapshot)
    }

    private static func sourceLabel(for command: [String]) -> String {
        let launcher = (command.first as NSString?)?.lastPathComponent ?? "cli"
        return launcher == "tokscale" ? "tokscale via PATH" : "tokscale via \(launcher)"
    }
}

// MARK: - Process plumbing (static + nonisolated, MusicStore.runOSA pattern)

enum TokscaleError: LocalizedError {
    case commandFailed(String)
    case emptyOutput(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let stderr):
            return stderr.isEmpty ? "tokscale exited with an error" : stderr
        case .emptyOutput(let what):
            return "tokscale produced no \(what) data"
        }
    }
}

