# Machine setup

A walkthrough for provisioning a new Mac with this repo.

Your SSH **private keys live only in 1Password**. Everything identity-related on
the machine (public keys, per-directory git config, the SSH config, the agent
config) is **generated** from a private 1Password document, so nothing secret or
personal is committed to this repo.

## How it works

- **1Password holds the secrets** — your SSH keys (as *SSH Key* items) plus a
  private document, **`dotfiles ssh+git manifest`**, that maps each
  `~/Work/<context>` directory to a key + git email.
- **This repo is generic** — scripts and a no-identity global `gitconfig`. It
  contains no directory names, keys, or emails.
- **The provisioner generates the rest locally** (never committed):
  `~/.ssh/<key>.pub`, `~/.ssh/config`, `~/Work/<dir>/.gitconfig`,
  `~/.config/git/work-includes`, `~/.config/git/allowed_signers`, and
  `~/.config/1Password/ssh/agent.toml`.

Per-repo key selection is pinned by git (`core.sshCommand`), and commits are
signed via 1Password's `op-ssh-sign`. With `useConfigOnly` and **no default
identity**, committing outside a configured context fails fast on purpose.

## Prerequisites

1. Install Homebrew, then the tools the helper scripts need up front:
   ```sh
   brew install jq
   brew install --cask 1password 1password-cli
   ```
2. Open 1Password, sign in, and enable **Settings → Developer →
   "Integrate with 1Password CLI"** and **"Use the SSH agent."**
3. Sign the CLI in: `op signin` (or unlock the desktop app). Check with
   `op whoami`.
4. Clone this repo, e.g. to `~/Work/github/laptop`.

## Step 1 — Import your existing SSH keys into 1Password

If your keys already live in 1Password, skip to Step 2. Coming from a machine
with private keys on disk, import each one so it's centralized and the agent can
serve it:

```sh
setup/import-ssh-key.sh --file ~/.ssh/id_ed25519 --title "SSH Key - acme" --vault Private
```

- Run it once per key. 1Password derives the public key automatically.
- It prints the `add-github-account.sh --existing …` command to wire the key
  into a context (Step 2).
- Once imported, the on-disk private keys are no longer needed — the 1Password
  agent serves them. (Keep a backup until you've verified everything.)

## Step 2 — Define your contexts (the manifest)

The `dotfiles ssh+git manifest` document maps each working directory to a key +
email.

- **Already have it** (from another machine): nothing to do — it lives in
  1Password and the provisioner will read it.
- **Building it**: add one context per account. Point `--existing` at a key you
  imported in Step 1 (or omit it to generate a brand-new key):
  ```sh
  setup/add-github-account.sh \
    --dir acme --email me@acme.com --name "Acme" \
    --vault Private --existing "SSH Key - acme"
  ```
  Add `--no-github` to skip the GitHub upload, or leave it on to register the
  key (auth + signing) on the currently active `gh` account.

## Step 3 — Run the full setup

```sh
./mac
```

`./mac` sources `laptop.local`, which installs the Homebrew bundle (apps + dev
tools), fonts, shell/tmux/iTerm/Hammerspoon config, AI tooling, and — as its
**final step** — runs `setup/provision-identities.sh` to pull your keys from
1Password and write all the identity files.

- It's idempotent and backs up anything it replaces (`<file>.backup.<timestamp>`).
- The provisioning step **skips gracefully** if `op`/`jq` are missing or you're
  not signed in. So on a truly bare machine you can run `./mac` first (it
  installs `op` + `jq`), then `op signin`, then re-run just the provisioner
  (Step 5's re-provision command).

## Step 4 — Enable the 1Password SSH agent

The one unavoidable manual toggle: **1Password → Settings → Developer → "Use the
SSH agent."** Your generated `~/.zshrc` already points `SSH_AUTH_SOCK` at the
agent socket. Restart your shell.

## Step 5 — Verify

```sh
cd ~/Work/acme
ssh -T git@github.com                       # should greet you as the right account
git commit --allow-empty -m "test"          # should sign via op-ssh-sign
git log --show-signature -1                  # should verify (allowed_signers)
```

Committing in a directory **without** a configured context should fail with
*"Author identity unknown"* — that's the intended fail-fast.

To regenerate local config any time the manifest changes:

```sh
sh setup/provision-identities.sh
```

## Day-to-day account management

| Task | Command |
|---|---|
| Import an existing private key into 1Password | `setup/import-ssh-key.sh` |
| Onboard a new account (key + context + GitHub) | `setup/add-github-account.sh` |
| Offboard a context | `setup/remove-github-account.sh` |

All three accept `--help`, and all edit the **private 1Password manifest** —
never this repo.

## What's in this directory

| Path | Purpose |
|---|---|
| `install.sh` | Full machine setup (run via `./mac`, or directly with `sh setup/install.sh`). |
| `provision-identities.sh` | Generate SSH/git identity files from the 1Password manifest. |
| `import-ssh-key.sh` | Import an existing private key into 1Password. |
| `add-github-account.sh` | Add a new account/context. |
| `remove-github-account.sh` | Remove a context (`--delete-key` / `--github` are shared-key-safe). |
| `git/gitconfig` | Generic global git config — no identity. |
| `zsh/`, `tmux/`, `starship/`, `hammerspoon/`, `iterm/` | Config assets installed by `install.sh`. |
