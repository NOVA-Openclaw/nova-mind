#!/usr/bin/env bats
# BATS tests for nova-mind issue #726:
#   1. memory-extract installs as an extension with runtime deps only.
#   2. Upgrading from the legacy hook removes ~/.openclaw/hooks/memory-extract
#      and hooks.internal.entries["memory-extract"].
#   3. Re-running the installer leaves exactly one plugin entry and no hook
#      entry.
#
# Run: bats tests/install/test_memory_extract_plugin_726.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    SCRATCH="$(mktemp -d)"
    SOURCE="$SCRATCH/memory-extract"
    TARGET="$SCRATCH/.openclaw/extensions/memory-extract"
    FAKE_REPO="$SCRATCH/repo"

    mkdir -p "$SCRATCH/.openclaw"
    cp -r "$REPO_ROOT/memory/plugins/memory-extract" "$SOURCE"

    mkdir -p "$FAKE_REPO/lib"
    INSTALL_SCRIPT="${AGENT_INSTALL_SCRIPT:-$REPO_ROOT/agent-install.sh}"
    cp "$INSTALL_SCRIPT" "$FAKE_REPO/agent-install.sh"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"
}

teardown() {
    rm -rf "$SCRATCH"
}

# ─── installed-artifact test ────────────────────────────────────────────────

@test "TC-726-001: memory-extract installs as an extension with runtime deps only" {
    env -i \
        HOME="$SCRATCH" \
        PATH="/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="" \
        FORCE_INSTALL=0 \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
        '

    [ -f "$TARGET/dist/index.js" ]
    [ -f "$TARGET/openclaw.plugin.json" ]

    # No runtime dependencies are declared, but the install helper still
    # writes a package-lock if one was present; the target must not contain
    # build-only packages.
    [ ! -d "$TARGET/node_modules/typescript" ]
    [ ! -d "$TARGET/node_modules/@types/node" ]
}

# ─── upgrade-from-legacy-hook test ───────────────────────────────────────────

@test "TC-726-002: upgrade removes legacy hook directory and config entry" {
    # Simulate an existing legacy hook install and config entry.
    mkdir -p "$SCRATCH/.openclaw/hooks/memory-extract"
    touch "$SCRATCH/.openclaw/hooks/memory-extract/handler.ts"
    printf '{"plugins":{"entries":{},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"memory-extract":{"enabled":true},"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"

    env -i \
        HOME="$SCRATCH" \
        PATH="/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        FORCE_INSTALL=0 \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
        '

    # Legacy hook directory removed.
    [ ! -d "$SCRATCH/.openclaw/hooks/memory-extract" ]

    # Plugin entry present and enabled.
    run jq -e '.plugins.entries."memory-extract".enabled == true' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -eq 0 ]

    # Legacy hook config entry removed.
    run jq -e '.hooks.internal.entries["memory-extract"]' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -ne 0 ]

    # session-init must be untouched.
    run jq -e '.hooks.internal.entries["session-init"].enabled == true' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -eq 0 ]

    # The parent hooks.internal object and its enabled flag must survive.
    run jq -e '.hooks.internal.enabled == true' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -eq 0 ]
}

# ─── idempotency test ────────────────────────────────────────────────────────

@test "TC-726-003: re-run leaves exactly one plugin entry and no hook entry" {
    printf '{"plugins":{"entries":{},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"

    # First install.
    env -i \
        HOME="$SCRATCH" \
        PATH="/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        FORCE_INSTALL=0 \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
        '

    # Re-run with force to trigger the config write path again.
    env -i \
        HOME="$SCRATCH" \
        PATH="/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        FORCE_INSTALL=1 \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
        '

    # Exactly one memory-extract plugin entry.
    run jq '[.plugins.entries | keys[] | select(. == "memory-extract")] | length' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    # No memory-extract hook entry.
    run jq -e '.hooks.internal.entries["memory-extract"]' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -ne 0 ]
}

@test "TC-726-004: verify_config treats memory-extract as plugin and warns on legacy hook remnants" {
    # Stub psql so verify_config does not need a real database.
    mkdir -p "$SCRATCH/bin"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SCRATCH/bin/psql"
    chmod +x "$SCRATCH/bin/psql"

    # Clean state: plugin configured, session-init hook enabled, no legacy remnants.
    printf '{"plugins":{"entries":{"memory-extract":{"enabled":true}},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"
    printf '{"session-init":{"enabled":true}}' > "$SCRATCH/.openclaw/hooks.json"

    run env -i \
        HOME="$SCRATCH" \
        PATH="$SCRATCH/bin:/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        PGUSER="testuser" \
        DB_USER="testuser" \
        DB_NAME="test_memory" \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            verify_config
        '

    [ "$status" -eq 0 ]
    [[ "$output" == *"memory-extract plugin configured"* ]]
    [[ "$output" == *"Hook 'session-init' enabled"* ]]
    [[ "$output" != *"Legacy memory-extract hook entry still present"* ]]
    [[ "$output" != *"Legacy memory-extract hook directory still present"* ]]

    # Legacy hook config entry produces a warning.
    printf '{"plugins":{"entries":{"memory-extract":{"enabled":true}},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"memory-extract":{"enabled":true},"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"

    run env -i \
        HOME="$SCRATCH" \
        PATH="$SCRATCH/bin:/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        PGUSER="testuser" \
        DB_USER="testuser" \
        DB_NAME="test_memory" \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            verify_config
        '

    [ "$status" -eq 0 ]
    [[ "$output" == *"Legacy memory-extract hook entry still present"* ]]

    # Legacy hook directory produces a warning.
    printf '{"plugins":{"entries":{"memory-extract":{"enabled":true}},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"
    mkdir -p "$SCRATCH/.openclaw/hooks/memory-extract"

    run env -i \
        HOME="$SCRATCH" \
        PATH="$SCRATCH/bin:/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        PGUSER="testuser" \
        DB_USER="testuser" \
        DB_NAME="test_memory" \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            verify_config
        '

    [ "$status" -eq 0 ]
    [[ "$output" == *"Legacy memory-extract hook directory still present"* ]]
}

# ─── SE #1231 regression tests ──────────────────────────────────────────────

@test "TC-1231-001: memory-extract install tolerates OPENCLAW_CONFIG being unset under set -u" {
    # The r4 config exists but OPENCLAW_CONFIG is not exported. Mutation proof:
    # reverting _install_memory_extract_plugin to read bare $OPENCLAW_CONFIG
    # makes this fail with "unbound variable" under set -u.
    printf '{"plugins":{"entries":{},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"

    env -i \
        HOME="$SCRATCH" \
        PATH="/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        FORCE_INSTALL=0 \
        bash -c '
            set -eu
            source "$SCRIPT_DIR/agent-install.sh"
            _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
        '

    [ -f "$TARGET/dist/index.js" ]
    [ -f "$TARGET/openclaw.plugin.json" ]

    # The default config path is used when OPENCLAW_CONFIG is unset.
    run jq -e '.plugins.entries."memory-extract".enabled == true' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -eq 0 ]
}

@test "TC-1231-002: config write failure leaves legacy hook directory and entries untouched" {
    # Mutation proof: if the legacy hook directory is removed before the
    # plugin config is committed, corrupt JSON here would still delete it.
    mkdir -p "$SCRATCH/.openclaw/hooks/memory-extract"
    touch "$SCRATCH/.openclaw/hooks/memory-extract/handler.ts"
    printf '{"plugins":{"entries":{},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"memory-extract":{"enabled":true},"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"

    # Corrupt the config so the jq enable step fails.
    printf 'not-json{{' >> "$SCRATCH/.openclaw/openclaw.json"

    run env -i \
        HOME="$SCRATCH" \
        PATH="/usr/bin:/bin" \
        AGENT_INSTALL_TEST_MODE=1 \
        SCRIPT_DIR="$FAKE_REPO" \
        OPENCLAW_DIR="$SCRATCH/.openclaw" \
        OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
        FORCE_INSTALL=0 \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
        '

    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not enable memory-extract plugin in config"* ]]

    # Legacy hook directory must survive the abort.
    [ -d "$SCRATCH/.openclaw/hooks/memory-extract" ]

    # Legacy hook config entry must survive the abort. The file is corrupt,
    # so verify by raw text instead of jq.
    grep -q '"memory-extract"' "$SCRATCH/.openclaw/openclaw.json"
    grep -q '"enabled":true' "$SCRATCH/.openclaw/openclaw.json"

    # Plugin entry must NOT have been written.
    run jq -e '.plugins.entries."memory-extract"' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -ne 0 ]
}

@test "TC-1231-003: second run is idempotent and leaves no legacy remnants" {
    printf '{"plugins":{"entries":{},"load":{"paths":[]}},"hooks":{"internal":{"enabled":true,"entries":{"session-init":{"enabled":true}}}},"agents":{"defaults":{}}}' > "$SCRATCH/.openclaw/openclaw.json"

    for i in 1 2; do
        env -i \
            HOME="$SCRATCH" \
            PATH="/usr/bin:/bin" \
            AGENT_INSTALL_TEST_MODE=1 \
            SCRIPT_DIR="$FAKE_REPO" \
            OPENCLAW_DIR="$SCRATCH/.openclaw" \
            OPENCLAW_CONFIG="$SCRATCH/.openclaw/openclaw.json" \
            FORCE_INSTALL=0 \
            bash -c '
                set -e
                source "$SCRIPT_DIR/agent-install.sh"
                _install_memory_extract_plugin "'"$SOURCE"'" "'"$TARGET"'"
            '
    done

    run jq '[.plugins.entries | keys[] | select(. == "memory-extract")] | length' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run jq -e '.hooks.internal.entries["memory-extract"]' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -ne 0 ]
    run jq -e '.hooks.internal["memory-extract"]' "$SCRATCH/.openclaw/openclaw.json"
    [ "$status" -ne 0 ]
    [ ! -d "$SCRATCH/.openclaw/hooks/memory-extract" ]
}
