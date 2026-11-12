# dev-setup

Sets up a new Mac for Node.js / NestJS / PostgreSQL development: Homebrew, iTerm2, VS Code, OrbStack, Oh My Zsh, mise, Claude Code and Codex, plus my shell, terminal and editor settings.

## What gets installed

**Command line**

- Homebrew
- git
- GitHub CLI (`gh`)
- mise
- PostgreSQL client tools (`psql`, via `libpq`)
- Node.js LTS
- pnpm
- NestJS CLI
- Claude Code
- Codex

**Applications**

- iTerm2
- Visual Studio Code
- OrbStack
- Google Chrome
- Postman
- Microsoft Teams
- pgAdmin 4

**Shell**

- Oh My Zsh
- powerlevel10k
- zsh-autosuggestions
- zsh-syntax-highlighting
- JetBrains Mono Nerd Font

**VS Code extensions**

- Claude Code, Codex
- ESLint, Prettier, EditorConfig
- Containers
- GitHub Actions
- Remote SSH

## macOS settings

- Keyboard: fast key repeat, full keyboard navigation, fn key for dictation
- Text substitutions off: smart quotes, smart dashes, auto-capitalization, auto-correct, double-space period
- Natural scrolling off
- Finder: show file extensions and hidden files, path bar, status bar; no `.DS_Store` on network and USB drives
- Dock: size, magnification, hot corners and pinned apps (Chrome, iTerm2, VS Code)
- Require password immediately after the screen locks
- Touch ID for `sudo`

## Install

Run from a pinned commit (use the full 40-character hash):

```bash
REF=<commit hash>
/bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/gurelyusuf/dev-setup/$REF/setup.sh)" setup.sh "$REF"
```

`./install-command.sh` prints this command for the current commit.

The script is safe to re-run and backs up any file it replaces to `~/.dev-setup-backup/`.
