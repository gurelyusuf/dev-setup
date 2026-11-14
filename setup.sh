#!/usr/bin/env bash
#
# Development environment bootstrap for macOS.
#
# Hosted on GitHub and always run from a pinned commit, so the code that runs
# is exactly the code that was reviewed. ./install-command.sh prints the
# command for the current commit; it looks like this:
#
#   REF=<40-character commit hash>
#   /bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL \
#     https://raw.githubusercontent.com/gurelyusuf/dev-setup/$REF/setup.sh)" setup.sh "$REF"
#
# The hash is passed twice on purpose: once to download this file, once so
# this file downloads config/ from the very same commit.
#
# Safe to re-run: every step checks whether its work is already done.
# Written for the stock macOS bash (3.2); avoid bash 4+ features.

set -euo pipefail

# GitHub repository (owner/name) that hosts this script and config/.
# It must be public: raw.githubusercontent.com serves private repos only with a token.
REPO="${SETUP_REPO:-gurelyusuf/dev-setup}"

# Built in preflight() from the commit hash argument. SETUP_BASE_URL=file:///path
# overrides it for local testing.
BASE_URL="${SETUP_BASE_URL:-}"

FORMULAE="git gh nvm libpq coreutils"

# npm packages installed globally into every Node.js version.
NODE_GLOBAL_PACKAGES="pnpm @nestjs/cli"
# Optional CLI tools, add to FORMULAE if wanted: jq ripgrep fd eza zoxide

# cask-name|App bundle name (used to skip apps that IT already installed)
CASKS="
iterm2|iTerm.app
visual-studio-code|Visual Studio Code.app
orbstack|OrbStack.app
google-chrome|Google Chrome.app
postman|Postman.app
microsoft-teams|Microsoft Teams.app
pgadmin4|pgAdmin 4.app
codex|
font-jetbrains-mono-nerd-font|
"

VSCODE_EXTENSIONS="
anthropic.claude-code
openai.chatgpt
dbaeumer.vscode-eslint
esbenp.prettier-vscode
editorconfig.editorconfig
ms-azuretools.vscode-containers
github.vscode-github-actions
ms-vscode-remote.remote-ssh
"

# Claude Code files under config/claude/, installed into ~/.claude/.
CLAUDE_FILES="CLAUDE.md AGENTS.md settings.json rules/nestjs.md rules/typeorm-postgres.md rules/redis.md"

# marketplace source|plugin@marketplace
CLAUDE_PLUGINS="
mksglu/context-mode|context-mode@context-mode
JuliusBrussee/caveman|caveman@caveman
DietrichGebert/ponytail|ponytail@ponytail
"

# Skill from cloudflare/security-audit-skill, pinned like everything else here.
SECURITY_AUDIT_REPO="https://github.com/cloudflare/security-audit-skill.git"
SECURITY_AUDIT_REF="c1c8a8c1471069fb0e188eeaff69b8e8db6564a8"

BACKUP_DIR="$HOME/.dev-setup-backup/$(date +%Y%m%d-%H%M%S)"
WARNINGS=""

# ---------------------------------------------------------------- helpers

step() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; WARNINGS="${WARNINGS}  - $*"$'\n'; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Prompts read from the terminal so they still work under `curl | bash`.
ask() { # ask "Question" VARNAME
  local reply=""
  if [[ -r /dev/tty ]]; then
    printf '    %s ' "$1" >/dev/tty
    read -r reply </dev/tty || true
  fi
  eval "$2=\$reply"
}

confirm() { # confirm "Question" -> 0 on yes
  local reply=""
  ask "$1 [y/N]" reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

# fetch <path under BASE_URL> <destination>
# Downloads to a temp file, backs up any different existing file, then moves
# the download into place. Integrity comes from the pinned commit in BASE_URL.
fetch() {
  local rel="$1" dest="$2" tmp proto="=https"
  case "$BASE_URL" in file://*) proto="=file" ;; esac
  tmp="$(mktemp)"
  curl --proto "$proto" --tlsv1.2 -fsSL "$BASE_URL/$rel" -o "$tmp" \
    || { rm -f "$tmp"; die "Could not download $BASE_URL/$rel"; }


  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    if cmp -s "$tmp" "$dest"; then
      rm -f "$tmp"; info "unchanged: $dest"; return 0
    fi
    # Keep the path under $HOME so files with the same name (e.g. the VS Code
    # and Claude Code settings.json) do not overwrite each other's backup.
    local backup="$BACKUP_DIR/${dest#"$HOME"/}"
    mkdir -p "$(dirname "$backup")"
    cp -p "$dest" "$backup"
    info "backed up existing $dest to $backup"
  fi
  mv "$tmp" "$dest"
  info "installed: $dest"
}

# merge_kept_keys <json file that fetch just replaced>
# Puts back the keys that only the old file had. Claude Code writes its own
# keys into settings.json (hooks, status line, extra plugins); replacing the
# file would drop them. Keys in the repo file win, and lists are not merged.
merge_kept_keys() {
  local dest="$1" backup="$BACKUP_DIR/${1#"$HOME"/}"
  [[ -f "$backup" ]] || return 0
  python3 - "$backup" "$dest" <<'PY' && info "kept machine-only keys: $dest" \
    || warn "could not merge the old keys into $dest; the old file is in $backup"
import json, os, sys

def merge(old, new):
    for key, value in old.items():
        if key not in new:
            new[key] = value
        elif isinstance(value, dict) and isinstance(new[key], dict):
            merge(value, new[key])
    return new

old_path, new_path = sys.argv[1:3]
with open(old_path) as f:
    old = json.load(f)
with open(new_path) as f:
    new = json.load(f)
with open(new_path + ".tmp", "w") as f:
    json.dump(merge(old, new), f, indent=2)
    f.write("\n")
os.replace(new_path + ".tmp", new_path)
PY
}

clone_once() { # clone_once <repo url> <destination>
  if [[ -d "$2" ]]; then info "already present: $(basename "$2")"; return 0; fi
  git clone --depth=1 --quiet "$1" "$2" && info "cloned: $(basename "$2")"
}

# ------------------------------------------------------------------ steps

preflight() {
  step "Checking the machine"
  [[ "$(uname -s)" == "Darwin" ]] || die "This script only supports macOS."
  [[ "$(id -u)" -ne 0 ]] || die "Run as your normal user, not with sudo."
  if [[ -z "$BASE_URL" ]]; then
    [[ "$REF" =~ ^[0-9a-f]{40}$ ]] || die "Pass the full 40-character commit hash as the first argument (got '${REF:-nothing}'). Branch names and short hashes are refused because they can change."
    BASE_URL="https://raw.githubusercontent.com/$REPO/$REF"
  fi
  case "$BASE_URL" in https://*|file://*) ;; *) die "BASE_URL must start with https://" ;; esac
  info "source: $BASE_URL"
  info "macOS $(sw_vers -productVersion) on $(uname -m)"
}

install_homebrew() {
  step "Homebrew"
  if ! have brew && [[ ! -x /opt/homebrew/bin/brew && ! -x /usr/local/bin/brew ]]; then
    info "Homebrew needs administrator rights; you may be asked for your password."
    sudo -v </dev/tty || die "Administrator rights are required to install Homebrew."
    # The installer also installs the Xcode Command Line Tools (needed for git).
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    info "already installed"
  fi

  if [[ -x /opt/homebrew/bin/brew ]]; then BREW=/opt/homebrew/bin/brew; else BREW=/usr/local/bin/brew; fi
  eval "$("$BREW" shellenv)"

  local line="eval \"\$($BREW shellenv)\""
  touch "$HOME/.zprofile"
  grep -qF "$line" "$HOME/.zprofile" || { printf '%s\n' "$line" >>"$HOME/.zprofile"; info "added brew to ~/.zprofile"; }
}

install_packages() {
  step "Command line tools"
  local f
  for f in $FORMULAE; do
    if brew list --formula "$f" >/dev/null 2>&1; then info "already installed: $f"
    else brew install "$f" || warn "brew install $f failed"; fi
  done

  step "Applications"
  local entry cask app
  printf '%s\n' "$CASKS" | while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    cask="${entry%%|*}"; app="${entry#*|}"
    if brew list --cask "$cask" >/dev/null 2>&1; then
      info "already installed: $cask"
    elif [[ -n "$app" && -d "/Applications/$app" ]]; then
      info "already in /Applications, skipping: $app"
    else
      brew install --cask "$cask" </dev/null || echo "$cask" >>"$FAILED_CASKS"
    fi
  done
  if [[ -s "$FAILED_CASKS" ]]; then
    warn "these apps could not be installed: $(tr '\n' ' ' <"$FAILED_CASKS")"
  fi
}

install_shell() {
  step "Oh My Zsh, powerlevel10k and plugins"
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    info "already installed: Oh My Zsh"
  else
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended
  fi
  local custom="$HOME/.oh-my-zsh/custom"
  clone_once https://github.com/romkatv/powerlevel10k.git "$custom/themes/powerlevel10k"
  clone_once https://github.com/zsh-users/zsh-autosuggestions.git "$custom/plugins/zsh-autosuggestions"
  clone_once https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"

  step "Shell config"
  fetch config/zshrc "$HOME/.zshrc"
  fetch config/p10k.zsh "$HOME/.p10k.zsh"
}

# Runs a command with nvm loaded. nvm.sh is not written for `set -eu`, so it
# is sourced in a subshell with those options off.
with_nvm() {
  (
    set +eu
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$(brew --prefix nvm)/nvm.sh" || exit 1
    "$@"
  )
}

install_node() {
  step "Node.js, pnpm and NestJS CLI (via nvm)"
  mkdir -p "$HOME/.nvm"

  # nvm installs every package listed here into each Node version it installs,
  # so these commands keep working after switching versions.
  local pkg defaults_file="$HOME/.nvm/default-packages"
  touch "$defaults_file"
  for pkg in $NODE_GLOBAL_PACKAGES; do
    grep -qxF "$pkg" "$defaults_file" || printf '%s\n' "$pkg" >>"$defaults_file"
  done

  with_nvm nvm install --lts || { warn "nvm could not install Node.js"; return 0; }
  with_nvm nvm alias default 'lts/*' >/dev/null || warn "could not set the default Node.js version"

  # Covers the case where this Node version was installed before the list above existed.
  for pkg in $NODE_GLOBAL_PACKAGES; do
    if with_nvm npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then info "already installed: $pkg"
    else with_nvm npm install -g "$pkg" || warn "npm install -g $pkg failed"; fi
  done
}

configure_iterm() {
  step "iTerm2 settings"
  local dir="$HOME/.config/iterm2"
  pgrep -xq iTerm2 && warn "iTerm2 is running; quit and reopen it to load the imported settings"
  fetch config/iterm/com.googlecode.iterm2.plist "$dir/com.googlecode.iterm2.plist"
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$dir"
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
}

configure_vscode() {
  step "VS Code settings and extensions"
  local user_dir="$HOME/Library/Application Support/Code/User"
  fetch config/vscode/settings.json "$user_dir/settings.json"
  fetch config/vscode/keybindings.json "$user_dir/keybindings.json"

  local code_bin="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  have code && code_bin="$(command -v code)"
  if [[ ! -x "$code_bin" ]]; then
    warn "VS Code CLI not found; extensions were not installed"
    return 0
  fi
  local installed ext
  installed="$("$code_bin" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  for ext in $VSCODE_EXTENSIONS; do
    if printf '%s\n' "$installed" | grep -qx "$ext"; then info "already installed: $ext"
    else "$code_bin" --install-extension "$ext" --force >/dev/null 2>&1 && info "installed: $ext" || warn "extension failed: $ext"; fi
  done
}

install_agents() {
  step "Claude Code and Codex"
  export PATH="$HOME/.local/bin:$PATH"
  if have claude; then
    info "already installed: claude"
  else
    curl --proto '=https' --tlsv1.2 -fsSL https://claude.ai/install.sh | bash || warn "Claude Code install failed"
  fi
  have codex && info "codex is installed" || warn "codex not found (cask install may have failed)"
}

configure_claude() {
  step "Claude Code config, plugins, MCP servers and skills"
  local f
  for f in $CLAUDE_FILES; do
    fetch "config/claude/$f" "$HOME/.claude/$f"
  done
  merge_kept_keys "$HOME/.claude/settings.json"
  fetch config/caveman/config.json "$HOME/.config/caveman/config.json"
  fetch config/ponytail/config.json "$HOME/.config/ponytail/config.json"
  link_codex_agents
  install_security_audit_skill

  export PATH="$HOME/.local/bin:$PATH"
  if ! have claude; then
    warn "claude not found; plugins and MCP servers were not installed"
    return 0
  fi
  install_claude_plugins
  install_claude_mcp_servers
}

# Codex reads ~/.codex/AGENTS.md; link it so both agents share one file.
link_codex_agents() {
  local link="$HOME/.codex/AGENTS.md" target="$HOME/.claude/AGENTS.md"
  if [[ -L "$link" && "$(readlink "$link")" == "$target" ]]; then
    info "already linked: $link"; return 0
  fi
  mkdir -p "$HOME/.codex"
  if [[ -e "$link" || -L "$link" ]]; then
    mkdir -p "$BACKUP_DIR/.codex"
    mv "$link" "$BACKUP_DIR/.codex/AGENTS.md"
    info "backed up existing $link to $BACKUP_DIR/.codex/AGENTS.md"
  fi
  ln -s "$target" "$link" && info "linked: $link -> $target"
}

install_security_audit_skill() {
  local dest="$HOME/.claude/skills/security-audit" tmp
  if [[ "$(cat "$dest/.source-ref" 2>/dev/null)" == "$SECURITY_AUDIT_REF" ]]; then
    info "already installed: security-audit skill"; return 0
  fi
  tmp="$(mktemp -d)"
  if ! { git -C "$tmp" init -q \
      && git -C "$tmp" fetch -q --depth=1 "$SECURITY_AUDIT_REPO" "$SECURITY_AUDIT_REF" \
      && git -C "$tmp" checkout -q FETCH_HEAD; }; then
    rm -rf "$tmp"; warn "could not download the security-audit skill"; return 0
  fi
  if [[ -d "$dest" ]]; then
    mkdir -p "$BACKUP_DIR/.claude/skills"
    mv "$dest" "$BACKUP_DIR/.claude/skills/security-audit"
    info "backed up existing security-audit skill to $BACKUP_DIR"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -R "$tmp/skills/security-audit" "$dest"
  printf '%s\n' "$SECURITY_AUDIT_REF" >"$dest/.source-ref"
  rm -rf "$tmp"
  info "installed: security-audit skill"
}

# Adding a marketplace or installing a plugin that is already there is a no-op.
# The loop reads a here-string (not a pipe) so warn() runs in this shell;
# claude gets </dev/null so it cannot consume the loop's input.
install_claude_plugins() {
  local entry src plugin
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    src="${entry%%|*}"; plugin="${entry#*|}"
    claude plugin marketplace add "$src" </dev/null >/dev/null 2>&1 || warn "could not add plugin marketplace $src"
    if claude plugin install "$plugin" </dev/null >/dev/null 2>&1; then info "installed: $plugin"
    else warn "could not install plugin $plugin"; fi
  done <<<"$CLAUDE_PLUGINS"
}

# add_mcp <name> <claude mcp add arguments...>; skips servers that already exist.
add_mcp() {
  local name="$1"; shift
  if claude mcp get "$name" </dev/null >/dev/null 2>&1; then info "already configured: $name"; return 0; fi
  if claude mcp add --scope user "$@" </dev/null >/dev/null 2>&1; then info "added MCP server: $name"
  else warn "could not add MCP server $name"; fi
}

install_claude_mcp_servers() {
  add_mcp context7 --transport http context7 https://mcp.context7.com/mcp
  add_mcp playwright playwright -- npx @playwright/mcp@latest
  add_mcp chrome-devtools chrome-devtools -- npx -y chrome-devtools-mcp@latest \
    --ignoreDefaultChromeArg=--enable-automation --chromeArg=--disable-blink-features=AutomationControlled
}

configure_git() {
  step "Git identity and SSH key"
  local name email
  if [[ -z "$(git config --global user.name || true)" ]]; then
    ask "Git user name for this machine:" name
    [[ -n "$name" ]] && git config --global user.name "$name" || warn "git user.name is not set"
  fi
  if [[ -z "$(git config --global user.email || true)" ]]; then
    ask "Git email for this machine:" email
    [[ -n "$email" ]] && git config --global user.email "$email" || warn "git user.email is not set"
  fi
  [[ -n "$(git config --global init.defaultBranch || true)" ]] || git config --global init.defaultBranch main
  # Larger buffer and longer timeout so big pushes over HTTPS do not fail.
  git config --global http.postBuffer 524288000
  git config --global http.timeout 300
  # Git reads this path by default; no core.excludesFile setting is needed.
  fetch config/git/ignore "$HOME/.config/git/ignore"

  local key="$HOME/.ssh/id_ed25519"
  if [[ -f "$key" ]]; then
    info "SSH key already exists: $key"
  elif confirm "Generate a new SSH key for this machine?"; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$(git config --global user.email || hostname)" -f "$key" </dev/tty
    if ! grep -q "UseKeychain" "$HOME/.ssh/config" 2>/dev/null; then
      printf 'Host *\n  AddKeysToAgent yes\n  UseKeychain yes\n  IdentityFile ~/.ssh/id_ed25519\n' >>"$HOME/.ssh/config"
      chmod 600 "$HOME/.ssh/config"
    fi
    ssh-add --apple-use-keychain "$key" </dev/tty || true
    info "Public key (add it to GitHub with: gh ssh-key add $key.pub):"
    info "$(cat "$key.pub")"
  fi
}

set_default() { # set_default <domain> <key> <-type> <value>
  defaults write "$1" "$2" "$3" "$4" || warn "could not set $1 $2"
}

dock_add() { # dock_add </path/to/App.app>
  if [[ ! -d "$1" ]]; then info "not installed, left out of the Dock: $(basename "$1" .app)"; return 0; fi
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$1</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
}

configure_macos() {
  step "macOS: keyboard"
  set_default NSGlobalDomain KeyRepeat -int 2
  set_default NSGlobalDomain InitialKeyRepeat -int 15
  set_default NSGlobalDomain AppleKeyboardUIMode -int 2          # Tab moves between all controls
  set_default com.apple.HIToolbox AppleFnUsageType -int 3        # fn key starts dictation
  # Text substitutions corrupt pasted code and commands.
  set_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  set_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  set_default NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  set_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  set_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  set_default NSGlobalDomain WebAutomaticSpellingCorrectionEnabled -bool false

  step "macOS: trackpad and mouse"
  set_default NSGlobalDomain com.apple.swipescrolldirection -bool false   # natural scrolling off
  set_default NSGlobalDomain com.apple.trackpad.scaling -float 1.5        # pointer speed
  # Secondary click with two fingers (built-in and Bluetooth trackpads).
  set_default com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
  set_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true

  step "macOS: appearance, language and windows"
  set_default NSGlobalDomain AppleInterfaceStyle -string Dark
  # English interface with Turkey as the region (dates, numbers, currency).
  defaults write NSGlobalDomain AppleLanguages -array "en-TR" || warn "could not set AppleLanguages"
  set_default NSGlobalDomain AppleLocale -string en_TR
  # Double-clicking a title bar fills the screen instead of minimizing.
  set_default NSGlobalDomain AppleActionOnDoubleClick -string Fill
  set_default NSGlobalDomain AppleMiniaturizeOnDoubleClick -bool false
  set_default com.apple.screencapture show-thumbnail -bool false

  step "macOS: Finder"
  set_default com.apple.finder _FXSortFoldersFirst -bool true
  set_default com.apple.finder FXDefaultSearchScope -string SCcf          # search the current folder
  set_default com.apple.finder FXEnableExtensionChangeWarning -bool false
  set_default com.apple.finder NewWindowTarget -string PfDe               # new windows open Desktop
  set_default com.apple.finder NewWindowTargetPath -string "file://$HOME/Desktop/"
  set_default com.apple.finder ShowHardDrivesOnDesktop -bool false
  set_default com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
  set_default com.apple.finder ShowRemovableMediaOnDesktop -bool false
  set_default NSGlobalDomain AppleShowAllExtensions -bool true
  set_default com.apple.finder AppleShowAllFiles -bool true
  set_default com.apple.finder ShowPathbar -bool true
  set_default com.apple.finder ShowStatusBar -bool true
  set_default com.apple.desktopservices DSDontWriteNetworkStores -bool true
  set_default com.apple.desktopservices DSDontWriteUSBStores -bool true

  step "macOS: Dock"
  set_default com.apple.dock orientation -string bottom
  set_default com.apple.dock autohide -bool false
  set_default com.apple.dock tilesize -int 71
  set_default com.apple.dock magnification -bool true
  set_default com.apple.dock largesize -int 73
  set_default com.apple.dock mineffect -string genie
  set_default com.apple.dock minimize-to-application -bool true
  set_default com.apple.dock show-recents -bool false
  set_default com.apple.dock expose-group-apps -bool true
  set_default com.apple.dock enterMissionControlByTopWindowDrag -bool false
  # Hot corners: bottom-left opens Quick Note, bottom-right shows the desktop.
  set_default com.apple.dock wvous-bl-corner -int 14
  set_default com.apple.dock wvous-bl-modifier -int 0
  set_default com.apple.dock wvous-br-corner -int 4
  set_default com.apple.dock wvous-br-modifier -int 0
  # Replace the Dock's app list. Apps that are not installed are left out.
  defaults write com.apple.dock persistent-apps -array
  defaults write com.apple.dock persistent-others -array
  dock_add "/Applications/Google Chrome.app"
  dock_add "/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app"
  dock_add "/Applications/Spotify.app"
  dock_add "/Applications/iTerm.app"
  dock_add "/Applications/Visual Studio Code.app"

  killall Dock >/dev/null 2>&1 || true
  killall Finder >/dev/null 2>&1 || true

  step "macOS: security"
  if sysadminctl -screenLock status 2>&1 | grep -q "is immediate"; then
    info "screen lock already requires the password immediately"
  else
    info "Requiring the password immediately after the screen locks; macOS asks for your password."
    sysadminctl -screenLock immediate -password - </dev/tty \
      || warn "could not change the screen lock delay (it may be managed by your company)"
  fi

  if grep -Eq '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo_local 2>/dev/null; then
    info "Touch ID for sudo already enabled"
  elif [[ -f /etc/pam.d/sudo_local.template ]]; then
    info "Enabling Touch ID for sudo; you may be asked for your password."
    # sudo_local survives macOS updates, unlike edits to /etc/pam.d/sudo.
    sed -E 's/^#(auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so)/\1/' /etc/pam.d/sudo_local.template \
      | sudo tee /etc/pam.d/sudo_local >/dev/null \
      || warn "could not enable Touch ID for sudo (administrator rights needed)"
  else
    warn "Touch ID for sudo needs macOS 14 or later; skipped"
  fi

  step "macOS: power"
  # Battery: display off after 10 min, sleep after 1. Power adapter: display off after 60 min, never sleep.
  sudo pmset -b displaysleep 10 sleep 1 || warn "could not set battery power settings"
  sudo pmset -c displaysleep 60 sleep 0 || warn "could not set power adapter settings"
}

verify() {
  step "Verification"
  export PATH="$HOME/.local/bin:${HOMEBREW_PREFIX:-/opt/homebrew}/opt/libpq/bin:$PATH"
  local c v
  for c in brew git gh psql code claude codex; do
    if have "$c"; then
      v="$("$c" --version 2>/dev/null | head -1)"
      printf '    \033[32mok\033[0m       %-7s %s\n' "$c" "$v"
    else
      printf '    \033[31mmissing\033[0m  %s\n' "$c"
    fi
  done
  for c in nvm node pnpm nest; do
    if v="$(with_nvm "$c" --version 2>/dev/null | head -1)" && [[ -n "$v" ]]; then
      printf '    \033[32mok\033[0m       %-7s %s\n' "$c" "$v"
    else
      printf '    \033[31mmissing\033[0m  %s\n' "$c"
    fi
  done

  if [[ -n "$WARNINGS" ]]; then
    printf '\n\033[1;33mWarnings:\033[0m\n%s' "$WARNINGS"
  fi
  cat <<'EOF'

Left for you to do by hand:
  1. Open a new iTerm2 window so the new shell config loads.
  2. Open OrbStack once to finish its setup; PostgreSQL runs from each
     project's docker-compose file.
  3. Sign in:  gh auth login   |   claude   |   codex
  4. Put machine-specific exports and secrets in ~/.zshrc.local
  5. Log out and back in so the keyboard, trackpad, appearance and language
     settings take effect.
  6. Make Chrome the default browser: System Settings > Desktop & Dock >
     Default web browser.
EOF
}

main() {
  REF="${1:-}"
  FAILED_CASKS="$(mktemp)"
  trap 'rm -f "$FAILED_CASKS"' EXIT
  preflight
  install_homebrew
  install_packages
  install_shell
  install_node
  configure_iterm
  configure_vscode
  install_agents
  configure_claude
  configure_git
  configure_macos
  verify
}

# Calling main on the last line means a truncated download runs nothing.
# The guard lets the file be sourced for testing without running the install.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
