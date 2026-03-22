# CLAUDE.md

## What this repo is

A dotfiles + task runner repo managed by [go-task](https://taskfile.dev). It bootstraps a macOS machine: installs packages, symlinks dotfiles into `$HOME`, and manages secrets.

The repo lives at `~/.taskfiles` after setup. `~/Taskfile.yml` is a symlink into it, so running `task` from `$HOME` (or any subdirectory that walks up to it) uses this repo's taskfile directly.

## How it integrates into the home environment

`task link` symlinks everything in `home/` into `$HOME`, plus explicitly links `~/.taskfiles/Taskfile.yml` → `~/Taskfile.yml`. Any dotfile you want managed goes in `home/`.

The `install` task runs in this order — the ordering is load-bearing:

1. `brew` — installs packages from `Brewfile`, including `age` and `sops`
2. `secrets:decrypt` — decrypts `secrets.yaml` → `.env` (requires age key, sops just installed)
3. `git-config` — reads `GIT_EMAIL`/`GIT_NAME` from `.env`
4. `link` — symlinks dotfiles
5. `hooks` — copies `hooks/pre-commit` into `.git/hooks/`

## Secrets

Secrets are stored encrypted in `secrets.yaml` using [SOPS](https://github.com/getsops/sops) + [age](https://age-encryption.org). The file is committed to the repo. The plaintext `.env` is gitignored and only exists locally after decryption.

### Key files

| path | committed | what it is |
|---|---|---|
| `secrets.yaml` | yes | SOPS-encrypted secrets |
| `.sops.yaml` | yes | SOPS config — contains only the age **public** key |
| `.env` | no | Decrypted plaintext, written by `task secrets:decrypt` |
| `~/.config/sops/age/keys.txt` | never | age private key — back this up to a password manager |

### Editing secrets

```sh
task secrets:edit
```

Opens `secrets.yaml` in `$EDITOR`. SOPS decrypts before opening and re-encrypts on save. Never edit `secrets.yaml` directly with a text editor.

### Adding a new secret

1. `task secrets:edit`
2. Add `NEW_KEY: value` in the editor, save and quit
3. `task secrets:decrypt` to refresh `.env`

### What secrets are in `.env`

At minimum:
- `GIT_EMAIL` — used by `task git-config`
- `GIT_NAME` — used by `task git-config`

Add others as needed. They are available as environment variables in all task shell steps via go-task's `dotenv` directive (loaded from `./.env` relative to the repo root).

**go-task dotenv limitation:** `dotenv` is read once at process startup. If a task writes `.env` during a run, subsequent tasks in the same invocation won't see the new values via `dotenv`. This is why `git-config` explicitly sources `.env` in its shell steps rather than relying on go-task's dotenv mechanism.

## Age key management

The age private key (`~/.config/sops/age/keys.txt`) must exist before `task secrets:decrypt` can run. It is never committed.

### Fresh machine — restoring existing key

```sh
mkdir -p ~/.config/sops/age
# restore keys.txt from your password manager
chmod 600 ~/.config/sops/age/keys.txt
task install
```

### Fresh machine — generating a new key

Only do this if you have no backup. Generating a new key means existing `secrets.yaml` cannot be decrypted by it until the file is re-encrypted.

```sh
task secrets:keygen        # prints the new public key
# 1. Add the public key to .sops.yaml
# 2. On a machine with the OLD key: sops updatekeys secrets.yaml
# 3. Commit .sops.yaml and the re-encrypted secrets.yaml
task install
```

## Bootstrap flow

`install.sh` is the entry point on a fresh machine. It:
1. Installs go-task if absent (via brew or the official installer)
2. Downloads `Taskfile.yml` from GitHub into a temp file
3. Runs `task default` — which clones the repo and symlinks dotfiles

`install.sh` intentionally stops there. The age key is a manual step. After the key is in place, run `task install` to complete setup.

Because `install.sh` runs a temp copy of `Taskfile.yml`, the `secrets` include (`secrets.yml`) won't exist at that temp path — which is why it's declared `optional: true`. No secrets tasks run during bootstrap.

## Pre-commit hook

`hooks/pre-commit` blocks committing `secrets.yaml` if it lacks the `sops:` metadata marker that indicates it's encrypted. The hook is installed by `task hooks` (called by `task install`). The source lives in `hooks/` so it's version-controlled; `.git/hooks/` is not tracked.

If you see the hook fire unexpectedly, it means `secrets.yaml` lost its encryption — run `sops -e -i secrets.yaml` to re-encrypt before committing.

## Variables

The canonical path variable used throughout both taskfiles:

```
TASKFILES_DIR: "{{.HOME}}/.taskfiles"
```

All file references within tasks use this variable. Do not hardcode `~/.taskfiles`.

`secrets.yml` inherits `TASKFILES_DIR` from the parent taskfile via go-task's variable scoping.
