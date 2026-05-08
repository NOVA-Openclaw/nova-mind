#!/bin/bash
# Bootstrap Context System Installer
#
# Installs:
#   1. Database management functions (idempotent — psql \i)
#   2. Database audit triggers (idempotent — psql \i)
#   3. OpenClaw hook files at ~/.openclaw/hooks/db-bootstrap-context/
#   4. Disk fallback files at ~/.openclaw/bootstrap-fallback/
#
# Hook and fallback files use SHA-256 hash comparison: install if missing,
# replace if different from repo, skip if identical. This matches the
# install_lib_files pattern in nova-mind/memory/agent-install.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
HOOK_DIR="$OPENCLAW_DIR/hooks/db-bootstrap-context"
FALLBACK_DIR="$OPENCLAW_DIR/bootstrap-fallback"

# Load centralized PG config (ENV → ~/.openclaw/postgres.json → defaults).
# Matches the pattern used in nova-mind/memory/agent-install.sh.
if [ -f "$OPENCLAW_DIR/lib/pg-env.sh" ]; then
    # shellcheck disable=SC1091
    source "$OPENCLAW_DIR/lib/pg-env.sh"
    load_pg_env
elif [ -f "$OPENCLAW_DIR/postgres.json" ] && command -v jq &>/dev/null; then
    # Fallback: inline jq parse (only if pg-env.sh missing)
    [ -z "${PGHOST:-}" ]     && export PGHOST="$(jq -r '.host // empty' "$OPENCLAW_DIR/postgres.json")"
    [ -z "${PGPORT:-}" ]     && export PGPORT="$(jq -r '.port // empty' "$OPENCLAW_DIR/postgres.json")"
    [ -z "${PGDATABASE:-}" ] && export PGDATABASE="$(jq -r '.database // empty' "$OPENCLAW_DIR/postgres.json")"
    [ -z "${PGUSER:-}" ]     && export PGUSER="$(jq -r '.user // empty' "$OPENCLAW_DIR/postgres.json")"
    if [ -z "${PGPASSWORD+set}" ]; then
        export PGPASSWORD="$(jq -r '.password // empty' "$OPENCLAW_DIR/postgres.json")"
    fi
fi
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_NAME:-${PGDATABASE:-${PGUSER//-/_}_memory}}"

# Color codes (match agent-install.sh conventions)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
CHECK="${GREEN}✅${NC}"
WARN="${YELLOW}⚠️${NC}"
INFO="${BLUE}ℹ️${NC}"
CROSS="${RED}❌${NC}"

echo "=== Bootstrap Context System Installation ==="
echo ""

# ----------------------------------------------------------------------------
# Prerequisites
# ----------------------------------------------------------------------------
if ! command -v psql &> /dev/null; then
    echo -e "  ${CROSS} psql not found. Install PostgreSQL client."
    exit 1
fi

if ! command -v sha256sum &> /dev/null; then
    echo -e "  ${CROSS} sha256sum not found (required for idempotent installs)."
    exit 1
fi

if ! command -v openclaw &> /dev/null; then
    echo -e "  ${WARN} openclaw command not found. Make sure OpenClaw is installed."
fi

# ----------------------------------------------------------------------------
# Database connection check
# ----------------------------------------------------------------------------
echo "Testing database connection..."
if ! psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "  ${CROSS} Cannot connect to database '$DB_NAME'"
    exit 1
fi
echo -e "  ${CHECK} Database connection OK"
echo ""

# ----------------------------------------------------------------------------
# SQL: management functions + audit triggers (idempotent CREATE OR REPLACE)
# ----------------------------------------------------------------------------

# Pre-flight: refuse to apply management-functions.sql if it carries known
# broken references that would regress the live function. Specifically check
# for the dropped columns workflow_steps.agent_id and workflows.orchestrator_agent_id
# (see nova-mind#171 / 5b20b40 — these were replaced with domain-based matching).
echo "Pre-flight check on management-functions.sql..."
MGMT_SQL="$SCRIPT_DIR/sql/management-functions.sql"
if [ ! -f "$MGMT_SQL" ]; then
    echo -e "  ${CROSS} management-functions.sql not found at $MGMT_SQL"
    exit 1
fi

# Extract just the get_agent_bootstrap function body to avoid false-positive
# matches from neighboring helper functions (e.g. list_agent_context which
# legitimately has different column references in this file).
GAB_BODY=$(awk '/^CREATE OR REPLACE FUNCTION (public\.)?get_agent_bootstrap/,/^\$\$;$|^\$function\$;$/' "$MGMT_SQL")
if [ -z "$GAB_BODY" ]; then
    echo -e "  ${WARN} get_agent_bootstrap function not found in $MGMT_SQL"
else
    BROKEN_REFS=""
    if echo "$GAB_BODY" | grep -qE 'ws\.agent_id|orchestrator_agent_id'; then
        BROKEN_REFS=$(echo "$GAB_BODY" | grep -nE 'ws\.agent_id|orchestrator_agent_id' | head -3)
    fi
    if [ -n "$BROKEN_REFS" ]; then
        echo -e "  ${CROSS} REFUSING to apply: management-functions.sql has stale references to dropped columns:"
        echo "$BROKEN_REFS" | sed 's/^/      /'
        echo ""
        echo "      The columns workflow_steps.agent_id and workflows.orchestrator_agent_id"
        echo "      were dropped in favor of domain-based matching (orchestrator_domain plus"
        echo "      workflow_steps.domain / domains[]). Applying this SQL would regress the"
        echo "      live function. See nova-mind#171 / commit 5b20b40 for the canonical fix."
        echo ""
        echo "      Re-sync this file from database/schema.sql before re-running install."
        exit 1
    fi
    echo -e "  ${CHECK} No stale column references detected"
fi
echo ""

echo "Installing management functions..."
psql -d "$DB_NAME" -f "$SCRIPT_DIR/sql/management-functions.sql" > /dev/null
echo -e "  ${CHECK} Functions installed"

echo "Installing audit triggers..."
psql -d "$DB_NAME" -f "$SCRIPT_DIR/sql/triggers.sql" > /dev/null
echo -e "  ${CHECK} Triggers installed"
echo ""

# ----------------------------------------------------------------------------
# Hash-compare installer for the hook files at $HOOK_DIR
# ----------------------------------------------------------------------------
# install_file <src> <dst> <label>:
#   - missing dst → copy
#   - dst hash differs from src → copy (warns about overwrite)
#   - dst hash matches src → skip
install_file() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [ ! -f "$src" ]; then
        echo -e "  ${WARN} [$label] source not found: $src — skipping"
        return 0
    fi

    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        echo -e "  ${CHECK} [$label] installed"
        return 0
    fi

    local src_hash dst_hash
    src_hash=$(sha256sum "$src" | awk '{print $1}')
    dst_hash=$(sha256sum "$dst" | awk '{print $1}')
    if [ "$src_hash" != "$dst_hash" ]; then
        cp "$src" "$dst"
        echo -e "  ${CHECK} [$label] updated (hash changed)"
    else
        echo -e "  ${INFO} [$label] up to date"
    fi
}

echo "Installing OpenClaw hook (hash-compared)..."
mkdir -p "$HOOK_DIR"
install_file "$SCRIPT_DIR/hook/handler.ts"   "$HOOK_DIR/handler.ts"   "hook/handler.ts"
install_file "$SCRIPT_DIR/hook/HOOK.md"      "$HOOK_DIR/HOOK.md"      "hook/HOOK.md"
install_file "$SCRIPT_DIR/hook/package.json" "$HOOK_DIR/package.json" "hook/package.json"
echo ""

# ----------------------------------------------------------------------------
# Hash-compare installer for fallback files at $FALLBACK_DIR
# ----------------------------------------------------------------------------
echo "Installing disk fallback files (hash-compared)..."
mkdir -p "$FALLBACK_DIR"
if [ -d "$SCRIPT_DIR/fallback" ]; then
    for src_file in "$SCRIPT_DIR/fallback/"*.md; do
        [ -e "$src_file" ] || continue
        base=$(basename "$src_file")
        install_file "$src_file" "$FALLBACK_DIR/$base" "fallback/$base"
    done
else
    echo -e "  ${WARN} No fallback files found in repo (optional)"
fi
echo ""

# ----------------------------------------------------------------------------
# Verify installation
# ----------------------------------------------------------------------------
echo "Verifying installation..."
FUNCTION_COUNT=$(psql -d "$DB_NAME" -tA -c "SELECT count(*) FROM pg_proc WHERE proname LIKE '%bootstrap%'")
echo -e "  ${CHECK} Database functions matching '%bootstrap%': $FUNCTION_COUNT"

# Confirm get_agent_bootstrap exists with the expected signature
if psql -d "$DB_NAME" -tA -c "SELECT proname FROM pg_proc WHERE proname = 'get_agent_bootstrap'" | grep -q '^get_agent_bootstrap$'; then
    echo -e "  ${CHECK} get_agent_bootstrap() present"
else
    echo -e "  ${WARN} get_agent_bootstrap() not found — hook will fall through to disk"
fi

# Smoke test: actually invoke the function for the local agent. If the SQL
# we just applied carried a runtime error (e.g. references a column that no
# longer exists), this catches it now instead of at next-session boot.
# Try the agent matching $PGUSER first, fall back to 'nova' for shared-DB
# deployments where the local user differs from the canonical agent name.
SMOKE_AGENT="${PGUSER:-$(whoami)}"
SMOKE_OUT=$(psql -d "$DB_NAME" -tA -c "SELECT count(*) FROM get_agent_bootstrap('$SMOKE_AGENT');" 2>&1)
SMOKE_EXIT=$?
if [ $SMOKE_EXIT -ne 0 ] || ! echo "$SMOKE_OUT" | grep -qE '^[0-9]+$'; then
    # Try 'nova' as a fallback (shared-DB peer setup)
    SMOKE_OUT2=$(psql -d "$DB_NAME" -tA -c "SELECT count(*) FROM get_agent_bootstrap('nova');" 2>&1)
    SMOKE_EXIT2=$?
    if [ $SMOKE_EXIT2 -ne 0 ] || ! echo "$SMOKE_OUT2" | grep -qE '^[0-9]+$'; then
        echo -e "  ${CROSS} get_agent_bootstrap() smoke test FAILED:"
        echo "$SMOKE_OUT"  | head -3 | sed 's/^/      /'
        echo "      "
        echo "      The SQL just applied left the function in a non-runnable state."
        echo "      Inspect the function definition with:"
        echo "      psql -d $DB_NAME -c \"\\df+ get_agent_bootstrap\""
        echo "      "
        echo "      The hook will silently fall through to disk-based bootstrap until"
        echo "      this is fixed. See nova-mind#171 for the canonical function shape."
        exit 1
    else
        echo -e "  ${CHECK} get_agent_bootstrap() smoke test passed for 'nova' (returned $SMOKE_OUT2 rows)"
    fi
else
    echo -e "  ${CHECK} get_agent_bootstrap() smoke test passed for '$SMOKE_AGENT' (returned $SMOKE_OUT rows)"
fi

if [ -f "$HOOK_DIR/handler.ts" ] && [ -f "$HOOK_DIR/HOOK.md" ]; then
    echo -e "  ${CHECK} Hook files verified at $HOOK_DIR"
else
    echo -e "  ${CROSS} Hook files missing at $HOOK_DIR"
    exit 1
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. (One-time) Migrate existing context files into the database:"
echo "     cd $SCRIPT_DIR && psql -d $DB_NAME -f sql/migrate-initial-context.sql"
echo ""
echo "  2. Restart the gateway to load updated hook code:"
echo "     systemctl --user restart openclaw-gateway.service"
echo ""
echo "  3. Smoke-test the database function:"
echo "     psql -d $DB_NAME -c \"SELECT count(*) FROM get_agent_bootstrap('nova');\""
echo ""
echo "Documentation: $SCRIPT_DIR/docs/MANAGEMENT.md"
