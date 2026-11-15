import AppKit
import BudgetCore
import QuotaKit
import SwiftUI

/// The app's side of the brake: keeps the heartbeat that lets hooks hold at all, watches the waiting room,
/// and turns clicks into decisions. Hooks never release on their own unless `releaseMode` says so.
@MainActor
final class HoldsModel: ObservableObject {
    static let shared = HoldsModel()

    @Published private(set) var pending: [HoldRequest] = []
    @Published var settings: BrakeSettings {
        didSet { save(); beat() }
    }
    private let monitor = Monitor()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var legacyObserver: NSObjectProtocol?
    private var notified = Set<String>()

    private init() {
        settings = JSONFile.load(BrakeSettings.self, from: Self.settingsURL(Monitor().paths)) ?? BrakeSettings()
        beat()
        reload()
        // Heartbeat and a slow poll as a safety net; the hook's distributed notification makes new holds show at once.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.beat()
                self?.reload()
            }
        }
        observer = DistributedNotificationCenter.default().addObserver(forName: HoldQueue.notification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        // Hooks installed before the rename post the old name until they are reinstalled.
        legacyObserver = DistributedNotificationCenter.default().addObserver(forName: HoldQueue.legacyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    static func settingsURL(_ paths: Paths) -> URL { paths.support.appendingPathComponent("brake.json") }

    private func save() { try? JSONFile.save(settings, to: Self.settingsURL(monitor.paths)) }
    private func beat() { HoldQueue.beat(settings, paths: monitor.paths, now: Date()) }

    func reload() {
        let next = HoldQueue.pending(paths: monitor.paths)
        if next != pending { pending = next }
        let fresh = next.filter { !notified.contains($0.id) }
        if !fresh.isEmpty {
            notified.formUnion(fresh.map(\.id))
            announce(fresh)
        }
    }

    /// Agents waiting, grouped by project for the list.
    var byProject: [(project: String, provider: Provider, count: Int, since: Date, reason: String)] {
        let groups = Dictionary(grouping: pending) { "\($0.provider.rawValue)|\($0.project)" }
        return groups.values.compactMap { items in
            guard let first = items.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return (first.project, first.provider, Set(items.map(\.sessionId)).count, first.createdAt, first.reason)
        }
        .sorted { $0.since < $1.since }
    }

    var sessionsWaiting: Int { Set(pending.map(\.sessionId)).count }

    func releaseAll() {
        HoldQueue.decideAll(HoldDecision(verdict: .allow, decidedAt: Date()), paths: monitor.paths)
        reload()
    }

    /// Release, and keep the brake off for half an hour so the same agents do not queue again right away.
    func releaseAndPause(model: Model) {
        model.setBrake(false)
        releaseAll()
    }

    func stopAll() {
        HoldQueue.decideAll(HoldDecision(verdict: .deny, decidedAt: Date()), paths: monitor.paths)
        reload()
    }

    /// Without an app bundle there is no Notification Center; a sound still says "look at the menu bar".
    private func announce(_ requests: [HoldRequest]) {
        NSSound(named: "Tink")?.play()
    }
}

/// "⏸ 7 агентов ждут" with the three decisions. Shown at the top of the popover while anything waits.
struct HoldQueueCard: View {
    @ObservedObject var holds: HoldsModel
    @ObservedObject var model: Model
    /// Rendering for a snapshot or a clip. The card draws its own buttons, so nothing changes; kept for callers.
    var snapshot = false

    private static let pillHeight: CGFloat = 32

    var body: some View {
        let count = holds.sessionsWaiting
        let first = holds.pending.first
        let provider = first?.provider ?? .claude
        let tint = provider.tint
        // When the 5-hour window frees up again, from the same numbers the bars show.
        let freeAt = model.presentation?.limits.first { $0.provider == provider && $0.fiveHourBudget != nil }?.fiveHourFreesAt
        let who = count == 1 ? Phrases.providerName(provider) : "\(count)"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.2))
                    Image(systemName: "pause.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.orange)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(count == 1 ? L("\(who) ждёт тебя", "\(who) is waiting for you")
                                    : L("\(who) \(agentsWord(count)) тебя", "\(who) agents are waiting for you"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(freeAt.map { L("Пауза, чтобы сберечь лимит · свободно в \(Phrases.time($0))",
                                        "Paused to save your limit · free again at \(Phrases.time($0))") }
                         ?? L("Пауза, чтобы сберечь лимит", "Paused to save your limit"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
            }
            .help(first?.reason ?? "")
            // Which sessions wait, and for how long — one quiet line each.
            VStack(spacing: 4) {
                ForEach(holds.byProject, id: \.project) { g in
                    HStack(spacing: 7) {
                        Circle().fill(g.provider.tint).frame(width: 7, height: 7)
                        Text(g.project).font(.system(size: 12.5, weight: .medium))
                        if g.count > 1 { Text("×\(g.count)").font(.system(size: 12)).foregroundStyle(.secondary) }
                        Spacer()
                        Text(Phrases.duration(Date().timeIntervalSince(g.since)))
                            .font(.system(size: 12)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 2)
            HStack(spacing: 8) {
                pill(L("Продолжить", "Continue"), fill: tint, text: Color.black.opacity(0.82)) { holds.releaseAll() }
                    .help(L("Агенты продолжат работу", "Agents go on with their work"))
                pill(L("+30 мин", "+30 min"), fill: tint.opacity(0.18), text: tint) { holds.releaseAndPause(model: model) }
                    .help(L("Продолжить и снять тормоз на 30 минут", "Continue and take the brake off for 30 minutes"))
                pill(L("Стоп", "Stop"), fill: Color.primary.opacity(0.09), text: .primary) { holds.stopAll() }
                    .help(L("Агенты аккуратно завершат ход и опишут, где остановились", "Agents wrap up their turn cleanly and describe where they stopped"))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.orange.opacity(0.28), lineWidth: 0.5))
    }

    /// A capsule button in the panel's own style: the same height and shape as the bars.
    private func pill(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .frame(height: Self.pillHeight)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// "1 агент ждёт", "3 агента ждут", "7 агентов ждут", "21 агент ждёт".
    private func agentsWord(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        let en = n == 1 ? "agent waits" : "agents wait"
        if m10 == 1 && m100 != 11 { return L("агент ждёт", en) }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return L("агента ждут", en) }
        return L("агентов ждут", en)
    }
}
