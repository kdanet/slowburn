import BudgetCore
import Foundation

/// How a waiting agent gets let go.
public enum ReleaseMode: String, Codable, Sendable, CaseIterable {
    /// Only a click in Slowburn releases; nothing lets agents go by itself.
    case manual
    /// Also release on its own once the reason is gone (window reopened, charge back).
    case whenBudgetReturns

    public var title: String {
        switch self {
        case .manual: L("Только вручную", "Manually only")
        case .whenBudgetReturns: L("Когда вернётся бюджет", "When the budget returns")
        }
    }
}

public struct BrakeSettings: Codable, Sendable, Equatable {
    public var releaseMode: ReleaseMode = .manual
    /// Answer "stop" this long into a hold, well before the host's own hook timeout (60 min in our config).
    public var maxWait: TimeInterval = 55 * 60
    /// Over plan by more than this many points before holding: whole-percent readings flap by one.
    public var tolerance: Double = 1

    public init() {}
}

/// Written by the app every few seconds. Hooks hold only while it is fresh: nobody else could release them.
public struct Heartbeat: Codable, Sendable {
    public var at: Date
    public var settings: BrakeSettings

    public init(at: Date, settings: BrakeSettings) {
        self.at = at
        self.settings = settings
    }

    public static let maxAge: TimeInterval = 30
    public func isFresh(now: Date) -> Bool { now.timeIntervalSince(at) <= Self.maxAge }
}

/// One tool call or prompt waiting for a decision.
public struct HoldRequest: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var provider: Provider
    public var event: String
    public var sessionId: String
    public var cwd: String?
    public var tool: String?
    public var agentId: String?
    public var reason: String
    public var createdAt: Date
    public var pid: Int32

    public init(id: String, provider: Provider, event: String, sessionId: String, cwd: String?, tool: String?,
                agentId: String?, reason: String, createdAt: Date, pid: Int32) {
        self.id = id
        self.provider = provider
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.tool = tool
        self.agentId = agentId
        self.reason = reason
        self.createdAt = createdAt
        self.pid = pid
    }

    /// The project folder's name, the way people recognise their sessions.
    public var project: String { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—" }
}

public enum HoldVerdict: String, Codable, Sendable {
    case allow, deny
}

public struct HoldDecision: Codable, Sendable, Equatable {
    public var verdict: HoldVerdict
    public var message: String?
    public var decidedAt: Date

    public init(verdict: HoldVerdict, message: String? = nil, decidedAt: Date) {
        self.verdict = verdict
        self.message = message
        self.decidedAt = decidedAt
    }
}

/// The waiting room, kept as small files so a hook process and the app never need a live connection:
/// `holds/<id>.json` is a request, `holds/<id>.decision` the answer, `stopped/<session>` a session told to stop.
public enum HoldQueue {
    public static let notification = Notification.Name("app.slowburn.holds.changed")
    /// What hooks installed before the rename still post, until `quota integrate` reinstalls them.
    public static let legacyNotification = Notification.Name("app.claudergy.holds.changed")

    static func dir(_ paths: Paths) -> URL { paths.support.appendingPathComponent("holds", isDirectory: true) }
    static func stoppedDir(_ paths: Paths) -> URL { paths.support.appendingPathComponent("stopped", isDirectory: true) }
    static func requestURL(_ id: String, _ paths: Paths) -> URL { dir(paths).appendingPathComponent("\(id).json") }
    static func decisionURL(_ id: String, _ paths: Paths) -> URL { dir(paths).appendingPathComponent("\(id).decision") }

    public static func enqueue(_ r: HoldRequest, paths: Paths) throws {
        try JSONFile.save(r, to: requestURL(r.id, paths))
    }

    /// Waiting requests, oldest first. Requests whose hook process is gone (Stop pressed, client quit) are cleared.
    public static func pending(paths: Paths) -> [HoldRequest] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir(paths), includingPropertiesForKeys: nil)) ?? []
        var out: [HoldRequest] = []
        for f in files where f.pathExtension == "json" {
            guard let r = JSONFile.load(HoldRequest.self, from: f) else { continue }
            if kill(r.pid, 0) != 0 && errno == ESRCH {
                clear(r.id, paths: paths)
                continue
            }
            if FileManager.default.fileExists(atPath: decisionURL(r.id, paths).path) { continue }
            out.append(r)
        }
        return out.sorted { $0.createdAt < $1.createdAt }
    }

    public static func decide(_ id: String, _ d: HoldDecision, paths: Paths) {
        try? JSONFile.save(d, to: decisionURL(id, paths))
    }

    public static func decideAll(_ d: HoldDecision, paths: Paths) {
        for r in pending(paths: paths) { decide(r.id, d, paths: paths) }
    }

    public static func decision(_ id: String, paths: Paths) -> HoldDecision? {
        JSONFile.load(HoldDecision.self, from: decisionURL(id, paths))
    }

    public static func clear(_ id: String, paths: Paths) {
        try? FileManager.default.removeItem(at: requestURL(id, paths))
        try? FileManager.default.removeItem(at: decisionURL(id, paths))
    }

    // MARK: sessions told to stop

    /// After "stop", a session's next tool calls are refused at once instead of queueing again,
    /// until the person writes to it (a new prompt) or `stopFor` passes.
    public static let stopFor: TimeInterval = 15 * 60

    public static func markStopped(_ session: String, paths: Paths, now: Date) {
        try? JSONFile.save(now, to: stoppedDir(paths).appendingPathComponent(safe(session)))
    }

    public static func isStopped(_ session: String, paths: Paths, now: Date) -> Bool {
        guard let at = JSONFile.load(Date.self, from: stoppedDir(paths).appendingPathComponent(safe(session))) else { return false }
        return now.timeIntervalSince(at) < stopFor
    }

    public static func clearStopped(_ session: String, paths: Paths) {
        try? FileManager.default.removeItem(at: stoppedDir(paths).appendingPathComponent(safe(session)))
    }

    private static func safe(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.prefix(80))
    }

    // MARK: demo sessions

    /// A session started with "#brake-demo" is held on every tool call for an hour, to try the brake
    /// without actually running out of budget. Other sessions are never affected.
    public static let demoPrefix = "#brake-demo"
    public static let demoFor: TimeInterval = 3600
    static func demoDir(_ paths: Paths) -> URL { paths.support.appendingPathComponent("demo", isDirectory: true) }

    public static func registerDemo(_ session: String, paths: Paths, now: Date) {
        try? JSONFile.save(now, to: demoDir(paths).appendingPathComponent(safe(session)))
    }

    public static func isDemo(_ session: String, paths: Paths, now: Date) -> Bool {
        guard let at = JSONFile.load(Date.self, from: demoDir(paths).appendingPathComponent(safe(session))) else { return false }
        return now.timeIntervalSince(at) < demoFor
    }

    // MARK: heartbeat and settings

    static func heartbeatURL(_ paths: Paths) -> URL { paths.support.appendingPathComponent("heartbeat.json") }

    public static func beat(_ settings: BrakeSettings, paths: Paths, now: Date) {
        try? JSONFile.save(Heartbeat(at: now, settings: settings), to: heartbeatURL(paths))
    }

    public static func heartbeat(paths: Paths) -> Heartbeat? {
        JSONFile.load(Heartbeat.self, from: heartbeatURL(paths))
    }
}

extension Brake {
    /// Why agents of `provider` should wait right now, or nil. Only two cases hold, the rest at most warn:
    /// the smart limit is overspent beyond tolerance, or Codex is about to work on paid credits.
    public static func holdReason(state: AppState?, provider: Provider, now: Date, tolerance: Double = 1) -> String? {
        guard let state, now.timeIntervalSince(state.generatedAt) <= maxStateAge else { return nil }
        if let until = state.overrideUntil, until > now { return nil }
        let pools = state.pools(of: provider).filter { $0.freshness == .fresh }

        let fullShort = pools.first { !$0.snapshot.isLongWindow && $0.reasons.contains("limit_reached") }
        if provider == .codex, let full = fullShort, (state.codexCredits?.spentLastHour ?? 0) > 0 {
            var r = L("Окно Codex заполнено до \(Phrases.time(full.snapshot.resetsAt)), дальше работа пойдёт за платные credits.",
                      "The Codex window is full until \(Phrases.time(full.snapshot.resetsAt)); further work will be paid in credits.")
            if let n = state.codexFreeResets, n > 0 { r += L(" У тебя \(Phrases.freeResets(n)) лимитов.", " You have \(Phrases.freeResets(n)).") }
            return r
        }
        // Our own 5-hour limit, there even when the provider has none: the norm plus up to one more norm of savings.
        for p in pools where p.snapshot.isLongWindow {
            guard let norm = p.fiveHourBudget, norm > 0, let spent = p.spentLast5h else { continue }
            let cap = p.fiveHourCap ?? norm
            if spent > cap + tolerance {
                return L("\(Phrases.providerName(provider)): за последние 5 часов потрачено \(Phrases.points(spent))% недели при норме \(Phrases.points(cap))% с запасом. Норма скользящая — \(p.fiveHourFreesAt.map { "снова можно в \(Phrases.time($0))" } ?? "через час-другой снова можно").",
                         "\(Phrases.providerName(provider)): \(Phrases.points(spent))% of the week spent in the last 5 hours, over the \(Phrases.points(cap))% norm with reserve. The norm is rolling — \(p.fiveHourFreesAt.map { "you can go again at \(Phrases.time($0))" } ?? "you can go again in an hour or two").")
            }
        }
        if let over = pools.filter({ $0.snapshot.isLongWindow }).first(where: { ($0.available ?? 0) < -tolerance }),
           let a = over.available, let plan = over.plan {
            let back = now.addingTimeInterval((-a + 0.5) / max(plan.ratePerHour, 0.0001) * 3600)
            return L("\(Phrases.providerName(provider)) впереди плана на \(Phrases.points(-a))%: заряд вернётся к \(Phrases.time(back)).",
                     "\(Phrases.providerName(provider)) is \(Phrases.points(-a))% ahead of plan: charge returns by \(Phrases.time(back)).")
        }
        return nil
    }
}
