#!/bin/bash
# env-loader.sh — Resolve secrets via nova-op and export them into the environment.
#
# Source this file and call load_openclaw_env() to export env vars.
#
# Design:
#   - Reads a JSON item map (default: ~/.openclaw/scripts/nova-op-item-map.json).
#   - For each variable in the map that is not already set and non-empty,
#     resolves the value with `nova-op item get <item> --vault <vault>
#     --field <field> --reveal`.
#   - Fails loudly on missing nova-op, unreadable map, or resolution failure.
#   - Never reads .env, secrets.env, .bash_env, or openclaw.json env.vars for
#     secret values.
#
# Issue: nova-workspace#309

load_openclaw_env() {
  local config_path="${1:-${HOME}/.openclaw/scripts/nova-op-item-map.json}"

  # Ensure nova-op is available.
  if ! command -v nova-op >/dev/null 2>&1; then
    echo "env-loader: nova-op not found in PATH" >&2
    return 1
  fi

  # Ensure the item map exists and is readable.
  if [ ! -f "$config_path" ]; then
    echo "env-loader: item map not found: $config_path" >&2
    return 1
  fi
  if [ ! -r "$config_path" ]; then
    echo "env-loader: item map not readable: $config_path" >&2
    return 1
  fi

  # Validate JSON.
  if ! jq empty "$config_path" 2>/dev/null; then
    echo "env-loader: item map is not valid JSON: $config_path" >&2
    return 1
  fi

  # Collect variable names from the map, skipping metadata keys.
  local vars
  vars=$(jq -r 'to_entries[] | select(.value | type == "object") | .key' "$config_path" 2>/dev/null)
  if [ -z "$vars" ]; then
    echo "env-loader: no secret entries found in item map: $config_path" >&2
    return 1
  fi

  local had_error=0
  local var
  while IFS= read -r var; do
    [ -z "$var" ] && continue

    # Already set and non-empty: keep existing value (plugin-injected keys win).
    local current
    eval "current=\${$var:-}"
    if [ -n "$current" ]; then
      continue
    fi

    local item field vault
    item=$(jq -r --arg k "$var" '.[$k].item // empty' "$config_path" 2>/dev/null)
    field=$(jq -r --arg k "$var" '.[$k].field // empty' "$config_path" 2>/dev/null)
    vault=$(jq -r --arg k "$var" '.[$k].vault // empty' "$config_path" 2>/dev/null)

    if [ -z "$item" ] || [ -z "$field" ] || [ -z "$vault" ]; then
      echo "env-loader: incomplete map entry for $var in $config_path" >&2
      had_error=1
      continue
    fi

    # Reject placeholder values that have not been replaced.
    if [ "$item" = "REPLACE_WITH_ITEM_ID" ] || [ "$vault" = "REPLACE_WITH_VAULT_ID" ]; then
      echo "env-loader: $var still contains placeholder values in $config_path; replace them with real vault/item IDs" >&2
      had_error=1
      continue
    fi

    local value
    value=$(nova-op item get "$item" --vault "$vault" --field "$field" --reveal 2>&1) || {
      local rc=$?
      echo "env-loader: failed to resolve $var (item=$item field=$field vault=$vault, rc=$rc): $value" >&2
      had_error=1
      continue
    }

    if [ -z "$value" ]; then
      echo "env-loader: resolved empty value for $var (item=$item field=$field vault=$vault)" >&2
      had_error=1
      continue
    fi

    export "$var=$value"
  done <<< "$vars"

  if [ "$had_error" -ne 0 ]; then
    return 1
  fi

  return 0
}
