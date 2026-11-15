import Foundation

/// The interface language: Russian or English, picked from the system's preferred languages.
/// `SLOWBURN_LANG=en|ru` overrides it (screenshots, testing). Strings are written in place as `L("рус", "eng")`.
public enum Lang: String, Sendable {
    case ru, en

    public static let current: Lang = {
        if let forced = ProcessInfo.processInfo.environment["SLOWBURN_LANG"].flatMap(Lang.init(rawValue:)) { return forced }
        let first = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return first.hasPrefix("ru") ? .ru : .en
    }()

    public static var isRussian: Bool { current == .ru }

    /// The locale for dates and numbers that matches the interface language.
    public static var locale: Locale { Locale(identifier: current == .ru ? "ru_RU" : "en_US") }
}

/// One string in both languages.
@inline(__always)
public func L(_ ru: String, _ en: String) -> String { Lang.current == .ru ? ru : en }
