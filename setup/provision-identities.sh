#!/bin/sh
# Provision SSH/git identities from a private manifest stored in 1Password.
#
# This script is generic and safe in a public repo: it contains NO directory
# names, keys, or emails. All of that lives in a 1Password document (title below)
# that maps each ~/Work/<context> to a 1Password SSH Key item + email.
#
# It generates, all LOCAL and never committed:
#   ~/.ssh/<pub>                         public key, pulled from 1Password
#   ~/Work/<dir>/.gitconfig              email + signingkey + core.sshCommand
#   ~/.config/git/work-includes          one includeIf per context
#   ~/.config/git/allowed_signers        email -> public key (for verification)
#   ~/.config/1Password/ssh/agent.toml   keys the 1Password agent should offer
#   ~/.ssh/config                        agent routing (per-repo keys via git)
#
# Requires: op (signed in) and jq. Skips gracefully if either is unavailable.

set -e

MANIFEST_TITLE="dotfiles ssh+git manifest"
MANIFEST_VAULT="Private"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

command -v op >/dev/null 2>&1 || { say "Skipping identity provisioning: 1Password CLI (op) not found"; exit 0; }
command -v jq >/dev/null 2>&1 || { say "Skipping identity provisioning: jq not found"; exit 0; }
op whoami >/dev/null 2>&1 || { say "Skipping identity provisioning: not signed in to op (run: eval \$(op signin))"; exit 0; }

say "Provisioning SSH/git identities from 1Password ..."
manifest="$(op document get "$MANIFEST_TITLE" --vault "$MANIFEST_VAULT" 2>/dev/null)" || {
  say "Manifest '$MANIFEST_TITLE' not found in 1Password; skipping"; exit 0; }

mkdir -p "$HOME/.ssh" "$HOME/.config/git" "$HOME/.config/1Password/ssh"
chmod 700 "$HOME/.ssh"

work_includes="$HOME/.config/git/work-includes"
allowed_signers="$HOME/.config/git/allowed_signers"
agent_toml="$HOME/.config/1Password/ssh/agent.toml"
: > "$work_includes"
: > "$allowed_signers"
: > "$agent_toml"

# ~/.ssh/config: route all auth through the 1Password agent. There is NO
# directory/host key selection here — git pins the right key per repo via
# core.sshCommand (written per context below).
agent_socket=$(echo "$manifest" | jq -r '.agent_socket')
[ -e "$HOME/.ssh/config" ] && mv "$HOME/.ssh/config" "$HOME/.ssh/config.backup.$(date +%Y-%m-%d_%H-%M-%S)"
{
  printf '# Managed by setup/provision-identities.sh — do not edit by hand.\n'
  printf 'Include ~/.orbstack/ssh/config\n\n'
  printf 'Host *\n\tIdentityAgent "%s"\n' "$agent_socket"
} > "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"

# Per context: pull the public key, write the per-dir .gitconfig, the includeIf,
# and an allowed_signers line. Contexts are listed parents-first so a nested
# context (e.g. org/sub) overrides its parent (last include wins).
echo "$manifest" | jq -c '.contexts[]' | while IFS= read -r ctx; do
  dir=$(printf '%s' "$ctx"   | jq -r '.dir')
  vault=$(printf '%s' "$ctx" | jq -r '.vault')
  item=$(printf '%s' "$ctx"  | jq -r '.item')
  email=$(printf '%s' "$ctx" | jq -r '.email')
  pub=$(printf '%s' "$ctx"   | jq -r '.pub')

  # Fetch the public key via `op item get` (title/vault as args) rather than an
  # op:// reference, so item titles with '@' or spaces resolve correctly.
  pubkey="$(op item get "$item" --vault "$vault" --format json \
    | jq -r '.fields[] | select(.id=="public_key") | .value')"
  if [ -z "$pubkey" ]; then
    echo "  ERROR: no public key for item '$item' in vault '$vault'" >&2
    exit 1
  fi
  printf '%s\n' "$pubkey" > "$HOME/.ssh/$pub"
  chmod 644 "$HOME/.ssh/$pub"

  mkdir -p "$HOME/Work/$dir"
  {
    printf '[user]\n\temail = %s\n\tsigningkey = ~/.ssh/%s\n' "$email" "$pub"
    printf '[core]\n\tsshCommand = ssh -i ~/.ssh/%s -o IdentitiesOnly=yes\n' "$pub"
  } > "$HOME/Work/$dir/.gitconfig"

  printf '[includeIf "gitdir:~/Work/%s/"]\n\tpath = ~/Work/%s/.gitconfig\n' "$dir" "$dir" >> "$work_includes"
  printf '%s %s\n' "$email" "$(awk '{print $1" "$2}' "$HOME/.ssh/$pub")" >> "$allowed_signers"
  echo "  context: $dir"
done

# Contexts can share an email/key (e.g. github + learning) -> de-duplicate.
sort -u "$allowed_signers" -o "$allowed_signers"

# agent.toml: the keys the 1Password SSH agent should offer.
echo "$manifest" | jq -r '.agent_keys[] | "[[ssh-keys]]\nvault = \"\(.vault)\"\nitem = \"\(.item)\"\n"' > "$agent_toml"

say "Identity provisioning complete."
