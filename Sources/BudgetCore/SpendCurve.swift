import Foundation

/// A finer local measure of spending (Claude Code's own token counts) that fills in between the server's readings.
///
/// The week comes back in whole percent, while the 5-hour norm is only about three of them: counted from
/// readings alone, the 5-hour bar would stand still and then jump by a third. The curve says when, within those
/// steps, the spending happened. Its units are converted to percent by `rate`, measured on the readings themselves.
public struct SpendCurve: Sendable, Equatable {
    public struct Bucket: Sendable, Equatable {
        public var start: Date
        /// The span the amount is spread over (the current bucket: only up to now).
        public var length: TimeInterval
        public var amount: Double

        public init(start: Date, length: TimeInterval, amount: Double) {
            self.start = start
            self.length = length
            self.amount = amount
        }
    }

    public var buckets: [Bucket]

    public init(buckets: [Bucket]) { self.buckets = buckets.sorted { $0.start < $1.start } }

    /// From when the curve knows anything.
    public var coveredFrom: Date? { buckets.first?.start }

    /// Local units spent in `[from, to]`, each bucket spread evenly over its span.
    public func amount(from: Date, to: Date) -> Double {
        var sum = 0.0
        for b in buckets where b.length > 0 {
            let lo = Swift.max(from, b.start), hi = Swift.min(to, b.start.addingTimeInterval(b.length))
            if hi > lo { sum += b.amount * hi.timeIntervalSince(lo) / b.length }
        }
        return sum
    }

    /// Reading units (percent) per local unit: the climb between the first and the last step up the curve covers,
    /// over what the curve spent between them. Both ends are moments a reading ticked up, so both sit on a boundary
    /// of a whole percent. nil until the readings have climbed at least `minClimb`.
    public func rate(history: [UsagePoint], minClimb: Double = 2) -> Double? {
        guard let covered = coveredFrom else { return nil }
        let sorted = history.sorted { $0.at < $1.at }
        var steps: [UsagePoint] = []
        for (i, p) in sorted.enumerated() where i > 0 && p.used > sorted[i - 1].used && p.at >= covered {
            steps.append(p)
        }
        guard let first = steps.first, let last = steps.last, last.used - first.used >= minClimb else { return nil }
        let spent = amount(from: first.at, to: last.at)
        guard spent > 0 else { return nil }
        return (last.used - first.used) / spent
    }
}
