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

## Claude Code setup

Files from `config/claude/` go into `~/.claude/`:

- `AGENTS.md`: instructions for every coding agent (communication, behavior, git, safety, team repos). `~/.codex/AGENTS.md` is a symlink to it, so Codex reads the same file.
- `CLAUDE.md`: Claude Code-only notes; imports `AGENTS.md` so it also loads in projects with their own `CLAUDE.md`.
- `rules/`: NestJS, TypeORM + PostgreSQL and Redis rules. Each loads only when Claude opens a matching file.
- `settings.json`: model, effort, permissions and enabled plugins.

Also installed:

- Plugins: [context-mode](https://github.com/mksglu/context-mode) (keeps large tool output out of the context), [caveman](https://github.com/JuliusBrussee/caveman) (terse replies; default mode in `config/caveman/config.json`), [ponytail](https://github.com/DietrichGebert/ponytail) (least new code; `lite` mode in `config/ponytail/config.json`, task board stays local; its band above the prompt is hidden). `AGENTS.md` splits their roles so they don't conflict.
- Plugin from this repo: `ponytail-bar` (`config/claude/plugins/ponytail-bar`), a band above the prompt with the model, context usage and ponytail's Review and Audit buttons. `.claude-plugin/marketplace.json` makes this repo its marketplace.
- MCP servers: Context7 (library docs), Playwright and Chrome DevTools (browser automation)
- Skill: [security-audit](https://github.com/cloudflare/security-audit-skill), pinned to a commit

Plugins and MCP servers track their latest versions; only the files in this repo and the security-audit skill are pinned.

## macOS settings

- Appearance: dark mode; English interface with Turkey as the region
- Keyboard: fast key repeat, full keyboard navigation, fn key for dictation
- Text substitutions off: smart quotes, smart dashes, auto-capitalization, auto-correct, double-space period
- Trackpad: natural scrolling off, pointer speed, two-finger secondary click
- Windows: double-clicking a title bar fills the screen; no screenshot thumbnail
- Finder: show file extensions and hidden files, path bar, status bar, folders first, search the current folder, new windows open Desktop, no disks on the desktop, no `.DS_Store` on network and USB drives
- Dock: size, magnification, hot corners and pinned apps (Chrome, iTerm2, VS Code; the app list is set on the first run only)
- Power: display sleeps after 10 minutes on battery, 60 minutes on power adapter
- Require password immediately after the screen locks
- Touch ID for `sudo`

## Git settings

- Asks for name and email, offers to create an SSH key
- Global ignore file: macOS and editor files, personal AI agent settings (`.claude/settings.local.json`, `CLAUDE.local.md`), local `.env` files
- Larger HTTP buffer and timeout for big pushes

## Install

Run from a pinned commit (use the full 40-character hash):

```bash
REF=<commit hash>
/bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/gurelyusuf/dev-setup/$REF/setup.sh)" setup.sh "$REF"
```

`./install-command.sh` prints this command for the current commit.

To run one step only, add its name after the hash (the names are the functions `main` calls at the bottom of `setup.sh`). From a local checkout, for example after editing the Claude Code config:

```bash
SETUP_BASE_URL="file://$PWD" ./setup.sh local configure_claude
```

`./test.sh` tests the helpers that replace files, against a temporary home folder.

The script is safe to re-run and backs up any file it replaces to `~/.dev-setup-backup/`. A re-run puts the repo version of every config file back, so settings you changed in an app since (VS Code, iTerm2) move to the backup. `~/.claude/settings.json` is the exception: keys that only your machine has are kept, and keys that are also in the repo file take the repo value.
