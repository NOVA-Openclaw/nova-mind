#!/bin/bash
# shell-install.sh — Prerequisite-checking wrapper for nova-relationships
# Non-interactive. Validates that nova-memory is installed and DB is reachable,
# then execs agent-install.sh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="$HOME/.openclaw"
PG_CONFIG="$CONFIG_DIR/postgres.json"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "═══════════════════════════════════════════"
echo "  nova-relationships shell-install"
echo "═══════════════════════════════════════════"
echo ""

# ============================================
# Part 1: Check for jq
# ============================================
if ! command -v jq &>/dev/null; then
    echo -e "${RED}❌ Error: jq is required${NC}" >&2
    echo "   Install: sudo apt install jq  (Debian/Ubuntu)" >&2
    echo "            brew install jq       (macOS)" >&2
    echo "            sudo dnf install jq   (Fedora/RHEL)" >&2
    exit 1
fi

# ============================================
# Part 2: Check for postgres.json OR PG env vars
# ============================================
echo "Checking database configuration..."

HAS_PG_CONFIG=false
HAS_PG_ENV_VARS=false

# Check if postgres.json exists
if [ -f "$PG_CONFIG" ]; then
    HAS_PG_CONFIG=true
fi

# Check if PG env vars are set
if [ -n "${PGHOST:-}" ] && [ -n "${PGDATABASE:-}" ] && [ -n "${PGUSER:-}" ]; then
    HAS_PG_ENV_VARS=true
fi

# Error if NEITHER exists
if [ "$HAS_PG_CONFIG" = false ] && [ "$HAS_PG_ENV_VARS" = false ]; then
    echo -e "${RED}❌ Error: No database configuration found${NC}" >&2
    echo "" >&2
    echo "nova-memory must be installed first. Run nova-memory/shell-install.sh to configure database settings." >&2
    echo "" >&2
    echo "Alternatively, set PG environment variables: PGHOST, PGDATABASE, PGUSER" >&2
    exit 1
fi

# ============================================
# Part 3: Validate postgres.json if present
# ============================================
if [ "$HAS_PG_CONFIG" = true ]; then
    echo -e "  ${GREEN}✅${NC} Found $PG_CONFIG"
    
    # Validate required fields
    MISSING_FIELDS=()
    for field in host port database user; do
        val=$(jq -r ".$field // empty" "$PG_CONFIG" 2>/dev/null)
        if [ -z "$val" ]; then
            MISSING_FIELDS+=("$field")
        fi
    done
    
    if [ ${#MISSING_FIELDS[@]} -gt 0 ]; then
        echo -e "${RED}❌ Error: $PG_CONFIG is incomplete${NC}" >&2
        echo "   Missing required fields: ${MISSING_FIELDS[*]}" >&2
        echo "" >&2
        echo "Re-run nova-memory/shell-install.sh to reconfigure database settings." >&2
        exit 1
    fi
    
    echo "  All required fields present (host, port, database, user)"
elif [ "$HAS_PG_ENV_VARS" = true ]; then
    echo -e "  ${GREEN}✅${NC} Using PG environment variables"
    echo "  PGHOST=$PGHOST PGDATABASE=$PGDATABASE PGUSER=$PGUSER"
fi

# ============================================
# Part 4: Load pg-env.sh
# ============================================
echo ""
echo "Loading environment..."

PG_ENV="$HOME/.openclaw/lib/pg-env.sh"
if [ ! -f "$PG_ENV" ]; then
    echo -e "${RED}❌ Error: pg-env.sh not found${NC}" >&2
    echo "   Expected: $PG_ENV" >&2
    echo "" >&2
    echo "pg-env.sh not found — is nova-memory installed?" >&2
    echo "Run nova-memory/shell-install.sh first to install shared library files." >&2
    exit 1
fi

# Source pg-env.sh to load database config
source "$PG_ENV"
if [ "$HAS_PG_CONFIG" = true ]; then
    load_pg_env
fi

echo -e "  ${GREEN}✅${NC} Loaded pg-env.sh"

# ============================================
# Part 5: Optionally load env-loader.sh (non-critical)
# ============================================
ENV_LOADER="$HOME/.openclaw/lib/env-loader.sh"
if [ -f "$ENV_LOADER" ]; then
    source "$ENV_LOADER"
    echo -e "  ${GREEN}✅${NC} Loaded env-loader.sh"
else
    echo -e "  ${YELLOW}⚠️${NC}  env-loader.sh not found (optional, skipping)"
fi

# ============================================
# Part 6: Test DB reachability
# ============================================
echo ""
echo "Testing database connectivity..."
echo "  Connecting to: $PGHOST:${PGPORT:-5432}/$PGDATABASE as $PGUSER"

# Create temp file for error capture
TEMP_ERROR=$(mktemp)
trap 'rm -f "$TEMP_ERROR"' EXIT

if ! psql -c "SELECT 1" >"$TEMP_ERROR" 2>&1; then
    echo -e "${RED}❌ Error: Cannot connect to PostgreSQL${NC}" >&2
    echo "" >&2
    echo "Connection details:" >&2
    echo "  Host:     $PGHOST" >&2
    echo "  Port:     ${PGPORT:-5432}" >&2
    echo "  Database: $PGDATABASE" >&2
    echo "  User:     $PGUSER" >&2
    echo "" >&2
    echo "psql error:" >&2
    cat "$TEMP_ERROR" >&2
    exit 1
fi

echo -e "  ${GREEN}✅${NC} Database is reachable"

# ============================================
# Part 7: Exec agent-install.sh
# ============================================
echo ""
echo "Prerequisite checks complete. Running agent-install.sh..."
echo ""

exec "$SCRIPT_DIR/agent-install.sh" "$@"
