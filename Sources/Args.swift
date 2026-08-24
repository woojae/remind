import Foundation

/// Minimal option parser. Options that take a value are declared explicitly so
/// `remind list --json overdue` can never mistake a positional for an argument.
struct Args {
    static let valueOptions: Set<String> = [
        "list", "due", "notes", "priority", "title", "url", "move", "limit", "sort", "remind-at",
    ]
    static let boolOptions: Set<String> = [
        "json", "all", "completed", "done", "force", "no-alarm", "help", "overdue",
        "today", "week", "no-due", "quiet",
    ]
    static let aliases: [String: String] = [
        "l": "list", "d": "due", "n": "notes", "p": "priority", "t": "title",
        "a": "all", "j": "json", "f": "force", "h": "help",
    ]

    var command: String
    var positionals: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    subscript(_ key: String) -> String? { values[key] }
    func has(_ key: String) -> Bool { flags.contains(key) }

    static func parse(_ argv: [String]) throws -> Args {
        var argv = argv
        let command = argv.isEmpty ? "help" : argv.removeFirst()
        var args = Args(command: command)
        var passthrough = false

        var i = 0
        while i < argv.count {
            let token = argv[i]
            i += 1

            if passthrough { args.positionals.append(token); continue }
            if token == "--" { passthrough = true; continue }

            guard token.hasPrefix("-"), token != "-" else {
                args.positionals.append(token)
                continue
            }

            var name = String(token.drop(while: { $0 == "-" }))
            var inlineValue: String?
            if let eq = name.firstIndex(of: "=") {
                inlineValue = String(name[name.index(after: eq)...])
                name = String(name[..<eq])
            }
            if let full = aliases[name] { name = full }

            if valueOptions.contains(name) {
                if let v = inlineValue {
                    args.values[name] = v
                } else if i < argv.count, !argv[i].hasPrefix("--") {
                    args.values[name] = argv[i]
                    i += 1
                } else {
                    throw RemindError.usage("Option --\(name) needs a value.")
                }
            } else if boolOptions.contains(name) {
                args.flags.insert(name)
            } else {
                throw RemindError.usage("Unknown option '\(token)'. Try `remind help`.")
            }
        }
        return args
    }
}
