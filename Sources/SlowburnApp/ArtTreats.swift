import SwiftUI

// Treats, sport and lazing about.

extension Motion {
    mutating func poseIceCream(_ t: Double) {
        var m = self
        let lift = Treat.coneLift(t), lick = Treat.lickStroke(t)
        // Eyeing the cone at the side, then a blissful squint while licking.
        m.lookX = 4 - 2 * lift
        m.lookY = 3 + 1 * lift
        if lift > 0.4 { m.blink = 1 - 0.7 * smooth((lift - 0.4) / 0.6) }
        m.rot = m.rot * 0.5 + 3 * lift - 2 * lick
        m.dy += -1.4 * lick
        self = m
    }

    mutating func poseWatermelon(_ t: Double) {
        var m = self
        let lift = Treat.melonLift(t), chew = Treat.melonChew(t)
        m.lookX = 0.8 * sin(tau * t / 3.7)
        m.lookY = 5 - 2 * lift
        m.dy += 1.5 * lift
        m.sy = 1 - 0.03 * lift - 0.025 * chew * abs(sin(tau * t / 0.3))
        m.sx = 1 + 0.03 * lift
        if chew > 0.1 { m.blink = 0.3 }
        self = m
    }

    mutating func posePopcorn(_ t: Double) {
        var m = self
        let chomp = Treat.popChomp(t)
        if let k = Treat.kernel(t) {
            m.lookX = min(max((Double(k.x) - 50) / 5, -5.5), 5.5)
            m.lookY = min(max((Double(k.y) - 42) / 7, -6), 5)
        } else {
            m.lookX = 0; m.lookY = 3
        }
        if chomp > 0.2 { m.blink = 0.3 }
        m.sy = 1 - 0.04 * chomp
        m.sx = 1 + 0.03 * chomp
        self = m
    }

    mutating func poseCampfire(_ t: Double) {
        var m = self
        let eat = Treat.eatSwing(t), munch = Treat.munch(t)
        m.lookX = 5 - 3 * eat
        m.lookY = 3 - 4 * eat
        m.rot = 2 + m.rot * 0.4 - 2 * eat
        if munch > 0.1 { m.blink = 0.3 }
        m.sy = 1 - 0.03 * munch * abs(sin(tau * t / 0.32))
        self = m
    }

    mutating func poseSunbathing(_ t: Double) {
        var m = self
        // Melted into the towel; once in a while a peek over the shades at the sun.
        let peek = Treat.peek(t)
        let breath = sin(tau * t / 5)
        m.rot = -5 + 0.8 * breath
        m.sx = 1.05 + 0.012 * breath
        m.sy = 0.95 - 0.012 * breath
        m.dy = 0
        m.blink = 0.3 + 0.7 * peek
        m.lookX = 3 * peek
        m.lookY = 1 - 7 * peek
        self = m
    }

    mutating func poseRain(_ t: Double) {
        var m = self
        let look = Motion.keyframes(phase(t, 7), [
            (0.0, [-4, -2]), (0.3, [-4, -2]), (0.42, [3, -4]), (0.7, [3, -4]), (0.82, [5, 1]), (0.92, [5, 1]), (1.0, [-4, -2]),
        ])
        m.lookX = look[0]; m.lookY = look[1]
        m.rot = m.rot * 0.6 + 1.5 * sin(tau * t / 3.3)
        // A little splash-hop in the puddle every few seconds.
        let hop = bump((phase(t, 3.5) - 0.8) / 0.12)
        m.dy += -4 * hop
        m.sy *= 1 + 0.03 * hop
        self = m
    }

    mutating func poseHammock(_ t: Double) {
        var m = self
        let s = Treat.swing(t)
        let breath = sin(tau * t / 4)
        m.rot = -4 + 3 * s
        m.dx = 4 * s
        m.dy = 4
        m.sx = 1.16 + 0.02 * breath
        m.sy = 0.74 - 0.02 * breath
        m.blink = 0.14
        m.lookX = 0; m.lookY = 2
        self = m
    }

    mutating func poseDumbbells(_ t: Double) {
        var m = self
        let lift = Treat.barLift(t), strain = Treat.strain(t)
        m.sy = 1 - 0.08 * lift - 0.02 * strain * sin(t * 47)
        m.sx = 1 + 0.06 * lift
        m.dx = 0.7 * strain * sin(t * 53)
        m.rot = m.rot * 0.3
        m.lookX = 0
        m.lookY = -2 - 2 * lift
        if strain > 0.2 { m.blink = 0.3 }
        self = m
    }

    mutating func poseBasketball(_ t: Double) {
        var m = self
        let b = Treat.basketball(t)
        m.lookX = min(max((Double(b.ball.x) - 50) / 7, -5), 6)
        m.lookY = min(max((Double(b.ball.y) - 50) / 7, -6), 5)
        m.dy += -1.6 * b.bob - 9 * b.jump
        m.sy = 1 - 0.06 * b.crouch + 0.05 * b.jump
        m.sx = 1 + 0.05 * b.crouch - 0.03 * b.jump
        m.rot = m.rot * 0.5 + 2
        self = m
    }

    mutating func poseFootball(_ t: Double) {
        var m = self
        let f = Treat.football(t)
        m.dy += -3 * f.hop
        m.sy = 1 + 0.04 * f.hop
        m.sx = 1 - 0.03 * f.hop
        m.rot = m.rot * 0.3 + 10 * f.lean
        m.dx = 2.5 * f.lean
        m.lookX = min(max((Double(f.ball.x) - 50) / 7, -5), 6)
        m.lookY = min(max((Double(f.ball.y) - 40) / 6, -6), 5)
        self = m
    }
}

extension ActivityProps {
    func drawIceCream(_ ctx: inout GraphicsContext) {
        if layer == .held { iceCone(&ctx) }
    }

    func drawWatermelon(_ ctx: inout GraphicsContext) {
        if layer == .held { melonSlice(&ctx) }
    }

    func drawPopcorn(_ ctx: inout GraphicsContext) {
        if layer == .front { popcornBucket(&ctx) }
    }

    func drawCampfire(_ ctx: inout GraphicsContext) {
        if layer == .behind { fireGlow(&ctx) }
        if layer == .held { roastingStick(&ctx) }
        if layer == .front { campfire(&ctx) }
    }

    func drawSunbathing(_ ctx: inout GraphicsContext) {
        if layer == .behind { sunAndTowel(&ctx) }
        if layer == .held { shades(&ctx) }
    }

    func drawRain(_ ctx: inout GraphicsContext) {
        if layer == .behind { puddle(&ctx) }
        if layer == .held { umbrella(&ctx) }
        if layer == .front { raindrops(&ctx) }
    }

    func drawHammock(_ ctx: inout GraphicsContext) {
        if layer == .behind { hammockBack(&ctx) }
        if layer == .front { hammockFront(&ctx) }
    }

    func drawDumbbells(_ ctx: inout GraphicsContext) {
        if layer == .held { barbell(&ctx) }
    }

    func drawBasketball(_ ctx: inout GraphicsContext) {
        if layer == .front { hoopAndBall(&ctx) }
    }

    func drawFootball(_ ctx: inout GraphicsContext) {
        if layer == .front { soccerBall(&ctx) }
    }

    // MARK: Pieces

    /// Fill, then outline: light fills still read on the light popover.
    private func inked(_ ctx: inout GraphicsContext, _ path: Path, _ fill: Color, _ edge: Color, _ width: CGFloat = 1.6) {
        ctx.fill(path, with: .color(fill))
        ctx.stroke(path, with: .color(edge), style: StrokeStyle(lineWidth: width, lineJoin: .round))
    }

    private var rainInk: Color { dark ? PropInk.water : Color(hex: 0x3A86CC) }

    private func iceCone(_ ctx: inout GraphicsContext) {
        let lift = Treat.coneLift(t), lick = Treat.lickStroke(t)
        // A tongue pokes out to meet the scoop on every lick.
        if lick > 0.05 {
            let tongue = Path(roundedRect: CGRect(x: 58, y: 66, width: 5 + 6 * lick, height: 7), cornerRadius: 3.5)
            inked(&ctx, tongue, TreatInk.tongue, TreatInk.tongueEdge, 1.4)
        }
        var c = ctx
        c.translateBy(x: 97 - 16 * lift - 2 * lick, y: 70 + 6 * lift)
        c.rotate(by: .degrees(8 - 43 * lift))
        c.scaleBy(x: 1.2, y: 1.2)
        let cone = Path { p in
            p.move(to: CGPoint(x: -8.5, y: 0)); p.addLine(to: CGPoint(x: 8.5, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 26)); p.closeSubpath()
        }
        c.fill(cone, with: .color(TreatInk.waffle))
        var waffle = c
        waffle.clip(to: cone)
        for i in -3...3 {
            let x = CGFloat(i) * 6
            waffle.stroke(segment(CGPoint(x: x - 12, y: 0), CGPoint(x: x + 12, y: 26)), with: .color(TreatInk.waffleEdge), lineWidth: 1.1)
            waffle.stroke(segment(CGPoint(x: x + 12, y: 0), CGPoint(x: x - 12, y: 26)), with: .color(TreatInk.waffleEdge), lineWidth: 1.1)
        }
        c.stroke(cone, with: .color(TreatInk.waffleEdge), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        inked(&c, circle(CGPoint(x: 0, y: -3), 9.5), TreatInk.berry, TreatInk.berryEdge)
        // A drip gathers at the scoop's rim, runs down the cone and falls.
        let q = phase(t, 3.3)
        let drip: CGPoint, r: CGFloat
        if q < 0.45 { drip = CGPoint(x: 6.5, y: 4); r = 1.2 + 1.6 * q / 0.45 }
        else if q < 0.85 { let u = (q - 0.45) / 0.4; drip = CGPoint(x: 6.5 - 2.5 * u, y: 4 + 11 * u); r = 2.8 }
        else { let u = (q - 0.85) / 0.15; drip = CGPoint(x: 4, y: 15 + 16 * u * u); r = 2.8 * (1 - 0.4 * u) }
        var d = c
        if q > 0.85 { d.opacity = 1 - (q - 0.85) / 0.15 }
        inked(&d, circle(drip, r), TreatInk.berry, TreatInk.berryEdge, 1.2)
        inked(&c, circle(CGPoint(x: 0, y: -15), 8), TreatInk.mint, TreatInk.mintEdge)
        c.stroke(segment(CGPoint(x: 1.5, y: -25), CGPoint(x: 4, y: -31)), with: .color(TreatInk.mintEdge), lineWidth: 1.6)
        c.fill(circle(CGPoint(x: 1.5, y: -24), 3.4), with: .color(TreatInk.cherry))
    }

    private func melonSlice(_ ctx: inout GraphicsContext) {
        let lift = Treat.melonLift(t), fresh = Treat.melonFresh(t), bitten = Treat.melonBitten(t)
        let notches: [CGFloat] = [9, -9, 19, -19]
        let top = 70 - 8 * lift + 20 * (1 - fresh)
        var c = ctx
        c.opacity = fresh
        c.translateBy(x: 50, y: top)
        c.rotate(by: .degrees(-3 * lift))
        func half(_ r: CGFloat) -> Path {
            Path { p in
                p.move(to: CGPoint(x: r, y: 0))
                p.addArc(center: .zero, radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                p.closeSubpath()
            }
        }
        c.clipToLayer { l in
            l.fill(Path(CGRect(x: -40, y: -20, width: 80, height: 60)), with: .color(.black))
            l.blendMode = .destinationOut
            for x in notches.prefix(bitten) {
                for (dx, dy) in [(-4.5, 0.5), (0.0, 3.0), (4.5, 0.5)] {
                    l.fill(circle(CGPoint(x: x + dx, y: dy), 5.2), with: .color(.black))
                }
            }
        }
        c.fill(half(28), with: .color(TreatInk.rind))
        c.fill(half(24.5), with: .color(TreatInk.rindPale))
        c.fill(half(22), with: .color(TreatInk.flesh))
        for (x, y, a) in [(-14.0, 7.0, 30.0), (-3.0, 12.0, 10.0), (9.0, 8.0, -20.0), (16.0, 13.0, -40.0), (-10.0, 16.0, 40.0), (3.0, 19.0, 0.0)] {
            var s = c
            s.translateBy(x: x, y: y)
            s.rotate(by: .degrees(a))
            s.fill(Path(ellipseIn: CGRect(x: -2, y: -3, width: 4, height: 6)), with: .color(TreatInk.seed))
        }
        // Seeds spat out after each bite.
        let p = phase(t, Treat.melonPeriod)
        for (i, b) in Treat.melonBites.enumerated() where p >= b && p < b + 0.1 {
            let q = (p - b) / 0.1
            let x0 = 50 + notches[i], y0 = 62.0
            for dir in [-1.0, 1.0] {
                var s = ctx
                s.opacity = 1 - q * q * q
                s.translateBy(x: x0 + dir * (6 + 26 * q), y: y0 - 18 * q + 40 * q * q)
                s.rotate(by: .degrees(dir * 400 * q))
                s.fill(Path(ellipseIn: CGRect(x: -2, y: -3, width: 4, height: 6)), with: .color(cord))
            }
        }
    }

    /// A popped kernel: three overlapping puffs, outlined once around the outside.
    private func kernelPuff(_ ctx: inout GraphicsContext, at c: CGPoint, r: CGFloat) {
        let puffs = [circle(CGPoint(x: c.x - 0.5 * r, y: c.y + 0.25 * r), 0.68 * r),
                     circle(CGPoint(x: c.x + 0.5 * r, y: c.y + 0.3 * r), 0.68 * r),
                     circle(CGPoint(x: c.x, y: c.y - 0.35 * r), 0.75 * r)]
        for p in puffs { ctx.stroke(p, with: .color(TreatInk.cornEdge), lineWidth: 2.8) }
        for p in puffs { ctx.fill(p, with: .color(TreatInk.corn)) }
    }

    private func popcornBucket(_ ctx: inout GraphicsContext) {
        // The heap, with one kernel hopping in it.
        let hopper = bump(phase(t, 0.9) / 0.5)
        for (x, y) in [(36.0, 71.0), (45.0, 67.0), (55.0, 68.0), (64.0, 71.0), (50.0, 73.0)] {
            kernelPuff(&ctx, at: CGPoint(x: x, y: y), r: 6)
        }
        kernelPuff(&ctx, at: CGPoint(x: 41 + 18 * Treat.hash(floor(t / 0.9)), y: 69 - 8 * hopper), r: 5)
        let bucket = Path { p in
            p.move(to: CGPoint(x: 30, y: 74)); p.addLine(to: CGPoint(x: 70, y: 74))
            p.addLine(to: CGPoint(x: 65, y: 105)); p.addLine(to: CGPoint(x: 35, y: 105)); p.closeSubpath()
        }
        ctx.fill(bucket, with: .color(TreatInk.paper))
        var stripes = ctx
        stripes.clip(to: bucket)
        for i in stride(from: 0, to: 5, by: 2) {
            let a = CGFloat(i), b = CGFloat(i + 1)
            let s = Path { p in
                p.move(to: CGPoint(x: 30 + 8 * a, y: 74)); p.addLine(to: CGPoint(x: 30 + 8 * b, y: 74))
                p.addLine(to: CGPoint(x: 35 + 6 * b, y: 105)); p.addLine(to: CGPoint(x: 35 + 6 * a, y: 105)); p.closeSubpath()
            }
            stripes.fill(s, with: .color(TreatInk.bucket))
        }
        ctx.stroke(bucket, with: .color(TreatInk.bucketEdge), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        inked(&ctx, Path(roundedRect: CGRect(x: 28, y: 72, width: 44, height: 5), cornerRadius: 2), TreatInk.paper, TreatInk.bucketEdge)
        if let k = Treat.kernel(t) { kernelPuff(&ctx, at: k, r: 5) }
    }

    private func fireGlow(_ ctx: inout GraphicsContext) {
        let flick = 0.85 + 0.15 * sin(t * 11) * sin(t * 7.3)
        let c = CGPoint(x: 106, y: 84)
        ctx.fill(circle(c, 44), with: .radialGradient(Gradient(colors: [PropInk.fire.opacity(0.45 * flick), PropInk.fire.opacity(0)]),
                                                      center: c, startRadius: 0, endRadius: 44))
    }

    private func roastingStick(_ ctx: inout GraphicsContext) {
        let eat = Treat.eatSwing(t), toast = Treat.toast(t)
        var c = ctx
        c.translateBy(x: 80, y: 74)
        c.rotate(by: .degrees(-26 - 72 * eat))
        c.scaleBy(x: 1.2, y: 1.2)
        c.stroke(segment(.zero, CGPoint(x: 30, y: 0)), with: .color(TreatInk.stick), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        if Treat.hasMarshmallow(t) {
            let puff = Path(roundedRect: CGRect(x: 21, y: -5, width: 11, height: 10), cornerRadius: 3.5)
            inked(&c, puff, Treat.mix(0xFBF6EC, 0xE9A945, toast), Treat.mix(0xB9B4AC, 0x9A5A22, toast))
            // Toasted edges darken last.
            if toast > 0.5 {
                c.stroke(Path(roundedRect: CGRect(x: 22, y: -4, width: 9, height: 8), cornerRadius: 3),
                         with: .color(Color(hex: 0xB06A2E).opacity(1.4 * (toast - 0.5))), lineWidth: 1.6)
            }
        }
    }

    private func flame(_ base: CGPoint, w: CGFloat, h: CGFloat, lean: CGFloat) -> Path {
        Path { p in
            let tip = CGPoint(x: base.x + lean, y: base.y - h)
            p.move(to: base)
            p.addQuadCurve(to: tip, control: CGPoint(x: base.x - w, y: base.y - h * 0.4))
            p.addQuadCurve(to: base, control: CGPoint(x: base.x + w, y: base.y - h * 0.4))
        }
    }

    private func campfire(_ ctx: inout GraphicsContext) {
        var ctx = ctx
        ctx.translateBy(x: 106, y: 101)
        ctx.scaleBy(x: 1.3, y: 1.3)
        ctx.translateBy(x: -106, y: -101)
        let base = CGPoint(x: 106, y: 100)
        let h = 25 + 3 * sin(t * 9) + 2 * sin(t * 13.7)
        let lean = 3 * sin(t * 5.3)
        ctx.fill(flame(base, w: 14, h: h, lean: lean), with: .color(PropInk.fire))
        ctx.fill(flame(CGPoint(x: base.x + 1, y: base.y), w: 9, h: h * 0.68, lean: -lean * 0.7), with: .color(Color(hex: 0xFFB43C)))
        ctx.fill(flame(CGPoint(x: base.x, y: base.y), w: 5, h: h * 0.4, lean: lean * 0.5), with: .color(Color(hex: 0xFFE38A)))
        for a in [-17.0, 17.0] {
            var log = ctx
            log.translateBy(x: base.x, y: base.y + 3)
            log.rotate(by: .degrees(a))
            inked(&log, Path(roundedRect: CGRect(x: -15, y: -3.5, width: 30, height: 7), cornerRadius: 3.5), PropInk.wood, TreatInk.woodEdge)
        }
        for i in 0..<4 {
            let q = phase(t + Double(i) * 0.41, 1.6)
            let x = base.x + 7 * sin(Double(i) * 2.1 + q * 5)
            let p = CGPoint(x: x, y: base.y - 16 - 46 * q)
            ctx.fill(circle(p, 2 * (1 - 0.4 * q)), with: .color((i % 2 == 0 ? star : PropInk.fire).opacity(1 - q)))
        }
    }

    private func sunAndTowel(_ ctx: inout GraphicsContext) {
        let towel = Path(roundedRect: CGRect(x: -6, y: 89, width: 112, height: 13), cornerRadius: 3)
        ctx.fill(towel, with: .color(TreatInk.towel))
        var stripes = ctx
        stripes.clip(to: towel)
        stripes.fill(Path(CGRect(x: -6, y: 93.5, width: 112, height: 4)), with: .color(TreatInk.paper))
        let sun = CGPoint(x: 102, y: -4)
        ctx.fill(circle(sun, 15), with: .radialGradient(Gradient(colors: [star.opacity(0.5), star.opacity(0)]),
                                                        center: sun, startRadius: 6, endRadius: 22))
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 + t * 0.5
            let ray = segment(CGPoint(x: sun.x + 13 * cos(a), y: sun.y + 13 * sin(a)), CGPoint(x: sun.x + 19 * cos(a), y: sun.y + 19 * sin(a)))
            ctx.stroke(ray, with: .color(star), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
        ctx.fill(circle(sun, 9.5), with: .color(star))
    }

    private func shades(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 0, y: 9 * Treat.peek(t))
        let frame = TreatInk.shadeFrame
        c.stroke(segment(CGPoint(x: 26, y: 44), CGPoint(x: 11, y: 40)), with: .color(frame), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        c.stroke(segment(CGPoint(x: 74, y: 44), CGPoint(x: 89, y: 40)), with: .color(frame), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        var bridge = Path(); bridge.move(to: CGPoint(x: 47, y: 44)); bridge.addQuadCurve(to: CGPoint(x: 53, y: 44), control: CGPoint(x: 50, y: 40))
        c.stroke(bridge, with: .color(frame), lineWidth: 2.4)
        for x in [CGFloat(25), 52] {
            let lens = Path(roundedRect: CGRect(x: x, y: 39, width: 23, height: 17), cornerRadius: 7, style: .continuous)
            c.fill(lens, with: .color(TreatInk.lens))
            c.stroke(lens, with: .color(frame), lineWidth: 2)
            c.stroke(segment(CGPoint(x: x + 5, y: 49), CGPoint(x: x + 11, y: 43)), with: .color(Color.white.opacity(0.55)),
                     style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private func puddle(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: -16, y: 95, width: 136, height: 11)
        ctx.fill(Path(ellipseIn: rect), with: .color(rainInk.opacity(0.3)))
        ctx.stroke(Path(ellipseIn: rect), with: .color(rainInk.opacity(0.7)), lineWidth: 1.6)
    }

    private func umbrella(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 80, y: 78)
        c.rotate(by: .degrees(Treat.umbrellaAngle(t)))
        c.stroke(segment(CGPoint(x: 0, y: 4), CGPoint(x: 0, y: -99)), with: .color(cord), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        var hook = Path()
        hook.addArc(center: CGPoint(x: -5, y: 4), radius: 5, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        c.stroke(hook, with: .color(cord), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        let tips: [CGFloat] = [-46, -23, 0, 23, 46]
        let rimY: CGFloat = -76, apex = CGPoint(x: 0, y: -96)
        // Four panels, alternately tinted and pale, each bowing up between its rib tips.
        for i in 0..<4 {
            let a = tips[i], b = tips[i + 1]
            let panel = Path { p in
                p.move(to: apex)
                p.addQuadCurve(to: CGPoint(x: a, y: rimY), control: CGPoint(x: a * 0.85, y: apex.y + 2))
                p.addQuadCurve(to: CGPoint(x: b, y: rimY), control: CGPoint(x: (a + b) / 2, y: rimY - 7))
                p.addQuadCurve(to: apex, control: CGPoint(x: b * 0.85, y: apex.y + 2))
                p.closeSubpath()
            }
            c.fill(panel, with: .color(tint))
            if i % 2 == 1 { c.fill(panel, with: .color(Color.white.opacity(0.45))) }
            c.stroke(panel, with: .color(Color.black.opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        }
        c.stroke(segment(apex, CGPoint(x: 0, y: -101)), with: .color(cord), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        // Raindrops pattering on the canopy.
        for i in 0..<3 {
            let q = phase(t + Double(i) * 0.29, 0.85)
            guard q < 0.35 else { continue }
            let u = q / 0.35
            let x = CGFloat(-28 + 28 * i)
            let y = rimY - 20 * (1 - pow(x / 46, 2)) - 2
            for dir in [-1.0, 1.0] {
                c.fill(circle(CGPoint(x: x + dir * 6 * u, y: y - 5 * bump(u)), 1.6), with: .color(rainInk.opacity(1 - u)))
            }
        }
    }

    private func raindrops(_ ctx: inout GraphicsContext) {
        let lanes: [(CGFloat, Double)] = [(-15, 0.0), (-5, 0.47), (5, 0.21), (110, 0.66), (120, 0.33)]
        let ground: CGFloat = 101
        for (x, off) in lanes {
            let q = phase(t + off * 0.8, 0.8)
            if q < 0.78 {
                let y = -24 + (ground + 24) * q / 0.78
                ctx.stroke(segment(CGPoint(x: x - 1.2, y: y - 8), CGPoint(x: x, y: y)), with: .color(rainInk),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            } else {
                let u = (q - 0.78) / 0.22
                for dir in [-1.0, 1.0] {
                    ctx.fill(circle(CGPoint(x: x + dir * 6 * u, y: ground - 6 * bump(u)), 1.7), with: .color(rainInk.opacity(1 - u)))
                }
                let w = 6 + 12 * u
                ctx.stroke(Path(ellipseIn: CGRect(x: x - w / 2, y: ground - w / 6, width: w, height: w / 3)),
                           with: .color(rainInk.opacity(1 - u)), lineWidth: 1.6)
            }
        }
    }

    private func hammockBack(_ ctx: inout GraphicsContext) {
        let s = Treat.swing(t)
        for x in [CGFloat(-16), 116] {
            inked(&ctx, Path(roundedRect: CGRect(x: x - 3.5, y: 34, width: 7, height: 82), cornerRadius: 2), PropInk.wood, TreatInk.woodEdge)
        }
        for (post, end) in [(CGPoint(x: -16, y: 40), CGPoint(x: -4, y: 66)), (CGPoint(x: 116, y: 40), CGPoint(x: 104, y: 66))] {
            for dy in [-3.0, 3.0] {
                ctx.stroke(segment(post, CGPoint(x: end.x, y: end.y + dy)), with: .color(cord), lineWidth: 1.6)
            }
        }
        // The far edge of the canvas, above and behind the body.
        var back = Path()
        back.move(to: CGPoint(x: -4, y: 66))
        back.addQuadCurve(to: CGPoint(x: 104, y: 66), control: CGPoint(x: 50 + 4 * s, y: 72))
        back.addLine(to: CGPoint(x: 104, y: 70))
        back.addQuadCurve(to: CGPoint(x: -4, y: 70), control: CGPoint(x: 50 + 4 * s, y: 120))
        back.closeSubpath()
        inked(&ctx, back, TreatInk.canvasShade, TreatInk.canvasEdge)
    }

    private func hammockFront(_ ctx: inout GraphicsContext) {
        let s = CGFloat(Treat.swing(t))
        let mid = 50 + 4 * s
        var sling = Path()
        sling.move(to: CGPoint(x: -4, y: 66))
        sling.addQuadCurve(to: CGPoint(x: 104, y: 66), control: CGPoint(x: mid, y: 94))
        sling.addQuadCurve(to: CGPoint(x: -4, y: 66), control: CGPoint(x: mid, y: 146))
        sling.closeSubpath()
        ctx.fill(sling, with: .color(TreatInk.canvas))
        var stripes = ctx
        stripes.clip(to: sling)
        for c in [CGFloat(108), 122] {
            var line = Path(); line.move(to: CGPoint(x: -4, y: 66)); line.addQuadCurve(to: CGPoint(x: 104, y: 66), control: CGPoint(x: mid, y: c))
            stripes.stroke(line, with: .color(TreatInk.paper), lineWidth: 3)
        }
        ctx.stroke(sling, with: .color(TreatInk.canvasEdge), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        for i in 0..<3 {
            let q = phase(t + Double(i), 3)
            let alpha = q < 0.2 ? q / 0.2 : (1 - q) / 0.8
            label(&ctx, "z", at: CGPoint(x: 78 + 18 * q + 4 * sin(q * 6) + 2 * s, y: 44 - 50 * q),
                  size: 14 + 6 * q, color: cord.opacity(alpha), design: .rounded)
        }
    }

    private func barbell(_ ctx: inout GraphicsContext) {
        let lift = Treat.barLift(t), strain = Treat.strain(t)
        let y = 74 - 80 * lift
        let bend = 2.5 * strain
        var bar = Path()
        bar.move(to: CGPoint(x: -14, y: y + bend)); bar.addQuadCurve(to: CGPoint(x: 114, y: y + bend), control: CGPoint(x: 50, y: y - bend))
        ctx.stroke(bar, with: .color(cord), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        for side in [-1.0, 1.0] {
            let cx = 50 + side * 54
            for (dx, h) in [(0.0, 28.0), (7.0, 20.0)] {
                let x = cx + side * dx
                inked(&ctx, Path(roundedRect: CGRect(x: x - 3.5, y: y + bend - h / 2, width: 7, height: h), cornerRadius: 2.5),
                      TreatInk.plate, cord)
            }
        }
        // Sweat at the top of the lift.
        if strain > 0 {
            let q = phase(t, Treat.liftPeriod)
            let u = min(max((q - 0.3) / 0.32, 0), 1)
            for (x0, dir) in [(84.0, 1.0), (16.0, -1.0)] {
                var d = ctx
                d.opacity = strain
                d.translateBy(x: x0 + dir * 4 * u, y: 24 + 14 * u)
                d.scaleBy(x: 1.4, y: 1.4)
                let drop = Path { p in
                    p.move(to: CGPoint(x: 0, y: -5))
                    p.addQuadCurve(to: CGPoint(x: 0, y: 3.5), control: CGPoint(x: 5, y: 2))
                    p.addQuadCurve(to: CGPoint(x: 0, y: -5), control: CGPoint(x: -5, y: 2))
                }
                inked(&d, drop, PropInk.water, Color(hex: 0x2F78B8), 1.2)
            }
        }
    }

    private func basketballPath(_ ctx: inout GraphicsContext, at p: CGPoint, squash: CGFloat) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y + 9 * (1 - squash))
        c.scaleBy(x: 1 + (1 - squash) * 0.8, y: squash)
        let r: CGFloat = 9
        c.fill(circle(.zero, r), with: .color(TreatInk.ball))
        var seams = Path()
        seams.move(to: CGPoint(x: -r, y: 0)); seams.addLine(to: CGPoint(x: r, y: 0))
        seams.move(to: CGPoint(x: 0, y: -r)); seams.addLine(to: CGPoint(x: 0, y: r))
        seams.move(to: CGPoint(x: -6, y: -6.8)); seams.addQuadCurve(to: CGPoint(x: -6, y: 6.8), control: CGPoint(x: -1.5, y: 0))
        seams.move(to: CGPoint(x: 6, y: -6.8)); seams.addQuadCurve(to: CGPoint(x: 6, y: 6.8), control: CGPoint(x: 1.5, y: 0))
        c.stroke(seams, with: .color(TreatInk.ballSeam), lineWidth: 1.3)
        c.stroke(circle(.zero, r), with: .color(TreatInk.ballSeam), lineWidth: 1.6)
    }

    private func hoopAndBall(_ ctx: inout GraphicsContext) {
        let b = Treat.basketball(t)
        let rim = CGRect(x: 98, y: 4, width: 22, height: 6)
        ctx.stroke(segment(CGPoint(x: 122, y: 0), CGPoint(x: 122, y: 112)), with: .color(cord), lineWidth: 2.4)
        inked(&ctx, Path(roundedRect: CGRect(x: 119, y: -18, width: 5.5, height: 28), cornerRadius: 1.5), TreatInk.paper, cord)
        ctx.stroke(Path(ellipseIn: rim), with: .color(TreatInk.rim.opacity(0.6)), lineWidth: 2)
        // Shadow on the floor, smaller when the ball is high.
        let lift = min(max((91 - b.ball.y) / 90, 0), 1)
        ctx.fill(Path(ellipseIn: CGRect(x: b.ball.x - 8 + 3 * lift, y: 100, width: 16 - 6 * lift, height: 3.5)),
                 with: .color(Color.black.opacity(0.25 * (1 - lift))))
        basketballPath(&ctx, at: b.ball, squash: b.squash)
        // Net and the front of the rim over the ball.
        var net = Path()
        for i in 0...4 {
            let x0 = rim.minX + 1 + CGFloat(i) * 5, x1 = rim.minX + 5 + CGFloat(i) * 3
            net.move(to: CGPoint(x: x0, y: rim.midY)); net.addLine(to: CGPoint(x: x1, y: rim.midY + 11))
        }
        net.move(to: CGPoint(x: rim.minX + 3, y: rim.midY + 6)); net.addLine(to: CGPoint(x: rim.maxX - 3, y: rim.midY + 6))
        ctx.stroke(net, with: .color(cord.opacity(0.75)), lineWidth: 1.2)
        var front = Path()
        front.addArc(center: .zero, radius: 1, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        front = front.applying(CGAffineTransform(translationX: rim.midX, y: rim.midY).scaledBy(x: rim.width / 2, y: rim.height / 2))
        ctx.stroke(front, with: .color(TreatInk.rim), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func soccerBall(_ ctx: inout GraphicsContext) {
        let f = Treat.football(t)
        let r: CGFloat = 9.5
        var c = ctx
        c.translateBy(x: f.ball.x, y: f.ball.y)
        c.fill(circle(.zero, r), with: .color(.white))
        var inner = c
        inner.clip(to: circle(.zero, r))
        inner.rotate(by: .radians(t * 5))
        func pentagon(_ center: CGPoint, _ s: CGFloat) -> Path {
            Path { p in
                for k in 0..<5 {
                    let a = -Double.pi / 2 + Double(k) * 2 * .pi / 5
                    let pt = CGPoint(x: center.x + s * cos(a), y: center.y + s * sin(a))
                    k == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
            }
        }
        inner.fill(pentagon(.zero, 4), with: .color(TreatInk.ballDark))
        for k in 0..<5 {
            let a = -Double.pi / 2 + Double(k) * 2 * .pi / 5
            inner.fill(pentagon(CGPoint(x: 10.5 * cos(a), y: 10.5 * sin(a)), 4), with: .color(TreatInk.ballDark))
        }
        c.stroke(circle(.zero, r), with: .color(dark ? Color(hex: 0x8A867F) : TreatInk.ballDark), lineWidth: 1.6)
    }
}

// MARK: - Shared timing and colours

fileprivate enum Treat {
    static func hash(_ n: Double) -> Double {
        let s = sin(n * 12.9898) * 43758.5453
        return s - floor(s)
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ x: Double) -> Color {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 255) / 255 }
        func m(_ s: UInt32) -> Double { ch(a, s) + (ch(b, s) - ch(a, s)) * x }
        return Color(.sRGB, red: m(16), green: m(8), blue: m(0))
    }

    // Ice cream: 0 = at the side, 1 = at the mouth.
    static func coneLift(_ t: Double) -> Double {
        let p = phase(t, 4.4)
        return smooth((p - 0.40) / 0.12) * (1 - smooth((p - 0.86) / 0.12))
    }

    /// 0…1 per lick while the cone is at the mouth.
    static func lickStroke(_ t: Double) -> Double {
        let p = phase(t, 4.4)
        guard p > 0.52, p < 0.85 else { return 0 }
        return bump(((p - 0.52) / 0.33 * 3).truncatingRemainder(dividingBy: 1))
    }

    // Watermelon: four bites, then a fresh slice.
    static let melonPeriod = 8.0
    static let melonBites: [Double] = [0.12, 0.32, 0.52, 0.72]

    static func melonLift(_ t: Double) -> Double {
        let p = phase(t, melonPeriod)
        return melonBites.map { bump((p - $0 + 0.06) / 0.12) }.max() ?? 0
    }

    static func melonBitten(_ t: Double) -> Int {
        let p = phase(t, melonPeriod)
        return p >= 0.92 ? 0 : melonBites.filter { p >= $0 }.count
    }

    static func melonChew(_ t: Double) -> Double {
        let p = phase(t, melonPeriod)
        return melonBites.map { p >= $0 && p < $0 + 0.12 ? bump((p - $0) / 0.12) : 0 }.max() ?? 0
    }

    /// Opacity: the finished slice sinks away and a fresh one rises.
    static func melonFresh(_ t: Double) -> Double {
        let p = phase(t, melonPeriod)
        if p < 0.85 { return 1 }
        if p < 0.92 { return 1 - smooth((p - 0.85) / 0.07) }
        return smooth((p - 0.92) / 0.08)
    }

    // Popcorn: one kernel per beat pops out, arcs over and drops into the mouth.
    static let popPeriod = 2.4

    static func kernel(_ t: Double) -> CGPoint? {
        let p = phase(t, popPeriod)
        guard p < 0.7 else { return nil }
        let n = floor(t / popPeriod)
        let q = p / 0.7
        let x0 = 40 + 20 * hash(n)
        let side = Int(n) % 2 == 0 ? 1.0 : -1.0
        let x = x0 + (50 - x0) * q + side * 24 * sin(.pi * q)
        let y = 72 - 8 * q - 4 * 78 * q * (1 - q)
        return CGPoint(x: x, y: y)
    }

    static func popChomp(_ t: Double) -> Double { bump((phase(t, popPeriod) - 0.7) / 0.22) }

    // Campfire: roast till golden, eat, a fresh one.
    static let roastPeriod = 9.0

    static func toast(_ t: Double) -> Double {
        let p = phase(t, roastPeriod)
        return p < 0.81 ? smooth(p / 0.68) : 0
    }

    static func eatSwing(_ t: Double) -> Double {
        let p = phase(t, roastPeriod)
        return smooth((p - 0.70) / 0.1) * (1 - smooth((p - 0.86) / 0.12))
    }

    static func hasMarshmallow(_ t: Double) -> Bool {
        let p = phase(t, roastPeriod)
        return p < 0.81 || p > 0.86
    }

    static func munch(_ t: Double) -> Double { bump((phase(t, roastPeriod) - 0.79) / 0.12) }

    // Sunbathing: a peek over the shades.
    static func peek(_ t: Double) -> Double {
        let p = phase(t, 10)
        return smooth((p - 0.62) / 0.05) * (1 - smooth((p - 0.78) / 0.05))
    }

    static func umbrellaAngle(_ t: Double) -> Double { -10 + 2.5 * sin(tau * t / 3.3) }

    static func swing(_ t: Double) -> Double { sin(tau * t / 4.6) }

    // Barbell: up, hold with a strain, down, rest.
    static let liftPeriod = 3.2

    static func barLift(_ t: Double) -> Double {
        let p = phase(t, liftPeriod)
        return smooth(p / 0.26) * (1 - smooth((p - 0.64) / 0.22))
    }

    static func strain(_ t: Double) -> Double {
        let p = phase(t, liftPeriod)
        return smooth((p - 0.24) / 0.06) * (1 - smooth((p - 0.6) / 0.06))
    }

    // Basketball: dribble, wind up, shoot, swish, back to the dribble.
    static func basketball(_ t: Double) -> (ball: CGPoint, squash: CGFloat, bob: Double, crouch: Double, jump: Double) {
        let s = phase(t, 6) * 6
        let hand = CGPoint(x: 104, y: 58), floor: CGFloat = 91
        if s < 3.9 {
            let u = s / 0.6
            let k = abs(sin(.pi * u))
            let y = floor - (floor - hand.y) * k
            let squash = k < 0.12 ? 0.82 + 0.18 * k / 0.12 : 1
            return (CGPoint(x: hand.x, y: y), squash, k, smooth((s - 3.4) / 0.5), 0)
        }
        if s < 4.3 {
            let u = smooth((s - 3.9) / 0.4)
            return (CGPoint(x: hand.x - 8 * u, y: hand.y - 26 * u), 1, 1, 1 - u, u * 0.6)
        }
        if s < 5.3 {
            let u = (s - 4.3) / 1.0
            let a = CGPoint(x: 96, y: 32), c = CGPoint(x: 98, y: -44), b = CGPoint(x: 109, y: 2)
            let x = (1 - u) * (1 - u) * a.x + 2 * u * (1 - u) * c.x + u * u * b.x
            let y = (1 - u) * (1 - u) * a.y + 2 * u * (1 - u) * c.y + u * u * b.y
            return (CGPoint(x: x, y: y), 1, 0, 0, 0.6 * (1 - smooth(u / 0.5)))
        }
        let u = (s - 5.3) / 0.7
        return (CGPoint(x: 109 - 5 * u, y: 2 + (floor - 2) * u * u), u > 0.92 ? 0.85 : 1, 0, 0, 0)
    }

    // Football: three headers, out to the side, a bump back up to the head.
    static let kickPeriod = 3.8
    static let headY: CGFloat = -6

    static func football(_ t: Double) -> (ball: CGPoint, hop: Double, lean: Double) {
        let s = phase(t, kickPeriod) * kickPeriod
        func out(_ q: Double) -> CGPoint {
            CGPoint(x: 50 + 49 * q, y: headY + (80 - headY) * q - 136 * q * (1 - q))
        }
        func near(_ d: Double) -> Double { smooth(1 - d / 0.16) }
        if s < 1.8 {
            let q = (s / 0.6).truncatingRemainder(dividingBy: 1)
            return (CGPoint(x: 50, y: headY - 52 * q * (1 - q)), near(min(q, 1 - q) * 0.6), 0)
        }
        if s < 2.8 {
            let q = s - 1.8
            return (out(q), near(q), near(1 - q))
        }
        let q = s - 2.8
        return (out(1 - q), near(1 - q), near(q))
    }
}

fileprivate enum TreatInk {
    static let paper = Color(hex: 0xFFF6EA)
    static let waffle = Color(hex: 0xE3A75C)
    static let waffleEdge = Color(hex: 0x9C6128)
    static let berry = Color(hex: 0xFF8FB1)
    static let berryEdge = Color(hex: 0xC4496D)
    static let mint = Color(hex: 0x93E2BE)
    static let mintEdge = Color(hex: 0x3D9A73)
    static let cherry = Color(hex: 0xE5323F)
    static let tongue = Color(hex: 0xFF7096)
    static let tongueEdge = Color(hex: 0xB83A5E)
    static let rind = Color(hex: 0x3E9B4F)
    static let rindPale = Color(hex: 0xC8EFA0)
    static let flesh = Color(hex: 0xFF4F5E)
    static let seed = Color(hex: 0x2A1916)
    static let corn = Color(hex: 0xFFF1CC)
    static let cornEdge = Color(hex: 0xD49A35)
    static let bucket = Color(hex: 0xE8434F)
    static let bucketEdge = Color(hex: 0xA52633)
    static let stick = Color(hex: 0x8E5D33)
    static let woodEdge = Color(hex: 0x6E4424)
    static let towel = Color(hex: 0x4FA9E0)
    static let lens = Color(hex: 0x1C1C22)
    static let shadeFrame = Color(hex: 0x111114)
    static let canvas = Color(hex: 0x3FA7A0)
    static let canvasShade = Color(hex: 0x2E7F79)
    static let canvasEdge = Color(hex: 0x225E5A)
    static let plate = Color(hex: 0x3A3A42)
    static let ball = Color(hex: 0xE8823A)
    static let ballSeam = Color(hex: 0x5A2C10)
    static let rim = Color(hex: 0xFF5A36)
    static let ballDark = Color(hex: 0x26262B)
}
