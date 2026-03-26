#!/usr/bin/env bash
# Daily embedding cron job
# Runs both file-based and database embedders

set -euo pipefail

STATE_DIR="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
SCRIPTS_DIR="$STATE_DIR/scripts"
LOG_DIR="$STATE_DIR/logs"
LOG_FILE="$LOG_DIR/embed-memories.log"
VENV_PYTHON="$HOME/.local/share/$USER/venv/bin/python"

mkdir -p "$LOG_DIR"

echo "=== $(date -Iseconds) ===" >> "$LOG_FILE"

# Embed file-based memories (daily logs, MEMORY.md)
echo "--- embed-memories (files) ---" >> "$LOG_FILE"
"$VENV_PYTHON" "$SCRIPTS_DIR/embed-memories.py" >> "$LOG_FILE" 2>&1
echo "embed-memories exit: $?" >> "$LOG_FILE"

# Embed database tables (entities, tasks, projects, library, etc.)
echo "--- embed-full-database ---" >> "$LOG_FILE"
"$VENV_PYTHON" "$SCRIPTS_DIR/embed-full-database.py" >> "$LOG_FILE" 2>&1
echo "embed-full-database exit: $?" >> "$LOG_FILE"

echo "" >> "$LOG_FILE"
