import BudgetCore
import Foundation
import Testing
@testable import QuotaKit

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

// 2027-01-15 08:00 UTC: 16 hours to midnight.
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func row(used: Double, available: Double, rate: Double, resetsInDays: Double, burn: Double?, spentToday: Double = 0) -> LimitRow {
    var smart = SmartStats(activeBurnPerHour: burn, spentToday: spentToday)
    smart.leftoverAtReset = 10
    return LimitRow(id: "x", provider: .codex, title: "Codex · неделя", resetText: "", used: used, planMarker: nil, tone: .ok,
                    windowName: "неделя", resetsAt: now.addingTimeInterval(resetsInDays * 86400),
                    available: available, normal: nil, battery: nil, margin: 2, ratePerHour: rate, smart: smart)
}

@Test func todayIsWhatTheDayEarnsPlusSavings() throws {
    // 1 point/h of plan, 3 points saved now, 16 h to midnight → 19 points can still go today.
    let b = try #require(WorkBudget.make(row(used: 40, available: 3, rate: 1, resetsInDays: 3, burn: 12), now: now, calendar: utc))
    #expect(abs(b.todayLeft - 19) < 1e-9)
    #expect(abs((b.hours(b.todayLeft) ?? 0) - 19.0 / 12) < 1e-9) // in hours of active work
    #expect(b.untilReset == 58)
    #expect(abs(b.perDay - 58.0 / 3) < 1e-9)
}

@Test func overspentTodayIsZeroNotNegative() throws {
    let b = try #require(WorkBudget.make(row(used: 60, available: -30, rate: 1, resetsInDays: 3, burn: 12), now: now, calendar: utc))
    #expect(b.todayLeft == 0)
}

@Test func todayNeverExceedsWhatIsLeftAtAll() throws {
    // Plenty earned on paper, but only 3 usable points remain before the provider limit (and margin).
    let b = try #require(WorkBudget.make(row(used: 95, available: 20, rate: 1, resetsInDays: 3, burn: 12), now: now, calendar: utc))
    #expect(b.todayLeft == 3)
}

@Test func unknownBurnMeansNoHoursYet() throws {
    let b = try #require(WorkBudget.make(row(used: 40, available: 3, rate: 1, resetsInDays: 3, burn: nil), now: now, calendar: utc))
    #expect(b.hours(10) == nil)
}

@Test func chargeAndTimeAtCurrentLoad() throws {
    var r = row(used: 40, available: 3, rate: 1, resetsInDays: 3, burn: 12, spentToday: 19)
    r.smart?.recentBurnPerHour = 38 // ten agents at once
    let b = try #require(WorkBudget.make(r, now: now, calendar: utc))
    #expect(abs(b.charge - 50) < 1e-9) // 19 spent, 19 left
    #expect(abs((b.timeAtCurrentLoad ?? 0) - 30 * 60) < 1e-6) // 19 points at 38/h = 30 min
    r.smart?.recentBurnPerHour = 0
    let idle = try #require(WorkBudget.make(r, now: now, calendar: utc))
    #expect(idle.isIdle)
    #expect(idle.timeAtCurrentLoad == nil)
    #expect(idle.weekLeft == 60)
}

@Test func spareTimeIsSpreadOverRemainingDays() throws {
    let b = try #require(WorkBudget.make(row(used: 40, available: 3, rate: 1, resetsInDays: 2, burn: 12), now: now, calendar: utc))
    #expect(abs((b.spareAddPerDay ?? 0) - 5) < 1e-9) // 10 points unused over 2 days
}
