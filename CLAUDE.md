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

Because `install.sh` runs a temp copy of `Taskfile.yml`, included taskfiles won't exist alongside it — which is why `includes` uses `optional: true`. The bootstrap only runs `task default` (checkout + link), not `task install`.

**Why includes use absolute paths:** `task -g` loads `~/Taskfile.yml` (a symlink), and go-task resolves relative paths relative to the symlink's location (`~/`), not its target (`~/.taskfiles/`). Includes use `{{.HOME}}/.taskfiles/secrets.yml` so they resolve correctly regardless of how task is invoked. Note: `{{.HOME}}` works directly in include paths, but multi-level expansion (e.g. `{{.taskfiles_dir}}` which itself contains `{{.HOME}}`) does not. Inside `{{range}}` blocks, use `$.HOME` (not `.HOME`) to access root-level vars — `.` is rebound to the current iteration item.

---

## Home environment integration

`task link` symlinks everything in `home/` into `$HOME`. It also explicitly links `~/.taskfiles/Taskfile.yml` → `~/Taskfile.yml`. Any dotfile you want managed belongs in `home/`.

The `install` task runs in this order — ordering is load-bearing:

1. `brew` — installs packages from `Brewfile`, including `age`, `sops`, and `yq`
2. `secrets:doctor` — checks all secrets prerequisites; prints actionable help and exits 1 if anything is wrong
3. `repos:git-credentials` — decrypts `vault.sops.yaml`; writes `~/.git-credentials`, per-identity `~/.gitconfig-<name>` files, `includeIf` gitconfig entries, and sets global `credential.helper = store` (removing `osxkeychain`)
4. `link` — symlinks dotfiles and `~/Taskfile.yml`
5. `hooks` — copies `hooks/pre-commit` into `.git/hooks/`

---

## Templating

Go-task uses Go's `text/template` engine extended with [Sprig](https://masterminds.github.io/sprig/) — a library of ~100 utility functions. Use `{{.VAR}}` to reference task vars, and sprig functions via pipes:

```yaml
"{{.dir | replace "~" .HOME}}"
"{{.VSCODE_WORKSPACE_FILE | default (printf "%s/file" .HOME)}}"
```

Inside `{{range}}` blocks, `.` is rebound to the current item — use `$.VAR` to access root-level vars (e.g. `$.HOME`).

Go-task also supports `sources`/`generates` on tasks to track input/output checksums and skip re-execution when outputs are up to date.

**Never use shell `eval` to work around templating.** Use go templates directly — `{{.user}}`, `{{.token}}`, `{{range .accounts}}`, etc. `eval` causes `Nil` execution errors when any template var is nil, is hard to debug, and is always the wrong approach here.

**Task-local vars pattern:** All path and config vars are defined inside each task with `| default` fallbacks, not in a global `vars:` block. This makes tasks self-contained and overridable at call time:

```yaml
  some-task:
    vars:
      foo: '{{.foo | default (printf "%s/.taskfiles/something" .HOME)}}'
    cmds:
      - do-thing "{{.foo}}"
```

Use `task: dep-name` with explicit `vars:` when passing vars to `deps` so the dep receives the resolved value, not a template string.

---

## File naming conventions

All YAML files in this repo use the `.yml` extension, not `.yaml`. This includes `Taskfile.yml`, `secrets.yml`, etc. Two exceptions use `.yaml`:
- `.sops.yaml` — SOPS requires that exact filename for config file discovery
- `vault.sops.yaml` — SOPS-managed secret files use the `.sops.yaml` suffix so SOPS's `path_regex` rule matches them automatically

---

## Variables

All paths are defined as vars — no bare strings in task `cmds`. Each taskfile defines its vars task-locally with `| default` fallbacks (see task-local vars pattern above). Included taskfiles use `{{.HOME}}/.taskfiles` directly rather than depending on a var from the parent.

User-defined vars use `lower_snake_case`. Built-in go-task vars (`{{.HOME}}`, `{{.USER}}`, etc.) remain uppercase as provided by go-task.

**Common task-local vars (defined per-task with `| default`):**

| var | default value |
|---|---|
| `home_dir` | `~/.taskfiles/home` |
| `brewfile` | `~/.taskfiles/Brewfile` |
| `hooks_src` | `~/.taskfiles/hooks` |
| `hooks_dst` | `~/.taskfiles/.git/hooks` |
| `env_file` | `~/.taskfiles/.env` (only used by `secrets:envgen`) |
| `age_key_file` | `~/.config/sops/age/keys.txt` |
| `age_key_dir` | `~/.config/sops/age` |
| `vault_file` | `~/.taskfiles/vault.sops.yaml` |
| `sops_config` | `~/.taskfiles/.sops.yaml` |

---

## Secrets

Secrets are stored encrypted in `vault.sops.yaml` using [SOPS](https://github.com/getsops/sops) + [age](https://age-encryption.org). The file is committed to the repo. There is no plaintext `.env` in the normal workflow — tasks decrypt on-demand via `sops -d` and pipe directly to `yq`.

### File inventory

| path | committed | what it is |
|---|---|---|
| `vault.sops.yaml` | yes | SOPS-encrypted structured secrets |
| `.sops.yaml` | yes | SOPS config — contains only the age **public** key |
| `.env` | no | Optional flat export, written by `task secrets:envgen` |
| `~/.config/sops/age/keys.txt` | never | age private key — back this up to a password manager |

### Vault structure

`vault.sops.yaml` holds a list of `identities`, each with git credentials and a list of repos. SOPS encrypts all leaf values; the structure (keys and list shape) stays visible in the encrypted file.

See `vault.sops.yaml.example` for a complete annotated example. The fields used by tasks are:

| field | used by |
|---|---|
| `name` | `git-credentials` (gitconfig filename, includeIf key), `repos:list` |
| `user` | `git-credentials` (credential store) |
| `token` | `git-credentials` (credential store) |
| `email` | `git-credentials` (per-identity gitconfig) |
| `git_name` | `git-credentials` (per-identity gitconfig, global fallback) |
| `dir` | `git-credentials` (includeIf path), `clone`/`pull`/`fetch`/`status` |
| `repos[]` | `clone`, `pull`, `fetch`, `status`, `list`, `ws-generate` |

### Git credential setup

`task repos:git-credentials` sets up HTTPS authentication for multiple GitHub accounts. The approach uses `git credential store` with per-identity username routing — **not** `osxkeychain`, path-based lookup (`useHttpPath`), or fake hostnames.

**What it writes:**

`~/.git-credentials` — one entry per identity:
```
https://user1:token1@github.com
https://user2:token2@github.com
```

`~/.gitconfig-<name>` — included via `[includeIf "gitdir:<dir>/"]`, with three credential keys that work together:
```ini
[credential "https://github.com"]
    username = user1           # tells store which entry to select
[credential]
    helper =                   # resets osxkeychain inherited from broader includeIf blocks
    helper = store             # only active helper inside this identity's dir
```

Global `~/.gitconfig`:
```ini
[credential]
    helper = store             # store only — osxkeychain removed; useHttpPath unset
```

**Why the empty `helper =` is necessary:** macOS Git ships with `osxkeychain` in the system gitconfig. Any broader `[includeIf]` (e.g. `gitdir:/Users/user/code/`) may also inject `osxkeychain`. Since git evaluates credential helpers in order, `osxkeychain` would be tried first and return the wrong identity. Setting `helper =` in the per-identity gitconfig clears all previously accumulated helpers before adding `store`.

**Why `credential.username` works:** `git credential store` matches entries in `~/.git-credentials` by protocol, host, and (if set) username. With `username` set in the per-dir gitconfig, store skips other identities' entries for the same host and returns the right token.

---

### Reading vault data in tasks

Tasks decrypt the vault once into a `sh:` dynamic var, then use go-task's `for` loop to iterate — no manual count/index arithmetic, no repeated `sops -d` calls:

```yaml
vars:
  vault_file: '{{.vault_file | default (printf "%s/.taskfiles/vault.sops.yaml" .HOME)}}'
  repo_lines:
    sh: sops -d "{{.vault_file}}" | yq '.identities[] | (.dir + "\t" + .repos[])'
cmds:
  - for: {var: repo_lines, split: "\n"}
    cmd: |
      dir=$(echo "{{.ITEM}}" | cut -f1 | sed "s|~|$HOME|g")
      url=$(echo "{{.ITEM}}" | cut -f2)
      repo_name=$(basename "$url" .git)
```

The `sh:` var runs once at task start. The yq expression emits one tab-separated line per repo across all identities.

For tasks that need all fields per identity (not per repo), use a similar pattern with a different yq expression — e.g. `'.identities[] | (.name + "\t" + .user + "\t" + .dir)'`.

### Diagnosing the setup

```sh
task secrets:doctor
```

Checks sequentially: `age`, `sops`, and `yq` installed; age private key present; `.sops.yaml` not a placeholder; `vault.sops.yaml` exists and is encrypted; vault decrypts and contains at least one identity. Each `[FAIL]` line shows the exact fix command. Also runs automatically as step 2 of `task install`.

### Day-to-day secrets workflow

| task | what it does |
|---|---|
| `task secrets:edit` | Opens `vault.sops.yaml` in `$EDITOR`; SOPS decrypts before and re-encrypts on save |
| `task secrets:envgen` | Generates a flat `.env` from vault (for tools that need `KEY=VALUE` format) |
| `task secrets:keygen` | Generates a new age key at `~/.config/sops/age/keys.txt`; prints the public key |
| `task repos:git-credentials` | Writes `~/.git-credentials` and per-identity gitconfig files from vault |

Never edit `vault.sops.yaml` directly with a text editor.

To add or change a secret: `task secrets:edit`, edit the YAML, save. Tasks read the vault at runtime — no extra decrypt step needed.

### Flat .env for external tooling

If a tool needs a flat `KEY=VALUE` file, run `task secrets:envgen`. It generates `~/.taskfiles/.env` (gitignored) with one entry per string field per identity, using the naming convention `GITHUB_<NAME_UPPER>_<FIELD_UPPER>=value`. Repos lists are skipped (not representable as flat values). This file is ephemeral — regenerate it after any vault edit.

---

## Age key management

The age private key (`~/.config/sops/age/keys.txt`) must exist before any `sops -d` call can succeed. It is never committed. Back it up to a password manager.

### Restoring an existing key (common case)

```sh
mkdir -p ~/.config/sops/age
# copy keys.txt from your password manager
chmod 600 ~/.config/sops/age/keys.txt
cd ~/.taskfiles && task install
```

### Generating a new key (no backup exists)

Only do this if you have no backup. A new key cannot decrypt the existing `vault.sops.yaml` until it is re-encrypted.

```sh
cd ~/.taskfiles
task secrets:keygen
# 1. Add the printed public key to .sops.yaml
# 2. On a machine with the OLD key: sops updatekeys vault.sops.yaml
# 3. Commit .sops.yaml and the re-encrypted vault.sops.yaml
task install
```

---

## Pre-commit hook

`hooks/pre-commit` blocks staging `vault.sops.yaml` if it lacks the `sops:` metadata marker that SOPS always writes into encrypted files. The hook source is version-controlled in `hooks/`; `task hooks` (called by `task install`) copies it into `.git/hooks/`.

If the hook fires unexpectedly, `vault.sops.yaml` has lost its encryption — run `sops -e -i vault.sops.yaml` to re-encrypt before committing.
