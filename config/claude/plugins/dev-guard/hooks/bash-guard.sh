#!/bin/bash
# PreToolUse hook for the Bash tool: enforces the command rules in ~/.claude/AGENTS.md.
# Prints a deny/ask decision as JSON, or nothing to let the command through.
# It reads the command as text, so it catches mistakes, not a command built to get past it
# (bash -c "git push" goes through).
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
# "git" (also by path), any global options, then the subcommand follows.
G="(^|$S|/)git($S+(-[Cc]$S+[^[:space:]]+|--[^[:space:]]+))*$S+"
# A wrapper's own arguments: only words that look like an option or a value (-n1, 60, {},
# VAR=x). Any other word is the wrapped command, and the words after it are its arguments.
W="([^[:space:]]*[-0-9{}=][^[:space:]]*$S+)*"
# Where a command starts: at the start of a segment or after a wrapper command and its
# arguments, then past any shell keywords and VAR=value prefixes. "command" is not a wrapper
# here, because "command -v pnpm" only looks a program up; exec counts only at the start,
# so "docker exec" does not.
P="(^|((^|$S)(xargs|timeout|sudo|env|nohup)|^exec)$S+$W)((if|then|else|elif|do|while|until|time|!|\{)$S+)*([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]*$S+)*"

# The command is split into one segment per line. First heredoc bodies, comments and
# redirects are dropped and quoted text becomes Q, so words inside a commit message or an
# echo are not mistaken for commands. Lines are joined with \r meanwhile, because a quote
# can span lines.
cr=$'\r'
quoted="\"([^\"\\\\]|\\\\.)*\"|'[^']*'"
# A << with no closing line is not a heredoc (a bit shift, say): its lines are kept.
segs=$(awk -v q="'" '
  tag != "" {
    if ($0 ~ "^[ \t]*" tag "$") { tag = ""; held = "" } else held = held $0 "\n"
    next
  }
  { print }
  match($0, "(^|[^<])<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z_0-9]*") {
    tag = substr($0, RSTART, RLENGTH); sub(/^.*[^A-Za-z_0-9]/, "", tag)
  }
  END { printf "%s", held }' <<<"$cmd" | tr '\n' '\r' |
  # The leftmost match wins, so a # inside quotes is no comment and a quote inside a comment
  # opens nothing.
  sed -E "s/($quoted)|(^|$S)#[^$cr]*/\\1/g; s/$quoted/Q/g; s/[0-9]*>+&?$S*[^[:space:]]*//g" |
  tr '\r;&|()`' '\n\n\n\n\n\n\n' | sed -E "s/^$S+//")
seg() { grep -Eq -- "$1" <<<"$segs"; }  # matches the structure of one command segment
raw() { grep -Eiq -- "$1" <<<"$cmd"; }  # matches anywhere, quoted text included

is_commit=false
seg "${G}commit$E" && is_commit=true

# --- deny ---

seg "${G}push$E" && decide deny "AGENTS.md: never push, only commit."

# -uno is --untracked-files=no, not -n.
{ seg "${G}.*--no-verify" || seg "${G}commit($S.*)?$S-[a-tv-zA-Z]*n[a-zA-Z]*$E"; } &&
  decide deny "AGENTS.md: never bypass hooks (--no-verify)."

if $is_commit || seg "(^|$S)gh$S+(pr|issue)$E"; then
  raw 'co-authored-by|generated with \[?claude' &&
    decide deny "AGENTS.md: no Co-Authored-By trailers or other attribution lines."
  raw "(^|[^[:alnum:]_/.@\`])@[[:alnum:]][[:alnum:]-]*([^[:alnum:]/-]|\$)" &&
    decide deny "AGENTS.md: no @username in commits, PRs or issues; it notifies them. Drop the @, or wrap it in backticks inside a quoted heredoc (in a double-quoted -m, backticks run as a command)."
fi

if $is_commit; then
  nl=$'\n'
  # The subject is the commit's first -m, or the first line of the commit's own heredoc when
  # there is no -m or the -m reads the heredoc. Only the listed options may bring a quoted
  # value before -m; allowing any option would let a second message pass as the subject.
  re_m="commit([^\"'${nl}]|--(author|date|trailer|cleanup)[= ](\"[^\"]*\"|'[^']*'))*(-[a-zA-Z]*m|--message=?)$S*[\"']([^\"'${nl}]*)"
  re_heredoc="commit[^;&|${nl}]*<<-?[\"']?[A-Za-z_]+[\"']?[^${nl}]*${nl}([^${nl}]*)"
  subject=
  [[ $cmd =~ $re_m ]] && subject=${BASH_REMATCH[5]}
  [[ (-z $subject || $subject == \$*) && $cmd =~ $re_heredoc ]] && subject=${BASH_REMATCH[1]}
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
[ -n "$other" ] && seg "${P}($other)$S" && ! seg "${P}($other)$S(.*$S)?(-g|--global)$E" &&
  decide deny "AGENTS.md: the lockfile here belongs to $pm; never mix package managers."

# --- ask ---

grep -E "(^|$S)rm$S" <<<"$segs" | grep -E "$S(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)$E" |
  grep -Eq "$S(-[a-zA-Z]*f[a-zA-Z]*|--force)$E" && decide ask "AGENTS.md: destructive command (rm -rf)."
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

# gh: every subcommand that is not read-only reaches other people. gh_cmds holds
# "gh <group> <verb>" with any "-flag value" pairs between them skipped.
gh_cmds=$(grep -Eo "${P}gh$S+[a-z-]+$S+(-[^[:space:]]+$S+[^[:space:]]+$S+)*[^[:space:]]+" <<<"$segs" |
  grep -Ev "${P}gh$S+(api|search|help|browse|completion|status)$S")
gh_api_writes() { # checks each gh api call on its own, so a read cannot cover for a write
  local s graphql=0 reads
  local re_api="${P}gh$S+api$E" re_get="$S(-X|--method)($S|=)*GET$E" re_graphql="${S}graphql$E"
  local re_write="$S(-X[A-Za-z]*|--method|-f|-F|--field|--raw-field|--input)($S|=|\$)"
  seg "$re_api" || return 1
  raw "query=[\"']?$S*mutation" && return 0
  while IFS= read -r s; do
    [[ $s =~ $re_api ]] || continue
    [[ $s =~ $re_get ]] && continue
    if [[ $s =~ $re_graphql ]]; then graphql=$((graphql + 1)); continue; fi
    [[ $s =~ $re_write ]] && return 0
  done <<<"$segs"
  # A graphql call is a read only when its query is written inline and starts as one. The
  # query text is quoted, so it is counted in the whole command, not per call; lines are
  # joined because a query often starts on the line after query=.
  reads=$(grep -Eio "query=[\"']?$S*(query[[:space:]({]|\{)" <<<"${cmd//$'\n'/ }" | wc -l)
  [ "$reads" -lt "$graphql" ]
}
{ { [ -n "$gh_cmds" ] &&
  grep -Evq "$S(([a-z]+-)?(view|list|status|diff|checks|checkout|watch|download|clone|get)|--help|-h)\$" <<<"$gh_cmds"; } ||
  gh_api_writes; } && decide ask "AGENTS.md: never post anything outward without approval."

# Under xargs the package names come from stdin, so a bare install adds them too.
{ seg "${P}(npm|pnpm|yarn)$S+(install|i|add)$S+(.*$S)?[^-[:space:]]" ||
  seg "(^|$S)xargs$S+$W(npm|pnpm|yarn)$S+(install|i|add)$E"; } &&
  ! seg "${P}(npm|pnpm|yarn)$S(.*$S)?(-g|--global)$E" &&
  decide ask "AGENTS.md: ask before adding a new dependency."

exit 0
