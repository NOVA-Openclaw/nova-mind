#!/bin/bash
# memory-catchup.sh - Ingest daily memory/*.md files into the DB.
#
# The transcript-processing catchup that used to read OpenClaw session JSONL
# files was removed by #710. The live memory-extract hook is the system of
# record for per-message ingestion; nova-mind no longer reads or deletes
# OpenClaw-owned session files.
# Usage: memory-catchup.sh

set -e

# Load OpenClaw environment (API keys from openclaw.json) and PostgreSQL env.
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
# shellcheck source=/dev/null
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env
if [ -f "$PG_ENV" ]; then
    # shellcheck source=/dev/null
    source "$PG_ENV" || true
    load_pg_env 2>/dev/null || true
fi

# After load_pg_env, PGDATABASE is set if configured; resolve_agent_db fills
# in "$(whoami)_memory" otherwise. Issue: nova-mind #775.
DB="${PGDATABASE:-$(resolve_agent_db)}"

# ─────────────────────────────────────────────────────────────
# Ingest daily memory/*.md files into DB (content only), then delete
# ─────────────────────────────────────────────────────────────
MEMORY_MD_DIR="${HOME}/.openclaw/memory"
if [ -d "$MEMORY_MD_DIR" ]; then
    while IFS= read -r md_file; do
        [ -f "$md_file" ] || continue
        md_content=$(cat "$md_file" 2>/dev/null)
        [ -z "$md_content" ] && rm -f "$md_file" && continue

        # Store the file content as an entity fact on the 'NOVA' entity (agent notes)
        md_key="daily_memory_note"
        md_date=$(date -u +"%Y-%m-%d")

        # Warn if content is being truncated
        md_len=${#md_content}
        if [ "$md_len" -gt 4000 ]; then
            echo "[memory-catchup] WARNING: $(basename "$md_file") is $md_len chars, truncating to 4000" >&2
        fi

        key_escaped="${md_key//\'/''}"
        source_escaped="memory-catchup:${md_date//\'/''}"
        value_escaped="${md_content//\'/''}"
        value_truncated="${value_escaped:0:4000}"

        if psql "$DB" -q -c "
            INSERT INTO entity_facts (entity_id, key, value, source)
            SELECT id, '$key_escaped',
                   '$value_truncated',
                   '$source_escaped'
            FROM entities WHERE LOWER(name) = 'nova'
            ON CONFLICT DO NOTHING;
        " 2>/dev/null; then
            echo "[memory-catchup] Ingested memory MD: $(basename "$md_file")"
            rm -f "$md_file"
        else
            echo "[memory-catchup] WARNING: Failed to ingest $(basename "$md_file"), keeping file" >&2
        fi
    done < <(find "$MEMORY_MD_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
fi
