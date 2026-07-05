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

# Mirrors the status symbols used by agent-install.sh so the inline helpers
# produce familiar output without sourcing the whole script.
CHECK_MARK="✅"
WARNING="⚠️"

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

    local new_json
    new_json=$(jq --arg db "$database" --arg user "$user" --arg pass "$password" \
        'if (.agent_chat // null) | type == "object" then
            .agent_chat |= . + {
                database: (.database // $db),
                user: (.user // $user),
                password: (.password // $pass)
            }
         else
            .agent_chat = {"database": $db, "user": $user, "password": $pass}
         end' "$pg_config" 2>/dev/null) || return 1

    # Only write if something changed.
    if [ "$(printf '%s\n' "$new_json" | jq -Sc .)" = "$(jq -Sc . < "$pg_config")" ]; then
        return 1
    fi

    printf '%s\n' "$new_json" >"${pg_config}.tmp" && \
        mv "${pg_config}.tmp" "$pg_config" && \
        chmod 600 "$pg_config"
}

_install_pg_notify_listener() {
    local source_script="$1"
    local source_service="$2"
    local target_dir="$3"
    local service_dir="$4"
    local logs_dir="$5"

    if [ ! -f "$source_script" ] || [ ! -f "$source_service" ]; then
        echo -e "  ${WARNING} pg-notify-listener source files not found (skipping)"
        return 1
    fi

    mkdir -p "$target_dir"
    mkdir -p "$service_dir"
    mkdir -p "$logs_dir"

    cp "$source_script" "$target_dir/pg-notify-listener.py"
    chmod +x "$target_dir/pg-notify-listener.py"
    echo -e "  ${CHECK_MARK} Installed pg-notify-listener.py → $target_dir"

    cp "$source_service" "$service_dir/pg-notify-listener.service"
    echo -e "  ${CHECK_MARK} Installed pg-notify-listener.service → $service_dir"

    if command -v systemctl &>/dev/null; then
        systemctl --user daemon-reload
        if systemctl --user is-active pg-notify-listener.service &>/dev/null; then
            if systemctl --user restart pg-notify-listener.service; then
                echo -e "  ${CHECK_MARK} Restarted pg-notify-listener.service"
            else
                echo -e "  ${WARNING} pg-notify-listener.service restart failed"
            fi
        else
            if systemctl --user enable pg-notify-listener.service &>/dev/null && \
               systemctl --user start pg-notify-listener.service; then
                echo -e "  ${CHECK_MARK} Enabled and started pg-notify-listener.service"
            else
                echo -e "  ${WARNING} pg-notify-listener.service enable/start failed"
            fi
        fi
    else
        echo -e "  ${WARNING} systemctl not available — service not started"
    fi
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
    run _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"
    run _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"
    run _ensure_pgpass_entry "localhost" "5432" "agent_chat" "nova" "secret1"

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

@test "agent_chat: merges missing keys without clobbering existing section" {
    local pg_config="$FAKE_HOME/postgres.json"
    cat > "$pg_config" <<'EOF'
{
  "host": "localhost",
  "database": "nova_memory",
  "user": "nova",
  "password": "secret1",
  "agent_chat": {
    "database": "agent_chat",
    "user": "nova"
  }
}
EOF

    run _ensure_agent_chat_postgres_json "$pg_config" "agent_chat" "nova" "secret1"
    [ "$status" -eq 0 ]

    [ "$(jq -r '.agent_chat.database' "$pg_config")" = "agent_chat" ]
    [ "$(jq -r '.agent_chat.user' "$pg_config")" = "nova" ]
    [ "$(jq -r '.agent_chat.password' "$pg_config")" = "secret1" ]
    [ "$(jq -r '.database' "$pg_config")" = "nova_memory" ]
}

@test "agent_chat: preserves existing section with different password (no clobber)" {
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
    "password": "manual-password",
    "host": "db.internal"
  }
}
EOF

    run _ensure_agent_chat_postgres_json "$pg_config" "agent_chat" "nova" "secret1"
    [ "$status" -eq 1 ]

    [ "$(jq -r '.agent_chat.password' "$pg_config")" = "manual-password" ]
    [ "$(jq -r '.agent_chat.host' "$pg_config")" = "db.internal" ]
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

# ─── pg-notify-listener deployment ─────────────────────────────────────────

@test "TC-listener: installs script, service unit, and starts service" {
    local fake_bin="$FAKE_HOME/bin"
    local calls_log="$FAKE_HOME/systemctl-calls.log"
    mkdir -p "$fake_bin"

    # The installer redirects stdout of some systemctl calls, so append to a
    # fixed log file directly rather than relying on stdout capture.
    cat > "$fake_bin/systemctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$calls_log"
if [ "\$2" = "is-active" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$fake_bin/systemctl"

    local src_dir="$FAKE_HOME/src"
    local tgt_dir="$FAKE_HOME/scripts"
    local svc_dir="$FAKE_HOME/systemd/user"
    local logs_dir="$FAKE_HOME/logs"
    mkdir -p "$src_dir"
    printf '#!/usr/bin/env python3\nprint("listen")\n' > "$src_dir/pg-notify-listener.py"
    printf '[Service]\nExecStart=python listener.py\n' > "$src_dir/pg-notify-listener.service"

    PATH="$fake_bin:$PATH" run _install_pg_notify_listener \
        "$src_dir/pg-notify-listener.py" \
        "$src_dir/pg-notify-listener.service" \
        "$tgt_dir" "$svc_dir" "$logs_dir"
    [ "$status" -eq 0 ]

    [ -x "$tgt_dir/pg-notify-listener.py" ]
    [ -f "$svc_dir/pg-notify-listener.service" ]
    [ -d "$logs_dir" ]

    grep -qxF -- "--user daemon-reload" "$calls_log"
    grep -qxF -- "--user is-active pg-notify-listener.service" "$calls_log"
    grep -qxF -- "--user enable pg-notify-listener.service" "$calls_log"
    grep -qxF -- "--user start pg-notify-listener.service" "$calls_log"
}

@test "TC-listener: skips install when source files are missing" {
    local tgt_dir="$FAKE_HOME/scripts"
    local svc_dir="$FAKE_HOME/systemd/user"
    local logs_dir="$FAKE_HOME/logs"

    run _install_pg_notify_listener \
        "$FAKE_HOME/no-such-script.py" \
        "$FAKE_HOME/no-such.service" \
        "$tgt_dir" "$svc_dir" "$logs_dir"
    [ "$status" -eq 1 ]

    [ ! -f "$tgt_dir/pg-notify-listener.py" ]
    [ ! -f "$svc_dir/pg-notify-listener.service" ]
}

@test "TC-listener: pg-notify-listener.py resolves pg_env repo-relative" {
    local listener="$REPO_ROOT/cognition/scripts/pg-notify-listener.py"
    # Resolves pg_env.py relative to the listener script (repo lib/), not from a
    # deployed ~/.openclaw/lib copy.
    grep -q 'os.path.dirname(os.path.abspath(__file__))' "$listener"
    grep -q 'sys.path.insert(0, _PG_ENV_DIR)' "$listener"
    grep -q 'from pg_env import load_pg_env' "$listener"
    # Must not regress to the old hardcoded ~/.openclaw/lib path.
    run grep -qE 'sys.path.insert.*\.openclaw.*lib' "$listener"
    [ "$status" -ne 0 ]
    # Must not hardcode an absolute workspace path.
    run grep -qF 'openclaw/workspace/nova-mind/lib' "$listener"
    [ "$status" -ne 0 ]
}

# ─── TC-68-adjacent / ordering / static checks ─────────────────────────────

@test "TC-68-adjacent: installer derives agent_chat DB from postgres.json" {
    grep -q "agent_chat_db=.*jq -r '.agent_chat.database" "$INSTALLER"
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

@test "Ordering: agent_chat DB config is provisioned before extension build" {
    local config_line
    local build_line
    config_line=$(grep -n "PostgreSQL password file and agent_chat DB config" "$INSTALLER" | head -1 | cut -d: -f1)
    build_line=$(grep -n "Building agent_chat TypeScript" "$INSTALLER" | head -1 | cut -d: -f1)
    [ -n "$config_line" ]
    [ -n "$build_line" ]
    [ "$config_line" -lt "$build_line" ]
}

@test "Ordering: pg-notify-listener is deployed before extension build" {
    local listener_line
    local build_line
    listener_line=$(grep -n "PostgreSQL NOTIFY listener" "$INSTALLER" | head -1 | cut -d: -f1)
    build_line=$(grep -n "Building agent_chat TypeScript" "$INSTALLER" | head -1 | cut -d: -f1)
    [ -n "$listener_line" ]
    [ -n "$build_line" ]
    [ "$listener_line" -lt "$build_line" ]
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
