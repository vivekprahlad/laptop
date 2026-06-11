#!/bin/sh
# Add a new GitHub (or other host) account/identity to the setup.
#
# Generates (or reuses) an SSH key in 1Password, appends the context to the
# private manifest, optionally uploads the public key to GitHub via gh (as BOTH
# an authentication and a signing key), then re-provisions local config.
#
# Generic + public-repo-safe: there is NO structure in this file. Everything you
# enter goes into the private 1Password manifest, never here.
#
# Usage:
#   setup/add-github-account.sh [--dir DIR] [--email EMAIL] [--name NAME]
#                               [--vault VAULT] [--host HOST]
#                               [--existing "ITEM TITLE"] [--no-github]
#
# Any value not passed as a flag is prompted for. Requires: op (signed in) + jq;
# gh (signed in to the target account) for the optional GitHub upload.

set -e

MANIFEST_TITLE="dotfiles ssh+git manifest"
MANIFEST_VAULT="Private"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }
prompt() { # prompt "message" "default" -> echoes the answer (message goes to stderr)
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2" >&2; else printf '%s: ' "$1" >&2; fi
  read -r _ans || true
  [ -z "$_ans" ] && _ans="$2"
  printf '%s' "$_ans"
}

dir=""; email=""; name=""; vault=""; host=""; existing=""; do_github=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2;;
    --email) email="$2"; shift 2;;
    --name) name="$2"; shift 2;;
    --vault) vault="$2"; shift 2;;
    --host) host="$2"; shift 2;;
    --existing) existing="$2"; shift 2;;
    --no-github) do_github=0; shift;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "unknown argument: $1 (try --help)";;
  esac
done

command -v op >/dev/null 2>&1 || die "1Password CLI (op) not found"
command -v jq >/dev/null 2>&1 || die "jq not found"
op whoami >/dev/null 2>&1 || die "not signed in to op (run: eval \$(op signin))"

[ -n "$dir" ]   || dir="$(prompt "Work directory under ~/Work (e.g. acme or acme/web)" "")"
[ -n "$email" ] || email="$(prompt "Git email for this account" "")"
[ -n "$name" ]  || name="$(prompt "Friendly name (used for the 1Password item + key filename)" "")"
[ -n "$host" ]  || host="$(prompt "Git host" "github.com")"
[ -n "$vault" ] || vault="$(prompt "1Password vault for the key" "Private")"
[ -n "$dir" ] && [ -n "$email" ] && [ -n "$name" ] || die "dir, email and name are required"

# Derive a filesystem-safe key filename from the friendly name and host.
hostshort=$(printf '%s' "$host" | sed 's/\..*//')
slug=$(printf '%s' "$name" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_-')
pub="${slug}_${hostshort}_key.pub"

# 1. SSH key item in 1Password
if [ -n "$existing" ]; then
  item="$existing"
  say "Using existing 1Password item: $item (vault $vault)"
else
  item="SSH Key - $name"
  say "Generating ed25519 SSH key in 1Password: $item (vault $vault)"
  op item create --category "SSH Key" --title "$item" --vault "$vault" --ssh-generate-key=Ed25519 >/dev/null
fi

pubkey="$(op item get "$item" --vault "$vault" --format json \
  | jq -r '.fields[] | select(.id=="public_key") | .value')"
[ -n "$pubkey" ] || die "could not read public key for '$item' in vault '$vault'"

# 2. Append the context to the private manifest (and the agent key list)
say "Adding context '$dir' to the 1Password manifest ..."
new_manifest="$(op document get "$MANIFEST_TITLE" --vault "$MANIFEST_VAULT" \
  | jq --arg dir "$dir" --arg vault "$vault" --arg item "$item" --arg email "$email" --arg pub "$pub" '
      .contexts += [{dir:$dir, vault:$vault, item:$item, email:$email, pub:$pub}]
      | .agent_keys += [{vault:$vault, item:$item}]
      | .agent_keys |= unique')"
printf '%s' "$new_manifest" | op document edit "$MANIFEST_TITLE" - --vault "$MANIFEST_VAULT"

# 3. Upload the public key to GitHub (auth + signing)
if [ "$do_github" -eq 1 ] && [ "$host" = "github.com" ]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    say "Uploading public key to the active GitHub account ..."
    printf '  Uploading to the CURRENTLY active gh account. Run "gh auth switch"\n'
    printf '  first if that is wrong, then re-run. (Ctrl-C to abort.)\n'
    tmp="$(mktemp)"; printf '%s\n' "$pubkey" > "$tmp"
    gh ssh-key add "$tmp" --title "$host $name (auth)"    --type authentication || echo "  auth-key upload skipped/failed"
    gh ssh-key add "$tmp" --title "$host $name (signing)" --type signing        || echo "  signing-key upload skipped/failed"
    rm -f "$tmp"
  else
    say "gh not installed or not signed in — add this key to the account manually"
    printf '  (Settings -> SSH and GPG keys, as BOTH an authentication and a signing key):\n\n%s\n' "$pubkey"
  fi
fi

# 4. Re-provision local config from the updated manifest
say "Re-provisioning local config from the manifest ..."
sh "$SCRIPT_DIR/provision-identities.sh"

say "Done. New context: ~/Work/$dir  (key item: $item)"
printf 'Verify with:  cd ~/Work/%s && ssh -T git@%s\n' "$dir" "$host"
