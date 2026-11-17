#!/usr/bin/env bash
# Tests for the dev-bar and dev-guard plugins and for the setup.sh helpers that
# replace or edit files in the home folder. The helpers run against a temporary HOME,
# so nothing on this machine changes.
#
#   ./test.sh

set -euo pipefail
cd "$(dirname "$0")"

# Before HOME changes: claude runs with the real home folder.
claude plugin test config/claude/plugins/dev-bar

config/claude/plugins/dev-guard/hooks/bash-guard.test.sh >/dev/null

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT
export HOME="$tmp_home" SETUP_BASE_URL="file://$PWD"
# shellcheck disable=SC1091
source ./setup.sh

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# fetch installs a new file.
dest="$HOME/ignore"
fetch config/git/ignore "$dest" >/dev/null
cmp -s config/git/ignore "$dest" || fail "fetch did not install a new file"

# fetch leaves an identical file alone and makes no backup.
fetch config/git/ignore "$dest" >/dev/null
[[ ! -e "$BACKUP_DIR" ]] || fail "fetch backed up an unchanged file"

# fetch backs up a different file before it replaces it.
echo "old content" >"$dest"
fetch config/git/ignore "$dest" >/dev/null
cmp -s config/git/ignore "$dest" || fail "fetch did not replace a changed file"
[[ "$(cat "$BACKUP_DIR/ignore")" == "old content" ]] || fail "fetch did not back up the old file"

# merge_kept_keys keeps keys only the old file had; the repo file wins otherwise.
settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
echo '{"theme": "dark", "model": "old", "enabledPlugins": {"mine@x": true}}' >"$settings"
fetch config/claude/settings.json "$settings" >/dev/null
merge_kept_keys "$settings" >/dev/null
python3 - "$settings" config/claude/settings.json <<'PY' || fail "merge_kept_keys produced the wrong settings"
import json, sys

merged, repo = (json.load(open(path)) for path in sys.argv[1:3])
assert merged["theme"] == "dark", "top-level key only in the old file was dropped"
assert merged["enabledPlugins"]["mine@x"] is True, "nested key only in the old file was dropped"
assert merged["model"] == repo["model"], "repo value did not win"
assert merged["permissions"] == repo["permissions"], "repo permissions did not win"
for plugin in repo["enabledPlugins"]:
    assert merged["enabledPlugins"][plugin] is True, "repo plugin missing: " + plugin
PY

# install_security_audit_skill keeps the installed skill when the download has no skill folder.
skill="$HOME/.claude/skills/security-audit"
mkdir -p "$skill"
echo "old skill" >"$skill/SKILL.md"
SECURITY_AUDIT_REPO="$HOME/empty-skill-repo"
git init -q "$SECURITY_AUDIT_REPO"
git -C "$SECURITY_AUDIT_REPO" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m empty
SECURITY_AUDIT_REF="$(git -C "$SECURITY_AUDIT_REPO" rev-parse HEAD)"
install_security_audit_skill >/dev/null || fail "install_security_audit_skill failed on a download without the skill"
[[ "$(cat "$skill/SKILL.md" 2>/dev/null)" == "old skill" ]] || fail "install_security_audit_skill removed the installed skill"

# configure_codex_tui creates the config, then on a re-run changes nothing.
codex_config="$HOME/.codex/config.toml"
rm -rf "$BACKUP_DIR"
configure_codex_tui >/dev/null
configure_codex_tui >/dev/null
[[ ! -e "$BACKUP_DIR/.codex/config.toml" ]] || fail "configure_codex_tui rewrote an unchanged config"

# configure_codex_tui replaces the status line and keeps every other key.
printf 'model = "mine"\n\n[tui]\nstatus_line = ["current-dir"]\nstatus_line_use_colors = true\n\n[notice]\nhide = true\n' >"$codex_config"
configure_codex_tui >/dev/null
configure_codex_tui >/dev/null
grep -q 'status_line = \["current-dir"\]' "$BACKUP_DIR/.codex/config.toml" || fail "configure_codex_tui did not back up the old config"
python3 - "$codex_config" <<'PY' || fail "configure_codex_tui produced the wrong config"
import sys, tomllib

with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)
assert config["model"] == "mine", "top-level key was dropped"
assert config["notice"]["hide"] is True, "another table was dropped"
assert config["tui"]["status_line_use_colors"] is True, "another tui key was dropped"
assert config["tui"]["status_line"] == ["model-with-reasoning", "context-used", "git-branch"], "status line was not set"
assert [config["tui"]["presets"][n]["label"] for n in "1234"] == ["Check", "Review", "Audit", "Security"], "presets are wrong"
PY

# configure_codex_tui adds the status line to a [tui] table that has none and keeps existing presets.
printf '[tui]\nstatus_line_use_colors = true\n\n[tui.presets.1]\ninput = "mine"\n' >"$codex_config"
configure_codex_tui >/dev/null
python3 - "$codex_config" <<'PY' || fail "configure_codex_tui broke a config with its own presets"
import sys, tomllib

with open(sys.argv[1], "rb") as f:
    tui = tomllib.load(f)["tui"]
assert tui["status_line"] == ["model-with-reasoning", "context-used", "git-branch"], "status line was not added"
assert tui["presets"] == {"1": {"input": "mine"}}, "existing presets were changed"
PY

guard=config/claude/plugins/dev-guard/hooks

# daily-done-rotate archives a log from another day and starts today's.
log="$HOME/Desktop/daily-done.md"
mkdir -p "$HOME/Desktop"
printf '# Daily Done - 01-01-2026\n\nold row\n' >"$log"
"$guard/daily-done-rotate.sh" </dev/null || fail "daily-done-rotate failed"
grep -q "old row" "$HOME/Desktop/daily-done-archive/01-01-2026-daily-done.md" || fail "daily-done-rotate did not archive the old log"
[[ "$(head -1 "$log")" == "# Daily Done - $(date +%d-%m-%Y)" ]] || fail "daily-done-rotate did not start today's log"

# daily-done-rotate leaves today's log alone.
echo "today row" >>"$log"
"$guard/daily-done-rotate.sh" </dev/null || fail "daily-done-rotate failed on today's log"
grep -q "today row" "$log" || fail "daily-done-rotate replaced today's log"

# stop-check blocks once for new uncommitted changes and never while it is already active.
repo="$HOME/stop-repo"
git init -q "$repo"
stop_check() { # stop_check <stop_hook_active> [baseline]
  printf '{"session_id": "test", "cwd": "%s", "stop_hook_active": %s}' "$repo" "$1" | TMPDIR="$HOME" "$guard/stop-check.sh" ${2:-}
}
[[ -z "$(stop_check false)" ]] || fail "stop-check blocked a clean repo"
touch "$repo/new.txt"
[[ "$(stop_check false)" == *'"block"'* ]] || fail "stop-check did not block new uncommitted changes"
[[ -z "$(stop_check false)" ]] || fail "stop-check blocked the same changes twice"
touch "$repo/other.txt"
[[ -z "$(stop_check true)" ]] || fail "stop-check blocked while it was already active"

# stop-check baseline records changes that were already there, so only later ones block.
rm "$HOME/claude-stop-check-test"
[[ -z "$(stop_check false baseline)" ]] || fail "stop-check baseline printed a decision"
[[ -z "$(stop_check false)" ]] || fail "stop-check blocked changes from before the session"
touch "$repo/later.txt"
[[ "$(stop_check false)" == *'"block"'* ]] || fail "stop-check did not block changes made after the baseline"

echo "ok"
