#!/usr/bin/env bash
#
# Installs only the AI tools from setup.sh: Claude Code and Codex, with their
# config, plugins, MCP servers and skills. Nothing else is installed; a part
# that needs a missing tool (Homebrew for Codex, git for the skill) is skipped
# with a warning.
#
# Run from a pinned commit, like setup.sh; `./install-command.sh ai-setup.sh`
# prints the command:
#
#   REF=<40-character commit hash>
#   /bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL \
#     https://raw.githubusercontent.com/gurelyusuf/dev-setup/$REF/ai-setup.sh)" ai-setup.sh "$REF"
#
# The steps themselves live in setup.sh, which is downloaded from the same
# commit and sourced. Written for the stock macOS bash (3.2).

set -euo pipefail

# Same repository as REPO in setup.sh; needed here to download setup.sh.
REPO="gurelyusuf/dev-setup"

ai_main() {
  REF="${1:-}"
  local base="${SETUP_BASE_URL:-}" proto="=https"
  if [[ -z "$base" ]]; then
    # Checked before the download: a branch name or short hash can change.
    [[ "$REF" =~ ^[0-9a-f]{40}$ ]] \
      || { printf 'Error: Pass the full 40-character commit hash as the first argument (got %s).\n' "${REF:-nothing}" >&2; exit 1; }
    base="https://raw.githubusercontent.com/$REPO/$REF"
  fi
  case "$base" in file://*) proto="=file" ;; esac

  SETUP_LIB="$(mktemp)"
  trap 'rm -f "$SETUP_LIB"' EXIT
  curl --proto "$proto" --tlsv1.2 -fsSL "$base/setup.sh" -o "$SETUP_LIB" \
    || { printf 'Error: Could not download %s/setup.sh\n' "$base" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$SETUP_LIB"

  preflight
  install_agents
  configure_claude
  configure_codex

  if [[ -n "$WARNINGS" ]]; then
    printf '\n\033[1;33mWarnings:\033[0m\n%s' "$WARNINGS"
  fi
  cat <<'EOF'

Left for you to do by hand:
  1. Sign in:  claude   |   codex
  2. In Codex, open /hooks and trust ponytail's two hooks.
EOF
}

# Calling ai_main on the last line means a truncated download runs nothing.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  ai_main "$@"
fi
