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

## tasks

| task | description |
|---|---|
| `task install` | full setup (brew + secrets + git-config + link + hooks) |
| `task brew` | install Homebrew packages |
| `task link` | symlink dotfiles into `$HOME` |
| `task hooks` | install git hooks into `.git/hooks/` |
| `task secrets:doctor` | check that all secrets prerequisites are met |
| `task secrets:decrypt` | decrypt `vault.yml` into `.env` |
| `task secrets:edit` | edit secrets in-place (encrypts on save) |
| `task secrets:keygen` | generate a new age key |

## secrets model

| file | committed | why |
|---|---|---|
| `vault.yml` | yes | encrypted by SOPS |
| `.sops.yaml` | yes | only contains public key |
| `.env` | no | plaintext, gitignored |
| `~/.config/sops/age/keys.txt` | never | your private key |

## run directly

```sh
task --taskfile <(curl -fsSL https://raw.githubusercontent.com/nick-hildebrant-etas/taskfiles/main/Taskfile.yml)
```
