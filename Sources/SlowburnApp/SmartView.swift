import BudgetCore
import QuotaKit
import SwiftUI

/// What a limit means, worded once so every row says it the same way.
struct LimitWords {
    let row: LimitRow
    let blockedUntil: Date?

    var providerTitle: String { L("Лимит \(row.provider.company) · \(row.windowName)", "\(row.provider.company) limit · \(row.windowName)") }
    var providerValue: String { row.used >= 100 ? L("исчерпан", "used up") : L("ещё \(Fmt.pct(row.providerLeft))", "\(Fmt.pct(row.providerLeft)) left") }
    var providerDetail: String { L("Потрачено \(Fmt.pct(row.used)) · \(row.resetText)", "Spent \(Fmt.pct(row.used)) · \(row.resetText)") }
    var smartValue: String {
        if let until = blockedUntil { return L("после \(Phrases.time(until))", "after \(Phrases.time(until))") }
        if let a = row.available, a < 0 { return L("сверх плана \(Fmt.pct(-a))", "\(Fmt.pct(-a)) over plan") }
        return L("можно \(Fmt.dur(row.availableHours))", "\(Fmt.dur(row.availableHours)) available")
    }
    var smartDetail: String {
        if blockedUntil != nil { return L("Сначала должно открыться окно 5 часов", "The 5-hour window has to reopen first") }
        guard let allowed = row.planMarker else { return "" }
        if let a = row.available, a < 0 { return L("Ты впереди плана: сейчас положено \(Fmt.pct(allowed))", "You're ahead of plan: \(Fmt.pct(allowed)) allowed by now") }
        return L("По плану сейчас \(Fmt.pct(allowed)), у тебя \(Fmt.pct(row.used))", "Plan says \(Fmt.pct(allowed)) by now, you're at \(Fmt.pct(row.used))")
    }
    var smartAlert: Bool { blockedUntil != nil || (row.available ?? 0) < 0 }
    /// 0...1 of an 8-hour day of charge.
    var smartFraction: Double { blockedUntil != nil ? 0 : min(1, (row.availableHours ?? 0) / 8) }
    var reserveValue: String { Fmt.dur(row.batteryHours) }
    var reserveDetail: String { L("Копится, пока не работаешь · страховка \(Fmt.pct(row.margin ?? 0)) не раздаётся",
                                 "Builds up while you rest · \(Fmt.pct(row.margin ?? 0)) safety margin is kept back") }
    var reserveFraction: Double { min(1, (row.batteryHours ?? 0) / 5) }
}

/// One small ring standing alone, so it never blends into a neighbour.
struct MiniRing: View {
    var fraction: Double
    var color: Color
    var size: CGFloat = 22
    var line: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: line)
            Circle().trim(from: 0, to: max(0.02, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A table row with any leading mark: title and value on top, optional bar, plain-language detail under.
struct MetricRow<Leading: View>: View {
    @ViewBuilder var leading: Leading
    var title: String
    var value: String
    var valueColor: Color = .primary
    var detail: String
    var bar: LimitRow?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading.font(.system(size: 22, weight: .medium)).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 12))
                    Spacer()
                    Text(value).font(.rounded(12)).monospacedDigit().foregroundStyle(valueColor)
                }
                if let bar { ProviderBar(row: bar) }
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

extension Provider {
    /// Whose ceiling the provider limit is.
    var company: String { self == .claude ? "Anthropic" : "OpenAI" }
}

extension Presentation {
    /// A full short window (Codex 5 h) blocks the provider whatever the weekly plan says: when it reopens.
    func blockedUntil(_ provider: Provider) -> Date? {
        limits.filter { $0.provider == provider && $0.available == nil && $0.used >= 100 }.map(\.resetsAt).max()
    }
}

enum Fmt {
    static func pct(_ v: Double) -> String { Phrases.points(v) + "%" }
    static func dur(_ hours: Double?) -> String {
        guard let h = hours else { return "—" }
        if h < 1 { return L("\(max(0, Int((h * 60).rounded()))) мин", "\(max(0, Int((h * 60).rounded()))) min") }
        return "~" + Phrases.hours(h)
    }
}

/// Diagonal hatching, for parts of a bar that are held back rather than spent or available.
struct Stripes: Shape {
    var spacing: CGFloat = 4
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = r.minX - r.height
        while x < r.maxX {
            p.move(to: CGPoint(x: x, y: r.maxY))
            p.addLine(to: CGPoint(x: x + r.height, y: r.minY))
            x += spacing
        }
        return p
    }
}

/// The colours of the three layers, shared by every layout so they mean the same thing everywhere.
struct LayerStyle {
    let tint: Color
    var spent: Color { tint }
    var canNow: Color { tint.opacity(0.42) }
    var battery: Color { tint.opacity(0.75) }
    static let later = Color.primary.opacity(0.08)
    static let margin = Color.primary.opacity(0.28)
    static let over = Color.orange
}

/// The provider's window, 0–100 %: spent, the plan tick, and the safety reserve hatched at the end.
struct ProviderBar: View {
    let row: LimitRow

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(LayerStyle.later)
                    if let m = row.margin {
                        Stripes(spacing: 3).stroke(LayerStyle.margin, lineWidth: 1.2)
                            .frame(width: w * m / 100, height: 6).offset(x: w * (100 - m) / 100)
                    }
                    Capsule().fill(row.used >= 100 ? Color.red : row.provider.tint)
                        .frame(width: max(6, w * min(row.used, 100) / 100))
                }
                .frame(height: 6)
                .clipShape(Capsule())
                if let marker = row.planMarker {
                    Capsule().fill(Color.primary.opacity(0.7)).frame(width: 2, height: 12)
                        .offset(x: w * marker / 100 - 1)
                }
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Smart: questions instead of percentages

/// Answers "how much now", "how much today", "will it last", "how many hours of work" — provider limits become a footnote.
struct SmartLayout: View {
    let p: Presentation
    var activities: [Provider: Activity] = [:]
    var busy: [Provider: AgentBusy] = [:]
    /// "+" / "−" on the 5-hour bar: (provider, +1 or −1).
    var onBoost: ((Provider, Int) -> Void)? = nil
    /// The reserve's checkbox: (provider, on) — the 5-hour limit takes from the reserve on its own.
    var onAutoReserve: ((Provider, Bool) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(p.blobs) { blob in
                let rows = p.limits.filter { $0.provider == blob.provider }
                if let main = rows.first(where: { $0.smart != nil }) ?? rows.first {
                    card(blob: blob, main: main, rows: rows)
                }
            }
        }
    }

    /// One short phrase, traffic-light coloured: the whole answer for people who read nothing else.
    /// The why goes into `detail`, shown on the caption line — the title never wraps, so the popover keeps its height.
    struct Status {
        var text: String
        var color: Color
        var detail: String? = nil
    }

    static func status(blob: BlobModel, main: LimitRow, budget: WorkBudget?, blocked: Date?, paying: Bool) -> Status {
        if blob.mood == .unknown { return Status(text: L("Нет свежих данных", "No fresh data"), color: .secondary) }
        if let until = blocked {
            return Status(text: L("Пауза до \(Phrases.time(until))", "Paused until \(Phrases.time(until))"), color: paying ? .red : .orange,
                          detail: paying ? L("Codex сейчас платит credits.", "Codex is paying credits now.") : nil)
        }
        if let a = main.available, a < -1 {
            return Status(text: L("Притормози", "Slow down"), color: .orange, detail: L("Ты впереди плана недели на \(Fmt.pct(-a)).", "You're \(Fmt.pct(-a)) ahead of the week's plan."))
        }
        if let out = budget?.runsOutAt {
            return Status(text: L("Притормози", "Slow down"), color: .orange, detail: L("В твоём темпе неделя кончится \(Phrases.time(out)).", "At your pace the week runs out by \(Phrases.time(out))."))
        }
        if let norm = main.fiveHourBudget, norm > 0, let spent = main.spentThisSlot {
            let cap = main.fiveHourCap ?? norm // the norm, plus what you added from the reserve
            if spent > cap + 0.05 {
                // The capsule shows how far over and when it opens again: nothing to add below.
                return Status(text: L("Притормози", "Slow down"), color: .orange)
            }
        }
        if let left = budget?.leftoverAtReset, left >= 10 { return Status(text: L("Можно смелее", "Go bolder"), color: .green) }
        return Status(text: L("Работай спокойно", "Work at ease"), color: .green)
    }

    private func card(blob: BlobModel, main: LimitRow, rows: [LimitRow]) -> some View {
        let tint = blob.provider.tint
        let blocked = p.blockedUntil(blob.provider)
        let budget = WorkBudget.make(main, now: Date())
        let status = Self.status(blob: blob, main: main, budget: budget, blocked: blocked,
                                 paying: blob.provider == .codex && p.moneyNote != nil)
        let window = rows.first { $0.available == nil && $0.windowName.contains("5") }
        let others = rows.filter { $0.id != main.id && $0.id != window?.id && $0.used >= 50 }
        return VStack(alignment: .leading, spacing: 10) {
            header(blob: blob, status: status, main: main, window: window)
                .padding(.bottom, 4)
            if main.fiveHourBudget != nil {
                fiveHourCapsule(main, tint: tint)
            } else if let window {
                windowCapsule(window, tint: tint)
            }
            if let window, main.fiveHourBudget != nil, window.used >= 50 { windowCapsule(window, tint: tint) }
            weekCapsule(main, label: L("Неделя", "Week"), tint: tint)
            ForEach(others) { weekCapsule($0, label: $0.windowName.capitalizedFirst, tint: tint) }
            if main.planMarker != nil {
                reserveCapsule(main)
                autoReserveCheckbox(main)
            }
            caption(status: status, budget: budget)
        }
        // The slot right of the bars exists only for "+": without it the bars run to the card's edge.
        .environment(\.capsuleSlot, hasPlus(main))
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    /// Name, the traffic-light phrase as the card's title, when the week resets — and the blob, big.
    private func header(blob: BlobModel, status: Status, main: LimitRow, window: LimitRow?) -> some View {
        // Both resets as icon + time: the clock for the current 5-hour slot (when the next one starts from zero),
        // the calendar for the week. Then the provider's own window while it is low.
        func item(_ icon: String, _ text: String, help: String) -> some View {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(text)
            }
            .help(help)
        }
        let caption = HStack(spacing: 12) {
            if let next = main.fiveHourResetsAt {
                item("clock", Phrases.time(next),
                     help: L("Новые 5 часов с полной нормой начнутся в \(Phrases.time(next)); что не потратишь до этого — уйдёт в резерв",
                             "The next 5 hours start at \(Phrases.time(next)) with a full norm; whatever you leave unspent goes to the reserve"))
            }
            item("calendar", Phrases.time(main.resetsAt),
                 help: L("Сброс недели \(Phrases.time(main.resetsAt))", "The week resets \(Phrases.time(main.resetsAt))"))
            if let w = window, w.used < 50 {
                Text(L("окно \(main.provider.company) \(Int(w.used.rounded()))%", "\(main.provider.company) window \(Int(w.used.rounded()))%"))
            }
        }
        .font(.system(size: 12.5)).foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.8)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Phrases.providerName(blob.provider).uppercased())
                        .font(.system(size: 12, weight: .semibold)).tracking(0.3)
                        .foregroundStyle(.secondary)
                    if let activity = activities[blob.provider] {
                        let n = busy[blob.provider]?.sessions ?? 0
                        Text("· \(activity.name)" + (activity.isWork && n > 1 ? " · \(n)" : ""))
                            .font(.system(size: 12)).foregroundStyle(.tertiary).lineLimit(1)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: activity)
                    }
                }
                Text(status.text)
                    .font(.system(size: 24, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(status.color == .green ? Color.primary : status.color)
                    .lineLimit(1).minimumScaleFactor(0.7)
                caption
            }
            Spacer(minLength: 0)
            BlobView(provider: blob.provider, mood: blob.mood, level: 1, size: 60, activity: activities[blob.provider])
                .frame(width: 66, height: 66)
        }
    }

    private static let capsuleHeight: CGFloat = 34

    /// A thick capsule with its label and value inside; the slot on the right keeps every capsule the same width.
    private func capsule<Fill: View, Value: View, Accessory: View>(_ label: String, fillFraction: Double, help: String,
                                                                  @ViewBuilder fill: @escaping (CGFloat) -> Fill,
                                                                  @ViewBuilder value: () -> Value,
                                                                  @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 8) {
            bar(label, fillFraction: fillFraction, help: help, fill: fill, value: value)
            slot(accessory)
        }
    }

    /// The slot right of a bar: one circle wide on every row, so all bars end at the same x.
    private func slot<Accessory: View>(@ViewBuilder _ accessory: () -> Accessory) -> some View {
        CapsuleSlot(size: Self.capsuleHeight, content: accessory())
    }

    /// Whether this card's 5-hour bar shows "+": the only thing the slot is for.
    private func hasPlus(_ main: LimitRow) -> Bool {
        guard onBoost != nil, let norm = main.fiveHourBudget, norm > 0 else { return false }
        return main.boostStep > 0.05
    }

    /// The bar itself: label on the left, value on the right, fill drawn by the caller.
    private func bar<Fill: View, Value: View>(_ label: String, fillFraction: Double, help: String,
                                              @ViewBuilder fill: @escaping (CGFloat) -> Fill,
                                              @ViewBuilder value: () -> Value) -> some View {
        // The label sits on the fill when the fill reaches past it: dark text there, normal text on the track.
        let onFill = fillFraction > 0.24
        return ZStack(alignment: .leading) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.09))
                    fill(geo.size.width)
                }
            }
            HStack {
                Text(label).foregroundStyle(onFill ? Color.black.opacity(0.82) : Color.primary)
                Spacer(minLength: 6)
                value()
            }
            .font(.system(size: 13.5, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 14)
        }
        .frame(height: Self.capsuleHeight)
        .clipShape(Capsule())
        .help(help)
    }

    /// Our own 5-hour limit, one fixed slot of the week at a time. The bar is the slot's norm: 100 % fills it. Whatever goes past the norm is taken
    /// from the top-up added with "+", drawn as a second, smaller bar ("+22%") that fills in turn.
    private func fiveHourCapsule(_ main: LimitRow, tint: Color) -> some View {
        let norm = max(main.fiveHourBudget ?? 0, 0.0001)
        let spent = max(main.spentThisSlot ?? 0, 0)
        let cap = max(main.fiveHourCap ?? norm, norm)
        let extra = cap - norm
        let boosted = extra > 0.05
        let over = spent > cap + 0.05
        let step = main.boostStep
        let normFill = min(spent, norm) / norm
        let boostFill = boosted ? min(max(spent - norm, 0), extra) / extra : 0
        let barColor = over ? Color.orange : tint
        let dark = Color.black.opacity(0.82)
        // The top-up on the bar's own scale: % of the norm.
        let extraText = "+\(Int((extra / norm * 100).rounded()))%"
        var help = L("Лимит Slowburn на 5 часов: норма \(Fmt.pct(norm)) недели, потрачено \(Fmt.pct(spent)).",
                     "Slowburn's 5-hour limit: a norm of \(Fmt.pct(norm)) of the week, \(Fmt.pct(spent)) spent.")
        help += L(" Неделя поделена на 5-часовые отрезки с одинаковой нормой; непотраченное уходит в резерв.",
                  " The week is cut into 5-hour slots with the same norm; whatever is left unspent goes to the reserve.")
        if let next = main.fiveHourResetsAt {
            help += L(" Новый отрезок начнётся в \(Phrases.time(next)).", " The next slot starts at \(Phrases.time(next)).")
        }

        func number(_ ink: Color) -> some View {
            HStack(spacing: 5) {
                // Over everything: when it opens again, right next to the number.
                if over, let free = main.fiveHourFreesAt {
                    Text(L("до \(Phrases.time(free)) ·", "until \(Phrases.time(free)) ·")).font(.system(size: 12.5, weight: .medium)).opacity(0.75)
                }
                Text("\(Int((spent / norm * 100).rounded()))%")
            }
            .font(.system(size: 13.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(ink)
        }

        let auto = main.fiveHourAuto
        func pillLabel(_ ink: Color) -> some View {
            HStack(spacing: 8) {
                // Auto: the whole reserve backs the bar — how much that is, on the bar's scale; the checked box
                // below says it is automatic. Manual top-ups add ✕ to give them back.
                if auto {
                    Text(extraText).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                } else {
                    Text(extraText).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).opacity(0.7)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(height: Self.capsuleHeight)
        }

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                bar(L("5 часов", "5 hours"), fillFraction: normFill, help: help) { W in
                    let fillW = W * CGFloat(normFill)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(barColor).frame(width: fillW)
                        // The number may sit across the fill's edge: dark on the fill, light on the track.
                        number(dark).padding(.trailing, 14)
                            .frame(width: W, height: Self.capsuleHeight, alignment: .trailing)
                            .mask(alignment: .leading) { Rectangle().frame(width: fillW) }
                        number(Color.primary).padding(.trailing, 14)
                            .frame(width: W, height: Self.capsuleHeight, alignment: .trailing)
                            .mask(alignment: .trailing) { Rectangle().frame(width: max(0, W - fillW)) }
                    }
                } value: {
                    EmptyView()
                }
                if boosted {
                    // The top-up as its own small bar: fills once the norm is used up; click gives it back.
                    Button { if !auto { onBoost?(main.provider, -1) } } label: {
                        pillLabel(tint)
                            .background {
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(tint.opacity(0.18))
                                        Rectangle().fill(barColor).frame(width: g.size.width * CGFloat(boostFill))
                                    }
                                }
                            }
                            .overlay {
                                GeometryReader { g in
                                    pillLabel(dark).mask(alignment: .leading) {
                                        Rectangle().frame(width: g.size.width * CGFloat(boostFill))
                                    }
                                }
                            }
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help(L("Из резерва добавлено \(extraText) к норме (\(Fmt.pct(extra)) недели)",
                            "\(extraText) added to the norm from the reserve (\(Fmt.pct(extra)) of the week)")
                          + (main.boostUntil.map { L(" до \(Phrases.time($0))", " until \(Phrases.time($0))") } ?? "")
                          + L(", потрачено \(Int((boostFill * 100).rounded()))% добавки. ", ", \(Int((boostFill * 100).rounded()))% of the top-up spent. ")
                          + (auto ? L("Берётся из резерва сама — галочка у «Резерва» это выключает.",
                                      "Drawn from the reserve automatically — the checkbox under “Reserve” turns this off.")
                                  : L("Клик возвращает её в резерв.", "Click to return it to the reserve.")))
                }
            }
            slot {
                if step > 0.05, onBoost != nil {
                    Button { onBoost?(main.provider, 1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: Self.capsuleHeight, height: Self.capsuleHeight)
                            .background(Circle().fill(tint.opacity(0.18)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Добавить к этим 5 часам ещё \(Fmt.pct(step)) из резерва" + (main.fiveHourResetsAt.map { " — до \(Phrases.time($0))" } ?? ""),
                             "Add \(Fmt.pct(step)) from the reserve to these 5 hours" + (main.fiveHourResetsAt.map { ", until \(Phrases.time($0))" } ?? "")))
                } else {
                    Color.clear
                }
            }
        }
        .contextMenu {
            if boosted, !auto { Button(L("Убрать добавку из резерва", "Return the top-up to the reserve")) { onBoost?(main.provider, -1) } }
        }
    }

    /// The provider's own 5-hour window, when it matters.
    private func windowCapsule(_ w: LimitRow, tint: Color) -> some View {
        let full = w.used >= 100
        return capsule(L("Окно \(w.provider.company)", "\(w.provider.company) window"), fillFraction: min(w.used, 100) / 100,
                       help: full ? L("Окно \(w.provider.company) на 5 часов заполнено до \(Phrases.time(w.resetsAt))",
                                    "\(w.provider.company)'s 5-hour window is full until \(Phrases.time(w.resetsAt))")
                                  : L("Окно \(w.provider.company) на 5 часов: \(Int(w.used.rounded()))%, \(w.resetText)",
                                      "\(w.provider.company)'s 5-hour window: \(Int(w.used.rounded()))%, \(w.resetText)")) { W in
            Rectangle().fill(full ? Color.red : tint).frame(width: W * CGFloat(min(w.used, 100)) / 100)
        } value: {
            Text(full ? L("до \(Phrases.time(w.resetsAt))", "until \(Phrases.time(w.resetsAt))") : "\(Int(w.used.rounded()))%").foregroundStyle(full ? Color.red : Color.primary)
        } accessory: { Color.clear }
    }

    /// A week: filled = spent, the white tick = where the plan is now.
    private func weekCapsule(_ row: LimitRow, label: String, tint: Color) -> some View {
        var help = L("\(label) \(row.provider.company): потрачено \(Fmt.pct(row.used)), \(row.resetText).",
                     "\(label) \(row.provider.company): \(Fmt.pct(row.used)) spent, \(row.resetText).")
        if let plan = row.planMarker {
            help += L(" Засечка — где ты должен быть по плану сейчас (\(Fmt.pct(plan))).",
                      " The tick is where the plan says you should be now (\(Fmt.pct(plan))).")
        }
        return capsule(label, fillFraction: min(row.used, 100) / 100, help: help) { W in
            ZStack(alignment: .leading) {
                Rectangle().fill(tint).frame(width: W * CGFloat(min(row.used, 100)) / 100)
                if let plan = row.planMarker {
                    Rectangle().fill(Color.primary.opacity(0.9)).frame(width: 3).offset(x: W * CGFloat(min(plan, 100)) / 100 - 1.5)
                }
            }
        } value: {
            Text("\(Int(row.used.rounded()))%")
        } accessory: { Color.clear }
    }

    /// The reserve on the week's own scale (0–100 % of the week): green when saved up, orange when in debt.
    /// The share lent to the 5-hour limit with "+" is drawn lighter.
    private func reserveCapsule(_ main: LimitRow) -> some View {
        // What earlier slots left unspent (less what this slot took past its norm); in debt, how far.
        let gap = (main.available ?? 0) < 0 ? (main.available ?? 0) : (main.battery ?? 0)
        let debt = gap < 0
        let lent = max(0, min(main.fiveHourBoost ?? 0, gap))
        let auto = main.fiveHourAuto
        let help = debt
            ? L("Ты потратил на \(Fmt.pct(-gap)) больше, чем выдано по плану вместе с этими 5 часами.",
                "You've spent \(Fmt.pct(-gap)) more than the plan has handed out, these 5 hours included.")
            : auto ? L("Резерв — всё, что не потрачено в прошлых 5-часовых отрезках недели. Лимит на 5 часов берёт из него сам, сколько нужно.",
                       "Reserve: everything earlier 5-hour slots of the week left unspent. The 5-hour limit draws from it as needed.")
                   : L("Резерв — всё, что не потрачено в прошлых 5-часовых отрезках недели. Из него «+» добавляет к этим 5 часам.",
                       "Reserve: everything earlier 5-hour slots of the week left unspent. “+” moves some of it to these 5 hours.")
        return capsule(L("Резерв", "Reserve"), fillFraction: abs(gap) / 100, help: help) { W in
            let x: (Double) -> CGFloat = { max(0, W * CGFloat(min($0, 100)) / 100) }
            ZStack(alignment: .leading) {
                Rectangle().fill(debt ? Color.orange : Color.green).frame(width: x(abs(gap) - lent))
                if lent > 0.05 {
                    Rectangle().fill(Color.green.opacity(0.45)).frame(width: x(lent)).offset(x: x(gap - lent))
                }
            }
        } value: {
            HStack(spacing: 5) {
                Text(debt ? "−\(Fmt.pct(-gap))" : Fmt.pct(gap)).foregroundStyle(debt ? Color.orange : Color.green)
                // With the checkbox on, the checkbox itself says where the reserve goes: nothing to add here.
                if !auto, lent > 0.05 {
                    Text(L("· \(Phrases.points(lent)) в «5 часах»", "· \(Phrases.points(lent)) in “5 hours”")).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        } accessory: { Color.clear }
    }

    /// A plain checkbox with its words, under the reserve: what it does is in the label, not in a tooltip.
    @ViewBuilder private func autoReserveCheckbox(_ main: LimitRow) -> some View {
        if let onAutoReserve, main.fiveHourBudget != nil {
            let on = main.fiveHourAuto
            Button { onAutoReserve(main.provider, !on) } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(on ? Color.green : Color.clear)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(on ? Color.green : Color.secondary.opacity(0.7), lineWidth: 1.3)
                        if on {
                            Image(systemName: "checkmark").font(.system(size: 9.5, weight: .heavy))
                                .foregroundStyle(Color.black.opacity(0.8))
                        }
                    }
                    .frame(width: 15, height: 15)
                    Text(L("Брать из резерва автоматически", "Draw from the reserve automatically"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(on ? L("Лимит на 5 часов сам берёт из резерва сколько нужно — без «+», в каждом отрезке. Сними, чтобы добавлять вручную.",
                       "The 5-hour limit draws what it needs from the reserve — no “+”, in every slot. Uncheck to add by hand.")
                     : L("Когда норма на 5 часов кончится, работа продолжится за счёт резерва — без нажатий «+».",
                         "When the 5-hour norm runs out, work carries on from the reserve — no need to press “+”."))
            .accessibilityLabel(L("Брать из резерва автоматически", "Draw from the reserve automatically"))
            .accessibilityValue(on ? L("включено", "on") : L("выключено", "off"))
        }
    }

    /// One line under the capsules: why the status is what it is, or the forecast. Always one line high,
    /// even when empty, so the popover never changes height when the advice comes and goes.
    private func caption(status: Status, budget: WorkBudget?) -> some View {
        var line = " "
        var color = Color.secondary
        if let d = status.detail {
            line = d
            color = status.color == .green ? .secondary : status.color
        } else if let left = budget?.leftoverAtReset, left >= 10 {
            line = L("В твоём темпе к сбросу пропадёт ~\(Fmt.pct(left)).", "At your pace ~\(Fmt.pct(left)) will go unused by the reset.")
        }
        return Text(line).font(.system(size: 12.5)).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// Today's spend against the day's share, for the "Сегодня" row.
struct DayBar: View {
    var fraction: Double
    var tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LayerStyle.later)
                Capsule().fill(fraction > 1 ? Color.orange : tint).frame(width: geo.size.width * min(max(fraction, 0.02), 1))
            }
        }
        .frame(height: 5)
    }
}

private struct CapsuleSlotKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether bars keep a slot on the right (for "+"); off, they take the full width.
    var capsuleSlot: Bool {
        get { self[CapsuleSlotKey.self] }
        set { self[CapsuleSlotKey.self] = newValue }
    }
}

/// The slot right of a bar, one circle wide on every row so all bars end at the same x — or nothing at all
/// when no bar in the card needs it.
struct CapsuleSlot<Content: View>: View {
    var size: CGFloat
    var content: Content
    @Environment(\.capsuleSlot) private var shown

    var body: some View {
        if shown { content.frame(width: size, height: size) }
    }
}
