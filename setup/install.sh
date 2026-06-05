#!/bin/sh
# Personal environment setup: Claude Code, the citypaul/.dotfiles Claude config
# (CLAUDE.md + skills + commands + agents), Pencil (pencil.dev),
# Starship, MesloLGS NF font, tmux (config + Catppuccin plugin), Hammerspoon
# config, iTerm2 colours/settings, a clean ~/.zshrc, a global git config, and
# SSH/git identities provisioned from 1Password.
#
# Idempotent and non-destructive: each step skips work already done and backs up
# anything it replaces (as <file>.backup.<timestamp>). Safe to re-run.
#
# Invoked automatically from laptop.local, or run directly: sh setup/install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say() { printf "\n\033[1m%s\033[0m\n" "$1"; }

backup() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    ts="$(date +%Y-%m-%d_%H-%M-%S)"
    mv "$1" "$1.backup.$ts"
    echo "  backed up $1 -> $1.backup.$ts"
  fi
}

# 1. Claude Code (official native installer -> ~/.local/bin/claude)
say "Installing Claude Code ..."
if command -v claude >/dev/null 2>&1; then
  echo "  claude already installed; skipping"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

# 2. Starship prompt + config
say "Installing & configuring Starship ..."
if ! command -v starship >/dev/null 2>&1; then
  brew install starship
fi
mkdir -p "$HOME/.config"
backup "$HOME/.config/starship.toml"
cp "$SCRIPT_DIR/starship/starship.toml" "$HOME/.config/starship.toml"

# 3. MesloLGS NF font (Powerlevel10k's Nerd Font) from the canonical source
say "Installing MesloLGS NF font ..."
font_dir="$HOME/Library/Fonts"
font_base="https://github.com/romkatv/powerlevel10k-media/raw/master"
mkdir -p "$font_dir"
for face in "Regular" "Bold" "Italic" "Bold Italic"; do
  target="$font_dir/MesloLGS NF $face.ttf"
  if [ -f "$target" ]; then
    echo "  MesloLGS NF $face already present; skipping"
  else
    echo "  downloading MesloLGS NF $face"
    url_face="$(printf '%s' "$face" | sed 's/ /%20/g')"
    curl -fsSL "$font_base/MesloLGS%20NF%20$url_face.ttf" -o "$target"
  fi
done
[ -f "$font_dir/MesloLGS NF License.txt" ] || \
  curl -fsSL "$font_base/MesloLGS%20NF%20License.txt" -o "$font_dir/MesloLGS NF License.txt"

# 4. tmux config + Catppuccin plugin (tmux/tmuxinator are installed via the brew bundle)
say "Configuring tmux ..."
cat_dir="$HOME/.config/tmux/plugins/catppuccin/tmux"
if [ -d "$cat_dir" ]; then
  echo "  Catppuccin tmux plugin already present; skipping"
else
  echo "  installing Catppuccin tmux plugin"
  mkdir -p "$(dirname "$cat_dir")"
  git clone -b latest --depth 1 https://github.com/catppuccin/tmux.git "$cat_dir"
fi
backup "$HOME/.tmux.conf"
cp "$SCRIPT_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"

# 5. iTerm2 colours & settings
say "Importing iTerm2 settings ..."
iterm_plist="$SCRIPT_DIR/iterm/com.googlecode.iterm2.plist"
if [ -f "$iterm_plist" ]; then
  if pgrep -x iTerm2 >/dev/null 2>&1; then
    echo "  WARNING: iTerm2 is running. Quit it and re-run, or it may overwrite these settings on quit."
  fi
  backup "$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  defaults import com.googlecode.iterm2 "$iterm_plist"
  echo "  imported (restart iTerm2 to apply)"
else
  echo "  no iTerm plist found in repo; skipping"
fi

# 6. Clean ~/.zshrc
say "Installing clean ~/.zshrc ..."
backup "$HOME/.zshrc"
cp "$SCRIPT_DIR/zsh/zshrc" "$HOME/.zshrc"
echo "  installed (restart your shell to apply)"

# 7. Pencil design app (pencil.dev — no Homebrew cask, install from DMG)
say "Installing Pencil (pencil.dev) ..."
if [ -d "/Applications/Pencil.app" ]; then
  echo "  Pencil already installed; skipping"
else
  if [ "$(uname -m)" = "arm64" ]; then
    pencil_url="https://pencil.dev/download/Pencil-mac-arm64.dmg"
  else
    pencil_url="https://pencil.dev/download/Pencil-mac-x64.dmg"
  fi
  pencil_dmg="$(mktemp -d)/Pencil.dmg"
  pencil_mnt="$(mktemp -d)"
  echo "  downloading $pencil_url"
  curl -fsSL "$pencil_url" -o "$pencil_dmg"
  hdiutil attach "$pencil_dmg" -nobrowse -quiet -mountpoint "$pencil_mnt"
  pencil_app="$(find "$pencil_mnt" -maxdepth 1 -name '*.app' -print | head -1)"
  if [ -n "$pencil_app" ]; then
    cp -R "$pencil_app" /Applications/
    echo "  installed to /Applications/Pencil.app"
  else
    echo "  WARNING: no .app found inside the Pencil DMG"
  fi
  hdiutil detach "$pencil_mnt" -quiet
  rm -f "$pencil_dmg"
fi

# 8. Hammerspoon config (the Hammerspoon app is installed via the brew bundle)
say "Configuring Hammerspoon ..."
if [ -d "$SCRIPT_DIR/hammerspoon" ]; then
  backup "$HOME/.hammerspoon"
  mkdir -p "$HOME/.hammerspoon"
  cp -R "$SCRIPT_DIR/hammerspoon/." "$HOME/.hammerspoon/"
  echo "  installed ~/.hammerspoon"
fi

# 9. Global git config (generic — per-context identity is added in step 10)
say "Installing global git config ..."
backup "$HOME/.gitconfig"
cp "$SCRIPT_DIR/git/gitconfig" "$HOME/.gitconfig"
echo "  installed ~/.gitconfig"

# 10. nWave — AI coding agents wired into Claude Code (uv is in the brew bundle)
say "Installing nWave (nwave-ai) ..."
if command -v uv >/dev/null 2>&1; then
  if uv tool list 2>/dev/null | grep -q '^nwave-ai '; then
    echo "  nwave-ai already installed; skipping"
  else
    uv tool install nwave-ai
  fi
  # Wire nWave into Claude Code (idempotent; safe to re-run)
  if command -v nwave-ai >/dev/null 2>&1; then
    nwave-ai install
  fi
else
  echo "  uv not found; skipping nWave (install uv via the brew bundle first)"
fi

# 11. citypaul/.dotfiles Claude config (CLAUDE.md + skills + commands + agents)
# Runs the upstream one-liner installer. Skills are fetched via `npx skills`
# (Node is installed earlier by the mac script), and CLAUDE.md/commands/agents
# are downloaded directly. The installer backs up anything it replaces. We run
# it after nWave so this config has the final say in ~/.claude. Guarded so a
# network/npx failure doesn't abort the remaining setup.
say "Installing citypaul/.dotfiles Claude config ..."
if curl -fsSL https://raw.githubusercontent.com/citypaul/.dotfiles/main/install-claude.sh | bash; then
  echo "  citypaul Claude config installed"
else
  echo "  WARNING: citypaul Claude config install failed; continuing"
fi

# 12. SSH/git identities from the private 1Password manifest
sh "$SCRIPT_DIR/provision-identities.sh"

say "Personal setup complete."
