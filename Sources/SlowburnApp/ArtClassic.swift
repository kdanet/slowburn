import SwiftUI

// Quiet pastimes: the first ten.

extension Motion {
    mutating func poseReading(_ t: Double) {
        var m = self
        // Lines scanned left to right, a quick return, a page turn every few seconds.
        let line = phase(t, 1.8)
        m.lookX = line < 0.85 ? -4 + 8 * line / 0.85 : 4 - 8 * (line - 0.85) / 0.15
        m.lookY = 5
        m.rot = 2 + m.rot * 0.3
        self = m
    }

    mutating func poseCoffee(_ t: Double) {
        var m = self
        let sip = Activity.sipLift(t)
        m.lookX = 2 + 2 * sip
        m.lookY = 2 - 3 * sip
        if sip > 0.6 { m.blink = 1 - 0.75 * smooth((sip - 0.6) / 0.4) }
        m.rot = -2 * sip + m.rot * 0.5
        self = m
    }

    mutating func poseMusic(_ t: Double) {
        var m = self
        // On the beat: bob down and sway, eyes shut in bliss.
        let beat = abs(sin(.pi * t / 0.5))
        m.dy = -2.2 * beat
        m.sy = 1 - 0.025 * (1 - beat)
        m.sx = 1 + 0.025 * (1 - beat)
        m.rot = 4 * sin(.pi * t / 1.0)
        m.blink = 0.28
        m.lookX = 0; m.lookY = 1
        self = m
    }

    mutating func poseJuggling(_ t: Double) {
        var m = self
        let lead = Activity.jugglePoint(t + 0.12, phase: 0)
        m.lookX = (lead.x - 50) / 9
        m.lookY = -2 + (lead.y - 30) / 14
        m.dy += -0.8 * abs(sin(tau * t / Activity.juggleBeat))
        self = m
    }

    mutating func poseBubbles(_ t: Double) {
        var m = self
        m.lookX = 3 + 1.5 * sin(tau * t / 3.1)
        m.lookY = -3
        let blow = phase(t, 3.2)
        if blow < 0.3 { m.sx = 1 + 0.03 * sin(.pi * blow / 0.3); m.sy = 1 - 0.03 * sin(.pi * blow / 0.3) }
        self = m
    }

    mutating func poseMeditating(_ t: Double) {
        var m = self
        m.dy = -6 - 3 * sin(tau * t / 4.4)
        m.rot = 0.6 * sin(tau * t / 7)
        m.sx = 1 + 0.02 * sin(tau * t / 4.4)
        m.sy = 1 - 0.02 * sin(tau * t / 4.4)
        m.blink = 0.14
        m.lookX = 0; m.lookY = 2
        self = m
    }

    mutating func poseGardening(_ t: Double) {
        var m = self
        m.lookX = 4
        m.lookY = 4
        m.rot = 5 + 2 * Activity.pour(t) + m.rot * 0.3
        self = m
    }

    mutating func poseYoyo(_ t: Double) {
        var m = self
        let y = Activity.yoyoDrop(t)
        m.lookX = 3.5
        m.lookY = -1 + 6 * y
        m.dy += -0.8 * max(0, 1 - y * 4)
        self = m
    }

    mutating func poseBalloon(_ t: Double) {
        var m = self
        m.lookX = 3.5 + 0.8 * sin(tau * t / 3.3)
        m.lookY = -4.5
        m.rot = -3 + m.rot
        m.dx += 1.2 * sin(tau * t / 5.5)
        self = m
    }

    mutating func poseStargazing(_ t: Double) {
        var m = self
        // Lean back and pick out one star after another.
        let pick = Motion.keyframes(phase(t, 10), [
            (0.00, [-3, -6]), (0.25, [-3, -6]), (0.35, [3, -7]), (0.6, [3, -7]),
            (0.7, [0, -5]), (0.9, [0, -5]), (1.0, [-3, -6]),
        ])
        m.lookX = pick[0]; m.lookY = pick[1]
        m.rot = -5 + m.rot * 0.5
        self = m
    }
}

extension ActivityProps {
    func drawReading(_ ctx: inout GraphicsContext) {
        if layer == .held { book(&ctx) }
    }

    func drawCoffee(_ ctx: inout GraphicsContext) {
        if layer == .held { mug(&ctx) }
    }

    func drawMusic(_ ctx: inout GraphicsContext) {
        if layer == .held { headphones(&ctx) }
        if layer == .front { notes(&ctx) }
    }

    func drawJuggling(_ ctx: inout GraphicsContext) {
        if layer == .front { juggle(&ctx) }
    }

    func drawBubbles(_ ctx: inout GraphicsContext) {
        if layer == .held { wand(&ctx) }
        if layer == .front { bubbles(&ctx) }
    }

    func drawMeditating(_ ctx: inout GraphicsContext) {
        if layer == .behind { aura(&ctx) }
    }

    func drawGardening(_ ctx: inout GraphicsContext) {
        if layer == .front { plant(&ctx) }
        if layer == .held { wateringCan(&ctx) }
    }

    func drawYoyo(_ ctx: inout GraphicsContext) {
        if layer == .held { yoyo(&ctx) }
    }

    func drawBalloon(_ ctx: inout GraphicsContext) {
        if layer == .held { balloon(&ctx) }
    }

    func drawStargazing(_ ctx: inout GraphicsContext) {
        if layer == .behind { stars(&ctx) }
    }


    // MARK: Pieces

    private func book(_ ctx: inout GraphicsContext) {
        // An open book held low in front, spine in the middle; a page lifts and turns every few seconds.
        let left = Path { p in
            p.move(to: CGPoint(x: 50, y: 70)); p.addQuadCurve(to: CGPoint(x: 20, y: 66), control: CGPoint(x: 36, y: 62))
            p.addLine(to: CGPoint(x: 20, y: 90)); p.addQuadCurve(to: CGPoint(x: 50, y: 94), control: CGPoint(x: 36, y: 86))
            p.closeSubpath()
        }
        let right = left.applying(CGAffineTransform(translationX: 100, y: 0).scaledBy(x: -1, y: 1))
        let cover = Path(roundedRect: CGRect(x: 17, y: 68, width: 66, height: 29), cornerRadius: 3)
        ctx.fill(cover, with: .color(PropInk.cover))
        ctx.fill(left, with: .color(PropInk.paper))
        ctx.fill(right, with: .color(PropInk.paper))
        for i in 0..<3 {
            let y = 73 + CGFloat(i) * 6
            var line = Path(); line.move(to: CGPoint(x: 25, y: y)); line.addLine(to: CGPoint(x: 44, y: y + 2))
            var line2 = Path(); line2.move(to: CGPoint(x: 56, y: y + 2)); line2.addLine(to: CGPoint(x: 75, y: y))
            ctx.stroke(line, with: .color(PropInk.steam), lineWidth: 1.4)
            ctx.stroke(line2, with: .color(PropInk.steam), lineWidth: 1.4)
        }
        let p = cycle(5)
        if p > 0.82 {
            // The turning page, squeezed from the right half to the left one.
            let q = (p - 0.82) / 0.18
            let w = cos(.pi * q)
            let turning = right.applying(CGAffineTransform(translationX: 50, y: 0).scaledBy(x: w, y: 1).translatedBy(x: -50, y: 0))
            ctx.fill(turning, with: .color(PropInk.paper.opacity(0.95)))
            ctx.stroke(turning, with: .color(PropInk.steam), lineWidth: 0.8)
        }
    }

    private func mug(_ ctx: inout GraphicsContext) {
        let lift = Activity.sipLift(t)
        var c = ctx
        // From the table at the right up to the mouth, tipping as it rises.
        c.translateBy(x: 82 - 22 * lift, y: 80 - 22 * lift)
        c.rotate(by: .degrees(-28 * lift))
        let cup = Path(roundedRect: CGRect(x: -9, y: -10, width: 18, height: 20), cornerRadius: 4, style: .continuous)
        var handle = Path(); handle.addArc(center: CGPoint(x: 9, y: 0), radius: 5, startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
        c.stroke(handle, with: .color(PropInk.mug), lineWidth: 3)
        c.fill(cup, with: .color(PropInk.mug))
        c.stroke(cup, with: .color(PropInk.metalEdge), lineWidth: 1.6)
        c.fill(Path(CGRect(x: -9, y: -3, width: 18, height: 5)), with: .color(tint.opacity(0.8)))
        // Steam only while it rests.
        if lift < 0.2 {
            for i in 0..<2 {
                let q = (t / 2.2 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                var s = Path()
                let x0 = CGFloat(-3 + i * 6), y0: CGFloat = -13 - 14 * q
                s.move(to: CGPoint(x: x0, y: y0 + 6))
                s.addQuadCurve(to: CGPoint(x: x0, y: y0 - 6), control: CGPoint(x: x0 + 4 * sin(.pi * 2 * q), y: y0))
                c.stroke(s, with: .color(PropInk.steam.opacity((1 - q) * (1 - lift / 0.2))),
                         style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func headphones(_ ctx: inout GraphicsContext) {
        var band = Path()
        band.addArc(center: CGPoint(x: 50, y: 50), radius: 43, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        ctx.stroke(band, with: .color(cord), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        for x in [CGFloat(4), 84] {
            let cup = Path(roundedRect: CGRect(x: x, y: 32, width: 12, height: 24), cornerRadius: 6, style: .continuous)
            ctx.fill(cup, with: .color(cord))
            ctx.fill(Path(roundedRect: CGRect(x: x + 3, y: 37, width: 6, height: 14), cornerRadius: 3), with: .color(tint))
        }
    }

    private func notes(_ ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let q = (t / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let x = 96 + 10 * sin(2 * .pi * q + Double(i)) + CGFloat(i) * 4
            let y = 40 - 50 * q
            let alpha = q < 0.15 ? q / 0.15 : (1 - q) / 0.85
            ctx.draw(Text(i == 1 ? "♫" : "♪").font(.system(size: 20, weight: .bold)).foregroundColor(tint.opacity(alpha)),
                     at: CGPoint(x: x, y: y))
        }
    }

    private func juggle(_ ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let p = Activity.jugglePoint(t, phase: Double(i) / 3)
            let r: CGFloat = 7
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(PropInk.balls[i]))
        }
    }

    private func wand(_ ctx: inout GraphicsContext) {
        var stick = Path(); stick.move(to: CGPoint(x: 80, y: 82)); stick.addLine(to: CGPoint(x: 96, y: 56))
        ctx.stroke(stick, with: .color(PropInk.metalEdge), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        ctx.stroke(Path(ellipseIn: CGRect(x: 92, y: 42, width: 14, height: 14)), with: .color(PropInk.metalEdge), lineWidth: 3)
    }

    private func bubbles(_ ctx: inout GraphicsContext) {
        for i in 0..<4 {
            let q = (t / 4.2 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
            let seed = Double(i) * 1.7
            let x = 100 + 14 * q + 6 * sin(2 * .pi * q * 1.5 + seed)
            let y = 46 - 70 * q
            let r = 3 + 6 * min(q * 3, 1)
            // Pop: a quick swell and fade at the end.
            let alpha = q > 0.85 ? (1 - q) / 0.15 : 1
            let rr = q > 0.85 ? r * (1 + 0.4 * (q - 0.85) / 0.15) : r
            let rect = CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr)
            ctx.fill(Path(ellipseIn: rect), with: .color(PropInk.water.opacity(0.18 * alpha)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(PropInk.water.opacity(0.9 * alpha)), lineWidth: 1.6)
            ctx.fill(Path(ellipseIn: CGRect(x: x - rr * 0.5, y: y - rr * 0.6, width: rr * 0.4, height: rr * 0.4)),
                     with: .color(Color.white.opacity(0.8 * alpha)))
        }
    }

    private func aura(_ ctx: inout GraphicsContext) {
        // A shadow that shrinks as the body rises, and slow rings breathing out.
        let rise = (sin(2 * .pi * t / 4.4) + 1) / 2
        let w = 56 - 10 * rise
        ctx.fill(Path(ellipseIn: CGRect(x: 50 - w / 2, y: 98, width: w, height: 6)), with: .color(Color.black.opacity(0.18 + 0.08 * (1 - rise))))
        for i in 0..<2 {
            let q = (t / 4.4 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let r = 40 + 28 * q
            ctx.stroke(Path(ellipseIn: CGRect(x: 50 - r, y: 46 - r, width: 2 * r, height: 2 * r)),
                       with: .color(tint.opacity(0.45 * (1 - q))), lineWidth: 2)
        }
        for i in 0..<3 {
            let a = 2 * .pi * (t / 9 + Double(i) / 3)
            let p = CGPoint(x: 50 + 58 * cos(a), y: 46 + 40 * sin(a))
            sparkle(&ctx, at: p, r: 4 + 1.5 * sin(t * 3 + Double(i)), color: star.opacity(0.8))
        }
    }

    private func plant(_ ctx: inout GraphicsContext) {
        // The sprout grows over the whole pastime, so it is taller near the end of it.
        let grown = 0.35 + 0.65 * (t.truncatingRemainder(dividingBy: Activity.leisureSlot) / Activity.leisureSlot)
        let stemTop = 86 - 22 * grown
        var stem = Path(); stem.move(to: CGPoint(x: 112, y: 88)); stem.addQuadCurve(to: CGPoint(x: 112, y: stemTop), control: CGPoint(x: 109, y: (88 + stemTop) / 2))
        ctx.stroke(stem, with: .color(PropInk.leaf), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        let sway = 6 * sin(2 * .pi * t / 3.4)
        for (dx, angle) in [(-1.0, -35.0), (1.0, 35.0)] {
            var leaf = ctx
            leaf.translateBy(x: 112, y: stemTop + 2)
            leaf.rotate(by: .degrees(angle + sway))
            leaf.fill(Path(ellipseIn: CGRect(x: dx < 0 ? -12 : 0, y: -4, width: 12 * grown + 4, height: 8)), with: .color(PropInk.leaf))
        }
        let pot = Path { p in
            p.move(to: CGPoint(x: 100, y: 86)); p.addLine(to: CGPoint(x: 124, y: 86))
            p.addLine(to: CGPoint(x: 120, y: 102)); p.addLine(to: CGPoint(x: 104, y: 102)); p.closeSubpath()
        }
        ctx.fill(pot, with: .color(PropInk.pot))
        ctx.fill(Path(roundedRect: CGRect(x: 98, y: 83, width: 28, height: 6), cornerRadius: 2), with: .color(PropInk.pot))
    }

    private func wateringCan(_ ctx: inout GraphicsContext) {
        let tip = Activity.pour(t)
        var c = ctx
        c.translateBy(x: 82, y: 66)
        c.rotate(by: .degrees(28 * tip))
        let can = Path(roundedRect: CGRect(x: -10, y: -8, width: 18, height: 16), cornerRadius: 4, style: .continuous)
        var spout = Path(); spout.move(to: CGPoint(x: 6, y: 4)); spout.addLine(to: CGPoint(x: 20, y: -8))
        c.stroke(spout, with: .color(PropInk.water), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        c.fill(can, with: .color(PropInk.water))
        var handle = Path(); handle.addArc(center: CGPoint(x: -1, y: -8), radius: 6, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        c.stroke(handle, with: .color(PropInk.water), lineWidth: 2.4)
        // Drops falling from the spout to the pot while tipped.
        if tip > 0.6 {
            for i in 0..<3 {
                let q = (t * 1.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = 105 + 3 * q, y = 64 + 20 * q
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 2.2, width: 3.2, height: 4.4)),
                         with: .color(PropInk.water.opacity((tip - 0.6) / 0.4)))
            }
        }
    }

    private func yoyo(_ ctx: inout GraphicsContext) {
        let hand = CGPoint(x: 86, y: 60)
        let y = hand.y + 6 + 46 * Activity.yoyoDrop(t)
        var string = Path(); string.move(to: hand); string.addLine(to: CGPoint(x: hand.x + 4, y: y))
        ctx.stroke(string, with: .color(cord.opacity(0.85)), lineWidth: 1.2)
        let r: CGFloat = 7.5
        let disc = CGRect(x: hand.x + 4 - r, y: y - r, width: 2 * r, height: 2 * r)
        ctx.fill(Path(ellipseIn: disc), with: .color(PropInk.balls[0]))
        var spoke = ctx
        spoke.translateBy(x: disc.midX, y: disc.midY)
        spoke.rotate(by: .radians(t * 14))
        var bar = Path(); bar.move(to: CGPoint(x: -r * 0.7, y: 0)); bar.addLine(to: CGPoint(x: r * 0.7, y: 0))
        spoke.stroke(bar, with: .color(Color.white.opacity(0.8)), lineWidth: 1.6)
        spoke.fill(Path(ellipseIn: CGRect(x: -1.8, y: -1.8, width: 3.6, height: 3.6)), with: .color(Color.white))
    }

    private func balloon(_ ctx: inout GraphicsContext) {
        let hand = CGPoint(x: 84, y: 64)
        let top = CGPoint(x: 104 + 5 * sin(2 * .pi * t / 4.1), y: -14 + 3 * sin(2 * .pi * t / 2.9))
        var string = Path(); string.move(to: hand)
        string.addQuadCurve(to: CGPoint(x: top.x, y: top.y + 15), control: CGPoint(x: hand.x + 18 + 4 * sin(t * 2), y: (hand.y + top.y) / 2))
        ctx.stroke(string, with: .color(cord.opacity(0.8)), lineWidth: 1.2)
        let body = Path(ellipseIn: CGRect(x: top.x - 11, y: top.y - 13, width: 22, height: 27))
        ctx.fill(body, with: .color(PropInk.balloon))
        ctx.fill(Path(ellipseIn: CGRect(x: top.x - 6, y: top.y - 8, width: 5, height: 8)), with: .color(Color.white.opacity(0.55)))
        var knot = Path(); knot.move(to: CGPoint(x: top.x - 2.5, y: top.y + 16)); knot.addLine(to: CGPoint(x: top.x + 2.5, y: top.y + 16))
        knot.addLine(to: CGPoint(x: top.x, y: top.y + 13)); knot.closeSubpath()
        ctx.fill(knot, with: .color(PropInk.balloon))
    }

    private func stars(_ ctx: inout GraphicsContext) {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [(18, -8, 4), (50, -22, 5), (88, -6, 4.5), (-8, 22, 3.2), (112, 26, 3.5), (70, -30, 3)]
        for (i, s) in spots.enumerated() {
            let twinkle = 0.55 + 0.45 * sin(t * (1.6 + Double(i) * 0.37) + Double(i) * 2)
            sparkle(&ctx, at: CGPoint(x: s.0, y: s.1), r: s.2 * (0.8 + 0.3 * twinkle), color: star.opacity(twinkle))
        }
        // A crescent moon, cut with a second circle.
        var moon = ctx
        moon.clipToLayer { layer in
            layer.fill(Path(CGRect(x: -50, y: -50, width: 200, height: 200)), with: .color(.black))
            layer.blendMode = .destinationOut
            layer.fill(Path(ellipseIn: CGRect(x: 113, y: -24, width: 18, height: 18)), with: .color(.black))
        }
        moon.fill(Path(ellipseIn: CGRect(x: 108, y: -22, width: 18, height: 18)), with: .color(star))
    }
}

// MARK: - Shared timing, so the body and its props agree

extension Activity {
    /// 0 = mug on the table, 1 = at the mouth.
    static func sipLift(_ t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: 7) / 7
        let x: Double
        switch p {
        case ..<0.55: x = 0
        case ..<0.65: x = (p - 0.55) / 0.1
        case ..<0.85: x = 1
        case ..<0.95: x = 1 - (p - 0.85) / 0.1
        default: x = 0
        }
        return x * x * (3 - 2 * x)
    }

    static let juggleBeat = 0.55

    /// A three-ball cascade in the 100-box: high arc left→right, quick low pass back.
    static func jugglePoint(_ t: Double, phase: Double) -> CGPoint {
        let period = juggleBeat * 3
        var p = (t / period + phase).truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        if p < 0.72 {
            let q = p / 0.72
            return CGPoint(x: 18 + 64 * q, y: 70 - 4 * 78 * q * (1 - q))
        }
        let q = (p - 0.72) / 0.28
        return CGPoint(x: 82 - 64 * q, y: 70 + 8 * sin(.pi * q))
    }

    /// 0 = yo-yo in hand, 1 = at the bottom of the string.
    static func yoyoDrop(_ t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: 2.4) / 2.4
        if p < 0.42 { let q = p / 0.42; return q * q }            // falls, speeding up
        if p < 0.52 { return 1 }                                  // sleeps at the bottom
        let q = (p - 0.52) / 0.48; return 1 - (1 - (1 - q) * (1 - q)) // climbs, slowing down
    }

    /// 0…1: how far the watering can is tipped.
    static func pour(_ t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: 6) / 6
        if p < 0.15 { return 0 }
        if p < 0.3 { let q = (p - 0.15) / 0.15; return q * q * (3 - 2 * q) }
        if p < 0.75 { return 1 }
        if p < 0.9 { let q = (p - 0.75) / 0.15; return 1 - q * q * (3 - 2 * q) }
        return 0
    }
}
