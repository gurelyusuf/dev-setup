# dev-setup

Sets up a new Mac for Node.js / NestJS / PostgreSQL development: Homebrew, iTerm2, VS Code, OrbStack, Oh My Zsh, nvm, Claude Code and Codex, plus my shell, terminal and editor settings.

## What gets installed

**Command line**

- Homebrew
- git
- GitHub CLI (`gh`)
- nvm
- PostgreSQL client tools (`psql`, via `libpq`)
- GNU coreutils (`gls`, `gdate`, `gcp`, ... with a `g` prefix)
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

- Appearance: dark mode; English interface with Turkey as the region
- Keyboard: fast key repeat, full keyboard navigation, fn key for dictation
- Text substitutions off: smart quotes, smart dashes, auto-capitalization, auto-correct, double-space period
- Trackpad: natural scrolling off, pointer speed, two-finger secondary click
- Windows: double-clicking a title bar fills the screen; no screenshot thumbnail
- Finder: show file extensions and hidden files, path bar, status bar, folders first, search the current folder, new windows open Desktop, no disks on the desktop, no `.DS_Store` on network and USB drives
- Dock: size, magnification, hot corners and pinned apps (Chrome, iTerm2, VS Code)
- Power: display sleeps after 10 minutes on battery, 60 minutes on power adapter
- Require password immediately after the screen locks
- Touch ID for `sudo`

## Git settings

- Asks for name and email, offers to create an SSH key
- Global ignore file (`.DS_Store`, `.claude/settings.local.json`)
- Larger HTTP buffer and timeout for big pushes

## Install

Run from a pinned commit (use the full 40-character hash):

```bash
REF=<commit hash>
/bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/gurelyusuf/dev-setup/$REF/setup.sh)" setup.sh "$REF"
```

`./install-command.sh` prints this command for the current commit.

The script is safe to re-run and backs up any file it replaces to `~/.dev-setup-backup/`.
