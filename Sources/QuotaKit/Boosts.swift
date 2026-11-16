import BudgetCore
import Foundation

/// "+" on the 5-hour bar: savings you chose to add to the current 5-hour slot. A grant counts only in the slot
/// it was pressed in; the next slot starts from the norm again — a click is never a permanent change.
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
    /// No slot is longer: older grants are dropped from the file.
    public static let lifetime: TimeInterval = Snapshot.slotLength

    static func url(_ paths: Paths) -> URL { paths.support.appendingPathComponent("boosts.json") }

    public static func all(paths: Paths) -> [BoostGrant] {
        JSONFile.load([BoostGrant].self, from: url(paths)) ?? []
    }

    /// Grants pressed in the slot that started at `since`.
    public static func active(_ p: Provider, paths: Paths, since: Date) -> [BoostGrant] {
        all(paths: paths).filter { $0.provider == p && $0.at >= since }
    }

    public static func total(_ p: Provider, paths: Paths, since: Date) -> Double {
        active(p, paths: paths, since: since).reduce(0) { $0 + $1.amount }
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
/// no "+" presses, in every slot. Per provider; stays on until unchecked.
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
