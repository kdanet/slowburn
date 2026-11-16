import AppKit
import BudgetCore
import QuotaKit
import SwiftUI

@MainActor
final class Model: ObservableObject {
    @Published var state: AppState?
    @Published var presentation: Presentation?
    @Published var menuImage: NSImage?
    @Published var refreshing = false
    /// What each blob is doing right now: the laptop while its agent works, a pastime otherwise.
    @Published var activities: [Provider: Activity] = [:]
    /// Agent sessions mid-turn, per provider.
    @Published var busy: [Provider: AgentBusy] = [:]
    let monitor = Monitor()
    private var timer: Timer?
    private var tick: Timer?
    private var activityTimer: Timer?
    private var scanning = false
    private var shownSince: [Provider: Date] = [:]

    init() {
        limitsOn = !MasterSwitch.isOff(paths: monitor.paths)
        apply(monitor.readState())
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        // Countdowns and "N s ago" move even between refreshes.
        tick = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.apply(self?.state) }
        }
        // Session logs move within seconds of a turn starting or ending; reading their tails is cheap.
        activityTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { await self?.scanActivity() }
        }
        Task { await scanActivity() }
    }

    func scanActivity() async {
        guard !scanning else { return }
        scanning = true
        let paths = monitor.paths
        let next = await Task.detached(priority: .utility) { AgentActivity.scan(paths: paths) }.value
        if next != busy { busy = next }
        updateActivities()
        scanning = false
    }

    private func updateActivities() {
        let now = Date()
        var next: [Provider: Activity] = [:]
        for p in Provider.allCases {
            let mood = presentation?.blob(p)?.mood ?? .unknown
            if let b = busy[p] {
                let want = Activity(work: b.work)
                // Hold a work step a few seconds, so quick hops between tools don't flicker.
                if let shown = activities[p], shown.isWork, shown != want,
                   let since = shownSince[p], now.timeIntervalSince(since) < 6 {
                    next[p] = shown
                } else {
                    next[p] = want
                }
            } else {
                next[p] = Activity.leisure(provider: p, mood: mood, now: now)
            }
            if next[p] != activities[p] { shownSince[p] = now }
        }
        if next != activities { activities = next }
    }

    func apply(_ next: AppState?) {
        state = next
        guard let next else { presentation = nil; return }
        let p = Presentation.make(next, now: Date())
        presentation = p
        updateActivities()
        menuImage = menuBarImage(provider: p.menuProvider, mood: p.menuMood, level: p.menuLevel)
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let monitor = self.monitor
        let next = await Task.detached { await monitor.refresh() }.value
        apply(next)
        refreshing = false
    }

    /// Limits paused for a while: no holds, warnings still on. nil when not paused.
    var pausedUntil: Date? {
        presentation?.overrideUntil.flatMap { $0 > Date() ? $0 : nil }
    }

    func setPaused(_ paused: Bool) {
        if paused { try? monitor.allow(minutes: Self.pauseMinutes) } else { monitor.clearOverride() }
        Task { await refresh() }
    }

    static let pauseMinutes: Double = 30

    /// "+" adds one norm (or the last of the savings) to the current 5-hour slot; "−" takes the last one back.
    func boost(_ provider: Provider, _ step: Int) {
        let now = Date()
        if step < 0 {
            Boosts.removeLast(provider, paths: monitor.paths, now: now)
        } else if let row = presentation?.limits.first(where: { $0.provider == provider && $0.fiveHourBudget != nil }) {
            Boosts.add(provider, amount: row.boostStep, paths: monitor.paths, now: now)
        }
        Task { await refresh() }
    }

    /// The big switch: off = hooks let everything through, nothing is held or warned about.
    @Published var limitsOn = true

    func setLimits(_ on: Bool) {
        MasterSwitch.set(on: on, paths: monitor.paths)
        limitsOn = !MasterSwitch.isOff(paths: monitor.paths)
    }

    /// The reserve's checkbox: let the 5-hour limit take from the reserve on its own.
    func setAutoReserve(_ provider: Provider, _ on: Bool) {
        AutoReserve.set(provider, on, paths: monitor.paths)
        Task { await refresh() }
    }

    func replan() {
        try? monitor.replan()
        Task { await refresh() }
    }
}

// MARK: - Pieces

extension Provider {
    var tint: Color { Palette.color(self) }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// System Settings–style grouped container: rows on one rounded surface, separated by inset hairlines.
struct InsetGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 26) }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: Model
    @ObservedObject var holds = HoldsModel.shared
    @ObservedObject var updates = Updates.shared
    /// Off for `--snapshot`: ImageRenderer cannot draw AppKit views.
    var anchored = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MasterSwitchCard(on: model.limitsOn, pausedUntil: model.pausedUntil,
                             set: { model.setLimits($0) }, pause: { model.setPaused($0) })
            // Switching off releases every hold, so the queue empties by itself.
            if !holds.pending.isEmpty { HoldQueueCard(holds: holds, model: model, snapshot: !anchored) }
            if let p = model.presentation {
                SmartLayout(p: p, activities: model.activities, busy: model.busy,
                            onBoost: { provider, step in model.boost(provider, step) },
                            onAutoReserve: { provider, on in model.setAutoReserve(provider, on) })
                    // Off: the numbers stay for reference, but they no longer steer anything.
                    .opacity(model.limitsOn ? 1 : 0.5)
                callouts(p)
            } else {
                HStack(spacing: 12) {
                    BlobView(provider: .claude, mood: .unknown, level: 1, size: 40)
                    Text(L("Собираю цифры…", "Gathering numbers…")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(14)
        .frame(width: 380)
        // MenuBarExtra windows do not always follow content that changes height (the hold card appearing,
        // a menu closing) and squeeze it instead. Always ask for the full natural height.
        .fixedSize(horizontal: false, vertical: true)
        .background { if anchored { TopAnchor() } }
        .background { if anchored { RoundedWindow(radius: 16) } }
        // Without the system shadow (see `RoundedWindow`) a hairline keeps the panel's edge visible on light backgrounds.
        .overlay {
            if anchored && RoundedWindow.systemShadowIgnoresShape {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Slowburn").font(.system(size: 13, weight: .semibold))
            Spacer()
            if let p = model.presentation {
                Text(model.refreshing ? L("обновляю…", "updating…") : L("обновлено \(p.freshText)", "updated \(p.freshText)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            if anchored {
                Menu {
                    Picker(L("Отпускать агентов", "Release agents"), selection: $holds.settings.releaseMode) {
                        ForEach(ReleaseMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Divider()
                    Button(L("Обновить сейчас", "Refresh now")) { Task { await model.refresh() } }
                        .keyboardShortcut("r")
                    Button(L("Перепланировать от текущего остатка", "Replan from what's left")) { model.replan() }
                    Divider()
                    if updates.available {
                        Button(L("Проверить обновления…", "Check for Updates…")) { updates.check() }
                            .disabled(!updates.canCheck)
                    }
                    if let v = updates.version {
                        Text("Slowburn \(v)")
                    }
                    Button(L("Выйти из Slowburn", "Quit Slowburn")) { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .focusEffectDisabled()
                .accessibilityLabel(L("Настройки", "Settings"))
            } else {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func callouts(_ p: Presentation) -> some View {
        if let note = p.moneyNote { callout(note, icon: "dollarsign.circle.fill", color: .yellow) }
        if let note = p.resetNote { callout(note, icon: "arrow.counterclockwise.circle.fill", color: .green) }
    }

    private func section(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private func callout(_ note: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(note + ".")
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.14)))
    }
}

@main
struct SlowburnApp: App {
    @StateObject private var model = Model()
    @StateObject private var holds = HoldsModel.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        let args = CommandLine.arguments
        if !args.contains(where: { $0.hasPrefix("--") }) {
            HookBinary.refresh()
            _ = Updates.shared // starts Sparkle's scheduled checks inside Slowburn.app
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Self.snapshot(to: args[i + 1])
        }
        if let i = args.firstIndex(of: "--export-ui"), i + 1 < args.count {
            IconExport.ui(to: args[i + 1])
        }
        if let i = args.firstIndex(of: "--export-clip"), i + 2 < args.count {
            IconExport.clip(to: args[i + 1], what: args[i + 2], seconds: i + 3 < args.count ? Double(args[i + 3]) ?? 4 : 4)
        }
        if let i = args.firstIndex(of: "--export-activities"), i + 2 < args.count {
            IconExport.activities(to: args[i + 1], names: args[i + 2].split(separator: ",").map(String.init))
        }
        if let i = args.firstIndex(of: "--export-icons"), i + 1 < args.count {
            IconExport.run(to: args[i + 1])
        }
        // Alerts and notifications show the app icon even though there is no Dock tile.
        NSApplication.shared.applicationIconImage = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { rect in
            let r = ImageRenderer(content: AppIconView(size: 512))
            r.scale = 1
            r.nsImage?.draw(in: rect)
            return true
        }
        if let i = args.firstIndex(of: "--moods"), i + 1 < args.count {
            Self.moodSheet(to: args[i + 1])
        }
        if let i = args.firstIndex(of: "--activities"), i + 1 < args.count {
            let only = i + 2 < args.count ? args[i + 2].split(separator: ",").map(String.init) : []
            Self.activitySheet(to: args[i + 1], only: only)
        }
    }

    /// `Slowburn --snapshot out` renders the popover in light and dark (out-light.png, out-dark.png) and exits.
    @MainActor
    static func snapshot(to base: String) {
        let model = Model()
        for scheme in [ColorScheme.dark, .light] {
            let bg = scheme == .dark ? Color(white: 0.17) : Color(white: 0.93)
            let renderer = ImageRenderer(content: PopoverView(model: model, anchored: false)
                .background(bg)
                .environment(\.colorScheme, scheme))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(base)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        exit(0)
    }

    /// `Slowburn --moods out.png` renders both blobs in every mood, large and at menu bar size, and exits.
    @MainActor
    static func moodSheet(to path: String) {
        let sheet = VStack(alignment: .leading, spacing: 24) {
            ForEach(Provider.allCases, id: \.self) { p in
                HStack(spacing: 28) {
                    ForEach(Mood.allCases, id: \.self) { mood in
                        VStack(spacing: 8) {
                            BlobView(provider: p, mood: mood, level: 1, size: 60, animate: false, effects: false)
                                .frame(width: 70, height: 70)
                            // The menu bar icon at a few charge levels, as macOS tints it on a dark bar.
                            HStack(spacing: 6) {
                                ForEach([1.0, 0.55, 0.15], id: \.self) { lvl in
                                    MenuRing(level: lvl, size: 18).colorInvert()
                                }
                            }
                            MenuRing(level: 0.7, size: 44).colorInvert()
                            Text(mood.name).font(.system(size: 10)).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(30)
        .background(Color(white: 0.17))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    /// `Slowburn --activities out.png [name,name…]` renders activities at a few moments, on dark and light, and exits.
    @MainActor
    static func activitySheet(to path: String, only: [String] = []) {
        let moments: [Double] = [0.3, 1.1, 2.4, 3.7, 6.2]
        let list = only.isEmpty ? Activity.allCases : only.compactMap(Activity.init(rawValue:))
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(list, id: \.self) { a in
                        HStack(spacing: 46) {
                            Text(a.name).font(.system(size: 11)).frame(width: 110, alignment: .leading)
                            ForEach(moments, id: \.self) { t in
                                BlobView(provider: Int(t * 10) % 2 == 0 ? .codex : .claude, mood: .calm, level: 1, size: 38,
                                         animate: false, activity: a, stillTime: t)
                                    .frame(width: 64, height: 64)
                            }
                        }
                    }
                }
                .padding(40)
                .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.93))
                .environment(\.colorScheme, scheme)
            }
        }
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            HStack(spacing: 3) {
                if let image = model.menuImage {
                    Image(nsImage: image)
                } else {
                    Image(systemName: "circle.dotted")
                }
                // Waiting agents outrank everything else in the menu bar: they need a click.
                Text(holds.pending.isEmpty ? (model.presentation?.menuLabel ?? "") : "⏸ \(holds.sessionsWaiting)")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}


// MARK: - Window anchoring

/// When the content changes height, the MenuBarExtra panel keeps its bottom edge and the top slides away
/// from the menu bar. This pins the top edge where the system first put it, so the panel grows and shrinks downwards.
struct TopAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        private var top: CGFloat?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            top = nil
            guard let window else { return }
            let nc = NotificationCenter.default
            // The system positions the panel right before showing it: remember that top edge.
            observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.top = window.frame.maxY
            })
            observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                guard let self, let top = self.top, abs(window.frame.maxY - top) > 0.5 else { return }
                window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
            })
            DispatchQueue.main.async { [weak self] in
                if self?.top == nil, window.isVisible { self?.top = window.frame.maxY }
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ nsView: AnchorView, context: Context) {}
}

/// Rounds the MenuBarExtra panel's corners: the window goes clear and its views are clipped to a rounded rect.
struct RoundedWindow: NSViewRepresentable {
    var radius: CGFloat

    /// From macOS 26 the panel's shadow no longer follows a clear window's content.
    static var systemShadowIgnoresShape: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    final class Probe: NSView {
        var radius: CGFloat = 16
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            guard let window else { return }
            // The panel's view tree is complete only after this pass; it is shown again on every click.
            DispatchQueue.main.async { [weak self] in self?.apply() }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                              queue: .main) { [weak self] _ in self?.apply() }
        }

        deinit { observer.map(NotificationCenter.default.removeObserver) }

        func apply() {
            guard let window, let content = window.contentView else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            func round(_ view: NSView) {
                view.wantsLayer = true
                view.layer?.cornerRadius = radius
                view.layer?.cornerCurve = .continuous
                view.layer?.masksToBounds = true
            }
            content.superview.map(round)
            round(content)
            // The panel's own backgrounds (blur and the dark fill) are full-size views of their own;
            // a backdrop layer ignores its parent's clipping, so each one is rounded too.
            for sub in content.subviews where sub.frame.size == content.bounds.size && sub.layer?.backgroundColor != nil {
                round(sub)
            }
            // Opening the panel would otherwise put keyboard focus (and its ring) on the first control, the gear.
            // With keyboard navigation on, AppKit and SwiftUI pick that control after the window becomes key,
            // so the focus is dropped again once they are done; Tab still reaches every control.
            window.makeFirstResponder(nil)
            for delay in [0.0, 0.05, 0.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in window?.makeFirstResponder(nil) }
            }
            if RoundedWindow.systemShadowIgnoresShape {
                // The window server draws this panel's shadow, with its light rim, along the window's own nearly
                // square corners whatever the content's shape: they stick out past ours as pale wedges.
                // No system shadow; the panel draws its own edge (see `PopoverView`).
                window.hasShadow = false
                return
            }
            window.invalidateShadow()
            // The shadow follows the window's shape once it has drawn: recompute after the first frames.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { window.invalidateShadow() }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let v = Probe()
        v.radius = radius
        return v
    }

    func updateNSView(_ nsView: Probe, context: Context) {}
}

/// The big switch at the top: limits and hooks on, or everything let through.
struct MasterSwitchCard: View {
    var on: Bool
    /// Paused for a while: agents are not held, warnings stay. Only while `on`.
    var pausedUntil: Date?
    var set: (Bool) -> Void
    var pause: (Bool) -> Void

    private var paused: Bool { on && pausedUntil != nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let tint: Color? = !on ? .orange : paused ? .yellow : nil
        return VStack(alignment: .leading, spacing: 8) {
            Button { set(!on) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        // Two lines in every state, so the card keeps its height.
                        Text(subtitle)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                    }
                    Spacer(minLength: 8)
                    BigSwitch(on: on)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Ограничения", "Limits"))
            .accessibilityValue(!on ? L("выключены", "off") : paused ? L("приостановлены", "paused") : L("включены", "on"))
            .accessibilityAddTraits(.isButton)

            // Pausing is for "let me finish this": half an hour, then the limits are back by themselves.
            Button { pause(!paused) } label: {
                Label(paused ? L("Вернуть сейчас", "Resume now")
                             : L("Приостановить на \(Int(Model.pauseMinutes)) мин", "Pause for \(Int(Model.pauseMinutes)) min"),
                      systemImage: paused ? "play.circle" : "pause.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Off has nothing to pause; the row keeps its place so the panel does not change height.
            .opacity(on ? 1 : 0)
            .disabled(!on)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(shape.fill(tint.map { $0.opacity(0.14) } ?? Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(tint.map { $0.opacity(0.35) } ?? Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var title: String {
        if !on { return L("Ограничения выключены", "Limits off") }
        if let until = pausedUntil { return L("Приостановлены до \(Phrases.time(until))", "Paused until \(Phrases.time(until))") }
        return L("Ограничения включены", "Limits on")
    }

    private var subtitle: String {
        if !on { return L("Slowburn только считает: агенты работают без пауз и предупреждений", "Slowburn only counts: agents run with no pauses or warnings") }
        if paused { return L("Агенты работают без пауз, предупреждения остаются", "Agents run with no pauses; warnings stay on") }
        return L("Ставят агентов на паузу, когда тратишь больше нормы", "Pause agents when you spend more than the norm")
    }
}

/// A large on/off switch drawn by hand, so it looks the same in the popover and in snapshots.
struct BigSwitch: View {
    var on: Bool

    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Color.green : Color.primary.opacity(0.18))
            Circle().fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .padding(3)
        }
        .frame(width: 52, height: 30)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: on)
    }
}
