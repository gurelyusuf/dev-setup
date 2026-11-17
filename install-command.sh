#!/usr/bin/env bash
# Prints the install command pinned to the current commit, for setup.sh or for
# the script named as the first argument (e.g. ./install-command.sh ai-setup.sh).
# Refuses to print it if the commit is not on GitHub yet or there are
# uncommitted changes, because the new machine would not get what you see here.

set -euo pipefail
cd "$(dirname "$0")"

script="${1:-setup.sh}"
git ls-files --error-unmatch -- "$script" >/dev/null 2>&1 || { echo "Not a file in this repo: $script" >&2; exit 1; }

repo="$(sed -n 's/^REPO="\(.*\)"$/\1/p' setup.sh)"
[[ -n "$repo" ]] || { echo "Could not read REPO from setup.sh" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first." >&2; exit 1; }
ref="$(git rev-parse HEAD)"
git fetch --quiet origin
git branch -r --contains "$ref" | grep -q . || { echo "Commit $ref is not pushed to origin yet." >&2; exit 1; }

cat <<OUT
REF=$ref
/bin/bash -c "\$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/$repo/\$REF/$script)" $script "\$REF"
OUT
