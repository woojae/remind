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

## Remind.app — the macOS app

The same EventKit core, as a small always-running Mac app modelled on
[Marco Arment's Unforgetful](https://marco.org/2026/08/14/unforgetful):
reminders for people who forget reminders.

- **One flat list.** Two groups: **Now** and **Later**. No folders, tags,
  smart lists, or modes. A hidden task is a forgotten task.
- **Nothing is overdue.** A task whose time has passed is simply *due now*.
  It reads "Since 3:15 PM", never "overdue", and it is never red.
- **Notifications repeat until you deal with the task.** Dismissing one
  changes nothing; it comes back after the repeat interval (default 10
  minutes) until the task is completed, snoozed, or deleted. Several due
  tasks are spaced out rather than dumped on you at once, and quiet hours
  (default 10 PM–8 AM) hold everything until morning.
- **Snooze scales.** The ladder is 10 min → 30 min → 1 h → 3 h → 6 h → 9 h →
  tomorrow morning → 3 days → a week. Every option shows the actual time it lands on,
  and the suggested rung climbs each time you snooze the same task.
- **Recurring tasks don't pile up.** Completing a repeating task you missed
  schedules the next occurrence from *now*, not from the date you skipped.
- **It is your Reminders database.** Siri, the Reminders app, and your phone
  all keep working; nothing is imported or duplicated. Tasks created here get
  a Reminders alarm too, so other devices notify you (Settings can turn that
  off).
- **Quick add** understands dates in the sentence: `Call mom tomorrow 5pm`,
  `Water plants in 3 days`, `Standup at noon`. A task with no date is due
  now. The mic button starts macOS dictation.
- **Menu bar item** shows how many tasks are due now, with Done/Snooze for
  each. Closing the window keeps the app (and the nagging) running.
- **Looks like a control room.** A near-black terminal with a faint
  engineering grid behind it, dot-matrix headlines and counters, monospace
  copy, square corners, and one hot pink accent for whatever is due right
  now. The theme is dark-only, so the windows stay dark in Light Mode. The
  palette lives in `App/Theme.swift`; the wordmark and readouts are set in
  [Doto](https://fonts.google.com/specimen/Doto) and the body in
  [JetBrains Mono](https://fonts.google.com/specimen/JetBrains+Mono) (both
  OFL), bundled from `App/Fonts/`.

### Build and run

```bash
make app           # -> .build/Remind.app
make run-app       # open it
make install-app   # copy to ~/Applications (APPINSTALL=/Applications to override)
```

On first launch macOS asks for Reminders access and for notification
permission. Both are attributed to Remind itself, not to your terminal.
Turn on **Launch at login** in Settings so it is always running; it only
notifies while it is open.

Because tasks also carry a Reminders alarm, Reminders.app will post its own
one-time notification at the due moment. If you find that redundant, turn
off notifications for Reminders in **System Settings → Notifications**, or
uncheck "Also set a Reminders alarm" in Remind's settings.

The app's own bookkeeping — when each task was last announced and how many
times it has been snoozed — lives in
`~/Library/Application Support/Remind/state.json`, not in the reminder.

## Remind for iPhone

The same app, on the phone: one screen with the quick-add field, the Now and
Later list, and the editor and settings as sheets. It reads the same Reminders
database, so Done and Snooze on either device show up on the other as soon as
iCloud catches up.

The one real difference is how nagging works. iOS suspends an app seconds after
it leaves the screen, so there is no timer to nag from. Instead, every change to
the list plans the next stretch of notifications and hands them to iOS: for each
task, one per repeat interval, spaced apart, skipping quiet hours, as far ahead
as iOS's 64-request budget reaches (about a day for one or two tasks, a few
hours for several). iOS fires them whether or not the app is open. Done and
Snooze on a banner run in the background and re-plan. Opening the app, or a
background refresh when iOS grants one, extends the plan. Settings shows how
much is queued and how far it reaches.

Nag bookkeeping (last notified, snooze count) is per device, so a task that is
due rings on both the Mac and the phone, each on its own clock.

### Build and run on your phone

The iOS app is built and signed by Xcode. The project is generated from
`project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # once
make xcodeproj          # -> Remind.xcodeproj
open Remind.xcodeproj
```

Then, in Xcode:

1. **Xcode › Settings › Accounts**, add your Apple ID. A free account is
   enough to run on your own phone.
2. Select the **RemindiOS** target › **Signing & Capabilities**, and pick your
   Team. Change the bundle identifier if Xcode says it's taken.
3. Plug in the phone, unlock it, tap Trust. Turn on **Developer Mode** on the
   phone (Settings › Privacy & Security) if asked.
4. Pick your phone in the toolbar's device menu and press **Run**.
5. The first launch stops with "Untrusted Developer". On the phone go to
   **Settings › General › VPN & Device Management**, tap your Apple ID, Trust,
   then run again.

With a free account the install expires after seven days; re-run from Xcode to
renew. A paid developer account can push builds through TestFlight instead.

`Remind.xcodeproj` is ignored by git; `project.yml` is the source of truth.
Re-run `make xcodeproj` after adding files. The project also has a **Remind**
macOS target, but `make app` remains the canonical Mac build.

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

The CLI's `Sources/` is five files:

- `Remind.swift` — entry point and command implementations
- `Store.swift` — EventKit wrapper, permissions, reference resolution
- `DateParse.swift` — the `--due` grammar
- `Format.swift` — table, detail, and JSON rendering
- `Args.swift` — option parsing
- `Help.swift` — help text

The macOS app in `App/` reuses `Store.swift` and `DateParse.swift` and adds:

- `RemindApp.swift` — scenes (window, menu bar item, settings) and app delegate
- `TaskStore.swift` — the observable list, completion, snooze, recurrence
- `Notifier.swift` — the repeat-until-done notification loop and its actions
- `Snooze.swift` — the snooze ladder and the on-disk nag state
- `QuickAdd.swift` — pulls a due date out of a typed sentence
- `Views.swift`, `SettingsView.swift`, `Display.swift` — SwiftUI
- `Theme.swift` — palette, window chrome, and control styles
- `mkicon.swift` — renders the app icon at build time (`--ios` for the phone's)

The iOS app in `iOS/` compiles everything above except the Mac-only files
(`Notifier`, `RemindApp`, `SettingsView`, `Snapshot`), plus:

- `RemindApp.swift` — the single-window scene, app delegate, background refresh
- `Notifier.swift` — plans the nags ahead and hands them to iOS
- `PhoneViews.swift`, `PhoneSettingsView.swift` — the one screen and its sheets

The handful of places the shared code touches AppKit or UIKit go through
`Platform` in `App/Theme.swift`.

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
