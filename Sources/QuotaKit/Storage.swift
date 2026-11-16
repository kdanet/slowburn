import Foundation

/// Every file Slowburn reads or writes. `SLOWBURN_HOME` relocates our own files (tests, experiments).
public struct Paths: Sendable {
    public var home: URL
    public var support: URL

    /// `HOME` wins over the account's home directory, so a test with a fake HOME can never touch real configs.
    public static var defaultHome: URL {
        if let h = ProcessInfo.processInfo.environment["HOME"], !h.isEmpty { return URL(fileURLWithPath: h, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public init(home: URL = Paths.defaultHome, support: URL? = nil) {
        self.home = home
        if let support {
            self.support = support
        } else if let env = ["SLOWBURN_HOME", "CLAUDERGY_HOME"].lazy.compactMap({ ProcessInfo.processInfo.environment[$0] })
                    .first(where: { !$0.isEmpty }) {
            self.support = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            self.support = home.appendingPathComponent("Library/Application Support/Slowburn", isDirectory: true)
            Paths.moveLegacySupport(home: home, to: self.support)
        }
    }

    /// The app used to be Claudergy. Its data moves to the new folder once, and the old path becomes a link to it,
    /// so hooks already installed with the old path keep working until they are reinstalled.
    static func moveLegacySupport(home: URL, to new: URL) {
        let fm = FileManager.default
        let old = home.appendingPathComponent("Library/Application Support/Claudergy", isDirectory: true)
        guard !fm.fileExists(atPath: new.path),
              let attrs = try? fm.attributesOfItem(atPath: old.path),
              attrs[.type] as? FileAttributeType == .typeDirectory else { return }
        // Another process may win the race; whoever loses simply finds the new folder in place.
        guard (try? fm.moveItem(at: old, to: new)) != nil else { return }
        try? fm.createSymbolicLink(at: old, withDestinationURL: new)
    }

    public var codexSessions: URL { home.appendingPathComponent(".codex/sessions", isDirectory: true) }
    public var claudeProjects: URL { home.appendingPathComponent(".claude/projects", isDirectory: true) }

    public var state: URL { support.appendingPathComponent("state.json") }
    public var plans: URL { support.appendingPathComponent("plans.json") }
    public var history: URL { support.appendingPathComponent("history.json") }
    public var offsets: URL { support.appendingPathComponent("offsets.json") }
    public var claudeTokens: URL { support.appendingPathComponent("claude-tokens.json") }
    public var codexTokens: URL { support.appendingPathComponent("codex-tokens.json") }
    public var statusLineInbox: URL { support.appendingPathComponent("claude-statusline.json") }
    public var override: URL { support.appendingPathComponent("override.json") }
    public var settings: URL { support.appendingPathComponent("settings.json") }
    public var endpointState: URL { support.appendingPathComponent("claude-endpoint.json") }
    public var cliUsageState: URL { support.appendingPathComponent("claude-cli-usage.json") }
}

public enum JSONFile {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// Atomic write (temp file + rename) so a hook never reads half a file.
    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

/// Reads only the bytes appended since the last call. A file seen for the first time is read
/// from its last `initialTail` bytes: Codex rollouts and Claude transcripts run to gigabytes.
public struct IncrementalReader {
    public var offsets: [String: UInt64]
    public let initialTail: UInt64

    public init(offsets: [String: UInt64], initialTail: UInt64) {
        self.offsets = offsets
        self.initialTail = initialTail
    }

    /// Complete new lines only; a half-written last line waits for the next call.
    public mutating func newLines(in url: URL) -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let key = url.path
        let tailStart: UInt64 = size > initialTail ? size - initialTail : 0
        var start = offsets[key] ?? tailStart
        var jumpedIn = offsets[key] == nil
        if start > size { start = tailStart; jumpedIn = true } // truncated or replaced file
        guard start < size, (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else {
            return []
        }
        offsets[key] = start + UInt64(lastNewline - data.startIndex + 1)
        var lines = data[data.startIndex..<lastNewline].split(separator: 0x0A, omittingEmptySubsequences: true)
        // Jumping into the middle of a file lands inside a line: drop that fragment.
        if jumpedIn, start > 0, !lines.isEmpty { lines.removeFirst() }
        return lines.map { Data($0) }
    }
}

/// Recently modified files under a directory, newest first.
public func recentFiles(under root: URL, ext: String, modifiedWithin: TimeInterval, now: Date) -> [URL] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return [] }
    var found: [(URL, Date)] = []
    for case let url as URL in walker where url.pathExtension == ext {
        guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
              let modified = values.contentModificationDate,
              now.timeIntervalSince(modified) <= modifiedWithin else { continue }
        found.append((url, modified))
    }
    return found.sorted { $0.1 > $1.1 }.map(\.0)
}

/// ISO 8601 with or without fractional seconds of any length, "Z" or an offset.
public func parseISODate(_ string: String) -> Date? {
    var s = string
    var fraction = 0.0
    if let dot = s.firstIndex(of: "."), let tzStart = s[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
        fraction = Double("0" + s[dot..<tzStart]) ?? 0
        s.removeSubrange(dot..<tzStart)
    }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s).map { $0.addingTimeInterval(fraction) }
}

/// JSON numbers or ISO strings for times, epoch seconds or milliseconds for numbers.
func parseTime(_ value: Any?) -> Date? {
    if let n = value as? NSNumber {
        let v = n.doubleValue
        return Date(timeIntervalSince1970: v > 1e12 ? v / 1000 : v)
    }
    if let s = value as? String { return parseISODate(s) ?? Double(s).map { Date(timeIntervalSince1970: $0) } }
    return nil
}

func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
