import BudgetCore
import Foundation

/// "+" on the 5-hour bar: savings you chose to add to the 5-hour limit. Each press is a grant that lives
/// 5 hours, then the limit goes back to the norm on its own — a click is never a permanent change.
public struct BoostGrant: Codable, Sendable, Equatable {
    public var provider: Provider
    public var amount: Double
    public var at: Date

    public init(provider: Provider, amount: Double, at: Date) {
        self.provider = provider
        self.amount = amount
        self.at = at
    }
}

public enum Boosts {
    public static let lifetime: TimeInterval = 5 * 3600

    static func url(_ paths: Paths) -> URL { paths.support.appendingPathComponent("boosts.json") }

    public static func all(paths: Paths) -> [BoostGrant] {
        JSONFile.load([BoostGrant].self, from: url(paths)) ?? []
    }

    public static func active(_ p: Provider, paths: Paths, now: Date) -> [BoostGrant] {
        all(paths: paths).filter { $0.provider == p && now.timeIntervalSince($0.at) < lifetime }
    }

    public static func total(_ p: Provider, paths: Paths, now: Date) -> Double {
        active(p, paths: paths, now: now).reduce(0) { $0 + $1.amount }
    }

    /// When the last active grant runs out.
    public static func until(_ p: Provider, paths: Paths, now: Date) -> Date? {
        active(p, paths: paths, now: now).map { $0.at.addingTimeInterval(lifetime) }.max()
    }

    public static func add(_ p: Provider, amount: Double, paths: Paths, now: Date) {
        guard amount > 0 else { return }
        var list = all(paths: paths).filter { now.timeIntervalSince($0.at) < lifetime }
        list.append(BoostGrant(provider: p, amount: amount, at: now))
        try? JSONFile.save(list, to: url(paths))
    }

    /// "−": takes back the most recent grant.
    public static func removeLast(_ p: Provider, paths: Paths, now: Date) {
        var list = all(paths: paths).filter { now.timeIntervalSince($0.at) < lifetime }
        if let i = list.lastIndex(where: { $0.provider == p }) { list.remove(at: i) }
        try? JSONFile.save(list, to: url(paths))
    }
}

/// The reserve's checkbox: when on, the 5-hour limit takes from the reserve on its own, as much as it holds —
/// no "+" presses, no 5-hour expiry. Per provider; stays on until unchecked.
public enum AutoReserve {
    static func url(_ paths: Paths) -> URL { paths.support.appendingPathComponent("auto-reserve.json") }

    public static func isOn(_ p: Provider, paths: Paths) -> Bool {
        (JSONFile.load([Provider].self, from: url(paths)) ?? []).contains(p)
    }

    public static func set(_ p: Provider, _ on: Bool, paths: Paths) {
        var list = Set(JSONFile.load([Provider].self, from: url(paths)) ?? [])
        if on { list.insert(p) } else { list.remove(p) }
        try? JSONFile.save(list.sorted { $0.rawValue < $1.rawValue }, to: url(paths))
    }
}
