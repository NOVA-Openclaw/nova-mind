#!/usr/bin/env bats
# BATS tests for agent-install.sh fixes:
#   #722: TypeScript build dependency install must use --legacy-peer-deps and
#         surface a clear error when npm fails.
#   #723: gateway.reload.mode must be "hybrid" (not "hot") and must not
#         overwrite an existing valid value (off|hybrid).
#
# Run: bats tests/install/test_agent_install_722_723.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    FAKE_OPENCLAW="$FAKE_HOME/.openclaw"
    mkdir -p "$FAKE_OPENCLAW"

    # Minimum postgres.json needed for the installer to source pg-env.sh.
    printf '%s\n' '{' '  "host": "localhost",' '  "port": 5432,' '  "database": "test_memory",' '  "user": "testuser",' '  "password": ""' '}' >"$FAKE_OPENCLAW/postgres.json"

    # Copy the installer and stub its sourced libs so we can source it
    # without a real PostgreSQL environment.
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    mkdir -p "$FAKE_REPO/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    export HOME="$FAKE_HOME"
    export AGENT_INSTALL_TEST_MODE=1
}

teardown() {
    rm -rf "$FAKE_HOME" "$FAKE_REPO"
}

source_installer_functions() {
    # shellcheck disable=SC1090
    source "$FAKE_REPO/agent-install.sh"
}

# ─── #722 TypeScript dependency install ─────────────────────────────────────

@test "TC-722-001: npm install failure is reported with captured output" {
    source_installer_functions

    local fake_dir
    fake_dir="$(mktemp -d)"

    # Create a stub npm that always fails with a recognizable message.
    mkdir -p "$fake_dir/bin"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ERR! ERESOLVE could not resolve" >&2' 'exit 1' >"$fake_dir/bin/npm"
    chmod +x "$fake_dir/bin/npm"

    # Override PATH so the stub npm is found first.
    local saved_path="$PATH"
    export PATH="$fake_dir/bin:$PATH"

    run _install_turn_context_typescript_deps "$fake_dir"
    export PATH="$saved_path"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to install TypeScript build dependencies"* ]]
    [[ "$output" == *"ERR! ERESOLVE could not resolve"* ]]
    [[ "$output" == *"--legacy-peer-deps"* ]]
}

@test "TC-722-002: npm install success returns zero" {
    source_installer_functions

    local fake_dir
    fake_dir="$(mktemp -d)"

    mkdir -p "$fake_dir/bin"
    printf '%s\n' '#!/usr/bin/env bash' 'mkdir -p node_modules/typescript' 'exit 0' >"$fake_dir/bin/npm"
    chmod +x "$fake_dir/bin/npm"

    local saved_path="$PATH"
    export PATH="$fake_dir/bin:$PATH"

    run _install_turn_context_typescript_deps "$fake_dir"
    export PATH="$saved_path"

    [ "$status" -eq 0 ]
}

