import BudgetCore
import Foundation
import Testing
@testable import QuotaKit

private func tempPaths() -> Paths {
    Paths(home: FileManager.default.temporaryDirectory,
          support: FileManager.default.temporaryDirectory.appendingPathComponent("slowburn-holds-\(UUID())"))
}

private func request(_ id: String, pid: Int32 = getpid(), at: Date = Date()) -> HoldRequest {
    HoldRequest(id: id, provider: .claude, event: "PreToolUse", sessionId: "s1", cwd: "/Users/me/Projects/Shop",
                tool: "Bash", agentId: nil, reason: "test", createdAt: at, pid: pid)
}

@Test func queueRoundTrip() throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.support) }
    try HoldQueue.enqueue(request("a", at: Date(timeIntervalSince1970: 1)), paths: paths)
    try HoldQueue.enqueue(request("b", at: Date(timeIntervalSince1970: 2)), paths: paths)
    #expect(HoldQueue.pending(paths: paths).map(\.id) == ["a", "b"])
    #expect(HoldQueue.pending(paths: paths).first?.project == "Shop")

    HoldQueue.decide("a", HoldDecision(verdict: .allow, decidedAt: Date()), paths: paths)
    #expect(HoldQueue.pending(paths: paths).map(\.id) == ["b"]) // decided ones leave the waiting list
    #expect(HoldQueue.decision("a", paths: paths)?.verdict == .allow)

    HoldQueue.decideAll(HoldDecision(verdict: .deny, message: "стоп", decidedAt: Date()), paths: paths)
    #expect(HoldQueue.pending(paths: paths).isEmpty)
    #expect(HoldQueue.decision("b", paths: paths)?.message == "стоп")
}

@Test func deadHookProcessesLeaveTheQueue() throws {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.support) }
    try HoldQueue.enqueue(request("gone", pid: 999_999), paths: paths) // no such process
    #expect(HoldQueue.pending(paths: paths).isEmpty)
}

@Test func stoppedSessionsExpireAndClear() {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.support) }
    let now = Date()
    HoldQueue.markStopped("abc-123", paths: paths, now: now)
    #expect(HoldQueue.isStopped("abc-123", paths: paths, now: now.addingTimeInterval(60)))
    #expect(!HoldQueue.isStopped("abc-123", paths: paths, now: now.addingTimeInterval(HoldQueue.stopFor + 1)))
    HoldQueue.clearStopped("abc-123", paths: paths)
    #expect(!HoldQueue.isStopped("abc-123", paths: paths, now: now))
}

@Test func heartbeatFreshness() {
    let now = Date()
    #expect(Heartbeat(at: now.addingTimeInterval(-10), settings: BrakeSettings()).isFresh(now: now))
    #expect(!Heartbeat(at: now.addingTimeInterval(-60), settings: BrakeSettings()).isFresh(now: now))
}

// MARK: when to hold

private func weeklyStatus(_ p: Provider, available: Double, now: Date) -> PoolStatus {
    let snap = Snapshot(pool: PoolKey(p, "seven_day"), title: "Неделя", usedPercent: 50, resetsAt: now.addingTimeInterval(86400 * 3),
                        windowMinutes: 10080, observedAt: now, source: .claudeUsageEndpoint, precision: 1)
    var s = PoolStatus(snapshot: snap, freshness: .fresh, level: available < 0 ? .red : .green, correctionDetected: false, reasons: [])
    s.available = available
    s.plan = PacePlan(t0: now.addingTimeInterval(-86400), u0: 30, resetsAt: snap.resetsAt, margin: 2, advance: 0)
    return s
}

private func state(_ pools: [PoolStatus], now: Date, credits: CreditsStatus? = nil, override: Date? = nil) -> AppState {
    AppState(generatedAt: now, pools: pools, providers: [], claudeTokens24h: [:], codexCredits: credits,
             codexFreeResets: 3, overrideUntil: override)
}

@Test func holdsOnlyBeyondTolerance() {
    let now = Date()
    #expect(Brake.holdReason(state: state([weeklyStatus(.claude, available: -0.5, now: now)], now: now), provider: .claude, now: now) == nil)
    let r = Brake.holdReason(state: state([weeklyStatus(.claude, available: -3, now: now)], now: now), provider: .claude, now: now)
    #expect(r?.contains("впереди плана") == true)
}

@Test func holdsWhenFiveHoursAteTheNormAndTheReserve() {
    let now = Date()
    var pool = weeklyStatus(.claude, available: 5, now: now)
    pool.fiveHourBudget = 3
    pool.battery = 2
    pool.fiveHourCap = Pacer.fiveHourCap(norm: 3, battery: 2, boost: 2) // 3 + 2 added by hand
    pool.spentThisSlot = 4.5 // within norm 3 + reserve 2
    #expect(Brake.holdReason(state: state([pool], now: now), provider: .claude, now: now) == nil)
    pool.spentThisSlot = 6.5 // beyond 3 + 2 (+1 tolerance)
    let r = Brake.holdReason(state: state([pool], now: now), provider: .claude, now: now)
    #expect(r?.contains("в этих 5 часах") == true)
}

@Test func overrideAndStaleStateNeverHold() {
    let now = Date()
    let over = [weeklyStatus(.claude, available: -3, now: now)]
    #expect(Brake.holdReason(state: state(over, now: now, override: now.addingTimeInterval(600)), provider: .claude, now: now) == nil)
    #expect(Brake.holdReason(state: state(over, now: now.addingTimeInterval(-3600)), provider: .claude, now: now) == nil)
    #expect(Brake.holdReason(state: nil, provider: .claude, now: now) == nil)
}

@Test func codexHoldsBeforePaidCredits() {
    let now = Date()
    let snap = Snapshot(pool: PoolKey(.codex, "codex.300"), title: "5 часов", usedPercent: 100, resetsAt: now.addingTimeInterval(1800),
                        windowMinutes: 300, observedAt: now, source: .codexUsageEndpoint, precision: 1)
    let full = PoolStatus(snapshot: snap, freshness: .fresh, level: .red, correctionDetected: false, reasons: ["limit_reached"])
    let paying = CreditsStatus(balance: 100, observedAt: now, spentLastHour: 2, spent24h: 2)
    let r = Brake.holdReason(state: state([full], now: now, credits: paying), provider: .codex, now: now)
    #expect(r?.contains("credits") == true)
    #expect(r?.contains("3 бесплатных сброса") == true)
    // Full window but nothing being paid: Codex simply waits on its own, no need to hold.
    #expect(Brake.holdReason(state: state([full], now: now), provider: .codex, now: now) == nil)
}

@Test func boostsStackTakeBackAndEndWithTheirSlot() {
    let paths = tempPaths()
    defer { try? FileManager.default.removeItem(at: paths.support) }
    let now = Date()
    let slotStart = now.addingTimeInterval(-600)
    Boosts.add(.codex, amount: 1, paths: paths, now: now.addingTimeInterval(-900)) // pressed in the previous slot
    Boosts.add(.codex, amount: 2.9, paths: paths, now: now)
    Boosts.add(.codex, amount: 2.9, paths: paths, now: now.addingTimeInterval(60))
    Boosts.add(.claude, amount: 1, paths: paths, now: now)
    #expect(abs(Boosts.total(.codex, paths: paths, since: slotStart) - 5.8) < 1e-9)
    Boosts.removeLast(.codex, paths: paths, now: now.addingTimeInterval(120))
    #expect(abs(Boosts.total(.codex, paths: paths, since: slotStart) - 2.9) < 1e-9)
    #expect(Boosts.total(.claude, paths: paths, since: slotStart) == 1)
    // The next slot starts from the norm again.
    #expect(Boosts.total(.codex, paths: paths, since: now.addingTimeInterval(3600)) == 0)
}
