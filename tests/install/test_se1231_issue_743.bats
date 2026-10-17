#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC1091
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
    export -f _schema_ddl_psql _schema_pgschema _run_schema_management
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

# ─── chunk 3: SKIP_SUPERUSER_PHASE=1 still applies schema as DB_USER ────────

_setup_schema_test_env() {
    # Minimal schema and ignore file for _run_schema_management tests.
    mkdir -p "$FAKE_REPO/database" "$FAKE_REPO/memory/database"
    printf '%s\n' 'CREATE TABLE IF NOT EXISTS test_table (id serial PRIMARY KEY);' >"$FAKE_REPO/database/schema.sql"
    printf '%s\n' '[tables]' '[views]' '[functions]' '[triggers]' '[indexes]' '[constraints]' >"$FAKE_REPO/database/.pgschemaignore"

    # Real Python helpers from the repo.
    export VENV_PYTHON="$REPO_ROOT/.local/share/$USER/venv/bin/python"
    if [ ! -x "$VENV_PYTHON" ]; then
        VENV_PYTHON="$(command -v python3)"
    fi

    # Stubs for pgschema and the reorder/strip Python helpers.
    cat >"$STUB_BIN/pgschema" <<'EOF'
#!/usr/bin/env bash
# Stub pgschema: plan writes a canned plan.json; apply succeeds.
action="$1"
shift
output_json=""
user_arg=""
while [ $# -gt 0 ]; do
    case "$1" in
        --output-json) output_json="$2"; shift 2 ;;
        --user) user_arg="$2"; shift 2 ;;
        --plan-user) shift 2 ;;
        --host|--plan-host|--db|--plan-db|--port|--plan-port|--schema) shift 2 ;;
        --file) shift 2 ;;
        --plan) shift 2 ;;
        --auto-approve|--no-color) shift ;;
        *) shift ;;
    esac
done

if [ "$action" = "plan" ]; then
    if [ -z "$output_json" ]; then
        echo "pgschema stub: missing --output-json" >&2
        exit 1
    fi
    # Copy the plan file injected by the test via PGSCHEMA_STUB_PLAN env.
    if [ -n "${PGSCHEMA_STUB_PLAN:-}" ] && [ -f "$PGSCHEMA_STUB_PLAN" ]; then
        cp "$PGSCHEMA_STUB_PLAN" "$output_json"
    else
        echo '{"version":"1.0.0","pgschema_version":"stub","source_fingerprint":{"hash":"x"},"groups":[]}' >"$output_json"
    fi
    # Record the --user value for assertions.
    if [ -n "$user_arg" ]; then
        echo "PGSCHEMA_USER=$user_arg" >&2
    fi
    exit 0
elif [ "$action" = "apply" ]; then
    echo "pgschema apply called"
    exit 0
fi

echo "pgschema stub: unknown action $action" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/pgschema"
    export PGSCHEMA_BIN="$STUB_BIN/pgschema"

    cat >"$FAKE_REPO/database/plan_reorder.py" <<'EOF'
#!/usr/bin/env python3
import argparse
import shutil
ap = argparse.ArgumentParser()
ap.add_argument('--plan')
ap.add_argument('--output')
args = ap.parse_args()
shutil.copy(args.plan, args.output)
EOF
    chmod +x "$FAKE_REPO/database/plan_reorder.py"

    cat >"$FAKE_REPO/database/strip_destructive.py" <<'EOF'
#!/usr/bin/env python3
import argparse
import shutil
ap = argparse.ArgumentParser()
ap.add_argument('--plan')
ap.add_argument('--output')
ap.add_argument('--ignore-objects', default='')
ap.add_argument('--log-exclusions', action='store_true')
args = ap.parse_args()
shutil.copy(args.plan, args.output)
print(0)
EOF
    chmod +x "$FAKE_REPO/database/strip_destructive.py"

    # Ensure the real plan_check_superuser.py is discoverable.
    cp "$REPO_ROOT/database/plan_check_superuser.py" "$FAKE_REPO/database/plan_check_superuser.py"

    # Override peer-shadow detection so no live DB is needed.
    _resolve_peer_shadowed_relations() { return 0; }
    export -f _resolve_peer_shadowed_relations

    export SKIP_SUPERUSER_PHASE=1
    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD=""
    export PG_SUPERUSER_HOST="localhost"
    export PGHOST="localhost"
    export PGPORT="5432"
}

_write_plan() {
    cat >"$1" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "CREATE TABLE IF NOT EXISTS test_table (id serial PRIMARY KEY);",
          "type": "table",
          "operation": "create",
          "path": "public.test_table"
        }
      ]
    }
  ]
}
JSON
}

@test "TC-743-040: prep done + agent-ownable plan applies as DB_USER" {
    source_installer_functions
    _setup_schema_test_env
    local plan_file
    plan_file="$(mktemp)"
    _write_plan "$plan_file"
    export PGSCHEMA_STUB_PLAN="$plan_file"

    run _run_schema_management
    [ "$status" -eq 0 ]
    [[ "$output" == *"Running pgschema plan (as DB_USER testuser)"* ]]
    [[ "$output" == *"Schema applied successfully"* ]]
    [[ "$output" == *"PGSCHEMA_USER=testuser"* ]]
    rm -f "$plan_file"
}

@test "TC-743-040-mut: applying superuser-owned plan as DB_USER fails closed" {
    source_installer_functions
    _setup_schema_test_env
    local plan_file
    plan_file="$(mktemp)"
    cat >"$plan_file" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "CREATE EXTENSION IF NOT EXISTS vector;",
          "type": "extension",
          "operation": "create",
          "path": "public.vector"
        }
      ]
    }
  ]
}
JSON
    export PGSCHEMA_STUB_PLAN="$plan_file"

    run _run_schema_management
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema plan contains superuser-only steps"* ]]
    [[ "$output" == *"CREATE EXTENSION"* ]]
    [[ "$output" == *"PG_SUPERUSER_PASSWORD environment variable"* ]]
    rm -f "$plan_file"
}

@test "TC-743-041: prep done + plan with superuser-only step halts before apply" {
    source_installer_functions
    _setup_schema_test_env
    local plan_file
    plan_file="$(mktemp)"
    cat >"$plan_file" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "CREATE OR REPLACE FUNCTION secdef_fn() RETURNS int LANGUAGE sql SECURITY DEFINER AS $$ SELECT 1 $$;",
          "type": "function",
          "operation": "create",
          "path": "public.secdef_fn"
        }
      ]
    }
  ]
}
JSON
    export PGSCHEMA_STUB_PLAN="$plan_file"

    run _run_schema_management
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema plan contains superuser-only steps"* ]]
    [[ "$output" == *"SECURITY DEFINER function"* ]]
    [[ "$output" == *"secdef_fn"* ]]
    rm -f "$plan_file"
}

@test "TC-743-042: new install via DBA prep gets the schema applied" {
    source_installer_functions
    _setup_schema_test_env
    local plan_file
    plan_file="$(mktemp)"
    _write_plan "$plan_file"
    export PGSCHEMA_STUB_PLAN="$plan_file"

    run _run_schema_management
    [ "$status" -eq 0 ]
    [[ "$output" == *"Schema applied successfully"* ]]
    [[ "$output" == *"Total tables in database:"* ]]
    rm -f "$plan_file"
}

@test "TC-743-043: warning lists skipped superuser-only steps" {
    source_installer_functions
    _setup_schema_test_env
    local plan_file
    plan_file="$(mktemp)"
    _write_plan "$plan_file"
    export PGSCHEMA_STUB_PLAN="$plan_file"

    run _run_schema_management
    [ "$status" -eq 0 ]
    [[ "$output" == *"Superuser-only steps skipped:"* ]]
    [[ "$output" == *"CREATE EXTENSION"* ]]
    [[ "$output" == *"ownership transfer"* ]]
    [[ "$output" == *"grant reconciliation"* ]]
    rm -f "$plan_file"
}

@test "TC-743-045: plan_check_superuser.py flags CREATE SERVER and CREATE EVENT TRIGGER" {
    plan_file="$(mktemp)"
    cat >"$plan_file" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', dbname 'db');",
          "type": "server",
          "operation": "create",
          "path": "public.loopback"
        },
        {
          "sql": "CREATE EVENT TRIGGER ev ON sql_drop EXECUTE FUNCTION fn();",
          "type": "event_trigger",
          "operation": "create",
          "path": "public.ev"
        }
      ]
    }
  ]
}
JSON
    run python3 "$REPO_ROOT/database/plan_check_superuser.py" --plan "$plan_file"
    [ "$status" -ne 0 ]
    [[ "$output" == *"CREATE SERVER (FDW)"* ]]
    [[ "$output" == *"CREATE EVENT TRIGGER"* ]]
    rm -f "$plan_file"
}

@test "TC-743-044: _schema_pgschema uses superuser password when SKIP_SUPERUSER_PHASE=0" {
    source_installer_functions

    local recording
    recording="$(mktemp)"
    cat >"$STUB_BIN/pgschema" <<EOF
#!/usr/bin/env bash
printf '%s\n' "argv:\$*" >> "$recording"
while IFS='=' read -r key val; do
    case "\$key" in
        PGPASSWORD|PG_SUPERUSER_PASSWORD) printf '%s=%s\n' "\$key" "\$val" >> "$recording" ;;
    esac
done < <(env)
printf '\n' >> "$recording"
exit 0
EOF
    chmod +x "$STUB_BIN/pgschema"
    export PGSCHEMA_BIN="$STUB_BIN/pgschema"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="secret123"
    export SKIP_SUPERUSER_PHASE=0

    run _schema_pgschema plan --db "$DB_NAME"
    [ "$status" -eq 0 ]

    run grep -E '^argv:' "$recording"
    [[ "$output" == *"plan"* ]]
    [[ "$output" != *"secret123"* ]]

    run grep -E '^PGPASSWORD=' "$recording"
    [[ "$output" == *"PGPASSWORD=secret123"* ]]

    rm -f "$recording"
}

@test "TC-743-shellcheck: bats file passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}
