import Foundation

/// User-tunable pacing knobs. All amounts are percentage points of one pool.
public struct PaceSettings: Codable, Sendable, Equatable {
    /// Technical reserve kept out of the plan (lag + whole-percent rounding).
    public var margin: Double = 2
    /// Start-of-plan advance, in hours of normal earning. Part of the weekly total, not on top of it.
    public var advanceHours: Double = 5
    /// How many extra 5h-budgets the battery may release per rolling 5 hours.
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
    public var fiveHourBudget: Double?
    public var spentLast5h: Double?
    /// How much the last 5 hours may take: the norm plus a slice of the savings (see `Pacer.fiveHourCap`).
    public var fiveHourCap: Double?
    /// The part of `fiveHourCap` above the norm that you added by hand.
    public var fiveHourBoost: Double?
    /// When the hand-added part runs out and the limit is back to the norm.
    public var boostUntil: Date?
    /// The reserve feeds the 5-hour limit on its own, all of it (the reserve's checkbox).
    public var fiveHourAuto: Bool?
    /// The 5-hour limit is rolling, so it has no single reset. With no more spending:
    /// when the last 5 hours are back within the limit (nil = they already are),
    public var fiveHourFreesAt: Date?
    /// and when everything spent in them has rolled off (nil = nothing spent).
    public var fiveHourClearsAt: Date?

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

    /// With no more spending, the first moment the trailing 5 hours take no more than `limit`: each reading
    /// rolls off 5 hours after it was taken. Nothing before `t0` (the plan start) is charged.
    /// nil when that is already true.
    public static func rollingRelease(history: [UsagePoint], current: Double, limit: Double, t0: Date, now: Date,
                                      window: TimeInterval = 5 * 3600) -> Date? {
        // spent(T) = current − (last reading at or before T − 5 h): it falls to `limit` once that reading
        // is the first one that had already reached `current − limit`.
        let need = current - limit
        let sorted = history.sorted(by: { $0.at < $1.at })
        // Already within it, counted the way `evaluate` counts (no reading that old: the earliest one).
        let since = Swift.max(now.addingTimeInterval(-window), t0)
        let base = sorted.last(where: { $0.at <= since })?.used ?? sorted.first?.used ?? current
        guard need > 1e-9, base < need - 1e-9,
              let first = sorted.first(where: { $0.used >= need - 1e-9 }) else { return nil }
        let at = first.at.addingTimeInterval(window)
        return at > now ? at : nil
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
                                boostUntil: Date? = nil) -> PoolStatus {
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
            let earned = plan.earned(at: now)
            let consumed = Swift.max(0, s.usedPercent - plan.u0)
            let available = earned - consumed
            let b5 = plan.fiveHourBudget
            // The plan's ledger starts at t0: spending before we started watching is not charged to it.
            let since = Swift.max(now.addingTimeInterval(-5 * 3600), plan.t0)
            let spent5h = since == plan.t0 ? consumed
                : spent(history: history, current: s.usedPercent, since: since,
                        // No reading that old: count from the earliest one we have, never from the plan start.
                        fallback: history.min(by: { $0.at < $1.at })?.used ?? s.usedPercent)
            status.plan = plan
            status.earned = earned
            status.consumed = consumed
            status.available = available
            status.normal = available.clamped(0, b5)
            status.battery = Swift.max(0, available - b5)
            status.batteryHours = plan.ratePerHour > 0 ? (status.battery ?? 0) / plan.ratePerHour : nil
            status.fiveHourBudget = b5
            status.spentLast5h = spent5h
            let cap = Pacer.fiveHourCap(norm: b5, battery: status.battery ?? 0, boost: fiveHourBoost)
            status.fiveHourBoost = Swift.min(Swift.max(0, status.battery ?? 0), Swift.max(0, fiveHourBoost))
            status.fiveHourCap = cap
            status.boostUntil = boostUntil
            if spent5h > 0 {
                let points = history + [current]
                func release(_ limit: Double) -> Date? {
                    rollingRelease(history: points, current: s.usedPercent, limit: limit, t0: plan.t0, now: now)
                }
                var frees = spent5h > cap ? release(cap) : nil
                // The hand-added part ends first: from then on only the norm counts.
                if let f = frees, let until = boostUntil, f > until, cap > b5 { frees = Swift.max(release(b5) ?? until, until) }
                status.fiveHourFreesAt = frees
                status.fiveHourClearsAt = release(0)
            }
            status.correctionDetected = s.usedPercent < plan.u0 - s.precision

            var level = Level.green
            if s.usedPercent >= 100 {
                level = .red; status.reasons.append("limit_reached")
            } else if available <= 0 {
                level = .red; status.reasons.append("earned_exhausted")
            } else {
                if spent5h > cap {
                    level = .yellow; status.reasons.append("battery_discharge_cap")
                } else if spent5h > b5 {
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
