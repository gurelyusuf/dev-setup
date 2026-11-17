#!/bin/bash
# Stop hook: when the turn ends with uncommitted changes that were not there at the previous
# stop, blocks once so they get committed (AGENTS.md: commit after every code change).
set -u

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input") || exit 1
active=$(jq -r '.stop_hook_active // false' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -z "$cwd" ] || cd "$cwd" || exit 1

status=$(git status --porcelain 2>/dev/null) || exit 0 # not a git repo

# Remember the working tree per session, so changes left alone on purpose block only once.
state="${TMPDIR:-/tmp}/claude-stop-check-$sid"
now=$({ echo "$status"; git diff HEAD 2>/dev/null; } | shasum | cut -d' ' -f1)
before=$(cat "$state" 2>/dev/null)
echo "$now" >"$state"

[ "$active" = true ] || [ -z "$status" ] || [ "$now" = "$before" ] && exit 0

jq -n --arg s "$status" '{decision: "block", reason: ("AGENTS.md: commit after every code change. Uncommitted changes:\n" + $s + "\nCommit the ones you made. If they are not yours or must stay uncommitted, say so and stop.")}'
