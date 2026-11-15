import BudgetCore
import Foundation

/// The one question the popover answers: how much more can I work — today, and until the reset.
/// Everything is in points of the provider's long window; `hours(_:)` turns points into hours of
/// *your* active work once the price of an hour is known.
public struct WorkBudget: Sendable, Equatable {
    /// Earned by midnight under the plan, minus what is already spent. Includes saved-up battery.
    public var todayLeft: Double
    /// Spent since midnight (or since history began today).
    public var spentToday: Double
    /// Usable until the reset (the safety margin excluded).
    public var untilReset: Double
    /// `untilReset` spread over the remaining days.
    public var perDay: Double
    public var resetsAt: Date
    /// Points one hour of active work costs; nil while learning.
    public var burnPerHour: Double?
    /// At the recent pace the budget ends here, before the reset.
    public var runsOutAt: Date?
    /// At the recent pace this much is left unused at the reset.
    public var leftoverAtReset: Double?
    public var daysLeft: Double
    /// Spending speed right now (last 30 min), points per hour; nil while history is too short.
    public var recentBurnPerHour: Double?
    /// The provider's own window: what is left of it, in percent.
    public var weekLeft: Double
    /// Your usual pace, points per day (recent, or the week's average while history is short).
    public var dailyPace: Double?

    /// Today's charge in percent, like a phone battery: share of today's budget still open.
    public var charge: Double { todayFraction * 100 }

    /// How long today's charge lasts if spending continues exactly as in the last half hour.
    /// nil when idle (nothing is draining) or while the speed is not known yet.
    public var timeAtCurrentLoad: TimeInterval? {
        guard let r = recentBurnPerHour, r > 0 else { return nil }
        return todayLeft / r * 3600
    }

    public var isIdle: Bool { recentBurnPerHour == 0 }

    public func hours(_ points: Double) -> Double? {
        guard let b = burnPerHour, b > 0 else { return nil }
        return max(0, points) / b
    }

    /// Share of today's budget still open, for the ring.
    public var todayFraction: Double {
        let total = spentToday + todayLeft
        return total > 0 ? min(1, todayLeft / total) : 0
    }

    /// How much more per day could be spent and still nothing would be lost at the reset.
    public var spareAddPerDay: Double? {
        guard let left = leftoverAtReset, left > 0 else { return nil }
        return left / max(daysLeft, 1.0 / 24)
    }

    public static func make(_ row: LimitRow, now: Date, calendar: Calendar = .current) -> WorkBudget? {
        guard let available = row.available, let rate = row.ratePerHour else { return nil }
        let margin = row.margin ?? 0
        let untilReset = max(0, 100 - margin - row.used)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let toMidnight = max(0, min(midnight, row.resetsAt).timeIntervalSince(now) / 3600)
        let daysLeft = max(row.resetsAt.timeIntervalSince(now) / 86400, 1.0 / 24)
        let s = row.smart
        return WorkBudget(
            todayLeft: min(untilReset, max(0, available + rate * toMidnight)),
            spentToday: s?.spentToday ?? 0,
            untilReset: untilReset,
            perDay: untilReset / daysLeft,
            resetsAt: row.resetsAt,
            burnPerHour: s?.activeBurnPerHour,
            runsOutAt: s?.runsOutAt,
            leftoverAtReset: s?.leftoverAtReset,
            daysLeft: daysLeft,
            recentBurnPerHour: s?.recentBurnPerHour,
            weekLeft: max(0, 100 - row.used),
            dailyPace: s?.dailyPace
        )
    }
}
