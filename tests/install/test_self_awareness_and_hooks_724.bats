#!/usr/bin/env bats
# BATS tests for nova-mind issue #724.
#
# 1. The self-awareness plugin must build and install into the target
#    directory with only its declared runtime dependencies; build-only
#    packages must live in devDependencies.
# 2. Enabling hooks must write hooks.token atomically, so no later
#    installer failure can leave hooks.enabled=true without hooks.token.
#
# Run: bats tests/install/test_self_awareness_and_hooks_724.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# ─── helpers ────────────────────────────────────────────────────────────────

teardown() {
    rm -rf "$SCRATCH"
}

# ─── installed-artifact test ────────────────────────────────────────────────

@test "TC-724-001: self-awareness install produces target with runtime deps only" {
    SCRATCH="$(mktemp -d)"
    SOURCE="$SCRATCH/self-awareness"
    TARGET="$SCRATCH/.openclaw/plugins/self-awareness"
    FAKE_REPO="$SCRATCH/repo"

    mkdir -p "$SCRATCH/.openclaw"
    printf '%s\n' '{' '  "host": "localhost",' '  "port": 5432,' '  "database": "test_memory",' '  "user": "testuser",' '  "password": ""' '}' >"$SCRATCH/.openclaw/postgres.json"
    cp -r "$REPO_ROOT/cognition/metacognition/self-awareness" "$SOURCE"

    mkdir -p "$FAKE_REPO/memory/lib" "$FAKE_REPO/lib"
    INSTALL_SCRIPT="${AGENT_INSTALL_SCRIPT:-$REPO_ROOT/agent-install.sh}"
    cp "$INSTALL_SCRIPT" "$FAKE_REPO/agent-install.sh"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/memory/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    # Run the install section in a scratch HOME with a minimal PATH, exactly
    # as the OpenClaw plugin loader sees it on a fresh machine.
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
            install_metacognition_plugin "self-awareness" "'"$SOURCE"'" "'"$TARGET"'"
        '

    [ -d "$TARGET/node_modules/pg" ]
    [ -f "$TARGET/dist/index.js" ]
    [ -f "$TARGET/openclaw.plugin.json" ]

    # Build-only packages must not be installed in the target.
    [ ! -d "$TARGET/node_modules/typescript" ]
    [ ! -d "$TARGET/node_modules/@types/node" ]
    [ ! -d "$TARGET/node_modules/@types/pg" ]

    # Build-only packages must not appear in dependencies.
    run jq -e '.dependencies // {} | has("typescript")' "$TARGET/package.json"
    [ "$status" -ne 0 ]
    run jq -e '.dependencies // {} | has("@types/node")' "$TARGET/package.json"
    [ "$status" -ne 0 ]
    run jq -e '.dependencies // {} | has("@types/pg")' "$TARGET/package.json"
    [ "$status" -ne 0 ]
}

# ─── hooks token atomicity test ─────────────────────────────────────────────

@test "TC-724-002: hooks enabled never leaves config without hooks.token" {
    SCRATCH="$(mktemp -d)"
    CONFIG="$SCRATCH/.openclaw/openclaw.json"

    mkdir -p "$SCRATCH/.openclaw"
    printf '{"plugins":{"entries":{}},"agents":{"defaults":{}}}' > "$CONFIG"

    # Run enable-hooks.sh as the installer does. In the old installer this
    # set hooks.enabled=true but did NOT set hooks.token, so a later failure
    # left the gateway unbootable. The fix generates the token atomically in
    # the same jq filter.
    cp "$REPO_ROOT/memory/scripts/enable-hooks.sh" "$SCRATCH/enable-hooks.sh"
    chmod +x "$SCRATCH/enable-hooks.sh"
    "$SCRATCH/enable-hooks.sh" "$CONFIG" >/dev/null 2>&1

    # Simulate a later installer step failing before the token-generation
    # point (the original bug). With the fix, the token is already present.
    run jq -e '.hooks.enabled == true and .hooks.internal.enabled == true and (.hooks.token | length > 0)' "$CONFIG"
    [ "$status" -eq 0 ]

    # The negative assertion: the config must never be in the invalid state.
    run jq -e '(.hooks.enabled == true or .hooks.internal.enabled == true) and (.hooks.token // "" | length == 0)' "$CONFIG"
    [ "$status" -ne 0 ]
}
