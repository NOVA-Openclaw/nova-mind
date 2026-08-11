#!/usr/bin/env bats
# BATS tests for agent-install.sh optional agent_chat peer detection (#579).
#
# Coverage:
#   TC-579-PD-01: absent bus -> informational skip, zero agent_chat artifacts
#   TC-579-PD-02: configured + reachable bus + checkout exists -> register + install
#   TC-579-PD-03: configured + reachable bus + checkout missing -> checkout warning
#   TC-579-PD-04: configured but unreachable bus -> unreachable warning
#   TC-579-PD-05: reachable DB only (no config) is present but warns on missing checkout
#   TC-579-PD-06: schema-version mismatch emits compatibility warning
#   TC-579-PD-07: agent-install.sh passes bash -n
#   TC-579-PD-08: agent-install.sh shellcheck has no new warnings vs main baseline
#
# Run: bats tests/install/test_agent_chat_peer_detection.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"
PEER_LIB="$REPO_ROOT/lib/agent-chat-peer-detection.sh"

setup() {
    FAKE_OPENCLAW="$(mktemp -d)"
    FAKE_POSTGRES="$FAKE_OPENCLAW/postgres.json"
    FAKE_REPO="$(mktemp -d)"
    MOCK_BIN="$(mktemp -d)"
    export FAKE_OPENCLAW FAKE_POSTGRES FAKE_REPO MOCK_BIN

    # State variables consumed by the mock jq/psql binaries.
    MOCK_JQ_HAS_AGENT_CHAT=0
    MOCK_PSQL_REACHABLE=0
    MOCK_PSQL_SCHEMA_VERSION="1"
    export MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE MOCK_PSQL_SCHEMA_VERSION

    # The peer-detection lib only probes postgres.json if the file exists.
    printf '{}' > "$FAKE_POSTGRES"

    cat >"$MOCK_BIN/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Mock jq that only supports the -e projection patterns used by peer detection.
# It never prints JSON values; it only exits 0/1 based on configured presence.
if [ "${1:-}" = "-e" ]; then
    case "$2" in
        '.agent_chat')
            [ "$MOCK_JQ_HAS_AGENT_CHAT" -eq 1 ] && exit 0 || exit 1
            ;;
        *)
            echo "mock jq: unsupported filter: $2" >&2
            exit 1
            ;;
    esac
fi
echo "mock jq: unsupported args: $*" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN/jq"

    cat >"$MOCK_BIN/psql" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Mock psql for the two read-only agent_chat bus probes.
# Reject anything that does not target the literal database name "agent_chat".
mock_db=""
mock_query=""
while [ $# -gt 0 ]; do
    case "$1" in
        -d) mock_db="$2"; shift 2 ;;
        -c) mock_query="$2"; shift 2 ;;
        -*) shift ;;
        *) shift ;;
    esac
done

if [ "$mock_db" != "agent_chat" ]; then
    echo "mock psql: unexpected database: $mock_db" >&2
    exit 1
fi

if [ "$mock_query" = "\q" ]; then
    [ "$MOCK_PSQL_REACHABLE" -eq 1 ] && exit 0 || exit 2
fi

if [ "$mock_query" = "SELECT COALESCE(MAX(version), 0) FROM schema_version" ]; then
    if [ "$MOCK_PSQL_REACHABLE" -eq 1 ]; then
        echo "$MOCK_PSQL_SCHEMA_VERSION"
        exit 0
    fi
    exit 2
fi

echo "mock psql: unexpected query: $mock_query" >&2
exit 1
EOF
    chmod +x "$MOCK_BIN/psql"

    PATH="$MOCK_BIN:$PATH"
    export PATH

    # Symbols required by the peer-detection library.
    WARNING="⚠️"
    INFO="ℹ️"
    DB_USER="testagent"
    PG_CONFIG="$FAKE_POSTGRES"
    PGHOST="localhost"
    PGPORT="5432"
    PGUSER="testagent"
    export WARNING INFO DB_USER PG_CONFIG PGHOST PGPORT PGUSER
}

teardown() {
    rm -rf "$FAKE_OPENCLAW" "$FAKE_REPO" "$MOCK_BIN"
}

# Source the helper functions inline so we do not need a live DB.
source_peer_lib() {
    # shellcheck disable=SC1090
    source "$PEER_LIB"
}

make_checkout() {
    mkdir -p "$FAKE_REPO"
    cat >"$FAKE_REPO/register-agent.sh" <<'EOF'
#!/usr/bin/env bash
echo "register-agent called with: $1"
exit 0
EOF
    cat >"$FAKE_REPO/install-plugin.sh" <<'EOF'
#!/usr/bin/env bash
echo "install-plugin called"
exit 0
EOF
    chmod +x "$FAKE_REPO/register-agent.sh" "$FAKE_REPO/install-plugin.sh"
}

@test "TC-579-PD-01: absent bus skips silently and writes no artifacts" {
    source_peer_lib
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO

    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent_chat bus not detected"* ]]
    [[ "$output" != *"Registering agent"* ]]
    [[ "$output" != *"agent-chat repo checkout not found"* ]]

    # Absent-mode must not create any files in the fake openclaw dir.
    # The only file that existed before the call was postgres.json.
    local file_count
    file_count=$(find "$FAKE_OPENCLAW" -type f | wc -l)
    [ "$file_count" -eq 1 ]
    [ -f "$FAKE_POSTGRES" ]
}

@test "TC-579-PD-02: configured + reachable + checkout exists registers and installs plugin" {
    MOCK_JQ_HAS_AGENT_CHAT=1
    MOCK_PSQL_REACHABLE=1
    make_checkout
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"Registering agent on agent_chat bus"* ]]
    [[ "$output" == *"register-agent called with: testagent"* ]]
    [[ "$output" == *"Installing agent_chat plugin"* ]]
    [[ "$output" == *"install-plugin called"* ]]
}

@test "TC-579-PD-03: configured + reachable + checkout missing warns and continues" {
    MOCK_JQ_HAS_AGENT_CHAT=1
    MOCK_PSQL_REACHABLE=1
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent-chat repo checkout not found"* ]]
    [[ "$output" == *"https://github.com/NOVA-Openclaw/agent-chat"* ]]
    [[ "$output" != *"Registering agent"* ]]
}

@test "TC-579-PD-04: configured but unreachable warns and continues" {
    MOCK_JQ_HAS_AGENT_CHAT=1
    MOCK_PSQL_REACHABLE=0
    export MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent_chat bus is configured but unreachable"* ]]
    [[ "$output" != *"Registering agent"* ]]
    [[ "$output" != *"agent-chat repo checkout not found"* ]]
}

@test "TC-579-PD-05: reachable DB without config is present but warns on missing checkout" {
    MOCK_JQ_HAS_AGENT_CHAT=0
    MOCK_PSQL_REACHABLE=1
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent-chat repo checkout not found"* ]]
    [[ "$output" != *"agent_chat bus not detected"* ]]
    [[ "$output" != *"agent_chat bus is configured but unreachable"* ]]
}

@test "TC-579-PD-06: older bus schema emits compatibility warning" {
    MOCK_JQ_HAS_AGENT_CHAT=1
    MOCK_PSQL_REACHABLE=1
    MOCK_PSQL_SCHEMA_VERSION="2"
    make_checkout
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE MOCK_PSQL_SCHEMA_VERSION

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent_chat bus schema version 2 is older than expected"* ]]
}

@test "TC-579-PD-06b: equal bus schema emits no warning" {
    MOCK_JQ_HAS_AGENT_CHAT=1
    MOCK_PSQL_REACHABLE=1
    MOCK_PSQL_SCHEMA_VERSION="3"
    make_checkout
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE MOCK_PSQL_SCHEMA_VERSION

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" != *"agent_chat bus schema version"* ]]
}

@test "TC-579-PD-06c: newer bus schema emits distinct forward-compatibility warning" {
    MOCK_JQ_HAS_AGENT_CHAT=1
    MOCK_PSQL_REACHABLE=1
    MOCK_PSQL_SCHEMA_VERSION="4"
    make_checkout
    AGENT_CHAT_REPO="$FAKE_REPO"
    export AGENT_CHAT_REPO MOCK_JQ_HAS_AGENT_CHAT MOCK_PSQL_REACHABLE MOCK_PSQL_SCHEMA_VERSION

    source_peer_lib
    run _agent_chat_integrate_peer
    [ "$status" -eq 0 ]
    [[ "$output" == *"agent_chat bus schema version 4 is newer than this installer knows; consider updating nova-mind"* ]]
}

@test "TC-579-PD-07: agent-install.sh passes bash -n" {
    run bash -n "$INSTALLER"
    [ "$status" -eq 0 ]
}

@test "TC-579-PD-07a: agent-chat-peer-detection.sh passes bash -n" {
    run bash -n "$PEER_LIB"
    [ "$status" -eq 0 ]
}

@test "TC-579-PD-08: agent-install.sh shellcheck has no new warnings vs main baseline" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi

    local baseline tmp_branch
    baseline="$(mktemp)"
    tmp_branch="$(mktemp)"

    git show main:agent-install.sh > "$baseline" 2>/dev/null || {
        rm -f "$baseline" "$tmp_branch"
        skip "main branch baseline not available"
    }
    cp "$INSTALLER" "$tmp_branch"

    local baseline_count branch_count
    baseline_count=$(shellcheck "$baseline" 2>/dev/null | grep -c '^\s*[0-9]' || true)
    branch_count=$(shellcheck "$tmp_branch" 2>/dev/null | grep -c '^\s*[0-9]' || true)

    rm -f "$baseline" "$tmp_branch"

    [ "$branch_count" -le "$baseline_count" ]
}

@test "TC-579-PD-08a: agent-chat-peer-detection.sh shellcheck has no new warnings vs main baseline" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi

    local baseline tmp_branch
    baseline="$(mktemp)"
    tmp_branch="$(mktemp)"

    git show main:lib/agent-chat-peer-detection.sh > "$baseline" 2>/dev/null || {
        rm -f "$baseline" "$tmp_branch"
        skip "main branch baseline not available"
    }
    cp "$PEER_LIB" "$tmp_branch"

    local baseline_count branch_count
    baseline_count=$(shellcheck "$baseline" 2>/dev/null | grep -c 'SC[0-9]\{4\}' || true)
    branch_count=$(shellcheck "$tmp_branch" 2>/dev/null | grep -c 'SC[0-9]\{4\}' || true)

    rm -f "$baseline" "$tmp_branch"

    [ "$branch_count" -le "$baseline_count" ]
}
