import AppKit
import BudgetCore
import QuotaKit
import SwiftUI

/// Brand colour of the app icon: the Claude blob's orange, a touch deeper so it holds on white and in the Dock.
enum Brand {
    static let orange = Color(hex: 0xFF8A57)
    static let ink = Color(hex: 0x1B1B1B)
}

/// The app icon ("B"): the tile is the blob, with its two big eyes. One bold shape, readable at 16 px and from afar.
/// `inset` leaves the margin macOS icons keep around the tile (100 of 1024 on each side); 0 draws the bare tile.
struct AppIconView: View {
    var size: CGFloat
    var inset: CGFloat = 100.0 / 1024

    var body: some View {
        let tile = size * (1 - 2 * inset)
        let k = tile / 100
        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(Brand.orange)
                .shadow(color: .black.opacity(inset > 0 ? 0.28 : 0), radius: size * 0.02, y: size * 0.012)
            ForEach([CGFloat(35), 64], id: \.self) { x in
                RoundedRectangle(cornerRadius: 8.5 * k, style: .continuous)
                    .fill(Brand.ink)
                    .frame(width: 17 * k, height: 40 * k)
                    .rotationEffect(.degrees(-6))
                    .offset(x: (x - 50) * k, y: -4 * k)
            }
        }
        .frame(width: tile, height: tile)
        .frame(width: size, height: size)
    }
}

/// The menu bar icon ("D"): a thick ring that empties as the charge runs down, two calm eyes inside.
/// The eyes never change: at menu bar size, mood shapes melt into dots; the ring carries the news.
/// Drawn in black for a template image: the faint track is partial alpha, macOS tints the rest.
struct MenuRing: View {
    var level: Double
    var size: CGFloat

    var body: some View {
        let k = size / 100
        let line = 12 * k
        ZStack {
            Circle().stroke(Color.black.opacity(0.3), lineWidth: line)
            Circle().trim(from: 0, to: max(0.04, min(level, 1)))
                .stroke(Color.black, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Two upright pills with a clear gap: the blob's face, kept large enough to stay apart at 18 pt.
            ForEach([CGFloat(-11.5), 11.5], id: \.self) { dx in
                Capsule()
                    .fill(Color.black)
                    // Shorter than a pause bar and set above centre, so it reads as a face, not a "pause" glyph.
                    .frame(width: 13 * k, height: 23 * k)
                    .rotationEffect(.degrees(-8))
                    .offset(x: dx * k, y: -4 * k)
            }
        }
        .padding(line / 2)
        .frame(width: size, height: size)
    }
}

enum IconExport {
    /// `Slowburn --export-icons dir`: AppIcon.iconset (all macOS sizes), AppIcon.icns, a 1024 PNG and the
    /// bare tile for landings, then exits.
    @MainActor
    static func run(to dir: String) {
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        let iconset = base.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for pt in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
                write(AppIconView(size: CGFloat(pt)), scale: CGFloat(scale), to: iconset.appendingPathComponent(name))
            }
        }
        write(AppIconView(size: 1024), scale: 1, to: base.appendingPathComponent("AppIcon-1024.png"))
        write(AppIconView(size: 1024, inset: 0), scale: 1, to: base.appendingPathComponent("AppIcon-tile-1024.png"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconset.path, "-o", base.appendingPathComponent("AppIcon.icns").path]
        try? p.run()
        p.waitUntilExit()
        exit(0)
    }

    /// `Slowburn --export-activities dir name,name…`: one transparent PNG per activity, for the landing page.
    /// Claude and Codex take turns, each caught at a moment where its props are mid-action.
    @MainActor
    static func activities(to dir: String, names: [String]) {
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (i, name) in names.enumerated() {
            guard let a = Activity(rawValue: name) else { continue }
            let provider: Provider = i % 2 == 0 ? .claude : .codex
            let view = BlobView(provider: provider, mood: .calm, level: 1, size: 120, animate: false,
                                activity: a, stillTime: 1.1 + Double(i) * 0.37)
                .frame(width: 240, height: 220)
                .environment(\.colorScheme, .dark)
            write(view, scale: 2, to: base.appendingPathComponent("\(name).png"))
        }
        exit(0)
    }

    /// `Slowburn --export-clip out.mp4 <what> [seconds]`: renders frames with a fixed blob clock and encodes
    /// them with ffmpeg (H.264, plays everywhere). `what` is `popover`, or `blob:<activity>:<claude|codex>`.
    /// Blob clips sit on the landing's card colour, since Safari can't play transparent video.
    @MainActor
    static func clip(to out: String, what: String, seconds: Double) {
        let fps = 30
        let frames = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("slowburn-frames-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: frames) }
        let parts = what.split(separator: ":").map(String.init)
        let model = parts[0] == "popover" ? Model() : nil
        // Start late in the day so the moods, glances and props are all mid-cycle.
        let t0 = 1000.0
        for i in 0..<Int(seconds * Double(fps)) {
            let t = t0 + Double(i) / Double(fps)
            let url = frames.appendingPathComponent(String(format: "f%04d.png", i))
            if let model {
                write(PopoverView(model: model, anchored: false)
                        .background(Color(white: 0.17))
                        .environment(\.colorScheme, .dark)
                        .environment(\.blobClock, t),
                      scale: 2, to: url)
            } else if parts.count >= 2, let a = Activity(rawValue: parts[1]) {
                let provider: Provider = parts.count > 2 && parts[2] == "codex" ? .codex : .claude
                write(BlobView(provider: provider, mood: .calm, level: 1, size: 120, activity: a)
                        .frame(width: 240, height: 220)
                        .background(Color(hex: 0x221E1B))
                        .environment(\.colorScheme, .dark)
                        .environment(\.blobClock, t),
                      scale: 2, to: url)
            }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        p.arguments = ["-y", "-loglevel", "error", "-framerate", "\(fps)", "-i", frames.appendingPathComponent("f%04d.png").path,
                       "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22",
                       "-preset", "slow", "-movflags", "+faststart", out]
        try? p.run()
        p.waitUntilExit()
        exit(0)
    }

    /// `Slowburn --export-ui dir`: pieces of the panel rendered on their own, each as a small panel with even
    /// padding and rounded corners (for the landing): the Claude and Codex cards, the waiting-agents card, the switch.
    @MainActor
    static func ui(to dir: String) {
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let model = Model()
        func mini<V: View>(_ v: V) -> some View {
            v.padding(14)
                .frame(width: 380)
                .background(Color(white: 0.17))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .environment(\.colorScheme, .dark)
                .environment(\.blobClock, 1003.4)
        }
        if var p = model.presentation {
            for provider in Provider.allCases {
                p.blobs = model.presentation!.blobs.filter { $0.provider == provider }
                p.limits = model.presentation!.limits.filter { $0.provider == provider }
                let card = SmartLayout(p: p, activities: model.activities, busy: model.busy,
                                       onBoost: { _, _ in }, onAutoReserve: { _, _ in })
                write(mini(card), scale: 2, to: base.appendingPathComponent("card-\(provider.rawValue).png"))
            }
        }
        if !HoldsModel.shared.pending.isEmpty {
            write(mini(HoldQueueCard(holds: HoldsModel.shared, model: model, snapshot: true)), scale: 2,
                  to: base.appendingPathComponent("hold.png"))
        }
        write(mini(MasterSwitchCard(on: true, set: { _ in }, pause: { _ in })), scale: 2, to: base.appendingPathComponent("switch.png"))
        exit(0)
    }

    @MainActor
    static func write<V: View>(_ view: V, scale: CGFloat, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = scale
        guard let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
