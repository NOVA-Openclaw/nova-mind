#!/bin/bash
# Daily embedding cron job
# Runs both file-based and database embedders

LOG_FILE="$HOME/.openclaw/logs/embed-memories.log"
VENV_DIR="${HOME}/.local/share/${USER}/venv"
VENV="$VENV_DIR/bin/activate"

echo "=== $(date -Iseconds) ===" >> "$LOG_FILE"
source "$VENV"

# Embed file-based memories (daily logs, MEMORY.md)
echo "--- embed-memories (files) ---" >> "$LOG_FILE"
python "$HOME/.openclaw/workspace/scripts/embed-memories.py" >> "$LOG_FILE" 2>&1
echo "embed-memories exit: $?" >> "$LOG_FILE"

# Embed database tables (entities, tasks, projects, library, etc.)
echo "--- embed-full-database ---" >> "$LOG_FILE"
python "$HOME/.openclaw/workspace/scripts/embed-full-database.py" >> "$LOG_FILE" 2>&1
echo "embed-full-database exit: $?" >> "$LOG_FILE"

# Embed research data
echo "--- embed-research ---" >> "$LOG_FILE"
python "$HOME/.openclaw/workspace/nova-mind/memory/scripts/embed-research.py" >> "$LOG_FILE" 2>&1
echo "embed-research exit: $?" >> "$LOG_FILE"

echo "" >> "$LOG_FILE"
