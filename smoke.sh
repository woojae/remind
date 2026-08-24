#!/bin/bash
# End-to-end check against a disposable list. Nothing here touches your real
# reminders: it refuses to run unless a list named $LIST exists, and every item
# it creates is deleted at the end.
#
#   1. In Reminders.app, create a list called "remind-smoke"
#   2. ./smoke.sh
set -uo pipefail

LIST="${LIST:-remind-smoke}"
BIN="${BIN:-./.build/remind}"
pass=0; fail=0

ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

expect() { # expect <description> <actual> <expected>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 — got '$2', expected '$3'"; fi
}

command -v jq >/dev/null || { echo "smoke.sh needs jq (brew install jq)"; exit 2; }
[ -x "$BIN" ] || { echo "build first: make build"; exit 2; }

step "access"
if ! "$BIN" auth --json | jq -e '.granted' >/dev/null; then
  "$BIN" auth
  exit 1
fi
ok "reminders access granted"

step "lists"
if "$BIN" lists --json | jq -e --arg l "$LIST" 'any(.[]; .name == $l)' >/dev/null; then
  ok "found list '$LIST'"
else
  echo "  Create a list named '$LIST' in Reminders.app first (this script only"
  echo "  writes there, and deletes everything it creates)."
  exit 2
fi

step "add — all-day and timed"
"$BIN" add "smoke all-day" --due tomorrow --list "$LIST" --quiet
"$BIN" add "smoke timed"   --due "tomorrow 9am" --list "$LIST" --quiet
"$BIN" add "smoke plain"   --list "$LIST" --quiet
json=$("$BIN" list --list "$LIST" --json)
expect "three reminders created" "$(jq 'length' <<<"$json")" "3"

# The all-day / timed distinction is the round-trip most likely to be wrong.
expect "all-day reminder is allDay"  "$(jq -r '.[]|select(.title=="smoke all-day")|.allDay' <<<"$json")" "true"
expect "timed reminder is not allDay" "$(jq -r '.[]|select(.title=="smoke timed")|.allDay' <<<"$json")" "false"
expect "timed reminder due at 09:00" \
  "$(jq -r '.[]|select(.title=="smoke timed")|.due' <<<"$json" | cut -d'T' -f2 | cut -d: -f1,2)" "09:00"
expect "undated reminder has no due" "$(jq -r '.[]|select(.title=="smoke plain")|has("due")' <<<"$json")" "false"

step "reference resolution"
short=$(jq -r '.[]|select(.title=="smoke timed")|.id' <<<"$json")
row=$(jq -r 'to_entries[]|select(.value.title=="smoke timed")|.key+1' <<<"$json")
expect "resolve by short id"        "$("$BIN" show "$short" --json | jq -r .title)" "smoke timed"
expect "resolve by row number"      "$("$BIN" show "$row"   --json | jq -r .title)" "smoke timed"
expect "resolve by title substring" "$("$BIN" show "smoke timed" --json | jq -r .id)" "$short"
expect "row number and short id agree" "$("$BIN" show "$row" --json | jq -r .id)" "$short"

step "edit"
expect "change due date"  "$("$BIN" edit "$short" --due "2026-12-24 18:30" --json | jq -r .due | cut -dT -f1)" "2026-12-24"
expect "still timed"      "$("$BIN" show "$short" --json | jq -r .allDay)" "false"
expect "clear due date"   "$("$BIN" edit "$short" --no-due --json | jq -r 'has("due")')" "false"
expect "set priority"     "$("$BIN" edit "$short" --priority high --json | jq -r .priority)" "high"
expect "rename"           "$("$BIN" edit "$short" --title "smoke renamed" --json | jq -r .title)" "smoke renamed"

step "complete / reopen"
expect "mark done"   "$("$BIN" done   "$short" --json | jq -r '.[0].completed')" "true"
expect "reopen"      "$("$BIN" undone "$short" --json | jq -r '.[0].completed')" "false"
expect "open list hides completed" \
  "$("$BIN" done "$short" --quiet; "$BIN" list --list "$LIST" --json | jq 'length')" "2"
"$BIN" undone "$short" --quiet

step "filters"
expect "--no-due finds the undated one" \
  "$("$BIN" list --list "$LIST" --no-due --json | jq -r '.[].title' | grep -c 'smoke plain')" "1"
expect "title query filters" \
  "$("$BIN" list --list "$LIST" plain --json | jq 'length')" "1"

step "delete"
for t in "smoke renamed" "smoke all-day" "smoke plain"; do
  "$BIN" delete "$t" --force --quiet 2>/dev/null
done
expect "list is empty again" "$("$BIN" list --list "$LIST" --all --json | jq 'length')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
