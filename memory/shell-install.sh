#!/bin/bash
# shell-install.sh — Interactive setup for nova-memory
# Human-facing entry point that ensures all config is in place, then execs agent-install.sh.
#
# Flow:
# 1. Source lib/pg-env.sh (early — makes load_pg_env() available before any DB checks)
# 2. Check postgres.json for required fields; if complete, call load_pg_env() and test reachability
#    - Warns if PGPASSWORD is empty for a TCP host
#    - If config is incomplete or DB unreachable, prompts for connection details
#    - Exits immediately (non-zero) if stdin is not a TTY and config is needed
# 3. Check openclaw.json for API keys; prompts interactively if missing
# 4. exec agent-install.sh (which does all the real work: schema, hooks, scripts, skills)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="$HOME/.openclaw"
PG_CONFIG="$CONFIG_DIR/postgres.json"
OPENCLAW_CONFIG="$CONFIG_DIR/openclaw.json"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "═══════════════════════════════════════════"
echo "  nova-memory shell-install"
echo "═══════════════════════════════════════════"
echo ""

# ============================================
# Source libraries early (before any checks)
# ============================================
PG_ENV="$SCRIPT_DIR/memory/lib/pg-env.sh"
if [ ! -f "$PG_ENV" ]; then
    echo -e "  ${RED}❌${NC} $PG_ENV not found"
    exit 1
fi
source "$PG_ENV"

# Create config directory if needed
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"
    echo -e "  ${GREEN}✅${NC} Created $CONFIG_DIR"
fi

# ============================================
# Part 1: Database config (postgres.json)
# ============================================
echo "Database configuration..."

# Check if postgres.json exists and has all required fields (field presence only — load_pg_env handles parsing)
_pg_config_complete() {
    if [ ! -f "$PG_CONFIG" ]; then
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        return 1
    fi
    for field in host port database user; do
        local val
        val=$(jq -r ".$field // empty" "$PG_CONFIG" 2>/dev/null)
        if [ -z "$val" ]; then
            return 1
        fi
    done
    return 0
}

PG_COMPLETE=false
NEED_PROMPT=false

if _pg_config_complete; then
    # Config file looks structurally complete — load env and test reachability
    load_pg_env

    echo "  Resolved: PGHOST=$PGHOST PGDATABASE=${PGDATABASE:-(not set)} PGUSER=$PGUSER"

    # Empty password warning for TCP hosts
    if [[ "$PGHOST" != /* ]] && [ -z "${PGPASSWORD:-}" ]; then
        echo -e "  ${YELLOW}⚠️  PGPASSWORD is empty for a network host ($PGHOST)${NC}"
        echo "      The agent_chat plugin requires password auth for TCP connections."
        echo "      Consider adding a password to $PG_CONFIG"
    fi

    # Reachability check — PGPASSWORD is now exported by load_pg_env
    if psql -c "SELECT 1" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $PG_CONFIG exists and is complete"
        PG_COMPLETE=true
    else
        echo -e "  ${YELLOW}⚠️  $PG_CONFIG exists but database '$PGDATABASE' is not reachable${NC}"
        echo "  Reconfiguring database settings..."
        NEED_PROMPT=true
    fi
else
    if [ ! -f "$PG_CONFIG" ]; then
        : # No config file — will prompt
    elif ! command -v jq &>/dev/null; then
        echo -e "  ${YELLOW}⚠️  jq not installed — cannot validate $PG_CONFIG${NC}"
    else
        # File exists but is missing fields
        for field in host port database user; do
            val=$(jq -r ".$field // empty" "$PG_CONFIG" 2>/dev/null)
            if [ -z "$val" ]; then
                echo -e "  ${YELLOW}⚠️  $PG_CONFIG is missing '$field'${NC}"
            fi
        done
    fi
    NEED_PROMPT=true
fi

if [ "$NEED_PROMPT" = true ]; then
    # Non-interactive guard — don't hang if no TTY
    if ! [ -t 0 ]; then
        echo -e "  ${RED}❌${NC} Database configuration is required but stdin is not a TTY."
        echo "      Run this script interactively, or create $PG_CONFIG manually."
        exit 1
    fi

    # Prompt for database connection details
    DEFAULT_HOST="localhost"
    DEFAULT_PORT="5432"
    DEFAULT_USER="$(whoami)"
    DEFAULT_DB="$(PGDATABASE= resolve_agent_db)"

    echo ""
    echo "  Enter PostgreSQL connection details (press Enter for defaults):"
    echo ""

    read -rp "    Host [$DEFAULT_HOST]: " INPUT_HOST
    read -rp "    Port [$DEFAULT_PORT]: " INPUT_PORT
    read -rp "    Database [$DEFAULT_DB]: " INPUT_DB
    read -rp "    User [$DEFAULT_USER]: " INPUT_USER
    read -rsp "    Password []: " INPUT_PASS
    echo ""

    DB_HOST="${INPUT_HOST:-$DEFAULT_HOST}"
    DB_PORT="${INPUT_PORT:-$DEFAULT_PORT}"
    DB_NAME="${INPUT_DB:-$DEFAULT_DB}"
    DB_USER="${INPUT_USER:-$DEFAULT_USER}"
    DB_PASS="${INPUT_PASS:-}"

    cat > "$PG_CONFIG" <<EOF
{
  "host": "$DB_HOST",
  "port": $DB_PORT,
  "database": "$DB_NAME",
  "user": "$DB_USER",
  "password": "$DB_PASS"
}
EOF
    chmod 600 "$PG_CONFIG"
    echo -e "  ${GREEN}✅${NC} Wrote $PG_CONFIG (chmod 600)"

    # Reload env with the new config
    load_pg_env

    echo "  Resolved: PGHOST=$PGHOST PGDATABASE=${PGDATABASE:-(not set)} PGUSER=$PGUSER"

    # Empty password warning for TCP hosts (post-prompt)
    if [[ "$PGHOST" != /* ]] && [ -z "${PGPASSWORD:-}" ]; then
        echo -e "  ${YELLOW}⚠️  No password set for a network host ($PGHOST)${NC}"
        echo "      The agent_chat plugin requires password auth for TCP connections."
    fi
fi

# ============================================
# Part 2: API keys (SecretRef only)
# ============================================
echo ""
echo "API key configuration..."

# Ensure openclaw.json exists
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "  ${YELLOW}⚠️  $OPENCLAW_CONFIG not found — creating minimal config${NC}"
    echo '{}' > "$OPENCLAW_CONFIG"
fi

if ! command -v jq &>/dev/null; then
    echo -e "  ${RED}❌${NC} jq is required to manage openclaw.json"
    echo "      Install: sudo apt install jq"
    exit 1
fi

# Post-#309: installers never prompt for API keys and never write them as
# plaintext into openclaw.json. Keys are resolved via 1Password (nova-op) or
# gateway SecretRef configuration instead.
echo -e "  ${INFO} API keys are no longer stored in openclaw.json env.vars."
echo "      Configure them via one of:"
echo "        1. Gateway SecretRef providers (recommended): add an exec provider"
echo "           such as 1Password to openclaw.json secrets.providers and set"
echo "           the corresponding SecretRef in the plugin/model config."
echo "        2. For memory scripts run outside the gateway, edit"
echo "           ~/.openclaw/scripts/nova-op-item-map.json with your vault/item IDs."

# ============================================
# Part 3: Hand off to agent-install.sh
# ============================================
echo ""
echo "Config setup complete. Running agent-install.sh..."
echo ""
exec "$SCRIPT_DIR/agent-install.sh" "$@"
