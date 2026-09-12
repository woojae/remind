import Foundation

/// A parsed due date. `hasTime` distinguishes an all-day reminder ("tomorrow")
/// from a timed one ("tomorrow 9am") — Reminders treats those very differently.
struct ParsedDate {
    var date: Date
    var hasTime: Bool
}

enum DateParse {

    // MARK: - Entry point

    /// `useDetector: false` restricts parsing to the explicit grammar above,
    /// skipping the fuzzy system detector. Callers that pull a date out of
    /// free text (the app's quick-add field) use it to avoid false positives.
    static func parse(_ raw: String, now: Date = Date(), useDetector: Bool = true) -> ParsedDate? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let lower = input.lowercased()

        if let p = explicit(lower, now: now) { return p }
        if let p = relative(lower, now: now) { return p }
        if useDetector, let p = detector(input, now: now) { return p }
        return nil
    }

    // MARK: - Time-of-day extraction

    private static let timeRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(\d{1,2}):(\d{2})\b|\b(noon|midnight)\b"#,
        options: [.caseInsensitive])

    /// Pulls a time-of-day out of `s`, returning the remaining text.
    private static func extractTime(_ s: String) -> (rest: String, hour: Int, minute: Int)? {
        let range = NSRange(s.startIndex..., in: s)
        guard let m = timeRegex.firstMatch(in: s, range: range) else { return nil }

        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            return String(s[r])
        }

        var hour = 0
        var minute = 0

        if let h = group(1) {                       // 9am / 3:30pm
            hour = Int(h) ?? 0
            minute = Int(group(2) ?? "0") ?? 0
            let ampm = (group(3) ?? "").lowercased()
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
        } else if let h = group(4) {                // 17:30
            hour = Int(h) ?? 0
            minute = Int(group(5) ?? "0") ?? 0
        } else if let word = group(6) {             // noon / midnight
            hour = word.lowercased() == "noon" ? 12 : 0
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        var rest = s
        if let r = Range(m.range, in: s) { rest.removeSubrange(r) }
        rest = rest.replacingOccurrences(of: " at ", with: " ")
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.hasSuffix(" at") { rest = String(rest.dropLast(3)).trimmingCharacters(in: .whitespaces) }
        return (rest, hour, minute)
    }

    private static func apply(hour: Int, minute: Int, to day: Date, cal: Calendar) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // MARK: - Explicit calendar formats

    private static let explicitFormats: [(format: String, hasTime: Bool, hasYear: Bool)] = [
        ("yyyy-MM-dd'T'HH:mm:ss", true,  true),
        ("yyyy-MM-dd'T'HH:mm",    true,  true),
        ("yyyy-MM-dd HH:mm:ss",   true,  true),
        ("yyyy-MM-dd HH:mm",      true,  true),
        ("yyyy-MM-dd",            false, true),
        ("yyyy/MM/dd HH:mm",      true,  true),
        ("yyyy/MM/dd",            false, true),
        ("MM/dd/yyyy HH:mm",      true,  true),
        ("MM/dd/yyyy",            false, true),
        ("MM-dd-yyyy",            false, true),
        ("MMM d yyyy",            false, true),
        ("MMMM d yyyy",           false, true),
        ("MM/dd",                 false, false),
        ("MMM d",                 false, false),
        ("MMMM d",                false, false),
    ]

    private static func explicit(_ s: String, now: Date) -> ParsedDate? {
        let cal = Calendar.current
        // Split a trailing time off so "2026-09-01 3pm" also works.
        let (body, hour, minute): (String, Int?, Int?) = {
            if let t = extractTime(s), !t.rest.isEmpty { return (t.rest, t.hour, t.minute) }
            return (s, nil, nil)
        }()
        let candidate = body.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty else { return nil }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = cal
        df.timeZone = cal.timeZone

        for spec in explicitFormats {
            df.dateFormat = spec.format
            guard var d = df.date(from: candidate) else { continue }

            if !spec.hasYear {
                // Year-less input means "the next such date".
                var c = cal.dateComponents([.month, .day], from: d)
                c.year = cal.component(.year, from: now)
                d = cal.date(from: c) ?? d
                if d < cal.startOfDay(for: now).addingTimeInterval(-86_400) {
                    c.year = (c.year ?? 0) + 1
                    d = cal.date(from: c) ?? d
                }
            }

            if let h = hour, let m = minute {
                return ParsedDate(date: apply(hour: h, minute: m, to: d, cal: cal), hasTime: true)
            }
            return ParsedDate(date: spec.hasTime ? d : cal.startOfDay(for: d), hasTime: spec.hasTime)
        }
        return nil
    }

    // MARK: - Relative expressions

    private static let weekdays: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
    ]

    private static let offsetRegex = try! NSRegularExpression(
        pattern: #"^(?:in\s+|\+)?(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|wks?|w|months?|mo)$"#,
        options: [.caseInsensitive])

    private static func relative(_ s: String, now: Date) -> ParsedDate? {
        let cal = Calendar.current
        var body = s
        var hour: Int?
        var minute: Int?
        if let t = extractTime(s) {
            body = t.rest
            hour = t.hour
            minute = t.minute
        }
        body = body.trimmingCharacters(in: .whitespaces)

        func finish(day: Date, defaultAllDay: Bool) -> ParsedDate {
            if let h = hour, let m = minute {
                return ParsedDate(date: apply(hour: h, minute: m, to: day, cal: cal), hasTime: true)
            }
            return ParsedDate(date: defaultAllDay ? cal.startOfDay(for: day) : day, hasTime: !defaultAllDay)
        }

        let today = cal.startOfDay(for: now)

        // Bare time: "9am" -> today, or tomorrow if that moment already passed.
        if body.isEmpty, let h = hour, let m = minute {
            var d = apply(hour: h, minute: m, to: today, cal: cal)
            if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return ParsedDate(date: d, hasTime: true)
        }

        switch body {
        case "now":
            return ParsedDate(date: now, hasTime: true)
        case "today", "tod":
            return finish(day: today, defaultAllDay: true)
        case "tomorrow", "tmr", "tmrw", "tom":
            return finish(day: cal.date(byAdding: .day, value: 1, to: today)!, defaultAllDay: true)
        case "yesterday":
            return finish(day: cal.date(byAdding: .day, value: -1, to: today)!, defaultAllDay: true)
        case "next week":
            return finish(day: cal.date(byAdding: .day, value: 7, to: today)!, defaultAllDay: true)
        case "next month":
            return finish(day: cal.date(byAdding: .month, value: 1, to: today)!, defaultAllDay: true)
        default:
            break
        }

        // "monday", "next friday", "this tue"
        var dayWord = body
        for prefix in ["next ", "this ", "on ", "coming "] where dayWord.hasPrefix(prefix) {
            dayWord = String(dayWord.dropFirst(prefix.count))
        }
        if let target = weekdays[dayWord] {
            let current = cal.component(.weekday, from: today)
            var delta = (target - current + 7) % 7
            if delta == 0 { delta = 7 }                 // "monday" on a Monday means the coming Monday
            return finish(day: cal.date(byAdding: .day, value: delta, to: today)!, defaultAllDay: true)
        }

        // "in 3 days", "+2w", "45m"
        let range = NSRange(body.startIndex..., in: body)
        if let m = offsetRegex.firstMatch(in: body, range: range),
           let numRange = Range(m.range(at: 1), in: body),
           let unitRange = Range(m.range(at: 2), in: body),
           let n = Int(body[numRange]) {
            let unit = String(body[unitRange])
            switch unit {
            case "m", "min", "mins", "minute", "minutes":
                return ParsedDate(date: cal.date(byAdding: .minute, value: n, to: now)!, hasTime: true)
            case "h", "hr", "hrs", "hour", "hours":
                return ParsedDate(date: cal.date(byAdding: .hour, value: n, to: now)!, hasTime: true)
            case "d", "day", "days":
                return finish(day: cal.date(byAdding: .day, value: n, to: today)!, defaultAllDay: true)
            case "w", "wk", "wks", "week", "weeks":
                return finish(day: cal.date(byAdding: .day, value: n * 7, to: today)!, defaultAllDay: true)
            case "mo", "month", "months":
                return finish(day: cal.date(byAdding: .month, value: n, to: today)!, defaultAllDay: true)
            default:
                return nil
            }
        }

        return nil
    }

    // MARK: - Fallback: system natural-language detector

    private static func detector(_ s: String, now: Date) -> ParsedDate? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = d.firstMatch(in: s, range: range), let date = m.date else { return nil }
        // The detector gives no all-day signal, so infer it from the input text.
        let hasTime = extractTime(s.lowercased()) != nil
        return ParsedDate(date: hasTime ? date : Calendar.current.startOfDay(for: date), hasTime: hasTime)
    }
}
