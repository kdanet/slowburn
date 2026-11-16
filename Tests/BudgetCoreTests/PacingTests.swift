import Foundation
import Testing
@testable import BudgetCore

private let week = 7 * 24 * 60
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func hours(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

private func weekly(used: Double, at: Date, resets: Date = hours(168), precision: Double = 1) -> Snapshot {
    Snapshot(pool: PoolKey(.claude, "seven_day"), title: "Неделя", usedPercent: used, resetsAt: resets,
             windowMinutes: week, observedAt: at, source: .claudeUsageEndpoint, precision: precision)
}

private func noAdvance() -> PaceSettings {
    var s = PaceSettings()
    s.margin = 0
    s.advanceHours = 0
    return s
}

@Test func fullWeekEarnsExactlyQuota() {
    var settings = PaceSettings()
    settings.margin = 2
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: settings)
    #expect(plan.quota == 98)
    #expect(abs(plan.earned(at: hours(168)) - 98) < 1e-9)
    #expect(abs(plan.earned(at: hours(500)) - 98) < 1e-9) // clamped after reset
    #expect(plan.advance > 0)
    #expect(abs(plan.earned(at: t0) - plan.advance) < 1e-9)
}

@Test func uniformRateMatchesWeeklyFigures() {
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: noAdvance())
    #expect(abs(plan.earned(at: hours(24)) - 100.0 / 7) < 1e-9)
    #expect(abs(plan.fiveHourBudget - 100.0 / 168 * 5) < 1e-9)
}

@Test func idleDaySplitsIntoNormalAndBatteryWithoutDoubleCounting() {
    let settings = noAdvance()
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: settings)
    let s = Pacer.evaluate(snapshot: weekly(used: 0, at: hours(24)), plan: plan,
                           history: [UsagePoint(at: t0, used: 0)], settings: settings, now: hours(24))
    let a = try! #require(s.available)
    #expect(abs(a - 100.0 / 7) < 1e-9)
    #expect(abs((s.normal ?? 0) + (s.battery ?? 0) - a) < 1e-9)
    #expect(abs((s.normal ?? 0) - 100.0 / 168 * 5) < 1e-9)
    #expect(abs((s.batteryHours ?? 0) - 19) < 1e-9) // 24h earned − 5h normal
    #expect(s.level == .green)
}

@Test func midWeekPlanSpreadsTheRemainderNotTheNominalRate() {
    // 40 points left for four days, no margin: 10 per day, not 14.29.
    let settings = noAdvance()
    let plan = PacePlan.start(from: weekly(used: 60, at: t0, resets: hours(96)), now: t0, settings: settings)
    #expect(abs(plan.ratePerHour * 24 - 10) < 1e-9)
    #expect(abs(plan.fiveHourBudget - 10.0 / 24 * 5) < 1e-9)
}

@Test func windowStartPlanCountsTheWholeWeek() throws {
    // Window opened 80 h ago, 43 % used: the straight line says 98·80/168 ≈ 46.7 by now → ~3.7 saved up.
    let s = weekly(used: 43, at: hours(80), resets: hours(168))
    let plan = PacePlan.fromWindowStart(s, settings: PaceSettings())
    #expect(plan.t0 == t0)
    #expect(plan.u0 == 0)
    let status = Pacer.evaluate(snapshot: s, plan: plan, history: [], settings: PaceSettings(), now: hours(80))
    let a = try #require(status.available)
    #expect(abs(a - (98.0 * 80 / 168 - 43)) < 1e-9)
    #expect(status.level == .green)
    // Normal 5-hour share first, the rest is battery.
    #expect(abs((status.battery ?? 0) - (a - 98.0 / 168 * 5)) < 1e-9)
}

@Test func manualReplanForgetsTheWeekSoFar() {
    let s = weekly(used: 60, at: hours(72), resets: hours(168))
    let replanned = PacePlan.start(from: s, now: hours(72), settings: PaceSettings())
    #expect(replanned.fromNow == true)
    #expect(replanned.u0 == 60)
    #expect(PacePlan.fromWindowStart(s, settings: PaceSettings()).fromNow == nil)
}

@Test func overspendingTurnsRed() {
    let settings = noAdvance()
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: settings)
    let s = Pacer.evaluate(snapshot: weekly(used: 5, at: hours(2)), plan: plan,
                           history: [UsagePoint(at: t0, used: 0)], settings: settings, now: hours(2))
    #expect((s.available ?? 0) < 0)
    #expect(s.level == .red)
    #expect(s.reasons.contains("earned_exhausted"))
}

@Test func spendingSavedBudgetIsCalm() {
    let settings = noAdvance()
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: settings)
    let b5 = plan.fiveHourBudget
    // Idle for 43 h, a burst to 1.4×B5, then calm: 1.5×B5 in the last 5 hours, little in the last 2.
    let history = [UsagePoint(at: t0, used: 0), UsagePoint(at: hours(43), used: 0), UsagePoint(at: hours(45.5), used: b5 * 1.4)]
    let snap = weekly(used: b5 * 1.5, at: hours(48), precision: 0.01)
    // With one norm added by hand ("+"), spending from the reserve is noted but stays calm.
    let boosted = Pacer.evaluate(snapshot: snap, plan: plan, history: history, settings: settings, now: hours(48),
                                 fiveHourBoost: b5)
    #expect(boosted.exhaustsAt == nil)
    #expect(boosted.level == .green)
    #expect(boosted.reasons.contains("using_battery"))
    #expect((boosted.available ?? 0) > 0)
    // Without it the 5-hour limit is just the norm: 1.5 norms is over it.
    let plain = Pacer.evaluate(snapshot: snap, plan: plan, history: history, settings: settings, now: hours(48))
    #expect(plain.level == .yellow)
    #expect(plain.reasons.contains("battery_discharge_cap"))
}

@Test func expiredWindowIsUnknownNotZero() {
    let plan = PacePlan.start(from: weekly(used: 50, at: t0), now: t0, settings: PaceSettings())
    let s = Pacer.evaluate(snapshot: weekly(used: 50, at: t0), plan: plan, history: [],
                           settings: PaceSettings(), now: hours(169))
    #expect(s.level == .unknown)
    #expect(s.available == nil)
}

@Test func decreaseInsideWindowIsFlaggedAsCorrection() {
    let plan = PacePlan.start(from: weekly(used: 30, at: t0), now: t0, settings: PaceSettings())
    let s = Pacer.evaluate(snapshot: weekly(used: 25, at: hours(1)), plan: plan, history: [],
                           settings: PaceSettings(), now: hours(1))
    #expect(s.correctionDetected)
    #expect(s.consumed == 0) // a drop never charges the battery
}

@Test func staleReadingIsMarked() {
    let plan = PacePlan.start(from: weekly(used: 10, at: t0), now: t0, settings: PaceSettings())
    let s = Pacer.evaluate(snapshot: weekly(used: 10, at: t0), plan: plan, history: [],
                           settings: PaceSettings(), now: hours(1))
    #expect(s.freshness == .stale)
    #expect(s.reasons.contains("stale_data"))
}

@Test func shortWindowForecastsExhaustion() {
    let now = hours(2)
    let s = Snapshot(pool: PoolKey(.codex, "codex.300"), title: "5 часов", usedPercent: 60, resetsAt: hours(4.5),
                     windowMinutes: 300, observedAt: now, source: .codexRollout, precision: 1)
    let history = [UsagePoint(at: hours(1), used: 30)] // 30 points/hour → 100% in 80 min, before reset
    let status = Pacer.evaluate(snapshot: s, plan: nil, history: history, settings: PaceSettings(), now: now)
    #expect(status.level == .yellow)
    #expect(abs((status.burnPerHour ?? 0) - 30) < 1e-9)
    let eta = try! #require(status.exhaustsAt)
    #expect(abs(eta.timeIntervalSince(now) - 80 * 60) < 1)
}

@Test func shortWindowAtLimitIsRed() {
    let s = Snapshot(pool: PoolKey(.codex, "codex.300"), title: "5 часов", usedPercent: 100, resetsAt: hours(3),
                     windowMinutes: 300, observedAt: hours(1), source: .codexRollout, precision: 1)
    let status = Pacer.evaluate(snapshot: s, plan: nil, history: [], settings: PaceSettings(), now: hours(1))
    #expect(status.level == .red)
}

@Test func fiveHourCapIsTheNormUntilYouAddMore() {
    // Default: the norm only, whatever the savings.
    #expect(Pacer.fiveHourCap(norm: 2.9, battery: 33, boost: 0) == 2.9)
    // Two presses of "+": two more norms.
    #expect(abs(Pacer.fiveHourCap(norm: 2.9, battery: 33, boost: 5.8) - 8.7) < 1e-9)
    // Never more than the savings hold.
    #expect(Pacer.fiveHourCap(norm: 2.9, battery: 1, boost: 5.8) == 3.9)
    #expect(Pacer.fiveHourCap(norm: 2.9, battery: -4, boost: 5.8) == 2.9)
    // A press adds one norm, or the last of the savings.
    #expect(Pacer.boostStep(norm: 2.9, battery: 33, boost: 0) == 2.9)
    #expect(abs(Pacer.boostStep(norm: 2.9, battery: 4, boost: 2.9) - 1.1) < 1e-9)
    #expect(Pacer.boostStep(norm: 2.9, battery: 4, boost: 4) == 0)
}

@Test func rollingFiveHoursFreeUpAsOldReadingsRollOff() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ h: Double, _ used: Double) -> UsagePoint { UsagePoint(at: now.addingTimeInterval(h * 3600), used: used) }
    let history = [at(-4, 40), at(-3, 42), at(-2, 45), at(-1, 47), at(0, 48)]
    let t0 = now.addingTimeInterval(-10 * 3600)
    // 8 spent over a limit of 4: back within it once the 45 % reading (2 h ago) is the base — in 3 hours.
    let frees = Pacer.rollingRelease(history: history, current: 48, limit: 4, t0: t0, now: now)
    #expect(frees == now.addingTimeInterval(3 * 3600))
    // Fully rolled off 5 hours after the last increase.
    #expect(Pacer.rollingRelease(history: history, current: 48, limit: 0, t0: t0, now: now) == now.addingTimeInterval(5 * 3600))
    // Already within the limit: nothing to wait for.
    #expect(Pacer.rollingRelease(history: history, current: 48, limit: 9, t0: t0, now: now) == nil)
    // Spending before the plan started is never charged: 45 → 48 since the start, over a limit of 2
    // until the 47 % reading (1 h ago) rolls off.
    let lateStart = now.addingTimeInterval(-1.5 * 3600)
    #expect(Pacer.rollingRelease(history: history, current: 48, limit: 4, t0: lateStart, now: now) == nil)
    #expect(Pacer.rollingRelease(history: history, current: 48, limit: 2, t0: lateStart, now: now)
            == now.addingTimeInterval(4 * 3600))
}

@Test func autoReserveBacksTheFiveHourLimitWithAllOfIt() {
    // The reserve's checkbox passes an unbounded top-up: the cap is the norm plus the whole reserve, never more.
    #expect(Pacer.fiveHourCap(norm: 2, battery: 3, boost: .greatestFiniteMagnitude) == 5)
    #expect(Pacer.fiveHourCap(norm: 2, battery: 0, boost: .greatestFiniteMagnitude) == 2)
    // Nothing left for "+" to add.
    #expect(Pacer.boostStep(norm: 2, battery: 3, boost: .greatestFiniteMagnitude) == 0)
}

// MARK: - Filling in between whole-percent readings

/// One unit of local spending per hour, every hour since t0; the week ticks up a percent every 10 units.
private func steadyCurve(until h: Double) -> SpendCurve {
    SpendCurve(buckets: (0..<Int(h.rounded(.up))).map { i in
        SpendCurve.Bucket(start: hours(Double(i)), length: min(3600, (h - Double(i)) * 3600), amount: 1)
    })
}

@Test func curveSpreadsBucketsAndMeasuresRateOnSteps() {
    let curve = steadyCurve(until: 30)
    #expect(abs(curve.amount(from: hours(0.5), to: hours(2)) - 1.5) < 1e-9)
    let history = [UsagePoint(at: hours(0), used: 0), UsagePoint(at: hours(10), used: 1),
                   UsagePoint(at: hours(20), used: 2), UsagePoint(at: hours(30), used: 3)]
    #expect(abs((curve.rate(history: history) ?? 0) - 0.1) < 1e-9)
    #expect(curve.rate(history: Array(history.prefix(2))) == nil) // one step is not enough to measure
}

@Test func fiveHourSpendingMovesBetweenWholePercentReadings() throws {
    let settings = noAdvance()
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: settings)
    let history = [UsagePoint(at: hours(0), used: 0), UsagePoint(at: hours(10), used: 1),
                   UsagePoint(at: hours(20), used: 2), UsagePoint(at: hours(30), used: 3)]
    // By readings alone the last 5 hours (29h–34h) spent a whole percent: the tick at 30h.
    let now = hours(34)
    let plain = Pacer.evaluate(snapshot: weekly(used: 3, at: now), plan: plan, history: history,
                               settings: settings, now: now)
    #expect(plain.spentLast5h == 1)
    let s = Pacer.evaluate(snapshot: weekly(used: 3, at: now), plan: plan, history: history,
                           settings: settings, now: now, curve: steadyCurve(until: 34))
    #expect(abs((s.spentLast5h ?? 0) - 0.5) < 1e-9) // 5 hours at 0.1 an hour
    // Over a cap of 0.3, it is free again once two of those hours have rolled off.
    let tight = Pacer.evaluate(snapshot: weekly(used: 3, at: now), plan: plan, history: history,
                               settings: settings, now: now, curve: steadyCurve(until: 34))
    let frees = Pacer.modelRelease({ at in 0.1 * steadyCurve(until: 34).amount(from: at.addingTimeInterval(-5 * 3600), to: now) },
                                   limit: 0.3, now: now)
    #expect(abs(try #require(frees).timeIntervalSince(hours(36))) < 2)
    #expect(tight.fiveHourClearsAt.map { abs($0.timeIntervalSince(hours(39))) < 2 } == true)
}

@Test func localCurveNeverStraysMoreThanAStepFromTheReadings() {
    let settings = noAdvance()
    let plan = PacePlan.start(from: weekly(used: 0, at: t0), now: t0, settings: settings)
    // Readings jumped by 3 in the last 5 hours (spent elsewhere) while the curve saw only 0.5.
    let history = [UsagePoint(at: hours(0), used: 0), UsagePoint(at: hours(10), used: 1),
                   UsagePoint(at: hours(20), used: 2), UsagePoint(at: hours(29), used: 3), UsagePoint(at: hours(31), used: 6)]
    let s = Pacer.evaluate(snapshot: weekly(used: 6, at: hours(34)), plan: plan, history: history,
                           settings: settings, now: hours(34), curve: steadyCurve(until: 34))
    #expect(abs((s.spentLast5h ?? 0) - 2) < 1e-9) // the 3 of the readings, less one step at most
}
