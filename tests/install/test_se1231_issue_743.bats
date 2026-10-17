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
    export PGDATABASE="test_memory"
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
    export -f _check_agent_credentials _check_superuser_prep_done _run_credential_and_superuser_checks
    export -f _print_superuser_sql _halt_agent_credentials_error _halt_missing_superuser_password
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

# ─── (d) #743 chunk 2: required agent credentials and optional superuser skip ─

@test "TC-743-030: --print-superuser-sql emits CREATE ROLE, CREATE DATABASE OWNER, CREATE EXTENSION and no password" {
    source_installer_functions

    run _print_superuser_sql
    [ "$status" -eq 0 ]
    [[ "$output" == *"CREATE ROLE testuser LOGIN PASSWORD '<set-by-dba>'"* ]]
    [[ "$output" == *"CREATE DATABASE test_memory OWNER testuser"* ]]
    [[ "$output" == *"CREATE EXTENSION IF NOT EXISTS vector"* ]]
}

@test "TC-743-031: _check_agent_credentials reports failure when psql cannot connect" {
    source_installer_functions

    cat >"$STUB_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql: error: connection to server failed" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/psql"

    run _check_agent_credentials
    [ "$status" -ne 0 ]
}

@test "TC-743-032: agent credential failure halts before any mutation" {
    cat >"$STUB_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql: error: connection to server failed" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/psql"

    # pg_isready must succeed so the installer reaches the credential check.
    cat >"$STUB_BIN/pg_isready" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/pg_isready"

    run bash "$FAKE_REPO/agent-install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot connect to PostgreSQL as agent role 'testuser'"* ]]
    [[ "$output" == *"CREATE ROLE testuser LOGIN PASSWORD"* ]]
    [[ "$output" == *"CREATE DATABASE test_memory OWNER testuser"* ]]
    [[ "$output" == *"CREATE EXTENSION IF NOT EXISTS vector"* ]]

    # No mutation should have occurred in FAKE_HOME.
    [ "$(find "$FAKE_HOME" -type f | wc -l)" -eq 1 ]
    [ -f "$FAKE_HOME/.openclaw/postgres.json" ]
}

_make_smart_psql_stub() {
    local agent_cred_exit="${1:-0}"
    local db_owner="${2:-}"
    local ext_present="${3:-0}"
    cat >"$STUB_BIN/psql" <<EOF
#!/usr/bin/env bash
args="\$*"
if [[ "\$args" == *"SELECT 1 FROM pg_database"* ]]; then
    [ -n "$db_owner" ] && echo "1" || echo ""
    exit 0
elif [[ "\$args" == *"pg_get_userbyid(datdba)"* ]]; then
    echo "$db_owner"
    exit 0
elif [[ "\$args" == *"SELECT 1 FROM pg_extension"* ]]; then
    if [ "$ext_present" -eq 1 ]; then
        echo "1"
    else
        echo ""
    fi
    exit 0
elif [[ "\$args" == *"SELECT 1"* ]]; then
    exit $agent_cred_exit
fi
echo "psql: unrecognized stub invocation: \$args" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/psql"
}

@test "TC-743-033: missing distinct superuser password with prep not done halts with instructions and prep SQL" {
    source_installer_functions
    _make_smart_psql_stub 0 "" 0

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD=""
    export PG_SUPERUSER_HOST="localhost"

    run _run_credential_and_superuser_checks
    [ "$status" -eq 1 ]
    [[ "$output" == *"Superuser password is required but not provided"* ]]
    [[ "$output" == *"PG_SUPERUSER_PASSWORD environment variable"* ]]
    [[ "$output" == *"Interactive shell-install.sh prompt"* ]]
    [[ "$output" == *"CREATE ROLE testuser LOGIN PASSWORD"* ]]
    [[ "$output" == *"CREATE DATABASE test_memory OWNER testuser"* ]]
    [[ "$output" == *"CREATE EXTENSION IF NOT EXISTS vector"* ]]
}

@test "TC-743-034: prep done sets SKIP_SUPERUSER_PHASE and skips superuser phase" {
    source_installer_functions
    _make_smart_psql_stub 0 "testuser" 1

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD=""
    export PG_SUPERUSER_HOST="localhost"

    run _run_credential_and_superuser_checks
    [ "$status" -eq 0 ]
    [[ "$output" == *"Superuser prep already done"* ]]
    [[ "$output" == *"skipping superuser-only reconciliation steps"* ]]
}

@test "TC-743-035: real password is never leaked in --print-superuser-sql or halt output" {
    source_installer_functions

    export PGPASSWORD="super-secret-agent-password"
    export PG_SUPERUSER_PASSWORD="super-secret-superuser-password"

    # --print output
    run _print_superuser_sql
    [[ "$output" != *"super-secret-agent-password"* ]]
    [[ "$output" != *"super-secret-superuser-password"* ]]

    # Agent credential failure output
    cat >"$STUB_BIN/psql" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$STUB_BIN/psql"
    run _halt_agent_credentials_error
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot connect to PostgreSQL as agent role 'testuser'"* ]]
    [[ "$output" != *"super-secret-agent-password"* ]]
    [[ "$output" != *"super-secret-superuser-password"* ]]

    # Missing superuser password output
    cat >"$STUB_BIN/psql" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/psql"
    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD=""
    run _halt_missing_superuser_password
    [ "$status" -eq 1 ]
    [[ "$output" == *"Superuser password is required but not provided"* ]]
    [[ "$output" != *"super-secret-agent-password"* ]]
    [[ "$output" != *"super-secret-superuser-password"* ]]
}
