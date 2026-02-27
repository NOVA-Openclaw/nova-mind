#!/bin/bash
# env-loader.sh — Load env.vars from ~/.openclaw/openclaw.json
# Source this file and call load_openclaw_env() to export env vars.
#
# Resolution order: ENV vars already set take precedence → openclaw.json env.vars
# Issue: nova-memory #98

load_openclaw_env() {
  local config="${HOME}/.openclaw/openclaw.json"
  local json=""

  # Try to read config file
  if [ -f "$config" ] && [ -r "$config" ]; then
    json=$(cat "$config" 2>/dev/null) || json=""
    # Validate JSON
    if [ -n "$json" ]; then
      if ! echo "$json" | jq empty 2>/dev/null; then
        echo "WARNING: Malformed JSON in $config, ignoring config file" >&2
        json=""
        return 1
      fi
    fi
  else
    return 0
  fi

  if [ -z "$json" ]; then
    return 0
  fi

  # Extract env.vars keys
  local keys
  keys=$(echo "$json" | jq -r '.env.vars | if type == "object" then keys[] else empty end' 2>/dev/null) || return 0

  local key val
  while IFS= read -r key; do
    [ -z "$key" ] && continue

    # If ENV var is already set and non-empty, keep it (precedence)
    local current
    eval "current=\${$key:-}"
    if [ -n "$current" ]; then
      continue
    fi

    # Get value from config
    val=$(echo "$json" | jq -r --arg k "$key" '.env.vars[$k] // empty' 2>/dev/null)
    if [ -n "$val" ]; then
      export "$key=$val"
    fi
  done <<< "$keys"
}
