import EventKit
import Foundation

enum Style {
    static let enabled = isatty(fileno(stdout)) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func wrap(_ s: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }

    static func dim(_ s: String) -> String { wrap(s, "2") }
    static func bold(_ s: String) -> String { wrap(s, "1") }
    static func red(_ s: String) -> String { wrap(s, "31") }
    static func yellow(_ s: String) -> String { wrap(s, "33") }
    static func green(_ s: String) -> String { wrap(s, "32") }
    static func cyan(_ s: String) -> String { wrap(s, "36") }
}

enum Format {

    // MARK: - Dates

    static func due(_ r: EKReminder, now: Date = Date()) -> String {
        guard let date = r.dueDate else { return "" }
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let today = cal.startOfDay(for: now)
        let dayDelta = cal.dateComponents([.day], from: today, to: day).day ?? 0

        let df = DateFormatter()
        df.locale = .current

        var label: String
        switch dayDelta {
        case 0: label = "today"
        case 1: label = "tomorrow"
        case -1: label = "yesterday"
        case 2...6:
            df.dateFormat = "EEE"
            label = df.string(from: date)
        default:
            df.dateFormat = cal.component(.year, from: date) == cal.component(.year, from: now) ? "MMM d" : "MMM d yyyy"
            label = df.string(from: date)
        }

        if !r.isAllDay {
            df.dateFormat = cal.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
            label += " " + df.string(from: date).lowercased()
        }
        return label
    }

    static func isOverdue(_ r: EKReminder, now: Date = Date()) -> Bool {
        guard !r.isCompleted, let date = r.dueDate else { return false }
        if r.isAllDay {
            return date < Calendar.current.startOfDay(for: now)
        }
        return date < now
    }

    static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Table

    static func table(_ reminders: [EKReminder], showList: Bool, now: Date = Date()) -> String {
        guard !reminders.isEmpty else { return Style.dim("No reminders.") }

        var rows: [[String]] = []
        for (i, r) in reminders.enumerated() {
            let mark = r.isCompleted ? Style.green("✓") : " "
            let dueText = due(r, now: now)
            let dueCell = isOverdue(r, now: now) ? Style.red(dueText) : Style.yellow(dueText)
            var title = r.title ?? "(untitled)"
            if r.isCompleted { title = Style.dim(title) }
            if let p = r.priorityLabel {
                let tag = p == "high" ? Style.red("!") : (p == "medium" ? Style.yellow("!") : Style.dim("!"))
                title = tag + " " + title
            }
            var row = [Style.dim(String(i + 1)), mark, Style.dim(Reminders.shortID(r)), title, dueCell]
            if showList { row.append(Style.cyan(r.calendar?.title ?? "")) }
            rows.append(row)
        }

        let widths = columnWidths(rows)
        return rows.map { row in
            row.enumerated()
                .map { idx, cell in idx == row.count - 1 ? cell : pad(cell, to: widths[idx]) }
                .joined(separator: "  ")
                .trimmingTrailingSpaces()
        }.joined(separator: "\n")
    }

    static func detail(_ r: EKReminder) -> String {
        var lines: [String] = []
        lines.append(Style.bold(r.title ?? "(untitled)"))
        lines.append("  id        \(Reminders.shortID(r))  \(Style.dim(r.calendarItemIdentifier))")
        lines.append("  list      \(r.calendar?.title ?? "")")
        lines.append("  status    \(r.isCompleted ? "completed" : "open")")
        if let d = r.dueDate {
            let suffix = r.isAllDay ? " (all day)" : ""
            lines.append("  due       \(due(r))\(suffix)  \(Style.dim(iso(d) ?? ""))")
        }
        if let p = r.priorityLabel { lines.append("  priority  \(p)") }
        if let alarms = r.alarms, !alarms.isEmpty {
            let stamps = alarms.compactMap { iso($0.absoluteDate) }.joined(separator: ", ")
            lines.append("  alarm     \(stamps.isEmpty ? "relative" : stamps)")
        }
        if let url = r.url { lines.append("  url       \(url.absoluteString)") }
        if let notes = r.notes, !notes.isEmpty {
            lines.append("  notes     " + notes.replacingOccurrences(of: "\n", with: "\n            "))
        }
        if let c = r.completionDate { lines.append("  done at   \(iso(c) ?? "")") }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    static func json(_ reminders: [EKReminder]) -> String {
        let payload = reminders.map { dictionary(for: $0) }
        return encode(payload)
    }

    static func dictionary(for r: EKReminder) -> [String: Any] {
        var d: [String: Any] = [
            "id": Reminders.shortID(r),
            "identifier": r.calendarItemIdentifier,
            "title": r.title ?? "",
            "list": r.calendar?.title ?? "",
            "completed": r.isCompleted,
            "allDay": r.isAllDay,
            "overdue": isOverdue(r),
        ]
        if let due = iso(r.dueDate) { d["due"] = due }
        if let p = r.priorityLabel { d["priority"] = p }
        if let notes = r.notes, !notes.isEmpty { d["notes"] = notes }
        if let url = r.url { d["url"] = url.absoluteString }
        if let c = iso(r.completionDate) { d["completedAt"] = c }
        return d
    }

    static func encode(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    // MARK: - Layout helpers

    private static func columnWidths(_ rows: [[String]]) -> [Int] {
        let count = rows.map(\.count).max() ?? 0
        return (0..<count).map { i in
            rows.compactMap { $0.element(at: i).map(visibleWidth) }.max() ?? 0
        }
    }

    /// Width ignoring ANSI escapes, so colored cells still line up.
    private static func visibleWidth(_ s: String) -> Int {
        stripped(s).count
    }

    private static func stripped(_ s: String) -> String {
        var out = ""
        var inEscape = false
        for ch in s {
            if inEscape {
                if ch == "m" { inEscape = false }
            } else if ch == "\u{1B}" {
                inEscape = true
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static func pad(_ s: String, to width: Int) -> String {
        let deficit = width - visibleWidth(s)
        return deficit > 0 ? s + String(repeating: " ", count: deficit) : s
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        var s = self
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
}
