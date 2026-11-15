import BudgetCore
import Foundation
import Testing
@testable import QuotaKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func weekly(_ p: Provider, used: Double, u0: Double, hoursIntoPlan: Double, observed: Date = now) -> PoolStatus {
    let snap = Snapshot(pool: PoolKey(p, p == .claude ? "seven_day" : "codex.10080"), title: "Неделя", usedPercent: used,
                        resetsAt: now.addingTimeInterval(4 * 86400), windowMinutes: 10080, observedAt: observed,
                        source: p == .claude ? .claudeUsageEndpoint : .codexRollout, precision: 1)
    let plan = PacePlan(t0: now.addingTimeInterval(-hoursIntoPlan * 3600), u0: u0, resetsAt: snap.resetsAt, margin: 2, advance: 0)
    var settings = PaceSettings()
    settings.staleAfter = 15 * 60
    return Pacer.evaluate(snapshot: snap, plan: plan, history: [], settings: settings, now: now)
}

private func fiveHour(used: Double) -> PoolStatus {
    let snap = Snapshot(pool: PoolKey(.codex, "codex.300"), title: "5 часов", usedPercent: used,
                        resetsAt: now.addingTimeInterval(3600), windowMinutes: 300, observedAt: now,
                        source: .codexRollout, precision: 1)
    return Pacer.evaluate(snapshot: snap, plan: nil, history: [], settings: PaceSettings(), now: now)
}

private func state(_ pools: [PoolStatus], credits: CreditsStatus? = nil) -> AppState {
    let summaries = Provider.allCases.map { p in
        ProviderSummary(provider: p, level: pools.filter { $0.snapshot.pool.provider == p }.map(\.level).max() ?? .unknown, error: nil)
    }
    return AppState(generatedAt: now, pools: pools, providers: summaries, claudeTokens24h: [:],
                    codexCredits: credits, overrideUntil: nil)
}

@Test func calmBlobShowsHoursOfEarnedPlan() throws {
    // 10 hours into a plan, nothing spent: 10 hours of charge.
    let p = Presentation.make(state([weekly(.claude, used: 40, u0: 40, hoursIntoPlan: 10)]), now: now)
    let claude = try #require(p.blob(.claude))
    #expect(claude.mood == .charged)
    #expect(claude.hoursText == "10 ч")
    #expect(claude.level == 1)
}

@Test func fullCodexWindowWithCreditsSpendingIsMoney() throws {
    let credits = CreditsStatus(balance: 100, observedAt: now, spentLastHour: 14, spent24h: 30)
    let p = Presentation.make(state([fiveHour(used: 100), weekly(.codex, used: 18, u0: 18, hoursIntoPlan: 3)], credits: credits), now: now)
    let codex = try #require(p.blob(.codex))
    #expect(codex.mood == .money)
    #expect(codex.hoursText == "0")
    #expect(p.menuProvider == .codex)
    #expect(p.menuLabel == "$")
    #expect(p.headline.contains("платит credits"))
    #expect(p.moneyNote != nil)
}

@Test func overspentPlanSleepsAndSaysWhenItWakes() throws {
    let p = Presentation.make(state([weekly(.claude, used: 60, u0: 40, hoursIntoPlan: 2)]), now: now)
    let claude = try #require(p.blob(.claude))
    #expect(claude.mood == .sleepy)
    #expect(claude.phrase.hasPrefix("Claude отдыхает до"))
    #expect(p.menuLabel == "zz")
}

@Test func noFreshDataIsUnknownNotEmpty() throws {
    let old = weekly(.claude, used: 40, u0: 40, hoursIntoPlan: 3, observed: now.addingTimeInterval(-3600))
    let p = Presentation.make(state([old]), now: now)
    let claude = try #require(p.blob(.claude))
    #expect(claude.mood == .unknown)
    #expect(claude.hours == nil)
    #expect(p.limits.first?.tone == .stale)
}

@Test func limitRowsCarryPlanMarkerOnlyForLongWindows() {
    let p = Presentation.make(state([weekly(.claude, used: 41, u0: 40, hoursIntoPlan: 10), fiveHour(used: 50)]), now: now)
    #expect(p.limits.map(\.title) == ["Claude · неделя", "Codex · 5 часов"])
    #expect(p.limits[0].planMarker != nil)
    #expect(p.limits[1].planMarker == nil)
}
