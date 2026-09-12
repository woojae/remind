import Foundation

/// Human phrasing for due dates. Deliberately never says "overdue".
enum Display {
    static func time(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = Calendar.current.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        return df.string(from: date)
    }

    /// "Today", "Tomorrow", "Friday", "Sep 20", "Sep 20, 2027".
    static func day(_ date: Date, now: Date) -> String {
        let cal = Calendar.current
        let delta = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        let df = DateFormatter()
        df.locale = .current
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6:
            df.dateFormat = "EEEE"
            return df.string(from: date)
        default:
            df.dateFormat = cal.component(.year, from: date) == cal.component(.year, from: now) ? "MMM d" : "MMM d, yyyy"
            return df.string(from: date)
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
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = item.isAllDay ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        return df.string(from: due)
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
