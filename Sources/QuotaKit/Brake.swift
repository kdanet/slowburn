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
            var note = String(format: "Codex работает за credits: −%.1f за последний час, остаток %.1f.", c.spentLastHour, c.balance)
            if let n = state.codexFreeResets, n > 0 {
                note += " У тебя \(Phrases.freeResets(n)) лимитов — можно обнулить окно бесплатно."
            }
            if worst.level == .red, state.overrideUntil.map({ $0 > now }) != true,
               prompt?.trimmingCharacters(in: .whitespaces).hasPrefix(bypassPrefix) != true {
                return .block("\(Phrases.reason(worst, now: now)) \(note) Чтобы продолжить за credits: начни сообщение с \(bypassPrefix) или нажми «Разрешить 30 мин».")
            }
            return .warn(note)
        }

        if worst.level == .red {
            if let until = state.overrideUntil, until > now {
                return .warn("Тормоз снят до \(Phrases.time(until)). \(Phrases.reason(worst, now: now))")
            }
            if let prompt, prompt.trimmingCharacters(in: .whitespaces).hasPrefix(bypassPrefix) {
                return .warn("Обход тормоза (\(bypassPrefix)). \(Phrases.reason(worst, now: now))")
            }
            return .block("\(Phrases.reason(worst, now: now)) Чтобы всё равно отправить: начни сообщение с \(bypassPrefix) или нажми «Разрешить 30 мин» в меню Slowburn.")
        }
        return .warn(Phrases.reason(worst, now: now))
    }
}

/// Russian UI strings, deterministic and free: no LLM calls.
public enum Phrases {
    public static func time(_ date: Date) -> String {
        // The endpoint's reset jitters around the hour (09:59:59.7): show the nearest minute.
        let date = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EE HH:mm"
        return f.string(from: date)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 60 { return "\(minutes) мин" }
        let h = minutes / 60, m = minutes % 60
        if h < 24 { return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин" }
        let d = h / 24, rh = h % 24
        return rh == 0 ? "\(d) д" : "\(d) д \(rh) ч"
    }

    public static func points(_ v: Double) -> String {
        String(format: abs(v) < 10 ? "%.1f" : "%.0f", v).replacingOccurrences(of: ".", with: ",")
    }

    public static func providerName(_ p: Provider) -> String { p == .claude ? "Claude" : "Codex" }

    /// Why a pool is yellow/red, with the earliest moment things get better.
    public static func reason(_ s: PoolStatus, now: Date) -> String {
        let name = "\(providerName(s.snapshot.pool.provider)) · \(s.snapshot.title)"
        if s.reasons.contains("limit_reached") {
            return "\(name): лимит исчерпан, сброс в \(time(s.snapshot.resetsAt))."
        }
        if s.reasons.contains("earned_exhausted"), let plan = s.plan, let available = s.available {
            // Back to a small positive balance (half a point) at the plan's fixed rate.
            let wait = (-available + 0.5) / max(plan.ratePerHour, 0.0001) * 3600
            return "\(name): ты впереди плана на \(points(-available)) п. Запас появится к \(time(now.addingTimeInterval(wait)))."
        }
        if s.reasons.contains("battery_discharge_cap") {
            return "\(name): за 5 часов потрачено \(points(s.spentLast5h ?? 0)) п. — больше двойной нормы. Батарейка: \(points(s.battery ?? 0)) п."
        }
        if s.reasons.contains("using_battery") {
            return "\(name): тратишь накопленное, в батарейке \(points(s.battery ?? 0)) п. (~\(duration((s.batteryHours ?? 0) * 3600)) обычного темпа)."
        }
        if s.reasons.contains("burn_exhausts_before_reset"), let eta = s.exhaustsAt {
            return "\(name): при текущем темпе лимит кончится к \(time(eta)), а сброс только в \(time(s.snapshot.resetsAt))."
        }
        return "\(name): \(points(s.snapshot.usedPercent))% использовано."
    }

    /// One line for the menu bar / status line.
    public static func compact(_ state: AppState, provider: Provider) -> String {
        let pools = state.pools(of: provider).filter { $0.level != .unknown }
        guard let main = pools.first(where: { $0.snapshot.isLongWindow }) ?? pools.first else {
            return "\(providerName(provider)): нет данных"
        }
        var line = "\(providerName(provider)) \(points(main.snapshot.usedPercent))%"
        if let a = main.available { line += a >= 0 ? " · запас \(points(a))" : " · перерасход \(points(-a))" }
        return line
    }
}
