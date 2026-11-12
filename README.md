# dev-setup

Sets up a new Mac for Node.js / NestJS / PostgreSQL development: Homebrew, iTerm2, VS Code, OrbStack, Oh My Zsh, mise, Claude Code and Codex, plus my shell, terminal and editor settings.

## Install

Run from a pinned commit (use the full 40-character hash):

```bash
REF=<commit hash>
/bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/gurelyusuf/dev-setup/$REF/setup.sh)" setup.sh "$REF"
```

`./install-command.sh` prints this command for the current commit.

The script is safe to re-run and backs up any file it replaces to `~/.dev-setup-backup/`.
