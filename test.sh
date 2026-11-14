#!/usr/bin/env bash
# Tests for the setup.sh helpers that replace files in the home folder.
# Runs against a temporary HOME, so nothing on this machine changes.
#
#   ./test.sh

set -euo pipefail
cd "$(dirname "$0")"

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

echo "ok"
