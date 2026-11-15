import BudgetCore
import QuotaKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }

    /// `amount` of `hex` over the popover's near-black, for the empty part of a blob.
    static func dimmed(_ hex: UInt32, amount: Double = 0.26) -> Color {
        func ch(_ s: UInt32) -> Double { (Double((hex >> s) & 255) * amount + 11 * (1 - amount)) / 255 }
        return Color(.sRGB, red: ch(16), green: ch(8), blue: ch(0))
    }
}

enum Palette {
    static let bg = Color(hex: 0x141414)
    static let ink = Color(hex: 0x0E0E10)
    static let text = Color(hex: 0xF4F2EE)
    static let muted = Color(hex: 0x8E8B86)
    static let dimText = Color(hex: 0x6F6C67)
    static let track = Color(hex: 0x262626)
    static let hair = Color.white.opacity(0.10)
    static let warn = Color(hex: 0xFFC94D)
    static let warnText = Color(hex: 0xFFD27A)
    static let red = Color(hex: 0xFF5C5C)
    static let redText = Color(hex: 0xFF7A7A)
    static let good = Color(hex: 0x7FE3B0)

    static func hex(_ p: Provider, mood: Mood) -> UInt32 {
        if mood == .unknown { return 0xBDB9B2 }
        return p == .claude ? 0xFF9B71 : 0x9C98FF
    }

    static func color(_ p: Provider, mood: Mood = .calm) -> Color { Color(hex: hex(p, mood: mood)) }
}

/// Claude's soft blob, drawn in a 100×100 box.
struct ClaudeShape: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var path = Path()
        path.move(to: p(52, 9))
        path.addCurve(to: p(91, 54), control1: p(79, 10), control2: p(93, 28))
        path.addCurve(to: p(48, 93), control1: p(89, 80), control2: p(72, 94))
        path.addCurve(to: p(9, 50), control1: p(22, 92), control2: p(7, 77))
        path.addCurve(to: p(52, 9), control1: p(11, 24), control2: p(26, 8))
        path.closeSubpath()
        return path
    }
}

/// Codex's rounded square, tilted a little.
struct CodexShape: Shape {
    func path(in r: CGRect) -> Path {
        let k = r.width / 100
        let square = CGRect(x: r.minX + 12 * k, y: r.minY + 12 * k, width: 76 * k, height: 76 * k)
        let base = Path(roundedRect: square, cornerRadius: 24 * k, style: .continuous)
        let c = CGPoint(x: r.midX, y: r.midY)
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: -7 * .pi / 180).translatedBy(x: -c.x, y: -c.y)
        return base.applying(t)
    }
}

struct BlobBody: Shape {
    var provider: Provider
    func path(in r: CGRect) -> Path {
        provider == .claude ? ClaudeShape().path(in: r) : CodexShape().path(in: r)
    }
}

/// An eye in the 100×100 box: centre, size, tilt.
struct Eye {
    var cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, rot: Double

    static func pair(_ mood: Mood) -> (Eye, Eye) {
        switch mood {
        case .calm: (Eye(cx: 37, cy: 47, w: 13, h: 25, rot: -6), Eye(cx: 63, cy: 47, w: 13, h: 25, rot: -6))
        case .charged: (Eye(cx: 37, cy: 44, w: 14, h: 29, rot: 0), Eye(cx: 63, cy: 44, w: 14, h: 29, rot: 0))
        case .worried: (Eye(cx: 37, cy: 49, w: 12, h: 24, rot: 18), Eye(cx: 63, cy: 49, w: 12, h: 24, rot: -18))
        case .money: (Eye(cx: 37, cy: 46, w: 17, h: 17, rot: 0), Eye(cx: 63, cy: 46, w: 17, h: 17, rot: 0))
        case .sleepy: (Eye(cx: 36, cy: 52, w: 18, h: 6, rot: 0), Eye(cx: 64, cy: 52, w: 18, h: 6, rot: 0))
        case .unknown: (Eye(cx: 39, cy: 49, w: 8, h: 8, rot: 0), Eye(cx: 61, cy: 49, w: 8, h: 8, rot: 0))
        }
    }
}

/// Procedural motion for one moment: how the body leans and bounces, where the eyes look, whether they blink.
struct Motion {
    var rot = 0.0, sx = 1.0, sy = 1.0, dx = 0.0, dy = 0.0
    var lookX = 0.0, lookY = 0.0, blink = 1.0, float = 0.0

    static func at(_ mood: Mood, t: Double) -> Motion {
        var m = Motion()
        let tau = 2 * Double.pi
        func cycle(_ period: Double) -> Double { t.truncatingRemainder(dividingBy: period) / period }

        // Slow sines with unrelated periods: drift that never visibly repeats or swings like a pendulum.
        func drift(_ a: Double, _ b: Double, _ c: Double) -> Double {
            (sin(tau * t / a) + 0.5 * sin(tau * t / b + 1.3) + 0.25 * sin(tau * t / c + 2.1)) / 1.75
        }

        switch mood {
        case .calm, .unknown:
            let sway = drift(7.3, 4.1, 2.9)
            let breath = sin(tau * t / 3.6)
            m.rot = -2.2 * sway + (mood == .unknown ? -7 : 0)
            m.sx = 1 + 0.018 * breath
            m.sy = 1 - 0.018 * breath
            m.dy = -0.8 * (breath + 1) / 2
        case .charged:
            // Squash, take off, hang, land, settle — on a spline, so speed changes but never stops at a keyframe.
            let v = spline(cycle(1.6), [
                (0.00, [0, 1.00, 1.00]),
                (0.10, [0, 1.07, 0.91]),
                (0.30, [-11, 0.96, 1.05]),
                (0.42, [-12.5, 0.98, 1.02]),
                (0.58, [0, 1.06, 0.93]),
                (0.72, [0, 0.99, 1.01]),
                (0.86, [0, 1.00, 1.00]),
                (1.00, [0, 1.00, 1.00]),
            ])
            m.dy = v[0]; m.sx = v[1]; m.sy = v[2]
        case .worried:
            m.rot = 4.5 * drift(3.1, 1.9, 1.3)
            m.dx = 0.8 * drift(2.3, 1.7, 1.1)
        case .money:
            // A damped shiver, then a calm pause with slow breathing.
            let p = cycle(2.6)
            let breath = sin(tau * t / 2.6)
            m.sx = 1 + 0.015 * breath
            m.sy = 1 - 0.015 * breath
            if p > 0.62 && p < 0.92 {
                let q = (p - 0.62) / 0.30
                let envelope = sin(.pi * q) * pow(1 - q, 1.5) * 1.6
                let wobble = sin(q * .pi * 7) * envelope
                m.dx = 2.6 * wobble; m.rot = 4.5 * wobble
            }
        case .sleepy:
            let s = (sin(tau * t / 5.2) + 1) / 2
            m.rot = -8 + 0.8 * drift(9.1, 6.3, 4.4)
            m.sx = 1.06 + 0.03 * s; m.sy = 0.86 - 0.03 * s
        }

        if mood == .calm || mood == .worried || mood == .unknown {
            // Glance left, right, up, holding each look; eyes glide there with soft starts and stops.
            let v = keyframes(cycle(8), [
                (0.00, [0, 0]), (0.16, [0, 0]),
                (0.26, [-5, 1]), (0.42, [-5, 1]),
                (0.53, [5, -1]), (0.66, [5, -1]),
                (0.76, [0, -3]), (0.88, [0, -3]),
                (0.98, [0, 0]), (1.00, [0, 0]),
            ])
            // A touch of drift so held looks stay alive.
            m.lookX = v[0] + 0.5 * drift(3.7, 2.3, 1.7)
            m.lookY = v[1] + 0.3 * drift(4.3, 2.9, 1.9)
        }
        if mood != .money && mood != .sleepy {
            // Close and open over ~0.3 s, eased at both ends.
            let p = cycle(4.6)
            if p > 0.93 && p < 0.995 {
                let s = sin(.pi * (p - 0.93) / 0.065)
                m.blink = 1 - 0.92 * s * s
            }
        }
        m.float = -4 * (sin(tau * t / 2.2) + 1) / 2
        return m
    }

    /// Between keyframes with quintic smootherstep: soft starts and stops, for held poses.
    static func keyframes(_ p: Double, _ frames: [(Double, [Double])]) -> [Double] {
        guard let next = frames.firstIndex(where: { $0.0 > p }), next > 0 else { return frames.last?.1 ?? [] }
        let (t0, a) = frames[next - 1], (t1, b) = frames[next]
        let x = (p - t0) / max(t1 - t0, 1e-9)
        let e = x * x * x * (x * (6 * x - 15) + 10)
        return zip(a, b).map { $0 + ($1 - $0) * e }
    }

    /// Through keyframes on a Catmull–Rom spline: velocity is continuous, motion flows without stops.
    static func spline(_ p: Double, _ frames: [(Double, [Double])]) -> [Double] {
        guard let next = frames.firstIndex(where: { $0.0 > p }), next > 0 else { return frames.last?.1 ?? [] }
        let i = next - 1
        let p0 = frames[max(i - 1, 0)].1, p1 = frames[i].1, p2 = frames[next].1, p3 = frames[min(next + 1, frames.count - 1)].1
        let x = (p - frames[i].0) / max(frames[next].0 - frames[i].0, 1e-9)
        let x2 = x * x, x3 = x2 * x
        return (0..<p1.count).map { j in
            0.5 * (2 * p1[j] + (p2[j] - p0[j]) * x + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * x2
                + (3 * p1[j] - p0[j] - 3 * p2[j] + p3[j]) * x3)
        }
    }
}

/// A blob: the body is the battery, filled from the bottom; eyes and motion carry the mood.
struct BlobView: View {
    var provider: Provider
    var mood: Mood
    var level: Double
    var size: CGFloat
    var animate = true
    var effects = true
    /// What the blob is busy with; nil draws the bare blob.
    var activity: Activity? = nil
    /// The moment drawn when not animating, for snapshots.
    var stillTime: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if animate && !reduceMotion {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                frame(Motion.at(mood, activity: activity, t: t), t: t)
            }
        } else {
            frame(Motion.at(mood, activity: activity, t: stillTime), t: stillTime)
        }
    }

    private var k: CGFloat { size / 100 }

    private func frame(_ m: Motion, t: Double) -> some View {
        let hex = Palette.hex(provider, mood: mood)
        let bright = Color(hex: hex)
        let dim = Color.dimmed(hex)
        let (l, r) = Eye.pair(mood)
        // The body spans y 8...94 of the box; the fill covers `level` of that height.
        let fillHeight = size * (86 * CGFloat(min(max(level, 0), 1)) + 6) / 100

        return ZStack {
            layer(fill: dim, eyes: bright, l: l, r: r, m: m)
            layer(fill: bright, eyes: Palette.ink, l: l, r: r, m: m)
                .mask(alignment: .bottom) { Rectangle().frame(height: fillHeight) }
                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: level)
        }
        .frame(width: size, height: size)
        // One Metal-composited layer instead of re-masking two vector layers on the CPU every frame.
        .drawingGroup()
        // Held props ride along with the body; they live outside the drawing group, which would clip them.
        .overlay { props(.held, t: t) }
        .scaleEffect(x: m.sx, y: m.sy, anchor: .bottom)
        .rotationEffect(.degrees(m.rot), anchor: .bottom)
        .offset(x: m.dx * k, y: m.dy * k)
        .background { props(.behind, t: t) }
        .overlay { props(.front, t: t) }
        .overlay(alignment: .topTrailing) { effectsView(m) }
        .animation(.easeInOut(duration: 0.45), value: activity)
        .accessibilityElement()
        .accessibilityLabel("\(Phrases.providerName(provider)): \(mood.name)" + (activity.map { ", \($0.name)" } ?? ""))
    }

    @ViewBuilder private func props(_ layer: ActivityProps.Layer, t: Double) -> some View {
        if effects, size >= 24, let activity {
            ActivityProps(activity: activity, layer: layer, size: size, t: t, tint: Palette.color(provider, mood: mood))
                .id(activity)
                .transition(.opacity)
        }
    }

    private func layer(fill: Color, eyes: Color, l: Eye, r: Eye, m: Motion) -> some View {
        ZStack(alignment: .topLeading) {
            BlobBody(provider: provider).fill(fill)
            eye(l, color: eyes, m: m)
            eye(r, color: eyes, m: m)
        }
        .frame(width: size, height: size)
    }

    private func eye(_ e: Eye, color: Color, m: Motion) -> some View {
        RoundedRectangle(cornerRadius: min(e.w, e.h) / 2 * k, style: .continuous)
            .fill(color)
            .frame(width: e.w * k, height: e.h * k)
            .scaleEffect(x: 1, y: m.blink)
            .rotationEffect(.degrees(e.rot))
            .position(x: (e.cx + m.lookX) * k, y: (e.cy + m.lookY) * k)
    }

    @ViewBuilder private func effectsView(_ m: Motion) -> some View {
        if effects && size >= 40 {
            switch mood {
            case .money:
                ZStack {
                    Circle().fill(Palette.warn)
                    Capsule().fill(Palette.ink).frame(width: 2.4 * k, height: 10 * k)
                }
                .frame(width: 18 * k, height: 18 * k)
                .offset(x: 4 * k, y: (-4 + m.float) * k)
            case .sleepy:
                Text("zz")
                    .font(.system(size: 13 * k, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .offset(x: 2 * k, y: (2 + m.float) * k)
            default:
                EmptyView()
            }
        }
    }
}

/// The blob's silhouette with its eyes cut out, for a monochrome menu bar icon.
struct TemplateBlob: View {
    var provider: Provider
    var mood: Mood
    var size: CGFloat

    var body: some View {
        let k = size / 100
        let (l, r) = Eye.pair(mood)
        ZStack(alignment: .topLeading) {
            BlobBody(provider: provider).fill(Color.black)
            ForEach([l, r].indices, id: \.self) { i in
                let e = [l, r][i]
                // Thin eyes vanish at menu bar size: give them a floor.
                RoundedRectangle(cornerRadius: max(min(e.w, e.h), 12) / 2 * k)
                    .frame(width: max(e.w, 12) * k, height: max(e.h, 12) * k)
                    .rotationEffect(.degrees(e.rot))
                    .position(x: e.cx * k, y: e.cy * k)
                    .blendMode(.destinationOut)
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

/// The menu bar icon is a template image, like system items: macOS tints it for light, dark and highlighted bars.
@MainActor
func menuBarImage(provider: Provider, mood: Mood, level: Double) -> NSImage? {
    // The ring empties as the charge runs down; the eyes carry the mood.
    let renderer = ImageRenderer(content: MenuRing(level: level, size: 18))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    guard let image = renderer.nsImage else { return nil }
    image.isTemplate = true
    return image
}
