#!/usr/bin/env bats
# Tests for nova-mind #743 / SE #1231 step 5:
#   - agent-install.sh and shell-install.sh contain no `sudo` commands
#   - superuser operations authenticate directly as PG_SUPERUSER via the
#     PGPASSWORD env var (scoped to one command), never on the command line
#   - a wrong/missing superuser password fails fast before schema steps
#   - the superuser password never appears in installer output
#
# These tests use stubbed psql/createdb/pgschema binaries and do NOT connect
# to a real PostgreSQL server.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    FAKE_OPENCLAW="$FAKE_HOME/.openclaw"
    mkdir -p "$FAKE_OPENCLAW"

    printf '%s\n' '{' '  "host": "localhost",' '  "port": 5432,' '  "database": "test_memory",' '  "user": "testuser",' '  "password": ""' '}' >"$FAKE_OPENCLAW/postgres.json"

    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    mkdir -p "$FAKE_REPO/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    STUB_BIN="$(mktemp -d)"
    export PATH="$STUB_BIN:$PATH"

    export HOME="$FAKE_HOME"
    export AGENT_INSTALL_TEST_MODE=1
    export DB_USER="testuser"
    export DB_NAME="test_memory"
    export PGUSER="testuser"
    export PGHOST="localhost"
    export PGPORT="5432"
}

teardown() {
    rm -rf "$FAKE_HOME" "$FAKE_REPO" "$STUB_BIN"
}

source_installer_functions() {
    # shellcheck disable=SC1090
    source "$FAKE_REPO/agent-install.sh"
    export -f _superuser_psql _superuser_createdb _superuser_pgschema _verify_superuser_connection
}

# ─── (a) no sudo remains in installer scripts ───────────────────────────────

@test "TC-743-001: agent-install.sh contains no sudo substring" {
    run grep -F "sudo" "$REPO_ROOT/agent-install.sh"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-743-002: shell-install.sh contains no sudo substring" {
    run grep -F "sudo" "$REPO_ROOT/shell-install.sh"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ─── (b) superuser helpers use PGPASSWORD env, not argv ─────────────────────

_make_recording_stub() {
    local name="$1"
    local recording="$2"
    cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
# Record argv and environment, then succeed.
printf '%s\n' "argv:\$*" >> "$recording"
while IFS='=' read -r key val; do
    case "\$key" in
        PGHOST|PGPORT|PGUSER|PGPASSWORD|PG_SUPERUSER|PG_SUPERUSER_PASSWORD|PG_SUPERUSER_HOST)
            printf '%s=%s\n' "\$key" "\$val" >> "$recording" ;;
    esac
done < <(env)
printf '\n' >> "$recording"
exit 0
EOF
    chmod +x "$STUB_BIN/$name"
}

@test "TC-743-010: _superuser_psql passes password via PGPASSWORD env" {
    source_installer_functions

    local recording
    recording="$(mktemp)"
    _make_recording_stub "psql" "$recording"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="secret123"
    export PG_SUPERUSER_HOST="pg.example.com"

    run _superuser_psql "$DB_NAME" -c "SELECT 1"
    [ "$status" -eq 0 ]

    run grep -E '^argv:' "$recording"
    [[ "$output" == *"-h pg.example.com"* ]]
    [[ "$output" == *"-U postgres"* ]]
    [[ "$output" != *"secret123"* ]]
    [[ "$output" != *"--password"* ]]

    run grep -E '^PGPASSWORD=' "$recording"
    [[ "$output" == *"PGPASSWORD=secret123"* ]]
}

@test "TC-743-011: _superuser_createdb passes password via PGPASSWORD env" {
    source_installer_functions

    local recording
    recording="$(mktemp)"
    _make_recording_stub "createdb" "$recording"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="secret123"
    export PG_SUPERUSER_HOST="/var/run/postgresql"

    run _superuser_createdb "$DB_NAME"
    [ "$status" -eq 0 ]

    run grep -E '^argv:' "$recording"
    [[ "$output" == *"-h /var/run/postgresql"* ]]
    [[ "$output" == *"-U postgres"* ]]
    [[ "$output" != *"secret123"* ]]
    [[ "$output" != *"--password"* ]]

    run grep -E '^PGPASSWORD=' "$recording"
    [[ "$output" == *"PGPASSWORD=secret123"* ]]
}

@test "TC-743-012: _superuser_pgschema passes password via PGPASSWORD env" {
    source_installer_functions

    local recording
    recording="$(mktemp)"
    _make_recording_stub "pgschema" "$recording"
    export PGSCHEMA_BIN="pgschema"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="secret123"
    export PG_SUPERUSER_HOST="pg.example.com"

    run _superuser_pgschema plan --db "$DB_NAME"
    [ "$status" -eq 0 ]

    run grep -E '^argv:' "$recording"
    [[ "$output" == *"plan"* ]]
    [[ "$output" != *"secret123"* ]]
    [[ "$output" != *"--password"* ]]

    run grep -E '^PGPASSWORD=' "$recording"
    [[ "$output" == *"PGPASSWORD=secret123"* ]]
}

@test "TC-743-013: helpers do not place password in argv when stdin is used" {
    source_installer_functions

    local recording
    recording="$(mktemp)"
    _make_recording_stub "psql" "$recording"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="secret123"
    export PG_SUPERUSER_HOST="localhost"

    run _superuser_psql "$DB_NAME" -c "SELECT 1"
    [ "$status" -eq 0 ]

    run grep -E '^argv:' "$recording"
    [[ "$output" != *"secret123"* ]]
    [[ "$output" != *"--password"* ]]

    run grep -E '^PGPASSWORD=' "$recording"
    [[ "$output" == *"PGPASSWORD=secret123"* ]]
}

# ─── (c) wrong/missing password fails fast before schema steps ──────────────

_make_failing_psql_stub() {
    cat >"$STUB_BIN/psql" <<'EOF'
#!/usr/bin/env bash
# Succeed only when PGPASSWORD matches the expected value.
if [ "${PGPASSWORD:-}" = "correct" ]; then
    exit 0
fi
echo "psql: error: connection to server failed" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/psql"
}

@test "TC-743-020: _verify_superuser_connection fails with wrong password" {
    source_installer_functions
    _make_failing_psql_stub

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="wrong"
    export PG_SUPERUSER_HOST="localhost"

    run _verify_superuser_connection
    [ "$status" -ne 0 ]
}

@test "TC-743-021: _verify_superuser_connection succeeds with correct password" {
    source_installer_functions
    _make_failing_psql_stub

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="correct"
    export PG_SUPERUSER_HOST="localhost"

    run _verify_superuser_connection
    [ "$status" -eq 0 ]
}

@test "TC-743-022: _verify_superuser_connection fails when password is empty" {
    source_installer_functions
    _make_failing_psql_stub

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD=""
    export PG_SUPERUSER_HOST="localhost"

    run _verify_superuser_connection
    [ "$status" -ne 0 ]
}

@test "TC-743-023: password does not appear in helper output on failure" {
    source_installer_functions
    _make_failing_psql_stub

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="leaked-password"
    export PG_SUPERUSER_HOST="localhost"

    run _verify_superuser_connection
    [ "$status" -ne 0 ]
    [[ "$output" != *"leaked-password"* ]]
}

@test "TC-743-024: _superuser_psql output does not contain password" {
    source_installer_functions

    cat >"$STUB_BIN/psql" <<EOF
#!/usr/bin/env bash
echo "connection ok"
exit 0
EOF
    chmod +x "$STUB_BIN/psql"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="top-secret"
    export PG_SUPERUSER_HOST="localhost"

    run _superuser_psql "$DB_NAME" -c "SELECT 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"connection ok"* ]]
    [[ "$output" != *"top-secret"* ]]
}
