import Foundation

enum Help {
    static func text(for topic: String?) -> String {
        switch topic {
        case "add": return addHelp
        case "list", "ls": return listHelp
        case "edit": return editHelp
        case "snooze": return snoozeHelp
        case "date", "dates", "due": return dateHelp
        default: return general
        }
    }

    static let general = """
    \(Style.bold("remind")) — Apple Reminders from the command line

    \(Style.bold("USAGE"))
      remind <command> [arguments] [options]

    \(Style.bold("COMMANDS"))
      list [query]        Show reminders (default: open ones, soonest first)
      lists               Show your reminder lists and open counts
      add <title>         Create a reminder
      done <ref>...       Mark reminders complete
      undone <ref>...     Reopen completed reminders
      edit <ref>          Change a reminder's fields
      snooze <ref> [rung] Push a reminder along the snooze ladder
      show <ref>          Print everything about one reminder
      delete <ref>...     Delete reminders (asks first, unless --force)
      auth                Check or request Reminders access
      help [topic]        Topics: add, list, edit, snooze, dates

    \(Style.bold("REFERRING TO A REMINDER"))
      A <ref> is any of:
        3            the row number from your last `remind list`
        a1b2c3       the short id shown in the list
        "dentist"    a unique substring of the title

    \(Style.bold("EXAMPLES"))
      remind add "Buy milk" --due "tomorrow 9am"
      remind list --today
      remind list --list Work --json
      remind done 3
      remind edit dentist --due friday --priority high
      remind snooze dentist 1h
      remind delete 2 --force

    \(Style.bold("GLOBAL OPTIONS"))
      --json      Machine-readable output
      --quiet     Suppress success output
      --help      This message

    Run `remind auth` first, from your terminal app, to grant Reminders access.
    """

    static let addHelp = """
    \(Style.bold("remind add")) <title> [options]

      -l, --list NAME      Target list (default: your default Reminders list)
      -d, --due WHEN       Due date — see `remind help dates`
      -n, --notes TEXT     Attach notes
      -p, --priority P     high | medium | low | none
          --url URL        Attach a URL
          --remind-at WHEN Alarm at a specific moment (instead of at the due time;
                           becomes the due date if --due is omitted)
          --no-alarm       Set the due date without a notification
      -j, --json           Print the created reminder as JSON

    A due date on its own does not notify you — remind attaches an alarm
    automatically (at the due time, or 9am for all-day reminders). Use
    --no-alarm to opt out.

    \(Style.bold("EXAMPLES"))
      remind add "Call the vet" --due "friday 2pm" --list Personal
      remind add "File taxes" --due 2026-04-15 --priority high
      remind add "Water plants" --due +3d --no-alarm
    """

    static let listHelp = """
    \(Style.bold("remind list")) [query] [options]

      -l, --list NAME   Only this list
      -a, --all         Include completed reminders
          --completed   Only completed reminders
          --overdue     Only reminders past due
          --today       Due today or earlier
          --week        Due within seven days
          --no-due      Only reminders with no due date
          --sort KEY    due (default) | title | priority | created
          --limit N     Cap the number of rows
      -j, --json        Machine-readable output

    A bare query filters by title substring: `remind list milk`.
    Rows are numbered; those numbers stay valid for `done`/`edit`/`delete`
    until the next `remind list`.
    """

    static let editHelp = """
    \(Style.bold("remind edit")) <ref> [options]

      -t, --title TEXT   Rename
      -d, --due WHEN     Change the due date (re-attaches an alarm)
          --no-due       Clear the due date and alarm
      -n, --notes TEXT   Replace notes (pass "" to clear)
      -p, --priority P   high | medium | low | none
          --url URL      Replace the URL
          --move NAME    Move to another list
          --remind-at W  Set the alarm moment
          --no-alarm     Set the due date without a notification

    \(Style.bold("EXAMPLES"))
      remind edit 4 --due "next monday 8am"
      remind edit dentist --move Personal --priority high
    """

    static let snoozeHelp = """
    \(Style.bold("remind snooze")) <ref> [rung] [options]

      Pushes a reminder along the same ladder Remind.app uses:

        1  10m       10 minutes          6  9h        9 hours
        2  30m       30 minutes          7  morning   next morning
        3  1h        1 hour              8  3d        in 3 days, morning
        4  3h        3 hours             9  week      next week, morning
        5  6h        6 hours

      With no rung, the suggested one is used: it climbs one step each time
      the same reminder is snoozed, exactly as the app's starred option does.

          --until WHEN  Any moment instead of a rung — see `remind help dates`
      -j, --json        Print the updated reminder as JSON

    The snooze is recorded in the app's nag state, so Remind.app stops
    announcing the task and its own suggested rung moves up.

    \(Style.bold("EXAMPLES"))
      remind snooze 3
      remind snooze dentist 1h
      remind snooze "file taxes" morning
      remind snooze 2 --until "friday 2pm"
    """

    static let dateHelp = """
    \(Style.bold("Date formats accepted by --due"))

      Relative     today, tomorrow, yesterday, next week, next month
      Weekdays     monday, fri, next thursday
      Offsets      +3d, +2w, in 4 hours, 45m, in 2 months
      Times        9am, 3:30pm, 17:00, noon, midnight
      Combined     "tomorrow 9am", "friday 2pm", "next monday 08:30"
      Calendar     2026-09-01, 2026-09-01 14:30, 9/1, Sep 1, 09/01/2026

    A date without a time creates an all-day reminder; adding a time creates
    a timed one. Anything unrecognized falls back to the macOS natural-language
    date detector, so phrases like "the 3rd of September" usually work too.
    """
}
