#!/usr/bin/env sh
set -e

REPO="nick-hildebrant-etas/taskfiles"
BRANCH="main"
TASKFILES_DIR="${HOME}/.taskfiles"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TASKFILE_URL="${RAW_BASE}/Taskfile.yml"

# Install go-task if not present
if ! command -v task >/dev/null 2>&1; then
  echo "Installing go-task..."
  if command -v brew >/dev/null 2>&1; then
    brew install go-task
  else
    sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b "${HOME}/.local/bin"
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
fi

echo "Fetching Taskfile from ${TASKFILE_URL}..."
TMPFILE="$(mktemp /tmp/Taskfile.XXXXXX)"
curl -fsSL "${TASKFILE_URL}" -o "${TMPFILE}"

echo "Running bootstrap..."
task --taskfile "${TMPFILE}" default

rm -f "${TMPFILE}"

# Ensure task includes resolve correctly when using 'task -g'.
# ~/Taskfile.yml is a symlink, so go-task resolves ./secrets.yml relative
# to ~/ — we create ~/secrets.yml here so it exists before 'task -g install'.
ln -sf "${TASKFILES_DIR}/secrets.yml" "${HOME}/secrets.yml"

cat <<EOF

Bootstrap complete. Repo is at ${TASKFILES_DIR}.

Next steps:

  1. Set up your age private key (required for secrets):

     Restore from backup (preferred):
       mkdir -p ~/.config/sops/age
       cp <your-backup>/keys.txt ~/.config/sops/age/keys.txt
       chmod 600 ~/.config/sops/age/keys.txt

     Or generate a new key (only if you have no backup):
       cd ${TASKFILES_DIR} && task secrets:keygen
       # then update .sops.yaml with the printed public key
       # and re-encrypt vault.yml on a machine with the old key

  2. Run the full installer:
       cd ${TASKFILES_DIR} && task install

  At any time, check your secrets setup with:
       cd ${TASKFILES_DIR} && task secrets:doctor

EOF
