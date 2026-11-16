import Foundation

/// User-tunable pacing knobs. All amounts are percentage points of one pool.
public struct PaceSettings: Codable, Sendable, Equatable {
    /// Technical reserve kept out of the plan (lag + whole-percent rounding).
    public var margin: Double = 2
    /// Start-of-plan advance, in hours of normal earning. Part of the weekly total, not on top of it.
    public var advanceHours: Double = 5
    /// How many extra 5h-budgets the battery may release per 5-hour slot.
    public var batteryDischargeFactor: Double = 1
    /// Readings older than this are stale: the soft brake stops blocking on them.
    public var staleAfter: TimeInterval = 15 * 60
    /// Window used to estimate the current burn rate.
    public var burnLookback: TimeInterval = 2 * 3600

    public init() {}
}

/// Continuous-accrual plan for one long window, anchored where we started watching it.
/// E(t) = L + (Q − L) · clamp((t − t0) / H, 0, 1); at reset exactly Q has been earned.
public struct PacePlan: Codable, Sendable, Equatable {
    public var t0: Date
    public var u0: Double
    public var resetsAt: Date
    public var margin: Double
    public var advance: Double
    /// true: started from the remainder at a chosen moment ("Перепланировать"), forgiving earlier over- or
    /// underspending. nil/false: the plan is the straight line from the window's start.
    public var fromNow: Bool?

    public init(t0: Date, u0: Double, resetsAt: Date, margin: Double, advance: Double, fromNow: Bool? = nil) {
        self.t0 = t0
        self.u0 = u0
        self.resetsAt = resetsAt
        self.margin = margin
        self.advance = advance
        self.fromNow = fromNow
    }

    /// The default: a straight line from the provider's window start. Every window starts at 0 %, so the whole
    /// week is known exactly — savings from earlier days count as reserve, overspending as debt.
    public static func fromWindowStart(_ s: Snapshot, settings: PaceSettings) -> PacePlan {
        PacePlan(t0: s.windowStart, u0: 0, resetsAt: s.resetsAt, margin: settings.margin, advance: 0)
    }

    /// Plan from the current remainder (a manual replan): forgets how the week went so far.
    public static func start(from s: Snapshot, now: Date, settings: PaceSettings) -> PacePlan {
        var plan = PacePlan(t0: now, u0: s.usedPercent, resetsAt: s.resetsAt, margin: settings.margin, advance: 0, fromNow: true)
        plan.advance = Swift.min(plan.quota, plan.ratePerHour * settings.advanceHours)
        return plan
    }

    /// Q: budget to spread until reset.
    public var quota: Double { Swift.max(0, 100 - u0 - margin) }
    public var hours: Double { Swift.max(resetsAt.timeIntervalSince(t0) / 3600, 1.0 / 60) }
    /// r: fixed for the life of the plan, so saved budget is not silently re-spread.
    public var ratePerHour: Double { quota / hours }
    public var fiveHourBudget: Double { ratePerHour * 5 }

    public func earned(at t: Date) -> Double {
        let frac = (t.timeIntervalSince(t0) / 3600 / hours).clamped(0, 1)
        return advance + (quota - advance) * frac
    }
}

/// One observed value of a pool inside the current window.
public struct UsagePoint: Codable, Sendable, Equatable {
    public var at: Date
    public var used: Double

    public init(at: Date, used: Double) {
        self.at = at
        self.used = used
    }
}

public struct PoolStatus: Codable, Sendable, Equatable {
    public var snapshot: Snapshot
    public var freshness: Freshness
    public var level: Level

    // Long windows only (nil for short ones such as Codex 5h).
    public var plan: PacePlan?
    public var earned: Double?
    public var consumed: Double?
    /// A = E − C: earned and not yet spent. Negative means ahead of plan.
    public var available: Double?
    public var normal: Double?
    public var battery: Double?
    public var batteryHours: Double?
    /// The current 5-hour slot's norm and what has been spent in it so far.
    public var fiveHourBudget: Double?
    public var spentThisSlot: Double?
    /// How much the current 5-hour slot may take: the norm plus what you added from savings (see `Pacer.fiveHourCap`).
    public var fiveHourCap: Double?
    /// The part of `fiveHourCap` above the norm, added from the reserve ("+" or the reserve's checkbox).
    public var fiveHourBoost: Double?
    /// Percent per unit of the local spend curve (see `SpendCurve.rate`), kept for the next week's first hours.
    public var spendRate: Double?
    /// When the added part runs out: the end of the slot, when the next one starts from the norm.
    public var boostUntil: Date?
    /// The reserve feeds the 5-hour limit on its own, all of it (the reserve's checkbox).
    public var fiveHourAuto: Bool?
    /// Over the limit: when it opens again — the next slot, with a fresh norm (nil = not over).
    public var fiveHourFreesAt: Date?
    /// When the current 5-hour slot ends and the next one starts from zero.
    public var fiveHourResetsAt: Date?
    /// Ahead of plan (`available` < 0): the start of the first slot whose norm brings it back above zero.
    public var planBackAt: Date?

    // Forecast, any window.
    public var burnPerHour: Double?
    public var projectedAtReset: Double?
    public var exhaustsAt: Date?
    /// Usage went down inside the same window: a provider correction or a stale reply.
    public var correctionDetected: Bool

    public var reasons: [String]

    /// Today / will-it-last / hours-of-work numbers for long windows (filled by the monitor).
    public var smart: SmartStats?

    public init(snapshot: Snapshot, freshness: Freshness, level: Level, correctionDetected: Bool, reasons: [String]) {
        self.snapshot = snapshot
        self.freshness = freshness
        self.level = level
        self.correctionDetected = correctionDetected
        self.reasons = reasons
    }
}

public enum Pacer {
    /// Our own 5-hour limit: the norm, plus whatever you deliberately added from savings ("+" in the app),
    /// never more than the savings actually hold. Nothing is taken from the reserve on its own.
    public static func fiveHourCap(norm: Double, battery: Double, boost: Double) -> Double {
        norm + Swift.min(Swift.max(0, battery), Swift.max(0, boost))
    }

    /// One press of "+": one more norm, or what is left of the savings if that is less.
    public static func boostStep(norm: Double, battery: Double, boost: Double) -> Double {
        Swift.max(0, Swift.min(norm, Swift.max(0, battery) - Swift.max(0, boost)))
    }

    /// Points per hour over the lookback, measured from the last reading at or before its start.
    public static func burnRate(history: [UsagePoint], current: UsagePoint, lookback: TimeInterval) -> Double? {
        let cutoff = current.at.addingTimeInterval(-lookback)
        let sorted = history.sorted { $0.at < $1.at }
        guard let base = sorted.last(where: { $0.at <= cutoff }) ?? sorted.first(where: { $0.at < current.at }) else {
            return nil
        }
        let hours = current.at.timeIntervalSince(base.at) / 3600
        guard hours >= 10.0 / 60 else { return nil }
        return Swift.max(0, current.used - base.used) / hours
    }

    /// Usage added since `since`, using the last reading at or before it (or `fallback`).
    public static func spent(history: [UsagePoint], current: Double, since: Date, fallback: Double) -> Double {
        let base = history.filter { $0.at <= since }.max { $0.at < $1.at }?.used ?? fallback
        return Swift.max(0, current - base)
    }

    public static func evaluate(snapshot s: Snapshot, plan: PacePlan?, history: [UsagePoint],
                                settings: PaceSettings, now: Date, fiveHourBoost: Double = 0,
                                curve: SpendCurve? = nil,
                                curveRate: Double? = nil) -> PoolStatus {
        let current = UsagePoint(at: Swift.max(s.observedAt, history.map(\.at).max() ?? s.observedAt), used: s.usedPercent)
        let freshness = Freshness.of(s.observedAt, now: now, staleAfter: settings.staleAfter)
        var status = PoolStatus(snapshot: s, freshness: freshness, level: .green, correctionDetected: false, reasons: [])

        // The window this reading belongs to is over: its number says nothing about the new one.
        if now >= s.resetsAt {
            status.level = .unknown
            status.reasons.append("window_reset_pending")
            return status
        }

        let hoursLeft = Swift.max(0, s.resetsAt.timeIntervalSince(now) / 3600)
        if let burn = burnRate(history: history, current: current, lookback: settings.burnLookback) {
            status.burnPerHour = burn
            status.projectedAtReset = s.usedPercent + burn * hoursLeft
            if burn > 0, s.usedPercent < 100 {
                let eta = now.addingTimeInterval((100 - s.usedPercent) / burn * 3600)
                if eta < s.resetsAt { status.exhaustsAt = eta }
            }
        }

        if s.isLongWindow, let plan {
            // The week is cut into fixed 5-hour slots. Each slot's norm is the plan's earning over it, handed
            // out whole when the slot starts; whatever a slot leaves unspent stays in the reserve.
            let slot = s.fiveHourSlot(at: now)
            // The plan's ledger starts at t0: spending before we started watching is not charged to it.
            let since = Swift.max(slot.start, plan.t0)
            let norm = Swift.max(0, plan.earned(at: slot.end) - plan.earned(at: since))
            let consumed = Swift.max(0, s.usedPercent - plan.u0)
            var spentSlot = since == plan.t0 ? consumed
                : spent(history: history, current: s.usedPercent, since: since,
                        // No reading that old: count from the earliest one we have, never from the plan start.
                        fallback: history.min(by: { $0.at < $1.at })?.used ?? s.usedPercent)
            // Readings in whole percent move the slot's figure in jumps of a third of its norm. Where a finer
            // local measure covers the slot, it says how much went in between — kept within a step of
            // what the readings say, since it can miss spending elsewhere (claude.ai, another Mac).
            // Early in a week there are too few ticks to measure the rate: the last week's (`curveRate`) stands in.
            let rate = curve?.rate(history: history + [current]) ?? curveRate
            status.spendRate = rate
            if let curve, let rate, let covered = curve.coveredFrom, covered <= since {
                let raw = rate * curve.amount(from: since, to: now)
                spentSlot = raw.clamped(Swift.max(0, spentSlot - s.precision), spentSlot + s.precision)
            }
            // A = what the plan has handed out through this slot, less what is spent.
            let earned = plan.earned(at: slot.end)
            let available = earned - consumed
            // The reserve as the slot began: everything earlier slots left unspent (negative = debt).
            let reserve = available - norm + spentSlot
            status.plan = plan
            status.earned = earned
            status.consumed = consumed
            status.available = available
            status.normal = Swift.max(0, Swift.min(norm - spentSlot, available))
            status.battery = Swift.max(0, available - (status.normal ?? 0))
            status.batteryHours = plan.ratePerHour > 0 ? (status.battery ?? 0) / plan.ratePerHour : nil
            status.fiveHourBudget = norm
            status.spentThisSlot = spentSlot
            let cap = Pacer.fiveHourCap(norm: norm, battery: reserve, boost: fiveHourBoost)
            status.fiveHourBoost = cap - norm
            status.fiveHourCap = cap
            if cap - norm > 0 { status.boostUntil = slot.end }
            status.fiveHourResetsAt = slot.end
            if spentSlot > cap { status.fiveHourFreesAt = slot.end }
            if available < 0 {
                // Each later slot hands out its norm when it starts: the first one that covers the debt.
                var start = slot.end
                while start < s.resetsAt {
                    let next = s.fiveHourSlot(at: start)
                    if plan.earned(at: next.end) - consumed >= 0.5 { status.planBackAt = start; break }
                    start = next.end
                }
            }
            status.correctionDetected = s.usedPercent < plan.u0 - s.precision

            var level = Level.green
            if s.usedPercent >= 100 {
                level = .red; status.reasons.append("limit_reached")
            } else if available <= 0 {
                level = .red; status.reasons.append("earned_exhausted")
            } else {
                if spentSlot > cap {
                    level = .yellow; status.reasons.append("battery_discharge_cap")
                } else if spentSlot > norm {
                    // Spending saved-up battery is what it is for: worth a note, not a worry.
                    status.reasons.append("using_battery")
                }
                if status.exhaustsAt != nil {
                    level = Swift.max(level, .yellow); status.reasons.append("burn_exhausts_before_reset")
                }
            }
            status.level = level
        } else {
            var level = Level.green
            if s.usedPercent >= 100 {
                level = .red; status.reasons.append("limit_reached")
            } else if status.exhaustsAt != nil {
                level = .yellow; status.reasons.append("burn_exhausts_before_reset")
            }
            status.level = level
        }

        if freshness != .fresh { status.reasons.append("stale_data") }
        return status
    }
}
