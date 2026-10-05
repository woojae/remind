import Foundation

/// User-adjustable behaviour. Views bind to the same keys through @AppStorage;
/// non-view code reads through these accessors.
enum Prefs {
    enum Key {
        static let repeatMinutes  = "repeatMinutes"   // how often a due task nags
        static let spacingSeconds = "spacingSeconds"  // minimum gap between any two notifications
        static let morningHour    = "morningHour"     // "tomorrow morning", all-day reminders
        static let quietEnabled   = "quietEnabled"
        static let quietStart     = "quietStart"      // hour, 0-23
        static let quietEnd       = "quietEnd"        // hour, 0-23
        static let attachAlarms   = "attachAlarms"    // also set an EventKit alarm so other devices notify
        static let excludedLists  = "excludedLists"   // JSON array of calendar identifiers
        static let defaultList    = "defaultList"     // calendar identifier, "" = Reminders default
    }

    static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.repeatMinutes: 10,
            Key.spacingSeconds: 30,
            Key.morningHour: 9,
            Key.quietEnabled: true,
            Key.quietStart: 22,
            Key.quietEnd: 8,
            Key.attachAlarms: true,
            Key.excludedLists: "[]",
            Key.defaultList: "",
        ])
    }

    static var repeatInterval: TimeInterval { Double(max(1, defaults.integer(forKey: Key.repeatMinutes))) * 60 }
    static var spacing: TimeInterval { Double(max(5, defaults.integer(forKey: Key.spacingSeconds))) }
    static var morningHour: Int { defaults.integer(forKey: Key.morningHour) }
    static var attachAlarms: Bool { defaults.bool(forKey: Key.attachAlarms) }
    static var defaultList: String { defaults.string(forKey: Key.defaultList) ?? "" }

    static var excludedLists: Set<String> {
        get {
            guard let raw = defaults.string(forKey: Key.excludedLists),
                  let ids = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) else { return [] }
            return Set(ids)
        }
        set {
            let data = (try? JSONEncoder().encode(Array(newValue).sorted())) ?? Data("[]".utf8)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: Key.excludedLists)
        }
    }

    /// Quiet hours suppress notifications (the list still shows what's due).
    static func isQuiet(at date: Date) -> Bool {
        guard defaults.bool(forKey: Key.quietEnabled) else { return false }
        let start = defaults.integer(forKey: Key.quietStart)
        let end = defaults.integer(forKey: Key.quietEnd)
        guard start != end else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end          // wraps midnight, e.g. 22 → 8
    }

    /// `date` itself if notifications are allowed then; otherwise the moment
    /// quiet hours end. Used to pre-schedule nags on iOS.
    static func nextAllowed(after date: Date) -> Date {
        guard isQuiet(at: date) else { return date }
        let cal = Calendar.current
        let end = defaults.integer(forKey: Key.quietEnd)
        var d = cal.date(bySettingHour: end, minute: 0, second: 0, of: cal.startOfDay(for: date)) ?? date
        if d <= date { d = cal.date(byAdding: .day, value: 1, to: d) ?? date }
        return d
    }
}
