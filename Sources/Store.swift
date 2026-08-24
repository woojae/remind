import EventKit
import Foundation
import CryptoKit

enum RemindError: Error, CustomStringConvertible {
    case accessDenied(EKAuthorizationStatus)
    case noSuchList(String)
    case noDefaultList
    case notFound(String)
    case ambiguous(String, [EKReminder])
    case badDate(String)
    case usage(String)

    var description: String {
        switch self {
        case .accessDenied(let status):
            return """
            No access to Reminders (status: \(Auth.name(status))).

            \(Auth.remedy(status))
            """
        case .noSuchList(let name):
            return "No reminder list named '\(name)'. Run `remind lists` to see what exists."
        case .noDefaultList:
            return "No default reminder list is configured. Pass --list NAME."
        case .notFound(let ref):
            return "No reminder matches '\(ref)'."
        case .ambiguous(let ref, let matches):
            let lines = matches.prefix(8).map { "  \(Reminders.shortID($0))  \($0.title ?? "")" }
            return "'\(ref)' matches \(matches.count) reminders:\n" + lines.joined(separator: "\n")
        case .badDate(let raw):
            return "Could not understand the date '\(raw)'. Try: today, tomorrow 9am, friday, +3d, 2026-09-01 14:30"
        case .usage(let msg):
            return msg
        }
    }
}

enum Auth {
    static func name(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "not determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "full access"
        case .writeOnly: return "write only"
        @unknown default: return "unknown"
        }
    }

    static func remedy(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .denied, .restricted:
            return """
            Grant it in System Settings > Privacy & Security > Reminders, then enable the
            terminal app you run `remind` from (Terminal, iTerm, Ghostty, ...).
            """
        case .writeOnly:
            return """
            Only write access was granted. Reminders needs full access to read items.
            Toggle the entry for your terminal app in
            System Settings > Privacy & Security > Reminders.
            """
        default:
            return """
            macOS shows the access prompt only for a foreground terminal session. Run
            `remind auth` directly in Terminal/iTerm and approve the dialog. If no dialog
            appears, add your terminal app manually under
            System Settings > Privacy & Security > Reminders.
            """
        }
    }
}

/// Thin wrapper over EventKit, sized to what the CLI needs.
final class Reminders {
    let store = EKEventStore()

    // MARK: - Access

    @discardableResult
    func requestAccess() async throws -> EKAuthorizationStatus {
        let current = EKEventStore.authorizationStatus(for: .reminder)
        if current == .fullAccess { return current }
        _ = try? await store.requestFullAccessToReminders()
        let granted = EKEventStore.authorizationStatus(for: .reminder)
        // A store built before authorization can keep serving an empty cache.
        if granted == .fullAccess { store.reset() }
        return granted
    }

    func requireAccess() async throws {
        let status = try await requestAccess()
        guard status == .fullAccess else {
            throw RemindError.accessDenied(status)
        }
    }

    // MARK: - Lists

    func lists() -> [EKCalendar] {
        store.calendars(for: .reminder).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func defaultList() -> EKCalendar? {
        store.defaultCalendarForNewReminders()
    }

    /// Exact match first, then case-insensitive, then unique prefix.
    func list(named name: String) throws -> EKCalendar {
        let all = lists()
        if let c = all.first(where: { $0.title == name }) { return c }
        if let c = all.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) { return c }
        let prefixed = all.filter { $0.title.lowercased().hasPrefix(name.lowercased()) }
        if prefixed.count == 1 { return prefixed[0] }
        throw RemindError.noSuchList(name)
    }

    func resolveList(_ name: String?) throws -> EKCalendar {
        if let name { return try list(named: name) }
        guard let d = defaultList() else { throw RemindError.noDefaultList }
        return d
    }

    // MARK: - Fetching

    /// EventKit exposes reminder fetching only asynchronously via a completion handler.
    func fetch(in calendars: [EKCalendar]?, includeCompleted: Bool, onlyCompleted: Bool) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: calendars)
        let items: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found ?? [])
            }
        }
        return items.filter { r in
            if onlyCompleted { return r.isCompleted }
            if includeCompleted { return true }
            return !r.isCompleted
        }
    }

    // MARK: - Identity

    /// A short, stable handle. Derived by hashing rather than slicing the raw
    /// identifier, whose format is undocumented and varies by OS version.
    static func shortID(_ r: EKReminder) -> String {
        shortID(for: r.calendarItemIdentifier)
    }

    static func shortID(for identifier: String) -> String {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return digest.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves a user-supplied reference: a list index from the previous run,
    /// a short id, a full calendar item identifier, or a unique title substring.
    func resolve(_ ref: String, among pool: [EKReminder]) throws -> EKReminder {
        // 1..999 means "the Nth row of the last `remind list`".
        if ref.count <= 3, let idx = Int(ref), idx > 0 {
            if let identifier = IndexCache.load().element(at: idx - 1) {
                if let hit = pool.first(where: { $0.calendarItemIdentifier == identifier }) { return hit }
                if let hit = store.calendarItem(withIdentifier: identifier) as? EKReminder { return hit }
            }
            throw RemindError.notFound("#\(idx) — run `remind list` first to number the rows")
        }

        let lower = ref.lowercased()
        if let hit = pool.first(where: { Reminders.shortID($0) == lower }) { return hit }
        if let hit = pool.first(where: { $0.calendarItemIdentifier == ref }) { return hit }
        if let hit = store.calendarItem(withIdentifier: ref) as? EKReminder { return hit }

        let byTitle = pool.filter { ($0.title ?? "").lowercased().contains(lower) }
        if byTitle.count == 1 { return byTitle[0] }
        if byTitle.count > 1 { throw RemindError.ambiguous(ref, byTitle) }
        throw RemindError.notFound(ref)
    }

    // MARK: - Mutation

    func save(_ reminder: EKReminder) throws {
        try store.save(reminder, commit: true)
    }

    func remove(_ reminder: EKReminder) throws {
        try store.remove(reminder, commit: true)
    }
}

// MARK: - Due dates and alarms

extension EKReminder {
    /// A due date alone never notifies — Reminders fires only on an alarm.
    func setDue(_ parsed: ParsedDate?, attachAlarm: Bool) {
        // Drop only the absolute-date alarms this tool manages. Location alarms
        // and relative offsets set in Reminders.app are left alone.
        for alarm in alarms ?? [] where alarm.absoluteDate != nil {
            removeAlarm(alarm)
        }

        guard let parsed else {
            dueDateComponents = nil
            return
        }

        let cal = Calendar.current
        let fields: Set<Calendar.Component> = parsed.hasTime
            ? [.year, .month, .day, .hour, .minute, .second, .timeZone]
            : [.year, .month, .day]
        dueDateComponents = cal.dateComponents(fields, from: parsed.date)

        if attachAlarm {
            // All-day reminders get a 9am nudge; timed ones fire at the due moment.
            let fireDate = parsed.hasTime
                ? parsed.date
                : cal.date(bySettingHour: 9, minute: 0, second: 0, of: parsed.date) ?? parsed.date
            addAlarm(EKAlarm(absoluteDate: fireDate))
        }
    }

    var dueDate: Date? {
        guard let c = dueDateComponents else { return nil }
        return Calendar.current.date(from: c)
    }

    var isAllDay: Bool {
        guard let c = dueDateComponents else { return false }
        return c.hour == nil
    }

    var priorityLabel: String? {
        switch priority {
        case 1...4: return "high"
        case 5: return "medium"
        case 6...9: return "low"
        default: return nil
        }
    }
}

enum Priority {
    static func value(_ raw: String) -> Int? {
        switch raw.lowercased() {
        case "high", "h", "1": return 1
        case "medium", "med", "m", "5": return 5
        case "low", "l", "9": return 9
        case "none", "0", "": return 0
        default: return nil
        }
    }
}

// MARK: - Row-number cache

/// Remembers the identifiers printed by the last `remind list` so the user can
/// say `remind done 3`. Row numbers are never used as durable identity.
enum IndexCache {
    private static var url: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/remind", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("last-list.json")
    }

    static func save(_ reminders: [EKReminder]) {
        let ids = reminders.map { $0.calendarItemIdentifier }
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> [String] {
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }
}

extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
