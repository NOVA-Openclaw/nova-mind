#!/usr/bin/env bats
# BATS test for nova-mind issue #598.
#
# The turn-context plugin must be installed into the target directory with
# only its declared runtime dependencies resolvable from that directory.
# Build-only packages must live in devDependencies.
#
# Run: bats tests/install/test_turn_context_installed_artifact_598.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    SCRATCH="$(mktemp -d)"
    SOURCE="$SCRATCH/turn-context"
    TARGET="$SCRATCH/.openclaw/plugins/turn-context"
    FAKE_REPO="$SCRATCH/repo"

    mkdir -p "$SCRATCH/.openclaw"
    cp -r "$REPO_ROOT/memory/plugins/turn-context" "$SOURCE"

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

@test "TC-598-001: turn-context install produces target with runtime deps only" {
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
        SOURCE="$SOURCE" \
        TARGET="$TARGET" \
        bash -c '
            set -e
            source "$SCRIPT_DIR/agent-install.sh"
            if declare -f _install_turn_context_plugin >/dev/null; then
                _install_turn_context_plugin "$SOURCE" "$TARGET"
            else
                # Pre-#598 behaviour: copy metadata and dist, skip runtime deps.
                mkdir -p "$TARGET/dist"
                for f in package.json openclaw.plugin.json tsconfig.json; do
                    [ -f "$SOURCE/$f" ] && cp "$SOURCE/$f" "$TARGET/$f"
                done
                touch "$TARGET/dist/index.js"
            fi
        '

    [ -d "$TARGET/node_modules/pg" ]
    [ -f "$TARGET/dist/index.js" ]
    [ -f "$TARGET/openclaw.plugin.json" ]

    # Every package listed in dependencies must resolve from the target dir.
    local dep
    for dep in $(jq -r '.dependencies // {} | keys[]' "$TARGET/package.json"); do
        (cd "$TARGET" && node -e "require.resolve('$dep')")
    done

    # Build-only packages must not appear in dependencies.
    run jq -e '.dependencies // {} | has("typescript")' "$TARGET/package.json"
    [ "$status" -ne 0 ]
    run jq -e '.dependencies // {} | has("@types/node")' "$TARGET/package.json"
    [ "$status" -ne 0 ]
    run jq -e '.dependencies // {} | has("@types/pg")' "$TARGET/package.json"
    [ "$status" -ne 0 ]
}
