import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude, codex
}

/// Where a quota number came from. Official-ness never makes an old reading fresh.
public enum SnapshotSource: String, Codable, Sendable {
    case codexRollout        // token_count event written by Codex Desktop/CLI
    case codexAppServer      // account/rateLimits/read
    case codexUsageEndpoint  // chatgpt.com/backend-api/wham/usage (unofficial, live)
    case claudeStatusLine    // rate_limits passed to a statusLine command
    case claudeUsageEndpoint // api.anthropic.com/api/oauth/usage (unofficial)
    case claudeCLIUsage      // `claude -p /usage`, printed by the official CLI
    case claudeRejection     // transcript recorded an API rejection: means 100%
}

/// One provider quota window, e.g. Claude's weekly pool or Codex's 5-hour window.
/// `id` is stable within a provider ("seven_day", "seven_day_fable", "codex.300").
public struct PoolKey: Hashable, Codable, Sendable, Comparable {
    public var provider: Provider
    public var id: String

    public init(_ provider: Provider, _ id: String) {
        self.provider = provider
        self.id = id
    }

    public var storageKey: String { "\(provider.rawValue)/\(id)" }

    public static func < (a: PoolKey, b: PoolKey) -> Bool { a.storageKey < b.storageKey }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public var pool: PoolKey
    public var title: String
    /// Percentage points of this pool used, as reported by the provider (0...100).
    public var usedPercent: Double
    public var resetsAt: Date
    public var windowMinutes: Int
    /// When the provider (or the file that carried it) measured this value.
    public var observedAt: Date
    public var source: SnapshotSource
    /// Smallest step the provider reports in (1.0 when only whole percents arrive).
    public var precision: Double

    public init(pool: PoolKey, title: String, usedPercent: Double, resetsAt: Date, windowMinutes: Int,
                observedAt: Date, source: SnapshotSource, precision: Double) {
        self.pool = pool
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
        self.observedAt = observedAt
        self.source = source
        self.precision = precision
    }

    public var windowStart: Date { resetsAt.addingTimeInterval(-Double(windowMinutes) * 60) }
    /// Weekly-ish windows get a pacing plan; short ones (Codex 5h) only a burn forecast.
    public var isLongWindow: Bool { windowMinutes >= 24 * 60 }
}

public enum Freshness: String, Codable, Sendable {
    case fresh, stale, unknown

    public static func of(_ observedAt: Date?, now: Date, staleAfter: TimeInterval) -> Freshness {
        guard let observedAt else { return .unknown }
        return now.timeIntervalSince(observedAt) <= staleAfter ? .fresh : .stale
    }
}

/// Soft-brake levels. The brake only ever acts at a new-prompt boundary.
public enum Level: String, Codable, Sendable, Comparable {
    case green, yellow, red, unknown

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .green: 1
        case .yellow: 2
        case .red: 3
        }
    }

    public static func < (a: Level, b: Level) -> Bool { a.rank < b.rank }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}
