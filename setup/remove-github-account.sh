#!/bin/sh
# Remove a context/account from the setup — the inverse of add-github-account.sh.
#
# Removes the context from the private 1Password manifest, deletes its local
# ~/Work/<dir>/.gitconfig (and ~/.ssh/<pub> if no other context uses the same
# key), then re-provisions. By default it is non-destructive to 1Password and
# GitHub. Optional, and only when no other context shares the key:
#   --delete-key  also delete the 1Password SSH Key item
#   --github      also remove the key (auth + signing) from the active gh account
#
# Generic + public-repo-safe: no structure here; the context list lives in the
# private 1Password manifest.
#
# Usage:
#   setup/remove-github-account.sh [--dir DIR] [--delete-key] [--github]
# A missing DIR is prompted for. Requires: op (signed in) + jq; gh for --github.

set -e

MANIFEST_TITLE="dotfiles ssh+git manifest"
MANIFEST_VAULT="Private"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }
prompt() {
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2" >&2; else printf '%s: ' "$1" >&2; fi
  read -r _ans || true
  [ -z "$_ans" ] && _ans="$2"
  printf '%s' "$_ans"
}

dir=""; delete_key=0; do_github=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2;;
    --delete-key) delete_key=1; shift;;
    --github) do_github=1; shift;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "unknown argument: $1 (try --help)";;
  esac
done

command -v op >/dev/null 2>&1 || die "1Password CLI (op) not found"
command -v jq >/dev/null 2>&1 || die "jq not found"
op whoami >/dev/null 2>&1 || die "not signed in to op (run: eval \$(op signin))"

[ -n "$dir" ] || dir="$(prompt "Work directory under ~/Work to remove" "")"
[ -n "$dir" ] || die "a directory is required"

manifest="$(op document get "$MANIFEST_TITLE" --vault "$MANIFEST_VAULT")"
ctx="$(printf '%s' "$manifest" | jq -c --arg d "$dir" '.contexts[] | select(.dir==$d)')"
[ -n "$ctx" ] || die "no context '$dir' found in the manifest"

vault="$(printf '%s' "$ctx" | jq -r '.vault')"
item="$(printf '%s' "$ctx" | jq -r '.item')"
pub="$(printf '%s' "$ctx" | jq -r '.pub')"

# Is the same key used by any OTHER context? If so, protect it from deletion.
others="$(printf '%s' "$manifest" | jq --arg d "$dir" --arg v "$vault" --arg i "$item" \
  '[.contexts[] | select(.dir != $d and .vault == $v and .item == $i)] | length')"
shared=0; [ "$others" -gt 0 ] && shared=1

say "Removing context '$dir' (key item: $item, vault: $vault)"
[ "$shared" -eq 1 ] && echo "  note: key shared by $others other context(s) — it will be kept everywhere"

# 1. Update the manifest: drop the context; drop the agent key only if unshared.
new_manifest="$(printf '%s' "$manifest" \
  | jq --arg d "$dir" --arg v "$vault" --arg i "$item" --argjson shared "$shared" '
      .contexts |= map(select(.dir != $d))
      | if $shared == 0 then .agent_keys |= map(select(.vault != $v or .item != $i)) else . end')"
printf '%s' "$new_manifest" | op document edit "$MANIFEST_TITLE" - --vault "$MANIFEST_VAULT"
echo "  manifest updated"

# 2. Remove local files (the dir itself is left in place — it may hold repos).
if [ -f "$HOME/Work/$dir/.gitconfig" ]; then
  rm -f "$HOME/Work/$dir/.gitconfig"
  echo "  removed ~/Work/$dir/.gitconfig"
fi
if [ "$shared" -eq 0 ] && [ -f "$HOME/.ssh/$pub" ]; then
  rm -f "$HOME/.ssh/$pub"
  echo "  removed ~/.ssh/$pub"
fi

# 3. GitHub removal (opt-in, unshared only).
pubkey="$(op item get "$item" --vault "$vault" --format json \
  | jq -r '.fields[] | select(.id=="public_key") | .value' 2>/dev/null || true)"
keybody="$(printf '%s' "$pubkey" | awk '{print $2}')"
if [ "$do_github" -eq 1 ]; then
  if [ "$shared" -eq 1 ]; then
    echo "  skipping GitHub removal: key still used by another context"
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && [ -n "$keybody" ]; then
    say "Removing key from the active GitHub account ..."
    echo "  (acting on the CURRENTLY active gh account; run 'gh auth switch' first if wrong)"
    for ep in user/keys user/ssh_signing_keys; do
      ids="$(gh api "$ep" --jq ".[] | select(.key | contains(\"$keybody\")) | .id" 2>/dev/null || true)"
      for id in $ids; do
        if gh api -X DELETE "$ep/$id" >/dev/null 2>&1; then echo "    deleted $ep/$id"; else echo "    failed to delete $ep/$id"; fi
      done
    done
  else
    echo "  gh not ready — remove this key from GitHub manually (auth + signing):"
    printf '\n%s\n' "$pubkey"
  fi
fi

# 4. Delete the 1Password key item (opt-in, unshared only).
if [ "$delete_key" -eq 1 ]; then
  if [ "$shared" -eq 1 ]; then
    echo "  skipping 1Password key deletion: still used by another context"
  elif op item delete "$item" --vault "$vault"; then
    echo "  deleted 1Password item: $item"
  else
    echo "  WARNING: failed to delete 1Password item '$item'"
  fi
fi

# 5. Re-provision (regenerates work-includes / agent.toml / allowed_signers).
say "Re-provisioning local config ..."
sh "$SCRIPT_DIR/provision-identities.sh"

say "Done. Removed context '$dir' (the ~/Work/$dir directory was left in place)."
