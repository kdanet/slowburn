import BudgetCore
import Foundation

/// What a blob feels, in order of how loudly it should speak.
public enum Mood: String, Codable, Sendable, CaseIterable {
    case calm, charged, worried, money, sleepy, unknown

    public var name: String {
        switch self {
        case .calm: "спокоен"
        case .charged: "заряжен"
        case .worried: "переживает"
        case .money: "платит"
        case .sleepy: "спит"
        case .unknown: "не видит"
        }
    }

    /// Higher speaks first in the headline and owns the menu bar icon.
    var severity: Int {
        switch self {
        case .money: 5
        case .sleepy: 4
        case .worried: 3
        case .unknown: 2
        case .charged: 1
        case .calm: 0
        }
    }

    public var isAlert: Bool { self == .money || self == .sleepy || self == .worried }
}

public struct BlobModel: Sendable, Identifiable {
    public var id: Provider { provider }
    public var provider: Provider
    public var mood: Mood
    /// Earned and unspent budget, in hours of plan time. nil = unknown.
    public var hours: Double?
    /// 0...1: how full the blob is drawn.
    public var level: Double
    public var hoursText: String
    public var subtitle: String
    /// One sentence for the headline.
    public var phrase: String

    /// The phrase without the provider's name, for a row that already shows it: "Бодр — ещё ~6 ч".
    public var status: String {
        var s = phrase
        let name = Phrases.providerName(provider)
        for prefix in [name + ": ", name + " "] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        if s.hasSuffix(".") { s.removeLast() }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

public struct LimitRow: Sendable, Identifiable {
    public enum Tone: Sendable { case ok, warn, red, stale }
    public var id: String
    public var provider: Provider
    public var title: String
    public var resetText: String
    public var used: Double
    /// Where usage would be if spending exactly on plan (long windows only).
    public var planMarker: Double?
    public var tone: Tone

    // The three layers of one limit, all in percentage points of this pool.
    /// "неделя", "Fable", "5 часов".
    public var windowName: String = ""
    public var resetsAt: Date = .distantFuture
    /// Smart limit: earned and unspent now (A). Negative = ahead of plan. nil for short windows.
    public var available: Double?
    /// Part of `available` that is the normal 5-hour allowance; the rest is the battery.
    public var normal: Double?
    public var battery: Double?
    /// Technical reserve the plan never hands out (kept for lag and rounding).
    public var margin: Double?
    /// Plan's earning rate, to turn points into hours.
    public var ratePerHour: Double?
    /// Today, will-it-last and hours of work (long windows).
    public var smart: SmartStats?
    /// Our rolling 5-hour norm (the plan's 5 hours of earning) and what the last 5 hours actually took.
    public var fiveHourBudget: Double?
    public var spentLast5h: Double?
    /// The norm plus what you added from savings with "+".
    public var fiveHourCap: Double?
    public var fiveHourBoost: Double?
    public var boostUntil: Date?
    /// Rolling 5 hours, with no more spending: back within the limit / fully rolled off.
    public var fiveHourFreesAt: Date? = nil
    public var fiveHourClearsAt: Date? = nil
    /// The reserve backs the 5-hour limit automatically (its checkbox is on).
    public var fiveHourAuto: Bool = false

    /// The provider's own ceiling: what is left before it blocks.
    public var providerLeft: Double { max(0, 100 - used) }
    public var availableHours: Double? { hours(available.map { max(0, $0) }) }
    public var batteryHours: Double? { hours(battery) }

    private func hours(_ points: Double?) -> Double? {
        guard let points, let r = ratePerHour, r > 0 else { return nil }
        return points / r
    }
}

public struct Presentation: Sendable {
    public var headline: String
    public var headlineTail: String?
    public var blobs: [BlobModel]
    public var limits: [LimitRow]
    public var moneyNote: String?
    public var resetNote: String?
    public var freshText: String
    public var menuProvider: Provider
    public var menuMood: Mood
    public var menuLevel: Double
    public var menuLabel: String
    public var overrideUntil: Date?

    public func blob(_ p: Provider) -> BlobModel? { blobs.first { $0.provider == p } }
}

extension Presentation {
    public static func make(_ state: AppState, now: Date, fullHours: Double = 8) -> Presentation {
        let blobs = Provider.allCases.map { blob(for: $0, state: state, now: now, fullHours: fullHours) }
        let ranked = blobs.sorted { ($0.mood.severity, $0.provider == .claude ? 1 : 0) > ($1.mood.severity, $1.provider == .claude ? 1 : 0) }
        let top = ranked[0]

        var moneyNote: String?
        if let c = state.codexCredits, c.spentLastHour > 0 {
            moneyNote = "Codex работает за credits: −\(Phrases.points(c.spentLastHour)) за последний час"
        }
        // Free resets matter exactly when Codex is stuck at a limit or paying for being past it.
        var resetNote: String?
        if let n = state.codexFreeResets, n > 0, moneyNote != nil || blobs.contains(where: { $0.provider == .codex && $0.hours == 0 }) {
            resetNote = "У тебя \(Phrases.freeResets(n)) лимитов Codex — можно обнулить окно бесплатно, вместо оплаты credits"
        }

        let newest = state.pools.map(\.snapshot.observedAt).max()
        let freshText = newest.map { Phrases.ago(now.timeIntervalSince($0)) } ?? "нет данных"

        let limits = limitRows(state, now: now)
        // Quiet by default: the blob's face says "fine"; text appears only when something needs you.
        let menuLabel: String = switch top.mood {
        case .money: "$"
        case .sleepy: "zz"
        case .unknown: "?"
        default: ""
        }

        return Presentation(
            headline: top.phrase,
            headlineTail: ranked.count > 1 ? ranked[1].phrase : nil,
            blobs: blobs,
            limits: limits,
            moneyNote: moneyNote,
            resetNote: resetNote,
            freshText: freshText,
            menuProvider: top.provider, menuMood: top.mood, menuLevel: top.level, menuLabel: menuLabel,
            overrideUntil: state.overrideUntil
        )
    }

    static func blob(for p: Provider, state: AppState, now: Date, fullHours: Double) -> BlobModel {
        let name = Phrases.providerName(p)
        let fresh = state.pools(of: p).filter { $0.freshness == .fresh && $0.level != .unknown }
        guard !fresh.isEmpty else {
            return BlobModel(provider: p, mood: .unknown, hours: nil, level: 0, hoursText: "—",
                             subtitle: "нет данных", phrase: "\(name): нет свежих цифр.")
        }

        // Charge = the tightest long pool's earned balance, in hours of its plan; a full short window empties it.
        var hours = fresh.compactMap { s -> Double? in
            guard let a = s.available, let plan = s.plan, plan.ratePerHour > 0 else { return nil }
            return max(0, a) / plan.ratePerHour
        }.min()
        let fullShort = fresh.filter { $0.reasons.contains("limit_reached") }
        if !fullShort.isEmpty { hours = 0 }

        let level = hours.map { min(1, max(0, $0 / fullHours)) } ?? 0.5
        let hoursText = hours.map(Phrases.hours) ?? "—"
        let worst = fresh.map(\.level).max() ?? .unknown

        // When it gets better: a full window resets, an overspent plan earns back half a point.
        let backAt: Date? = fresh.filter { $0.level == .red }.compactMap { s -> Date? in
            if s.reasons.contains("limit_reached") { return s.snapshot.resetsAt }
            guard let a = s.available, let plan = s.plan else { return nil }
            return now.addingTimeInterval((-a + 0.5) / max(plan.ratePerHour, 0.0001) * 3600)
        }.max()

        let paying = p == .codex && !fullShort.isEmpty && (state.codexCredits?.spentLastHour ?? 0) > 0
        if paying {
            let t = backAt.map(Phrases.time) ?? "сброса"
            return BlobModel(provider: p, mood: .money, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                             subtitle: "окно до \(t)", phrase: "\(name) спит до \(t) и платит credits.")
        }
        if worst == .red {
            let t = backAt.map(Phrases.time) ?? "сброса"
            return BlobModel(provider: p, mood: .sleepy, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                             subtitle: "заряд к \(t)", phrase: "\(name) отдыхает до \(t).")
        }
        if worst == .yellow {
            let eta = fresh.filter { $0.snapshot.isLongWindow }.compactMap(\.exhaustsAt).min()
            let phrase = eta.map { "\(name) в таком темпе кончится к \(Phrases.time($0))." }
                ?? "\(name) тратит запас — осталось ~\(hoursText)."
            return BlobModel(provider: p, mood: .worried, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                             subtitle: eta == nil ? "идёт запас" : "к сбросу не хватит", phrase: phrase)
        }
        if let h = hours, h >= fullHours {
            return BlobModel(provider: p, mood: .charged, hours: h, level: level, hoursText: hoursText,
                             subtitle: "\(Phrases.hours(min(h, 5))) обычных + \(Phrases.hours(max(0, h - 5))) запаса",
                             phrase: "\(name) накопил на ~\(hoursText).")
        }
        return BlobModel(provider: p, mood: .calm, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                         subtitle: "по плану", phrase: "\(name) бодр — ещё ~\(hoursText).")
    }

    static func limitRows(_ state: AppState, now: Date) -> [LimitRow] {
        state.pools
            .sorted { ($0.snapshot.pool.provider == .claude ? 0 : 1, $0.snapshot.windowMinutes, $0.snapshot.pool.id)
                    < ($1.snapshot.pool.provider == .claude ? 0 : 1, $1.snapshot.windowMinutes, $1.snapshot.pool.id) }
            .map { p in
                let s = p.snapshot
                var title = s.title.replacingOccurrences(of: "Неделя · ", with: "")
                if title == "Неделя" { title = "неделя" }
                let marker = p.plan.map { min(100, $0.u0 + $0.earned(at: now)) }
                let tone: LimitRow.Tone
                if p.level == .unknown || p.freshness != .fresh {
                    tone = .stale
                } else if s.usedPercent >= 100 {
                    tone = .red
                } else if let marker, s.usedPercent > marker + 5 {
                    tone = .warn
                } else {
                    tone = .ok
                }
                let reset = p.level == .unknown ? "окно сменилось" : "сброс через " + Phrases.countdown(s.resetsAt.timeIntervalSince(now))
                return LimitRow(id: s.pool.storageKey, provider: s.pool.provider,
                                title: "\(Phrases.providerName(s.pool.provider)) · \(title)", resetText: reset,
                                used: s.usedPercent, planMarker: marker, tone: tone,
                                windowName: title, resetsAt: s.resetsAt,
                                available: p.available, normal: p.normal, battery: p.battery,
                                margin: p.plan?.margin, ratePerHour: p.plan?.ratePerHour, smart: p.smart,
                                fiveHourBudget: p.fiveHourBudget, spentLast5h: p.spentLast5h, fiveHourCap: p.fiveHourCap,
                                fiveHourBoost: p.fiveHourBoost, boostUntil: p.boostUntil,
                                fiveHourFreesAt: p.fiveHourFreesAt, fiveHourClearsAt: p.fiveHourClearsAt,
                                fiveHourAuto: p.fiveHourAuto ?? false)
            }
    }
}

extension Phrases {
    public static func hours(_ h: Double) -> String {
        if h >= 1 { return "\(Int(h.rounded())) ч" }
        return h > 0 ? "<1 ч" : "0"
    }

    /// "3 д 20 ч", "1 ч 10 мин", "12 мин".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        let d = m / 1440, h = (m % 1440) / 60, mm = m % 60
        if d > 0 { return h == 0 ? "\(d) д" : "\(d) д \(h) ч" }
        if h > 0 { return mm == 0 ? "\(h) ч" : "\(h) ч \(mm) мин" }
        return "\(mm) мин"
    }

    /// "1 бесплатный сброс", "3 бесплатных сброса", "5 бесплатных сбросов".
    public static func freeResets(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n) бесплатный сброс" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) бесплатных сброса" }
        return "\(n) бесплатных сбросов"
    }

    public static func ago(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s) с назад" }
        if s < 3600 { return "\(s / 60) мин назад" }
        return "\(s / 3600) ч назад"
    }
}
