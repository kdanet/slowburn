import BudgetCore
import Foundation

public struct ProviderSummary: Codable, Sendable {
    public var provider: Provider
    /// Worst level among fresh pools; `unknown` when nothing fresh is known.
    public var level: Level
    public var error: String?
}

/// Everything the menu bar and the hooks need, recomputed by the monitor and read by hooks without IO beyond one file.
public struct AppState: Codable, Sendable {
    public var generatedAt: Date
    public var pools: [PoolStatus]
    public var providers: [ProviderSummary]
    public var claudeTokens24h: [String: TokenCounts]
    public var codexCredits: CreditsStatus?
    /// Free "full reset" grants on the Codex account, when the server reports them.
    public var codexFreeResets: Int?
    public var overrideUntil: Date?

    public func pools(of provider: Provider) -> [PoolStatus] { pools.filter { $0.snapshot.pool.provider == provider } }
    public func summary(of provider: Provider) -> ProviderSummary? { providers.first { $0.provider == provider } }
}

public struct CreditsStatus: Codable, Sendable {
    public var balance: Double
    public var observedAt: Date
    public var spentLastHour: Double
    public var spent24h: Double
}

public struct Override: Codable, Sendable {
    public var until: Date
    public var createdAt: Date

    public init(until: Date, createdAt: Date) {
        self.until = until
        self.createdAt = createdAt
    }
}

/// Latest reading and in-window history per pool, so incremental reads never lose the current value.
struct HistoryFile: Codable {
    var latest: [String: Snapshot] = [:]
    var points: [String: [UsagePoint]] = [:]
    var credits: [UsagePoint]? = []

    static let sameWindow: TimeInterval = 3600

    mutating func mergeCredits(_ incoming: [UsagePoint], now: Date) {
        var list = (credits ?? []) + incoming
        list.sort { $0.at < $1.at }
        var compact: [UsagePoint] = []
        for p in list where p.at >= now.addingTimeInterval(-8 * 86400) {
            if let last = compact.last, last.used == p.used || last.at == p.at { continue }
            compact.append(p)
        }
        credits = compact
    }

    func creditsStatus(now: Date) -> CreditsStatus? {
        guard let list = credits, let last = list.last else { return nil }
        // Only decreases count as spending; a top-up is not negative spending.
        func spent(since: Date) -> Double {
            zip(list, list.dropFirst()).filter { $0.1.at >= since }.reduce(0) { $0 + max(0, $1.0.used - $1.1.used) }
        }
        return CreditsStatus(balance: last.used, observedAt: last.at,
                             spentLastHour: spent(since: now.addingTimeInterval(-3600)),
                             spent24h: spent(since: now.addingTimeInterval(-86400)))
    }

    mutating func merge(_ incoming: [Snapshot]) {
        for s in incoming.sorted(by: { $0.observedAt < $1.observedAt }) {
            let key = s.pool.storageKey
            if let current = latest[key] {
                if s.resetsAt < current.resetsAt.addingTimeInterval(-Self.sameWindow) { continue } // older window
                if s.resetsAt > current.resetsAt.addingTimeInterval(Self.sameWindow) { points[key] = [] } // new window
                if s.observedAt >= current.observedAt || points[key]?.isEmpty == true { latest[key] = s }
            } else {
                latest[key] = s
            }
            var list = points[key] ?? []
            let point = UsagePoint(at: s.observedAt, used: s.usedPercent)
            if let i = list.lastIndex(where: { $0.at <= point.at }) {
                // Keep the moment a value was first reached; repeated equal readings add nothing.
                if list[i].used != point.used { list.insert(point, at: i + 1) }
            } else {
                list.insert(point, at: 0)
            }
            points[key] = list
        }
        for (key, s) in latest {
            points[key] = points[key]?.filter { $0.at >= s.windowStart.addingTimeInterval(-Self.sameWindow) }
        }
    }
}

struct OffsetsFile: Codable {
    var codex: [String: UInt64] = [:]
    var claude: [String: UInt64] = [:]
}

public final class Monitor: @unchecked Sendable {
    public let paths: Paths
    public var settings: PaceSettings
    /// Codex numbers only move when Codex is used, so an old rollout reading is still informative.
    public var codexStaleAfter: TimeInterval = 6 * 3600

    public init(paths: Paths = Paths()) {
        self.paths = paths
        self.settings = JSONFile.load(PaceSettings.self, from: paths.settings) ?? PaceSettings()
    }

    public func readState() -> AppState? { JSONFile.load(AppState.self, from: paths.state) }

    @discardableResult
    public func refresh(now: Date = Date()) async -> AppState {
        var offsets = JSONFile.load(OffsetsFile.self, from: paths.offsets) ?? OffsetsFile()

        var codexReader = IncrementalReader(offsets: offsets.codex, initialTail: 8 << 20)
        var codex = CodexSource.snapshots(paths: paths, reader: &codexReader, now: now)
        offsets.codex = codexReader.offsets
        let codexLive = await CodexLiveSource.fetch(paths: paths, now: now)
        codex.quota += codexLive.snapshots
        if let c = codexLive.credits { codex.credits.append(c) }

        let statusLine = ClaudeSource.statusLineSnapshots(paths: paths)
        var endpoint = await ClaudeSource.endpointSnapshots(paths: paths, now: now)
        // Endpoint unusable (CLI token expired or refused): ask the official CLI, which also refreshes its token.
        let endpointFresh = endpoint.snapshots.contains { now.timeIntervalSince($0.observedAt) < 5 * 60 }
        let cli = ClaudeSource.cliUsageSnapshots(paths: paths, now: now, force: !endpointFresh)
        if !cli.isEmpty, endpoint.error != nil { endpoint.error = nil }

        var claudeReader = IncrementalReader(offsets: offsets.claude, initialTail: 4 << 20)
        let tokens = ClaudeTokenLedger.update(paths: paths, reader: &claudeReader, now: now)
        offsets.claude = claudeReader.offsets
        try? JSONFile.save(offsets, to: paths.offsets)

        var history = JSONFile.load(HistoryFile.self, from: paths.history) ?? HistoryFile()
        history.merge(codex.quota + statusLine + endpoint.snapshots + cli)
        history.mergeCredits(codex.credits, now: now)
        try? JSONFile.save(history, to: paths.history)

        var plans = JSONFile.load([String: PacePlan].self, from: paths.plans) ?? [:]
        var statuses: [PoolStatus] = []
        for (key, s) in history.latest.sorted(by: { $0.value.pool < $1.value.pool }) {
            var plan: PacePlan?
            if s.isLongWindow, now < s.resetsAt {
                // Keep a plan of this window if it is the straight line from its start, or a manual replan.
                // Anything else (a new window, first sight, an old mid-week anchor) becomes the straight line.
                if let p = plans[key], abs(p.resetsAt.timeIntervalSince(s.resetsAt)) < HistoryFile.sameWindow,
                   p.fromNow == true || abs(p.t0.timeIntervalSince(s.windowStart)) < HistoryFile.sameWindow {
                    plan = p
                } else {
                    plan = PacePlan.fromWindowStart(s, settings: settings)
                    plans[key] = plan
                }
            }
            var poolSettings = settings
            if s.source == .codexRollout { poolSettings.staleAfter = codexStaleAfter }
            // With the reserve's checkbox on, the whole reserve backs the 5-hour limit, with no expiry.
            let auto = AutoReserve.isOn(s.pool.provider, paths: paths)
            var status = Pacer.evaluate(snapshot: s, plan: plan, history: history.points[key] ?? [],
                                        settings: poolSettings, now: now,
                                        fiveHourBoost: auto ? .greatestFiniteMagnitude : Boosts.total(s.pool.provider, paths: paths, now: now),
                                        boostUntil: auto ? nil : Boosts.until(s.pool.provider, paths: paths, now: now),
                                        curve: tokens.curve(for: s.pool, now: now))
            if auto { status.fiveHourAuto = true }
            if s.isLongWindow, now < s.resetsAt {
                status.smart = Smart.compute(snapshot: s, plan: plan, history: history.points[key] ?? [], now: now)
            }
            statuses.append(status)
        }
        plans = plans.filter { _, p in p.resetsAt > now.addingTimeInterval(-86400) }
        try? JSONFile.save(plans, to: paths.plans)

        let summaries = Provider.allCases.map { provider -> ProviderSummary in
            let fresh = statuses.filter { $0.snapshot.pool.provider == provider && $0.freshness == .fresh }
            let level = fresh.map(\.level).max() ?? .unknown
            let error = provider == .claude && endpoint.snapshots.isEmpty && statusLine.isEmpty ? endpoint.error : nil
            return ProviderSummary(provider: provider, level: level, error: error)
        }
        let overrideUntil = JSONFile.load(Override.self, from: paths.override).map(\.until).flatMap { $0 > now ? $0 : nil }
        let state = AppState(generatedAt: now, pools: statuses, providers: summaries,
                             claudeTokens24h: tokens.totals(since: now.addingTimeInterval(-86400)),
                             codexCredits: history.creditsStatus(now: now),
                             codexFreeResets: codexLive.freeResets,
                             overrideUntil: overrideUntil)
        try? JSONFile.save(state, to: paths.state)
        return state
    }

    /// "Перепланировать от текущего остатка": restart every live long window's plan from now,
    /// forgiving the week's debt (or dropping its savings). The next new window goes back to the straight line.
    public func replan(now: Date = Date()) throws {
        let history = JSONFile.load(HistoryFile.self, from: paths.history) ?? HistoryFile()
        var plans: [String: PacePlan] = [:]
        for (key, s) in history.latest where s.isLongWindow && now < s.resetsAt {
            plans[key] = PacePlan.start(from: s, now: now, settings: settings)
        }
        try JSONFile.save(plans, to: paths.plans)
    }

    /// Back to the straight line from each window's start.
    public func resetPlans() throws {
        try JSONFile.save([String: PacePlan](), to: paths.plans)
    }

    public func allow(minutes: Double, now: Date = Date()) throws {
        try JSONFile.save(Override(until: now.addingTimeInterval(minutes * 60), createdAt: now), to: paths.override)
    }

    public func clearOverride() {
        try? FileManager.default.removeItem(at: paths.override)
    }
}
