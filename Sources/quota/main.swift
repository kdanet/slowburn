import BudgetCore
import Foundation
import QuotaKit

let usage = """
quota — темп подписок Claude и Codex

  quota status [--json] [--cached]   свежие цифры (или последние сохранённые)
  quota refresh                      обновить state.json один раз
  quota allow [минуты]               снять мягкий тормоз (по умолчанию 30 мин)
  quota allow --clear                вернуть тормоз
  quota replan                       перестроить план от текущего остатка
  quota hook <claude|codex> [event]  для хуков: читает stdin, отвечает JSON
  quota integrate [claude] [codex]   поставить тормоз в хуки (по умолчанию Claude)
  quota uninstall-hooks              убрать всё своё из хуков Claude и Codex
  quota holds                        кто сейчас ждёт решения тормоза
  quota release [id…] [--deny]       отпустить ожидающих (все или по id) или остановить их
  quota statusline                   для statusLine Claude Code: читает stdin, печатает строку
"""

let args = Array(CommandLine.arguments.dropFirst())
let monitor = Monitor()
let now = Date()

func readStdin() -> Data { FileHandle.standardInput.readDataToEndOfFile() }

func printJSON(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

func render(_ state: AppState) -> String {
    var out: [String] = []
    for provider in Provider.allCases {
        let summary = state.summary(of: provider)
        let mark = switch summary?.level ?? .unknown {
        case .green: "🟢"
        case .yellow: "🟡"
        case .red: "🔴"
        case .unknown: "⚪️"
        }
        var header = "\(mark) \(Phrases.providerName(provider))"
        if let err = summary?.error { header += "  (источник: \(err))" }
        out.append(header)
        let pools = state.pools(of: provider)
        if pools.isEmpty { out.append("   нет данных") }
        for p in pools {
            let s = p.snapshot
            let age = Phrases.duration(state.generatedAt.timeIntervalSince(s.observedAt))
            var line = "   \(s.title): \(Phrases.points(s.usedPercent))% · сброс \(Phrases.time(s.resetsAt)) · подтверждено \(age) назад"
            if p.level == .unknown { line += " · окно сменилось, ждём данных" }
            out.append(line)
            if let a = p.available, let b5 = p.fiveHourBudget, let plan = p.plan {
                out.append("     план: \(Phrases.points(plan.ratePerHour * 24)) п./сутки, 5ч-норма \(Phrases.points(b5)) п.")
                out.append("     запас \(Phrases.points(a)) п. = обычный \(Phrases.points(p.normal ?? 0)) + батарейка \(Phrases.points(p.battery ?? 0)) (~\(Phrases.duration((p.batteryHours ?? 0) * 3600)))")
                out.append("     за 5 часов: \(Phrases.points(p.spentLast5h ?? 0)) п.")
            }
            if let burn = p.burnPerHour {
                var f = "     темп \(Phrases.points(burn)) п./ч"
                if let eta = p.exhaustsAt { f += " → 100% к \(Phrases.time(eta))" }
                else if let proj = p.projectedAtReset { f += " → к сбросу ~\(Phrases.points(min(proj, 100)))%" }
                out.append(f)
            }
            if p.level >= .yellow { out.append("     ⚠︎ \(Phrases.reason(p, now: state.generatedAt))") }
        }
    }
    if let c = state.codexCredits {
        var line = "Codex credits: \(String(format: "%.1f", c.balance)) · за час −\(String(format: "%.1f", c.spentLastHour)) · за сутки −\(String(format: "%.1f", c.spent24h))"
        if c.spentLastHour > 0 { line = "💸 " + line }
        out.append(line)
    }
    if !state.claudeTokens24h.isEmpty {
        out.append("Claude, токены за 24 ч:")
        for (model, c) in state.claudeTokens24h.sorted(by: { $0.value.total > $1.value.total }) {
            out.append("   \(model): \(c.messages) отв. · вход \(c.input) · кеш чт. \(c.cacheRead) · кеш зап. \(c.cacheWrite) · выход \(c.output)")
        }
    }
    if let until = state.overrideUntil { out.append("Тормоз снят до \(Phrases.time(until))") }
    return out.joined(separator: "\n")
}

func run() async -> Int32 {
    switch args.first {
    case "status":
        let state = args.contains("--cached") ? monitor.readState() : await monitor.refresh(now: now)
        guard let state else { print("Нет сохранённого состояния. Запусти quota refresh."); return 1 }
        if args.contains("--json") {
            let data = try! JSONFile.encoder.encode(state)
            FileHandle.standardOutput.write(data)
            print()
        } else {
            print(render(state))
            let busy = AgentActivity.scan(paths: monitor.paths, now: now)
            let words = Provider.allCases.map { p in
                guard let b = busy[p] else { return "\(Phrases.providerName(p)) отдыхает" }
                return "\(Phrases.providerName(p)) работает: \(b.work.rawValue)" + (b.sessions > 1 ? " (сессий: \(b.sessions))" : "")
            }
            print("Агенты: " + words.joined(separator: " · "))
        }
    case "refresh":
        let state = await monitor.refresh(now: now)
        print("ok: \(state.pools.count) окон")
    case "allow":
        if args.contains("--clear") {
            monitor.clearOverride()
            print("Тормоз снова включён")
        } else {
            let minutes = args.dropFirst().first.flatMap(Double.init) ?? 30
            try? monitor.allow(minutes: minutes, now: now)
            await monitor.refresh(now: now)
            print("Тормоз снят на \(Phrases.duration(minutes * 60))")
        }
    case "replan":
        try? monitor.replan()
        let state = await monitor.refresh(now: now)
        print(render(state))
    case "hook":
        // Must stay fast and never fail the host: no network, one small file read, always exit 0.
        guard args.count >= 2, let provider = Provider(rawValue: args[1]) else { return 0 }
        let event = args.count >= 3 ? args[2] : "UserPromptSubmit"
        let payload = (try? JSONSerialization.jsonObject(with: readStdin())) as? [String: Any] ?? [:]
        Hook.run(provider: provider, event: event, payload: payload, monitor: monitor, now: now)
    case "integrate", "uninstall-hooks":
        return Integrate.run(args: args, paths: monitor.paths)
    case "holds":
        let pending = HoldQueue.pending(paths: monitor.paths)
        if pending.isEmpty { print("Никто не ждёт") }
        for r in pending {
            print("\(r.id.prefix(8))  \(Phrases.providerName(r.provider)) · \(r.project) · \(r.tool ?? "сообщение") · ждёт \(Phrases.duration(now.timeIntervalSince(r.createdAt)))")
        }
    case "release":
        let deny = args.contains("--deny")
        let d = HoldDecision(verdict: deny ? .deny : .allow, decidedAt: now)
        let ids = args.dropFirst().filter { !$0.hasPrefix("--") }
        let pending = HoldQueue.pending(paths: monitor.paths)
        let chosen = ids.isEmpty ? pending : pending.filter { r in ids.contains { r.id.hasPrefix($0) } }
        for r in chosen { HoldQueue.decide(r.id, d, paths: monitor.paths) }
        print("\(deny ? "Остановлено" : "Отпущено"): \(chosen.count)")
    case "statusline":
        let input = readStdin()
        if let obj = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
           let limits = obj["rate_limits"], let raw = try? JSONSerialization.data(withJSONObject: limits) {
            try? JSONFile.save(ClaudeSource.StatusLineDrop(receivedAt: now, rateLimits: raw), to: monitor.paths.statusLineInbox)
        }
        if let state = monitor.readState() { print("◔ " + Phrases.compact(state, provider: .claude)) }
    default:
        print(usage)
        return args.isEmpty || args.first == "help" || args.first == "--help" ? 0 : 2
    }
    return 0
}

exit(await run())
