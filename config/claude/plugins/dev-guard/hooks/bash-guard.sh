#!/bin/bash
# PreToolUse hook for the Bash tool: enforces the command rules in ~/.claude/AGENTS.md.
# Prints a deny/ask decision as JSON, or nothing to let the command through.
set -u

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input") || exit 1
[ -n "$cmd" ] || exit 0
cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -z "$cwd" ] || cd "$cwd" || exit 1

decide() { # decide <deny|ask> <reason>
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

S='[[:space:]]'
E="($S|\$)"
# "git", any global options, then the subcommand follows.
G="(^|$S)git($S+(-[Cc]$S+[^[:space:]]+|--[^[:space:]]+))*$S+"

# Quoted text becomes Q, redirects are dropped and the command is split into one segment per
# line, so words inside a commit message or an echo are not mistaken for commands.
segs=$(sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g; s/[0-9]*>+&?$S*[^[:space:]]*//g" <<<"$cmd" |
  tr ';&|(' '\n\n\n\n' | sed -E "s/^$S+//")
seg() { grep -Eq -- "$1" <<<"$segs"; }  # matches the structure of one command segment
raw() { grep -Eiq -- "$1" <<<"$cmd"; }  # matches anywhere, quoted text included

is_commit=false
seg "${G}commit$E" && is_commit=true

# --- deny ---

seg "${G}push$E" && decide deny "AGENTS.md: never push, only commit."

{ seg "${G}.*--no-verify" || seg "${G}commit($S.*)?$S-[a-zA-Z]*n[a-zA-Z]*$E"; } &&
  decide deny "AGENTS.md: never bypass hooks (--no-verify)."

if $is_commit || seg "(^|$S)gh$S+(pr|issue)$E"; then
  raw 'co-authored-by|generated with \[?claude' &&
    decide deny "AGENTS.md: no Co-Authored-By trailers or other attribution lines."
  raw "(^|[^[:alnum:]_/.@\`])@[[:alnum:]][[:alnum:]-]*([^[:alnum:]/-]|\$)" &&
    decide deny "AGENTS.md: no @username in commits, PRs or issues; it notifies them. Drop the @ or wrap it in backticks."
fi

if $is_commit; then
  nl=$'\n'
  re_heredoc="<<-?[\"']?[A-Za-z_]+[\"']?[^${nl}]*${nl}([^${nl}]*)"
  re_m="(-[a-zA-Z]*m|--message=?)$S*[\"']([^\"'${nl}]*)"
  subject=
  if [[ $cmd =~ $re_heredoc ]]; then
    subject=${BASH_REMATCH[1]}
  elif [[ $cmd =~ $re_m ]]; then
    subject=${BASH_REMATCH[2]}
  fi
  re_cc='^(feat|fix|refactor|docs|test|chore|perf|ci)(\([^)]+\))?!?: [^A-Z ]'
  # A subject that is a shell variable cannot be checked here.
  [[ -n $subject && $subject != \$* && ! $subject =~ $re_cc ]] &&
    decide deny "AGENTS.md: commit subject must be '<type>: <description>' with type feat|fix|refactor|docs|test|chore|perf|ci and a lowercase description."
fi

pm_for() { # prints the package manager that owns the lockfile in directory $1
  [ -f "$1/package-lock.json" ] && echo npm && return
  [ -f "$1/pnpm-lock.yaml" ] && echo pnpm && return
  [ -f "$1/yarn.lock" ] && echo yarn
}
pm=$(pm_for "$PWD")
[ -n "$pm" ] || pm=$(pm_for "$(git rev-parse --show-toplevel 2>/dev/null)")
case $pm in
  npm) other='pnpm|yarn' ;;
  pnpm) other='npm|yarn' ;;
  yarn) other='npm|pnpm' ;;
  *) other= ;;
esac
[ -n "$other" ] && seg "^($other)$S" && ! seg "^($other)$S(.*$S)?(-g|--global)$E" &&
  decide deny "AGENTS.md: the lockfile here belongs to $pm; never mix package managers."

# --- ask ---

seg "(^|$S)rm$S+(.*$S)?(-[a-zA-Z]*[rR][a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*[rR]|-[rR]$S+(.*$S)?-f|-f$S+(.*$S)?-[rR]|--recursive.*--force|--force.*--recursive)" &&
  decide ask "AGENTS.md: destructive command (rm -rf)."
seg "${G}reset$S(.*$S)?--hard" && decide ask "AGENTS.md: destructive command (git reset --hard)."
seg "(^|$S)docker($S+|-)compose$S.*down$S(.*$S)?(-v|--volumes)$E" &&
  decide ask "AGENTS.md: destructive command (docker compose down -v)."
raw 'migration:revert' && decide ask "AGENTS.md: destructive command (migration:revert)."
! $is_commit && raw "drop$S+(table|database|schema)|truncate$S" &&
  decide ask "AGENTS.md: destructive command (drop or truncate)."

if $is_commit; then
  branch=$(git branch --show-current 2>/dev/null)
  # One person often commits under two names or two emails, so other contributors means
  # more than one of each.
  authors=$(git log -n 200 --format='%an%x09%ae' 2>/dev/null | grep -v '\[bot\]')
  names=$(cut -f1 <<<"$authors" | sort -u | wc -l)
  emails=$(cut -f2 <<<"$authors" | sort -u | wc -l)
  [[ $branch =~ ^(main|master|develop|dev|release/.*)$ ]] && [ "$names" -gt 1 ] && [ "$emails" -gt 1 ] &&
    decide ask "AGENTS.md: this repo has other contributors and '$branch' is a shared branch."
fi

seg "(^|$S)gh$S+(pr|issue)$S+(create|comment|review)$E" &&
  decide ask "AGENTS.md: never post anything outward without approval."

seg "^(npm|pnpm|yarn)$S+(install|i|add)$S+(.*$S)?[^-[:space:]]" &&
  ! seg "^(npm|pnpm|yarn)$S(.*$S)?(-g|--global)$E" &&
  decide ask "AGENTS.md: ask before adding a new dependency."

exit 0
