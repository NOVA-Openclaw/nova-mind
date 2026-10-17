#!/usr/bin/env bats
# Tests for nova-mind#666 / #1231 step 5:
#   - installer-created objects owned by postgres are transferred to DB_USER
#   - peer/FDW bootstrap stack is left untouched
#   - grant_reconcile_gate catches missing privileges on tables and foreign tables

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIX_OWNERSHIP="$REPO_ROOT/database/fix_installer_ownership.py"
GATE="$REPO_ROOT/database/grant_reconcile_gate.py"

_pg_available() {
    command -v psql >/dev/null 2>&1 && command -v pg_isready >/dev/null 2>&1 && \
        pg_isready -h /var/run/postgresql >/dev/null 2>&1
}

_make_test_db() {
    local dbname="nova_mind_666_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

_create_test_user() {
    local user="testuser_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    psql -U nova -d postgres -c "CREATE ROLE \"$user\" LOGIN;" >/dev/null 2>&1
    echo "$user"
}

_drop_test_user() {
    local user="$1"
    psql -U nova -d postgres -c "DROP ROLE IF EXISTS \"$user\";" >/dev/null 2>&1 || true
}

# Create a plain table as postgres, simulating a pgschema apply on a fresh DB.
_seed_postgres_table() {
    local DB="$1"
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
SET ROLE postgres;
CREATE TABLE installer_created_table (
    id serial PRIMARY KEY,
    payload text NOT NULL
);
CREATE INDEX idx_installer_created_payload ON installer_created_table(payload);
CREATE FUNCTION installer_created_fn() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RETURN NEW; END;
$$;
SQL
}

# Seed a peer/FDW fixture.  The foreign table + view must stay postgres-owned.
_seed_fdw_fixture() {
    local DB="$1"
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
SET ROLE postgres;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'loopback') THEN
        EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L)', 'localhost', current_database());
    END IF;
END $$;
CREATE TABLE fdw_local_table (
    id serial PRIMARY KEY,
    context_type text NOT NULL
);
CREATE FOREIGN TABLE fdw_foreign_table (
    id int,
    context_type text
) SERVER loopback OPTIONS (schema_name 'public', table_name 'fdw_local_table');
-- Mirror the real bootstrap view: it depends on both the local backing table and the foreign table.
CREATE VIEW fdw_backed_view AS
    SELECT id, context_type FROM fdw_local_table
    UNION ALL
    SELECT id, context_type FROM fdw_foreign_table;
CREATE TABLE normal_installer_table (id serial PRIMARY KEY);
SQL
}

# Run the ownership transfer helper and apply the generated SQL as nova (superuser).
_run_ownership_transfer() {
    local DB="$1"
    local DB_USER="$2"
    local plan_file plan_err
    plan_file=$(mktemp)
    plan_err=$(mktemp)
    if python3 "$FIX_OWNERSHIP" --dbname "$DB" --db-user "$DB_USER" --superuser postgres --connect-user nova plan >"$plan_file" 2>"$plan_err"; then
        psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -f "$plan_file" >/dev/null
    else
        cat "$plan_err" >&2
        return 1
    fi
}

# Run the grant reconcile gate in "check" mode.
_run_gate_check() {
    local DB="$1"
    local DB_USER="$2"
    python3 "$GATE" --dbname "$DB" --db-user "$DB_USER" --superuser postgres check
}

@test "TC-666a: postgres-created table is transferred to DB_USER and accessible" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    _seed_postgres_table "$DB"

    # Before transfer: DB_USER cannot use the table.
    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"installer_created_table"* ]]

    _run_ownership_transfer "$DB" "$DB_USER"

    # Ownership moved to DB_USER.
    run psql -U nova -d "$DB" -tAc "SELECT rolname FROM pg_class c JOIN pg_roles r ON r.oid=c.relowner WHERE c.relname='installer_created_table'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$DB_USER"* ]]

    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -eq 0 ]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666a-mut: skipping ownership transfer leaves the table inaccessible" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    _seed_postgres_table "$DB"

    # No transfer happened.
    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"installer_created_table"* ]]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666b: FDW bootstrap stack remains owned by postgres" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    _seed_fdw_fixture "$DB"

    _run_ownership_transfer "$DB" "$DB_USER"

    # Normal table moved; FDW objects did not.
    run psql -U nova -d "$DB" -tAc "SELECT c.relname, r.rolname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_roles r ON r.oid=c.relowner WHERE n.nspname='public' AND c.relname IN ('normal_installer_table','fdw_foreign_table','fdw_backed_view','fdw_local_table') ORDER BY c.relname"
    [ "$status" -eq 0 ]
    [[ "$output" == *"normal_installer_table|$DB_USER"* ]]
    [[ "$output" == *"fdw_foreign_table|postgres"* ]]
    [[ "$output" == *"fdw_backed_view|postgres"* ]]
    [[ "$output" == *"fdw_local_table|postgres"* ]]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666b-mut: without FDW exclusion the helper would retitle FDW objects" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    _seed_fdw_fixture "$DB"

    # Monkeypatch the helper to disable the FDW exclusion.
    run python3 - "$DB" "$DB_USER" <<PY
import sys
sys.path.insert(0, '$REPO_ROOT/database')
import fix_installer_ownership
fix_installer_ownership._fdw_excluded_oids = lambda cur: set()
sql, _ = fix_installer_ownership._generate_sql('$DB', '$DB_USER', 'postgres', 'nova')
for stmt in sql:
    if 'fdw_foreign_table' in stmt or 'fdw_backed_view' in stmt or 'fdw_local_table' in stmt:
        print(stmt)
PY
    [ "$status" -eq 0 ]
    [ -n "$output" ]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666c: gate fails when DB_USER lacks SELECT on a postgres-owned table" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -c "SET ROLE postgres; CREATE TABLE gate_test_table (id int);" >/dev/null

    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"gate_test_table"* ]]
    [[ "$output" == *"SELECT"* ]]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666c-mut: removing SELECT from the gate check hides the failure" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -c "SET ROLE postgres; CREATE TABLE gate_test_table (id int);" >/dev/null
    # Grant DML so the only missing required privilege is SELECT.
    psql -U nova -d "$DB" -c "SET ROLE postgres; GRANT INSERT, UPDATE, DELETE ON TABLE gate_test_table TO \"$DB_USER\";" >/dev/null

    # Normal gate fails because SELECT is required.
    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SELECT"* ]]

    # Monkeypatch the gate so tables only require INSERT/UPDATE/DELETE.
    run python3 - "$DB" "$DB_USER" <<PY
import sys
sys.path.insert(0, '$REPO_ROOT/database')
import grant_reconcile_gate
grant_reconcile_gate._PRIVS_BY_KIND['r'] = [
    ('INSERT', 'has_table'), ('UPDATE', 'has_table'), ('DELETE', 'has_table')
]
sys.exit(grant_reconcile_gate.main(['--dbname', '$DB', '--db-user', '$DB_USER', '--superuser', 'postgres', 'check']))
PY
    [ "$status" -eq 0 ]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666d: gate covers a standalone foreign table" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
SET ROLE postgres;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DO $$
BEGIN
    EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L)', 'localhost', current_database());
END $$;
CREATE TABLE ft_local (id int);
CREATE FOREIGN TABLE ft_foreign (id int) SERVER loopback OPTIONS (schema_name 'public', table_name 'ft_local');
SQL
    # The backing local table must also satisfy the gate; grant it everything.
    psql -U nova -d "$DB" -c "SET ROLE postgres; GRANT ALL ON TABLE ft_local TO \"$DB_USER\";" >/dev/null

    # Foreign table is owned by postgres and not part of the FDW view stack.
    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ft_foreign"* ]]
    [[ "$output" == *"SELECT"* ]]

    psql -U nova -d "$DB" -c "SET ROLE postgres; GRANT SELECT ON TABLE ft_foreign TO \"$DB_USER\";" >/dev/null
    run _run_gate_check "$DB" "$DB_USER"
    [ "$status" -eq 0 ]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666d-mut: excluding relkind f from the gate hides foreign-table failures" {
    if ! _pg_available; then skip "PostgreSQL not available"; fi

    DB=$(_make_test_db)
    DB_USER=$(_create_test_user)
    psql -U nova -d "$DB" -c "GRANT CONNECT ON DATABASE \"$DB\" TO \"$DB_USER\";" >/dev/null
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
SET ROLE postgres;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DO $$
BEGIN
    EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L)', 'localhost', current_database());
END $$;
CREATE TABLE ft_local (id int);
CREATE FOREIGN TABLE ft_foreign (id int) SERVER loopback OPTIONS (schema_name 'public', table_name 'ft_local');
SQL
    psql -U nova -d "$DB" -c "SET ROLE postgres; GRANT ALL ON TABLE ft_local TO \"$DB_USER\";" >/dev/null

    run python3 - "$DB" "$DB_USER" <<PY
import sys
sys.path.insert(0, '$REPO_ROOT/database')
import grant_reconcile_gate
grant_reconcile_gate._PRIVS_BY_KIND['f'] = []
sys.exit(grant_reconcile_gate.main(['--dbname', '$DB', '--db-user', '$DB_USER', '--superuser', 'postgres', 'check']))
PY
    [ "$status" -eq 0 ]

    _drop_test_db "$DB"
    _drop_test_user "$DB_USER"
}

@test "TC-666-shellcheck: new bats file passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}
