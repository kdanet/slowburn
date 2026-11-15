import SwiftUI

// Outdoors and on the move.

extension Motion {
    /// Eyes on a point in the box.
    fileprivate mutating func eye(on p: CGPoint) {
        lookX = max(-6, min(6, Double(p.x - 50) / 8))
        lookY = max(-6, min(6, Double(p.y - 46) / 8))
    }

    mutating func poseFishing(_ t: Double) {
        var m = self
        let f = Outdoor.fishing(t)
        m.rot *= 0.3
        m.lookX = 4.5; m.lookY = 4.5
        if let q = f.fish { m.eye(on: Outdoor.fishPoint(q)) }
        // Patient half-lidded wait; wide awake when it bites.
        m.blink *= 0.72 + 0.28 * f.perk
        m.dy += f.lift
        m.sy *= 1 + 0.035 * f.perk
        m.sx *= 1 - 0.025 * f.perk
        self = m
    }

    mutating func poseKite(_ t: Double) {
        var m = self
        let k = Outdoor.kite(t)
        m.eye(on: k.pos)
        m.lookY = -6
        m.rot = -3 + 0.5 * m.rot + 1.5 * sin(tau * t / 4.3)
        m.dx += 1.2 * sin(tau * t / 4.3)
        self = m
    }

    mutating func posePaperPlane(_ t: Double) {
        var m = self
        let p = Outdoor.plane(t)
        m.eye(on: p.pos)
        m.rot = m.rot * 0.4 - 5 * p.windup + 4 * p.kick
        m.dx += -1.5 * p.windup + 1.5 * p.kick
        self = m
    }

    mutating func poseJumpRope(_ t: Double) {
        var m = self
        let h = Outdoor.hop(t)
        m.dy = h[0]; m.sx = h[1]; m.sy = h[2]
        m.rot *= 0.3
        m.lookX = 0; m.lookY = -1 + h[0] / 6
        self = m
    }

    mutating func poseHulaHoop(_ t: Double) {
        var m = self
        let phi = Outdoor.hulaPhase(t)
        m.dx = Outdoor.hulaDX(phi)
        m.rot = 3.5 * sin(phi) + 0.2 * m.rot
        m.lookX = -1.5 * cos(phi); m.lookY = 0.5
        self = m
    }

    mutating func poseSkateboard(_ t: Double) {
        var m = self
        let o = Outdoor.ollie(t)
        m.dy += -14 * o.h
        m.rot = 4 + 0.3 * m.rot - 3 * o.h
        m.sx *= 1 + 0.07 * o.squash
        m.sy *= 1 - 0.07 * o.squash
        m.lookX = 5; m.lookY = 0.5 + 2.5 * o.h
        self = m
    }

    mutating func poseSnowfall(_ t: Double) {
        var m = self
        let f = Outdoor.catchFlake(t)
        m.eye(on: f.pos)
        if f.landed > 0 { m.lookY = -6 }
        m.blink = min(m.blink, 1 - 0.7 * f.joy)
        m.dy += -2.5 * f.hop
        m.rot = m.rot * 0.5 + 2 * f.joy * sin(tau * t / 1.2)
        self = m
    }

    mutating func poseButterfly(_ t: Double) {
        var m = self
        let b = Outdoor.butterfly(t)
        m.eye(on: b.pos)
        m.rot = 0.5 * m.rot + 3 * Double(b.pos.x - 50) / 52
        m.dx += 1.5 * Double(b.pos.x - 50) / 52
        self = m
    }

    mutating func poseDandelion(_ t: Double) {
        var m = self
        let d = Outdoor.dandelion(t)
        // Breathe in, then puff: a stretch and a squash.
        let v = Motion.keyframes(d.p, [
            (0.00, [1, 1, 0]), (0.30, [1, 1, 0]),
            (0.42, [0.965, 1.05, -1.5]), (0.47, [1.07, 0.93, 0]),
            (0.56, [1.04, 0.96, 0]), (0.66, [1, 1, 0]), (1.00, [1, 1, 0]),
        ])
        m.sx *= v[0]; m.sy *= v[1]; m.dy += v[2]
        m.rot *= 0.3
        if d.p > 0.44 && d.p < 0.58 { m.blink = 0.3 }
        if let u = d.flight {
            m.lookX = 5 + 1 * u; m.lookY = -1 - 5 * smooth(u * 2)
        } else {
            m.lookX = 5; m.lookY = -1
        }
        self = m
    }

    mutating func poseSwimRing(_ t: Double) {
        var m = self
        let s = Outdoor.swim(t)
        m.dy = s.dy; m.rot = s.rot; m.dx = 0
        m.lookY = m.lookY * 0.5 + 1
        self = m
    }
}

extension ActivityProps {
    func drawFishing(_ ctx: inout GraphicsContext) {
        if layer == .front { fishing(&ctx) }
    }

    func drawKite(_ ctx: inout GraphicsContext) {
        if layer == .front { kite(&ctx) }
    }

    func drawPaperPlane(_ ctx: inout GraphicsContext) {
        let p = Outdoor.plane(t)
        if layer == .front { plane(&ctx, at: p.pos, heading: p.heading) }
    }

    func drawJumpRope(_ ctx: inout GraphicsContext) {
        if layer != .held { rope(&ctx, front: layer == .front) }
    }

    func drawHulaHoop(_ ctx: inout GraphicsContext) {
        if layer != .held { hoop(&ctx, front: layer == .front) }
    }

    func drawSkateboard(_ ctx: inout GraphicsContext) {
        if layer == .behind { speedLines(&ctx) }
        if layer == .front { board(&ctx) }
    }

    func drawSnowfall(_ ctx: inout GraphicsContext) {
        if layer == .held { caughtFlake(&ctx) } else { snowField(&ctx, front: layer == .front) }
    }

    func drawButterfly(_ ctx: inout GraphicsContext) {
        if layer == .front { butterfly(&ctx) }
    }

    func drawDandelion(_ ctx: inout GraphicsContext) {
        if layer == .held { dandelion(&ctx) }
        if layer == .front { seedsAfloat(&ctx) }
    }

    func drawSwimRing(_ ctx: inout GraphicsContext) {
        if layer != .held { swimRing(&ctx, front: layer == .front) }
    }

    // MARK: Pieces

    private var snow: Color { dark ? Color(white: 0.96) : Color(hex: 0x5E8FC4) }
    private var fluff: Color { dark ? Color(white: 0.93) : Color(hex: 0x8C867C) }

    /// A copy of the context that moves the way the body does: offset, then a turn about the bottom centre.
    private func riding(_ ctx: GraphicsContext, dx: Double = 0, dy: Double, rot: Double = 0) -> GraphicsContext {
        var c = ctx
        c.translateBy(x: 50 + dx, y: 100 + dy)
        c.rotate(by: .degrees(rot))
        c.translateBy(x: -50, y: -100)
        return c
    }

    private func ringPoint(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ tilt: Double, _ a: Double) -> CGPoint {
        let x = rx * CGFloat(cos(a)), y = ry * CGFloat(sin(a))
        let ct = CGFloat(cos(tilt)), st = CGFloat(sin(tilt))
        return CGPoint(x: c.x + x * ct - y * st, y: c.y + x * st + y * ct)
    }

    /// The front (lower) or back (upper) half of a striped ring seen from the side; stripes slide by `spin`.
    private func stripedRing(_ ctx: inout GraphicsContext, center: CGPoint, rx: CGFloat, ry: CGFloat, tilt: Double,
                             front: Bool, width: CGFloat, spin: Double, pairs: Int, colors: (Color, Color)) {
        let steps = 40
        let start = front ? 0.0 : Double.pi
        var whole = Path(), a = Path(), b = Path()
        for i in 0..<steps {
            let a0 = start + .pi * Double(i) / Double(steps)
            let a1 = start + .pi * (Double(i) + 1.25) / Double(steps)
            let p0 = ringPoint(center, rx, ry, tilt, a0), p1 = ringPoint(center, rx, ry, tilt, min(a1, start + .pi))
            if i == 0 { whole.move(to: p0) }
            whole.addLine(to: ringPoint(center, rx, ry, tilt, start + .pi * Double(i + 1) / Double(steps)))
            let k = Int(floor(((a0 + a1) / 2 - spin) / tau * Double(2 * pairs)))
            if ((k % 2) + 2) % 2 == 0 { a.move(to: p0); a.addLine(to: p1) } else { b.move(to: p0); b.addLine(to: p1) }
        }
        ctx.stroke(whole, with: .color(PropInk.metalEdge), style: StrokeStyle(lineWidth: width + 2.6, lineCap: .butt))
        ctx.stroke(a, with: .color(colors.0), style: StrokeStyle(lineWidth: width, lineCap: .butt))
        ctx.stroke(b, with: .color(colors.1), style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }

    // Fishing

    private func fishing(_ ctx: inout GraphicsContext) {
        let f = Outdoor.fishing(t)
        let pond = Outdoor.pond
        let pondRect = CGRect(x: pond.x - 19, y: pond.y - 6.5, width: 38, height: 13)
        ctx.fill(Path(ellipseIn: pondRect), with: .color(PropInk.water.opacity(0.45)))
        ctx.stroke(Path(ellipseIn: pondRect), with: .color(PropInk.water), lineWidth: 1.8)
        let bob = CGPoint(x: pond.x, y: pond.y - 2 + CGFloat(f.dip))
        // Ripples around the float.
        for i in 0..<2 {
            let u = phase(t / 1.6 + Double(i) / 2, 1)
            let r = 5 + 11 * CGFloat(u)
            ctx.stroke(Path(ellipseIn: CGRect(x: pond.x - r, y: pond.y - 1 - r * 0.3, width: 2 * r, height: r * 0.6)),
                       with: .color(PropInk.water.opacity(0.9 * (1 - u))), lineWidth: 1.4)
        }
        // Rod from the hand, line to the float.
        let lift = CGFloat(f.lift)
        let hand = CGPoint(x: 78, y: 80 + lift)
        let tip = CGPoint(x: 114 - 4 * CGFloat(f.perk), y: 22 - 8 * CGFloat(f.perk) + lift)
        var line = Path(); line.move(to: tip)
        line.addQuadCurve(to: CGPoint(x: bob.x, y: bob.y - 5), control: CGPoint(x: (tip.x + bob.x) / 2 + 4, y: (tip.y + bob.y) / 2 + 4))
        ctx.stroke(line, with: .color(cord.opacity(0.85)), lineWidth: 1.3)
        ctx.stroke(segment(hand, tip), with: .color(PropInk.wood), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        let grip = CGPoint(x: hand.x + (tip.x - hand.x) * 0.2, y: hand.y + (tip.y - hand.y) * 0.2)
        ctx.stroke(segment(hand, grip), with: .color(PropInk.metalEdge), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.fill(circle(CGPoint(x: grip.x + 3, y: grip.y + 1), 3.4), with: .color(PropInk.metal))
        ctx.stroke(circle(CGPoint(x: grip.x + 3, y: grip.y + 1), 3.4), with: .color(PropInk.metalEdge), lineWidth: 1.2)
        // The float: above the water in full, below it faded.
        var above = ctx
        above.clip(to: Path(CGRect(x: 80, y: -60, width: 60, height: pond.y - 1 + 60)))
        bobber(&above, at: bob)
        var below = ctx
        below.clip(to: Path(CGRect(x: 80, y: pond.y - 1, width: 60, height: 30)))
        below.opacity = 0.35
        bobber(&below, at: bob)
        // The fish leaps out of the pond and dives back in.
        if let q = f.fish {
            let p = Outdoor.fishPoint(q)
            let heading = atan2(-120 * (1 - 2 * q), 20.0)
            var c = ctx
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(heading))
            c.scaleBy(x: 1.35, y: 1.35)
            var tail = Path(); tail.move(to: CGPoint(x: -4, y: 0)); tail.addLine(to: CGPoint(x: -10, y: -4.5))
            tail.addLine(to: CGPoint(x: -10, y: 4.5)); tail.closeSubpath()
            c.fill(tail, with: .color(PropInk.fire))
            c.fill(Path(ellipseIn: CGRect(x: -7, y: -4, width: 14, height: 8)), with: .color(PropInk.fire))
            c.fill(circle(CGPoint(x: 3.2, y: -1), 1.3), with: .color(PropInk.cordOnLight))
            for (x0, s) in [(CGFloat(96), q), (CGFloat(118), 1 - q)] where s < 0.2 {
                let u = CGFloat(s / 0.2)
                for j in -1...1 {
                    ctx.fill(circle(CGPoint(x: x0 + CGFloat(j) * 4 * (0.5 + u), y: pond.y - 3 - 6 * sin(.pi * u) * (j == 0 ? 1.4 : 1)), 1.6),
                             with: .color(PropInk.water.opacity(Double(1 - u))))
                }
            }
        }
    }

    private func bobber(_ ctx: inout GraphicsContext, at p: CGPoint) {
        let r: CGFloat = 5.4
        ctx.stroke(segment(CGPoint(x: p.x, y: p.y - r), CGPoint(x: p.x, y: p.y - r - 2.5)), with: .color(PropInk.metalEdge), lineWidth: 1.6)
        ctx.fill(circle(p, r), with: .color(PropInk.paper))
        var top = Path()
        top.addArc(center: p, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        top.closeSubpath()
        ctx.fill(top, with: .color(PropInk.bad))
        ctx.stroke(circle(p, r), with: .color(PropInk.metalEdge), lineWidth: 1.2)
    }

    // Kite

    private func kite(_ ctx: inout GraphicsContext) {
        let k = Outdoor.kite(t)
        let hand = CGPoint(x: 84, y: 66)
        var c = ctx
        c.translateBy(x: k.pos.x, y: k.pos.y)
        c.rotate(by: .degrees(k.tilt))
        let top = CGPoint(x: 0, y: -17), right = CGPoint(x: 13, y: -4), bottom = CGPoint(x: 0, y: 21), left = CGPoint(x: -13, y: -4)
        let mid = CGPoint(x: 0, y: -4)
        // Where the tail and string attach, in box coordinates.
        let a = k.tilt * .pi / 180
        func world(_ p: CGPoint) -> CGPoint {
            CGPoint(x: k.pos.x + p.x * CGFloat(cos(a)) - p.y * CGFloat(sin(a)), y: k.pos.y + p.x * CGFloat(sin(a)) + p.y * CGFloat(cos(a)))
        }
        let anchor = world(CGPoint(x: 0, y: 3)), tailStart = world(bottom)
        var string = Path(); string.move(to: hand)
        string.addQuadCurve(to: anchor, control: CGPoint(x: hand.x + 14 + 3 * sin(t * 1.7), y: (hand.y + anchor.y) / 2 + 6))
        ctx.stroke(string, with: .color(cord.opacity(0.85)), lineWidth: 1.3)
        // A wavy tail streaming down-wind with three bows.
        var tail = Path(); tail.move(to: tailStart)
        var bows: [CGPoint] = []
        for i in 1...16 {
            let s = Double(i) / 16
            let p = CGPoint(x: tailStart.x + CGFloat(8 * s + 5 * sin(tau * (1.4 * s - t / 1.1)) * s),
                            y: tailStart.y + CGFloat(34 * s))
            tail.addLine(to: p)
            if i % 5 == 0 || i == 16 { bows.append(p) }
        }
        ctx.stroke(tail, with: .color(cord.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        for p in bows.prefix(3) {
            var bow = Path()
            bow.move(to: p); bow.addLine(to: CGPoint(x: p.x - 6, y: p.y - 4)); bow.addLine(to: CGPoint(x: p.x - 6, y: p.y + 4)); bow.closeSubpath()
            bow.move(to: p); bow.addLine(to: CGPoint(x: p.x + 6, y: p.y - 4)); bow.addLine(to: CGPoint(x: p.x + 6, y: p.y + 4)); bow.closeSubpath()
            ctx.fill(bow, with: .color(tint))
        }
        // The sail in four panes, with its cross spars.
        let panes: [(CGPoint, CGPoint, Color)] = [(top, right, PropInk.balloon), (right, bottom, PropInk.balls[1]),
                                                  (bottom, left, PropInk.balloon), (left, top, PropInk.balls[1])]
        for (p, q, col) in panes {
            var pane = Path(); pane.move(to: mid); pane.addLine(to: p); pane.addLine(to: q); pane.closeSubpath()
            c.fill(pane, with: .color(col))
        }
        var outline = Path(); outline.move(to: top); outline.addLine(to: right); outline.addLine(to: bottom); outline.addLine(to: left); outline.closeSubpath()
        c.stroke(outline, with: .color(PropInk.metalEdge), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
        c.stroke(segment(top, bottom), with: .color(PropInk.metalEdge), lineWidth: 1.2)
        c.stroke(segment(left, right), with: .color(PropInk.metalEdge), lineWidth: 1.2)
    }

    // Paper plane

    private func plane(_ ctx: inout GraphicsContext, at p: CGPoint, heading: Double) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .radians(heading))
        c.scaleBy(x: 1.4, y: 1.4)
        var dart = Path()
        dart.move(to: CGPoint(x: 11, y: 0)); dart.addLine(to: CGPoint(x: -8, y: -8))
        dart.addLine(to: CGPoint(x: -4, y: 0)); dart.addLine(to: CGPoint(x: -8, y: 8)); dart.closeSubpath()
        c.fill(dart, with: .color(PropInk.paper))
        // The far wing, folded under, a shade darker.
        var fold = Path(); fold.move(to: CGPoint(x: 11, y: 0)); fold.addLine(to: CGPoint(x: -4, y: 0)); fold.addLine(to: CGPoint(x: -8, y: 8)); fold.closeSubpath()
        c.fill(fold, with: .color(PropInk.steam))
        c.stroke(dart, with: .color(PropInk.metalEdge), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
    }

    // Jump rope

    private func rope(_ ctx: inout GraphicsContext, front: Bool) {
        let h = Outdoor.hop(t)
        let dy = CGFloat(h[0])
        let phi = Outdoor.ropeAngle(t)
        let isFront = sin(phi) >= 0
        let a = CGPoint(x: 1, y: 60 + dy), b = CGPoint(x: 99, y: 60 + dy)
        if isFront == front {
            let midY = 46 + dy - 62 * CGFloat(cos(phi))
            var r = Path(); r.move(to: a)
            r.addQuadCurve(to: b, control: CGPoint(x: 50, y: 2 * midY - a.y))
            ctx.stroke(r, with: .color(PropInk.balloon), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        if front {
            for p in [a, b] {
                ctx.fill(Path(roundedRect: CGRect(x: p.x - 3, y: p.y - 1, width: 6, height: 13), cornerRadius: 3), with: .color(PropInk.wood))
            }
        }
    }

    // Hula hoop

    private func hoop(_ ctx: inout GraphicsContext, front: Bool) {
        let phi = Outdoor.hulaPhase(t)
        let center = CGPoint(x: 50 + CGFloat(0.5 * Outdoor.hulaDX(phi) - 4 * cos(phi)), y: 66 + CGFloat(1.5 * sin(phi)))
        stripedRing(&ctx, center: center, rx: 50, ry: 11, tilt: 0.1 * sin(phi + 1), front: front,
                    width: 5.6, spin: -phi, pairs: 6, colors: (PropInk.cover, PropInk.paper))
    }

    // Skateboard

    private func speedLines(_ ctx: inout GraphicsContext) {
        let rows: [CGFloat] = [22, 40, 58, 74, 32, 66]
        for (i, y) in rows.enumerated() {
            let q = phase(t * 1.5 + Double(i) * 0.37, 1)
            let x = 106 - 128 * CGFloat(q)
            ctx.stroke(segment(CGPoint(x: x, y: y), CGPoint(x: x + 14, y: y)),
                       with: .color(cord.opacity(0.85 * bump(q))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func board(_ ctx: inout GraphicsContext) {
        let o = Outdoor.ollie(t)
        // Ground dashes streaming past.
        for i in 0..<3 {
            let q = phase(t * 1.8 + Double(i) / 3, 1)
            let x = 108 - 126 * CGFloat(q)
            ctx.stroke(segment(CGPoint(x: x, y: 112), CGPoint(x: x + 10, y: 112)),
                       with: .color(cord.opacity(0.5 * bump(q))), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        var c = riding(ctx, dy: -14 * o.h)
        c.translateBy(x: 50, y: 98); c.rotate(by: .degrees(o.tilt)); c.translateBy(x: -50, y: -98)
        for x in [CGFloat(24), 76] {
            c.fill(Path(CGRect(x: x - 3, y: 98, width: 6, height: 3.5)), with: .color(PropInk.metalEdge))
            c.fill(circle(CGPoint(x: x, y: 104), 4.4), with: .color(star))
            c.fill(circle(CGPoint(x: x, y: 104), 1.6), with: .color(PropInk.metalEdge))
        }
        var deck = Path()
        deck.move(to: CGPoint(x: 1, y: 92)); deck.addQuadCurve(to: CGPoint(x: 12, y: 97.5), control: CGPoint(x: 4, y: 97.5))
        deck.addLine(to: CGPoint(x: 88, y: 97.5)); deck.addQuadCurve(to: CGPoint(x: 99, y: 92), control: CGPoint(x: 96, y: 97.5))
        c.stroke(deck, with: .color(PropInk.metalEdge), style: StrokeStyle(lineWidth: 6.2, lineCap: .round, lineJoin: .round))
        c.stroke(deck, with: .color(PropInk.wood), style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round))
    }

    // Snowfall

    private func snowflake(_ ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat, spin: Double, color: Color) {
        var arms = Path()
        for i in 0..<3 {
            let a = spin + Double(i) * .pi / 3
            let d = CGPoint(x: r * CGFloat(cos(a)), y: r * CGFloat(sin(a)))
            arms.move(to: CGPoint(x: p.x - d.x, y: p.y - d.y)); arms.addLine(to: CGPoint(x: p.x + d.x, y: p.y + d.y))
        }
        ctx.stroke(arms, with: .color(color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
    }

    private func snowField(_ ctx: inout GraphicsContext, front: Bool) {
        let flakes: [(x: CGFloat, period: Double, off: Double, r: CGFloat, front: Bool)] = [
            (-9, 5.2, 0.10, 4.6, true), (108, 6.1, 0.55, 5.2, true), (121, 5.5, 0.05, 4, true), (2, 6.6, 0.62, 4, true),
            (28, 5.8, 0.35, 4.4, false), (80, 6.3, 0.85, 4.2, false), (50, 5.0, 0.7, 3.6, false),
        ]
        for (i, f) in flakes.enumerated() where f.front == front {
            let q = phase(t / f.period + f.off, 1)
            let x = f.x + 5 * CGFloat(sin(tau * (1.3 * q + Double(i) * 0.4)))
            let y = -24 + 134 * CGFloat(q)
            let alpha = min(1, q * 8, (1 - q) * 8)
            snowflake(&ctx, at: CGPoint(x: x, y: y), r: f.r, spin: t * 0.8 + Double(i), color: snow.opacity(alpha))
        }
    }

    private func caughtFlake(_ ctx: inout GraphicsContext) {
        let f = Outdoor.catchFlake(t)
        snowflake(&ctx, at: f.pos, r: 6 * CGFloat(0.5 + 0.5 * f.alpha), spin: f.landed > 0 ? 0.3 : t * 1.2, color: snow.opacity(f.alpha))
        if f.joy > 0 {
            for x in [CGFloat(25), 75] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: 56, width: 12, height: 6.5)), with: .color(PropInk.balloon.opacity(0.6 * f.joy)))
            }
        }
    }

    // Butterfly

    private func butterfly(_ ctx: inout GraphicsContext) {
        let b = Outdoor.butterfly(t)
        let flap = CGFloat(0.22 + 0.78 * abs(cos(tau * t / 0.32)))
        var c = ctx
        c.translateBy(x: b.pos.x, y: b.pos.y)
        c.rotate(by: .degrees(14 * b.facing))
        c.scaleBy(x: 1.45, y: 1.45)
        for side in [CGFloat(-1), 1] {
            var w = c
            w.scaleBy(x: side * flap, y: 1)
            w.fill(Path(ellipseIn: CGRect(x: 0.5, y: -10, width: 10.5, height: 10)), with: .color(PropInk.balloon))
            w.fill(Path(ellipseIn: CGRect(x: 0.5, y: -1, width: 7.5, height: 7.5)), with: .color(star))
            w.fill(circle(CGPoint(x: 6.5, y: -5.5), 1.8), with: .color(PropInk.paper.opacity(0.85)))
        }
        c.fill(Path(roundedRect: CGRect(x: -1.5, y: -7, width: 3, height: 13), cornerRadius: 1.5), with: .color(cord))
        var feelers = Path()
        feelers.move(to: CGPoint(x: -0.5, y: -6)); feelers.addQuadCurve(to: CGPoint(x: -4.5, y: -12), control: CGPoint(x: -1.5, y: -10))
        feelers.move(to: CGPoint(x: 0.5, y: -6)); feelers.addQuadCurve(to: CGPoint(x: 4.5, y: -12), control: CGPoint(x: 1.5, y: -10))
        c.stroke(feelers, with: .color(cord), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    // Dandelion

    private func tuft(_ ctx: inout GraphicsContext, at p: CGPoint, angle: Double, r: CGFloat, color: Color) {
        var t = Path()
        for da in [-0.7, 0, 0.7] {
            t.move(to: p)
            t.addLine(to: CGPoint(x: p.x + r * CGFloat(cos(angle + da)), y: p.y + r * CGFloat(sin(angle + da))))
        }
        ctx.stroke(t, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    private func dandelion(_ ctx: inout GraphicsContext) {
        let d = Outdoor.dandelion(t)
        let head = Outdoor.dandelionHead
        var stem = Path(); stem.move(to: CGPoint(x: 84, y: 84))
        stem.addQuadCurve(to: CGPoint(x: head.x, y: head.y + 2), control: CGPoint(x: 99, y: 68))
        ctx.stroke(stem, with: .color(PropInk.leaf), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        let s = CGFloat(d.full)
        if s > 0 {
            ctx.fill(circle(head, 16 * s), with: .color(fluff.opacity(0.2)))
            for i in 0..<Outdoor.seedCount {
                let a = Outdoor.seedAngle(i)
                let tip = CGPoint(x: head.x + 12 * s * CGFloat(cos(a)), y: head.y + 12 * s * CGFloat(sin(a)))
                ctx.stroke(segment(head, tip), with: .color(fluff.opacity(0.8)), lineWidth: 1.2)
                tuft(&ctx, at: tip, angle: a, r: 4.2 * s, color: fluff)
            }
        }
        ctx.fill(circle(head, 3.6), with: .color(PropInk.wood))
    }

    private func seedsAfloat(_ ctx: inout GraphicsContext) {
        guard let u = Outdoor.dandelion(t).flight else { return }
        let head = Outdoor.dandelionHead
        let e = 1 - (1 - u) * (1 - u)
        for i in 0..<Outdoor.seedCount {
            let a = Outdoor.seedAngle(i)
            let spread = CGFloat(8 + 6 * e) * CGFloat(e)
            let wobble = 3 * CGFloat(sin(tau * (u * 1.6 + Double(i) * 0.31)))
            let p = CGPoint(x: head.x + (12 + spread) * CGFloat(cos(a)) + CGFloat(16 * e) + wobble,
                            y: head.y + (12 + spread) * CGFloat(sin(a)) - CGFloat(42 * e) - CGFloat(i % 3) * 3 * CGFloat(e))
            var alpha = 1 - smooth((u - 0.55) / 0.4)
            alpha *= min(1, max(0, Double(124 - p.x) / 8)) * min(1, max(0, Double(p.y + 24) / 8))
            let lean = -Double.pi / 2 + 0.3 * sin(tau * u * 2 + Double(i))
            let stalk = CGPoint(x: p.x - 6 * CGFloat(cos(lean)), y: p.y - 6 * CGFloat(sin(lean)))
            ctx.stroke(segment(p, stalk), with: .color(fluff.opacity(alpha)), lineWidth: 1.2)
            ctx.fill(circle(stalk, 1.5), with: .color(PropInk.wood.opacity(alpha)))
            tuft(&ctx, at: p, angle: lean, r: 4.2, color: fluff.opacity(alpha))
        }
    }

    // Swim ring

    private func swimRing(_ ctx: inout GraphicsContext, front: Bool) {
        let s = Outdoor.swim(t)
        var c = riding(ctx, dy: s.dy, rot: s.rot)
        stripedRing(&c, center: CGPoint(x: 50, y: 77), rx: 50, ry: 11, tilt: 0, front: front,
                    width: 12, spin: 0.4, pairs: 4, colors: (PropInk.bad, PropInk.paper))
        guard front else { return }
        var surface = Path()
        for i in 0...28 {
            let x = -20 + 5 * Double(i)
            let y = 85 + 1.8 * sin(0.13 * x - 2.2 * t) + 0.9 * sin(0.31 * x + 1.3 * t)
            if i == 0 { surface.move(to: CGPoint(x: x, y: y)) } else { surface.addLine(to: CGPoint(x: x, y: y)) }
        }
        var water = surface
        water.addLine(to: CGPoint(x: 120, y: 114)); water.addLine(to: CGPoint(x: -20, y: 114)); water.closeSubpath()
        // Faded at the sides and the bottom, so the water has no box edges.
        var w = ctx
        w.clipToLayer { mask in
            mask.fill(Path(CGRect(x: -22, y: 60, width: 144, height: 60)),
                      with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                                             .init(color: .black, location: 0.84), .init(color: .clear, location: 1)]),
                                            startPoint: CGPoint(x: -20, y: 0), endPoint: CGPoint(x: 120, y: 0)))
        }
        w.fill(water, with: .linearGradient(Gradient(colors: [PropInk.water.opacity(0.75), PropInk.water.opacity(0.1)]),
                                            startPoint: CGPoint(x: 0, y: 84), endPoint: CGPoint(x: 0, y: 114)))
        w.stroke(surface, with: .color(PropInk.water), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Shared timing, so the body and its props agree

private enum Outdoor {
    // Fishing: a 6 s wait — nibbles, a bite, a fish leaps.
    static let pond = CGPoint(x: 106, y: 105)

    struct Fishing { var perk: Double; var lift: Double; var dip: Double; var fish: Double? }

    static func fishing(_ t: Double) -> Fishing {
        let p = phase(t, 6)
        var dip = 0.8 * sin(tau * t / 1.7)
        if p > 0.34 && p < 0.46 { dip += 2.4 * abs(sin((p - 0.34) / 0.12 * 3 * .pi)) }
        if p > 0.46 && p < 0.58 { dip += 7 * bump((p - 0.46) / 0.12) }
        let perk = smooth((p - 0.45) / 0.05) * (1 - smooth((p - 0.8) / 0.12))
        let fish: Double? = p > 0.55 && p < 0.8 ? (p - 0.55) / 0.25 : nil
        return Fishing(perk: perk, lift: -4 * perk, dip: dip, fish: fish)
    }

    /// The leap: out of the pond on the left, back in on the right.
    static func fishPoint(_ q: Double) -> CGPoint {
        CGPoint(x: 96 + 22 * q, y: 103 - 116 * q * (1 - q))
    }

    // Kite

    static func kite(_ t: Double) -> (pos: CGPoint, tilt: Double) {
        let x = 98 + 7 * sin(tau * t / 4.3) + 2 * sin(tau * t / 1.7)
        let y = 1 + 3 * sin(tau * t / 3.1 + 1)
        return (CGPoint(x: x, y: y), 8 + 10 * sin(tau * t / 4.3 + 0.6))
    }

    // Paper plane: wind up, throw, a loop round the blob (passing under the eyes on the way back), caught again.

    static let loopCenter = CGPoint(x: 54, y: 26)
    static let loopStart = 50.0 * .pi / 180

    static func plane(_ t: Double) -> (pos: CGPoint, heading: Double, windup: Double, kick: Double) {
        let p = phase(t, 5)
        func at(_ th: Double) -> CGPoint {
            CGPoint(x: loopCenter.x + 60 * CGFloat(cos(th)), y: loopCenter.y + 38 * CGFloat(sin(th)))
        }
        let hand = at(loopStart)
        let rest = atan2(-38 * cos(loopStart), 60 * sin(loopStart))
        let kick = p > 0.2 && p < 0.38 ? bump((p - 0.2) / 0.18) : 0
        if p < 0.2 {
            let w = bump(p / 0.2)
            return (CGPoint(x: hand.x - 5 * CGFloat(w), y: hand.y + 3 * CGFloat(w)), rest + 0.3 * w, w, 0)
        }
        if p >= 0.9 { return (hand, rest, 0, 0) }
        let q = (p - 0.2) / 0.7
        let th = loopStart - tau * (0.35 * q + 0.65 * smooth(q))
        return (at(th), atan2(-38 * cos(th), 60 * sin(th)), 0, kick)
    }

    // Jump rope: one turn every 0.9 s, the hop timed to clear it at the bottom.

    static func ropeAngle(_ t: Double) -> Double { tau * phase(t, 0.9) }

    /// [dy, sx, sy]
    static func hop(_ t: Double) -> [Double] {
        Motion.spline(phase(t, 0.9), [
            (0.00, [0, 1.00, 1.00]), (0.18, [0, 1.06, 0.93]), (0.30, [-6, 0.97, 1.04]),
            (0.50, [-11, 1.00, 1.00]), (0.68, [-4, 0.98, 1.02]), (0.80, [0, 1.07, 0.92]),
            (0.92, [0, 1.00, 1.00]), (1.00, [0, 1.00, 1.00]),
        ])
    }

    // Hula hoop

    static func hulaPhase(_ t: Double) -> Double { tau * phase(t, 0.9) }
    static func hulaDX(_ phi: Double) -> Double { 3.5 * cos(phi) }

    // Skateboard: an ollie every 4 s.

    static func ollie(_ t: Double) -> (h: Double, tilt: Double, squash: Double) {
        let p = phase(t, 4)
        let q = (p - 0.5) / 0.22
        let h = q > 0 && q < 1 ? 4 * q * (1 - q) : 0
        let tilt = q > 0 && q < 1 ? -14 * sin(.pi * min(q * 2, 1)) : 0
        let squash = bump((p - 0.44) / 0.06) + bump((p - 0.72) / 0.08)
        return (h, tilt, squash)
    }

    // Snowfall: one flake every 6 s drifts onto the head and melts there.

    static func catchFlake(_ t: Double) -> (pos: CGPoint, alpha: Double, landed: Double, joy: Double, hop: Double) {
        let p = phase(t, 6)
        let q = min(p / 0.45, 1)
        let x = 60 + 7 * sin(tau * 1.2 * q) * (1 - q)
        let y = -24 + 30 * q
        var alpha = min(1, p / 0.05)
        if p > 0.85 { alpha = 1 - (p - 0.85) / 0.15 }
        let landed = p >= 0.45 ? 1.0 : 0
        let joy = smooth((p - 0.53) / 0.05) * (1 - smooth((p - 0.8) / 0.08))
        let hop = p > 0.45 && p < 0.57 ? bump((p - 0.45) / 0.12) : 0
        return (CGPoint(x: x, y: y), alpha, landed, joy, hop)
    }

    // Butterfly: a figure-8 over the head every 7 s.

    static func butterfly(_ t: Double) -> (pos: CGPoint, facing: Double) {
        let a = tau * phase(t, 7)
        let x = 50 + 52 * sin(a)
        let y = 8 + 12 * sin(2 * a) + 2 * sin(t * 5.3)
        return (CGPoint(x: x, y: y), cos(a) >= 0 ? 1 : -1)
    }

    // Dandelion: hold, breathe in, puff — seeds sail away — the head grows back.

    static let dandelionHead = CGPoint(x: 100, y: 34)
    static let seedCount = 10
    static func seedAngle(_ i: Int) -> Double { tau * Double(i) / Double(seedCount) + 0.25 }

    static func dandelion(_ t: Double) -> (p: Double, full: Double, flight: Double?) {
        let p = phase(t, 6)
        let full = p < 0.46 ? 1 : smooth((p - 0.8) / 0.2)
        let flight: Double? = p >= 0.46 ? (p - 0.46) / 0.54 : nil
        return (p, full, flight)
    }

    // Swim ring: bobbing on the swell.

    static func swim(_ t: Double) -> (dy: Double, rot: Double) {
        (2.4 * sin(tau * t / 2.6), 3 * sin(tau * t / 4.1 + 0.7))
    }
}
