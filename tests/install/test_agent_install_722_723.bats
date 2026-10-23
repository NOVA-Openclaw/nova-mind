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
    mkdir -p "$FAKE_REPO/memory/lib" "$FAKE_REPO/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/memory/lib/pg-env.sh"
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

# TC-789 assertion helpers (reused for both positive and mutation tests).
_assert_789_001() {
    local repo_root="$1"
    local home_dir="$2"
    local saved_home="$HOME"
    export HOME="$home_dir"
    export AGENT_INSTALL_TEST_MODE=1
    # Clear positional parameters so agent-install.sh's argument parser
    # does not see the helper arguments when sourced.
    set --
    # shellcheck disable=SC1090
    source "$repo_root/agent-install.sh"
    install_lib_files
    [ -f "$home_dir/.openclaw/lib/pg-env.sh" ]
    grep -q 'resolve_agent_db()' "$home_dir/.openclaw/lib/pg-env.sh"
    export HOME="$saved_home"
}

_assert_789_002() {
    local repo_root="$1"
    local home_dir="$2"
    local saved_home="$HOME"
    export HOME="$home_dir"
    export AGENT_INSTALL_TEST_MODE=1
    set --
    # shellcheck disable=SC1090
    source "$repo_root/agent-install.sh"
    install_lib_files
    [ -f "$home_dir/.openclaw/lib/pg-env.ts" ]
    grep -q 'export function resolveAgentDatabase' "$home_dir/.openclaw/lib/pg-env.ts"
    export HOME="$saved_home"
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

# ─── #723 gateway.reload.mode ───────────────────────────────────────────────

@test "TC-723-001: missing gateway.reload.mode is set to hybrid" {
    source_installer_functions

    local config
    config="$(mktemp)"
    printf '%s\n' '{}' >"$config"

    run _configure_gateway_reload_mode "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Set gateway.reload.mode = \"hybrid\""* ]]
    [ "$(jq -r '.gateway.reload.mode' "$config")" = "hybrid" ]
}

@test "TC-723-002: existing 'off' is left unchanged" {
    source_installer_functions

    local config
    config="$(mktemp)"
    printf '%s\n' '{"gateway":{"reload":{"mode":"off"}}}' >"$config"

    run _configure_gateway_reload_mode "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"off"* ]]
    [[ "$output" != *"Set gateway.reload.mode"* ]]
    [ "$(jq -r '.gateway.reload.mode' "$config")" = "off" ]
}

@test "TC-723-003: existing 'hybrid' is left unchanged" {
    source_installer_functions

    local config
    config="$(mktemp)"
    printf '%s\n' '{"gateway":{"reload":{"mode":"hybrid"}}}' >"$config"

    run _configure_gateway_reload_mode "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hybrid"* ]]
    [[ "$output" != *"Set gateway.reload.mode"* ]]
    [ "$(jq -r '.gateway.reload.mode' "$config")" = "hybrid" ]
}

@test "TC-723-004: obsolete 'hot' value is overwritten with hybrid" {
    source_installer_functions

    local config
    config="$(mktemp)"
    printf '%s\n' '{"gateway":{"reload":{"mode":"hot"}}}' >"$config"

    run _configure_gateway_reload_mode "$config"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Set gateway.reload.mode = \"hybrid\""* ]]
    [ "$(jq -r '.gateway.reload.mode' "$config")" = "hybrid" ]
}

@test "TC-789-001: install_lib_files deploys pg-env.sh with resolve_agent_db" {
    run _assert_789_001 "$REPO_ROOT" "$HOME"
    [ "$status" -eq 0 ]
}

@test "TC-789-002: install_lib_files deploys pg-env.ts exporting resolveAgentDatabase" {
    run _assert_789_002 "$REPO_ROOT" "$HOME"
    [ "$status" -eq 0 ]
}

@test "TC-789-003: stale source fails TC-789-001/002; real source passes" {
    local stale_home stale_repo real_home
    stale_home="$(mktemp -d)"
    stale_repo="$(mktemp -d)"
    real_home="$(mktemp -d)"
    mkdir -p "$stale_home/.openclaw" "$stale_repo/memory/lib" "$stale_repo/lib"
    mkdir -p "$real_home/.openclaw"
    cp "$REPO_ROOT/agent-install.sh" "$stale_repo/agent-install.sh"

    # Simulate the pre-fix memory/lib copy: no resolve_agent_db / resolveAgentDatabase.
    cat >"$stale_repo/memory/lib/pg-env.sh" <<'STALEEOF'
#!/bin/bash
load_pg_env() { :; }
load_pg_superuser_env() { :; }
STALEEOF
    cat >"$stale_repo/memory/lib/pg-env.ts" <<'STALEEOF'
export function loadPgEnv() {}
STALEEOF
    printf '%s\n' '# stub' >"$stale_repo/memory/lib/env-loader.sh"
    printf '%s\n' '# stub' >"$stale_repo/memory/lib/env_loader.py"
    printf '%s\n' '# stub' >"$stale_repo/memory/lib/pg_env.py"
    printf '%s\n' '# stub' >"$stale_repo/lib/agent-chat-peer-detection.sh"

    cat >"$stale_home/.openclaw/postgres.json" <<'STALEEOF'
{"host":"localhost","port":5432,"database":"test_memory","user":"testuser","password":""}
STALEEOF
    cat >"$real_home/.openclaw/postgres.json" <<'STALEEOF'
{"host":"localhost","port":5432,"database":"test_memory","user":"testuser","password":""}
STALEEOF

    # Stale source: TC-789-001/002 assertions must fail.
    run _assert_789_001 "$stale_repo" "$stale_home"
    [ "$status" -ne 0 ]
    run _assert_789_002 "$stale_repo" "$stale_home"
    [ "$status" -ne 0 ]

    # Real source: TC-789-001/002 assertions must pass.
    run _assert_789_001 "$REPO_ROOT" "$real_home"
    [ "$status" -eq 0 ]
    run _assert_789_002 "$REPO_ROOT" "$real_home"
    [ "$status" -eq 0 ]

    rm -rf "$stale_home" "$stale_repo" "$real_home"
}

