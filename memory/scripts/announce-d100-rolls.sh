#!/usr/bin/env bash
# announce-d100-rolls.sh — cron wrapper for the D100 roll announcer.
# Activates the nova venv and logs output with ISO-8601 timestamps.
#
# See: nova-mind#432

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.openclaw/logs/announce-d100-rolls.log"
VENV_DIR="${HOME}/.local/share/${USER}/venv"

mkdir -p "$(dirname "$LOG_FILE")"

exec >> "$LOG_FILE" 2>&1

echo "[$(date -Iseconds)] announce-d100-rolls starting"

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
