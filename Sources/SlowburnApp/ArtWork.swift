import BudgetCore
import SwiftUI

// Work: always at the laptop, with a prop for what the agent is doing.

extension Motion {
    mutating func poseTyping(_ t: Double) {
        atLaptop(t)
    }

    mutating func poseCoding(_ t: Double) {
        atLaptop(t)
        // A glance up-right as each snippet pops out of the screen.
        let q = phase(t, WorkTiming.codePeriod / 2)
        let w = bump(min(q / 0.5, 1))
        lookX += 3 * w
        lookY -= 3 * w
    }

    mutating func poseSearching(_ t: Double) {
        atLaptop(t)
        let p = WorkTiming.lens(t)
        lookX = (p.x - 50) / 5
        lookY = 5
        rot += (p.x - 50) / 12
    }

    mutating func poseTerminal(_ t: Double) {
        atLaptop(t)
        // Now and then a look over at the prompt, top left.
        let w = smooth((phase(t, 5) - 0.55) / 0.1) * (1 - smooth((phase(t, 5) - 0.85) / 0.1))
        lookX = lookX * (1 - w) - 4.5 * w
        lookY = lookY * (1 - w) - 4 * w
    }

    mutating func poseTesting(_ t: Double) {
        atLaptop(t)
        let q = phase(t, WorkTiming.testPeriod)
        let w = smooth((q - 0.0) / 0.06) * (1 - smooth((q - 0.86) / 0.1))
        let x = -4 + 8 * smooth((q - 0.04) / 0.45)
        lookX = lookX * (1 - w) + x * w
        lookY = lookY * (1 - w) - 5 * w
    }

    mutating func poseBuilding(_ t: Double) {
        atLaptop(t)
        let w = bump(phase(t, 6) / 0.4) * (phase(t, 6) < 0.4 ? 1 : 0)
        lookX = lookX * (1 - w) + 5 * w
        lookY = lookY * (1 - w) - 5 * w
    }

    mutating func poseShipping(_ t: Double) {
        atLaptop(t)
        let h = WorkTiming.rocket(t).lift
        let w = smooth(h / 12)
        lookX = lookX * (1 - w) + 5 * w
        lookY = lookY * (1 - w) + (2 - 8 * smooth(h / 80)) * w
        dy -= 1.5 * w
    }

    mutating func poseBrowsing(_ t: Double) {
        atLaptop(t)
        let w = smooth((phase(t, 4.5) - 0.5) / 0.1) * (1 - smooth((phase(t, 4.5) - 0.88) / 0.1))
        lookX = lookX * (1 - w) + 5 * w
        lookY = lookY * (1 - w) - 5 * w
    }

    mutating func poseDelegating(_ t: Double) {
        atLaptop(t)
        // Eyes ride along with each note to the helper.
        let q = phase(t, WorkTiming.notePeriod)
        let w = bump(q / 0.7) * (q < 0.7 ? 1 : 0)
        lookX = lookX * (1 - w) + 5.5 * w
        lookY = lookY * (1 - w) + 2 * w
        rot += 2 * w
    }

    mutating func poseThinking(_ t: Double) {
        let base = self
        atLaptop(t)
        // Slow, thoughtful pecking; eyes up on the idea.
        dy = base.dy - 0.5 * abs(sin(tau * t * 0.9))
        lookX = 1.2 * sin(tau * t / 5)
        lookY = -5
        rot = -1 + base.rot * 0.4
    }

    mutating func posePlanning(_ t: Double) {
        atLaptop(t)
        // Over to the clipboard as each line is ticked, back to the screen in between.
        let q = phase(t, WorkTiming.planPeriod)
        var w = 0.0
        for a in WorkTiming.planTicks { w = max(w, bump((q - a + 0.06) / 0.2)) }
        lookX = lookX * (1 - w) + 5.5 * w
        lookY = lookY * (1 - w) - 1 * w
    }

    mutating func poseDebugging(_ t: Double) {
        atLaptop(t)
        let b = WorkTiming.bug(t)
        lookX = (b.p.x - 50) / 4.5
        lookY = 5
        rot += 1.5 * sin(tau * t / 0.9)
    }

    mutating func poseAsking(_ t: Double) {
        let base = self
        atLaptop(t)
        // Hands off the keys: looking at you, leaning a little, bobbing while it waits.
        lookX = 0.8 * sin(tau * t / 6)
        lookY = 0
        rot = 4 + base.rot * 0.5
        dy = base.dy - 1.4 * (1 + sin(tau * t / 1.6)) / 2
    }
}

extension ActivityProps {
    func drawTyping(_ ctx: inout GraphicsContext) {
        if layer == .front { laptop(&ctx) }
    }

    func drawCoding(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        codeSnippets(&ctx)
        laptop(&ctx, dots: false)
    }

    func drawSearching(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        magnifier(&ctx)
    }

    func drawTerminal(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        prompt(&ctx)
    }

    func drawTesting(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        checks(&ctx)
    }

    func drawBuilding(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        gears(&ctx)
    }

    func drawShipping(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        rocket(&ctx)
    }

    func drawBrowsing(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        globe(&ctx)
    }

    func drawDelegating(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        helper(&ctx)
    }

    func drawThinking(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        bulb(&ctx)
    }

    func drawPlanning(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        clipboard(&ctx)
    }

    func drawDebugging(_ ctx: inout GraphicsContext) {
        if layer == .held { sweat(&ctx) }
        if layer == .front {
            laptop(&ctx, dots: false)
            bug(&ctx)
        }
    }

    func drawAsking(_ ctx: inout GraphicsContext) {
        guard layer == .front else { return }
        laptop(&ctx, dots: false)
        question(&ctx)
    }


    // MARK: Pieces

    func laptop(_ ctx: inout GraphicsContext, dots: Bool = true) {
        // Seen from behind: the lid faces us, the base is a thin slab on the "table".
        let lid = Path(roundedRect: CGRect(x: 20, y: 58, width: 60, height: 36), cornerRadius: 5, style: .continuous)
        ctx.fill(lid, with: .color(PropInk.metal))
        ctx.stroke(lid, with: .color(PropInk.metalEdge), lineWidth: 2.2)
        // A glowing logo in the provider's colour.
        let glow = 0.75 + 0.25 * sin(2 * .pi * t / 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: 45, y: 71, width: 10, height: 10)), with: .color(tint.opacity(glow)))
        let base = Path(roundedRect: CGRect(x: 12, y: 93, width: 76, height: 6), cornerRadius: 3, style: .continuous)
        ctx.fill(base, with: .color(PropInk.metalEdge))
        // Typing dots popping above the lid.
        guard dots else { return }
        for i in 0..<3 {
            let p = (t * 1.6 - Double(i) * 0.18).truncatingRemainder(dividingBy: 1)
            let lift = p < 0.5 ? sin(.pi * p / 0.5) : 0
            let r: CGFloat = 3.2
            let c = CGPoint(x: 92 + CGFloat(i) * 9, y: 18 - 4 * lift)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(tint.opacity(0.45 + 0.55 * lift)))
        }
    }

    private func codeSnippets(_ ctx: inout GraphicsContext) {
        // Little editor tiles rise out of the screen, behind the lid's top edge, and drift up and away.
        let marks = ["</>", "{ }"]
        for i in 0..<2 {
            let q = phase(t + Double(i) * WorkTiming.codePeriod / 2, WorkTiming.codePeriod)
            let c = CGPoint(x: 88 + 20 * q, y: 68 - 70 * smooth(q * 1.1))
            let s = 0.75 + 0.25 * smooth(q / 0.25)
            let alpha = q > 0.75 ? (1 - q) / 0.25 : 1
            var c2 = ctx
            c2.opacity = alpha
            c2.translateBy(x: c.x, y: c.y)
            c2.scaleBy(x: s, y: s)
            c2.rotate(by: .degrees(-8 + 10 * q))
            let tile = Path(roundedRect: CGRect(x: -16, y: -10, width: 32, height: 20), cornerRadius: 5, style: .continuous)
            c2.fill(tile, with: .color(WorkInk.screen))
            c2.stroke(tile, with: .color(tint), lineWidth: 1.8)
            label(&c2, marks[i], at: .zero, size: 14, color: tint, weight: .heavy, design: .monospaced)
        }
    }

    private func magnifier(_ ctx: inout GraphicsContext) {
        let p = WorkTiming.lens(t)
        let r: CGFloat = 11
        var handle = Path(); handle.move(to: CGPoint(x: p.x + 8, y: p.y + 8)); handle.addLine(to: CGPoint(x: p.x + 17, y: p.y + 17))
        ctx.stroke(handle, with: .color(WorkInk.handle), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        let lens = circle(p, r)
        ctx.fill(lens, with: .color(PropInk.water.opacity(0.45)))
        var glint = Path()
        glint.addArc(center: p, radius: r - 4, startAngle: .degrees(200), endAngle: .degrees(260), clockwise: false)
        ctx.stroke(glint, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.stroke(lens, with: .color(WorkInk.handle), lineWidth: 3.2)
    }

    private func prompt(_ ctx: inout GraphicsContext) {
        // A tiny terminal window up on the left, talking to the blob: ">_" with a blinking cursor.
        let box = CGRect(x: -16, y: -8, width: 38, height: 26)
        var tail = Path()
        tail.move(to: CGPoint(x: 8, y: 16)); tail.addLine(to: CGPoint(x: 20, y: 26)); tail.addLine(to: CGPoint(x: 17, y: 15))
        tail.closeSubpath()
        let win = Path(roundedRect: box, cornerRadius: 6, style: .continuous)
        ctx.fill(tail, with: .color(WorkInk.screen))
        ctx.stroke(tail, with: .color(cord), lineWidth: 1.6)
        ctx.fill(win, with: .color(WorkInk.screen))
        ctx.stroke(win, with: .color(cord), lineWidth: 1.6)
        label(&ctx, ">", at: CGPoint(x: -7, y: 4.5), size: 16, color: WorkInk.prompt, weight: .heavy, design: .monospaced)
        if phase(t, 1.0) < 0.55 {
            ctx.fill(Path(roundedRect: CGRect(x: 1, y: 9, width: 11, height: 3.4), cornerRadius: 1), with: .color(WorkInk.prompt))
        }
    }

    private func checks(_ ctx: inout GraphicsContext) {
        // Three results pop in a row above the head; every third run the last one fails.
        let q = phase(t, WorkTiming.testPeriod)
        let run = Int((t / WorkTiming.testPeriod).rounded(.down))
        let fade = 1 - smooth((q - 0.88) / 0.1)
        for i in 0..<3 {
            let start = 0.04 + 0.2 * Double(i)
            let k = (q - start) / 0.1
            guard k > 0 else { continue }
            let s = k < 1 ? smooth(k) * (1 + 0.25 * sin(.pi * k)) : 1
            let fail = i == 2 && run % 3 == 1
            var c = ctx
            c.opacity = fade
            c.translateBy(x: 27 + 23 * CGFloat(i), y: -10)
            c.scaleBy(x: s, y: s)
            c.scaleBy(x: 1.18, y: 1.18)
            c.fill(circle(.zero, 8.5), with: .color(fail ? PropInk.bad : WorkInk.pass))
            if fail {
                c.stroke(segment(CGPoint(x: -3.6, y: -3.6), CGPoint(x: 3.6, y: 3.6)), with: .color(.white),
                         style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                c.stroke(segment(CGPoint(x: 3.6, y: -3.6), CGPoint(x: -3.6, y: 3.6)), with: .color(.white),
                         style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            } else {
                var tick = Path()
                tick.move(to: CGPoint(x: -4.2, y: 0.2)); tick.addLine(to: CGPoint(x: -1.2, y: 3.4)); tick.addLine(to: CGPoint(x: 4.4, y: -3.4))
                c.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func gears(_ ctx: inout GraphicsContext) {
        // Two gears meshing up on the right: a big grey one driving a small one in the provider's colour.
        let a = tau * t / 4
        let dir = Double.pi / 4
        let big = CGPoint(x: 90, y: -1), rBig: CGFloat = 13
        let rSmall: CGFloat = 9.75
        let small = CGPoint(x: big.x + (rBig + rSmall) * CGFloat(cos(dir)), y: big.y + (rBig + rSmall) * CGFloat(sin(dir)))
        let b = -(a - dir) * 8 / 6 + dir + .pi + .pi / 6
        ctx.fill(gear(at: small, pitch: rSmall, teeth: 6, angle: b), with: .color(tint), style: FillStyle(eoFill: true))
        ctx.stroke(gear(at: small, pitch: rSmall, teeth: 6, angle: b), with: .color(PropInk.metalEdge), lineWidth: 1.6)
        ctx.fill(gear(at: big, pitch: rBig, teeth: 8, angle: a), with: .color(PropInk.metal), style: FillStyle(eoFill: true))
        ctx.stroke(gear(at: big, pitch: rBig, teeth: 8, angle: a), with: .color(PropInk.metalEdge), lineWidth: 1.6)
    }

    private func gear(at c: CGPoint, pitch: CGFloat, teeth n: Int, angle: Double) -> Path {
        let root = pitch - 2.4, tip = pitch + 3, step = tau / Double(n)
        func pt(_ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))) }
        var p = Path()
        for i in 0..<n {
            let a = angle + Double(i) * step
            let pts = [pt(root, a - step * 0.5), pt(root, a - step * 0.3), pt(tip, a - step * 0.19),
                       pt(tip, a + step * 0.19), pt(root, a + step * 0.3)]
            for (j, q) in pts.enumerated() { if i == 0 && j == 0 { p.move(to: q) } else { p.addLine(to: q) } }
        }
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: c.x - pitch * 0.26, y: c.y - pitch * 0.26, width: pitch * 0.52, height: pitch * 0.52))
        return p
    }

    private func rocket(_ ctx: inout GraphicsContext) {
        let r = WorkTiming.rocket(t)
        let pad = CGPoint(x: 106, y: 97)
        // Launch pad, and a puff of smoke while lifting off.
        ctx.fill(Path(roundedRect: CGRect(x: 94, y: 97, width: 24, height: 4), cornerRadius: 2), with: .color(PropInk.metalEdge))
        if r.lift > 0 {
            let puff = min(r.lift / 60, 1)
            for side in [CGFloat(-1), 0, 1] {
                let c = CGPoint(x: pad.x + side * (5 + 9 * puff), y: pad.y - 3 - 5 * puff - (side == 0 ? 3 : 0))
                ctx.fill(circle(c, 4 + 3 * puff), with: .color(PropInk.steam.opacity(0.75 * (1 - puff))))
            }
        }
        var c = ctx
        c.opacity = r.alpha
        let shake = r.lift == 0 ? 0.5 * sin(t * 60) : 0
        c.translateBy(x: pad.x + shake, y: pad.y - 5 - r.lift)
        c.scaleBy(x: 1.2, y: 1.2)
        // Flame: flickers on the pad, roars in flight.
        let roar = r.lift > 0 ? 1.0 : 0.45
        let len = CGFloat(roar * (8 + 3 * sin(t * 37) + 2 * sin(t * 23)))
        var flame = Path()
        flame.move(to: CGPoint(x: -4.5, y: 0)); flame.addQuadCurve(to: CGPoint(x: 0, y: len + 4), control: CGPoint(x: -4, y: len * 0.6))
        flame.addQuadCurve(to: CGPoint(x: 4.5, y: 0), control: CGPoint(x: 4, y: len * 0.6)); flame.closeSubpath()
        c.fill(flame, with: .color(PropInk.fire))
        c.fill(flame.applying(CGAffineTransform(scaleX: 0.5, y: 0.55)), with: .color(PropInk.star))
        // Fins, body, window.
        for s in [CGFloat(-1), 1] {
            var fin = Path()
            fin.move(to: CGPoint(x: 5 * s, y: -11)); fin.addLine(to: CGPoint(x: 11 * s, y: 1)); fin.addLine(to: CGPoint(x: 5 * s, y: -1))
            fin.closeSubpath()
            c.fill(fin, with: .color(tint))
            c.stroke(fin, with: .color(cord), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
        var body = Path()
        body.move(to: CGPoint(x: -6, y: 0)); body.addLine(to: CGPoint(x: -6, y: -14))
        body.addQuadCurve(to: CGPoint(x: 0, y: -28), control: CGPoint(x: -6, y: -23))
        body.addQuadCurve(to: CGPoint(x: 6, y: -14), control: CGPoint(x: 6, y: -23))
        body.addLine(to: CGPoint(x: 6, y: 0)); body.closeSubpath()
        c.fill(body, with: .color(PropInk.paper))
        c.stroke(body, with: .color(cord), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        c.fill(circle(CGPoint(x: 0, y: -14), 3.2), with: .color(PropInk.cover))
    }

    private func globe(_ ctx: inout GraphicsContext) {
        // A turning globe up on the right: meridians slide across, land drifts by.
        let c = CGPoint(x: 103, y: 4), r: CGFloat = 14
        let disc = circle(c, r)
        ctx.fill(disc, with: .color(PropInk.water))
        var inside = ctx
        inside.clip(to: disc)
        let spin = tau * t / 6
        for (lon, lat, size) in [(0.0, -5.0, 7.0), (2.2, 5.0, 8.0), (4.1, -2.0, 6.5)] {
            let a = lon + spin
            guard cos(a) > -0.2 else { continue }
            let x = c.x + r * 0.85 * CGFloat(sin(a))
            let w = CGFloat(size) * CGFloat(max(cos(a), 0.15))
            inside.fill(Path(ellipseIn: CGRect(x: x - w, y: c.y + CGFloat(lat) - CGFloat(size) * 0.6, width: 2 * w, height: CGFloat(size) * 1.2)),
                        with: .color(PropInk.leaf))
        }
        let line = WorkInk.ocean
        for k in 0..<3 {
            let a = (spin + Double(k) * .pi / 3).truncatingRemainder(dividingBy: .pi)
            let hw = r * CGFloat(abs(cos(a)))
            inside.stroke(Path(ellipseIn: CGRect(x: c.x - hw, y: c.y - r, width: 2 * hw, height: 2 * r)), with: .color(line), lineWidth: 1.6)
        }
        inside.stroke(segment(CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x + r, y: c.y)), with: .color(line), lineWidth: 1.6)
        ctx.stroke(disc, with: .color(line), lineWidth: 2)
    }

    private func helper(_ ctx: inout GraphicsContext) {
        // A little helper in the provider's colour at its own laptop; notes fly over to it.
        let bob = CGFloat(-0.8 * abs(sin(tau * t * 1.4)))
        let box = CGRect(x: 90, y: 58 + bob, width: 34, height: 34)
        let codex = tint == Palette.color(.codex)
        let shape = codex ? CodexShape().path(in: box) : ClaudeShape().path(in: box)
        ctx.fill(shape, with: .color(tint))
        for x in [CGFloat(0.37), 0.63] {
            let e = CGRect(x: box.minX + box.width * x - 2.8, y: box.minY + box.height * 0.47 - 5, width: 5.6, height: 10)
            ctx.fill(Path(roundedRect: e, cornerRadius: 2.8), with: .color(Palette.ink))
        }
        let lid = Path(roundedRect: CGRect(x: 96, y: 79, width: 24, height: 14), cornerRadius: 3)
        ctx.fill(lid, with: .color(PropInk.metal))
        ctx.stroke(lid, with: .color(PropInk.metalEdge), lineWidth: 1.6)
        ctx.fill(Path(roundedRect: CGRect(x: 91, y: 92, width: 34, height: 4), cornerRadius: 2), with: .color(PropInk.metalEdge))
        // A note arcs from the big blob over to the helper.
        let q = phase(t, WorkTiming.notePeriod)
        guard q < 0.7 else { return }
        let k = q / 0.7
        let p = CGPoint(x: 80 + 27 * CGFloat(k), y: 40 - 30 * CGFloat(bump(k)) + 20 * CGFloat(k))
        var n = ctx
        n.opacity = min(k / 0.15, 1) * min((1 - k) / 0.15, 1)
        n.translateBy(x: p.x, y: p.y)
        n.rotate(by: .degrees(-20 + 40 * k))
        let sheet = Path(roundedRect: CGRect(x: -6, y: -7, width: 12, height: 14), cornerRadius: 1.5)
        n.fill(sheet, with: .color(PropInk.paper))
        n.stroke(sheet, with: .color(cord), lineWidth: 1.4)
        for i in 0..<2 {
            let y = CGFloat(-2.5 + 4.5 * Double(i))
            n.stroke(segment(CGPoint(x: -3, y: y), CGPoint(x: 3, y: y)), with: .color(tint), lineWidth: 1.6)
        }
    }

    private func bulb(_ ctx: inout GraphicsContext) {
        // A light bulb above the head that warms up and glows.
        let glow = 0.5 + 0.5 * sin(tau * t / 1.8)
        var ctx = ctx
        ctx.translateBy(x: 50, y: 11)
        ctx.scaleBy(x: 1.15, y: 1.15)
        ctx.translateBy(x: -50, y: -5)
        let c = CGPoint(x: 50, y: -12)
        for f in [1.08, 1.3, 1.7, 1.92] {
            let a = Double.pi * f
            let d1 = 12.5 + CGFloat(glow), d2 = 15 + 2 * CGFloat(glow)
            ctx.stroke(segment(CGPoint(x: c.x + d1 * CGFloat(cos(a)), y: c.y + d1 * CGFloat(sin(a))),
                               CGPoint(x: c.x + d2 * CGFloat(cos(a)), y: c.y + d2 * CGFloat(sin(a)))),
                       with: .color(star.opacity(0.4 + 0.6 * glow)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        var glass = Path()
        glass.move(to: CGPoint(x: c.x - 5, y: c.y + 10))
        glass.addCurve(to: CGPoint(x: c.x, y: c.y - 10), control1: CGPoint(x: c.x - 6, y: c.y + 3), control2: CGPoint(x: c.x - 12, y: c.y - 10))
        glass.addCurve(to: CGPoint(x: c.x + 5, y: c.y + 10), control1: CGPoint(x: c.x + 12, y: c.y - 10), control2: CGPoint(x: c.x + 6, y: c.y + 3))
        glass.closeSubpath()
        ctx.fill(glass, with: .color(Color(hex: 0xFFF3C4)))
        ctx.fill(glass, with: .color(PropInk.star.opacity(0.35 + 0.65 * glow)))
        ctx.stroke(glass, with: .color(cord), lineWidth: 1.6)
        var fil = Path()
        fil.move(to: CGPoint(x: c.x - 3, y: c.y + 8)); fil.addLine(to: CGPoint(x: c.x - 3, y: c.y - 1))
        fil.addLine(to: CGPoint(x: c.x, y: c.y + 2)); fil.addLine(to: CGPoint(x: c.x + 3, y: c.y - 1)); fil.addLine(to: CGPoint(x: c.x + 3, y: c.y + 8))
        ctx.stroke(fil, with: .color(PropInk.fire.opacity(0.5 + 0.5 * glow)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        let cap = Path(roundedRect: CGRect(x: c.x - 5.5, y: c.y + 10, width: 11, height: 7), cornerRadius: 2)
        ctx.fill(cap, with: .color(PropInk.metal))
        ctx.stroke(cap, with: .color(PropInk.metalEdge), lineWidth: 1.6)
    }

    private func clipboard(_ ctx: inout GraphicsContext) {
        // A clipboard on the right; the plan's lines get ticked one by one.
        var c = ctx
        c.translateBy(x: 108, y: 44)
        c.rotate(by: .degrees(6))
        let board = Path(roundedRect: CGRect(x: -14, y: -21, width: 28, height: 42), cornerRadius: 3.5)
        c.fill(board, with: .color(PropInk.wood))
        c.stroke(board, with: .color(Color(hex: 0x6E4826)), lineWidth: 1.6)
        c.fill(Path(roundedRect: CGRect(x: -11, y: -16, width: 22, height: 34), cornerRadius: 1.5), with: .color(PropInk.paper))
        c.fill(Path(roundedRect: CGRect(x: -6, y: -24, width: 12, height: 7), cornerRadius: 2), with: .color(PropInk.metalEdge))
        let q = phase(t, WorkTiming.planPeriod)
        for (i, at) in WorkTiming.planTicks.enumerated() {
            let y = CGFloat(-8 + 10 * i)
            c.stroke(Path(CGRect(x: -8, y: y - 3, width: 6, height: 6)), with: .color(PropInk.metalEdge), lineWidth: 1.4)
            c.stroke(segment(CGPoint(x: 1, y: y), CGPoint(x: 8, y: y)), with: .color(PropInk.steam), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let k = (q - at) / 0.08
            guard k > 0, q < 0.94 else { continue }
            let s = CGFloat(min(k, 1))
            var tick = Path()
            tick.move(to: CGPoint(x: -8, y: y - 0.5))
            tick.addLine(to: CGPoint(x: -5.5, y: y + 2.5))
            tick.addLine(to: CGPoint(x: -5.5 + 7 * s, y: y + 2.5 - 9 * s))
            c.stroke(tick, with: .color(WorkInk.passDeep), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
    }

    private func bug(_ ctx: inout GraphicsContext) {
        // A ladybird-ish bug wandering over the lid, legs scuttling.
        let b = WorkTiming.bug(t)
        var c = ctx
        c.translateBy(x: b.p.x, y: b.p.y)
        c.rotate(by: .radians(b.heading))
        let ink = Color(hex: 0x2A2626)
        for i in 0..<3 {
            let x = CGFloat(-4 + 4 * i)
            let w = CGFloat(2 * sin(t * 18 + Double(i) * 2.1))
            for s in [CGFloat(-1), 1] {
                c.stroke(segment(CGPoint(x: x, y: 2 * s), CGPoint(x: x + w * s, y: 8 * s)), with: .color(ink),
                         style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        for s in [CGFloat(-1), 1] {
            c.stroke(segment(CGPoint(x: 8, y: 1.5 * s), CGPoint(x: 12, y: 4.5 * s)), with: .color(ink),
                     style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        c.fill(circle(CGPoint(x: 6.5, y: 0), 3.4), with: .color(ink))
        let shell = Path(ellipseIn: CGRect(x: -7, y: -5.5, width: 13, height: 11))
        c.fill(shell, with: .color(PropInk.bad))
        c.stroke(shell, with: .color(ink), lineWidth: 1.2)
        c.stroke(segment(CGPoint(x: -7, y: 0), CGPoint(x: 6, y: 0)), with: .color(ink), lineWidth: 1.2)
        for (x, y) in [(-3.0, -2.6), (-3.0, 2.6), (1.5, -2.8), (1.5, 2.8)] {
            c.fill(circle(CGPoint(x: x, y: y), 1.3), with: .color(ink))
        }
    }

    private func sweat(_ ctx: inout GraphicsContext) {
        // A bead of sweat that slides down the side of the head and comes back.
        let q = phase(t, 2.6)
        let p = CGPoint(x: 84 + 2 * CGFloat(q), y: 22 + 14 * CGFloat(smooth(q)))
        let alpha = min(q / 0.15, 1) * min((1 - q) / 0.2, 1)
        var ctx = ctx
        ctx.translateBy(x: p.x, y: p.y); ctx.scaleBy(x: 1.6, y: 1.6); ctx.translateBy(x: -p.x, y: -p.y)
        var drop = Path()
        drop.move(to: CGPoint(x: p.x, y: p.y - 6))
        drop.addQuadCurve(to: CGPoint(x: p.x + 3.6, y: p.y + 1.6), control: CGPoint(x: p.x + 3.4, y: p.y - 2))
        drop.addArc(center: CGPoint(x: p.x, y: p.y + 1.6), radius: 3.6, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        drop.addQuadCurve(to: CGPoint(x: p.x, y: p.y - 6), control: CGPoint(x: p.x - 3.4, y: p.y - 2))
        ctx.fill(drop, with: .color(PropInk.water.opacity(alpha)))
        ctx.stroke(drop, with: .color(WorkInk.ocean.opacity(alpha)), lineWidth: 1.2)
        ctx.fill(circle(CGPoint(x: p.x - 1.2, y: p.y + 1), 1), with: .color(Color.white.opacity(0.9 * alpha)))
    }

    private func question(_ ctx: inout GraphicsContext) {
        // A speech bubble with a "?", bobbing gently while it waits.
        let pulse = CGFloat(bump(phase(t, 3.2) / 0.2) * (phase(t, 3.2) < 0.2 ? 1 : 0))
        let bob = CGFloat(2 * sin(tau * t / 1.6))
        var c = ctx
        c.translateBy(x: 106, y: 4 + bob)
        c.scaleBy(x: 1 + 0.1 * pulse, y: 1 + 0.1 * pulse)
        var tail = Path()
        tail.move(to: CGPoint(x: -9, y: 7)); tail.addLine(to: CGPoint(x: -17, y: 20)); tail.addLine(to: CGPoint(x: -2, y: 11))
        tail.closeSubpath()
        let bubble = Path(ellipseIn: CGRect(x: -16, y: -13, width: 32, height: 26))
        c.stroke(tail, with: .color(cord), style: StrokeStyle(lineWidth: 3.2, lineJoin: .round))
        c.stroke(bubble, with: .color(cord), lineWidth: 3.2)
        c.fill(tail, with: .color(PropInk.paper))
        c.fill(bubble, with: .color(PropInk.paper))
        label(&c, "?", at: CGPoint(x: 0, y: 0), size: 20, color: WorkInk.ask, weight: .black, design: .rounded)
    }
}

// MARK: - Colours and shared timing, so the body and its props agree

private enum WorkInk {
    static let screen = Color(hex: 0x26262C)
    static let prompt = Color(hex: 0x6EE59A)
    static let pass = Color(hex: 0x3DBE6E)
    static let passDeep = Color(hex: 0x2E9E58)
    static let handle = Color(hex: 0x3B3A40)
    static let ocean = Color(hex: 0x2F6FB0)
    static let ask = Color(hex: 0x2E2C2A)
}

private enum WorkTiming {
    static let codePeriod = 2.8
    static let testPeriod = 3.6
    static let notePeriod = 2.4
    static let planPeriod = 4.8
    static let planTicks = [0.15, 0.4, 0.65]

    /// The magnifier sweeps back and forth over the lid, pausing a beat at each end.
    static func lens(_ t: Double) -> CGPoint {
        let q = phase(t, 4)
        let s = q < 0.5 ? smooth(q / 0.4) : 1 - smooth((q - 0.5) / 0.4)
        return CGPoint(x: 30 + 40 * s, y: 70 - 3 * bump(q < 0.5 ? q / 0.4 : (q - 0.5) / 0.4))
    }

    /// Rocket: rests on the pad, then lifts off and fades out; a fresh one fades in.
    static func rocket(_ t: Double) -> (lift: CGFloat, alpha: Double) {
        let q = phase(t, 4)
        if q < 0.4 { return (0, 1) }
        if q < 0.85 {
            let k = (q - 0.4) / 0.45
            let h = 110 * k * k
            return (CGFloat(h), 1 - smooth((h - 50) / 40))
        }
        return (0, smooth((q - 0.85) / 0.15))
    }

    /// The bug wanders the lid; heading follows its velocity.
    static func bug(_ t: Double) -> (p: CGPoint, heading: Double) {
        let a = tau * t / 6, b = tau * t / 2.1
        let p = CGPoint(x: 50 + 22 * sin(a), y: 72 + 6 * sin(b))
        let v = (22 * cos(a) / 6, 6 * cos(b) / 2.1)
        return (p, atan2(v.1, v.0))
    }
}

extension Motion {
    /// At the laptop: eyes on the screen, a quick nod of typing, now and then a look up to think.
    /// Every work pose starts from this one.
    mutating func atLaptop(_ t: Double) {
        let think = phase(t, 9) > 0.8 ? sin(.pi * (phase(t, 9) - 0.8) / 0.2) : 0
        lookX = 1.5 * sin(tau * t / 2.3) * (1 - think)
        lookY = 4 * (1 - think) - 4 * think
        dy += -0.6 * abs(sin(tau * t * 2.6)) * (1 - think)
        rot = 3 * (1 - think) + rot * 0.4
    }
}
