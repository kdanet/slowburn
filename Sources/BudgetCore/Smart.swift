import Foundation

/// The numbers a person actually asks about, derived from one long window's history:
/// how much of today's budget is gone, will it last until the reset, and what that means in hours of work.
public struct SmartStats: Codable, Sendable, Equatable {
    /// Points of this pool one hour of *active* work costs, learned from history. nil while still learning.
    public var activeBurnPerHour: Double?
    /// How much active time the estimate rests on.
    public var activeHoursObserved: Double

    /// Spent since local midnight (or since the first reading today).
    public var spentToday: Double
    /// The plan's share for a full day.
    public var todayAllowance: Double?

    /// Recent spending, points per calendar day. nil with less than 3 h of history.
    public var dailyPace: Double?
    /// At `dailyPace` the usable budget runs out here, before the reset.
    public var runsOutAt: Date?
    /// At `dailyPace` this much would be left unused at the reset.
    public var leftoverAtReset: Double?

    /// Usable budget left (up to the safety margin), in hours of active work.
    public var workHoursLeft: Double?
    /// `workHoursLeft` spread over the days to the reset.
    public var workHoursPerDay: Double?
    /// `dailyPace` is the window's average so far, not our own recent history.
    public var paceFromWindowAverage = false
    /// Today's count starts here, not at midnight: history began later today.
    public var todaySince: Date?
    /// Spending speed over the last `recentWindow`, points per hour: the "current load", whatever
    /// number of agents produces it. nil while history does not reach back that far.
    public var recentBurnPerHour: Double?

    public init(activeBurnPerHour: Double? = nil, activeHoursObserved: Double = 0, spentToday: Double = 0,
                todayAllowance: Double? = nil, dailyPace: Double? = nil, runsOutAt: Date? = nil,
                leftoverAtReset: Double? = nil, workHoursLeft: Double? = nil, workHoursPerDay: Double? = nil) {
        self.activeBurnPerHour = activeBurnPerHour
        self.activeHoursObserved = activeHoursObserved
        self.spentToday = spentToday
        self.todayAllowance = todayAllowance
        self.dailyPace = dailyPace
        self.runsOutAt = runsOutAt
        self.leftoverAtReset = leftoverAtReset
        self.workHoursLeft = workHoursLeft
        self.workHoursPerDay = workHoursPerDay
    }

    /// Converts points of this pool to hours of active work, when the burn is known.
    public func workHours(_ points: Double) -> Double? {
        guard let b = activeBurnPerHour, b > 0 else { return nil }
        return points / b
    }
}

public enum Smart {
    /// Slots of this length that saw usage grow count as active work.
    public static let slot: TimeInterval = 15 * 60
    /// Below this the burn estimate is noise (whole-percent steps).
    public static let minPointsForBurn = 3.0
    public static let minActiveHours = 0.5
    /// How far back "current load" looks: long enough to see whole-percent steps, short enough to follow
    /// you starting or stopping agents.
    public static let recentWindow: TimeInterval = 30 * 60

    public static func compute(snapshot s: Snapshot, plan: PacePlan?, history: [UsagePoint], now: Date,
                               calendar: Calendar = .current) -> SmartStats {
        var points = history.filter { $0.at <= now }.sorted { $0.at < $1.at }
        if points.last.map({ $0.at < s.observedAt }) ?? true {
            points.append(UsagePoint(at: s.observedAt, used: s.usedPercent))
        }
        var out = SmartStats()

        // Active burn: growth divided by the number of quarter-hours in which growth was seen.
        var increase = 0.0
        var slots = Set<Int>()
        for (a, b) in zip(points, points.dropFirst()) where b.used > a.used {
            increase += b.used - a.used
            slots.insert(Int(b.at.timeIntervalSince1970 / slot))
            if b.at.timeIntervalSince(a.at) <= slot { slots.insert(Int(a.at.timeIntervalSince1970 / slot)) }
        }
        let activeHours = Double(slots.count) * slot / 3600
        out.activeHoursObserved = activeHours
        if increase >= minPointsForBurn, activeHours >= minActiveHours {
            out.activeBurnPerHour = increase / activeHours
        }

        // Today, from the last reading at or before midnight (or the first one after it).
        let midnight = calendar.startOfDay(for: now)
        let base = points.last(where: { $0.at <= midnight }) ?? points.first(where: { $0.at > midnight })
        out.spentToday = max(0, s.usedPercent - (base?.used ?? s.usedPercent))
        out.todayAllowance = plan.map { $0.ratePerHour * 24 }

        // Will it last? Recent pace over up to the last 24 h, extrapolated to the reset.
        let margin = plan?.margin ?? 0
        let usable = max(0, 100 - margin - s.usedPercent)
        let daysLeft = max(s.resetsAt.timeIntervalSince(now) / 86400, 1.0 / 24)
        if let first = points.first {
            let span = min(86400, now.timeIntervalSince(first.at))
            if span >= 3 * 3600 {
                let from = now.addingTimeInterval(-span)
                let start = points.last(where: { $0.at <= from }) ?? first
                out.dailyPace = max(0, s.usedPercent - start.used) / span * 86400
            }
        }
        // Not enough of our own history yet: the window's average so far is still a fair first guess.
        let elapsed = now.timeIntervalSince(s.windowStart)
        if out.dailyPace == nil, elapsed >= 6 * 3600 {
            out.dailyPace = s.usedPercent / elapsed * 86400
            out.paceFromWindowAverage = true
        }
        if let pace = out.dailyPace {
            if pace > 0, usable / pace < daysLeft {
                out.runsOutAt = now.addingTimeInterval(usable / pace * 86400)
            } else {
                out.leftoverAtReset = max(0, usable - pace * daysLeft)
            }
        }
        if let base, base.at > midnight { out.todaySince = base.at }

        // Current load: growth since the reading in force at the start of the window.
        let windowStart = now.addingTimeInterval(-recentWindow)
        if let base = points.last(where: { $0.at <= windowStart }) {
            out.recentBurnPerHour = max(0, s.usedPercent - base.used) / (recentWindow / 3600)
        }

        if let burn = out.activeBurnPerHour, burn > 0 {
            out.workHoursLeft = usable / burn
            out.workHoursPerDay = usable / burn / daysLeft
        }
        return out
    }
}
