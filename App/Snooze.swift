import Foundation

/// A concrete snooze choice: a label and the moment it lands on.
struct SnoozeOption: Identifiable, Hashable {
    let step: Int
    let label: String
    let date: Date
    var id: Int { step }
}

/// The snooze ladder. Each time a task is snoozed, the suggested rung moves
/// one further out — a task you've pushed away five times probably shouldn't
/// be offered "10 minutes" again.
enum Snooze {
    /// Short titles used in notification action buttons, one per rung.
    static let actionTitles = [
        "Snooze 10 min", "Snooze 30 min", "Snooze 1 hour", "Snooze 3 hours",
        "Snooze until tomorrow", "Snooze 3 days", "Snooze a week",
    ]
    static var rungs: Int { actionTitles.count }

    static func suggestedStep(snoozeCount: Int) -> Int {
        min(max(snoozeCount, 0), rungs - 1)
    }

    static func options(now: Date = Date(), morningHour: Int = Prefs.morningHour) -> [SnoozeOption] {
        let cal = Calendar.current
        let morning = nextMorning(after: now, hour: morningHour, cal: cal)
        let isToday = cal.isDate(morning, inSameDayAs: now)
        func plusMorning(days: Int) -> Date {
            let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: now))!
            return cal.date(bySettingHour: morningHour, minute: 0, second: 0, of: day)!
        }
        return [
            SnoozeOption(step: 0, label: "10 minutes", date: now.addingTimeInterval(10 * 60)),
            SnoozeOption(step: 1, label: "30 minutes", date: now.addingTimeInterval(30 * 60)),
            SnoozeOption(step: 2, label: "1 hour", date: now.addingTimeInterval(60 * 60)),
            SnoozeOption(step: 3, label: "3 hours", date: now.addingTimeInterval(3 * 60 * 60)),
            SnoozeOption(step: 4, label: isToday ? "This morning" : "Tomorrow morning", date: morning),
            SnoozeOption(step: 5, label: "In 3 days", date: plusMorning(days: 3)),
            SnoozeOption(step: 6, label: "Next week", date: plusMorning(days: 7)),
        ]
    }

    /// The next `hour`:00 that is at least an hour away.
    static func nextMorning(after now: Date, hour: Int, cal: Calendar = .current) -> Date {
        let today = cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.startOfDay(for: now))!
        if today.timeIntervalSince(now) >= 60 * 60 { return today }
        return cal.date(byAdding: .day, value: 1, to: today)!
    }
}

/// Per-task nag bookkeeping that doesn't belong in the Reminders database:
/// when we last notified, and how many times the task has been snoozed.
struct NagState: Codable {
    var lastNotified: [String: Date] = [:]
    var snoozeCount: [String: Int] = [:]
    var lastDelivery: Date?

    mutating func prune(keeping ids: Set<String>) {
        lastNotified = lastNotified.filter { ids.contains($0.key) }
        snoozeCount = snoozeCount.filter { ids.contains($0.key) }
    }

    mutating func forget(_ id: String) {
        lastNotified[id] = nil
        snoozeCount[id] = nil
    }
}

enum StateFile {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Remind", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }

    static func load() -> NagState {
        guard let data = try? Data(contentsOf: url) else { return NagState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NagState.self, from: data)) ?? NagState()
    }

    static func save(_ state: NagState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
