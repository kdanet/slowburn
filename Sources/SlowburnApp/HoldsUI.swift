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

    var body: some View {
        let count = holds.sessionsWaiting
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").font(.system(size: 18)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("\(count) \(agentsWord(count)) решения", "\(count) \(agentsWord(count)) for a decision"))
                        .font(.system(size: 13, weight: .semibold))
                    if let reason = holds.pending.first?.reason {
                        Text(reason).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(spacing: 4) {
                ForEach(holds.byProject, id: \.project) { g in
                    HStack(spacing: 6) {
                        Circle().fill(g.provider.tint).frame(width: 6, height: 6)
                        Text(g.project).font(.system(size: 11.5))
                        if g.count > 1 { Text("×\(g.count)").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer()
                        Text(L("ждёт \(Phrases.duration(Date().timeIntervalSince(g.since)))", "waiting \(Phrases.duration(Date().timeIntervalSince(g.since)))"))
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
            HStack(spacing: 6) {
                Button(L("Продолжить всех", "Continue all")) { holds.releaseAll() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L("+ 30 мин без тормоза", "+ 30 min, no brake")) { holds.releaseAndPause(model: model) }
                    .controlSize(.small)
                Spacer(minLength: 0)
                Button(L("Стоп", "Stop")) { holds.stopAll() }
                    .controlSize(.small)
                    .help(L("Агенты аккуратно завершат ход и опишут, где остановились", "Agents wrap up their turn cleanly and describe where they stopped"))
            }
            Text(holds.settings.releaseMode == .manual
                 ? L("Сами не продолжат: только по твоей кнопке. Через \(Int(holds.settings.maxWait / 60)) мин без решения — остановятся.",
                     "They won't continue on their own, only on your click. After \(Int(holds.settings.maxWait / 60)) min with no decision they stop.")
                 : L("Продолжат сами, когда вернётся бюджет, или по твоей кнопке.",
                     "They continue on their own when the budget returns, or on your click."))
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5))
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
