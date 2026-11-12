#!/usr/bin/env bash
# Prints the install command pinned to the current commit.
# Refuses to print it if the commit is not on GitHub yet or there are
# uncommitted changes, because the new machine would not get what you see here.

set -euo pipefail
cd "$(dirname "$0")"

repo="$(sed -n 's/^REPO="\${SETUP_REPO:-\(.*\)}"$/\1/p' setup.sh)"
[[ -n "$repo" ]] || { echo "Could not read REPO from setup.sh" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first." >&2; exit 1; }
ref="$(git rev-parse HEAD)"
git fetch --quiet origin
git branch -r --contains "$ref" | grep -q . || { echo "Commit $ref is not pushed to origin yet." >&2; exit 1; }

cat <<OUT
REF=$ref
/bin/bash -c "\$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/$repo/\$REF/setup.sh)" setup.sh "\$REF"
OUT
