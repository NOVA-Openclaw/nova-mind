#!/usr/bin/env bats
# Tests for nova-mind#498: additive-by-construction pgschema apply.
#
# Verifies that the installer strips DROP operations from the pgschema plan
# before applying, so:
#   * unknown/local tables survive with their data intact,
#   * additive CREATEs still land,
#   * the apply exits 0.
#
# These tests do NOT run the full agent-install.sh; they exercise the same
# plan -> reorder -> strip-destructive -> apply chain the installer uses.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
REORDERER="$REPO_ROOT/database/plan_reorder.py"
STRIPPER="$REPO_ROOT/database/strip_destructive.py"
VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

_pg_available() {
    command -v psql >/dev/null 2>&1 && command -v pgschema >/dev/null 2>&1 && \
        pg_isready -h /var/run/postgresql >/dev/null 2>&1
}

_make_test_db() {
    local dbname="nova_mind_additive_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

@test "strip_destructive.py removes all DROP steps and reports count" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "1.7.2",
  "source_fingerprint": {"hash": "x"},
  "groups": [{"steps": [
    {"sql": "DROP TABLE IF EXISTS public.local_table;", "type": "table", "operation": "drop", "path": "public.local_table"},
    {"sql": "DROP INDEX IF EXISTS public.idx_local;", "type": "index", "operation": "drop", "path": "public.idx_local"},
    {"sql": "ALTER TABLE public.local_table DROP COLUMN old_col;", "type": "column", "operation": "drop", "path": "public.local_table.old_col"},
    {"sql": "CREATE TABLE public.work_queue (id serial PRIMARY KEY);", "type": "table", "operation": "create", "path": "public.work_queue"}
  ]}]
}
JSON

    run "$VENV_PYTHON" "$STRIPPER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]

    run "$VENV_PYTHON" -c "import json; p=json.load(open('$OUT')); print(len(p['groups'][0]['steps']), p['groups'][0]['steps'][0]['operation'])"
    [ "$status" -eq 0 ]
    [[ "$output" == "1 create" ]]

    rm -f "$PLAN" "$OUT"
}

@test "TC-498a: additive apply preserves a drift-seeded local table" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCHEMA=$(mktemp)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    FILTERED=$(mktemp)

    # Seed a fake agent-local table with rows (simulates Victoria's trades/cash_ledger).
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE local_only (id serial PRIMARY KEY, payload text);
INSERT INTO local_only (payload) VALUES ('row1'), ('row2'), ('row3');
SQL

    # Schema desired state only knows about a new shared table, NOT local_only.
    cat >"$SCHEMA" <<'SQL'
CREATE TABLE new_shared (id serial PRIMARY KEY);
SQL

    pgschema plan \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --file "$SCHEMA" \
        --output-json "$PLAN" \
        --no-color >/dev/null 2>&1

    # Without additive filtering, pgschema would plan a DROP for local_only.
    run "$VENV_PYTHON" -c "import json; p=json.load(open('$PLAN')); drops=[s for g in (p.get('groups') or []) for s in g['steps'] if s.get('operation')=='drop']; print(len(drops))"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    # Reorder + strip destructive ops (installer pipeline).
    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1
    "$VENV_PYTHON" "$STRIPPER" --plan "$REORDERED" --output "$FILTERED" >/dev/null 2>&1

    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    # a) local table survived with its rows
    local local_count
    local_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM local_only;")
    [ "$local_count" -eq 3 ]

    # b) additive CREATE landed
    local shared_exists
    shared_exists=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='new_shared';")
    [ "$shared_exists" -eq 1 ]

    rm -f "$SCHEMA" "$PLAN" "$REORDERED" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-498b: additive apply strips DROP COLUMN on a managed table" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCHEMA=$(mktemp)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    FILTERED=$(mktemp)

    # Existing managed table with a column that schema.sql will no longer define.
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE managed (id serial PRIMARY KEY, old_col text, new_col text);
INSERT INTO managed (old_col, new_col) VALUES ('keep', 'keep');
SQL

    # Desired state drops old_col and keeps new_col.
    cat >"$SCHEMA" <<'SQL'
CREATE TABLE managed (id serial PRIMARY KEY, new_col text);
SQL

    pgschema plan \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --file "$SCHEMA" \
        --output-json "$PLAN" \
        --no-color >/dev/null 2>&1

    # Reorder + strip destructive ops.
    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1
    "$VENV_PYTHON" "$STRIPPER" --plan "$REORDERED" --output "$FILTERED" >/dev/null 2>&1

    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    # The destructive DROP COLUMN was skipped, so old_col still exists.
    local old_col_exists
    old_col_exists=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='managed' AND column_name='old_col';")
    [ "$old_col_exists" -eq 1 ]

    # The row survived.
    local row_count
    row_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM managed;")
    [ "$row_count" -eq 1 ]

    rm -f "$SCHEMA" "$PLAN" "$REORDERED" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-498c: strip_destructive.py handles malformed plan JSON" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{"version": "1.0.0", "groups": "not-an-array"}
JSON
    run "$VENV_PYTHON" "$STRIPPER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 2 ]
    rm -f "$PLAN" "$OUT"
}

@test "TC-498d: pre-migration 007 is no longer in the auto-run directory" {
    [ ! -f "$REPO_ROOT/database/pre-migrations/007-drop-deprecated-agent-bootstrap-context-local.sql" ]
}

@test "TC-498e: manual migration 007 exists and is guarded" {
    local manual="$REPO_ROOT/database/manual-migrations/MANUAL-007-drop-agent-bootstrap-context-local.sql"
    [ -f "$manual" ]
    grep -q "to_regclass('public.agent_bootstrap_context_local')" "$manual"
    grep -q "row_count > 0" "$manual"
    grep -q "RAISE EXCEPTION" "$manual"
}
