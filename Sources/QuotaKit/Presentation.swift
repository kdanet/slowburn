import BudgetCore
import Foundation

/// What a blob feels, in order of how loudly it should speak.
public enum Mood: String, Codable, Sendable, CaseIterable {
    case calm, charged, worried, money, sleepy, unknown

    public var name: String {
        switch self {
        case .calm: L("спокоен", "calm")
        case .charged: L("заряжен", "charged")
        case .worried: L("переживает", "worried")
        case .money: L("платит", "paying")
        case .sleepy: L("спит", "sleeping")
        case .unknown: L("не видит", "can't see")
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
    /// Our 5-hour norm (the plan's earning over the current fixed slot) and what the slot has taken so far.
    public var fiveHourBudget: Double?
    public var spentThisSlot: Double?
    /// The norm plus what you added from savings with "+".
    public var fiveHourCap: Double?
    public var fiveHourBoost: Double?
    public var boostUntil: Date?
    /// Over the limit: when the next slot opens it again / when the current slot ends.
    public var fiveHourFreesAt: Date? = nil
    public var fiveHourResetsAt: Date? = nil
    /// The reserve backs the 5-hour limit automatically (its checkbox is on).
    public var fiveHourAuto: Bool = false

    /// The provider's own ceiling: what is left before it blocks.
    public var providerLeft: Double { max(0, 100 - used) }
    public var availableHours: Double? { hours(available.map { max(0, $0) }) }
    /// What one more "+" would add: one norm, or what is left of the reserve the slot started with.
    public var boostStep: Double {
        guard let norm = fiveHourBudget, norm > 0 else { return 0 }
        let reserve = max(battery ?? 0, 0) + max(0, (spentThisSlot ?? 0) - norm)
        return Pacer.boostStep(norm: norm, battery: reserve, boost: max(0, (fiveHourCap ?? norm) - norm))
    }
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
            moneyNote = L("Codex работает за credits: −\(Phrases.points(c.spentLastHour)) за последний час",
                          "Codex is spending credits: −\(Phrases.points(c.spentLastHour)) in the last hour")
        }
        // Free resets matter exactly when Codex is stuck at a limit or paying for being past it.
        var resetNote: String?
        if let n = state.codexFreeResets, n > 0, moneyNote != nil || blobs.contains(where: { $0.provider == .codex && $0.hours == 0 }) {
            resetNote = L("У тебя \(Phrases.freeResets(n)) лимитов Codex — можно обнулить окно бесплатно, вместо оплаты credits",
                          "You have \(Phrases.freeResets(n)) for Codex — reset the window for free instead of paying credits")
        }

        let newest = state.pools.map(\.snapshot.observedAt).max()
        let freshText = newest.map { Phrases.ago(now.timeIntervalSince($0)) } ?? L("нет данных", "no data")

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
                             subtitle: L("нет данных", "no data"), phrase: L("\(name): нет свежих цифр.", "\(name): no fresh numbers."))
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

        // When it gets better: a full window resets, an overspent plan gets a slot whose norm covers the debt.
        let backAt: Date? = fresh.filter { $0.level == .red }.compactMap { s -> Date? in
            if s.reasons.contains("limit_reached") { return s.snapshot.resetsAt }
            return s.planBackAt ?? s.snapshot.resetsAt
        }.max()

        let paying = p == .codex && !fullShort.isEmpty && (state.codexCredits?.spentLastHour ?? 0) > 0
        if paying {
            let t = backAt.map(Phrases.time) ?? L("сброса", "reset")
            return BlobModel(provider: p, mood: .money, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                             subtitle: L("окно до \(t)", "window until \(t)"),
                             phrase: L("\(name) спит до \(t) и платит credits.", "\(name) sleeps until \(t) and pays credits."))
        }
        if worst == .red {
            let t = backAt.map(Phrases.time) ?? L("сброса", "reset")
            return BlobModel(provider: p, mood: .sleepy, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                             subtitle: L("заряд к \(t)", "charged by \(t)"), phrase: L("\(name) отдыхает до \(t).", "\(name) is resting until \(t)."))
        }
        if worst == .yellow {
            let eta = fresh.filter { $0.snapshot.isLongWindow }.compactMap(\.exhaustsAt).min()
            let phrase = eta.map { L("\(name) в таком темпе кончится к \(Phrases.time($0)).", "\(name) runs out by \(Phrases.time($0)) at this pace.") }
                ?? L("\(name) тратит запас — осталось ~\(hoursText).", "\(name) is using its reserve — ~\(hoursText) left.")
            return BlobModel(provider: p, mood: .worried, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                             subtitle: eta == nil ? L("идёт запас", "using reserve") : L("к сбросу не хватит", "won't last to reset"), phrase: phrase)
        }
        if let h = hours, h >= fullHours {
            return BlobModel(provider: p, mood: .charged, hours: h, level: level, hoursText: hoursText,
                             subtitle: L("\(Phrases.hours(min(h, 5))) обычных + \(Phrases.hours(max(0, h - 5))) запаса",
                                         "\(Phrases.hours(min(h, 5))) regular + \(Phrases.hours(max(0, h - 5))) reserve"),
                             phrase: L("\(name) накопил на ~\(hoursText).", "\(name) has saved up ~\(hoursText)."))
        }
        return BlobModel(provider: p, mood: .calm, hours: hours, level: max(level, 0.04), hoursText: hoursText,
                         subtitle: L("по плану", "on plan"), phrase: L("\(name) бодр — ещё ~\(hoursText).", "\(name) is fresh — ~\(hoursText) to go."))
    }

    static func limitRows(_ state: AppState, now: Date) -> [LimitRow] {
        state.pools
            .sorted { ($0.snapshot.pool.provider == .claude ? 0 : 1, $0.snapshot.windowMinutes, $0.snapshot.pool.id)
                    < ($1.snapshot.pool.provider == .claude ? 0 : 1, $1.snapshot.windowMinutes, $1.snapshot.pool.id) }
            .map { p in
                let s = p.snapshot
                var title = Phrases.windowTitle(s.title).replacingOccurrences(of: L("Неделя · ", "Week · "), with: "")
                if title == L("Неделя", "Week") { title = L("неделя", "week") }
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
                let reset = p.level == .unknown ? L("окно сменилось", "window changed")
                    : L("сброс через ", "resets in ") + Phrases.countdown(s.resetsAt.timeIntervalSince(now))
                return LimitRow(id: s.pool.storageKey, provider: s.pool.provider,
                                title: "\(Phrases.providerName(s.pool.provider)) · \(title)", resetText: reset,
                                used: s.usedPercent, planMarker: marker, tone: tone,
                                windowName: title, resetsAt: s.resetsAt,
                                available: p.available, normal: p.normal, battery: p.battery,
                                margin: p.plan?.margin, ratePerHour: p.plan?.ratePerHour, smart: p.smart,
                                fiveHourBudget: p.fiveHourBudget, spentThisSlot: p.spentThisSlot, fiveHourCap: p.fiveHourCap,
                                fiveHourBoost: p.fiveHourBoost, boostUntil: p.boostUntil,
                                fiveHourFreesAt: p.fiveHourFreesAt, fiveHourResetsAt: p.fiveHourResetsAt,
                                fiveHourAuto: p.fiveHourAuto ?? false)
            }
    }
}

extension Phrases {
    public static func hours(_ h: Double) -> String {
        if h >= 1 { return L("\(Int(h.rounded())) ч", "\(Int(h.rounded())) h") }
        return h > 0 ? L("<1 ч", "<1 h") : "0"
    }

    /// "3 д 20 ч", "1 ч 10 мин", "12 мин".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let m = max(0, Int(seconds / 60))
        let d = m / 1440, h = (m % 1440) / 60, mm = m % 60
        if d > 0 { return h == 0 ? L("\(d) д", "\(d) d") : L("\(d) д \(h) ч", "\(d) d \(h) h") }
        if h > 0 { return mm == 0 ? L("\(h) ч", "\(h) h") : L("\(h) ч \(mm) мин", "\(h) h \(mm) min") }
        return L("\(mm) мин", "\(mm) min")
    }

    /// "1 бесплатный сброс", "3 бесплатных сброса", "5 бесплатных сбросов".
    public static func freeResets(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let en = n == 1 ? "1 free reset" : "\(n) free resets"
        if mod10 == 1 && mod100 != 11 { return L("\(n) бесплатный сброс", en) }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return L("\(n) бесплатных сброса", en) }
        return L("\(n) бесплатных сбросов", en)
    }

    /// A stored window title ("Неделя", "5 hours", "Неделя · Fable") in the interface language,
    /// so state written under the other language still reads right.
    public static func windowTitle(_ raw: String) -> String {
        for (ru, en) in [("Неделя", "Week"), ("5 часов", "5 hours"), ("Сутки", "Day")] {
            for word in [ru, en] where raw == word || raw.hasPrefix(word + " · ") {
                return L(ru, en) + raw.dropFirst(word.count)
            }
        }
        return raw
    }

    public static func ago(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return L("\(s) с назад", "\(s) s ago") }
        if s < 3600 { return L("\(s / 60) мин назад", "\(s / 60) min ago") }
        return L("\(s / 3600) ч назад", "\(s / 3600) h ago")
    }
}
