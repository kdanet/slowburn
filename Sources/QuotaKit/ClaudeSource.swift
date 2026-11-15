import BudgetCore
import Foundation

/// Claude Desktop keeps its quota percentages to itself and does not run `statusLine`. Sources, best first:
/// 1. the usage endpoint with the Claude Code CLI's own token, read-only and only while it is unexpired
///    (we never refresh it: rotating someone else's refresh token can log the CLI out);
/// 2. `claude -p /usage`: the official CLI prints the same numbers locally, with no model call,
///    and refreshes its own token on the way, which re-enables source 1;
/// 3. a `statusLine` payload, for terminal sessions (`quota statusline`).
public enum ClaudeSource {
    /// Keychain item the Claude Code CLI keeps its OAuth credentials in.
    public static let cliKeychainService = "Claude Code-credentials"

    static func title(for key: String) -> String {
        switch key {
        case "five_hour": "5 часов"
        case "seven_day": "Неделя"
        default:
            if key.hasPrefix("seven_day_") {
                "Неделя · " + key.dropFirst("seven_day_".count).capitalized
            } else {
                key
            }
        }
    }

    static func windowMinutes(for key: String) -> Int { key.hasPrefix("five_hour") ? 300 : 10080 }

    // MARK: statusLine inbox

    public struct StatusLineDrop: Codable, Sendable {
        public var receivedAt: Date
        public var rateLimits: Data // raw JSON of `rate_limits`

        public init(receivedAt: Date, rateLimits: Data) {
            self.receivedAt = receivedAt
            self.rateLimits = rateLimits
        }
    }

    /// `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}`; a missing window means unknown, not zero.
    public static func parseStatusLine(_ limits: [String: Any], receivedAt: Date) -> [Snapshot] {
        limits.compactMap { key, value in
            guard let w = value as? [String: Any], let used = number(w["used_percentage"]),
                  let resets = parseTime(w["resets_at"]) else { return nil }
            return Snapshot(pool: PoolKey(.claude, key), title: title(for: key), usedPercent: used, resetsAt: resets,
                            windowMinutes: windowMinutes(for: key), observedAt: receivedAt,
                            source: .claudeStatusLine, precision: used.rounded() == used ? 1 : 0.01)
        }
    }

    public static func statusLineSnapshots(paths: Paths) -> [Snapshot] {
        guard let drop = JSONFile.load(StatusLineDrop.self, from: paths.statusLineInbox),
              let limits = try? JSONSerialization.jsonObject(with: drop.rateLimits) as? [String: Any] else { return [] }
        return parseStatusLine(limits, receivedAt: drop.receivedAt)
    }

    // MARK: usage endpoint

    public struct EndpointState: Codable, Sendable {
        public var lastAttempt: Date?
        public var nextAllowed: Date?
        public var lastError: String?
        public var lastBody: Data?
        public var lastSuccess: Date?
    }

    /// Pool id for a model-scoped weekly limit: "Fable" → "seven_day_fable".
    static func scopedId(model: String) -> String {
        "seven_day_" + model.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    /// Prefers the `limits` array (it names model-scoped pools such as Fable); falls back to the
    /// older `five_hour` / `seven_day*` keys. Blocks about money (extra usage, spend) are not quota.
    public static func parseEndpoint(_ obj: [String: Any], observedAt: Date) -> [Snapshot] {
        if let limits = obj["limits"] as? [[String: Any]], !limits.isEmpty {
            return limits.compactMap { l in
                guard let used = number(l["percent"]), let resets = parseTime(l["resets_at"]) else { return nil }
                let kind = (l["kind"] as? String) ?? ""
                let weekly = (l["group"] as? String) == "weekly" || kind.hasPrefix("weekly")
                let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                let id: String
                if weekly {
                    id = model.map(scopedId) ?? (kind == "weekly_all" ? "seven_day" : "seven_day_\(kind)")
                } else {
                    id = kind.contains("session") || kind.contains("five") ? "five_hour" : kind
                }
                return Snapshot(pool: PoolKey(.claude, id), title: title(for: id), usedPercent: used, resetsAt: resets,
                                windowMinutes: weekly ? 10080 : 300, observedAt: observedAt,
                                source: .claudeUsageEndpoint, precision: used.rounded() == used ? 1 : 0.01)
            }
        }
        return obj.compactMap { key, value in
            guard key.hasPrefix("five_hour") || key.hasPrefix("seven_day"),
                  let w = value as? [String: Any], let used = number(w["utilization"]),
                  let resets = parseTime(w["resets_at"]) else { return nil }
            return Snapshot(pool: PoolKey(.claude, key), title: title(for: key), usedPercent: used, resetsAt: resets,
                            windowMinutes: windowMinutes(for: key), observedAt: observedAt,
                            source: .claudeUsageEndpoint, precision: used.rounded() == used ? 1 : 0.01)
        }
    }

    enum TokenState: Equatable {
        case valid(String)
        case expired
        case missing
    }

    /// The CLI's access token, read-only. Expired (or about to be) counts as unusable: refreshing is the CLI's job.
    static func readCLIToken(now: Date) -> TokenState {
        guard let out = run("/usr/bin/security", ["find-generic-password", "-s", cliKeychainService, "-w"], timeout: 10),
              let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .missing }
        if let expires = parseTime(oauth["expiresAt"]), expires < now.addingTimeInterval(120) { return .expired }
        return .valid(token)
    }

    /// Runs a tool with stdin closed, returns stdout on exit status 0. Kills it after `timeout`.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval, cwd: URL? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Polls at most once a minute and backs off on errors; returns the last good reading either way.
    public static func endpointSnapshots(paths: Paths, now: Date, minInterval: TimeInterval = 60) async -> (snapshots: [Snapshot], error: String?) {
        var state = JSONFile.load(EndpointState.self, from: paths.endpointState) ?? EndpointState()
        func cached() -> [Snapshot] {
            guard let body = state.lastBody, let at = state.lastSuccess,
                  let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [] }
            return parseEndpoint(obj, observedAt: at)
        }
        if let next = state.nextAllowed, now < next { return (cached(), state.lastError) }
        let token: String
        switch readCLIToken(now: now) {
        case .valid(let t): token = t
        case .expired: return (cached(), "token_expired")
        case .missing: return (cached(), "no_token")
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("slowburn", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        state.lastAttempt = now
        state.nextAllowed = now.addingTimeInterval(minInterval)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200:
                state.lastBody = data
                state.lastSuccess = now
                state.lastError = nil
            case 401, 403:
                state.lastError = "auth_\(code)"
                state.nextAllowed = now.addingTimeInterval(15 * 60)
            case 429:
                let retry = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
                state.lastError = "rate_limited"
                state.nextAllowed = now.addingTimeInterval(max(retry, minInterval))
            default:
                state.lastError = "http_\(code)"
                state.nextAllowed = now.addingTimeInterval(5 * 60)
            }
        } catch {
            state.lastError = "network"
            state.nextAllowed = now.addingTimeInterval(2 * 60)
        }
        try? JSONFile.save(state, to: paths.endpointState)
        return (cached(), state.lastError)
    }

    // MARK: official CLI `/usage`

    public struct CLIUsageState: Codable, Sendable {
        public var lastRun: Date?
        public var lastText: String?
        public var lastSuccess: Date?
    }

    static func claudeExecutable(home: URL) -> String? {
        let candidates = [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/claude" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `claude -p /usage` is a local command: no model call, no cost. User settings are skipped so our own
    /// hooks do not fire for it, and the session is not saved into ~/.claude/projects.
    public static func cliUsageSnapshots(paths: Paths, now: Date, force: Bool, minInterval: TimeInterval = 180) -> [Snapshot] {
        var state = JSONFile.load(CLIUsageState.self, from: paths.cliUsageState) ?? CLIUsageState()
        let due = force && (state.lastRun.map { now.timeIntervalSince($0) >= minInterval } ?? true)
        if due, let exe = claudeExecutable(home: paths.home) {
            state.lastRun = now
            try? FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
            if let out = run(exe, ["-p", "/usage", "--output-format", "json", "--no-session-persistence",
                                   "--setting-sources", "project"], timeout: 45, cwd: paths.support),
               let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
               obj["num_turns"] as? Int == 0, let text = obj["result"] as? String, text.contains("% used") {
                state.lastText = text
                state.lastSuccess = now
            }
            try? JSONFile.save(state, to: paths.cliUsageState)
        }
        guard let text = state.lastText, let at = state.lastSuccess else { return [] }
        return parseCLIUsage(text, observedAt: at)
    }

    /// Lines such as `Current week (all models): 41% used · resets Nov 19 at 2pm (Europe/Samara)`
    /// or `Current session: 12% used · resets 7:30pm (Europe/Samara)`.
    public static func parseCLIUsage(_ text: String, observedAt: Date) -> [Snapshot] {
        let pattern = #"^Current (session|week)(?: \(([^)]+)\))?: ([\d.]+)% used(?: · resets (.+?) \(([^)]+)\))?\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let kind = group(1), let used = group(3).flatMap(Double.init),
                  let resetText = group(4), let tz = group(5).flatMap(TimeZone.init(identifier:)),
                  let resets = parseResetPhrase(resetText, timeZone: tz, now: observedAt) else { return nil }
            let scope = group(2)
            let id: String
            if kind == "session" {
                id = "five_hour"
            } else if let scope, scope != "all models" {
                id = scopedId(model: scope)
            } else {
                id = "seven_day"
            }
            return Snapshot(pool: PoolKey(.claude, id), title: title(for: id), usedPercent: used, resetsAt: resets,
                            windowMinutes: kind == "session" ? 300 : 10080, observedAt: observedAt,
                            source: .claudeCLIUsage, precision: 1)
        }
    }

    /// "Nov 19 at 2pm", "Nov 19 at 2:30pm", "7pm", "7:30pm" → the next such moment at or after `now`.
    static func parseResetPhrase(_ phrase: String, timeZone: TimeZone, now: Date) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.defaultDate = now
        let cleaned = phrase.replacingOccurrences(of: " ", with: " ").trimmingCharacters(in: .whitespaces)
        for format in ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d, h:mma", "MMM d, ha", "h:mma", "ha"] {
            f.dateFormat = format
            guard var date = f.date(from: cleaned) else { continue }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            // `defaultDate` fills fields the text lacks; minutes must be 0 for "2pm", not now's minutes.
            let hasMinutes = format.contains("mm")
            if format.hasPrefix("MMM") {
                // No year in the text: take the occurrence closest after now (allowing a little lag).
                var comps = cal.dateComponents([.month, .day, .hour, .minute], from: date)
                if !hasMinutes { comps.minute = 0 }
                comps.year = cal.component(.year, from: now)
                date = cal.date(from: comps) ?? date
                if date < now.addingTimeInterval(-86400) { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
            } else {
                var comps = cal.dateComponents([.year, .month, .day], from: now)
                let t = cal.dateComponents([.hour, .minute], from: date)
                comps.hour = t.hour
                comps.minute = hasMinutes ? t.minute : 0
                date = cal.date(from: comps) ?? date
                if date < now.addingTimeInterval(-60) { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
            }
            return date
        }
        return nil
    }
}

/// Token usage by model from Claude Code transcripts (`entrypoint: claude-desktop` included).
/// This is history and attribution, not quota: it never turns into a percentage on its own.
public struct TokenCounts: Codable, Sendable, Equatable {
    public var input = 0
    public var cacheRead = 0
    public var cacheWrite = 0
    public var output = 0
    public var messages = 0

    public init() {}

    public var total: Int { input + cacheRead + cacheWrite + output }

    mutating func add(_ o: TokenCounts) {
        input += o.input; cacheRead += o.cacheRead; cacheWrite += o.cacheWrite; output += o.output; messages += o.messages
    }
}

public struct ClaudeTokenLedger: Codable, Sendable {
    /// hour (epoch seconds, floored) → model → counts
    public var hours: [Int: [String: TokenCounts]] = [:]
    /// message ids already counted, with the hour they landed in (a message spans several lines).
    public var seen: [String: Int] = [:]

    public init() {}

    static let marker = Data("\"usage\"".utf8)

    public mutating func ingest(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
              let id = message["id"] as? String, seen[id] == nil,
              let at = (obj["timestamp"] as? String).flatMap(parseISODate) else { return }
        let model = (message["model"] as? String) ?? "unknown"
        guard model != "<synthetic>" else { return }
        var c = TokenCounts()
        c.input = Int(number(usage["input_tokens"]) ?? 0)
        c.cacheRead = Int(number(usage["cache_read_input_tokens"]) ?? 0)
        c.cacheWrite = Int(number(usage["cache_creation_input_tokens"]) ?? 0)
        c.output = Int(number(usage["output_tokens"]) ?? 0)
        c.messages = 1
        let hour = Int(at.timeIntervalSince1970) / 3600 * 3600
        seen[id] = hour
        hours[hour, default: [:]][model, default: TokenCounts()].add(c)
    }

    public mutating func trim(keepingSince cutoff: Date) {
        let h = Int(cutoff.timeIntervalSince1970)
        hours = hours.filter { $0.key >= h }
        seen = seen.filter { $0.value >= h }
    }

    public func totals(since: Date) -> [String: TokenCounts] {
        let h = Int(since.timeIntervalSince1970) / 3600 * 3600
        var out: [String: TokenCounts] = [:]
        for (hour, models) in hours where hour >= h {
            for (model, c) in models { out[model, default: TokenCounts()].add(c) }
        }
        return out
    }

    public static func update(paths: Paths, reader: inout IncrementalReader, now: Date) -> ClaudeTokenLedger {
        var ledger = JSONFile.load(ClaudeTokenLedger.self, from: paths.claudeTokens) ?? ClaudeTokenLedger()
        for file in recentFiles(under: paths.claudeProjects, ext: "jsonl", modifiedWithin: 86400, now: now) {
            for line in reader.newLines(in: file) where line.range(of: marker) != nil {
                ledger.ingest(line: line)
            }
        }
        ledger.trim(keepingSince: now.addingTimeInterval(-8 * 86400))
        try? JSONFile.save(ledger, to: paths.claudeTokens)
        return ledger
    }
}
