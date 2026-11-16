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

    /// The size of the slices local spending is counted in.
    public static let slice = 300

    /// Slices of `size` seconds keyed by their start; the one still going on holds only what was spent up to now.
    public init(slices: [Int: Double], size: Int = SpendCurve.slice, now: Date) {
        self.init(buckets: slices.map { key, amount in
            let start = Date(timeIntervalSince1970: TimeInterval(key))
            return Bucket(start: start, length: Swift.min(TimeInterval(size), Swift.max(1, now.timeIntervalSince(start))),
                          amount: amount)
        })
    }

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

    /// Reading units (percent) per local unit, fitted through the moments the readings ticked up. Each tick sits
    /// on a boundary of a whole percent, so the ticks lie on one line against the curve's running total; a fit
    /// through all of them (not just the two ends) shrugs off a tick seen late because nothing was watching.
    /// nil until the readings have climbed at least `minClimb` over what the curve covers.
    public func rate(history: [UsagePoint], minClimb: Double = 2) -> Double? {
        guard let covered = coveredFrom else { return nil }
        let sorted = history.sorted { $0.at < $1.at }
        var steps: [UsagePoint] = []
        for (i, p) in sorted.enumerated() where i > 0 && p.used > sorted[i - 1].used && p.at >= covered {
            steps.append(p)
        }
        guard let first = steps.first, let last = steps.last, last.used - first.used >= minClimb else { return nil }
        let xs = steps.map { amount(from: first.at, to: $0.at) }, ys = steps.map(\.used)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) { sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx) }
        guard sxx > 0 else { return nil }
        let rate = sxy / sxx
        return rate > 0 && rate.isFinite ? rate : nil
    }
}
