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
