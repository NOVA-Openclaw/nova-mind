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
echo "  nova-mind shell-install"
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

# Ensure postgres.json belongs to this peer: user must be $(whoami) and
# database must be <user>_memory as resolved by lib/pg-env.sh (nova-mind#778).
_validate_pg_ownership() {
    local expected_user expected_db
    expected_user=$(whoami)
    # Canonical DB for this peer, ignoring any inherited PGDATABASE (#774).
    expected_db=$(PGDATABASE= resolve_agent_db)
    if [ -n "${NOVA_MIND_ALLOW_FOREIGN_POSTGRES_JSON:-}" ]; then
        return 0
    fi
    if [ "${PGUSER:-}" != "$expected_user" ]; then
        echo -e "  ${RED}❌${NC} $PG_CONFIG belongs to user '${PGUSER:-}', but this installer is running as '$expected_user'."
        echo "      database must be '$expected_db' and user must be '$expected_user'."
        echo "      Remove or edit $PG_CONFIG, or set NOVA_MIND_ALLOW_FOREIGN_POSTGRES_JSON=1 to override."
        return 1
    fi
    if [ "${PGDATABASE:-}" != "$expected_db" ]; then
        echo -e "  ${RED}❌${NC} $PG_CONFIG points to database '${PGDATABASE:-}', but the agent database for '$expected_user' is '$expected_db'."
        echo "      A stale postgres.json from another peer will target the wrong database."
        echo "      Update $PG_CONFIG to database '$expected_db' and user '$expected_user', or remove it and re-run."
        return 1
    fi
    return 0
}

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

    if ! _validate_pg_ownership; then
        exit 1
    fi

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
    # Non-interactive path: if the environment already provides the database
    # and superuser details, write postgres.json from the env values instead
    # of hanging on a missing TTY (#743).
    if ! [ -t 0 ]; then
        if [ -n "${PGHOST:-}" ] && [ -n "${PGPORT:-}" ] && [ -n "${PGDATABASE:-}" ] && [ -n "${PGUSER:-}" ]; then
            cat > "$PG_CONFIG" <<EOF
{
  "host": "$PGHOST",
  "port": $PGPORT,
  "database": "$PGDATABASE",
  "user": "$PGUSER",
  "password": "${PGPASSWORD:-}"
}
EOF
            chmod 600 "$PG_CONFIG"
            echo -e "  ${GREEN}✅${NC} Wrote $PG_CONFIG from environment (non-interactive)"
            load_pg_env
            export PG_SUPERUSER="${PG_SUPERUSER:-postgres}"
            export PG_SUPERUSER_PASSWORD="${PG_SUPERUSER_PASSWORD:-}"
            export PG_SUPERUSER_HOST="${PG_SUPERUSER_HOST:-/var/run/postgresql}"
            echo -e "  ${GREEN}✅${NC} Superuser set to '$PG_SUPERUSER' (session-only, not persisted)"
            echo -e "  ${GREEN}✅${NC} Superuser host set to '$PG_SUPERUSER_HOST'"
            echo "  Resolved: PGHOST=$PGHOST PGDATABASE=${PGDATABASE:-(not set)} PGUSER=$PGUSER"
            NEED_PROMPT=false
        else
            echo -e "  ${RED}❌${NC} Database configuration is required but stdin is not a TTY."
            echo "      Run this script interactively, or create $PG_CONFIG manually."
            exit 1
        fi
    fi

    if [ "$NEED_PROMPT" = true ]; then
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
        echo ""

        # Prompt for postgres superuser credentials (session-only, NOT persisted)
        DEFAULT_SUPERUSER="postgres"
        DEFAULT_SUPERUSER_HOST="/var/run/postgresql"
        echo "  PostgreSQL superuser for schema operations (CREATE EXTENSION, DDL):"
        read -rp "    Superuser [$DEFAULT_SUPERUSER]: " INPUT_SUPERUSER
        read -rsp "    Superuser password []: " INPUT_SUPERUSER_PASS
        echo ""
        read -rp "    Superuser host (unix socket path or hostname) [$DEFAULT_SUPERUSER_HOST]: " INPUT_SUPERUSER_HOST
        echo ""

        DB_HOST="${INPUT_HOST:-$DEFAULT_HOST}"
        DB_PORT="${INPUT_PORT:-$DEFAULT_PORT}"
        DB_NAME="${INPUT_DB:-$DEFAULT_DB}"
        DB_USER="${INPUT_USER:-$DEFAULT_USER}"
        DB_PASS="${INPUT_PASS:-}"
        PG_SUPERUSER="${INPUT_SUPERUSER:-$DEFAULT_SUPERUSER}"
        PG_SUPERUSER_PASSWORD="${INPUT_SUPERUSER_PASS:-}"
        PG_SUPERUSER_HOST="${INPUT_SUPERUSER_HOST:-$DEFAULT_SUPERUSER_HOST}"

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

        # Reload env with the new config (this sets PGUSER/PGPASSWORD from the agent user)
        load_pg_env

        # Export superuser credentials for agent-install.sh (session-only)
        export PG_SUPERUSER="$PG_SUPERUSER"
        export PG_SUPERUSER_PASSWORD="$PG_SUPERUSER_PASSWORD"
        export PG_SUPERUSER_HOST="$PG_SUPERUSER_HOST"
        echo -e "  ${GREEN}✅${NC} Superuser set to '$PG_SUPERUSER' (session-only, not persisted)"
        echo -e "  ${GREEN}✅${NC} Superuser host set to '$PG_SUPERUSER_HOST'"

        echo "  Resolved: PGHOST=$PGHOST PGDATABASE=${PGDATABASE:-(not set)} PGUSER=$PGUSER"

        # Empty password warning for TCP hosts (post-prompt)
        if [[ "$PGHOST" != /* ]] && [ -z "${PGPASSWORD:-}" ]; then
            echo -e "  ${YELLOW}⚠️  No password set for a network host ($PGHOST)${NC}"
            echo "      The agent_chat plugin requires password auth for TCP connections."
        fi
    fi
fi

# Final guard: the resolved database/user must belong to this peer.
# This also blocks an inherited PGDATABASE that names another agent's DB (#774).
if ! _validate_pg_ownership; then
    exit 1
fi

# ============================================
# Part 2: API keys (openclaw.json env.vars as SecretRefs)
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
    echo "      Install: apt install jq"
    exit 1
fi

# Wire an env.var as a SecretRef. Caller must set cfg/cfg_tmp.
# Args: <env_var_name> <provider_name> <secret_id>
_wire_env_secretref() {
    local var_name="$1"
    local provider="$2"
    local secret_id="$3"
    local cfg="$OPENCLAW_CONFIG"
    local cfg_tmp="$OPENCLAW_CONFIG_TMP"

    # Caller can pre-inject the value (e.g. from a parent plugin or test).
    if [ -n "${!var_name:-}" ]; then
        echo -e "  ${GREEN}✅${NC} $var_name set in environment"
        return 0
    fi

    local existing_exists existing_type
    existing_exists=$(jq -e --arg v "$var_name" '.env.vars | has($v)' "$cfg" >/dev/null 2>&1 && echo 1 || echo 0)
    if [ "$existing_exists" -eq 1 ]; then
        existing_type=$(jq -r --arg v "$var_name" '.env.vars[$v] | type' "$cfg" 2>/dev/null)
        if [ "$existing_type" = "string" ]; then
            echo -e "  ${YELLOW}⚠️${NC} $var_name is a plaintext string in $cfg; leaving it unchanged but it should be migrated to a SecretRef"
        else
            echo -e "  ${GREEN}✅${NC} $var_name already configured as SecretRef in $cfg"
        fi
        return 0
    fi

    local provider_exists
    provider_exists=$(jq --arg p "$provider" -e '.secrets.providers[$p]' "$cfg" >/dev/null 2>&1 && echo 1 || echo 0)
    if [ "$provider_exists" -ne 1 ]; then
        echo -e "  ${YELLOW}⚠️${NC} $var_name not wired: provider '$provider' is not defined in openclaw.json secrets.providers"
        echo "      Add the provider and re-run shell-install.sh to wire the SecretRef automatically."
        return 0
    fi

    jq --arg v "$var_name" --arg provider "$provider" --arg id "$secret_id" '
        .env.vars = (.env.vars // {})
        | .env.vars[$v] = {
            "source": "exec",
            "provider": $provider,
            "id": $id
          }
    ' "$cfg_tmp" >"${cfg_tmp}.secret" && mv "${cfg_tmp}.secret" "$cfg_tmp"

    local backup_cfg
    backup_cfg=$(mktemp "${cfg}.bak.validate.XXXXXX")
    cp "$cfg" "$backup_cfg"
    if mv "$cfg_tmp" "$cfg"; then
        if command -v openclaw &>/dev/null && openclaw config validate --help &>/dev/null; then
            if openclaw config validate >/dev/null 2>&1; then
                echo -e "  ${GREEN}✅${NC} $var_name SecretRef wired (provider=$provider, id=$secret_id)"
            else
                echo -e "  ${RED}❌${NC} openclaw config validate failed after wiring $var_name SecretRef; restoring backup"
                mv "$backup_cfg" "$cfg"
                rm -f "$cfg_tmp"
                OPENCLAW_CONFIG_TMP=$(mktemp "${cfg}.tmp.XXXXXX")
                cp "$cfg" "$OPENCLAW_CONFIG_TMP"
                return 1
            fi
        else
            echo -e "  ${GREEN}✅${NC} $var_name SecretRef wired (provider=$provider, id=$secret_id)"
        fi
        # Recreate the working temp file so subsequent keys can be wired.
        cp "$cfg" "$cfg_tmp"
    else
        echo -e "  ${RED}❌${NC} Could not write updated OpenClaw config for $var_name"
        rm -f "$backup_cfg"
        return 1
    fi
    rm -f "$backup_cfg"
}

OPENCLAW_CONFIG_TMP=$(mktemp "${OPENCLAW_CONFIG}.tmp.XXXXXX")
cp "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG_TMP"

# OPENAI_API_KEY: default provider op_openai, secret id "value".
# Override provider/id via OPENAI_SECRET_PROVIDER / OPENAI_SECRET_ID.
OPENAI_SECRET_PROVIDER="${OPENAI_SECRET_PROVIDER:-op_openai}"
OPENAI_SECRET_ID="${OPENAI_SECRET_ID:-value}"
_wire_env_secretref "OPENAI_API_KEY" "$OPENAI_SECRET_PROVIDER" "$OPENAI_SECRET_ID" || true

# ANTHROPIC_API_KEY: default provider op_anthropic, secret id "value".
# Override provider/id via ANTHROPIC_SECRET_PROVIDER / ANTHROPIC_SECRET_ID.
ANTHROPIC_SECRET_PROVIDER="${ANTHROPIC_SECRET_PROVIDER:-op_anthropic}"
ANTHROPIC_SECRET_ID="${ANTHROPIC_SECRET_ID:-value}"
_wire_env_secretref "ANTHROPIC_API_KEY" "$ANTHROPIC_SECRET_PROVIDER" "$ANTHROPIC_SECRET_ID" || true

rm -f "$OPENCLAW_CONFIG_TMP"

# ============================================
# Part 3: Hand off to agent-install.sh
# ============================================
echo ""
echo "Config setup complete. Running agent-install.sh..."
echo ""
if [ -n "${SHELL_INSTALL_TEST_SKIP_AGENT_INSTALL:-}" ]; then
    echo "  (test mode: skipping agent-install.sh invocation)"
    exit 0
fi
exec "$SCRIPT_DIR/agent-install.sh" "$@"

