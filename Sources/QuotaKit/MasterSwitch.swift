import Foundation

/// The big switch at the top of the popover: with it off, Slowburn only watches. Hooks let every prompt and
/// tool call through at once — no holds, no warnings, no stopped sessions — until it is switched back on.
public enum MasterSwitch {
    static func url(_ paths: Paths) -> URL { paths.support.appendingPathComponent("limits-off.json") }

    /// True while all limits and hooks are switched off.
    public static func isOff(paths: Paths) -> Bool {
        FileManager.default.fileExists(atPath: url(paths).path)
    }

    /// Switching off also lets go of everyone waiting now and forgets sessions told to stop.
    public static func set(on: Bool, paths: Paths, now: Date = Date()) {
        if on {
            try? FileManager.default.removeItem(at: url(paths))
            return
        }
        try? JSONFile.save(now, to: url(paths))
        HoldQueue.decideAll(HoldDecision(verdict: .allow, decidedAt: now), paths: paths)
        let stopped = HoldQueue.stoppedDir(paths)
        for f in (try? FileManager.default.contentsOfDirectory(at: stopped, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
    }
}
