#!/bin/bash
# SessionStart hook: archives ~/Desktop/daily-done.md when its heading holds an older date and
# starts a new file for today (AGENTS.md: Daily done log).
set -u

file=~/Desktop/daily-done.md
archive=~/Desktop/daily-done-archive
today=$(date +%d-%m-%Y)

[ -f "$file" ] || exit 0
date=$(head -1 "$file" | grep -Eo '[0-9]{2}-[0-9]{2}-[0-9]{4}') ||
  { echo "daily-done-rotate: no date in the heading of $file" >&2; exit 1; }
[ "$date" = "$today" ] && exit 0

target="$archive/$date-daily-done.md"
[ -e "$target" ] && { echo "daily-done-rotate: $target already exists" >&2; exit 1; }
# Another session may rotate at the same moment: never replace its archive or its new log.
mkdir -p "$archive" && mv -n "$file" "$target" || exit 1
[ -e "$file" ] || printf '# Daily Done - %s\n\n| Saat | Yer | Konu | Yapılan |\n| --- | --- | --- | --- |\n' "$today" >"$file"
