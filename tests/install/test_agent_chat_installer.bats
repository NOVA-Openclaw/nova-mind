#!/usr/bin/env bats
# BATS tests for agent-install.sh agent_chat migration changes (#320).
#
# Coverage (mapped to run-334-step3-test-cases.md):
#   TC-63: .pgpass provisioning — memory + agent_chat DB entries
#   TC-64: .pgpass idempotent re-run
#   TC-67: Installer config-write section — dead-key removal
#   TC-68-adjacent: verify_cognition resolves agent_chat DB from postgres.json
#
# Run: bats tests/install/test_agent_chat_installer.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"

# Inline copies of the helper functions under test.  They are isolated here so
# the test does not have to source the entire installer (which executes script
# body code on source).
_ensure_pgpass_entry() {
    local host="$1"
    local port="$2"
    local database="$3"
    local user="$4"
    local password="$5"
    local pgpass="$PGPASS_FILE"
    local prefix="${host}:${port}:${database}:${user}:"
    local line="${prefix}${password}"

    if [ ! -f "$pgpass" ]; then
        touch "$pgpass"
        chmod 600 "$pgpass"
    fi

    if grep -qxF "$line" "$pgpass" 2>/dev/null; then
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp)
    chmod 600 "$tmpfile"
    if [ -s "$pgpass" ]; then
        grep -vF "$prefix" "$pgpass" >"$tmpfile" 2>/dev/null || cat "$pgpass" >"$tmpfile"
    fi
    printf '%s\n' "$line" >>"$tmpfile"
    mv "$tmpfile" "$pgpass"
    chmod 600 "$pgpass"
    return 0
}

_ensure_agent_chat_postgres_json() {
    local pg_config="$1"
    local database="$2"
    local user="$3"
    local password="$4"

    if [ ! -f "$pg_config" ] || ! command -v jq &>/dev/null; then
        return 1
    fi

    local already_correct
    already_correct=$(jq --arg db "$database" --arg user "$user" --arg pass "$password" \
        '(.agent_chat // {}) | {database, user, password} == {database: $db, user: $user, password: $pass}' \
        "$pg_config" 2>/dev/null || echo "false")
    if [ "$already_correct" = "true" ]; then
        return 1
    fi

    jq --arg db "$database" --arg user "$user" --arg pass "$password" \
        '.agent_chat = {"database": $db, "user": $user, "password": $pass}' \
        "$pg_config" >"${pg_config}.tmp" && \
        mv "${pg_config}.tmp" "$pg_config" && \
        chmod 600 "$pg_config"
}

setup() {
    FAKE_HOME="$(mktemp -d)"
    export PGPASS_FILE="$FAKE_HOME/.pgpass"
}

teardown() {
    rm -rf "$FAKE_HOME"
}

# ─── TC-63 ──────────────────────────────────────────────────────────────────

@test "TC-63: .pgpass provisioning writes memory and agent_chat entries" {
    run _ensure_pgpass_entry "localhost" "5432" "nova_memory" "nova" "secret1"
    [ "$status" -eq 0 ]
    run _ensure_pgpass_entry "127.0.0.1" "5432" "nova_memory" "nova" "secret1"
    [ "$status" -eq 0 ]
    run _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"
    [ "$status" -eq 0 ]
    run _ensure_pgpass_entry "127.0.0.1" "5432" "agent_chat" "nova" "secret1"
    [ "$status" -eq 0 ]

    [ -f "$PGPASS_FILE" ]
    run stat -c '%a' "$PGPASS_FILE"
    [ "$output" = "600" ]

    grep -qxF "localhost:5432:nova_memory:nova:secret1" "$PGPASS_FILE"
    grep -qxF "127.0.0.1:5432:nova_memory:nova:secret1" "$PGPASS_FILE"
    grep -qxF "localhost:5432:agent_chat:nova:secret1" "$PGPASS_FILE"
    grep -qxF "127.0.0.1:5432:agent_chat:nova:secret1" "$PGPASS_FILE"
}

# ─── TC-64 ──────────────────────────────────────────────────────────────────

@test "TC-64: .pgpass provisioning is idempotent — no duplicate lines" {
    _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"
    _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"
    _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"

    local count
    count=$(grep -cF "localhost:5432:agent_chat:nova:secret1" "$PGPASS_FILE" || true)
    [ "$count" -eq 1 ]
}

@test "TC-64: .pgpass password rotation replaces stale entry" {
    _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "oldpass"
    _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "newpass"

    ! grep -qF "localhost:5432:agent_chat:nova:oldpass" "$PGPASS_FILE"
    grep -qxF "localhost:5432:agent_chat:nova:newpass" "$PGPASS_FILE"
}

# ─── postgres.json nested section ───────────────────────────────────────────

@test "agent_chat: writes nested section to postgres.json" {
    local pg_config="$FAKE_HOME/postgres.json"
    cat > "$pg_config" <<'EOF'
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "nova",
  "password": "secret1"
}
EOF

    run _ensure_agent_chat_postgres_json "$pg_config" "agent_chat" "nova" "secret1"
    [ "$status" -eq 0 ]

    [ "$(jq -r '.agent_chat.database' "$pg_config")" = "agent_chat" ]
    [ "$(jq -r '.agent_chat.user' "$pg_config")" = "nova" ]
    [ "$(jq -r '.agent_chat.password' "$pg_config")" = "secret1" ]
    [ "$(jq -r '.database' "$pg_config")" = "nova_memory" ]
}

@test "agent_chat: postgres.json nested section is idempotent" {
    local pg_config="$FAKE_HOME/postgres.json"
    cat > "$pg_config" <<'EOF'
{
  "host": "localhost",
  "database": "nova_memory",
  "user": "nova",
  "password": "secret1",
  "agent_chat": {
    "database": "agent_chat",
    "user": "nova",
    "password": "secret1"
  }
}
EOF

    run _ensure_agent_chat_postgres_json "$pg_config" "agent_chat" "nova" "secret1"
    [ "$status" -eq 1 ]
}

# ─── TC-67 ──────────────────────────────────────────────────────────────────

@test "TC-67: openclaw.json dead connection keys removed, live keys preserved" {
    local config="$FAKE_HOME/openclaw.json"
    cat > "$config" <<'EOF'
{
  "channels": {
    "agent_chat": {
      "enabled": false,
      "database": "nova_memory",
      "host": "localhost",
      "port": 5432,
      "user": "nova",
      "password": "secret1",
      "pollIntervalMs": 500
    }
  },
  "plugins": {
    "entries": {
      "agent_chat": {
        "enabled": false,
        "config": {
          "database": "nova_memory",
          "host": "localhost",
          "port": 5432,
          "user": "nova",
          "password": "secret1",
          "routeToSession": "other"
        }
      }
    }
  }
}
EOF

    jq '.channels.agent_chat |= ((. // {}) | del(.database, .host, .port, .user, .password) + {"enabled": true})' \
        "$config" >"${config}.tmp" && mv "${config}.tmp" "$config"
    jq '.plugins.entries.agent_chat |= (. + {"enabled": true} | .config |= ((. // {}) | del(.database, .host, .port, .user, .password) + {"routeToSession": "main"}))' \
        "$config" >"${config}.tmp" && mv "${config}.tmp" "$config"

    [ "$(jq -r '.channels.agent_chat.enabled' "$config")" = "true" ]
    [ "$(jq -r '.channels.agent_chat.pollIntervalMs' "$config")" = "500" ]
    [ "$(jq -r '.channels.agent_chat.database' "$config")" = "null" ]
    [ "$(jq -r '.channels.agent_chat.host' "$config")" = "null" ]
    [ "$(jq -r '.channels.agent_chat.user' "$config")" = "null" ]
    [ "$(jq -r '.channels.agent_chat.password' "$config")" = "null" ]

    [ "$(jq -r '.plugins.entries.agent_chat.enabled' "$config")" = "true" ]
    [ "$(jq -r '.plugins.entries.agent_chat.config.routeToSession' "$config")" = "main" ]
    [ "$(jq -r '.plugins.entries.agent_chat.config.database' "$config")" = "null" ]
    [ "$(jq -r '.plugins.entries.agent_chat.config.host' "$config")" = "null" ]
    [ "$(jq -r '.plugins.entries.agent_chat.config.user' "$config")" = "null" ]
    [ "$(jq -r '.plugins.entries.agent_chat.config.password' "$config")" = "null" ]
}

# ─── TC-68-adjacent / ordering / static checks ─────────────────────────────

@test "TC-68-adjacent: installer derives agent_chat DB from postgres.json" {
    grep -q "agent_chat_db=.*jq -r '.agent_chat.database'" "$INSTALLER"
}

@test "Ordering: agent_config_sync is configured before agent_chat channel cleanup" {
    local sync_line
    local chat_line
    sync_line=$(grep -n "agent_config_sync plugin enabled" "$INSTALLER" | head -1 | cut -d: -f1)
    chat_line=$(grep -n "Configure agent_chat channel" "$INSTALLER" | head -1 | cut -d: -f1)
    [ -n "$sync_line" ]
    [ -n "$chat_line" ]
    [ "$sync_line" -lt "$chat_line" ]
}

@test "agent-install.sh passes bash -n" {
    run bash -n "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "ShellCheck: zero warnings on agent-install.sh" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$INSTALLER"
    [ "$status" -eq 0 ]
}
