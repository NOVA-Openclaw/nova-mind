#!/usr/bin/env bash
# announce-d100-rolls.sh — cron wrapper for the D100 roll announcer.
# Activates the nova venv and logs output with ISO-8601 timestamps.
#
# See: nova-mind#432, nova-mind#435

set -euo pipefail

# Cron runs with a minimal PATH (/usr/bin:/bin) and does not export USER.
# Reconstruct a usable PATH and a reliable username before any expansion.
export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${HOME}/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
USER_NAME="$(id -un)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.openclaw/logs/announce-d100-rolls.log"
VENV_DIR="${HOME}/.local/share/${USER_NAME}/venv"

mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date -Iseconds)] announce-d100-rolls starting (user=${USER_NAME})"

if [ -f "${VENV_DIR}/bin/activate" ]; then
    # shellcheck disable=SC1090,SC1091
    source "${VENV_DIR}/bin/activate"
else
    echo "[$(date -Iseconds)] WARNING: venv not found at ${VENV_DIR}"
fi

RC=0
"${SCRIPT_DIR}/announce-d100-rolls.py" "$@" || RC=$?

echo "[$(date -Iseconds)] announce-d100-rolls exit=${RC}"
exit "$RC"
