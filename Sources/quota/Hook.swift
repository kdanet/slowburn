import BudgetCore
import Foundation
import QuotaKit

/// `quota hook <claude|codex> <UserPromptSubmit|PreToolUse>` — the brake inside the host.
///
/// Never breaks the host: without a live Slowburn app, fresh data or a reason to hold it lets everything
/// through at once. When it holds, it waits for a decision made in the app; only the app (or its auto
/// release mode) lets an agent go, and a hold that runs too long ends in "stop", never in silent spending.
enum Hook {
    static var holdID: String?
    static var holdPaths: Paths?
    static var signalSources: [DispatchSourceSignal] = []

    static func run(provider: Provider, event: String, payload: [String: Any], monitor: Monitor, now: Date) {
        let paths = monitor.paths
        let session = payload["session_id"] as? String ?? ""
        let prompt = (payload["prompt"] as? String)?.trimmingCharacters(in: .whitespaces)
        let isPrompt = event == "UserPromptSubmit"
        guard isPrompt || event == "PreToolUse" else { return }
        // Everything switched off in the app: let it all through, say nothing.
        if MasterSwitch.isOff(paths: paths) { return }

        if isPrompt {
            // The person wrote to this session again: whatever we stopped is theirs to restart.
            HoldQueue.clearStopped(session, paths: paths)
            if prompt?.hasPrefix(HoldQueue.demoPrefix) == true { HoldQueue.registerDemo(session, paths: paths, now: now) }
        } else if HoldQueue.isStopped(session, paths: paths, now: now) {
            respond(.deny, message: stopInstruction(L("Сессия остановлена в Slowburn.", "Session stopped in Slowburn.")), isPrompt: false, session: session, paths: paths)
            return
        }

        guard let beat = HoldQueue.heartbeat(paths: paths), beat.isFresh(now: now) else { return } // no app, no holding
        let state = monitor.readState()
        let demo = !isPrompt && HoldQueue.isDemo(session, paths: paths, now: now)
            ? L("Демо тормоза: так выглядит пауза, когда кончается бюджет.", "Brake demo: this is what a pause looks like when the budget runs out.") : nil
        guard let reason = Brake.holdReason(state: state, provider: provider, now: now, tolerance: beat.settings.tolerance) ?? demo else {
            if isPrompt, case .warn(let m) = Brake.decide(state: state, provider: provider, prompt: prompt, now: now) {
                printJSON(["systemMessage": "◔ " + m])
            }
            return
        }
        if isPrompt, prompt?.hasPrefix(Brake.bypassPrefix) == true {
            printJSON(["systemMessage": L("◔ Обход тормоза (++). ", "◔ Brake bypassed (++). ") + reason])
            return
        }

        let request = HoldRequest(id: UUID().uuidString, provider: provider, event: event, sessionId: session,
                                  cwd: payload["cwd"] as? String, tool: payload["tool_name"] as? String,
                                  agentId: payload["agent_id"] as? String, reason: reason, createdAt: now, pid: getpid())
        guard (try? HoldQueue.enqueue(request, paths: paths)) != nil else { return }
        holdID = request.id
        holdPaths = paths
        cleanUpOnSignals()
        DistributedNotificationCenter.default().postNotificationName(HoldQueue.notification, object: nil,
                                                                    userInfo: nil, deliverImmediately: true)

        let (verdict, message) = wait(for: request, provider: provider, monitor: monitor)
        HoldQueue.clear(request.id, paths: paths)
        holdID = nil
        respond(verdict, message: message, isPrompt: isPrompt, session: session, paths: paths)
    }

    /// Polls for the app's decision. Auto release happens only in `whenBudgetReturns` mode.
    static func wait(for request: HoldRequest, provider: Provider, monitor: Monitor) -> (HoldVerdict, String?) {
        let paths = monitor.paths
        var lastStateCheck = Date.distantPast
        while true {
            Thread.sleep(forTimeInterval: 0.5)
            let now = Date()
            if let d = HoldQueue.decision(request.id, paths: paths) {
                return (d.verdict, d.message ?? (d.verdict == .deny ? stopInstruction(L("Остановлено в Slowburn.", "Stopped in Slowburn.")) : nil))
            }
            guard let beat = HoldQueue.heartbeat(paths: paths), now.timeIntervalSince(beat.at) <= 60 else {
                return (.deny, stopInstruction(L("Slowburn закрылся, решить про паузу некому.", "Slowburn has quit; nobody is left to decide on the pause.")))
            }
            if now.timeIntervalSince(request.createdAt) >= beat.settings.maxWait {
                let minutes = Int(beat.settings.maxWait / 60)
                return (.deny, stopInstruction(L("Пауза длилась \(minutes) мин без решения.", "The pause lasted \(minutes) min with no decision.")))
            }
            if beat.settings.releaseMode == .whenBudgetReturns, now.timeIntervalSince(lastStateCheck) >= 5 {
                lastStateCheck = now
                if Brake.holdReason(state: monitor.readState(), provider: provider, now: now,
                                    tolerance: beat.settings.tolerance) == nil {
                    return (.allow, nil)
                }
            }
        }
    }

    /// What the agent reads when it is stopped: finish cleanly, call nothing else.
    static func stopInstruction(_ why: String) -> String {
        L("Slowburn: бюджет на паузе. \(why) Не вызывай больше инструментов: коротко опиши, на чём остановился и что осталось сделать. Пользователь продолжит позже.",
          "Slowburn: the budget is paused. \(why) Do not call any more tools: briefly describe where you stopped and what is left to do. The user will continue later.")
    }

    static func respond(_ verdict: HoldVerdict, message: String?, isPrompt: Bool, session: String, paths: Paths) {
        guard verdict == .deny else { return } // allow = no output: the host's normal permission flow continues
        let text = message ?? stopInstruction(L("Остановлено в Slowburn.", "Stopped in Slowburn."))
        if isPrompt {
            printJSON(["decision": "block", "reason": "◔ " + text])
        } else {
            HoldQueue.markStopped(session, paths: paths, now: Date())
            printJSON(["hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": text,
            ]])
        }
    }

    /// Stop pressed in the host (SIGTERM) or the client quitting: take our request out of the queue.
    static func cleanUpOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler {
                if let id = holdID, let paths = holdPaths { HoldQueue.clear(id, paths: paths) }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
