#!/usr/bin/env sh
set -e

REPO="nick-hildebrant-etas/taskfiles"
BRANCH="main"
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

echo "Running tasks..."
task --taskfile "${TMPFILE}" "$@"

rm -f "${TMPFILE}"
