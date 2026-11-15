import BudgetCore
import QuotaKit
import SwiftUI

/// Prop colours that read on both the dark and the light popover.
enum PropInk {
    static let metal = Color(hex: 0xC9C5BE)
    static let metalEdge = Color(hex: 0x6A6660)
    static let paper = Color(hex: 0xF6F1E6)
    static let cover = Color(hex: 0x4F7BD9)
    static let mug = Color(hex: 0xF2EDE4)
    static let coffee = Color(hex: 0x6B4429)
    static let steam = Color(hex: 0xB9B4AC)
    static let cordOnLight = Color(hex: 0x2E2C2A)
    static let cordOnDark = Color(hex: 0xB8B3AB)
    static let leaf = Color(hex: 0x6CCB7E)
    static let pot = Color(hex: 0xD9774B)
    static let water = Color(hex: 0x7CC4F2)
    static let star = Color(hex: 0xFFD97A)
    static let starOnLight = Color(hex: 0xE3A52B)
    static let balloon = Color(hex: 0xFF5C7A)
    static let good = Color(hex: 0x5FD08A)
    static let bad = Color(hex: 0xFF5C5C)
    static let wood = Color(hex: 0xB07A4A)
    static let fire = Color(hex: 0xFF9A3C)
    static let balls = [Color(hex: 0xFF6B6B), Color(hex: 0x6BC6FF), Color(hex: 0xFFD45C)]
}

/// Draws an activity's props in the blob's 100×100 box (they may reach past it, up to `bleed`).
/// The body spans roughly x 9…91, y 8…94; eyes sit near (37, 47) and (63, 47).
/// `.behind` goes under the body, `.held` moves with the body, `.front` stays put in front of it.
struct ActivityProps: View {
    enum Layer { case behind, held, front }

    var activity: Activity
    var layer: Layer
    var size: CGFloat
    var t: Double
    var tint: Color
    @Environment(\.colorScheme) private var scheme

    /// The canvas reaches this far past the box on every side, as a fraction of the box.
    static let bleed: CGFloat = 0.45

    var dark: Bool { scheme == .dark }
    /// Strings, headbands, outlines: dark on a light popover, light on a dark one.
    var cord: Color { dark ? PropInk.cordOnDark : PropInk.cordOnLight }
    /// Pale gold vanishes on a light popover: deepen it there.
    var star: Color { dark ? PropInk.star : PropInk.starOnLight }

    var body: some View {
        let full = size * (1 + 2 * Self.bleed)
        Canvas { ctx, _ in
            ctx.translateBy(x: size * Self.bleed, y: size * Self.bleed)
            ctx.scaleBy(x: size / 100, y: size / 100)
            draw(&ctx)
        }
        .frame(width: full, height: full)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Helpers

    func cycle(_ period: Double) -> Double { t.truncatingRemainder(dividingBy: period) / period }

    func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); return p
    }

    func label(_ ctx: inout GraphicsContext, _ s: String, at p: CGPoint, size: CGFloat, color: Color,
               weight: Font.Weight = .bold, design: Font.Design = .default) {
        ctx.draw(Text(s).font(.system(size: size, weight: weight, design: design)).foregroundColor(color), at: p)
    }

    func sparkle(_ ctx: inout GraphicsContext, at c: CGPoint, r: CGFloat, color: Color) {
        let star = Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - r))
            p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        }
        ctx.fill(star, with: .color(color))
    }
}
