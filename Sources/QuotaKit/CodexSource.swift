import BudgetCore
import Foundation

/// Codex Desktop and the CLI write a `token_count` event with the account's rate limits
/// into `~/.codex/sessions/**/rollout-*.jsonl` after every turn. Reading those costs nothing.
public enum CodexSource {
    static let marker = Data("\"rate_limits\"".utf8)

    public static func snapshots(paths: Paths, reader: inout IncrementalReader, now: Date) -> (quota: [Snapshot], credits: [UsagePoint]) {
        var quota: [Snapshot] = []
        var credits: [UsagePoint] = []
        for file in recentFiles(under: paths.codexSessions, ext: "jsonl", modifiedWithin: 8 * 86400, now: now) {
            for line in reader.newLines(in: file) where line.range(of: marker) != nil {
                quota.append(contentsOf: parse(line: line))
                if let c = parseCredits(line: line) { credits.append(c) }
            }
        }
        return (quota, credits)
    }

    /// Codex keeps working past a full window by spending credits. The balance is money-like, not a percentage.
    public static func parseCredits(line: Data) -> UsagePoint? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any],
              let credits = limits["credits"] as? [String: Any], credits["has_credits"] as? Bool == true,
              let balance = number(credits["balance"]) ?? (credits["balance"] as? String).flatMap(Double.init),
              let observed = (obj["timestamp"] as? String).flatMap(parseISODate) else { return nil }
        return UsagePoint(at: observed, used: balance)
    }

    public static func parse(line: Data) -> [Snapshot] {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any],
              let observed = (obj["timestamp"] as? String).flatMap(parseISODate) else { return [] }
        let limitId = (limits["limit_id"] as? String) ?? "codex"
        // primary/secondary are positions, not meanings: identify windows by their length.
        return ["primary", "secondary"].compactMap { slot in
            guard let w = limits[slot] as? [String: Any], let used = number(w["used_percent"]),
                  let minutes = number(w["window_minutes"]).map({ Int($0) }),
                  let resets = parseTime(w["resets_at"]) else { return nil }
            return Snapshot(pool: PoolKey(.codex, "\(limitId).\(minutes)"), title: windowTitle(minutes: minutes),
                            usedPercent: used, resetsAt: resets, windowMinutes: minutes, observedAt: observed,
                            source: .codexRollout, precision: used.rounded() == used ? 1 : 0.01)
        }
    }
}

/// Live numbers from the same server endpoint Codex's own usage screen reads. Rollouts only move while
/// Codex works; this stays fresh while it is idle. Read-only: the token in ~/.codex/auth.json is never refreshed here.
public enum CodexLiveSource {
    public struct Result: Sendable {
        public var snapshots: [Snapshot] = []
        public var credits: UsagePoint?
        public var freeResets: Int?
        public var error: String?
    }

    struct State: Codable {
        var nextAllowed: Date?
        var lastBody: Data?
        var lastSuccess: Date?
        var lastError: String?
    }

    public static func parse(_ obj: [String: Any], observedAt: Date) -> Result {
        var out = Result()
        if let rl = obj["rate_limit"] as? [String: Any] {
            for key in ["primary_window", "secondary_window"] {
                guard let w = rl[key] as? [String: Any], let used = number(w["used_percent"]),
                      let seconds = number(w["limit_window_seconds"]), let resets = parseTime(w["reset_at"]) else { continue }
                let minutes = Int(seconds / 60)
                out.snapshots.append(Snapshot(pool: PoolKey(.codex, "codex.\(minutes)"), title: windowTitle(minutes: minutes),
                                              usedPercent: used, resetsAt: resets, windowMinutes: minutes, observedAt: observedAt,
                                              source: .codexUsageEndpoint, precision: used.rounded() == used ? 1 : 0.01))
            }
        }
        if let c = obj["credits"] as? [String: Any], c["has_credits"] as? Bool == true,
           let balance = number(c["balance"]) ?? (c["balance"] as? String).flatMap(Double.init) {
            out.credits = UsagePoint(at: observedAt, used: balance)
        }
        if let r = obj["rate_limit_reset_credits"] as? [String: Any] {
            out.freeResets = (number(r["applicable_available_count"]) ?? number(r["available_count"])).map { Int($0) }
        }
        return out
    }

    public static func fetch(paths: Paths, now: Date, minInterval: TimeInterval = 120) async -> Result {
        let stateURL = paths.support.appendingPathComponent("codex-live.json")
        var state = JSONFile.load(State.self, from: stateURL) ?? State()
        func cached(_ error: String?) -> Result {
            guard let body = state.lastBody, let at = state.lastSuccess,
                  let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return Result(error: error) }
            var r = parse(obj, observedAt: at)
            r.error = error
            return r
        }
        if let next = state.nextAllowed, now < next { return cached(state.lastError) }

        let authURL = paths.home.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any], let token = tokens["access_token"] as? String else {
            return cached("no_token")
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let account = tokens["account_id"] as? String { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("slowburn", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        state.nextAllowed = now.addingTimeInterval(minInterval)
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200:
                state.lastBody = body; state.lastSuccess = now; state.lastError = nil
            case 401, 403:
                state.lastError = "auth_\(code)"; state.nextAllowed = now.addingTimeInterval(15 * 60)
            case 429:
                state.lastError = "rate_limited"; state.nextAllowed = now.addingTimeInterval(10 * 60)
            default:
                state.lastError = "http_\(code)"; state.nextAllowed = now.addingTimeInterval(5 * 60)
            }
        } catch {
            state.lastError = "network"; state.nextAllowed = now.addingTimeInterval(2 * 60)
        }
        try? JSONFile.save(state, to: stateURL)
        return cached(state.lastError)
    }
}

func windowTitle(minutes: Int) -> String {
    switch minutes {
    case 300: "5 часов"
    case 10080: "Неделя"
    case 1440: "Сутки"
    default: minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes) мин"
    }
}
