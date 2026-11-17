#!/bin/bash
# Self-check for bash-guard.sh. Prints "ok" when every case passes.
hook="$(dirname "$0")/bash-guard.sh"
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
fail=0

t() { # t <deny|ask|allow> <cwd> <command>
  got=$(jq -n --arg c "$3" --arg d "$2" '{tool_input: {command: $c}, cwd: $d}' | "$hook" |
    jq -r '.hookSpecificOutput.permissionDecision')
  [ "${got:-allow}" = "$1" ] || { echo "FAIL want $1 got ${got:-allow}: $3" >&2; fail=1; }
}

commit_as() { # commit_as <repo> <author name> <author email>
  git -C "$1" -c user.name="$2" -c user.email="$3" -c commit.gpgsign=false \
    commit -q --allow-empty -m "chore: init"
}

plain=$tmp/plain npm=$tmp/npm pnpm=$tmp/pnpm solo=$tmp/solo team=$tmp/team
mkdir "$plain" "$npm" "$pnpm"
touch "$npm/package-lock.json" "$pnpm/pnpm-lock.yaml"
# solo: one person under two names. team: two people.
git init -q -b main "$solo" && commit_as "$solo" alice a@example.com && commit_as "$solo" "Alice A" a@example.com
git init -q -b main "$team" && commit_as "$team" alice a@example.com && commit_as "$team" bob b@example.com

t allow "$plain" 'ls -la'
t allow "$plain" 'git status && git log --oneline | head -5'

t deny "$plain" 'git push'
t deny "$plain" 'git -C /some/repo push origin main --force'
t deny "$plain" 'git add . && git commit -m "fix: x" && git push'
t allow "$plain" 'git commit -m "docs: explain git push"'
t allow "$plain" 'git log --grep push'

t deny "$plain" 'git commit --no-verify -m "fix: x"'
t deny "$plain" 'git commit -n -m "fix: x"'
t allow "$plain" 'git commit --amend --no-edit'

t deny "$plain" 'git commit -m "fix: x

Co-Authored-By: Someone <s@example.com>"'
t deny "$plain" 'gh pr create --title "fix: x" --body "Generated with [Claude Code](https://claude.com)"'

t deny "$plain" 'git commit -m "fix: thanks @octocat"'
t allow "$plain" 'git commit -m "fix: mail a@example.com and bump @types/node"'
t allow "$plain" 'git commit -m "fix: handle `@Injectable` providers"'

t allow "$plain" 'git commit -m "feat: let a confirmed case go back to planned"'
t allow "$plain" 'git commit -m "feat(api)!: drop the v1 routes"'
t deny "$plain" 'git commit -m "Fixed the bug"'
t deny "$plain" 'git commit -m "fix: Uppercase description"'
t deny "$plain" 'git commit -m "style: reformat"'
t allow "$plain" $'git commit -m "$(cat <<\'EOF\'\nfix: stop the double charge\n\nbody text\nEOF\n)"'
t deny "$plain" $'git commit -m "$(cat <<\'EOF\'\nStop the double charge\nEOF\n)"'
t allow "$plain" 'git commit -m "$MSG"'

t deny "$npm" 'pnpm install'
t deny "$npm" 'cd app && yarn build'
t allow "$npm" 'npm run build 2>&1 | tail -5'
t deny "$pnpm" 'npm test'
t allow "$pnpm" 'npx tsc --noEmit'
t allow "$pnpm" 'npm install -g typescript'

t ask "$plain" 'rm -rf node_modules'
t ask "$plain" 'rm -fr /tmp/x'
t ask "$plain" 'rm -r -f build'
t allow "$plain" 'rm -f one.txt'
t allow "$plain" 'echo "never run rm -rf here"'
t ask "$plain" 'git reset --hard HEAD~1'
t allow "$plain" 'git reset --soft HEAD~1'
t ask "$plain" 'docker compose down -v'
t ask "$plain" 'docker-compose -f x.yml down --volumes'
t allow "$plain" 'docker compose down'
t ask "$plain" 'npm run migration:revert'
t ask "$plain" 'psql -c "DROP TABLE users"'
t ask "$plain" 'psql -c "truncate users"'
t allow "$plain" 'git commit -m "fix: truncate long titles"'

t allow "$solo" 'git commit -m "fix: x"'
t ask "$team" 'git commit -m "fix: x"'
git -C "$team" checkout -q -b feature
t allow "$team" 'git commit -m "fix: x"'

t ask "$plain" 'gh pr create --title "fix: x" --body "y"'
t ask "$plain" 'gh issue comment 12 --body "done"'
t allow "$plain" 'gh pr view 12'

t ask "$npm" 'npm install lodash'
t ask "$npm" 'npm i -D vitest 2>&1 | tail -3'
t ask "$pnpm" 'pnpm add zod'
t allow "$npm" 'npm install'
t allow "$npm" 'npm install 2>/dev/null'
t allow "$npm" 'npm ci'

[ $fail = 0 ] && echo ok
exit $fail
