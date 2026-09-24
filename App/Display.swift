import Foundation

/// Human phrasing for due dates. Deliberately never says "overdue".
enum Display {
    /// DateFormatter is expensive to create and these run once per row per
    /// render, so keep one instance per format. All callers are on the main
    /// actor.
    private static var formatters: [String: DateFormatter] = [:]
    private static func formatter(_ format: String, posix: Bool = false) -> DateFormatter {
        let key = posix ? "posix:" + format : format
        if let df = formatters[key] { return df }
        let df = DateFormatter()
        df.locale = posix ? Locale(identifier: "en_US_POSIX") : .current
        df.dateFormat = format
        formatters[key] = df
        return df
    }

    static func time(_ date: Date) -> String {
        formatter(Calendar.current.component(.minute, from: date) == 0 ? "h a" : "h:mm a").string(from: date)
    }

    /// "Today", "Tomorrow", "Friday", "Sep 20", "Sep 20, 2027".
    static func day(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let delta = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6:
            return formatter("EEEE").string(from: date)
        default:
            let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
            return formatter(sameYear ? "MMM d" : "MMM d, yyyy").string(from: date)
        }
    }

    /// Label for a task's row. Due-now tasks read "Since …"; future ones read
    /// as a plain moment.
    static func when(_ item: TaskItem, now: Date) -> String {
        guard let due = item.due else { return "Now" }
        let cal = Calendar.current
        let sameDay = cal.isDate(due, inSameDayAs: now)
        let dayText = day(due, now: now)

        if due <= now {
            if item.isAllDay { return sameDay ? "Today" : "Since \(dayText.lowercasedFirst)" }
            if now.timeIntervalSince(due) < 60 { return "Now" }
            return sameDay ? "Since \(time(due))" : "Since \(dayText.lowercasedFirst) \(time(due))"
        }
        if item.isAllDay { return dayText }
        return sameDay ? time(due) : "\(dayText) \(time(due))"
    }

    /// Absolute form for the editor field, in a format DateParse accepts back.
    static func editable(_ item: TaskItem) -> String {
        guard let due = item.due else { return "" }
        return formatter(item.isAllDay ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm", posix: true).string(from: due)
    }

    static func preview(_ parsed: ParsedDate?, now: Date) -> String {
        guard let parsed else { return "Now" }
        let d = day(parsed.date, now: now)
        return parsed.hasTime ? "\(d) \(time(parsed.date))" : d
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first = first else { return self }
        return first.lowercased() + dropFirst()
    }
}
