# taskfiles

my taskfiles / dotfiles / secret thing

## install

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nick-hildebrant-etas/taskfiles/main/install.sh)"
```

This clones the repo to `~/.taskfiles` and symlinks dotfiles. It does **not** run the full install — that comes after you set up your age key.

### fresh machine setup

**Step 1 — bootstrap:**
```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nick-hildebrant-etas/taskfiles/main/install.sh)"
```

**Step 2 — restore your age key** (from 1Password or wherever you back it up):
```sh
mkdir -p ~/.config/sops/age
# restore keys.txt here
chmod 600 ~/.config/sops/age/keys.txt
```

Or generate a new one if you don't have a backup:
```sh
task secrets:keygen
# add the printed public key to .sops.yaml, commit, and re-encrypt
# vault.sops.yaml on a machine that already has the old key
```

**Step 3 — full install:**
```sh
task install
```

`task install` runs in this order: `brew` → `secrets:doctor` → `repos:git-credentials` → `repos:doctor` → `link` → `hooks`

## tasks

### core

| task | description |
|---|---|
| `task install` | full setup — brew, secrets, git-config, link, hooks |
| `task brew` | install Homebrew packages from `Brewfile` |
| `task link` | symlink dotfiles into `$HOME` and link `~/Taskfile.yml` |
| `task hooks` | copy git hooks into `.git/hooks/` |
| `task checkout` | clone or pull the taskfiles repo |

### secrets

| task | description |
|---|---|
| `task secrets:doctor` | check all secrets prerequisites |
| `task secrets:edit` | edit `vault.sops.yaml` in-place (SOPS encrypts on save) |
| `task secrets:envgen` | generate a flat `.env` from vault (for tools that need `KEY=VALUE`) |
| `task secrets:keygen` | generate a new age key |

### repos

| task | description |
|---|---|
| `task repos:git-credentials` | write `~/.git-credentials` and per-account gitconfigs from vault |
| `task repos:doctor` | check git credentials and per-account config |
| `task repos:clone` | clone any repos not yet present (parallel) |
| `task repos:pull` | pull latest on all repos (parallel) |
| `task repos:fetch` | fetch all repos (parallel) |
| `task repos:status` | show git status for all repos (parallel) |
| `task repos:ws-generate` | generate VS Code workspace file |
| `task repos:ws-open` | open VS Code workspace (regenerates if `repos.yml` changed) |

## secrets model

Secrets live in `vault.sops.yaml` as structured YAML. Tasks decrypt on-demand with `sops -d` — there is no plaintext `.env` in the normal workflow. See `vault.sops.yaml.example` for the full schema.

| file | committed | why |
|---|---|---|
| `vault.sops.yaml` | yes | encrypted by SOPS; structured `identities:` list |
| `.sops.yaml` | yes | only contains public key |
| `.env` | no | optional flat export from `task secrets:envgen`, gitignored |
| `~/.config/sops/age/keys.txt` | never | your private key |

## git credentials

`task repos:git-credentials` configures HTTPS authentication for multiple GitHub accounts without relying on the macOS keychain. It writes:

- `~/.git-credentials` — one `https://user:token@github.com` entry per identity
- `~/.gitconfig-<name>` — per-identity gitconfig included via `[includeIf "gitdir:<dir>/"]`, containing:
  - `credential.username = <user>` — tells `git credential store` which entry to use for this identity
  - `credential.helper = ` (empty) — resets any `osxkeychain` or other helpers inherited from broader `includeIf` blocks
  - `credential.helper = store` — only active helper for repos in this identity's directory
- Global `~/.gitconfig` — `credential.helper = store` only; `useHttpPath` is unset

This means git always uses `store`, never `osxkeychain`, and the correct token is selected per-repo via `credential.username` in the directory-scoped gitconfig.
