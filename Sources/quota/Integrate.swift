import BudgetCore
import Foundation
import QuotaKit

/// `quota integrate [claude] [codex]` and `quota uninstall-hooks`.
///
/// Touches only entries that are ours (the stable binary, or the stage-0 probes), keeps everything else —
/// Orca's Codex hooks, your own — in place, and writes a timestamped backup of each config first.
enum Integrate {
    /// Hook timeout the host enforces; the hook itself answers "stop" before it (`BrakeSettings.maxWait`).
    static let hookTimeout = 3600
    /// Any copy of our binary (wherever it was installed from) and the stage-0 probes.
    static let ourMarkers = ["/bin/quota' hook ", "Slowburn/bin/quota", "Claudergy/bin/quota", "Slowburn/probes/", "Claudergy/probes/"]

    static func installBinary(paths: Paths) throws -> URL {
        let bin = paths.support.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let dest = bin.appendingPathComponent("quota")
        guard let src = Bundle.main.executableURL?.resolvingSymlinksInPath() else { throw CocoaError(.fileNoSuchFile) }
        if src.path != dest.path {
            let tmp = bin.appendingPathComponent("quota.new")
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: src, to: tmp)
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }

    static func config(for provider: Provider, home: URL) -> URL {
        provider == .claude ? home.appendingPathComponent(".claude/settings.json") : home.appendingPathComponent(".codex/hooks.json")
    }

    static func isOurs(_ group: [String: Any]) -> Bool {
        let hooks = group["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { h in ourMarkers.contains { (h["command"] as? String)?.contains($0) == true } }
    }

    /// Rewrites one config: drops our old entries everywhere, then (unless removing) adds the brake.
    static func apply(provider: Provider, binary: URL?, paths: Paths) throws -> String {
        let url = config(for: provider, home: paths.home)
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = parsed
            let backups = paths.support.appendingPathComponent("backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try data.write(to: backups.appendingPathComponent("\(provider.rawValue)-\(url.lastPathComponent).\(stamp)"))
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var removed = 0
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            removed += groups.count - kept.count
            hooks[event] = kept.isEmpty ? nil : kept
        }
        if let line = root["statusLine"] as? [String: Any], ourMarkers.contains(where: { (line["command"] as? String)?.contains($0) == true }) {
            root["statusLine"] = nil
        }
        var added = 0
        if let binary {
            for event in ["UserPromptSubmit", "PreToolUse"] {
                var groups = hooks[event] as? [[String: Any]] ?? []
                groups.append(["hooks": [[
                    "type": "command",
                    "command": "'\(binary.path)' hook \(provider.rawValue) \(event)",
                    "timeout": hookTimeout,
                ]]])
                hooks[event] = groups
                added += 1
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try out.write(to: url, options: .atomic)
        return "\(Phrases.providerName(provider)): убрано старых записей \(removed), добавлено \(added) · \(url.path)"
    }

    static func run(args: [String], paths: Paths) -> Int32 {
        let uninstall = args.first == "uninstall-hooks"
        var providers = args.dropFirst().compactMap(Provider.init(rawValue:))
        if providers.isEmpty { providers = uninstall ? Provider.allCases : [.claude] }
        do {
            let binary = uninstall ? nil : try installBinary(paths: paths)
            if let binary { print("Бинарник: \(binary.path)") }
            for p in providers { print(try apply(provider: p, binary: binary, paths: paths)) }
            if !uninstall {
                print("Тормоз держит агентов, только пока запущено приложение Slowburn.")
                if providers.contains(.codex) { print("Codex: разреши новые хуки в Codex Desktop, иначе он их не запустит.") }
            }
            return 0
        } catch {
            print("Не получилось: \(error.localizedDescription). Конфиги не тронуты, бэкапы в \(paths.support.path)/backups")
            return 1
        }
    }
}
