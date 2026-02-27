#!/bin/bash
# shell-install.sh - Environment wrapper for humans
# Sets up shell environment before calling agent-install.sh

# Load database config from postgres.json if available
PG_CONFIG="$HOME/.openclaw/postgres.json"
if [ -f "$PG_CONFIG" ] && command -v jq &>/dev/null; then
    _pg_val() { jq -r ".$1 // empty" "$PG_CONFIG" 2>/dev/null; }
    [ -z "${PGHOST:-}" ]     && val=$(_pg_val host)     && [ -n "$val" ] && export PGHOST="$val"
    [ -z "${PGPORT:-}" ]     && val=$(_pg_val port)     && [ -n "$val" ] && export PGPORT="$val"
    [ -z "${PGDATABASE:-}" ] && val=$(_pg_val database) && [ -n "$val" ] && export PGDATABASE="$val"
    [ -z "${PGUSER:-}" ]     && val=$(_pg_val user)     && [ -n "$val" ] && export PGUSER="$val"
    [ -z "${PGPASSWORD:-}" ] && val=$(_pg_val password) && [ -n "$val" ] && export PGPASSWORD="$val"
fi

# Set defaults for anything not loaded from config
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-$(whoami)}"
DB_USER_CLEAN="${PGUSER//-/_}"
export PGDATABASE="${PGDATABASE:-${DB_USER_CLEAN}_memory}"
export OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace-coder}"

echo "Environment configured:"
echo "  PGUSER=$PGUSER"
echo "  PGDATABASE=$PGDATABASE"
echo "  OPENCLAW_WORKSPACE=$OPENCLAW_WORKSPACE"
echo ""

# Load API keys from openclaw.json if env-loader is available
ENV_LOADER="$HOME/.openclaw/lib/env-loader.sh"
if [ -f "$ENV_LOADER" ]; then
    source "$ENV_LOADER"
    load_openclaw_env 2>/dev/null || true
fi

# Call the agent installer
exec "$(dirname "$0")/agent-install.sh" "$@"
