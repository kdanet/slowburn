import BudgetCore
import Foundation

/// The soft brake. It acts only when a new prompt is submitted, never mid-turn,
/// and it always lets the user through: `++` at the start of a prompt or an override window.
public enum Brake {
    public static let bypassPrefix = "++"
    /// A state file older than this means the monitor is not running: let everything through.
    public static let maxStateAge: TimeInterval = 15 * 60

    public enum Decision: Equatable, Sendable {
        case allow
        case warn(String)
        case block(String)
    }

    public static func decide(state: AppState?, provider: Provider, prompt: String?, now: Date) -> Decision {
        guard let state, now.timeIntervalSince(state.generatedAt) <= maxStateAge else { return .allow }
        let pools = state.pools(of: provider).filter { $0.freshness == .fresh }
        guard let worst = pools.max(by: { $0.level < $1.level }), worst.level >= .yellow else { return .allow }

        // A full Codex window plus a falling credit balance means work is being paid for.
        if provider == .codex, worst.reasons.contains("limit_reached"), let c = state.codexCredits, c.spentLastHour > 0 {
            var note = String(format: L("Codex работает за credits: −%.1f за последний час, остаток %.1f.",
                                         "Codex is spending credits: −%.1f in the last hour, %.1f left."), c.spentLastHour, c.balance)
            if let n = state.codexFreeResets, n > 0 {
                note += L(" У тебя \(Phrases.freeResets(n)) лимитов — можно обнулить окно бесплатно.",
                          " You have \(Phrases.freeResets(n)) — you can reset the window for free.")
            }
            if worst.level == .red, state.overrideUntil.map({ $0 > now }) != true,
               prompt?.trimmingCharacters(in: .whitespaces).hasPrefix(bypassPrefix) != true {
                return .block(L("\(Phrases.reason(worst, now: now)) \(note) Чтобы продолжить за credits: начни сообщение с \(bypassPrefix) или приостанови ограничения в Slowburn на 30 мин.",
                                 "\(Phrases.reason(worst, now: now)) \(note) To continue on credits: start your message with \(bypassPrefix) or pause the limits in Slowburn for 30 min."))
            }
            return .warn(note)
        }

        if worst.level == .red {
            if let until = state.overrideUntil, until > now {
                return .warn(L("Тормоз снят до \(Phrases.time(until)). \(Phrases.reason(worst, now: now))",
                                "Brake off until \(Phrases.time(until)). \(Phrases.reason(worst, now: now))"))
            }
            if let prompt, prompt.trimmingCharacters(in: .whitespaces).hasPrefix(bypassPrefix) {
                return .warn(L("Обход тормоза (\(bypassPrefix)). \(Phrases.reason(worst, now: now))",
                                "Brake bypassed (\(bypassPrefix)). \(Phrases.reason(worst, now: now))"))
            }
            return .block(L("\(Phrases.reason(worst, now: now)) Чтобы всё равно отправить: начни сообщение с \(bypassPrefix) или приостанови ограничения в Slowburn на 30 мин.",
                             "\(Phrases.reason(worst, now: now)) To send anyway: start your message with \(bypassPrefix) or pause the limits in Slowburn for 30 min."))
        }
        return .warn(Phrases.reason(worst, now: now))
    }
}

/// UI strings in Russian or English, deterministic and free: no LLM calls.
public enum Phrases {
    public static func time(_ date: Date) -> String {
        // The endpoint's reset jitters around the hour (09:59:59.7): show the nearest minute.
        let date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let f = DateFormatter()
        f.locale = Lang.locale
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EE HH:mm"
        return f.string(from: date)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 60 { return L("\(minutes) мин", "\(minutes) min") }
        let h = minutes / 60, m = minutes % 60
        if h < 24 { return m == 0 ? L("\(h) ч", "\(h) h") : L("\(h) ч \(m) мин", "\(h) h \(m) min") }
        let d = h / 24, rh = h % 24
        return rh == 0 ? L("\(d) д", "\(d) d") : L("\(d) д \(rh) ч", "\(d) d \(rh) h")
    }

    public static func points(_ v: Double) -> String {
        let s = String(format: abs(v) < 10 ? "%.1f" : "%.0f", v)
        return Lang.isRussian ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    public static func providerName(_ p: Provider) -> String { p == .claude ? "Claude" : "Codex" }

    /// Why a pool is yellow/red, with the earliest moment things get better.
    public static func reason(_ s: PoolStatus, now: Date) -> String {
        let name = "\(providerName(s.snapshot.pool.provider)) · \(windowTitle(s.snapshot.title))"
        if s.reasons.contains("limit_reached") {
            return L("\(name): лимит исчерпан, сброс в \(time(s.snapshot.resetsAt)).",
                     "\(name): limit reached, resets at \(time(s.snapshot.resetsAt)).")
        }
        if s.reasons.contains("earned_exhausted"), let available = s.available {
            // Back once a later slot's norm covers the debt (half a point to spare).
            let back = s.planBackAt ?? s.snapshot.resetsAt
            return L("\(name): ты впереди плана на \(points(-available)) п. Запас появится к \(time(back)).",
                     "\(name): you're \(points(-available)) pts ahead of plan. Headroom returns by \(time(back)).")
        }
        if s.reasons.contains("battery_discharge_cap") {
            return L("\(name): в этих 5 часах потрачено \(points(s.spentThisSlot ?? 0)) п. — больше нормы с добавкой. Батарейка: \(points(s.battery ?? 0)) п.",
                     "\(name): \(points(s.spentThisSlot ?? 0)) pts spent in these 5 hours — over the norm with its top-up. Battery: \(points(s.battery ?? 0)) pts.")
        }
        if s.reasons.contains("using_battery") {
            return L("\(name): тратишь накопленное, в батарейке \(points(s.battery ?? 0)) п. (~\(duration((s.batteryHours ?? 0) * 3600)) обычного темпа).",
                     "\(name): spending your savings, \(points(s.battery ?? 0)) pts left in the battery (~\(duration((s.batteryHours ?? 0) * 3600)) at the usual pace).")
        }
        if s.reasons.contains("burn_exhausts_before_reset"), let eta = s.exhaustsAt {
            return L("\(name): при текущем темпе лимит кончится к \(time(eta)), а сброс только в \(time(s.snapshot.resetsAt)).",
                     "\(name): at this pace the limit runs out by \(time(eta)), but it only resets at \(time(s.snapshot.resetsAt)).")
        }
        return L("\(name): \(points(s.snapshot.usedPercent))% использовано.", "\(name): \(points(s.snapshot.usedPercent))% used.")
    }

    /// One line for the menu bar / status line.
    public static func compact(_ state: AppState, provider: Provider) -> String {
        let pools = state.pools(of: provider).filter { $0.level != .unknown }
        guard let main = pools.first(where: { $0.snapshot.isLongWindow }) ?? pools.first else {
            return L("\(providerName(provider)): нет данных", "\(providerName(provider)): no data")
        }
        var line = "\(providerName(provider)) \(points(main.snapshot.usedPercent))%"
        if let a = main.available { line += a >= 0 ? L(" · запас \(points(a))", " · headroom \(points(a))") : L(" · перерасход \(points(-a))", " · overspent \(points(-a))") }
        return line
    }
}
