import SwiftUI

// Hobbies.

extension Motion {
    mutating func posePainting(_ t: Double) {
        var m = self
        // Eyes on the canvas, following the brush tip up and down.
        let tip = Hobby.paint(t).tip
        m.lookX = 5.5
        m.lookY = min(max(Double(tip.y - 44) / 4, -4), 3)
        m.rot = 3 + m.rot * 0.3
        self = m
    }

    mutating func poseKnitting(_ t: Double) {
        var m = self
        // Head down over the needles, rocking a little with every stitch.
        let swing = Hobby.needleSwing(t)
        m.lookX = 0.5 * swing
        m.lookY = 5
        m.rot = 1.5 * swing + m.rot * 0.3
        self = m
    }

    mutating func poseGuitar(_ t: Double) {
        var m = self
        // Nod on every strum, sway over two, eyes shut in bliss half the time.
        let b = phase(t, Hobby.strumBeat)
        m.dy = -2 * bump(b)
        m.sy = 1 - 0.02 * (1 - bump(b))
        m.sx = 1 + 0.02 * (1 - bump(b))
        m.rot = 4 * sin(tau * t / (2 * Hobby.strumBeat))
        let bliss = Motion.keyframes(phase(t, 8), [(0, [1]), (0.45, [1]), (0.5, [0]), (0.95, [0]), (1, [1])])[0]
        m.blink = 0.3 + 0.7 * bliss
        m.lookX = -3 * bliss
        m.lookY = 4 * bliss + 1
        self = m
    }

    mutating func poseDrums(_ t: Double) {
        var m = self
        // Bounce on every hit; squeeze the eyes on the crash.
        let b = phase(t, Hobby.drumBeat)
        let hit = exp(-b * 5)
        m.sy = 1 - 0.04 * hit
        m.sx = 1 + 0.04 * hit
        m.dy = -1.8 * bump(b)
        m.rot = 2 * sin(tau * t / (4 * Hobby.drumBeat))
        m.lookX = 0; m.lookY = 4
        let crash = Hobby.sinceCrash(t)
        if crash < 0.3 { m.blink = 0.3 + 0.7 * smooth(crash / 0.3) }
        self = m
    }

    mutating func poseGaming(_ t: Double) {
        var m = self
        // Narrowed, focused eyes darting with the game; now and then a win and a jump.
        let jump = Hobby.gameJump(t)
        m.rot = 3 * sin(tau * t / 0.9) + m.rot * 0.2
        m.lookX = 1.6 * sin(tau * t / 1.3)
        m.lookY = 3.5
        m.blink = 0.72
        if jump > 0 {
            let up = bump(jump)
            m.dy = -12 * up
            m.sy = 1 - 0.06 * (jump < 0.12 ? bump(jump / 0.12) : 0) + 0.04 * up
            m.sx = 1 + 0.06 * (jump < 0.12 ? bump(jump / 0.12) : 0) - 0.03 * up
            m.blink = 0.72 + 0.36 * bump(min(jump * 1.4, 1))
            m.lookY = 3.5 - 6 * bump(min(jump * 1.4, 1))
            m.rot = 0
        }
        self = m
    }

    mutating func poseDisco(_ t: Double) {
        var m = self
        // Side to side over two beats, a squash on each.
        let b = phase(t, Hobby.discoBeat)
        let side = sin(tau * t / (2 * Hobby.discoBeat))
        m.dx = 6 * side
        m.rot = 8 * side
        m.dy = -3 * bump(b)
        m.sy = 1 - 0.06 * (1 - bump(b))
        m.sx = 1 + 0.05 * (1 - bump(b))
        m.blink = 0.3
        m.lookX = 2 * side; m.lookY = -1
        self = m
    }

    mutating func poseCamera(_ t: Double) {
        var m = self
        let s = phase(t, Hobby.cameraPeriod) * Hobby.cameraPeriod
        // Aim steadily, flinch at the flash, then watch the photo come out.
        let look = Motion.keyframes(s / Hobby.cameraPeriod, [
            (0.00, [3, 1]), (0.12, [3, 1]), (0.22, [2, 6]), (0.62, [2, 6]), (0.75, [4, 0]), (1.0, [3, 1]),
        ])
        m.lookX = look[0]; m.lookY = look[1]
        m.rot = 2 + m.rot * 0.3
        if s < 0.4 { m.blink = 0.14 + 0.86 * smooth(s / 0.4) }
        self = m
    }

    mutating func poseRubik(_ t: Double) {
        var m = self
        let turn = Hobby.cubeTurn(t)
        // Eyes on the cube; a small nod whenever a layer clicks into place.
        m.lookX = 0.8 * sin(tau * t / 3.7)
        m.lookY = 5
        let settle = turn.since < 0.35 ? bump(turn.since / 0.35) : 0
        m.dy = 1.2 * settle
        m.rot = m.rot * 0.4
        self = m
    }

    mutating func poseCardHouse(_ t: Double) {
        var m = self
        let h = Hobby.cards(t)
        m.rot = 3 + m.rot * 0.3
        m.lookX = 5.5
        m.lookY = min(max(Double(h.focus.y - 47) / 5, -3), 6)
        if h.collapse > 0 {
            // Flinch as it falls, then stare at the pile.
            let c = h.collapse
            m.blink = c < 0.35 ? 0.14 + 0.86 * smooth((c - 0.2) / 0.15) : 1
            m.rot = 3 - 5 * bump(min(c * 1.6, 1))
            m.dy = -3 * bump(min(c * 2.5, 1))
            m.lookY = 5.5
        }
        self = m
    }

    mutating func poseFishbowl(_ t: Double) {
        var m = self
        let fish = Hobby.fish(t)
        m.lookX = min(max(Double(fish.x - 54) / 2.4, -5), 5)
        m.lookY = 5
        m.sy = m.sy * 0.98
        self = m
    }
}

extension ActivityProps {
    func drawPainting(_ ctx: inout GraphicsContext) {
        if layer == .front { easel(&ctx) }
    }

    func drawKnitting(_ ctx: inout GraphicsContext) {
        if layer == .held { needles(&ctx) }
        if layer == .front { yarnBall(&ctx) }
    }

    func drawGuitar(_ ctx: inout GraphicsContext) {
        if layer == .held { guitar(&ctx) }
        if layer == .front { guitarNotes(&ctx) }
    }

    func drawDrums(_ ctx: inout GraphicsContext) {
        if layer == .front { drumKit(&ctx) }
    }

    func drawGaming(_ ctx: inout GraphicsContext) {
        if layer == .behind { screenGlow(&ctx) }
        if layer == .held { gamepad(&ctx) }
        if layer == .front { winSparkles(&ctx) }
    }

    func drawDisco(_ ctx: inout GraphicsContext) {
        if layer == .front { discoBall(&ctx) }
    }

    func drawCamera(_ ctx: inout GraphicsContext) {
        if layer == .held { polaroid(&ctx) }
        if layer == .front { flash(&ctx) }
    }

    func drawRubik(_ ctx: inout GraphicsContext) {
        if layer == .held { cube(&ctx) }
    }

    func drawCardHouse(_ ctx: inout GraphicsContext) {
        if layer == .front { cardHouse(&ctx) }
    }

    func drawFishbowl(_ ctx: inout GraphicsContext) {
        if layer == .front { fishbowl(&ctx) }
    }

    // MARK: Pieces

    private func easel(_ ctx: inout GraphicsContext) {
        let wood = StrokeStyle(lineWidth: 3, lineCap: .round)
        ctx.stroke(segment(CGPoint(x: 110, y: 18), CGPoint(x: 110, y: 108)), with: .color(HobbyInk.woodDark), style: wood)
        ctx.stroke(segment(CGPoint(x: 107, y: 18), CGPoint(x: 96, y: 112)), with: .color(HobbyInk.wood), style: wood)
        ctx.stroke(segment(CGPoint(x: 113, y: 18), CGPoint(x: 124, y: 112)), with: .color(HobbyInk.wood), style: wood)
        let o = Hobby.canvasOrigin
        let canvas = Path(CGRect(x: o.x, y: o.y, width: 26, height: 30))
        ctx.fill(canvas, with: .color(HobbyInk.canvas))
        ctx.stroke(canvas, with: .color(cord), lineWidth: 1.6)
        ctx.fill(Path(roundedRect: CGRect(x: o.x - 3, y: o.y + 30, width: 32, height: 4), cornerRadius: 1.5),
                 with: .color(HobbyInk.wood))
        let paint = Hobby.paint(t)
        for i in 0..<4 where paint.done[i] > 0 {
            let n = 24
            let path = Path { p in
                p.move(to: Hobby.strokePoint(i, 0))
                for k in 1...n { p.addLine(to: Hobby.strokePoint(i, paint.done[i] * Double(k) / Double(n))) }
            }
            ctx.stroke(path, with: .color(Hobby.paintColors[i].opacity(paint.fade)),
                       style: StrokeStyle(lineWidth: i == 1 ? 4 : 3.6, lineCap: .round, lineJoin: .round))
        }
        // The brush: paint-tipped bristles at the canvas, the handle reaching back towards the body.
        let tip = paint.tip
        let d = CGPoint(x: -0.6, y: 0.8)
        func along(_ k: CGFloat) -> CGPoint { CGPoint(x: tip.x + d.x * k, y: tip.y + d.y * k) }
        ctx.stroke(segment(along(8), along(25)), with: .color(HobbyInk.woodDark), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.stroke(segment(along(8), along(25)), with: .color(HobbyInk.red), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        ctx.stroke(segment(along(5), along(9)), with: .color(PropInk.metal), style: StrokeStyle(lineWidth: 3.4))
        ctx.stroke(segment(along(1), along(5.5)), with: .color(Hobby.paintColors[paint.color]),
                   style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
    }

    private func needles(_ ctx: inout GraphicsContext) {
        let swing = CGFloat(Hobby.needleSwing(t))
        // The scarf hangs from where the needles cross; new rows appear at the top and push it down.
        let rows = t / Hobby.stitch
        let frac = CGFloat(rows - rows.rounded(.down))
        let base = Int(rows.rounded(.down))
        let grown = CGFloat(min(t.truncatingRemainder(dividingBy: Activity.leisureSlot) / 90, 1))
        let top: CGFloat = 74, rowH: CGFloat = 3.6, width: CGFloat = 17
        let length = 26 + 12 * grown
        var scarf = ctx
        scarf.translateBy(x: 50, y: top)
        scarf.rotate(by: .degrees(2.5 * sin(tau * t / 3.3)))
        let strip = Path(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: length), cornerRadius: 2)
        scarf.stroke(strip, with: .color(cord), lineWidth: 3)
        var inside = scarf
        inside.clip(to: strip)
        let count = Int(length / rowH) + 2
        for j in -1..<count {
            let k = base - j
            let y = (CGFloat(j) + frac) * rowH
            let striped = ((k / 3) % 2 + 2) % 2 == 0
            inside.fill(Path(CGRect(x: -width / 2, y: y, width: width, height: rowH + 0.2)),
                        with: .color(striped ? HobbyInk.yarn : PropInk.paper))
            // A row of little Vs, the knit stitches.
            let v = Path { p in
                var x = -width / 2 + 1.5
                while x < width / 2 {
                    p.move(to: CGPoint(x: x, y: y + 0.6)); p.addLine(to: CGPoint(x: x + 2.1, y: y + rowH - 0.6))
                    p.addLine(to: CGPoint(x: x + 4.2, y: y + 0.6))
                    x += 4.6
                }
            }
            inside.stroke(v, with: .color(striped ? HobbyInk.yarnDark.opacity(0.6) : PropInk.steam), lineWidth: 1)
        }
        // Two needles crossing in an X, tapping together on each stitch.
        for side in [-1.0, 1.0] {
            let butt = CGPoint(x: 50 + 24 * side, y: 92)
            let a = (side < 0 ? -40.0 : 220.0) + 6 * Double(swing) * side
            let tip = CGPoint(x: butt.x + 42 * cos(a * .pi / 180), y: butt.y + 42 * sin(a * .pi / 180))
            ctx.stroke(segment(butt, tip), with: .color(cord), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            ctx.fill(circle(butt, 3.6), with: .color(side < 0 ? HobbyInk.blue : HobbyInk.yellow))
            ctx.stroke(circle(butt, 3.6), with: .color(cord), lineWidth: 1.2)
        }
    }

    private func yarnBall(_ ctx: inout GraphicsContext) {
        let c = CGPoint(x: 103, y: 100)
        var thread = Path()
        thread.move(to: CGPoint(x: c.x - 6, y: c.y - 7))
        thread.addQuadCurve(to: CGPoint(x: 58, y: 76), control: CGPoint(x: 80, y: 102 + 3 * sin(tau * t / Hobby.stitch)))
        ctx.stroke(thread, with: .color(HobbyInk.yarn), lineWidth: 1.6)
        ctx.fill(circle(c, 10), with: .color(HobbyInk.yarn))
        var lines = ctx
        lines.clip(to: circle(c, 10))
        lines.translateBy(x: c.x, y: c.y)
        lines.rotate(by: .degrees(-25 + 10 * sin(tau * t / (2 * Hobby.stitch))))
        for dy in [-5.0, 0, 5] {
            var arc = Path()
            arc.move(to: CGPoint(x: -11, y: dy - 3)); arc.addQuadCurve(to: CGPoint(x: 11, y: dy - 3), control: CGPoint(x: 0, y: dy + 5))
            lines.stroke(arc, with: .color(HobbyInk.yarnDark), lineWidth: 1.6)
        }
        ctx.stroke(circle(c, 10), with: .color(HobbyInk.yarnDark), lineWidth: 1.6)
    }

    private func guitar(_ ctx: inout GraphicsContext) {
        var g = ctx
        g.translateBy(x: 32, y: 78)
        g.rotate(by: .degrees(-33))
        // Neck and headstock.
        g.fill(Path(CGRect(x: 20, y: -2.8, width: 48, height: 5.6)), with: .color(HobbyInk.woodDark))
        for x in stride(from: CGFloat(32), through: 62, by: 7.5) {
            g.stroke(segment(CGPoint(x: x, y: -2.8), CGPoint(x: x, y: 2.8)), with: .color(PropInk.metal), lineWidth: 1)
        }
        let head = Path(roundedRect: CGRect(x: 66, y: -4.5, width: 13, height: 9), cornerRadius: 2.5)
        g.fill(head, with: .color(HobbyInk.woodDark))
        for x in [CGFloat(70), 76] {
            g.fill(circle(CGPoint(x: x, y: -5.6), 1.9), with: .color(PropInk.metal))
            g.fill(circle(CGPoint(x: x, y: 5.6), 1.9), with: .color(PropInk.metal))
        }
        // The body: two bouts with one outline.
        let lower = circle(CGPoint(x: 0, y: 0), 15), upper = circle(CGPoint(x: 17, y: 0), 11)
        g.stroke(lower, with: .color(HobbyInk.woodDark), lineWidth: 3.2)
        g.stroke(upper, with: .color(HobbyInk.woodDark), lineWidth: 3.2)
        g.fill(lower, with: .color(HobbyInk.guitarTop))
        g.fill(upper, with: .color(HobbyInk.guitarTop))
        g.fill(circle(CGPoint(x: 13, y: 0), 4.8), with: .color(HobbyInk.core))
        g.fill(Path(roundedRect: CGRect(x: -8, y: -5.5, width: 3.4, height: 11), cornerRadius: 1), with: .color(HobbyInk.woodDark))
        // Strings, ringing after each strum.
        let s = phase(t, Hobby.strumBeat) * Hobby.strumBeat
        for (i, y) in [CGFloat(-1.7), 0, 1.7].enumerated() {
            let amp = CGFloat(2.2 * exp(-s * 6) * sin(s * 90 + Double(i) * 1.7))
            var str = Path()
            str.move(to: CGPoint(x: -6.5, y: y))
            str.addQuadCurve(to: CGPoint(x: 67, y: y), control: CGPoint(x: 30, y: y + amp))
            g.stroke(str, with: .color(PropInk.paper.opacity(0.9)), lineWidth: 0.9)
        }
        // A swoosh across the strings on the strum.
        if s < 0.18 {
            let q = s / 0.18
            var sw = Path()
            sw.addArc(center: CGPoint(x: 6, y: 0), radius: 9, startAngle: .degrees(-50), endAngle: .degrees(50), clockwise: false)
            g.stroke(sw, with: .color(Color.white.opacity(0.85 * (1 - q))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    private func guitarNotes(_ ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let q = phase(t / 2.7 + Double(i) / 3, 1)
            let x = -4 - 5 * sin(tau * q + Double(i)) - CGFloat(i) * 2
            let y = 66 - 70 * q
            let alpha = q < 0.15 ? q / 0.15 : (1 - q) / 0.85
            label(&ctx, i == 1 ? "♫" : "♪", at: CGPoint(x: x, y: y), size: 18, color: tint.opacity(alpha))
        }
    }

    private func drumKit(_ ctx: inout GraphicsContext) {
        // Cymbal on a stand at the right, wobbling after a crash.
        let crash = Hobby.sinceCrash(t)
        let stand = StrokeStyle(lineWidth: 2, lineCap: .round)
        ctx.stroke(segment(CGPoint(x: 110, y: 70), CGPoint(x: 110, y: 110)), with: .color(cord), style: stand)
        ctx.stroke(segment(CGPoint(x: 110, y: 104), CGPoint(x: 102, y: 112)), with: .color(cord), style: stand)
        ctx.stroke(segment(CGPoint(x: 110, y: 104), CGPoint(x: 118, y: 112)), with: .color(cord), style: stand)
        var cym = ctx
        cym.translateBy(x: 110, y: 68)
        cym.rotate(by: .degrees(-6 + 12 * exp(-crash * 4) * sin(crash * 30)))
        let plate = Path(ellipseIn: CGRect(x: -14, y: -3.6, width: 28, height: 7.2))
        cym.fill(plate, with: .color(PropInk.star))
        cym.stroke(plate, with: .color(HobbyInk.brass), lineWidth: 1.6)
        cym.fill(Path(ellipseIn: CGRect(x: -3.5, y: -4.5, width: 7, height: 4)), with: .color(HobbyInk.brass))
        if crash < 0.5 {
            let q = CGFloat(crash / 0.5)
            for side in [CGFloat(-1), 1] {
                var arc = Path()
                arc.addArc(center: .zero, radius: 17 + 6 * q, startAngle: .degrees(side < 0 ? 200 : -20),
                           endAngle: .degrees(side < 0 ? 160 : 20), clockwise: false)
                cym.stroke(arc, with: .color(star.opacity(Double(1 - q))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        // The snare in front of the body.
        let shell = Path { p in
            p.move(to: CGPoint(x: 28, y: 92)); p.addLine(to: CGPoint(x: 28, y: 106))
            p.addQuadCurve(to: CGPoint(x: 72, y: 106), control: CGPoint(x: 50, y: 118))
            p.addLine(to: CGPoint(x: 72, y: 92)); p.closeSubpath()
        }
        ctx.fill(shell, with: .color(HobbyInk.red))
        ctx.stroke(shell, with: .color(HobbyInk.redDark), lineWidth: 1.6)
        let zig = Path { p in
            p.move(to: CGPoint(x: 30, y: 97))
            for (k, x) in stride(from: CGFloat(36), through: 70, by: 6).enumerated() {
                p.addLine(to: CGPoint(x: x, y: k % 2 == 0 ? 107 : 97))
            }
        }
        ctx.stroke(zig, with: .color(PropInk.paper), lineWidth: 1.6)
        let head = Path(ellipseIn: CGRect(x: 27, y: 86, width: 46, height: 12))
        ctx.fill(head, with: .color(PropInk.paper))
        ctx.stroke(head, with: .color(PropInk.metalEdge), lineWidth: 2)
        // Two sticks from the sides of the body, hitting in turn.
        for left in [true, false] {
            let s = Hobby.stick(t, left: left)
            let pivot = CGPoint(x: left ? 16 : 84, y: 76)
            let tip = CGPoint(x: pivot.x + 28 * cos(s.angle), y: pivot.y + 28 * sin(s.angle))
            ctx.stroke(segment(pivot, tip), with: .color(HobbyInk.woodDark), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(segment(pivot, tip), with: .color(HobbyInk.stick), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            if s.since < 0.14 {
                let q = CGFloat(s.since / 0.14)
                sparkle(&ctx, at: CGPoint(x: tip.x, y: tip.y - 3), r: 8 * (1 - q) + 2, color: star.opacity(Double(1 - q)))
            }
        }
    }

    private func screenGlow(_ ctx: inout GraphicsContext) {
        // Light from the game the blob is facing, changing colour with the scene.
        let scene = phase(t, 7.5) * 3
        let k = Int(scene) % 3
        let colors = [HobbyInk.blue, HobbyInk.pink, HobbyInk.green]
        let w = smooth((scene - scene.rounded(.down) - 0.85) / 0.15)
        let flicker = 0.85 + 0.15 * sin(t * 23) * sin(t * 7)
        for (i, c) in [colors[k], colors[(k + 1) % 3]].enumerated() {
            let a = (i == 0 ? 1 - w : w) * 0.55 * flicker
            guard a > 0.01 else { continue }
            ctx.fill(circle(CGPoint(x: 50, y: 56), 66),
                     with: .radialGradient(Gradient(colors: [c.opacity(a), c.opacity(0)]),
                                           center: CGPoint(x: 50, y: 56), startRadius: 34, endRadius: 66))
        }
    }

    private func gamepad(_ ctx: inout GraphicsContext) {
        let shape = Path { p in
            p.addRoundedRect(in: CGRect(x: 26, y: 68, width: 48, height: 18), cornerSize: CGSize(width: 8, height: 8))
            p.addEllipse(in: CGRect(x: 24, y: 74, width: 17, height: 20))
            p.addEllipse(in: CGRect(x: 59, y: 74, width: 17, height: 20))
        }
        ctx.stroke(shape, with: .color(HobbyInk.padEdge), lineWidth: 3.2)
        ctx.fill(shape, with: .color(HobbyInk.pad))
        let press = Hobby.press(t)
        // D-pad, one arm lit when pressed.
        let dc = CGPoint(x: 37, y: 78)
        ctx.fill(Path(roundedRect: CGRect(x: dc.x - 5.5, y: dc.y - 1.9, width: 11, height: 3.8), cornerRadius: 1), with: .color(PropInk.metal))
        ctx.fill(Path(roundedRect: CGRect(x: dc.x - 1.9, y: dc.y - 5.5, width: 3.8, height: 11), cornerRadius: 1), with: .color(PropInk.metal))
        if press >= 4 {
            let dirs = [CGPoint(x: 3.6, y: 0), CGPoint(x: 0, y: 3.6), CGPoint(x: -3.6, y: 0), CGPoint(x: 0, y: -3.6)]
            let d = dirs[press - 4]
            ctx.fill(circle(CGPoint(x: dc.x + d.x, y: dc.y + d.y), 2.2), with: .color(Color.white))
        }
        // Four face buttons; the pressed one flashes and glows.
        let bc = CGPoint(x: 63, y: 78)
        let spots = [CGPoint(x: 0, y: -4.3), CGPoint(x: 4.3, y: 0), CGPoint(x: 0, y: 4.3), CGPoint(x: -4.3, y: 0)]
        let colors = [HobbyInk.green, HobbyInk.red, HobbyInk.blue, HobbyInk.yellow]
        for i in 0..<4 {
            let p = CGPoint(x: bc.x + spots[i].x, y: bc.y + spots[i].y)
            if press == i {
                ctx.fill(circle(p, 5.2), with: .color(colors[i].opacity(0.45)))
                ctx.fill(circle(p, 2.9), with: .color(Color.white))
            } else {
                ctx.fill(circle(p, 2.7), with: .color(colors[i]))
            }
        }
    }

    private func winSparkles(_ ctx: inout GraphicsContext) {
        let jump = Hobby.gameJump(t)
        guard jump > 0.15 else { return }
        let a = Double(bump((jump - 0.15) / 0.85))
        sparkle(&ctx, at: CGPoint(x: 6, y: 18), r: 7 * CGFloat(a), color: star.opacity(a))
        sparkle(&ctx, at: CGPoint(x: 96, y: 10), r: 8 * CGFloat(a), color: star.opacity(a))
        sparkle(&ctx, at: CGPoint(x: 104, y: 36), r: 5 * CGFloat(a), color: tint.opacity(a))
    }

    private func discoBall(_ ctx: inout GraphicsContext) {
        // Spots of light sweeping over the room and the dancer.
        for i in 0..<Hobby.spotColors.count {
            let p = Hobby.spot(t, i)
            let pulse = 0.85 + 0.15 * sin(t * 5 + Double(i) * 2)
            ctx.fill(circle(p, 6), with: .color(Hobby.spotColors[i].opacity(0.9 * pulse)))
            ctx.fill(circle(p, 2.4), with: .color(Color.white.opacity(0.7 * pulse)))
        }
        let c = CGPoint(x: 50, y: -11), r: CGFloat = 11
        ctx.stroke(segment(CGPoint(x: 50, y: -25), CGPoint(x: 50, y: c.y - r)), with: .color(cord), lineWidth: 1.6)
        let ball = circle(c, r)
        ctx.fill(ball, with: .color(PropInk.metal))
        var facets = ctx
        facets.clip(to: ball)
        let spin = t * 1.6
        for lat in stride(from: -60.0, through: 60, by: 30) {
            let y = c.y + r * CGFloat(sin(lat * .pi / 180)), hw = r * CGFloat(cos(lat * .pi / 180))
            facets.stroke(segment(CGPoint(x: c.x - hw, y: y), CGPoint(x: c.x + hw, y: y)), with: .color(PropInk.metalEdge), lineWidth: 0.9)
        }
        for k in 0..<8 {
            let lon = Double(k) * .pi / 4 + spin.truncatingRemainder(dividingBy: .pi / 4)
            let sx = CGFloat(-cos(lon))
            let meridian = Path { p in
                for j in 0...12 {
                    let lat = -Double.pi / 2 + .pi * Double(j) / 12
                    let pt = CGPoint(x: c.x + r * CGFloat(cos(lat)) * sx, y: c.y + r * CGFloat(sin(lat)))
                    if j == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            facets.stroke(meridian, with: .color(PropInk.metalEdge), lineWidth: 0.9)
        }
        for i in 0..<3 {
            let tw = max(0, sin(t * 4.3 + Double(i) * 2.1))
            let p = CGPoint(x: c.x - 5 + CGFloat(i) * 5, y: c.y - 4 + CGFloat(i % 2) * 6)
            facets.fill(Path(CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Color.white.opacity(tw)))
        }
        ctx.stroke(ball, with: .color(PropInk.metalEdge), lineWidth: 1.6)
        let glint = max(0, sin(t * 2.2))
        sparkle(&ctx, at: CGPoint(x: c.x + 7, y: c.y - 7), r: 6 * CGFloat(glint), color: Color.white.opacity(glint))
    }

    private func polaroid(_ ctx: inout GraphicsContext) {
        let shot = Hobby.shot(t)
        // The photo slides out of the slot under the camera, then tips over and develops.
        if shot.photo > 0 {
            var ph = ctx
            ph.translateBy(x: 72, y: 62 + 24 * CGFloat(shot.eject))
            ph.rotate(by: .degrees(9 * shot.tip))
            let frame = Path(roundedRect: CGRect(x: -10, y: 0, width: 20, height: 23), cornerRadius: 1)
            ph.opacity = shot.photo
            ph.fill(frame, with: .color(PropInk.paper))
            ph.stroke(frame, with: .color(cord), lineWidth: 1.6)
            let pic = CGRect(x: -7.5, y: 2.5, width: 15, height: 14)
            ph.fill(Path(pic), with: .color(PropInk.water))
            ph.fill(Path(CGRect(x: pic.minX, y: pic.minY + 9, width: pic.width, height: 5)), with: .color(PropInk.leaf))
            ph.fill(circle(CGPoint(x: 0, y: pic.minY + 8), 4.6), with: .color(tint))
            ph.fill(circle(CGPoint(x: -1.6, y: pic.minY + 7.4), 0.9), with: .color(HobbyInk.core))
            ph.fill(circle(CGPoint(x: 1.6, y: pic.minY + 7.4), 0.9), with: .color(HobbyInk.core))
            ph.fill(Path(pic), with: .color(Color(white: 0.22).opacity(1 - shot.develop)))
        }
        // An instant camera: cream body, rainbow stripe, big lens, flash window.
        let body = Path(roundedRect: CGRect(x: 48, y: 60, width: 46, height: 24), cornerRadius: 5, style: .continuous)
        ctx.fill(Path(roundedRect: CGRect(x: 51, y: 55.5, width: 7, height: 5), cornerRadius: 1.5), with: .color(HobbyInk.red))
        ctx.fill(body, with: .color(PropInk.paper))
        ctx.stroke(body, with: .color(cord), lineWidth: 1.8)
        for (i, c) in [HobbyInk.red, HobbyInk.orange, HobbyInk.yellow, HobbyInk.green, HobbyInk.blue].enumerated() {
            ctx.fill(Path(CGRect(x: 53 + CGFloat(i) * 1.8, y: 61, width: 1.8, height: 22)), with: .color(c))
        }
        let lens = CGPoint(x: 73, y: 72.5)
        ctx.fill(circle(lens, 8.8), with: .color(HobbyInk.core))
        ctx.stroke(circle(lens, 7.2), with: .color(PropInk.metal), lineWidth: 1.6)
        ctx.fill(circle(lens, 4.4), with: .color(Color(hex: 0x24364D)))
        ctx.fill(circle(CGPoint(x: lens.x - 1.8, y: lens.y - 1.8), 1.5), with: .color(Color.white.opacity(0.85)))
        let flashWin = Path(roundedRect: CGRect(x: 83, y: 63, width: 8, height: 5.5), cornerRadius: 1)
        ctx.fill(flashWin, with: .color(shot.flash > 0 ? Color.white : Color(hex: 0xD8E6F0)))
        ctx.stroke(flashWin, with: .color(PropInk.metalEdge), lineWidth: 1)
        ctx.stroke(segment(CGPoint(x: 61, y: 81.8), CGPoint(x: 83, y: 81.8)), with: .color(HobbyInk.core), lineWidth: 1.6)
    }

    private func flash(_ ctx: inout GraphicsContext) {
        let f = Hobby.shot(t).flash
        guard f > 0 else { return }
        let c = CGPoint(x: 89, y: 64)
        ctx.fill(circle(c, 34), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * f), Color.white.opacity(0)]),
                                                      center: c, startRadius: 0, endRadius: 34))
        var rays = ctx
        rays.translateBy(x: c.x, y: c.y)
        for k in 0..<8 {
            let a = Double(k) * .pi / 4 + 0.2
            let r0 = CGFloat(8), r1 = CGFloat(8 + 14 * f)
            rays.stroke(segment(CGPoint(x: r0 * cos(a), y: r0 * sin(a)), CGPoint(x: r1 * cos(a), y: r1 * sin(a))),
                        with: .color(star.opacity(f)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        sparkle(&ctx, at: c, r: 6 + 9 * CGFloat(f), color: Color.white.opacity(f))
    }

    private func cube(_ ctx: inout GraphicsContext) {
        // An isometric cube; the top layer turns a quarter at a time.
        let turn = Hobby.cubeTurn(t)
        let s: CGFloat = 7
        let center = CGPoint(x: 50, y: 78)
        let tilt = 4 * sin(tau * t / 5.3)
        let ca = cos(turn.angle), sa = sin(turn.angle)
        func project(_ v: (Double, Double, Double), turned: Bool = false) -> CGPoint {
            var (x, y, z) = v
            if turned { (x, z) = (x * ca - z * sa, x * sa + z * ca) }
            return CGPoint(x: center.x + CGFloat(x - z) * 0.866 * s, y: center.y + CGFloat(x + z) * 0.5 * s - CGFloat(y) * s)
        }
        func quad(_ o: (Double, Double, Double), _ u: (Double, Double, Double), _ v: (Double, Double, Double),
                  _ a: Double, _ b: Double, _ c: Double, _ d: Double, turned: Bool) -> Path {
            func at(_ i: Double, _ j: Double) -> CGPoint {
                project((o.0 + u.0 * i + v.0 * j, o.1 + u.1 * i + v.1 * j, o.2 + u.2 * i + v.2 * j), turned: turned)
            }
            return Path { p in p.move(to: at(a, c)); p.addLine(to: at(b, c)); p.addLine(to: at(b, d)); p.addLine(to: at(a, d)); p.closeSubpath() }
        }
        /// A face from corner `o` along `u` (cols) and `v` (rows), stickers coloured from `colors`.
        func face(_ c: inout GraphicsContext, _ o: (Double, Double, Double), _ u: (Double, Double, Double),
                  _ v: (Double, Double, Double), cols: Int, rows: Int, colors: [Int], turned: Bool) {
            c.fill(quad(o, u, v, 0, Double(cols), 0, Double(rows), turned: turned), with: .color(HobbyInk.core))
            for j in 0..<rows { for i in 0..<cols {
                let g = 0.1
                let p = quad(o, u, v, Double(i) + g, Double(i + 1) - g, Double(j) + g, Double(j + 1) - g, turned: turned)
                c.fill(p, with: .color(HobbyInk.cube[colors[(j * cols + i) % colors.count]]))
            } }
        }
        var c = ctx
        c.translateBy(x: center.x, y: center.y + 18)
        c.rotate(by: .degrees(tilt))
        c.translateBy(x: -center.x, y: -center.y - 18)
        // Fixed lower two layers: right face (x = +1.5) and left face (z = +1.5).
        face(&c, (1.5, 0.5, 1.5), (0, 0, -1), (0, -1, 0), cols: 3, rows: 2, colors: [1, 3, 1, 5, 1, 2], turned: false)
        face(&c, (-1.5, 0.5, 1.5), (1, 0, 0), (0, -1, 0), cols: 3, rows: 2, colors: [4, 4, 0, 4, 2, 4], turned: false)
        c.fill(quad((-1.5, 0.5, -1.5), (1, 0, 0), (0, 0, 1), 0, 3, 0, 3, turned: false), with: .color(HobbyInk.core))
        // The turning top layer: its four sides (only those facing us), then its top.
        let sides: [((Double, Double, Double), (Double, Double, Double), (Double, Double), [Int])] = [
            ((1.5, 1.5, 1.5), (0, 0, -1), (1, 0), [5, 1, 0]),
            ((-1.5, 1.5, 1.5), (1, 0, 0), (0, 1), [2, 4, 4]),
            ((-1.5, 1.5, -1.5), (0, 0, 1), (-1, 0), [3, 3, 1]),
            ((1.5, 1.5, -1.5), (-1, 0, 0), (0, -1), [0, 5, 2]),
        ]
        for side in sides {
            let n = side.2
            let nx = n.0 * ca - n.1 * sa, nz = n.0 * sa + n.1 * ca
            if nx + nz > 0.02 { face(&c, side.0, side.1, (0, -1, 0), cols: 3, rows: 1, colors: side.3, turned: true) }
        }
        face(&c, (-1.5, 1.5, -1.5), (1, 0, 0), (0, 0, 1), cols: 3, rows: 3, colors: [0, 0, 3, 0, 0, 0, 5, 0, 0], turned: true)
    }

    private func cardHouse(_ ctx: inout GraphicsContext) {
        let h = Hobby.cards(t)
        var ctx = ctx
        ctx.translateBy(x: 110, y: 104); ctx.scaleBy(x: 1.15, y: 1.15); ctx.translateBy(x: -110, y: -104)
        for card in h.cards {
            let half = CGPoint(x: 9 * cos(card.angle), y: 9 * sin(card.angle))
            let a = CGPoint(x: card.center.x - half.x, y: card.center.y - half.y)
            let b = CGPoint(x: card.center.x + half.x, y: card.center.y + half.y)
            ctx.stroke(segment(a, b), with: .color(cord.opacity(card.alpha)), style: StrokeStyle(lineWidth: 6.2, lineCap: .round))
            ctx.stroke(segment(a, b), with: .color((card.red ? HobbyInk.red : PropInk.paper).opacity(card.alpha)),
                       style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        }
    }

    private func fishbowl(_ ctx: inout GraphicsContext) {
        let c = Hobby.bowlCenter, r = Hobby.bowlRadius
        let glass = dark ? PropInk.water : HobbyInk.glass
        let bowl = Path { p in
            for k in 0...40 {
                let a = (-53.13 + 286.26 * Double(k) / 40) * .pi / 180
                let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        ctx.fill(bowl, with: .color(Color.white.opacity(0.14)))
        var water = ctx
        water.clip(to: bowl)
        water.fill(Path(CGRect(x: c.x - r, y: Hobby.waterLine, width: 2 * r, height: 2 * r)), with: .color(PropInk.water.opacity(0.5)))
        water.stroke(segment(CGPoint(x: c.x - r, y: Hobby.waterLine), CGPoint(x: c.x + r, y: Hobby.waterLine)),
                     with: .color(glass), lineWidth: 1.6)
        // Pebbles and a swaying weed.
        for (i, x) in [CGFloat(-10), -4, 3, 9].enumerated() {
            water.fill(circle(CGPoint(x: c.x + x, y: c.y + r - 3), 3.2), with: .color(HobbyInk.cube[[3, 4, 1, 5][i]].opacity(0.9)))
        }
        let sway = CGFloat(3 * sin(tau * t / 2.6))
        var weed = Path()
        weed.move(to: CGPoint(x: c.x + 13, y: c.y + r - 4))
        weed.addQuadCurve(to: CGPoint(x: c.x + 12 + sway, y: c.y - 2), control: CGPoint(x: c.x + 17, y: c.y + 8))
        water.stroke(weed, with: .color(HobbyInk.green), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        // Bubbles leave the fish's mouth and rise to the surface.
        for i in 0..<3 {
            let q = phase(t / 2.1 + Double(i) / 3, 1)
            let born = Hobby.fish(t - q * 2.1)
            let x = born.x + 6 * born.facing + CGFloat(1.5 * sin(q * 9))
            let y = born.y - 2 - (born.y - 2 - Hobby.waterLine) * CGFloat(q)
            water.stroke(circle(CGPoint(x: x, y: y), 1.6 + 1.2 * CGFloat(q)), with: .color(Color.white.opacity(0.9 * (1 - q * 0.6))), lineWidth: 1.4)
        }
        // The goldfish; it squeezes thin as it turns round.
        let f = Hobby.fish(t)
        var fish = water
        fish.translateBy(x: f.x, y: f.y)
        fish.scaleBy(x: f.facing, y: 1)
        let wag = CGFloat(2 * sin(t * 9))
        let tail = Path { p in
            p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: -10, y: -4.5 + wag))
            p.addLine(to: CGPoint(x: -10, y: 4.5 + wag)); p.closeSubpath()
        }
        let bodyPath = Path(ellipseIn: CGRect(x: -6, y: -4.2, width: 13, height: 8.4))
        fish.fill(tail, with: .color(HobbyInk.fish))
        fish.stroke(tail, with: .color(HobbyInk.fishEdge), lineWidth: 1.2)
        fish.fill(bodyPath, with: .color(HobbyInk.fish))
        fish.stroke(bodyPath, with: .color(HobbyInk.fishEdge), lineWidth: 1.2)
        fish.fill(circle(CGPoint(x: 3.4, y: -1), 1.5), with: .color(HobbyInk.core))
        // Glass on top: outline, rim and a highlight.
        ctx.stroke(bowl, with: .color(glass), lineWidth: 2)
        let rimY = c.y - 0.8 * r
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 0.6 * r, y: rimY - 2.4, width: 1.2 * r, height: 4.8)), with: .color(glass), lineWidth: 2)
        var shine = Path()
        shine.addArc(center: c, radius: r - 4, startAngle: .degrees(200), endAngle: .degrees(235), clockwise: false)
        ctx.stroke(shine, with: .color(Color.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}

// MARK: - Colours and shared timing, so the body and its props agree

private enum HobbyInk {
    static let canvas = Color(hex: 0xFBF8F1)
    static let wood = Color(hex: 0xA8703F)
    static let woodDark = Color(hex: 0x5E3B22)
    static let stick = Color(hex: 0xEBC48E)
    static let guitarTop = Color(hex: 0xE09A50)
    static let brass = Color(hex: 0x9A6A10)
    static let pad = Color(hex: 0x33333B)
    static let padEdge = Color(hex: 0x9A9AA6)
    static let red = Color(hex: 0xE84A4A)
    static let redDark = Color(hex: 0x9E2A2A)
    static let orange = Color(hex: 0xFF8A2A)
    static let yellow = Color(hex: 0xFFD23F)
    static let green = Color(hex: 0x3CC46A)
    static let blue = Color(hex: 0x3F8CFF)
    static let pink = Color(hex: 0xFF4FB0)
    static let core = Color(hex: 0x1C1C20)
    static let fish = Color(hex: 0xFF7A2E)
    static let fishEdge = Color(hex: 0x8A300A)
    static let yarn = Color(hex: 0xE8536B)
    static let yarnDark = Color(hex: 0xA8324A)
    static let glass = Color(hex: 0x3D8FCC)
    /// White, yellow, red, orange, blue, green.
    static let cube = [Color(hex: 0xF4F4EE), yellow, red, orange, blue, green]
}

private enum Hobby {
    static func mix(_ a: CGPoint, _ b: CGPoint, _ q: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(q), y: a.y + (b.y - a.y) * CGFloat(q))
    }

    // MARK: Painting — four strokes on the canvas, a pause, wipe, again.

    static let paintPeriod = 10.0
    static let strokeStart = 0.6, strokeGap = 2.0, strokeLen = 1.4
    static let canvasOrigin = CGPoint(x: 97, y: 22)
    static let paintColors = [HobbyInk.blue, HobbyInk.green, HobbyInk.yellow, HobbyInk.red]
    static let brushRest = CGPoint(x: 92, y: 64)

    /// A point `u` of the way along stroke `i`: sky, hill, sun, flower.
    static func strokePoint(_ i: Int, _ u: Double) -> CGPoint {
        let x: Double, y: Double
        switch i {
        case 0: x = 4 + 18 * u; y = 6 + 1.6 * sin(u * 2 * tau)
        case 1:
            let a = (1 - u) * (1 - u), b = 2 * u * (1 - u), c = u * u
            x = a * 2 + b * 12 + c * 24; y = a * 27 + b * 10 + c * 24
        case 2: let ang = -tau / 4 + tau * u; x = 18.5 + 2.6 * cos(ang); y = 13 + 2.6 * sin(ang)
        default: let ang = tau * u; x = 7 + 1.8 * cos(ang); y = 24.5 + 1.8 * sin(ang)
        }
        return CGPoint(x: canvasOrigin.x + CGFloat(x), y: canvasOrigin.y + CGFloat(y))
    }

    struct Paint { var done: [Double]; var tip: CGPoint; var color: Int; var fade: Double }

    static func paint(_ t: Double) -> Paint {
        let s = phase(t, paintPeriod) * paintPeriod
        let done = (0..<4).map { min(max((s - strokeStart - strokeGap * Double($0)) / strokeLen, 0), 1) }
        let fade = 1 - smooth((s - 9.0) / 0.6)
        let lastEnd = strokeStart + strokeGap * 3 + strokeLen
        var tip = brushRest, color = 0
        if s < strokeStart {
            tip = mix(brushRest, strokePoint(0, 0), smooth(s / strokeStart))
        } else if s >= lastEnd {
            tip = mix(strokePoint(3, 1), brushRest, smooth((s - lastEnd) / 0.8)); color = 3
        } else {
            let i = min(Int((s - strokeStart) / strokeGap), 3)
            let local = s - strokeStart - strokeGap * Double(i)
            if local <= strokeLen {
                tip = strokePoint(i, local / strokeLen); color = i
            } else {
                // Lift off, swing to the next stroke, pick up its colour on the way.
                let q = (local - strokeLen) / (strokeGap - strokeLen)
                tip = mix(strokePoint(i, 1), strokePoint(i + 1, 0), smooth(q))
                tip.x -= 7 * CGFloat(bump(q))
                color = q < 0.5 ? i : i + 1
            }
        }
        return Paint(done: done, tip: tip, color: color, fade: fade)
    }

    // MARK: Knitting

    static let stitch = 0.9
    /// −1…1: the needles rocking against each other, once per stitch.
    static func needleSwing(_ t: Double) -> Double { sin(tau * t / stitch) }

    // MARK: Guitar and drums

    static let strumBeat = 0.6
    static let drumBeat = 0.3

    /// One stick: its angle from the pivot (radians) and seconds since its last hit.
    static func stick(_ t: Double, left: Bool) -> (angle: Double, since: Double) {
        let cycleLen = 2 * drumBeat
        let deg = Double.pi / 180
        let lift = { (q: Double) in 62 * bump(pow(q, 0.75)) }
        if left {
            let q = phase(t, cycleLen)
            return ((30 - lift(q)) * deg, q * cycleLen)
        }
        // The right stick hits on the off-beats; every fourth hit goes to the cymbal.
        let tr = t - drumBeat
        let q = phase(tr, cycleLen)
        let c = Int((tr / cycleLen).rounded(.down)) % 4
        let k = c < 0 ? c + 4 : c
        let target = { (cymbal: Bool) in cymbal ? (336.0, -1.0) : (150.0, 1.0) }
        let from = target(k == 3), to = target(k == 2)
        let w = smooth(q)
        let angle = from.0 + (to.0 - from.0) * w + (from.1 + (to.1 - from.1) * w) * lift(q)
        return (angle * deg, q * cycleLen)
    }

    /// Seconds since the last cymbal crash (once per bar of eight beats).
    static func sinceCrash(_ t: Double) -> Double { phase(t - 7 * drumBeat, 8 * drumBeat) * 8 * drumBeat }

    // MARK: Gaming

    /// 0 outside the celebration jump, else 0…1 through it.
    static func gameJump(_ t: Double) -> Double {
        let s = phase(t, 7) * 7
        return s > 5.7 && s < 6.6 ? (s - 5.7) / 0.9 : 0
    }

    /// Which control is pressed: 0…3 face buttons, 4…7 d-pad directions, −1 none.
    static func press(_ t: Double) -> Int {
        let slot = Int((t / 0.22).rounded(.down))
        guard phase(t, 0.22) < 0.6 else { return -1 }
        let h = ((slot &* 2_654_435_761) >> 7) & 0xFFFF
        return h % 9 == 8 ? -1 : h % 8
    }

    // MARK: Disco

    static let discoBeat = 0.5
    static let spotColors = [HobbyInk.pink, Color(hex: 0x5CE1FF), HobbyInk.yellow, Color(hex: 0x7CFF6B), Color(hex: 0xB57CFF)]

    static func spot(_ t: Double, _ i: Int) -> CGPoint {
        let f = Double(i)
        let x = 50 + 62 * sin(t * (0.55 + 0.07 * f) + f * 1.3)
        let y = 56 + 40 * sin(t * (0.8 - 0.05 * f) + f * 2.1)
        return CGPoint(x: x, y: y)
    }

    // MARK: Camera

    static let cameraPeriod = 4.5

    /// Flash brightness, how far the photo is out, how developed, its tilt and its visibility.
    static func shot(_ t: Double) -> (flash: Double, eject: Double, develop: Double, tip: Double, photo: Double) {
        let s = phase(t, cameraPeriod) * cameraPeriod
        let flash = s < 0.5 ? 1 - s / 0.5 : 0
        let eject = smooth((s - 0.3) / 0.8)
        let tip = smooth((s - 1.1) / 0.4)
        let develop = smooth((s - 1.3) / 1.5)
        let photo = s < 0.3 ? 0 : 1 - smooth((s - 3.9) / 0.5)
        return (flash, eject, develop, tip, photo)
    }

    // MARK: Rubik's cube

    /// The top layer's angle (radians) and seconds since it last clicked into place.
    static func cubeTurn(_ t: Double) -> (angle: Double, since: Double) {
        let step = 1.5, turn = 0.6
        let s = phase(t, 4 * step) * 4 * step
        let k = (s / step).rounded(.down)
        let local = s - k * step
        let q = smooth((local - (step - turn)) / turn)
        return ((k + q) * .pi / 2, local)
    }

    // MARK: House of cards

    struct Card { var center: CGPoint; var angle: Double; var red: Bool; var alpha: Double }

    static let cardPeriod = 9.4
    /// Each card's resting place: centre and angle (radians), bottom row first.
    static let cardSlots: [(CGPoint, Double)] = {
        func lean(_ a: CGPoint, _ b: CGPoint) -> (CGPoint, Double) {
            (CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), atan2(Double(b.y - a.y), Double(b.x - a.x)))
        }
        return [
            lean(CGPoint(x: 98, y: 104), CGPoint(x: 104, y: 87)),
            lean(CGPoint(x: 110, y: 104), CGPoint(x: 104, y: 87)),
            lean(CGPoint(x: 110.5, y: 104), CGPoint(x: 116.5, y: 87)),
            lean(CGPoint(x: 122.5, y: 104), CGPoint(x: 116.5, y: 87)),
            (CGPoint(x: 110.3, y: 85), 0),
            lean(CGPoint(x: 104.5, y: 83), CGPoint(x: 110.3, y: 66)),
            lean(CGPoint(x: 116, y: 83), CGPoint(x: 110.3, y: 66)),
        ]
    }()

    /// The cards in play, what the eyes follow, and 0…1 through the collapse (0 while building).
    static func cards(_ t: Double) -> (cards: [Card], focus: CGPoint, collapse: Double) {
        let s = phase(t, cardPeriod) * cardPeriod
        let hand = CGPoint(x: 86, y: 80)
        let start = 0.3, every = 0.85, fly = 0.55, fallAt = 7.0, fall = 1.4
        var cards: [Card] = []
        var focus = CGPoint(x: 110, y: 80)
        let collapse = s > fallAt ? min((s - fallAt) / fall, 1) : 0
        let fadeOut = 1 - smooth((s - fallAt - fall) / 0.6)
        for (i, slot) in cardSlots.enumerated() {
            let t0 = start + every * Double(i)
            guard s >= t0 else { break }
            let red = i % 2 == 1
            if s < t0 + fly {
                // Flying from the body to its place, turning upright on the way.
                let q = smooth((s - t0) / fly)
                var p = mix(hand, slot.0, q)
                p.y -= 10 * CGFloat(bump(q))
                cards.append(Card(center: p, angle: slot.1 * q, red: red, alpha: 1))
                focus = p
            } else if collapse > 0 {
                let seed = Double(i)
                let q = collapse
                let drop = q * q
                let restX = slot.0.x + CGFloat(6 * sin(seed * 2.3 + 1)) * CGFloat(q)
                let restY = slot.0.y + (102 - slot.0.y + CGFloat(seed.truncatingRemainder(dividingBy: 3))) * CGFloat(drop)
                let flat = (sin(seed * 1.7) > 0 ? 0.08 : -0.08) + (cos(slot.1) < 0 ? Double.pi : 0)
                let angle = slot.1 + (flat - slot.1) * smooth(q * 1.3)
                cards.append(Card(center: CGPoint(x: restX, y: restY), angle: angle, red: red, alpha: fadeOut))
            } else {
                cards.append(Card(center: slot.0, angle: slot.1, red: red, alpha: 1))
            }
        }
        if collapse > 0 { focus = CGPoint(x: 110, y: 100) }
        return (cards, focus, collapse)
    }

    // MARK: Fishbowl

    static let bowlCenter = CGPoint(x: 54, y: 86)
    static let bowlRadius: CGFloat = 21
    static let waterLine: CGFloat = 74

    /// The fish's position and facing (1 right, −1 left, squeezed in between while it turns).
    static func fish(_ t: Double) -> (x: CGFloat, y: CGFloat, facing: CGFloat) {
        let a = tau * t / 6
        let x = bowlCenter.x + CGFloat(10 * sin(a))
        let y = bowlCenter.y + 2 + CGFloat(3 * sin(tau * t / 3.1))
        let facing = CGFloat(min(max(cos(a) * 3, -1), 1))
        return (x, y, abs(facing) < 0.2 ? (facing < 0 ? -0.2 : 0.2) : facing)
    }
}
