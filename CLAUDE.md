# CLAUDE.md

## What this repo is

A dotfiles + task runner repo managed by [go-task](https://taskfile.dev). It bootstraps a macOS machine: installs packages, symlinks dotfiles into `$HOME`, and manages secrets encrypted with SOPS + age.

The repo lives at `~/.taskfiles` after setup. `~/Taskfile.yml` is a symlink to `~/.taskfiles/Taskfile.yml`, so running `task` from `$HOME` (or any subdirectory that walks up to it) uses this repo's taskfile directly.

---

## Bootstrap flow

`install.sh` is the entry point on a fresh machine. It:

1. Installs go-task if absent (via brew, or the official installer into `~/.local/bin`)
2. Downloads `Taskfile.yml` from GitHub into a temp file
3. Runs `task default` against the temp file — clones the repo to `~/.taskfiles` and symlinks dotfiles

After that it prints instructions telling the user to restore their age key and run `task install`. It intentionally stops there — secrets setup is a manual step.

Because `install.sh` runs a temp copy of `Taskfile.yml`, `secrets.yml` won't exist alongside it — which is why `includes` uses `optional: true`. The bootstrap only runs `task default` (checkout + link), not `task install`. After `task default` completes, `install.sh` explicitly creates `~/secrets.yml` as a symlink to `~/.taskfiles/secrets.yml`.

**Why `~/secrets.yml` must exist:** `task -g` loads `~/Taskfile.yml` (a symlink), and go-task resolves `./secrets.yml` relative to the symlink's location (`~/`), not its target (`~/.taskfiles/`). Both `install.sh` and `task link` create `~/secrets.yml` to ensure the include resolves correctly.

---

## Home environment integration

`task link` symlinks everything in `home/` into `$HOME`. It also explicitly links `~/.taskfiles/Taskfile.yml` → `~/Taskfile.yml`. Any dotfile you want managed belongs in `home/`.

The `install` task runs in this order — ordering is load-bearing:

1. `brew` — installs packages from `Brewfile`, including `age` and `sops`
2. `secrets:doctor` — checks all secrets prerequisites; prints actionable help and exits 1 if anything is wrong
3. `secrets:decrypt` — decrypts `vault.yml` → `.env` (requires age key; sops was just installed)
4. `git-config` — sources `.env` directly in shell and sets `user.email`/`user.name` if unset
5. `link` — symlinks dotfiles and `~/Taskfile.yml`
6. `hooks` — copies `hooks/pre-commit` into `.git/hooks/`

---

## File naming conventions

All YAML files in this repo use the `.yml` extension, not `.yaml`. This includes `Taskfile.yml`, `secrets.yml`, `vault.yml`, etc. The sole exception is `.sops.yaml`, which keeps its `.yaml` extension because SOPS requires that exact filename for its config file discovery.

---

## Variables

All paths are defined as vars — no bare strings in task `cmds`. `secrets.yml` inherits `TASKFILES_DIR` from the parent via go-task's variable scoping.

User-defined vars use `lower_snake_case`. Built-in go-task vars (`{{.HOME}}`, `{{.USER}}`, etc.) remain uppercase as provided by go-task.

**`Taskfile.yml` globals:**

| var | value |
|---|---|
| `taskfiles_dir` | `~/.taskfiles` |
| `home_dir` | `~/.taskfiles/home` |
| `brewfile` | `~/.taskfiles/Brewfile` |
| `hooks_src` | `~/.taskfiles/hooks` |
| `hooks_dst` | `~/.taskfiles/.git/hooks` |
| `env_file` | `~/.taskfiles/.env` |

**`secrets.yml` vars:**

| var | value |
|---|---|
| `age_key_file` | `~/.config/sops/age/keys.txt` |
| `age_key_dir` | `~/.config/sops/age` |
| `vault_file` | `~/.taskfiles/vault.yml` |
| `sops_config` | `~/.taskfiles/.sops.yaml` |
| `env_file` | `~/.taskfiles/.env` |

---

## Secrets

Secrets are stored encrypted in `vault.yml` using [SOPS](https://github.com/getsops/sops) + [age](https://age-encryption.org). The file is committed to the repo. The plaintext `.env` is gitignored and only exists locally after decryption.

### File inventory

| path | committed | what it is |
|---|---|---|
| `vault.yml` | yes | SOPS-encrypted secrets |
| `.sops.yaml` | yes | SOPS config — contains only the age **public** key |
| `.env` | no | Decrypted `KEY=value` pairs, written by `task secrets:decrypt` |
| `~/.config/sops/age/keys.txt` | never | age private key — back this up to a password manager |

### Required secrets

At minimum, `vault.yml` must contain:

- `GIT_EMAIL` — used by `task git-config`
- `GIT_NAME` — used by `task git-config`

### Diagnosing the setup

```sh
task secrets:doctor
```

Checks sequentially: `age` and `sops` installed, age private key present, `.sops.yaml` not a placeholder, `vault.yml` exists and is encrypted, `.env` decrypted with required vars. Each `[FAIL]` line shows the exact fix command. Also runs automatically as step 2 of `task install`.

### Day-to-day secrets workflow

| task | what it does |
|---|---|
| `task secrets:edit` | Opens `vault.yml` in `$EDITOR`; SOPS decrypts before and re-encrypts on save |
| `task secrets:decrypt` | Decrypts `vault.yml` → `.env` using `sops decrypt --output-type dotenv` |
| `task secrets:keygen` | Generates a new age key at `~/.config/sops/age/keys.txt`; prints the public key |
| `task secrets:encrypt-env` | One-time migration: converts an existing `.env` into an encrypted `vault.yml` |

Never edit `vault.yml` directly with a text editor.

To add a new secret: `task secrets:edit`, add the key, save, then `task secrets:decrypt` to refresh `.env`.

### go-task dotenv limitation

`dotenv` is read once at process startup. If a task writes `.env` during a run (e.g., `secrets:decrypt` inside `task install`), subsequent tasks in the same invocation won't see the new values via `dotenv`. This is why `git-config` explicitly sources `{{.ENV_FILE}}` in its shell steps rather than relying on go-task's dotenv mechanism.

---

## Age key management

The age private key (`~/.config/sops/age/keys.txt`) must exist before `task secrets:decrypt` can run. It is never committed. Back it up to a password manager.

### Restoring an existing key (common case)

```sh
mkdir -p ~/.config/sops/age
# copy keys.txt from your password manager
chmod 600 ~/.config/sops/age/keys.txt
cd ~/.taskfiles && task install
```

### Generating a new key (no backup exists)

Only do this if you have no backup. A new key cannot decrypt the existing `vault.yml` until it is re-encrypted.

```sh
cd ~/.taskfiles
task secrets:keygen
# 1. Add the printed public key to .sops.yaml
# 2. On a machine with the OLD key: sops updatekeys vault.yml
# 3. Commit .sops.yaml and the re-encrypted vault.yml
task install
```

---

## Pre-commit hook

`hooks/pre-commit` blocks staging `vault.yml` if it lacks the `sops:` metadata marker that SOPS always writes into encrypted files. The hook source is version-controlled in `hooks/`; `task hooks` (called by `task install`) copies it into `.git/hooks/`.

If the hook fires unexpectedly, `vault.yml` has lost its encryption — run `sops -e -i vault.yml` to re-encrypt before committing.
