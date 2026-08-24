# remind

Apple Reminders from the command line. A single Swift binary talking to
EventKit directly — no AppleScript, no Reminders.app window, no dependencies.

```
$ remind add "Renew passport" --due "next friday 9am" --priority high
added  4f9a1c  Renew passport  Fri 9 am  Personal

$ remind list --week
1    a03e11  ! Renew passport      Fri 9 am     Personal
2    7c2d90    Standup notes       today 9 am   Work
3    1b8f45    Water the plants    Sun          Home

$ remind done 2
done  7c2d90  Standup notes
```

## Install

```bash
make install
```

Installs to `~/.local/bin/remind` (override with `PREFIX=/usr/local make install`).
Make sure that directory is on your `PATH`.

## Grant access

Run this once, **from your terminal app** (Terminal, iTerm, Ghostty, …):

```bash
remind auth
```

macOS shows the Reminders permission dialog only for a foreground terminal
session, and attributes it to the terminal app rather than to `remind` itself.
If no dialog appears, add your terminal under
**System Settings → Privacy & Security → Reminders**.

## Commands

| Command | What it does |
| --- | --- |
| `remind list [query]` | Open reminders, soonest first. A bare query filters by title. |
| `remind lists` | Your reminder lists, with open counts. `*` marks the default. |
| `remind add <title>` | Create a reminder. |
| `remind done <ref>…` | Mark complete. |
| `remind undone <ref>…` | Reopen. |
| `remind edit <ref>` | Change title, due date, notes, priority, URL, or list. |
| `remind show <ref>` | Everything about one reminder. |
| `remind delete <ref>…` | Delete. Confirms first unless `--force`. |
| `remind auth` | Check or request access. Exits non-zero if not granted. |
| `remind help [topic]` | Topics: `add`, `list`, `edit`, `dates`. |

### Referring to a reminder

A `<ref>` is any of:

- **`3`** — the row number from your last `remind list`
- **`a1b2c3`** — the short id shown in the list (stable, derived from the item's identifier)
- **`"dentist"`** — a unique substring of the title; ambiguous matches are listed rather than guessed

Row numbers are a convenience only. They are re-derived on every `remind list`
and are never used as durable identity — the short id and the full
`calendarItemIdentifier` are.

### Due dates

```
Relative     today, tomorrow, yesterday, next week, next month
Weekdays     monday, fri, next thursday
Offsets      +3d, +2w, in 4 hours, 45m, in 2 months
Times        9am, 3:30pm, 17:00, noon, midnight
Combined     "tomorrow 9am", "friday 2pm", "next monday 08:30"
Calendar     2026-09-01, 2026-09-01 14:30, 9/1, Sep 1, 09/01/2026
```

A date without a time creates an **all-day** reminder; adding a time creates a
**timed** one. Unrecognized input falls back to the macOS natural-language date
detector, so phrases like `"the 3rd of September"` usually work too.

**Due dates alone never notify you** — Reminders fires on alarms, not due dates.
`remind` attaches one automatically: at the due moment for timed reminders, at
9am for all-day ones. Pass `--no-alarm` to opt out, or `--remind-at WHEN` to add
an alarm at a different moment.

## Scripting

Every command takes `--json`:

```bash
remind list --overdue --json | jq -r '.[].title'
remind lists --json | jq -r '.[] | select(.default).name'
```

`--quiet` suppresses success output. Failures print to stderr and exit non-zero.
`remind delete` refuses to run non-interactively without `--force`.

## How it works

`Sources/` is five files:

- `Remind.swift` — entry point and command implementations
- `Store.swift` — EventKit wrapper, permissions, reference resolution
- `DateParse.swift` — the `--due` grammar
- `Format.swift` — table, detail, and JSON rendering
- `Args.swift` — option parsing
- `Help.swift` — help text

Two macOS details the `Makefile` handles, both of which break the binary if
skipped:

1. **EventKit requires a usage description.** A bare `swiftc` executable has no
   `Info.plist`, and EventKit *hard-crashes* rather than returning an error. The
   `Info.plist` is linked into the binary's `__TEXT,__info_plist` section.
2. **The binary is ad-hoc signed** on every build, to give it a stable code
   identity for TCC. Note that the permission prompt is attributed to the
   *terminal app* you launch `remind` from, not to `remind` itself.

## Verifying it works

`smoke.sh` exercises every EventKit path end to end — create, read, edit,
complete, delete, and all three ways of referring to a reminder — against a
disposable list, deleting everything it creates:

```bash
# create a list named "remind-smoke" in Reminders.app first
./smoke.sh
```

It refuses to run if that list doesn't exist, and writes nowhere else.
Needs `jq`.

## Development

```bash
make build                        # -> .build/remind
make run ARGS="list --today"
make clean
```
