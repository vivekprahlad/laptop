#!/bin/sh
# Personal environment setup: Claude Code, the citypaul/.dotfiles Claude config
# (CLAUDE.md + skills + commands + agents), Pencil (pencil.dev),
# Starship, MesloLGS NF font, tmux (config + Catppuccin plugin), Hammerspoon
# config, iTerm2 colours/settings, a clean ~/.zshrc, a global git config, the
# context-mode Claude Code plugin, the Trail of Bits Claude Code config, and
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

# 9. Global git config (generic — per-context identity is added in step 14)
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
# it after nWave so citypaul's CLAUDE.md/commands/agents win — but note that
# `npx skills` snapshots ~/.claude/skills/ and re-materializes ONLY its tracked
# set, which DELETES nWave's skills installed in step 10. Step 11b re-applies
# nWave to restore them. Guarded so a network/npx failure doesn't abort setup.
say "Installing citypaul/.dotfiles Claude config ..."
if curl -fsSL https://raw.githubusercontent.com/citypaul/.dotfiles/main/install-claude.sh | bash; then
  echo "  citypaul Claude config installed"
else
  echo "  WARNING: citypaul Claude config install failed; continuing"
fi

# 11b. Re-apply nWave skills clobbered by step 11's `npx skills`.
# `npx skills` owns ~/.claude/skills/ and drops anything outside its tracked set,
# including the nWave skills installed in step 10. Re-running the nWave installer
# re-materializes them so both skill sets coexist. Idempotent; guarded.
if command -v nwave-ai >/dev/null 2>&1; then
  say "Re-applying nWave skills (clobbered by npx skills in step 11) ..."
  nwave-ai install || echo "  WARNING: nWave re-apply failed; run 'nwave-ai install' manually"
fi

# 11c. Document the nWave/skills.sh clobber in ~/.claude/CLAUDE.md so a fresh
# provision carries the guidance forward. Runs after citypaul (step 11) rewrites
# CLAUDE.md, so the note re-applies on every provision. Idempotent via a marker.
say "Adding nWave/skills.sh guard to ~/.claude/CLAUDE.md ..."
nwave_guard_marker="nWave + skills.sh ownership guard"
claude_md="$HOME/.claude/CLAUDE.md"
if [ -f "$claude_md" ] && grep -qF "$nwave_guard_marker" "$claude_md"; then
  echo "  guard already present; skipping"
else
  mkdir -p "$HOME/.claude"
  cat >> "$claude_md" <<'EOF'

<!-- >>> nWave + skills.sh ownership guard (added by laptop setup; edit or remove freely) >>> -->
> ⚠️ **`npx skills` and the nWave installer both own `~/.claude/skills/`.** `npx skills add ...` snapshots that directory (to `skills.pre-skills-sh.<timestamp>`) and re-materializes ONLY its tracked set, which **deletes nWave's `nw-*` skills**. If nWave skills go missing after any skills.sh run, restore them with: `nwave-ai install`. The provisioning repo (`setup/install.sh` step 11b) already re-applies nWave after its `npx skills` step.
EOF
  echo "  appended guard to CLAUDE.md"
fi

# 12. context-mode Claude Code plugin (mksglu/context-mode)
# MCP server that keeps raw tool output out of the context window and tracks
# session state in SQLite. Installed via the Claude Code plugin marketplace.
# Guarded and idempotent: skips the marketplace add / plugin install if already
# present, and a failure here doesn't abort the remaining setup.
say "Installing context-mode Claude Code plugin ..."
if command -v claude >/dev/null 2>&1; then
  if claude plugin marketplace list 2>/dev/null | grep -q 'context-mode'; then
    echo "  context-mode marketplace already added; skipping"
  else
    claude plugin marketplace add mksglu/context-mode || \
      echo "  WARNING: failed to add context-mode marketplace; continuing"
  fi
  if claude plugin list 2>/dev/null | grep -q 'context-mode'; then
    echo "  context-mode plugin already installed; skipping"
  else
    claude plugin install context-mode@context-mode || \
      echo "  WARNING: failed to install context-mode plugin; continuing"
  fi
else
  echo "  claude not found; skipping context-mode plugin"
fi

# 13. Trail of Bits Claude Code config (trailofbits/claude-code-config)
# Opinionated security-focused defaults. Scripted non-destructively: prerequisite
# CLI tools, a jq merge of ToB's keys into the existing settings.json (preserving
# the nWave hooks + PATH), the statusline script, the review-pr/fix-issue
# commands, and ToB's global standards APPENDED (not overwritten) to CLAUDE.md.
# Runs after citypaul (step 11) so the CLAUDE.md append lands on the final file
# and re-applies on every provision. Guarded so any failure continues the setup.
tob_base="https://raw.githubusercontent.com/trailofbits/claude-code-config/main"

say "Installing Trail of Bits prerequisite tools ..."
for f in ast-grep shellcheck shfmt actionlint zizmor macos-trash ripgrep fd pnpm; do
  brew install "$f" || echo "  WARNING: brew install $f failed; continuing"
done
if command -v uv >/dev/null 2>&1; then
  for t in ruff ty pip-audit; do
    uv tool install "$t" || echo "  WARNING: uv tool install $t failed; continuing"
  done
else
  echo "  uv not found; skipping ruff/ty/pip-audit"
fi
if command -v cargo >/dev/null 2>&1; then
  cargo install cargo-deny || echo "  WARNING: cargo install cargo-deny failed; continuing"
else
  echo "  cargo (Rust toolchain) not found; skipping cargo-deny"
fi
if command -v npm >/dev/null 2>&1; then
  npm install -g oxlint agent-browser || echo "  WARNING: npm global install failed; continuing"
else
  echo "  npm not found; skipping oxlint/agent-browser"
fi

say "Installing Trail of Bits statusline + commands ..."
mkdir -p "$HOME/.claude/commands"
if curl -fsSL "$tob_base/scripts/statusline.sh" -o "$HOME/.claude/statusline.sh"; then
  chmod +x "$HOME/.claude/statusline.sh"
  echo "  installed ~/.claude/statusline.sh"
else
  echo "  WARNING: failed to fetch statusline.sh; continuing"
fi
for cmd in review-pr fix-issue; do
  curl -fsSL "$tob_base/commands/$cmd.md" -o "$HOME/.claude/commands/$cmd.md" \
    && echo "  installed ~/.claude/commands/$cmd.md" \
    || echo "  WARNING: failed to fetch $cmd.md; continuing"
done

say "Merging Trail of Bits keys into ~/.claude/settings.json ..."
tob_settings="$(mktemp)"
if curl -fsSL "$tob_base/settings.json" -o "$tob_settings"; then
  settings="$HOME/.claude/settings.json"
  if [ ! -f "$settings" ]; then
    mkdir -p "$HOME/.claude"
    cp "$tob_settings" "$settings"
    echo "  wrote settings.json (none existed)"
  elif command -v jq >/dev/null 2>&1; then
    merged="$(mktemp)"
    # Set ToB's opinionated scalars + statusLine; union the deny rules; merge env
    # with existing keys winning (preserves PATH); strip any previously-injected
    # ToB Bash guard hooks (by message) then re-append, so re-runs don't stack.
    # The "not direct push to main" guard is dropped on re-append: this is a
    # personal repo where pushing straight to main is the intended workflow.
    if jq --slurpfile tob "$tob_settings" '
        ($tob[0]) as $t
        | .cleanupPeriodDays = $t.cleanupPeriodDays
        | .enableAllProjectMcpServers = $t.enableAllProjectMcpServers
        | .alwaysThinkingEnabled = $t.alwaysThinkingEnabled
        | .statusLine = $t.statusLine
        | .env = (($t.env // {}) + (.env // {}))
        | .permissions = (.permissions // {})
        | .permissions.deny = (((.permissions.deny // []) + ($t.permissions.deny // [])) | unique)
        | .hooks = (.hooks // {})
        | .hooks.PreToolUse = (
            ((.hooks.PreToolUse // []) | map(select(
              (([.hooks[]?.command] | join(" "))) as $c
              | (((($c | test("Use trash instead of rm -rf"))) or (($c | test("not direct push to main"))))) | not
            )))
            + (($t.hooks.PreToolUse // []) | map(select(
              (([.hooks[]?.command] | join(" "))) as $c
              | ($c | test("not direct push to main")) | not
            )))
          )
      ' "$settings" > "$merged" 2>/dev/null; then
      mv "$merged" "$settings"
      echo "  merged Trail of Bits keys into settings.json"
    else
      rm -f "$merged"
      echo "  WARNING: settings.json merge failed; left unchanged"
    fi
  else
    echo "  jq not found; skipping settings.json merge"
  fi
else
  echo "  WARNING: failed to fetch Trail of Bits settings.json; continuing"
fi
rm -f "$tob_settings"

say "Appending Trail of Bits standards to ~/.claude/CLAUDE.md ..."
tob_md_marker="Trail of Bits global standards (appended by laptop setup"
claude_md="$HOME/.claude/CLAUDE.md"
if [ -f "$claude_md" ] && grep -qF "$tob_md_marker" "$claude_md"; then
  echo "  Trail of Bits section already present; skipping"
else
  tob_md="$(mktemp)"
  if curl -fsSL "$tob_base/claude-md-template.md" -o "$tob_md"; then
    {
      printf '\n\n---\n\n<!-- >>> %s; edit or remove freely) >>> -->\n\n' "$tob_md_marker"
      cat "$tob_md"
    } >> "$claude_md"
    echo "  appended Trail of Bits standards to CLAUDE.md"
  else
    echo "  WARNING: failed to fetch claude-md-template.md; continuing"
  fi
  rm -f "$tob_md"
fi

# 14. SSH/git identities from the private 1Password manifest
sh "$SCRIPT_DIR/provision-identities.sh"

say "Personal setup complete."
