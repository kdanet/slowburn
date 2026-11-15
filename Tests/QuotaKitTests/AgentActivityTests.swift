import Foundation
import Testing
@testable import QuotaKit

private func lines(_ s: String...) -> [Data] { s.map { Data($0.utf8) } }

@Test func claudeTurnInProgress() {
    #expect(AgentActivity.claudeBusy(lines: lines(
        #"{"type":"user","message":{"role":"user","content":"сделай"}}"#,
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use"}]}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result"}]}}"#)))
    // Just submitted, nothing answered yet.
    #expect(AgentActivity.claudeBusy(lines: lines(#"{"type":"user","message":{"role":"user","content":"привет"}}"#)))
}

@Test func claudeFinishedTurnIgnoresLaterMetadata() {
    #expect(!AgentActivity.claudeBusy(lines: lines(
        #"{"type":"user","message":{"role":"user","content":"сделай"}}"#,
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text"}]}}"#,
        #"{"type":"custom-title","customTitle":"x"}"#,
        #"{"type":"bridge-session","sessionId":"s"}"#)))
    #expect(!AgentActivity.claudeBusy(lines: lines(
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}"#,
        #"{"type":"system","subtype":"stop_hook_summary"}"#,
        #"{"type":"system","subtype":"local_command","content":"<local-command-stdout>ok</local-command-stdout>"}"#)))
}

@Test func claudeInterruptedTurnIsIdle() {
    #expect(!AgentActivity.claudeBusy(lines: lines(
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}"#,
        #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#)))
}

@Test func claudeMetadataOnlyIsIdle() {
    #expect(!AgentActivity.claudeBusy(lines: lines(#"{"type":"agent-name","agentName":"x"}"#)))
}

@Test func codexTurnBoundaries() {
    #expect(AgentActivity.codexBusy(lines: lines(
        #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"type":"response_item","payload":{"type":"message"}}"#)))
    #expect(!AgentActivity.codexBusy(lines: lines(
        #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"type":"event_msg","payload":{"type":"task_complete"}}"#)))
    #expect(!AgentActivity.codexBusy(lines: lines(
        #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#)))
    #expect(!AgentActivity.codexBusy(lines: lines(#"{"type":"session_meta","payload":{}}"#)))
}

@Test func claudeWorkFollowsTheCurrentTool() {
    func tool(_ name: String, _ input: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":null,"content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"#
    }
    #expect(AgentActivity.claudeWork(lines: lines(tool("Edit", #"{"file_path":"a.swift"}"#))) == .coding)
    #expect(AgentActivity.claudeWork(lines: lines(tool("Bash", #"{"command":"swift test"}"#))) == .testing)
    #expect(AgentActivity.claudeWork(lines: lines(tool("Bash", #"{"command":"git push origin main"}"#))) == .shipping)
    #expect(AgentActivity.claudeWork(lines: lines(tool("Bash", #"{"command":"swift build"}"#))) == .building)
    #expect(AgentActivity.claudeWork(lines: lines(tool("Grep", #"{"pattern":"x"}"#))) == .searching)
    #expect(AgentActivity.claudeWork(lines: lines(tool("WebSearch", #"{"query":"x"}"#))) == .browsing)
    #expect(AgentActivity.claudeWork(lines: lines(tool("Agent", #"{"prompt":"x"}"#))) == .delegating)
    #expect(AgentActivity.claudeWork(lines: lines(tool("AskUserQuestion", #"{}"#))) == .asking)
    #expect(AgentActivity.claudeWork(lines: lines(tool("mcp__ccd_turn__update_plan", #"{}"#))) == .planning)
    // A finished tool keeps its step on screen; a failed one turns into debugging.
    #expect(AgentActivity.claudeWork(lines: lines(tool("Bash", #"{"command":"swift test"}"#),
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#)) == .testing)
    #expect(AgentActivity.claudeWork(lines: lines(tool("Bash", #"{"command":"swift test"}"#),
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","is_error":true}]}}"#)) == .debugging)
    #expect(AgentActivity.claudeWork(lines: lines(
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":null,"content":[{"type":"thinking","thinking":""}]}}"#)) == .thinking)
}

@Test func codexWorkFollowsTheCurrentTool() {
    #expect(AgentActivity.codexWork(lines: lines(
        #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
        #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch"}}"#)) == .coding)
    #expect(AgentActivity.codexWork(lines: lines(
        #"{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"npm test\"}"}}"#,
        #"{"type":"response_item","payload":{"type":"function_call_output","output":"ok"}}"#)) == .testing)
    #expect(AgentActivity.codexWork(lines: lines(#"{"type":"response_item","payload":{"type":"reasoning"}}"#)) == .thinking)
}

@Test func claudeUnansweredRequestGoesIdle() {
    let sent = #"{"type":"api-request","timestamp":"2026-11-15T18:41:28.356Z"}"#
    let at = parseISODate("2026-11-15T18:41:28.356Z")!
    #expect(AgentActivity.claudeWork(lines: lines(sent), now: at.addingTimeInterval(30)) == .thinking)
    #expect(AgentActivity.claudeWork(lines: lines(sent, #"{"type":"custom-title"}"#), now: at.addingTimeInterval(600)) == nil)
}

@Test func masterSwitchOffReleasesHoldsAndForgetsStops() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("slowburn-switch-\(UUID().uuidString)")
    let paths = Paths(home: dir, support: dir)
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = Date()
    let r = HoldRequest(id: "h1", provider: .claude, event: "PreToolUse", sessionId: "s1", cwd: nil, tool: "Bash",
                        agentId: nil, reason: "x", createdAt: now, pid: getpid())
    try HoldQueue.enqueue(r, paths: paths)
    HoldQueue.markStopped("s2", paths: paths, now: now)
    #expect(!MasterSwitch.isOff(paths: paths))

    MasterSwitch.set(on: false, paths: paths, now: now)
    #expect(MasterSwitch.isOff(paths: paths))
    #expect(HoldQueue.decision("h1", paths: paths)?.verdict == .allow)
    #expect(!HoldQueue.isStopped("s2", paths: paths, now: now))

    MasterSwitch.set(on: true, paths: paths, now: now)
    #expect(!MasterSwitch.isOff(paths: paths))
}

@Test func legacyDataFolderMovesAndLeavesALink() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent("slowburn-home-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: home) }
    let old = home.appendingPathComponent("Library/Application Support/Claudergy")
    try fm.createDirectory(at: old.appendingPathComponent("bin"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: old.appendingPathComponent("state.json"))

    let new = home.appendingPathComponent("Library/Application Support/Slowburn")
    Paths.moveLegacySupport(home: home, to: new)
    #expect(fm.fileExists(atPath: new.appendingPathComponent("state.json").path))
    // Hooks installed with the old path still reach the data through the link.
    #expect(fm.fileExists(atPath: old.appendingPathComponent("state.json").path))
    #expect((try? fm.destinationOfSymbolicLink(atPath: old.path)) != nil)
    // Running again changes nothing.
    Paths.moveLegacySupport(home: home, to: new)
    #expect(fm.fileExists(atPath: new.appendingPathComponent("state.json").path))
}
