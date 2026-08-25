import EventKit
import Foundation

@main
struct Remind {
    static func main() async {
        let argv = Array(CommandLine.arguments.dropFirst())
        do {
            try await run(argv)
        } catch let error as RemindError {
            FileHandle.standardError.write(Data(("remind: " + error.description + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("remind: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run(_ argv: [String]) async throws {
        let args = try Args.parse(argv)
        if args.has("help") || args.command == "help" || args.command == "--help" {
            print(Help.text(for: args.positionals.first))
            return
        }

        let app = Reminders()

        switch args.command {
        case "", "list", "ls", "show-all":
            try await Commands.list(app, args)
        case "auth":
            try await Commands.auth(app, args)
        case "lists", "l":
            try await Commands.lists(app, args)
        case "add", "a", "new":
            try await Commands.add(app, args)
        case "done", "complete", "check", "x":
            try await Commands.done(app, args, completed: true)
        case "undone", "uncomplete", "reopen":
            try await Commands.done(app, args, completed: false)
        case "delete", "rm", "remove":
            try await Commands.delete(app, args)
        case "edit", "set", "update":
            try await Commands.edit(app, args)
        case "show", "info", "cat":
            try await Commands.show(app, args)
        case "version", "--version":
            print("remind 1.0.0")
        default:
            throw RemindError.usage("Unknown command '\(args.command)'. Try `remind help`.")
        }
    }
}

enum Commands {

    // MARK: - auth

    static func auth(_ app: Reminders, _ args: Args) async throws {
        let before = EKEventStore.authorizationStatus(for: .reminder)
        let after = try await app.requestAccess()

        let granted = after == .fullAccess
        if args.has("json") {
            print(Format.encode(["status": Auth.name(after), "granted": granted]))
            exit(granted ? 0 : 1)
        }

        print("Reminders access: \(Auth.name(after))")
        if granted {
            let count = app.lists().count
            print(Style.green("Granted.") + " \(count) list\(count == 1 ? "" : "s") visible.")
            return
        }
        if before == after && before == .notDetermined {
            print(Style.yellow("No permission dialog appeared."))
        }
        print("")
        print(Auth.remedy(after))
        exit(1)
    }

    // MARK: - lists

    static func lists(_ app: Reminders, _ args: Args) async throws {
        try await app.requireAccess()
        let all = app.lists()
        let defaultID = app.defaultList()?.calendarIdentifier

        if args.has("json") {
            print(Format.encode(all.map { c -> [String: Any] in
                ["name": c.title, "identifier": c.calendarIdentifier, "default": c.calendarIdentifier == defaultID]
            }))
            return
        }

        guard !all.isEmpty else { print(Style.dim("No reminder lists.")); return }

        let open = await app.fetch(in: nil, includeCompleted: false, onlyCompleted: false)
        var counts: [String: Int] = [:]
        for r in open {
            guard let id = r.calendar?.calendarIdentifier else { continue }
            counts[id, default: 0] += 1
        }

        let width = all.map(\.title.count).max() ?? 0
        for c in all {
            let marker = c.calendarIdentifier == defaultID ? Style.green("*") : " "
            let name = c.title.padding(toLength: max(width, c.title.count), withPad: " ", startingAt: 0)
            let n = counts[c.calendarIdentifier] ?? 0
            print("\(marker) \(name)  \(Style.dim("\(n) open"))")
        }
    }

    // MARK: - list

    static func list(_ app: Reminders, _ args: Args) async throws {
        try await app.requireAccess()

        let calendars: [EKCalendar]? = try args["list"].map { [try app.list(named: $0)] }
        let onlyCompleted = args.has("completed") || args.has("done")
        var items = await app.fetch(
            in: calendars,
            includeCompleted: args.has("all"),
            onlyCompleted: onlyCompleted)

        // Free-text positionals filter by title, so `remind list groceries` works.
        let query = args.positionals.joined(separator: " ").lowercased()
        if !query.isEmpty {
            items = items.filter { ($0.title ?? "").lowercased().contains(query) }
        }

        let now = Date()
        let cal = Calendar.current
        if args.has("overdue") {
            items = items.filter { Format.isOverdue($0, now: now) }
        } else if args.has("today") {
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            items = items.filter { r in
                guard let d = r.dueDate else { return false }
                return d < end
            }
        } else if args.has("week") {
            let end = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
            items = items.filter { r in
                guard let d = r.dueDate else { return false }
                return d < end
            }
        }
        if args.has("no-due") {
            items = items.filter { $0.dueDate == nil }
        }

        items = sort(items, by: args["sort"] ?? "due")
        if let limit = args["limit"].flatMap(Int.init), limit > 0 {
            items = Array(items.prefix(limit))
        }

        IndexCache.save(items)

        if args.has("json") {
            print(Format.json(items))
            return
        }
        print(Format.table(items, showList: calendars == nil))
    }

    private static func sort(_ items: [EKReminder], by key: String) -> [EKReminder] {
        switch key {
        case "title":
            return items.sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
        case "priority":
            return items.sorted { lhs, rhs in
                let l = lhs.priority == 0 ? 10 : lhs.priority
                let r = rhs.priority == 0 ? 10 : rhs.priority
                return l == r ? dueBefore(lhs, rhs) : l < r
            }
        case "created":
            return items.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        default:
            // Due date ascending, undated last.
            return items.sorted(by: dueBefore)
        }
    }

    private static func dueBefore(_ a: EKReminder, _ b: EKReminder) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?): return x == y ? (a.title ?? "") < (b.title ?? "") : x < y
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return (a.title ?? "") < (b.title ?? "")
        }
    }

    // MARK: - add

    static func add(_ app: Reminders, _ args: Args) async throws {
        try await app.requireAccess()

        var title = args.positionals.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if let explicitTitle = args["title"] { title = explicitTitle }
        guard !title.isEmpty else {
            throw RemindError.usage("Nothing to add. Usage: remind add \"Buy milk\" --due tomorrow 9am")
        }

        let calendar = try app.resolveList(args["list"])
        let reminder = EKReminder(eventStore: app.store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = args["notes"]
        if let raw = args["url"], let url = URL(string: raw) { reminder.url = url }

        if let raw = args["priority"] {
            guard let p = Priority.value(raw) else {
                throw RemindError.usage("Priority must be high, medium, low, or none.")
            }
            reminder.priority = p
        }

        var customAlarm: ParsedDate?
        if let raw = args["remind-at"] {
            guard let parsed = DateParse.parse(raw) else { throw RemindError.badDate(raw) }
            customAlarm = parsed
        }

        if let raw = args["due"] {
            guard let parsed = DateParse.parse(raw) else { throw RemindError.badDate(raw) }
            // An explicit --remind-at replaces the alarm the due date would imply.
            reminder.setDue(parsed, attachAlarm: customAlarm == nil && !args.has("no-alarm"))
            if let alarm = customAlarm { reminder.addAlarm(EKAlarm(absoluteDate: alarm.date)) }
        } else if let alarm = customAlarm {
            // EventKit ignores alarms on an undated reminder, so the alarm
            // moment becomes the due date too.
            reminder.setDue(alarm, attachAlarm: true)
        }

        try app.save(reminder)

        if args.has("json") {
            print(Format.encode(Format.dictionary(for: reminder)))
        } else if !args.has("quiet") {
            var line = Style.green("added") + "  \(Reminders.shortID(reminder))  \(title)"
            let dueText = Format.due(reminder)
            if !dueText.isEmpty { line += "  " + Style.yellow(dueText) }
            line += "  " + Style.cyan(calendar.title)
            print(line)
        }
    }

    // MARK: - done / undone

    static func done(_ app: Reminders, _ args: Args, completed: Bool) async throws {
        try await app.requireAccess()
        guard !args.positionals.isEmpty else {
            throw RemindError.usage("Which reminder? Usage: remind \(completed ? "done" : "undone") <id|number|title>")
        }

        // Include completed items so `undone` can find them.
        let pool = await app.fetch(in: nil, includeCompleted: true, onlyCompleted: false)
        var changed: [EKReminder] = []

        for ref in args.positionals {
            let reminder = try app.resolve(ref, among: pool)
            reminder.isCompleted = completed
            try app.save(reminder)
            changed.append(reminder)
        }

        if args.has("json") {
            print(Format.json(changed))
        } else if !args.has("quiet") {
            for r in changed {
                let verb = completed ? Style.green("done") : Style.yellow("reopened")
                print("\(verb)  \(Reminders.shortID(r))  \(r.title ?? "")")
            }
        }
    }

    // MARK: - delete

    static func delete(_ app: Reminders, _ args: Args) async throws {
        try await app.requireAccess()
        guard !args.positionals.isEmpty else {
            throw RemindError.usage("Which reminder? Usage: remind delete <id|number|title> [--force]")
        }

        let pool = await app.fetch(in: nil, includeCompleted: true, onlyCompleted: false)
        let targets = try args.positionals.map { try app.resolve($0, among: pool) }

        // Deletion syncs to iCloud and is not undoable from here.
        if !args.has("force") {
            guard isatty(fileno(stdin)) == 1 else {
                throw RemindError.usage("Refusing to delete non-interactively without --force.")
            }
            print("Delete \(targets.count) reminder\(targets.count == 1 ? "" : "s"):")
            for r in targets { print("  \(Reminders.shortID(r))  \(r.title ?? "")") }
            print("This cannot be undone. Continue? [y/N] ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return
            }
        }

        let summaries = targets.map { Format.dictionary(for: $0) }
        for r in targets { try app.remove(r) }

        if args.has("json") {
            print(Format.encode(summaries))
        } else if !args.has("quiet") {
            for s in summaries {
                print("\(Style.red("deleted"))  \(s["id"] as? String ?? "")  \(s["title"] as? String ?? "")")
            }
        }
    }

    // MARK: - edit

    static func edit(_ app: Reminders, _ args: Args) async throws {
        try await app.requireAccess()
        guard let ref = args.positionals.first else {
            throw RemindError.usage("Which reminder? Usage: remind edit <id|number|title> --due friday")
        }

        let pool = await app.fetch(in: nil, includeCompleted: true, onlyCompleted: false)
        let reminder = try app.resolve(ref, among: pool)

        var touched = false
        if let title = args["title"] { reminder.title = title; touched = true }
        if let notes = args["notes"] { reminder.notes = notes.isEmpty ? nil : notes; touched = true }
        if let raw = args["url"] { reminder.url = raw.isEmpty ? nil : URL(string: raw); touched = true }
        if let raw = args["priority"] {
            guard let p = Priority.value(raw) else {
                throw RemindError.usage("Priority must be high, medium, low, or none.")
            }
            reminder.priority = p
            touched = true
        }
        if args.has("no-due") {
            reminder.setDue(nil, attachAlarm: false)
            touched = true
        } else if let raw = args["due"] {
            guard let parsed = DateParse.parse(raw) else { throw RemindError.badDate(raw) }
            reminder.setDue(parsed, attachAlarm: !args.has("no-alarm"))
            touched = true
        }
        if let raw = args["remind-at"] {
            guard let parsed = DateParse.parse(raw) else { throw RemindError.badDate(raw) }
            if reminder.dueDate == nil {
                reminder.setDue(parsed, attachAlarm: true)
            } else {
                for alarm in reminder.alarms ?? [] where alarm.absoluteDate != nil {
                    reminder.removeAlarm(alarm)
                }
                reminder.addAlarm(EKAlarm(absoluteDate: parsed.date))
            }
            touched = true
        }
        if let target = args["move"] {
            reminder.calendar = try app.list(named: target)
            touched = true
        }

        guard touched else {
            throw RemindError.usage("Nothing to change. Pass --title, --due, --no-due, --notes, --priority, --url, --remind-at, or --move.")
        }
        try app.save(reminder)

        if args.has("json") {
            print(Format.encode(Format.dictionary(for: reminder)))
        } else if !args.has("quiet") {
            print(Format.detail(reminder))
        }
    }

    // MARK: - show

    static func show(_ app: Reminders, _ args: Args) async throws {
        try await app.requireAccess()
        guard let ref = args.positionals.first else {
            throw RemindError.usage("Which reminder? Usage: remind show <id|number|title>")
        }
        let pool = await app.fetch(in: nil, includeCompleted: true, onlyCompleted: false)
        let reminder = try app.resolve(ref, among: pool)

        if args.has("json") {
            print(Format.encode(Format.dictionary(for: reminder)))
        } else {
            print(Format.detail(reminder))
        }
    }
}
