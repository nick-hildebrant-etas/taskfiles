# taskfiles

my taskfiles / dotfiles / secret thing

## install

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nick-hildebrant-etas/taskfiles/main/install.sh)"
```

This will:
1. Install [go-task](https://taskfile.dev) if not already present
2. Fetch `Taskfile.yml` from this repo and run it

## tasks

| task | description |
|---|---|
| `task install` | full setup (brew + link) |
| `task brew` | install Homebrew packages |
| `task link` | symlink dotfiles into `$HOME` |

## run directly

```sh
task --taskfile <(curl -fsSL https://raw.githubusercontent.com/nick-hildebrant-etas/taskfiles/main/Taskfile.yml)
```
