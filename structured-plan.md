# Migration Plan: score-task-template + SOPS YAML Structured Data

## Goals

1. Migrate secrets from flat SOPS env vault (`vault.yml` → `.env`) to structured SOPS YAML (`vault.sops.yaml` + `yq`)
2. Add `yq` as a required dependency at the same level as `task` (auto-installed in `install.sh` before bootstrap)
3. Rename project to `score-task-template` (target audience: eclipse-score users)
4. Make identity groups fully flexible — any name, any number — each with its own `dir`, git credentials, and repo set

---

## New Vault Schema

Replace the flat `GITHUB_WORK_USER=...` env-style `vault.yml` with a structured `vault.sops.yaml`:

```yaml
# vault.sops.yaml  (committed encrypted; `task secrets:edit` to modify)
identities:
  - name: score
    user: myusername
    token: ghp_token_here
    email: me@example.com
    git_name: My Name
    dir: ~/score
    host_alias: score.github.com
    url_prefix: https://github.com/myusername/

  # Add any additional identity — work, personal, eclipse, client, etc.
  # No hardcoded names. All tasks derive the identity list at runtime via yq.
```

SOPS encrypts all leaf string values. Structure (keys, list shape) remains visible in the encrypted file; only values are ciphertext.

---

## Repo List Changes

Repos gain an optional `identity` field linking a repo to a named identity from the vault. The list stays in `repos.yml` as a go-task var (non-secret plaintext).

- Repos **with** an `identity`: authenticated clone using that identity's credentials; `git-credentials` writes a matching `includeIf` gitconfig entry
- Repos **without** an `identity`: unauthenticated `git clone` (public repos, read-only checkouts); no credentials written; shown in an "unassigned" group in `repos:list`

```yaml
repos:
  - name: score-task-template
    dir: ~/.taskfiles
    url: https://github.com/eclipse-score/score-task-template
    identity: score

  - name: score-cache
    dir: ~/work/score-cache
    url: https://github.com/eclipse-score/score-cache
    identity: score

  - name: score-baselibs
    dir: ~/work/baselibs
    url: https://github.com/eclipse-score/baselibs
    # no identity — public repo, unauthenticated clone
```

---

## File-by-File Changes

### `Brewfile`

Add `yq`:

```
brew "age"
brew "sops"
brew "yq"
```

### `install.sh`

- Update `REPO` to `eclipse-score/score-task-template`
- Add `yq` auto-install block immediately after the existing `task` block:

```sh
if ! command -v yq >/dev/null 2>&1; then
  echo "Installing yq..."
  if command -v brew >/dev/null 2>&1; then
    brew install yq
  else
    YQ_VERSION="v4.44.1"
    YQ_BIN="${HOME}/.local/bin/yq"
    mkdir -p "${HOME}/.local/bin"
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_darwin_arm64" -o "${YQ_BIN}"
    chmod +x "${YQ_BIN}"
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
fi
```

### `vault.yml` → `vault.sops.yaml`

- Rename and rewrite with the structured identities schema above
- Update `.sops.yaml` `creation_rules` `path_regex` to match `vault.sops.yaml` instead of `vault.yml`
- No migration task — clean break, no backwards compatibility

### `Taskfile.yml`

- **Remove** `dotenv: ["{{.HOME}}/.taskfiles/.env"]` — no more `.env` dependency
- Update `checkout` default `repo` var to `https://github.com/eclipse-score/score-task-template`
- `install` task order:
  1. `brew` (installs yq, sops, age)
  2. `secrets:doctor`
  3. `repos:git-credentials` (reads `vault.sops.yaml` directly — no decrypt step)
  4. `repos:doctor`
  5. `link`
  6. `hooks`
  - Remove `secrets:decrypt` from the install chain

### `secrets.yml`

#### Remove
- `decrypt` task
- `encrypt-env` task

#### Update
- `doctor`:
  - Add `yq` installed check alongside `age` and `sops`
  - Change vault file reference to `vault.sops.yaml`
  - Remove `.env` file check
  - Add check: vault contains at least one entry under `.identities`
- `edit`: change vault path to `vault.sops.yaml`
- `check-key`: unchanged
- `keygen`: unchanged

#### Add
- `check-yq` precondition task (mirrors `check-key`):
  ```yaml
  check-yq:
    desc: Verify yq is installed (internal precondition)
    preconditions:
      - sh: command -v yq
        msg: "yq not found — run: task brew"
  ```
- `generate-env` (optional utility — for tools that still need a flat `.env`):
  - Runs `sops -d vault.sops.yaml | yq` to emit dotenv-style `KEY=value` output
  - Not called by `install`; run manually as needed

### `repos.yml`

#### Remove
- The entire `vars: accounts:` block — identity data lives in the vault exclusively

#### Update repos list
- Add optional `identity:` field to each repo entry (see repo list above)

#### Rewrite `git-credentials`

Replace go-task `{{range .accounts}}` with a shell loop driven by `yq`. `sops -d` is called once per shell block and stored in `$vault` to avoid repeated decryption.

```yaml
git-credentials:
  vars:
    vault_file: '{{.vault_file | default (printf "%s/.taskfiles/vault.sops.yaml" .HOME)}}'
    default_identity: '{{.default_identity | default "score"}}'
  deps:
    - task: secrets:check-key
    - task: secrets:check-yq
  cmds:
    - |
      vault=$(sops -d "{{.vault_file}}")
      count=$(echo "$vault" | yq '.identities | length')

      : > ~/.git-credentials
      chmod 600 ~/.git-credentials

      for i in $(seq 0 $((count - 1))); do
        name=$(echo      "$vault" | yq ".identities[$i].name")
        user=$(echo      "$vault" | yq ".identities[$i].user")
        token=$(echo     "$vault" | yq ".identities[$i].token")
        email=$(echo     "$vault" | yq ".identities[$i].email")
        git_name=$(echo  "$vault" | yq ".identities[$i].git_name")
        dir=$(echo       "$vault" | yq ".identities[$i].dir" | sed "s|~|$HOME|g")
        url_prefix=$(echo "$vault" | yq ".identities[$i].url_prefix")
        cred_url=$(echo "$url_prefix" | sed "s|https://|https://${user}:${token}@|")

        printf '%s\n' "$cred_url" >> ~/.git-credentials
        cfg="$HOME/.gitconfig-${name}"
        printf '[user]\n\temail = %s\n\tname = %s\n' "$email" "$git_name" > "$cfg"
        git config --global "includeIf.gitdir:${dir}/.path" "$cfg"
        echo "configured: ${name} (${dir})"
      done
    - git config --global credential.helper store
    - git config --global credential.useHttpPath true
    - |
      vault=$(sops -d "{{.vault_file}}")
      default_name="{{.default_identity}}"
      email=$(echo    "$vault" | yq ".identities[] | select(.name == \"$default_name\") | .email")
      git_name=$(echo "$vault" | yq ".identities[] | select(.name == \"$default_name\") | .git_name")
      git config --global user.email "$email"
      git config --global user.name "$git_name"
      echo "global identity: $git_name <$email>"
```

#### Rewrite `doctor`

Replace hardcoded account checks with a `yq` loop over identities from the vault. Each identity block checks: user, email, and token are non-empty; `~/.gitconfig-<name>` exists with valid user.name and user.email.

Also check repos without an identity field are accessible (optional: `git ls-remote` check).

#### Add `list` task

Groups repos by identity for human-readable output. Repos without an `identity` field are shown under `[unassigned]`.

The task decrypts the vault to get the ordered identity list, then filters the go-task `repos` var by each identity name using go-task template output embedded in the shell script:

```yaml
list:
  desc: List all repos grouped by identity
  silent: true
  vars:
    vault_file: '{{.vault_file | default (printf "%s/.taskfiles/vault.sops.yaml" .HOME)}}'
  deps:
    - task: secrets:check-key
    - task: secrets:check-yq
  cmds:
    - |
      vault=$(sops -d "{{.vault_file}}")
      identities=$(echo "$vault" | yq '.identities[].name')

      # build repo data from go-task template expansion
      repos_data=$(cat <<'REPOS'
      {{range .repos}}{{.name}}|{{.dir}}|{{.identity | default "unassigned"}}
      {{end}}
      REPOS
      )

      for identity in $identities unassigned; do
        block=$(printf '%s\n' "$repos_data" | awk -F'|' -v id="$identity" '$3==id {print $1, $2}')
        [ -z "$block" ] && continue
        printf "\n[%s]\n" "$identity"
        printf '%s\n' "$block" | while read -r name dir; do
          printf "  %-24s %s\n" "$name" "$dir"
        done
      done
      printf '\n'
```

#### Update `clone`

The `_clone` internal task currently always uses `git clone <url>`. No change needed — unauthenticated clones work for public repos. Authenticated clones work via `~/.git-credentials` (credential helper store) set up by `git-credentials`. The `identity` field on a repo has no effect at clone time beyond what credentials are available.

#### Update `pull`, `fetch`, `status`

These continue to use go-task `for: var: repos` loops unchanged. The `_git` internal task header can print `{{.ITEM.identity | default "—"}}` for context.

#### Remove preconditions checking `.env`

Replace with `deps` on `secrets:check-key` and `secrets:check-yq`.

---

## Implementation Order

1. **Add `yq` to Brewfile**
2. **Update `install.sh`** — add yq bootstrap block, update `REPO` to `eclipse-score/score-task-template`
3. **Rewrite `vault.sops.yaml`** — new structured schema, update `.sops.yaml` path_regex
4. **Update `secrets.yml`** — add `check-yq`, remove `decrypt`/`encrypt-env`, add `generate-env`, update `doctor` and `edit`
5. **Update `repos.yml`** — remove `accounts:` var, add `identity:` fields to repos, rewrite `git-credentials` and `doctor`, add `list` task, remove `.env` preconditions
6. **Update `Taskfile.yml`** — remove `dotenv:`, update `checkout` URL, update `install` chain
7. **Update README** — rename to score-task-template, update install URL, task table, and project description
