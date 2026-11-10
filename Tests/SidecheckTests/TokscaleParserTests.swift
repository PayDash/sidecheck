import XCTest
@testable import Sidecheck

/// Pins the tokscale JSON decoding and snapshot aggregation against a
/// synthetic fixture mirroring the verified v4.21 CLI schema (real usage
/// data stays out of the repo). Schema drift must fail here, not in the UI.
final class TokscaleParserTests: XCTestCase {
    private let fixtureJSON = """
    {
      "groupBy": "client,session,model",
      "entries": [
        {
          "client": "zcode",
          "sessionId": "sess_1114969d-f563-48cf-a428-42155b764673",
          "model": "glm-5.3",
          "provider": "zhipu",
          "input": 1000,
          "output": 200,
          "cacheRead": 9000,
          "cacheWrite": 100,
          "reasoning": 50,
          "messageCount": 12,
          "cost": 1.25,
          "performance": { "msPer1KTokens": 64.2 }
        },
        {
          "client": "zcode",
          "sessionId": "sess_1114969d-f563-48cf-a428-42155b764673",
          "model": "glm-5.3-flash",
          "provider": "zhipu",
          "input": 500,
          "output": 100,
          "cacheRead": 4000,
          "cacheWrite": 0,
          "reasoning": 0,
          "messageCount": 5,
          "cost": 0.75
        },
        {
          "client": "opencode",
          "sessionId": "sess_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "model": "deepseek-v4.1",
          "provider": "opencode",
          "input": 800,
          "output": 50,
          "cacheRead": 0,
          "cacheWrite": 0,
          "reasoning": 0,
          "cost": 0.5
        }
      ]
    }
    """

    private let workspaceJSON = """
    {
      "groupBy": "workspace,model",
      "entries": [
        {
          "client": "zcode",
          "workspaceKey": "/Users/demo/Documents/alpha",
          "workspaceLabel": "alpha",
          "model": "glm-5.3",
          "provider": "zhipu",
          "input": 600,
          "output": 100,
          "cacheRead": 3000,
          "cacheWrite": 0,
          "reasoning": 0,
          "cost": 0.4
        },
        {
          "client": "zcode",
          "workspaceKey": "/Users/demo/Documents/beta",
          "workspaceLabel": "beta",
          "model": "glm-5.3-flash",
          "provider": "zhipu",
          "input": 400,
          "output": 20,
          "cacheRead": 1000,
          "cacheWrite": 0,
          "reasoning": 0,
          "cost": 0.1
        }
      ]
    }
    """

    private let graphJSON = """
    {
      "meta": { "generatedAt": "2026-11-09T00:00:00Z", "version": "4.21.0" },
      "summary": { "totalTokens": 15350, "totalCost": 2.5 },
      "contributions": [
        {
          "date": "2026-11-07",
          "totals": { "tokens": 10350, "cost": 2.0, "messages": 17 },
          "tokenBreakdown": { "input": 1500, "output": 300, "cacheRead": 8000, "cacheWrite": 100, "reasoning": 450 },
          "clients": ["zcode"]
        },
        {
          "date": "2026-11-08",
          "totals": { "tokens": 5000, "cost": 0.5, "messages": 5 },
          "tokenBreakdown": { "input": 800, "output": 100, "cacheRead": 4000, "cacheWrite": 0, "reasoning": 100 },
          "clients": ["zcode", "opencode"]
        }
      ]
    }
    """

    private func buildSnapshot(
        sessionEntries: [TokscaleEntry],
        workspaceEntries: [TokscaleEntry],
        graphDays: [TokscaleGraphDay],
        range: TokenRange = .all
    ) throws -> TokenSnapshot {
        let sessions = try TokscaleParser.parseGrouped(Data(fixtureJSON.utf8)).entries
        let workspaces = try TokscaleParser.parseGrouped(Data(workspaceJSON.utf8)).entries
        let days = try TokscaleParser.parseGraph(Data(graphJSON.utf8)).contributions
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return TokscaleParser.snapshot(
            range: range,
            sessionEntries: sessionEntries.isEmpty ? sessions : sessionEntries,
            workspaceEntries: workspaceEntries.isEmpty ? workspaces : workspaceEntries,
            graphDays: graphDays.isEmpty ? days : graphDays,
            sourceLabel: "test",
            scannedAt: now,
            now: now
        )
    }

    // MARK: Decoding

    func testGroupedEntriesDecodeWithDefaults() throws {
        // Missing optional fields must not fail the whole payload.
        let sparse = """
        {"entries": [{"client": "zcode", "model": "glm-5.3"}]}
        """
        let response = try TokscaleParser.parseGrouped(Data(sparse.utf8))
        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries[0].input, 0)
        XCTAssertNil(response.entries[0].cost) // absent cost stays nil (optional)
        XCTAssertNil(response.entries[0].cacheHitRate) // no prompt tokens
    }

    func testGraphDayDecodesTotalsAndBreakdown() throws {
        let days = try TokscaleParser.parseGraph(Data(graphJSON.utf8)).contributions
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].tokens, 10350)
        XCTAssertEqual(days[0].cost, 2.0, accuracy: 0.0001)
        XCTAssertEqual(days[0].cacheRead, 8000)
    }

    func testGraphDayHandlesFlatShape() throws {
        let flat = """
        {"contributions": [{"date": "2026-11-08", "tokens": 5000, "cost": 0.5}]}
        """
        let days = try TokscaleParser.parseGraph(Data(flat.utf8)).contributions
        XCTAssertEqual(days[0].tokens, 5000)
        XCTAssertEqual(days[0].input, 0)
    }

    func testTuiCacheDecodesNestedTokens() throws {
        let cache = """
        {
          "schemaVersion": 12,
          "timestamp": 1793305132926,
          "data": {
            "models": [
              {
                "model": "glm-5.3",
                "colorKey": "glm-5.3",
                "provider": "zhipu",
                "client": "zcode",
                "tokens": { "input": 1000, "output": 200, "cacheRead": 9000, "cacheWrite": 0, "reasoning": 0 },
                "cost": 1.25,
                "sessionCount": 6
              }
            ],
            "daily": [
              {
                "date": "2026-11-08",
                "tokens": { "input": 500, "output": 100, "cacheRead": 4000, "cacheWrite": 0, "reasoning": 0 },
                "cost": 0.75
              }
            ]
          }
        }
        """
        let decoded = try TokscaleParser.parseTuiCache(Data(cache.utf8))
        XCTAssertEqual(decoded.models.count, 1)
        XCTAssertEqual(decoded.models[0].input, 1000)
        let modelPrompt = decoded.models[0].input + decoded.models[0].cacheRead + decoded.models[0].cacheWrite
        XCTAssertEqual(Double(decoded.models[0].cacheRead) / Double(modelPrompt), 0.9, accuracy: 0.0001)
        XCTAssertEqual(decoded.daily.count, 1)
        XCTAssertEqual(decoded.daily[0].tokens, 4600) // summed from nested tokens
    }

    // MARK: Aggregation

    func testSnapshotAggregatesTotalsFromSessionScanOnly() throws {
        let snapshot = try buildSnapshot(sessionEntries: [], workspaceEntries: [], graphDays: [])
        // Totals come from the session scan; workspace rows duplicate the
        // same tokens and must not double-count.
        let sessions = try TokscaleParser.parseGrouped(Data(fixtureJSON.utf8)).entries
        XCTAssertEqual(snapshot.input, sessions.reduce(0) { $0 + $1.input })
        XCTAssertEqual(snapshot.output, sessions.reduce(0) { $0 + $1.output })
        XCTAssertEqual(snapshot.cost, sessions.reduce(0.0) { $0 + ($1.cost ?? 0) }, accuracy: 0.0001)
    }

    func testCacheHitRateMath() throws {
        let snapshot = try buildSnapshot(sessionEntries: [], workspaceEntries: [], graphDays: [])
        let input = 1000 + 500 + 800
        let cacheRead = 9000 + 4000 + 0
        let cacheWrite = 100
        let expected = Double(cacheRead) / Double(input + cacheRead + cacheWrite)
        let rate = try XCTUnwrap(snapshot.cacheHitRate)
        XCTAssertEqual(rate, expected, accuracy: 0.0001)
        XCTAssertEqual(snapshot.totalTokens, input + 350 + cacheRead + cacheWrite + 50) // outputs 350, reasoning 50
    }

    func testCacheHitRateIsNilWithoutTokens() throws {
        let empty = TokscaleParser.snapshot(
            range: .all, sessionEntries: [], workspaceEntries: [],
            graphDays: [], sourceLabel: "test"
        )
        XCTAssertNil(empty.cacheHitRate)
        XCTAssertEqual(empty.totalTokens, 0)
    }

    func testModelsAggregateAcrossSessions() throws {
        let snapshot = try buildSnapshot(sessionEntries: [], workspaceEntries: [], graphDays: [])
        XCTAssertEqual(snapshot.models.count, 3)
        let glm = try XCTUnwrap(snapshot.models.first { $0.model == "glm-5.3" })
        XCTAssertEqual(glm.totalTokens, 1000 + 200 + 9000 + 100 + 50)
        XCTAssertEqual(glm.sessions.count, 1)
        XCTAssertEqual(glm.cacheHitRate!, 9000.0 / 10100.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.models.first?.model, "glm-5.3") // sorted by tokens desc
    }

    func testSessionsCarryClientAndModel() throws {
        let snapshot = try buildSnapshot(sessionEntries: [], workspaceEntries: [], graphDays: [])
        XCTAssertEqual(snapshot.sessions.count, 2)
        let top = snapshot.sessions.first!
        XCTAssertEqual(top.client, "zcode")
        XCTAssertTrue(top.tokens >= snapshot.sessions.last!.tokens)
        XCTAssertEqual(top.shortId, "1114969d") // sess_ prefix stripped, 8 chars
        XCTAssertEqual(snapshot.sessionCount, 2)
    }

    func testProjectsAggregateByWorkspace() throws {
        let snapshot = try buildSnapshot(sessionEntries: [], workspaceEntries: [], graphDays: [])
        XCTAssertEqual(snapshot.projects.count, 2)
        let alpha = try XCTUnwrap(snapshot.projects.first { $0.workspaceLabel == "alpha" })
        XCTAssertEqual(alpha.tokens, 600 + 100 + 3000)
    }

    func testDailyWindowFiltering() throws {
        let days = try TokscaleParser.parseGraph(Data(graphJSON.utf8)).contributions
        // All: both days survive.
        let all = try buildSnapshot(sessionEntries: [], workspaceEntries: [], graphDays: days, range: .all)
        XCTAssertEqual(all.daily.count, 2)
        // Today: the fixture dates are fixed in the past, so a "today"
        // window over a fixed now yields an empty chart.
        let fixedNow = TokscaleParser.dayDate("2026-11-08")!.addingTimeInterval(4000)
        let today = TokscaleParser.snapshot(
            range: .today,
            sessionEntries: try TokscaleParser.parseGrouped(Data(fixtureJSON.utf8)).entries,
            workspaceEntries: [],
            graphDays: days,
            sourceLabel: "test",
            now: fixedNow
        )
        XCTAssertEqual(today.daily.count, 1)
        XCTAssertEqual(today.daily.first?.date, "2026-11-08")
    }
}
