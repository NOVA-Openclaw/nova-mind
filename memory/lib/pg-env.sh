#!/bin/bash
# pg-env.sh — Centralized PostgreSQL config loader
# Source this file and call load_pg_env() to set PG* env vars.
#
# Resolution order: ENV vars → ~/.openclaw/postgres.json → defaults
# Issue: nova-memory #94

load_pg_env() {
  local config="${HOME}/.openclaw/postgres.json"
  local json=""

  # Try to read config file
  if [ -f "$config" ] && [ -r "$config" ]; then
    json=$(cat "$config" 2>/dev/null) || json=""
    # Validate JSON
    if [ -n "$json" ]; then
      if ! echo "$json" | jq empty 2>/dev/null; then
        echo "WARNING: Malformed JSON in $config, ignoring config file" >&2
        json=""
      fi
    fi
  fi

  # Helper: get value from JSON, returns empty for null/missing/empty
  _pg_json_val() {
    local key="$1"
    if [ -n "$json" ]; then
      local val
      val=$(echo "$json" | jq -r ".$key // empty" 2>/dev/null)
      # jq returns "null" for null with -r if we don't use // empty
      # // empty handles null. Also filter empty strings.
      if [ -n "$val" ]; then
        echo "$val"
      fi
    fi
  }

  # For each var: if ENV is set and non-empty, keep it; else try config; else default
  # Empty ENV strings are treated as unset (${VAR:-} expands to empty, triggering fallback)

  local val

  val="${PGHOST:-$(_pg_json_val host)}"
  export PGHOST="${val:-localhost}"

  val="${PGPORT:-$(_pg_json_val port)}"
  export PGPORT="${val:-5432}"

  val="${PGUSER:-$(_pg_json_val user)}"
  export PGUSER="${val:-$(whoami)}"

  # No defaults for PGDATABASE and PGPASSWORD
  val="${PGDATABASE:-$(_pg_json_val database)}"
  if [ -n "$val" ]; then
    export PGDATABASE="$val"
  fi

  val="${PGPASSWORD:-$(_pg_json_val password)}"
  if [ -n "$val" ]; then
    export PGPASSWORD="$val"
  fi
}
