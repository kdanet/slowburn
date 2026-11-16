import BudgetCore
import Foundation
import QuotaKit

let usage = L("""
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
""", """
quota — pacing for Claude and Codex subscriptions

  quota status [--json] [--cached]   fresh numbers (or the last saved ones)
  quota refresh                      update state.json once
  quota allow [minutes]              lift the soft brake (30 min by default)
  quota allow --clear                bring the brake back
  quota replan                       rebuild the plan from what is left
  quota hook <claude|codex> [event]  for hooks: reads stdin, answers JSON
  quota integrate [claude] [codex]   put the brake into hooks (Claude by default)
  quota uninstall-hooks              remove everything of ours from Claude and Codex hooks
  quota holds                        who is waiting for a brake decision right now
  quota release [id…] [--deny]       let waiting agents go (all or by id), or stop them
  quota statusline                   for Claude Code's statusLine: reads stdin, prints a line
""")

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
        if let err = summary?.error { header += L("  (источник: \(err))", "  (source: \(err))") }
        out.append(header)
        let pools = state.pools(of: provider)
        if pools.isEmpty { out.append(L("   нет данных", "   no data")) }
        for p in pools {
            let s = p.snapshot
            let age = Phrases.duration(state.generatedAt.timeIntervalSince(s.observedAt))
            var line = L("   \(Phrases.windowTitle(s.title)): \(Phrases.points(s.usedPercent))% · сброс \(Phrases.time(s.resetsAt)) · подтверждено \(age) назад",
                         "   \(Phrases.windowTitle(s.title)): \(Phrases.points(s.usedPercent))% · resets \(Phrases.time(s.resetsAt)) · confirmed \(age) ago")
            if p.level == .unknown { line += L(" · окно сменилось, ждём данных", " · window changed, waiting for data") }
            out.append(line)
            if let a = p.available, let b5 = p.fiveHourBudget, let plan = p.plan {
                out.append(L("     план: \(Phrases.points(plan.ratePerHour * 24)) п./сутки, 5ч-норма \(Phrases.points(b5)) п.",
                             "     plan: \(Phrases.points(plan.ratePerHour * 24)) pts/day, 5h norm \(Phrases.points(b5)) pts"))
                out.append(L("     запас \(Phrases.points(a)) п. = обычный \(Phrases.points(p.normal ?? 0)) + батарейка \(Phrases.points(p.battery ?? 0)) (~\(Phrases.duration((p.batteryHours ?? 0) * 3600)))",
                             "     headroom \(Phrases.points(a)) pts = regular \(Phrases.points(p.normal ?? 0)) + battery \(Phrases.points(p.battery ?? 0)) (~\(Phrases.duration((p.batteryHours ?? 0) * 3600)))"))
                let slotEnd = p.fiveHourResetsAt.map { L(", новые с \(Phrases.time($0))", ", next from \(Phrases.time($0))") } ?? ""
                out.append(L("     в этих 5 часах: \(Phrases.points(p.spentThisSlot ?? 0)) из \(Phrases.points(b5)) п.\(slotEnd)",
                             "     these 5 hours: \(Phrases.points(p.spentThisSlot ?? 0)) of \(Phrases.points(b5)) pts\(slotEnd)"))
            }
            if let burn = p.burnPerHour {
                var f = L("     темп \(Phrases.points(burn)) п./ч", "     pace \(Phrases.points(burn)) pts/h")
                if let eta = p.exhaustsAt { f += L(" → 100% к \(Phrases.time(eta))", " → 100% by \(Phrases.time(eta))") }
                else if let proj = p.projectedAtReset { f += L(" → к сбросу ~\(Phrases.points(min(proj, 100)))%", " → ~\(Phrases.points(min(proj, 100)))% at reset") }
                out.append(f)
            }
            if p.level >= .yellow { out.append("     ⚠︎ \(Phrases.reason(p, now: state.generatedAt))") }
        }
    }
    if let c = state.codexCredits {
        var line = L("Codex credits: \(String(format: "%.1f", c.balance)) · за час −\(String(format: "%.1f", c.spentLastHour)) · за сутки −\(String(format: "%.1f", c.spent24h))",
                     "Codex credits: \(String(format: "%.1f", c.balance)) · last hour −\(String(format: "%.1f", c.spentLastHour)) · last day −\(String(format: "%.1f", c.spent24h))")
        if c.spentLastHour > 0 { line = "💸 " + line }
        out.append(line)
    }
    if !state.claudeTokens24h.isEmpty {
        out.append(L("Claude, токены за 24 ч:", "Claude, tokens in 24 h:"))
        for (model, c) in state.claudeTokens24h.sorted(by: { $0.value.total > $1.value.total }) {
            out.append(L("   \(model): \(c.messages) отв. · вход \(c.input) · кеш чт. \(c.cacheRead) · кеш зап. \(c.cacheWrite) · выход \(c.output)",
                         "   \(model): \(c.messages) replies · in \(c.input) · cache read \(c.cacheRead) · cache write \(c.cacheWrite) · out \(c.output)"))
        }
    }
    if let until = state.overrideUntil { out.append(L("Тормоз снят до \(Phrases.time(until))", "Brake off until \(Phrases.time(until))")) }
    return out.joined(separator: "\n")
}

func run() async -> Int32 {
    switch args.first {
    case "status":
        let state = args.contains("--cached") ? monitor.readState() : await monitor.refresh(now: now)
        guard let state else { print(L("Нет сохранённого состояния. Запусти quota refresh.", "No saved state. Run quota refresh.")); return 1 }
        if args.contains("--json") {
            let data = try! JSONFile.encoder.encode(state)
            FileHandle.standardOutput.write(data)
            print()
        } else {
            print(render(state))
            let busy = AgentActivity.scan(paths: monitor.paths, now: now)
            let words = Provider.allCases.map { p in
                guard let b = busy[p] else { return L("\(Phrases.providerName(p)) отдыхает", "\(Phrases.providerName(p)) is resting") }
                return L("\(Phrases.providerName(p)) работает: \(b.work.rawValue)", "\(Phrases.providerName(p)) working: \(b.work.rawValue)")
                    + (b.sessions > 1 ? L(" (сессий: \(b.sessions))", " (sessions: \(b.sessions))") : "")
            }
            print(L("Агенты: ", "Agents: ") + words.joined(separator: " · "))
        }
    case "refresh":
        let state = await monitor.refresh(now: now)
        print(L("ok: \(state.pools.count) окон", "ok: \(state.pools.count) windows"))
    case "allow":
        if args.contains("--clear") {
            monitor.clearOverride()
            print(L("Тормоз снова включён", "Brake back on"))
        } else {
            let minutes = args.dropFirst().first.flatMap(Double.init) ?? 30
            try? monitor.allow(minutes: minutes, now: now)
            await monitor.refresh(now: now)
            print(L("Тормоз снят на \(Phrases.duration(minutes * 60))", "Brake off for \(Phrases.duration(minutes * 60))"))
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
        if pending.isEmpty { print(L("Никто не ждёт", "Nobody is waiting")) }
        for r in pending {
            print(L("\(r.id.prefix(8))  \(Phrases.providerName(r.provider)) · \(r.project) · \(r.tool ?? "сообщение") · ждёт \(Phrases.duration(now.timeIntervalSince(r.createdAt)))",
                    "\(r.id.prefix(8))  \(Phrases.providerName(r.provider)) · \(r.project) · \(r.tool ?? "message") · waiting \(Phrases.duration(now.timeIntervalSince(r.createdAt)))"))
        }
    case "release":
        let deny = args.contains("--deny")
        let d = HoldDecision(verdict: deny ? .deny : .allow, decidedAt: now)
        let ids = args.dropFirst().filter { !$0.hasPrefix("--") }
        let pending = HoldQueue.pending(paths: monitor.paths)
        let chosen = ids.isEmpty ? pending : pending.filter { r in ids.contains { r.id.hasPrefix($0) } }
        for r in chosen { HoldQueue.decide(r.id, d, paths: monitor.paths) }
        print(L("\(deny ? "Остановлено" : "Отпущено"): \(chosen.count)", "\(deny ? "Stopped" : "Released"): \(chosen.count)"))
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
