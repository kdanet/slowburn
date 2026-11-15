import Foundation
import Testing
@testable import BudgetCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func h(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func weekly(used: Double, at: Date, resetsAt: Date) -> Snapshot {
    Snapshot(pool: PoolKey(.claude, "seven_day"), title: "Неделя", usedPercent: used, resetsAt: resetsAt,
             windowMinutes: 10080, observedAt: at, source: .claudeUsageEndpoint, precision: 1)
}

@Test func activeBurnCountsOnlyWorkingTime() throws {
    // One hour of work (+2 per quarter hour = 8 points), then 5 idle hours: burn is 8/h, not 8/6.
    var history = [UsagePoint(at: h(0), used: 10)]
    for q in 1...4 { history.append(UsagePoint(at: h(Double(q) * 0.25), used: 10 + Double(q) * 2)) }
    let s = weekly(used: 18, at: h(6), resetsAt: h(96))
    let stats = Smart.compute(snapshot: s, plan: nil, history: history, now: h(6), calendar: utc)
    let burn = try #require(stats.activeBurnPerHour)
    #expect(abs(burn - 8 / 1.25) < 0.01) // 4 growth slots + the starting one
    #expect(stats.activeHoursObserved == 1.25)
}

@Test func currentLoadIsTheLastHalfHour() throws {
    // Idle all morning at 20, then 3 points in the last 30 minutes → 6 points/h right now.
    let history = [UsagePoint(at: h(-5), used: 20), UsagePoint(at: h(-0.25), used: 22), UsagePoint(at: h(0), used: 23)]
    let s = weekly(used: 23, at: h(0), resetsAt: h(96))
    let stats = Smart.compute(snapshot: s, plan: nil, history: history, now: h(0), calendar: utc)
    #expect(abs((stats.recentBurnPerHour ?? -1) - 6) < 1e-9)
    // History that starts inside the window cannot say what the load is yet.
    let short = Smart.compute(snapshot: s, plan: nil, history: [UsagePoint(at: h(-0.1), used: 22)], now: h(0), calendar: utc)
    #expect(short.recentBurnPerHour == nil)
}

@Test func tooLittleHistoryMeansStillLearning() {
    // Window opened 72 h ago (resets in 96 h of a 168 h week); history only from the last hour.
    let s = weekly(used: 11, at: h(1), resetsAt: h(97))
    let stats = Smart.compute(snapshot: s, plan: nil, history: [UsagePoint(at: h(0), used: 10)], now: h(1), calendar: utc)
    #expect(stats.activeBurnPerHour == nil)
    #expect(stats.workHoursLeft == nil)
    // Pace falls back to the window's average so far: 11 points in 72 h = 3.67/day.
    #expect(stats.paceFromWindowAverage)
    #expect(abs((stats.dailyPace ?? 0) - 11.0 / 3) < 0.01)
    #expect(stats.todaySince == h(0))
}

@Test func spentTodayStartsAtMidnight() {
    // t0 is 2027-01-15 08:00 UTC; midnight is 8 hours earlier.
    let history = [UsagePoint(at: h(-10), used: 20), UsagePoint(at: h(-2), used: 25), UsagePoint(at: h(1), used: 30)]
    let s = weekly(used: 33, at: h(2), resetsAt: h(96))
    let plan = PacePlan(t0: h(-20), u0: 15, resetsAt: h(96), margin: 2, advance: 0)
    let stats = Smart.compute(snapshot: s, plan: plan, history: history, now: h(2), calendar: utc)
    #expect(stats.spentToday == 13) // 33 now − 20 at the last reading before midnight
    #expect(abs((stats.todayAllowance ?? 0) - plan.ratePerHour * 24) < 1e-9)
}

@Test func fastPaceRunsOutBeforeReset() throws {
    // 20 points in the last 10 hours = 48/day; 58 usable points left; 4 days to reset → runs out in ~29 h.
    let history = [UsagePoint(at: h(-10), used: 20), UsagePoint(at: h(0), used: 40)]
    let s = weekly(used: 40, at: h(0), resetsAt: h(96))
    let plan = PacePlan(t0: h(-48), u0: 0, resetsAt: h(96), margin: 2, advance: 0)
    let stats = Smart.compute(snapshot: s, plan: plan, history: history, now: h(0), calendar: utc)
    let out = try #require(stats.runsOutAt)
    #expect(abs(out.timeIntervalSince(h(0)) / 3600 - 58.0 / 48 * 24) < 0.01)
    #expect(stats.leftoverAtReset == nil)
}

@Test func slowPaceLeavesBudgetUnused() throws {
    // 2 points in 10 hours = 4.8/day over 4 days = 19.2; 58 usable → ~38.8 left unused.
    let history = [UsagePoint(at: h(-10), used: 38), UsagePoint(at: h(0), used: 40)]
    let s = weekly(used: 40, at: h(0), resetsAt: h(96))
    let plan = PacePlan(t0: h(-48), u0: 0, resetsAt: h(96), margin: 2, advance: 0)
    let stats = Smart.compute(snapshot: s, plan: plan, history: history, now: h(0), calendar: utc)
    #expect(stats.runsOutAt == nil)
    #expect(abs((stats.leftoverAtReset ?? 0) - 38.8) < 0.01)
}

@Test func workHoursLeftUsesActiveBurnAndKeepsMargin() throws {
    var history = [UsagePoint(at: h(0), used: 30)]
    for q in 1...8 { history.append(UsagePoint(at: h(Double(q) * 0.25), used: 30 + Double(q))) } // 4 points/h
    let s = weekly(used: 38, at: h(2), resetsAt: h(50))
    let plan = PacePlan(t0: h(0), u0: 30, resetsAt: h(50), margin: 2, advance: 0)
    let stats = Smart.compute(snapshot: s, plan: plan, history: history, now: h(2), calendar: utc)
    let burn = try #require(stats.activeBurnPerHour)
    #expect(abs((stats.workHoursLeft ?? 0) - 60 / burn) < 1e-9) // (100 − 2 − 38) / burn
    #expect(abs((stats.workHoursPerDay ?? 0) - 60 / burn / 2) < 1e-9) // 48 h = 2 days left
}
