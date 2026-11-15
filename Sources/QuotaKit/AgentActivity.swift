import BudgetCore
import Foundation

/// What a busy agent is doing, guessed from the last step in its log.
public enum WorkKind: String, Sendable, CaseIterable {
    case typing      // writing its answer
    case coding      // editing files
    case searching   // reading and grepping the codebase
    case terminal    // running a shell command
    case testing     // running tests
    case building    // building, installing, compiling
    case shipping    // committing, pushing, deploying
    case browsing    // searching or reading the web
    case delegating  // handing work to subagents
    case thinking    // reasoning before the next step
    case planning    // keeping a todo list or plan
    case debugging   // the last tool failed
    case asking      // waiting for the user's answer

    /// Shell commands, by what they are for. First match wins.
    static let commandKinds: [(WorkKind, [String])] = [
        (.testing, ["test", "pytest", "jest", "vitest", "rspec", "xctest", "spec"]),
        (.shipping, ["git push", "git commit", "deploy", "publish", "release", "gh pr", "fly ", "vercel", "kubectl apply"]),
        (.building, ["build", "make", "compile", "install", "tsc", "webpack", "vite", "gradle", "cargo b", "xcodebuild", "bundle"]),
        (.browsing, ["curl ", "wget "]),
        (.searching, ["grep", "rg ", "find ", "cat ", "sed -n", "head ", "tail ", "ls", "git log", "git diff", "git status"]),
    ]

    /// A tool call, from its name and (for shells and script runners) the text of its input.
    public static func classify(tool: String, input: String) -> WorkKind {
        let name = tool.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }
        if has("askuser", "request_user_input", "question") { return .asking }
        if has("todo", "plan") { return .planning }
        if has("websearch", "webfetch", "web_search", "browser", "chrome", "navigate", "fetch") { return .browsing }
        if has("agent", "task", "spawn", "session", "sendmessage", "workflow") { return .delegating }
        if has("edit", "write", "patch", "notebook") { return .coding }
        if has("read", "grep", "glob", "search", "view", "list") { return .searching }
        if has("bash", "shell", "exec", "command", "terminal", "run") {
            let text = input.lowercased()
            // Script runners wrap other tools: a patch inside is still coding.
            if text.contains("apply_patch") || text.contains("write_file") { return .coding }
            for (kind, words) in commandKinds where words.contains(where: { text.contains($0) }) { return kind }
            return .terminal
        }
        return .typing
    }
}

/// One provider's agents that are mid-turn.
public struct AgentBusy: Sendable, Equatable {
    public var sessions: Int
    /// What the most recently active of them is doing.
    public var work: WorkKind

    public init(sessions: Int, work: WorkKind) {
        self.sessions = sessions
        self.work = work
    }
}

/// Which agents are mid-turn right now, read from the session logs both CLIs append to while they work.
///
/// A log that moved recently is not enough: Claude Code also writes metadata (titles, bridge records) between
/// turns. So the last *conversational* entry decides — a finished turn ends with `end_turn` / a stop-hook summary
/// (Claude) or `task_complete` (Codex); anything else in a fresh log means the agent is still going.
public enum AgentActivity {
    /// A turn whose log has been silent this long is treated as over: a crash, a closed window, a stuck permission prompt.
    public static let silentAfter: TimeInterval = 10 * 60
    static let tailBytes = 256 << 10

    /// Busy sessions per provider. Cheap enough to call every few seconds.
    public static func scan(paths: Paths, now: Date = Date()) -> [Provider: AgentBusy] {
        var busy: [Provider: AgentBusy] = [:]
        func note(_ provider: Provider, _ work: WorkKind?) {
            guard let work else { return }
            // Files come newest first: the first busy one names the work.
            if var b = busy[provider] { b.sessions += 1; busy[provider] = b } else { busy[provider] = AgentBusy(sessions: 1, work: work) }
        }
        for file in recentFiles(under: paths.claudeProjects, ext: "jsonl", modifiedWithin: silentAfter, now: now) {
            note(.claude, claudeWork(lines: tail(of: file), now: now))
        }
        for file in recentFiles(under: paths.codexSessions, ext: "jsonl", modifiedWithin: silentAfter, now: now) {
            note(.codex, codexWork(lines: tail(of: file)))
        }
        return busy
    }

    public static func claudeBusy(lines: [Data]) -> Bool { claudeWork(lines: lines) != nil }
    public static func codexBusy(lines: [Data]) -> Bool { codexWork(lines: lines) != nil }

    /// Claude Code transcript lines, oldest first. nil = the turn is over.
    /// A request with no answer logged this long after it: the reply went somewhere unpersisted (side chats).
    static let unansweredAfter: TimeInterval = 3 * 60

    public static func claudeWork(lines: [Data], now: Date? = nil) -> WorkKind? {
        // A finished tool hands back to the same step: keep showing it, unless it failed.
        var afterResult = false
        for line in lines.reversed() {
            guard let d = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = d["type"] as? String else { continue }
            switch type {
            case "assistant":
                let message = d["message"] as? [String: Any]
                let stop = message?["stop_reason"] as? String
                if !afterResult, stop == "end_turn" || stop == "stop_sequence" || stop == "max_tokens" || stop == "refusal" {
                    return nil
                }
                // A streamed message is logged per content block: the last block is the current step.
                guard let block = (message?["content"] as? [[String: Any]])?.last else { return .typing }
                switch block["type"] as? String {
                case "tool_use":
                    return WorkKind.classify(tool: block["name"] as? String ?? "", input: inputText(block["input"]))
                case "thinking", "redacted_thinking":
                    return .thinking
                default:
                    return afterResult ? .thinking : .typing
                }
            case "system":
                let sub = d["subtype"] as? String
                if !afterResult, sub == "stop_hook_summary" || sub == "turn_duration" { return nil }
                continue // local commands, compaction, retried API errors: look further back
            case "user":
                // Esc leaves a synthetic "[Request interrupted by user]" as the last word.
                if !afterResult, let text = userText(d), text.contains("[Request interrupted by user") { return nil }
                let blocks = (d["message"] as? [String: Any])?["content"] as? [[String: Any]]
                if let results = blocks?.filter({ $0["type"] as? String == "tool_result" }), !results.isEmpty {
                    if afterResult { continue }
                    if results.contains(where: { $0["is_error"] as? Bool == true }) { return .debugging }
                    afterResult = true
                    continue
                }
                return .thinking // a fresh prompt: reading the task
            case "api-request":
                if let now, let at = parseTime(d["timestamp"]), now.timeIntervalSince(at) > unansweredAfter { return nil }
                if !afterResult { return .thinking }
                continue
            case "attachment", "progress", "api-request-blob":
                if !afterResult { return .thinking }
                continue
            default:
                continue // summaries, titles, bridge records, snapshots: not a sign of work
            }
        }
        return afterResult ? .thinking : nil
    }

    /// Codex rollout lines, oldest first. nil = the turn is over.
    public static func codexWork(lines: [Data]) -> WorkKind? {
        var afterOutput = false
        var sawWork = false
        for line in lines.reversed() {
            guard let d = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let payload = d["payload"] as? [String: Any]
            let kind = payload?["type"] as? String
            switch d["type"] as? String {
            case "event_msg":
                if kind == "task_complete" || kind == "turn_aborted" || kind == "shutdown_complete" {
                    return afterOutput ? .thinking : nil
                }
                if kind == "task_started" { return .thinking }
                sawWork = true
            case "response_item":
                sawWork = true
                switch kind {
                case "function_call", "custom_tool_call", "local_shell_call":
                    let name = payload?["name"] as? String ?? (kind == "local_shell_call" ? "shell" : "")
                    return WorkKind.classify(tool: name, input: inputText(payload?["arguments"] ?? payload?["input"] ?? payload?["action"]))
                case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
                    afterOutput = true
                case "web_search_call":
                    return .browsing
                case "reasoning":
                    return .thinking
                case "message":
                    let role = payload?["role"] as? String
                    if role == "assistant" { return afterOutput ? .thinking : .typing }
                    return .thinking
                default:
                    continue
                }
            default:
                continue
            }
        }
        // No turn boundary in the tail of a fresh log: the turn is long and still running.
        return sawWork ? (afterOutput ? .thinking : .typing) : nil
    }

    private static func inputText(_ value: Any?) -> String {
        if let s = value as? String { return s }
        guard let value, JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func userText(_ d: [String: Any]) -> String? {
        let content = (d["message"] as? [String: Any])?["content"]
        if let s = content as? String { return s }
        if let blocks = content as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return nil
    }

    /// Complete lines from the end of a file; the first partial line of the window is dropped.
    static func tail(of url: URL) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}
