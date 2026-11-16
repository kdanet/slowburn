import AppKit
import Foundation
import QuotaKit
import Sparkle

/// In-app updates through Sparkle: the appcast lives on the website, every update is signed with our EdDSA key
/// and notarized. Only a real Slowburn.app updates itself — a `swift build` binary has no bundle to replace.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false

    /// The version people see, e.g. "0.2.0"; nil outside a bundle.
    var version: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }

    private init() {
        let bundled = Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = bundled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        controller?.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    var available: Bool { controller != nil }

    func check() { controller?.checkForUpdates(nil) }
}

/// The hooks run a copy of `quota` kept in the data folder, so they survive the app moving. When the app
/// updates, that copy is refreshed from the new bundle on the next launch.
enum HookBinary {
    static func refresh(paths: Paths = Paths()) {
        let fm = FileManager.default
        let dest = paths.support.appendingPathComponent("bin/quota")
        let src = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/quota")
        guard Bundle.main.bundleURL.pathExtension == "app", fm.fileExists(atPath: dest.path), fm.fileExists(atPath: src.path),
              !fm.contentsEqual(atPath: src.path, andPath: dest.path) else { return }
        let tmp = dest.deletingLastPathComponent().appendingPathComponent("quota.new")
        try? fm.removeItem(at: tmp)
        guard (try? fm.copyItem(at: src, to: tmp)) != nil else { return }
        _ = try? fm.replaceItemAt(dest, withItemAt: tmp)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }
}
