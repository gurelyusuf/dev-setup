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
t deny "$plain" '(git push)'
t deny "$plain" 'echo `git push`'
t deny "$plain" '/usr/bin/git push'
t deny "$plain" $'cat > notes.md <<EOF\nsome notes\nEOF\ngit push'

# A << that opens no heredoc, a comment or a quote inside a quote hides nothing after it.
t deny "$plain" $'python3 -c "print(1 << n)"\ngit push'
t ask "$plain" $'grep -n "cout << value" main.cpp\nrm -rf build'
t deny "$plain" $'x=$((1<<n))\ngit push'
t ask "$plain" $'# it\'s the old build\nrm -rf build\n# that\'s all'
t ask "$plain" $'rm -rf build # it\'s old\necho \'done\''
t deny "$plain" $'echo "issue #12 isn\'t done"; git push'
t deny "$plain" $'sed \'s/"//g\' f.txt; git push; echo "done"'
t allow "$plain" $'# never run git push here\nls'

# Words in a commit body are not commands, however the body is passed.
t allow "$plain" $'git commit -m "$(cat <<\'EOF\'\nfeat: add the guard\n\nIt refuses git push and "rm -rf" too.\nEOF\n)"'
t allow "$plain" $'git commit -F - <<EOF\nfix: clean the build\n\nrm -rf node_modules is no longer needed.\nEOF'
t allow "$plain" $'git commit -m "docs: explain\n\nnever run git push here"'

t deny "$plain" 'git commit --no-verify -m "fix: x"'
t deny "$plain" 'git commit -n -m "fix: x"'
t allow "$plain" 'git commit --amend --no-edit'
t allow "$plain" 'git commit -uno -m "fix: x"'

t deny "$plain" 'git commit -m "fix: x

Co-Authored-By: Someone <s@example.com>"'
t deny "$plain" 'gh pr create --title "fix: x" --body "Generated with [Claude Code](https://claude.com)"'

t deny "$plain" 'git commit -m "fix: thanks @octocat"'
t allow "$plain" 'git commit -m "fix: mail a@example.com and bump @types/node"'
t allow "$plain" "git commit -m 'fix: handle \`@Injectable\` providers'"

t allow "$plain" 'git commit -m "feat: let a confirmed case go back to planned"'
t allow "$plain" 'git commit -m "feat(api)!: drop the v1 routes"'
t deny "$plain" 'git commit -m "Fixed the bug"'
t deny "$plain" 'git commit -m "fix: Uppercase description"'
t deny "$plain" 'git commit -m "style: reformat"'
t allow "$plain" $'git commit -m "$(cat <<\'EOF\'\nfix: stop the double charge\n\nbody text\nEOF\n)"'
t deny "$plain" $'git commit -m "$(cat <<\'EOF\'\nStop the double charge\nEOF\n)"'
t allow "$plain" 'git commit -m "$MSG"'
t allow "$plain" $'cat > notes.md <<EOF\nSome Notes\nEOF\ngit add notes.md && git commit -m "docs: add notes"'
t allow "$plain" $'git commit -m "docs: add notes" && cat <<EOF\nSome Notes\nEOF'
t allow "$plain" 'git commit -m "fix: stop the double charge" -m "Body paragraph with details."'
t deny "$plain" 'git commit -m "Bad subject" -m "fix: body that looks like a subject"'
t deny "$plain" 'git commit --author="A B <a@example.com>" -m "Bad Subject"'
t deny "$plain" 'git commit --author "A B <a@example.com>" -m "Bad Subject"'
t allow "$plain" 'git commit --author="A B <a@example.com>" -m "fix: x" -m "Body Paragraph"'
t allow "$plain" $'git commit -m "fix: stop the double charge" -m "$(cat <<\'EOF\'\nBody Paragraph\nEOF\n)"'

t deny "$npm" 'pnpm install'
t deny "$npm" 'cd app && yarn build'
t allow "$npm" 'npm run build 2>&1 | tail -5'
t deny "$npm" 'CI=1 pnpm install'
t deny "$pnpm" 'npm test'
t allow "$pnpm" 'npx tsc --noEmit'
t allow "$pnpm" 'npm install -g typescript'

t ask "$plain" 'rm -rf node_modules'
t ask "$plain" 'rm -fr /tmp/x'
t ask "$plain" 'rm -r -f build'
t ask "$plain" 'rm -r --force build'
t ask "$plain" 'rm --recursive -f build'
t allow "$plain" 'rm -r build'
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
t ask "$plain" 'gh pr merge 12 --squash'
t ask "$plain" 'gh pr edit 12 --body "new text"'
t ask "$plain" 'gh release create v1.0.0'
t ask "$plain" 'gh api repos/o/r/issues/1/comments -f body=hi'
t ask "$plain" 'gh api -X DELETE repos/o/r/issues/comments/1'
t ask "$plain" 'gh api graphql -f query="mutation { addComment(input: {}) { clientMutationId } }"'
t ask "$plain" 'gh secret set TOKEN'
t ask "$plain" 'gh project item-create 1 --title x'
t ask "$plain" 'cd repo && gh pr merge 12'
# A shell keyword in front of the command hides nothing.
t ask "$plain" 'for n in 12 13; do gh pr merge $n --squash; done'
t ask "$plain" 'if gh pr create --title "fix: x" --body y; then echo ok; fi'
t ask "$plain" 'for id in 1 2; do gh api -X DELETE repos/o/r/issues/comments/$id; done'
t ask "$plain" '{ gh pr merge 12; }'
t ask "$plain" 'time gh pr merge 12'
t allow "$plain" 'for n in 1 2; do gh pr view $n; done'
# Neither does a wrapper command.
t ask "$plain" 'gh issue list --json number -q ".[].number" | xargs -n1 gh issue close'
t ask "$plain" 'timeout 60 gh pr merge 12'
t ask "$plain" 'sudo gh pr merge 12'
t ask "$plain" 'env GH_TOKEN=x gh pr merge 12'
t allow "$plain" 'timeout 60 gh pr view 12'
t allow "$plain" 'gh pr list --json number -q ".[].number" | xargs -n1 gh pr view'
t allow "$plain" $'gh api graphql -f query=\'\nquery($id: ID!) { node(id: $id) { id } }\' -f id=abc'
t ask "$plain" $'gh api graphql -f query=\'\nmutation { resolveReviewThread(input: {}) { clientMutationId } }\''
t allow "$plain" 'rg "query=mutation" src'
t ask "$plain" 'gh api -X GET repos/o/r/pulls/1 && gh api -X POST repos/o/r/issues/1/comments -f body=hi'
t ask "$plain" 'gh api graphql -f query="query { viewer { login } }" && gh api repos/o/r/issues/1/comments -f body=hi'
# A graphql call is a read only when its query is written inline and is not a mutation.
t ask "$plain" $'gh api graphql -f query="$(cat <<\'EOF\'\nmutation { resolveReviewThread(input: {}) { clientMutationId } }\nEOF\n)"'
t ask "$plain" 'gh api graphql -f query="$MUTATION"'
t ask "$plain" 'gh api graphql --input body.json'
t ask "$plain" 'gh api graphql -f query="query { viewer { login } }" && gh api graphql -f query="$MUTATION"'
t allow "$plain" 'gh api graphql -f query="{ viewer { login } }"'
t allow "$plain" 'brew install gh jq fd'
t allow "$plain" 'rg gh config src'
t allow "$plain" 'gh status --org acme'
t allow "$plain" 'gh api repos/o/r/pulls'
t allow "$plain" 'gh api graphql -f query="query { viewer { login } }"'
t allow "$plain" 'gh api -X GET search/issues -f q=bug'
t allow "$plain" 'gh pr -R o/r view 12'
t allow "$plain" 'gh pr --help'
t allow "$plain" 'gh secret list && gh project item-list 1 && gh auth status'
t allow "$plain" 'gh search prs dev-guard && gh --version'
t allow "$plain" 'gh pr view 12'
t allow "$plain" 'gh pr list && gh pr diff 12 && gh pr checks 12'
t allow "$plain" 'gh repo view && gh run list'

t ask "$npm" 'npm install lodash'
t ask "$npm" 'npm i -D vitest 2>&1 | tail -3'
t ask "$pnpm" 'pnpm add zod'
t ask "$npm" 'CI=1 npm install lodash'
t ask "$npm" 'for p in lodash zod; do npm install $p; done'
t deny "$npm" 'if pnpm install; then echo ok; fi'
t ask "$npm" 'echo lodash zod | xargs npm install'
t deny "$npm" 'timeout 60 pnpm install'
t allow "$npm" 'command -v pnpm >/dev/null || echo missing'
t allow "$npm" 'npm install'
t allow "$npm" 'npm install 2>/dev/null'
t allow "$npm" 'npm ci'

[ $fail = 0 ] && echo ok
exit $fail
