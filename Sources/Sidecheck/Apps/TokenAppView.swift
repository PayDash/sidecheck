import SwiftUI

/// The Tokens app: AI token usage from tokscale — per-model/session/project
/// breakdowns with cache hit rate front and center. Cost is secondary
/// (tokscale's own estimate), never the headline. Data comes from shelling
/// out to the tokscale CLI with a TUI-cache fallback (TokscaleStore).
struct TokenAppView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var tokscale: TokscaleStore

    private enum ChartMetric: String, CaseIterable, Identifiable {
        case tokens
        case cost

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @State private var chartMetric: ChartMetric = .tokens

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                pills

                switch tokscale.state {
                case .notInstalled:
                    installCard
                case .failed(let message):
                    errorCard(message)
                default:
                    content
                }

                footer
            }
            .padding(16)
        }
    }

    // MARK: Range pills

    private var pills: some View {
        HStack(spacing: 8) {
            ForEach(TokenRange.allCases) { candidate in
                pill(candidate.label, selected: tokscale.range == candidate) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        tokscale.range = candidate
                    }
                }
            }
            Spacer()
        }
    }

    private func pill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(theme.accent.opacity(selected ? 0.16 : 0), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        selected ? theme.accent.opacity(0.55) : theme.cardStroke,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let snapshot = tokscale.snapshot {
            heroCard(snapshot)
            if snapshot.daily.count >= 2 {
                chartCard(snapshot)
            }
            if !snapshot.models.isEmpty {
                modelsCard(snapshot)
            }
            if !snapshot.sessions.isEmpty {
                sessionsCard(snapshot)
            }
            if !snapshot.projects.isEmpty {
                projectsCard(snapshot)
            }
        } else if tokscale.state == .scanning {
            placeholderCard("Scanning tokscale sessions…")
        } else {
            placeholderCard("No usage recorded for this range yet.")
        }
    }

    // MARK: Hero

    private func heroCard(_ snapshot: TokenSnapshot) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.compactCount(snapshot.totalTokens))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                        .themeGlow(theme)
                    Text("tokens")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                    if snapshot.sessionCount > 0 {
                        Text("\(snapshot.sessionCount) session\(snapshot.sessionCount == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                Text("in \(Format.compactCount(snapshot.input)) · out \(Format.compactCount(snapshot.output)) · cache \(Format.compactCount(snapshot.cacheRead))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)

                Divider().overlay(theme.divider)

                cacheHitSection(snapshot)

                Text("\(Format.dollars(snapshot.cost)) · tokscale estimate")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func cacheHitSection(_ snapshot: TokenSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cache hit rate")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if let rate = snapshot.cacheHitRate {
                    Text(String(format: "%.1f%%", rate * 100))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
            }
            MeterBar(progress: snapshot.cacheHitRate ?? 0)
            if let rate = snapshot.cacheHitRate {
                Text(Self.cacheHitCaption(rate: rate, snapshot: snapshot))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private static func cacheHitCaption(rate: Double, snapshot: TokenSnapshot) -> String {
        let cached = Format.compactCount(snapshot.cacheRead)
        let total = Format.compactCount(snapshot.input + snapshot.cacheRead + snapshot.cacheWrite)
        let hint = rate >= 0.7
            ? "most prompt tokens came from cache"
            : rate >= 0.3 ? "a healthy share of prompts came from cache" : "most prompt tokens were uncached"
        return "\(cached) of \(total) prompt tokens cached — \(hint)"
    }

    // MARK: Daily chart

    private func chartCard(_ snapshot: TokenSnapshot) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(icon: "chart.bar.fill", title: "Daily usage")
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(ChartMetric.allCases) { metric in
                            chartPill(metric)
                        }
                    }
                }
                chart(snapshot)
                if chartMetric == .cost {
                    Text("Cost is tokscale's LiteLLM-based estimate — unpriced models are excluded")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func chartPill(_ metric: ChartMetric) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                chartMetric = metric
            }
        } label: {
            Text(metric.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chartMetric == metric ? theme.accent : theme.textTertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(theme.accent.opacity(chartMetric == metric ? 0.14 : 0), in: Capsule())
                .overlay(Capsule().strokeBorder(
                    chartMetric == metric ? theme.accent.opacity(0.5) : theme.cardStroke,
                    lineWidth: 1
                ))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chart(_ snapshot: TokenSnapshot) -> some View {
        let days = snapshot.daily
        let values = days.map { day -> Double in
            chartMetric == .tokens ? Double(day.tokens) : day.cost
        }
        let step = max(days.count / 6, 1)
        let labels: [String?] = days.enumerated().map { index, day in
            index % step == 0 || index == days.count - 1 ? Self.shortDate(day.date) : nil
        }
        BarChart(values: values, labels: labels) { _ in
            // Day drill-down would need a per-day group-by rescan — the
            // bars are the overview here.
        }
    }

    // MARK: Models

    private func modelsCard(_ snapshot: TokenSnapshot) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(icon: "cpu", title: "Models")
                let top = snapshot.models.first?.totalTokens ?? 0
                ForEach(snapshot.models.prefix(8)) { row in
                    modelRow(row, maxTokens: top)
                }
                if snapshot.models.count > 8 {
                    Text("+ \(snapshot.models.count - 8) more models")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func modelRow(_ row: TokenModelRow, maxTokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(row.model)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(Format.compactCount(row.totalTokens))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .contentTransition(.numericText())
            }
            Text("\(row.clients)\(row.provider.map { " · \($0)" } ?? "")")
                .font(.system(size: 9.5))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            HStack(spacing: 10) {
                MeterBar(progress: maxTokens > 0 ? Double(row.totalTokens) / Double(maxTokens) : 0)
                if let rate = row.cacheHitRate {
                    Text(String(format: "%.0f%%", rate * 100))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 34, alignment: .trailing)
                }
                Text(Format.dollars(row.cost))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    // MARK: Sessions

    private func sessionsCard(_ snapshot: TokenSnapshot) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 11) {
                CardTitle(icon: "bubble.left.and.text.bubble.right", title: "Top sessions")
                ForEach(snapshot.sessions.prefix(8)) { session in
                    HStack(spacing: 10) {
                        Text(session.shortId)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(session.client) · \(session.model)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                        Spacer()
                        Text(Format.compactCount(session.tokens))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }

    // MARK: Projects

    private func projectsCard(_ snapshot: TokenSnapshot) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 11) {
                CardTitle(icon: "folder", title: "Projects")
                let top = snapshot.projects.first?.tokens ?? 0
                ForEach(snapshot.projects.prefix(8)) { project in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(project.workspaceLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.compactCount(project.tokens))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.textSecondary)
                                .contentTransition(.numericText())
                        }
                        MeterBar(progress: top > 0 ? Double(project.tokens) / Double(top) : 0)
                    }
                }
            }
        }
    }

    // MARK: States

    private func placeholderCard(_ text: String) -> some View {
        ThemedCard {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        }
    }

    private var installCard: some View {
        ThemedCard {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(theme.textTertiary)
                    .themeGlow(theme)
                Text("tokscale isn't installed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Tokens scans the local session files of AI coding agents (ZCode, OpenCode, Codex, …). Install it, then rescan:")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                Text("bun install -g @tokscale/cli\nnpm i -g tokscale")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.cardFill, in: RoundedRectangle(cornerRadius: theme.cardRadius * 0.7, style: .continuous))
                rescanButton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func errorCard(_ message: String) -> some View {
        ThemedCard {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.orange)
                Text("Scan failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(3)
                rescanButton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var rescanButton: some View {
        Button {
            tokscale.scanIfStale(force: true)
        } label: {
            Label("Rescan", systemImage: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9))
                .foregroundStyle(theme.textTertiary)
            Text(footerText)
                .font(.system(size: 9.5))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .padding(.top, 2)
    }

    private var footerText: String {
        var parts: [String] = []
        if let snapshot = tokscale.snapshot {
            let age = Int(Date().timeIntervalSince(snapshot.scannedAt))
            let ageText = age < 5 ? "just now" : age < 60 ? "\(age)s ago" : "\(age / 60)m ago"
            parts.append("scanned \(ageText) · \(snapshot.sourceLabel)")
        } else if tokscale.state == .scanning {
            parts.append("scanning…")
        }
        parts.append("data by tokscale")
        return parts.joined(separator: " · ")
    }

    private static func shortDate(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }
}
