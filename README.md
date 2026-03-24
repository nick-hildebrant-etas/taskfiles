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
# vault.yml on a machine that already has the old key
```

**Step 3 — full install:**
```sh
task install
```

`task install` runs in this order: `brew` → `secrets:doctor` → `secrets:decrypt` → `repos:git-credentials` → `repos:doctor` → `link` → `hooks`

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
| `task secrets:decrypt` | decrypt `vault.yml` → `.env` |
| `task secrets:edit` | edit secrets in-place (SOPS encrypts on save) |
| `task secrets:keygen` | generate a new age key |
| `task secrets:encrypt-env` | one-time: convert an existing `.env` into `vault.yml` |

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

| file | committed | why |
|---|---|---|
| `vault.yml` | yes | encrypted by SOPS |
| `.sops.yaml` | yes | only contains public key |
| `.env` | no | plaintext, gitignored |
| `~/.config/sops/age/keys.txt` | never | your private key |
