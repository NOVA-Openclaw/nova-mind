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
    export -f _superuser_psql _superuser_createdb
    export -f _schema_ddl_psql _schema_pgschema _run_schema_management
    export -f _check_agent_credentials _run_credential_and_superuser_checks
    export -f _bootstrap_precheck_passes _bootstrap_role_and_database
    export -f _print_superuser_sql _halt_agent_credentials_error _halt_bootstrap_credentials_error
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

    run _superuser_psql postgres -c "SELECT 1"
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

@test "TC-743-013: helpers do not place password in argv when stdin is used" {
    source_installer_functions

    local recording
    recording="$(mktemp)"
    _make_recording_stub "psql" "$recording"

    export PG_SUPERUSER="postgres"
    export PG_SUPERUSER_PASSWORD="secret123"
    export PG_SUPERUSER_HOST="localhost"

    run _superuser_psql postgres -c "SELECT 1"
    [ "$status" -eq 0 ]

    run grep -E '^argv:' "$recording"
    [[ "$output" != *"secret123"* ]]
    [[ "$output" != *"--password"* ]]

    run grep -E '^PGPASSWORD=' "$recording"
    [[ "$output" == *"PGPASSWORD=secret123"* ]]
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

    run _superuser_psql postgres -c "SELECT 1"
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

@test "TC-743-032: missing role/database with no superuser credentials prints bootstrap instructions and exits 1" {
    cat >"$STUB_BIN/psql" <<'EOF'
#!/usr/bin/env bash
echo "psql: error: connection to server failed" >&2
exit 1
EOF
    chmod +x "$STUB_BIN/psql"

    # pg_isready must succeed so the installer reaches the bootstrap check.
    cat >"$STUB_BIN/pg_isready" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$STUB_BIN/pg_isready"

    run bash "$FAKE_REPO/agent-install.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Agent role 'testuser' or database 'test_memory' does not exist"* ]]
    [[ "$output" == *"CREATE ROLE testuser LOGIN PASSWORD"* ]]
    [[ "$output" == *"CREATE DATABASE test_memory OWNER testuser"* ]]
    [[ "$output" == *"CREATE EXTENSION IF NOT EXISTS vector"* ]]

    # No mutation should have occurred in FAKE_HOME.
    [ "$(find "$FAKE_HOME" -type f | wc -l)" -eq 1 ]
    [ -f "$FAKE_HOME/.openclaw/postgres.json" ]
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

    # Bootstrap credentials error output
    run _halt_bootstrap_credentials_error
    [ "$status" -eq 1 ]
    [[ "$output" == *"Agent role 'testuser' or database 'test_memory' does not exist"* ]]
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
    export VENV_PYTHON

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

    # Ensure the real Python helpers are discoverable.
    cp "$REPO_ROOT/database/plan_check_superuser.py" "$FAKE_REPO/database/plan_check_superuser.py"
    cp "$REPO_ROOT/database/grant_reconcile_gate.py" "$FAKE_REPO/database/grant_reconcile_gate.py"
    cp "$REPO_ROOT/database/fix_installer_ownership.py" "$FAKE_REPO/database/fix_installer_ownership.py"

    # Stub grant_reconcile_gate.py so schema-management tests don't need a live DB.
    cat >"$FAKE_REPO/database/grant_reconcile_gate.py" <<'EOF'
#!/usr/bin/env python3
import argparse
import json
import sys

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dbname", default="")
    parser.add_argument("--db-user", default="")
    parser.add_argument("--superuser", default="")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("snapshot")
    sub.add_parser("verify")
    sub.add_parser("protected-snapshot")
    check = sub.add_parser("check")
    check.add_argument("--protected-snapshot", default=None)
    args = parser.parse_args(argv)
    if args.action == "snapshot":
        json.dump({}, sys.stdout)
        print()
    elif args.action == "verify":
        print("OK: snapshot verified", file=sys.stderr)
    elif args.action == "protected-snapshot":
        json.dump({}, sys.stdout)
        print()
    elif args.action == "check":
        print("OK: protected-object ownership gate passed", file=sys.stderr)
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF
    chmod +x "$FAKE_REPO/database/grant_reconcile_gate.py"

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
    [[ "$output" == *"Ask a DBA to apply these steps as a PostgreSQL superuser."* ]]
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

@test "TC-743-shellcheck: bats file passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}

# ─── chunk 4: ownership check for existing objects when SKIP_SUPERUSER_PHASE=1 ─

_write_ownership_catalog() {
    cat >"$1" <<'JSON'
[
  {"schema": "public", "name": "protect_bootstrap_context_writes_v2", "kind": "function", "owner": "postgres"},
  {"schema": "public", "name": "test_table", "kind": "table", "owner": "testuser"}
]
JSON
}

_write_postgres_owned_function_plan() {
    cat >"$1" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "CREATE OR REPLACE FUNCTION protect_bootstrap_context_writes_v2() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END; $$;",
          "type": "function",
          "operation": "create",
          "path": "public.protect_bootstrap_context_writes_v2"
        }
      ]
    }
  ]
}
JSON
}

_write_agent_owned_table_plan() {
    cat >"$1" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "ALTER TABLE test_table ADD COLUMN x integer;",
          "type": "table",
          "operation": "alter",
          "path": "public.test_table"
        }
      ]
    }
  ]
}
JSON
}

_write_unparseable_step_plan() {
    cat >"$1" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "stub",
  "source_fingerprint": {"hash": "x"},
  "groups": [
    {
      "steps": [
        {
          "sql": "ALTER THING foo;",
          "type": "thing",
          "operation": "alter",
          "path": "not_a_valid_path"
        }
      ]
    }
  ]
}
JSON
}

@test "TC-743-050: plan altering postgres-owned function halts and lists owner" {
    local plan_file catalog
    plan_file="$(mktemp)"
    catalog="$(mktemp)"
    _write_postgres_owned_function_plan "$plan_file"
    _write_ownership_catalog "$catalog"

    run python3 "$REPO_ROOT/database/plan_check_superuser.py" \
        --plan "$plan_file" \
        --catalog-stub "$catalog" \
        --db-user testuser
    [ "$status" -ne 0 ]
    [[ "$output" == *"protect_bootstrap_context_writes_v2"* ]]
    [[ "$output" == *"postgres"* ]]

    rm -f "$plan_file" "$catalog"
}

@test "TC-743-051-mut: removing ownership check lets postgres-owned function pass" {
    local plan_file catalog mutated_script
    plan_file="$(mktemp)"
    catalog="$(mktemp)"
    mutated_script="$(mktemp)"
    _write_postgres_owned_function_plan "$plan_file"
    _write_ownership_catalog "$catalog"

    # Mutate a copy of the checker to remove the ownership-resolution block.
    python3 - <<PY
import re
with open("$REPO_ROOT/database/plan_check_superuser.py", "r", encoding="utf-8") as fh:
    src = fh.read()
# Replace _check_step's body with regex/create-only checks and no ownership lookup.
replacement = '''def _check_step(step: dict[str, Any], db_user: str, resolver: Any) -> tuple[str, str | None] | None:
    regex_reason = _step_requires_superuser(step)
    if regex_reason:
        return regex_reason, None
    if resolver is None:
        return None
    if _is_create_only(step):
        return None
    return None
'''
src = re.sub(r"def _check_step\(.*?\n(?=def |\Z)", replacement, src, count=1, flags=re.S)
with open("$mutated_script", "w", encoding="utf-8") as fh:
    fh.write(src)
PY

    run python3 "$mutated_script" \
        --plan "$plan_file" \
        --catalog-stub "$catalog" \
        --db-user testuser
    [ "$status" -eq 0 ]

    rm -f "$plan_file" "$catalog" "$mutated_script"
}

@test "TC-743-052: plan altering agent-owned table proceeds" {
    local plan_file catalog
    plan_file="$(mktemp)"
    catalog="$(mktemp)"
    _write_agent_owned_table_plan "$plan_file"
    _write_ownership_catalog "$catalog"

    run python3 "$REPO_ROOT/database/plan_check_superuser.py" \
        --plan "$plan_file" \
        --catalog-stub "$catalog" \
        --db-user testuser
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    rm -f "$plan_file" "$catalog"
}

@test "TC-743-053: unparseable step halts" {
    local plan_file catalog
    plan_file="$(mktemp)"
    catalog="$(mktemp)"
    _write_unparseable_step_plan "$plan_file"
    _write_ownership_catalog "$catalog"

    run python3 "$REPO_ROOT/database/plan_check_superuser.py" \
        --plan "$plan_file" \
        --catalog-stub "$catalog" \
        --db-user testuser
    [ "$status" -ne 0 ]
    [[ "$output" == *"unparseable or unresolvable"* ]]

    rm -f "$plan_file" "$catalog"
}
