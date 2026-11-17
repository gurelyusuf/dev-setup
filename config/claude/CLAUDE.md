# CLAUDE.md

Claude Code-specific notes only. Shared instructions for all agents live in `~/.claude/AGENTS.md`,
imported below so they load even in projects that have their own CLAUDE.md.

@AGENTS.md

- Use the `gh` CLI for GitHub (repos, PRs, issues, API).

## Hooks

Some rules in `AGENTS.md` are also enforced by the hooks of the `dev-guard` plugin (`bash-guard.sh`, `stop-check.sh`, `daily-done-rotate.sh`; source in `config/claude/plugins/dev-guard` of the dev-setup repo).

- When a hook denies or asks, follow it. Never work around it with a different command.
- When a rule in `AGENTS.md` changes, update the matching hook and `bash-guard.test.sh` in the same change.
