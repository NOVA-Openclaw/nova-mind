#!/usr/bin/env bash
# hermes-comms-check.sh — consolidated comms poller cron wrapper (#474).
#
# Design: exactly one cron job invokes this wrapper. The wrapper ensures the
# deterministic ingest runs as the hermes DB user (re-exec via sudo when called
# as another user), captures the report, and logs the run to comms_checks.
#
# Repo path: scripts/comms/hermes-comms-check.sh
# Canonical install: copied to ~/.openclaw/scripts/comms/ by agent-install.sh

set -euo pipefail

# Cron runs with a minimal PATH; reconstruct a usable one before any expansion.
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
USER_NAME="$(id -un)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.openclaw/logs/hermes-comms-check.log"

# Allow tests to bypass the sudo re-exec without installing a crontab as hermes.
HERMES_COMMS_NO_SUDO="${HERMES_COMMS_NO_SUDO:-0}"

# Re-exec as hermes if we are not already hermes and sudo is available.
# This keeps the DB writer-of-record user consistent with comms_items grants.
if [ "$USER_NAME" != "hermes" ] && [ "$HERMES_COMMS_NO_SUDO" != "1" ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -u hermes "$0" "$@"
    fi
fi

# Locate scripts/comms/ingest.py. Prefer the adjacent copy in the installed
# comms/ directory; fall back to the checked-out repo path for development.
if [ -f "${SCRIPT_DIR}/ingest.py" ]; then
    INGEST_PY="${SCRIPT_DIR}/ingest.py"
elif [ -f "${HOME}/.openclaw/workspace-coder/nova-mind/scripts/comms/ingest.py" ]; then
    INGEST_PY="${HOME}/.openclaw/workspace-coder/nova-mind/scripts/comms/ingest.py"
else
    echo "[$(date -Iseconds)] ERROR: cannot locate scripts/comms/ingest.py" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
exec >> "$LOG_FILE" 2>&1

echo "[$(date -Iseconds)] hermes-comms-check starting (user=${USER_NAME})"

VENV_DIR="${HOME}/.local/share/${USER_NAME}/venv"
if [ -f "${VENV_DIR}/bin/activate" ]; then
    # shellcheck disable=SC1090,SC1091
    source "${VENV_DIR}/bin/activate"
fi

RC=0
python3 "$INGEST_PY" --platforms email,x,nostr --log-check || RC=$?

echo "[$(date -Iseconds)] hermes-comms-check exit=${RC}"
exit "$RC"
