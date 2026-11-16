import BudgetCore
import Foundation
import Testing
@testable import QuotaKit

// Shape copied from a real Codex Desktop rollout (values changed).
private let codexLine = Data("""
{"timestamp":"2026-11-15T13:01:40.571Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":100.0,"window_minutes":300,"resets_at":1794756448},"secondary":{"used_percent":18.0,"window_minutes":10080,"resets_at":1795036984},"credits":{"has_credits":true,"unlimited":false,"balance":"44483.3027970000"},"plan_type":"plus"}}}
""".utf8)

@Test func parsesCodexRolloutByWindowLengthNotPosition() throws {
    let snaps = CodexSource.parse(line: codexLine)
    #expect(snaps.count == 2)
    let five = try #require(snaps.first { $0.windowMinutes == 300 })
    #expect(five.pool == PoolKey(.codex, "codex.300"))
    #expect(five.usedPercent == 100)
    #expect(five.precision == 1)
    #expect(five.resetsAt == Date(timeIntervalSince1970: 1794756448))
    let week = try #require(snaps.first { $0.windowMinutes == 10080 })
    #expect(week.isLongWindow)
    #expect(abs(week.observedAt.timeIntervalSince1970 - 1_794_747_700.571) < 0.01)
    let credits = try #require(CodexSource.parseCredits(line: codexLine))
    #expect(abs(credits.used - 44483.302797) < 1e-6)
}

@Test func parsesCodexLiveUsage() throws {
    // Shape of chatgpt.com/backend-api/wham/usage, trimmed.
    let json = """
    {"plan_type": "plus",
     "rate_limit": {"allowed": false, "limit_reached": true,
       "primary_window": {"used_percent": 100, "limit_window_seconds": 18000, "reset_after_seconds": 3134, "reset_at": 1794756448},
       "secondary_window": {"used_percent": 18, "limit_window_seconds": 604800, "reset_after_seconds": 283670, "reset_at": 1795036984}},
     "credits": {"has_credits": true, "unlimited": false, "balance": "44453.6319370000"},
     "rate_limit_reset_credits": {"available_count": 3, "applicable_available_count": 3}}
    """
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let r = CodexLiveSource.parse(obj, observedAt: Date())
    // Same pool ids as the rollouts, so both sources feed one history.
    #expect(Set(r.snapshots.map(\.pool.id)) == ["codex.300", "codex.10080"])
    #expect(r.snapshots.first { $0.windowMinutes == 300 }?.usedPercent == 100)
    #expect(abs((r.credits?.used ?? 0) - 44453.631937) < 1e-6)
    #expect(r.freeResets == 3)
}

@Test func testsRunInRussian() {
    // The expectations here are Russian: run the suite as `SLOWBURN_LANG=ru swift test`.
    #expect(Lang.current == .ru, "run the tests as SLOWBURN_LANG=ru swift test")
    #expect(L("да", "yes") == "да")
    #expect(Phrases.points(1.5) == "1,5")
}

@Test func russianPluralForResets() {
    #expect(Phrases.freeResets(1) == "1 бесплатный сброс")
    #expect(Phrases.freeResets(3) == "3 бесплатных сброса")
    #expect(Phrases.freeResets(5) == "5 бесплатных сбросов")
    #expect(Phrases.freeResets(11) == "11 бесплатных сбросов")
    #expect(Phrases.freeResets(22) == "22 бесплатных сброса")
}

@Test func ignoresNonQuotaLines() {
    #expect(CodexSource.parse(line: Data(#"{"type":"response_item","payload":{"type":"message"}}"#.utf8)).isEmpty)
    #expect(CodexSource.parse(line: Data("not json".utf8)).isEmpty)
}

@Test func parsesClaudeEndpointPoolsAndSkipsMoney() {
    let obj: [String: Any] = [
        "five_hour": ["utilization": 0.0, "resets_at": NSNull()],
        "seven_day": ["utilization": 37.5, "resets_at": "2026-11-20T10:00:00.123456+00:00"],
        "seven_day_fable": ["utilization": 61, "resets_at": "2026-11-20T10:00:00Z"],
        "extra_usage": ["is_enabled": false, "utilization": 0],
    ]
    let snaps = ClaudeSource.parseEndpoint(obj, observedAt: Date())
    #expect(Set(snaps.map(\.pool.id)) == ["seven_day", "seven_day_fable"]) // null reset = unknown, not 0%
    let fable = snaps.first { $0.pool.id == "seven_day_fable" }
    #expect(fable?.title == "Неделя · Fable")
    #expect(fable?.windowMinutes == 10080)
}

@Test func parsesClaudeEndpointLimitsArray() throws {
    // Trimmed from a real response for an account without a 5-hour window.
    let json = """
    {"five_hour": null, "seven_day": {"utilization": 41.0, "resets_at": "2026-11-19T10:00:00.066959+00:00"},
     "limits": [
      {"kind": "weekly_all", "group": "weekly", "percent": 41, "resets_at": "2026-11-19T10:00:00.066959+00:00", "scope": null},
      {"kind": "weekly_scoped", "group": "weekly", "percent": 3, "resets_at": "2026-11-19T10:00:00.067140+00:00",
       "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}}],
     "extra_usage": {"is_enabled": false, "utilization": null}}
    """
    let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let snaps = ClaudeSource.parseEndpoint(obj, observedAt: Date())
    #expect(Set(snaps.map(\.pool.id)) == ["seven_day", "seven_day_fable"])
    #expect(snaps.first { $0.pool.id == "seven_day_fable" }?.usedPercent == 3)
    #expect(snaps.allSatisfy { $0.windowMinutes == 10080 })
}

@Test func parsesOfficialCLIUsageText() throws {
    let text = """
    You are currently using your subscription to power your Claude Code usage

    Current week (all models): 41% used · resets Nov 19 at 2pm (Europe/Samara)
    Current week (Fable): 3% used · resets Nov 19 at 2:30pm (Europe/Samara)
    Current session: 12% used · resets 7pm (Europe/Samara)

    Last 24h · 2988 requests · 7 sessions
      88% of your usage was at >150k context
    """
    let now = try #require(parseISODate("2026-11-15T13:47:00Z")) // 17:47 in Samara (UTC+4)
    let snaps = ClaudeSource.parseCLIUsage(text, observedAt: now)
    #expect(snaps.count == 3)
    let week = try #require(snaps.first { $0.pool.id == "seven_day" })
    #expect(week.usedPercent == 41)
    #expect(week.resetsAt == parseISODate("2026-11-19T10:00:00Z"))
    #expect(snaps.first { $0.pool.id == "seven_day_fable" }?.resetsAt == parseISODate("2026-11-19T10:30:00Z"))
    let session = try #require(snaps.first { $0.pool.id == "five_hour" })
    #expect(session.resetsAt == parseISODate("2026-11-15T15:00:00Z"))
    #expect(session.windowMinutes == 300)
}

@Test func parsesClaudeStatusLine() {
    let limits: [String: Any] = ["seven_day": ["used_percentage": 41, "resets_at": 1795200000]]
    let snaps = ClaudeSource.parseStatusLine(limits, receivedAt: Date())
    #expect(snaps.count == 1)
    #expect(snaps.first?.usedPercent == 41)
    #expect(snaps.first?.source == .claudeStatusLine)
}

@Test func isoDatesWithAnyFraction() {
    #expect(parseISODate("2026-11-15T13:01:40Z") == Date(timeIntervalSince1970: 1_794_747_700))
    #expect(abs(parseISODate("2026-11-15T17:01:40.5+04:00")!.timeIntervalSince1970 - 1_794_747_700.5) < 1e-6)
}

@Test func tokenLedgerCountsEachMessageOnce() {
    var ledger = ClaudeTokenLedger()
    let line = Data(#"{"type":"assistant","timestamp":"2026-11-15T13:00:00Z","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_read_input_tokens":100,"cache_creation_input_tokens":10,"output_tokens":5}}}"#.utf8)
    ledger.ingest(line: line)
    ledger.ingest(line: line) // the same message is written once per content block
    let totals = ledger.totals(since: Date(timeIntervalSince1970: 1_794_700_000))
    #expect(totals["claude-opus-5-5"]?.messages == 1)
    #expect(totals["claude-opus-5-5"]?.total == 117)
}

@Test func incrementalReaderSkipsPartialLines() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("slowburn-\(UUID()).jsonl")
    try Data("aaaa\nbbbb\ncc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    var reader = IncrementalReader(offsets: [:], initialTail: 7) // lands inside "bbbb"
    #expect(reader.newLines(in: url).isEmpty) // fragment dropped, "cc" not finished
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("c\ndddd\n".utf8))
    try handle.close()
    #expect(reader.newLines(in: url).map { String(decoding: $0, as: UTF8.self) } == ["ccc", "dddd"])
}

// MARK: brake

private func state(level: Level, reasons: [String], generatedAt: Date, override: Date? = nil,
                   credits: CreditsStatus? = nil, provider: Provider = .claude) -> AppState {
    let snap = Snapshot(pool: PoolKey(provider, "seven_day"), title: "Неделя", usedPercent: 100,
                        resetsAt: generatedAt.addingTimeInterval(86400), windowMinutes: 10080,
                        observedAt: generatedAt, source: .claudeUsageEndpoint, precision: 1)
    let pool = PoolStatus(snapshot: snap, freshness: .fresh, level: level, correctionDetected: false, reasons: reasons)
    return AppState(generatedAt: generatedAt, pools: [pool],
                    providers: [ProviderSummary(provider: provider, level: level, error: nil)],
                    claudeTokens24h: [:], codexCredits: credits, overrideUntil: override)
}

@Test func brakeBlocksRedAndLetsUserThrough() {
    let now = Date()
    let red = state(level: .red, reasons: ["limit_reached"], generatedAt: now)
    guard case .block = Brake.decide(state: red, provider: .claude, prompt: "привет", now: now) else {
        Issue.record("expected block"); return
    }
    guard case .warn = Brake.decide(state: red, provider: .claude, prompt: "  ++ привет", now: now) else {
        Issue.record("++ must pass"); return
    }
    let overridden = state(level: .red, reasons: ["limit_reached"], generatedAt: now, override: now.addingTimeInterval(600))
    guard case .warn = Brake.decide(state: overridden, provider: .claude, prompt: "привет", now: now) else {
        Issue.record("override must pass"); return
    }
}

@Test func brakeFailsOpenOnOldOrMissingState() {
    let now = Date()
    let old = state(level: .red, reasons: ["limit_reached"], generatedAt: now.addingTimeInterval(-3600))
    #expect(Brake.decide(state: old, provider: .claude, prompt: "x", now: now) == .allow)
    #expect(Brake.decide(state: nil, provider: .claude, prompt: "x", now: now) == .allow)
}

@Test func brakeNamesCreditSpending() {
    let now = Date()
    let credits = CreditsStatus(balance: 100, observedAt: now, spentLastHour: 3, spent24h: 3)
    let s = state(level: .red, reasons: ["limit_reached"], generatedAt: now, credits: credits, provider: .codex)
    guard case .block(let reason) = Brake.decide(state: s, provider: .codex, prompt: "x", now: now) else {
        Issue.record("expected block"); return
    }
    #expect(reason.contains("credits"))
}

@Test func codexLedgerCountsEachTurnOnceAndSkipsCreditTurns() {
    func line(total: Int, input: Int, cached: Int, output: Int, primary: Double) -> Data {
        Data("""
        {"timestamp":"2026-11-15T13:48:39.613Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(total)},"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"output_tokens":\(output)}},"rate_limits":{"primary":{"used_percent":\(primary),"window_minutes":300},"secondary":{"used_percent":18.0,"window_minutes":10080}}}}
        """.utf8)
    }
    var ledger = CodexTokenLedger()
    ledger.ingest(line: line(total: 100, input: 1000, cached: 900, output: 10, primary: 40), file: "a")
    ledger.ingest(line: line(total: 100, input: 1000, cached: 900, output: 10, primary: 40), file: "a") // repeated event
    ledger.ingest(line: line(total: 200, input: 1000, cached: 0, output: 0, primary: 100), file: "a")  // paid from credits
    let counted: Double = ledger.slices.values.reduce(0, +)
    #expect(counted == 270) // 100 fresh + 900 cached at a tenth + 10 output at eight times
}

@Test func claudeCurveJoinsOldHoursToNewSlicesWithoutCountingTwice() throws {
    var ledger = ClaudeTokenLedger()
    var c = TokenCounts()
    c.input = 1000
    ledger.hours[3600] = ["claude-opus-5-5": c]          // 1000 in the hour 1:00–2:00
    ledger.slices = [5400: ["claude-opus-5-5": 400]]      // 400 of it at 1:30, kept as a slice
    let curve = try #require(ledger.curve(for: PoolKey(.claude, "seven_day"), now: Date(timeIntervalSince1970: 7200)))
    let total = curve.amount(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 7200))
    #expect(abs(total - 1000) < 1e-6)
    #expect(ledger.curve(for: PoolKey(.claude, "seven_day_fable"), now: Date(timeIntervalSince1970: 7200)) == nil)
}
