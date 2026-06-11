#!/bin/sh
# Import an existing SSH private key into 1Password as an SSH Key item.
# 1Password derives the public key automatically. Afterwards you can wire it
# into a context with: setup/add-github-account.sh --existing "<title>"
#
# Generic + public-repo-safe: no structure here.
#
# Usage:
#   setup/import-ssh-key.sh [--file PATH] [--title TITLE] [--vault VAULT]
# Missing values are prompted for. Requires: op (signed in) + jq.

set -e

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }
prompt() {
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2" >&2; else printf '%s: ' "$1" >&2; fi
  read -r _ans || true
  [ -z "$_ans" ] && _ans="$2"
  printf '%s' "$_ans"
}

file=""; title=""; vault=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="$2"; shift 2;;
    --title) title="$2"; shift 2;;
    --vault) vault="$2"; shift 2;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "unknown argument: $1 (try --help)";;
  esac
done

command -v op >/dev/null 2>&1 || die "1Password CLI (op) not found"
command -v jq >/dev/null 2>&1 || die "jq not found"
op whoami >/dev/null 2>&1 || die "not signed in to op (run: eval \$(op signin))"

[ -n "$file" ] || file="$(prompt "Path to the SSH PRIVATE key file" "$HOME/.ssh/id_ed25519")"
# shellcheck disable=SC2088  # intentionally matching a literal, unexpanded "~/"
case "$file" in "~/"*) file="$HOME/${file#\~/}";; esac
[ -f "$file" ] || die "file not found: $file"
grep -q "PRIVATE KEY" "$file" || die "$file does not look like a private key (no 'PRIVATE KEY' header) — point at the private key, not the .pub"

[ -n "$title" ] || title="$(prompt "1Password item title" "SSH Key - imported")"
[ -n "$vault" ] || vault="$(prompt "1Password vault" "Private")"

say "Importing '$file' into 1Password as '$title' (vault $vault) ..."
op item template get "SSH Key" \
  | jq --arg t "$title" --rawfile k "$file" \
      '.title = $t | (.fields[] | select(.id == "private_key")).value = $k' \
  | op item create --vault "$vault" - >/dev/null

# Read back the public key 1Password derived, as confirmation.
pubkey="$(op item get "$title" --vault "$vault" --format json \
  | jq -r '.fields[] | select(.id == "public_key") | .value' 2>/dev/null || true)"
[ -n "$pubkey" ] || die "import appears to have failed: no public key for '$title' in vault '$vault'"

say "Imported. 1Password derived this public key:"
printf '%s\n' "$pubkey"
printf '\nWire it into a context with:\n  setup/add-github-account.sh --existing "%s" --vault "%s" --dir <work-dir> --email <email>\n' "$title" "$vault"
