#!/usr/bin/env bats
# Tests for nova-mind#792: remove Victoria trading-table names from the shipped
# .pgschemaignore / .pgschemaignore-peer files and assert the additive contract.
#
# CHUNK 1 (static): TC-792-001 .. TC-792-005, TC-792-081.
# CHUNK 2 (live PG): TC-792-010, TC-792-011, TC-792-030, TC-792-031.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
REORDERER="$REPO_ROOT/database/plan_reorder.py"
STRIPPER="$REPO_ROOT/database/strip_destructive.py"
VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

VICTORIA_NAMES=(
  trades
  cash_ledger
  portfolios
  positions
  instruments
  portfolio_snapshots
  portfolio_asset_classes
  strategies
  strategy_notes
  asset_classes
  open_orders
  order_adjustments
  price_cache_v2
)

_pg_available() {
    command -v psql >/dev/null 2>&1 && command -v pgschema >/dev/null 2>&1 && \
        pg_isready -h /var/run/postgresql >/dev/null 2>&1
}

_make_test_db() {
    local dbname="nova_mind_792_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

# Run the real installer plan -> reorder -> strip-destructive -> apply pipeline
# against database/schema.sql on the given DB.  Extra pgschema plan flags mirror
# the existing test_608 helper.
_run_schema_management() {
    local DB="$1"
    local PLAN="$2"
    local REORDERED="$3"
    local FILTERED="$4"
    shift 4
    local EXTRA_STRIP_ARGS=("$@")

    local SCRATCH
    SCRATCH=$(mktemp -d /tmp/pgschema-792-XXXXXX)
    cp "$REPO_ROOT/database/.pgschemaignore" "$SCRATCH/.pgschemaignore"
    cp "$REPO_ROOT/database/schema.sql" "$SCRATCH/schema.sql"

    (
        cd "$SCRATCH" || exit 1
        pgschema plan \
            --host /var/run/postgresql \
            --user nova \
            --db "$DB" \
            --schema public \
            --file schema.sql \
            --plan-host /var/run/postgresql \
            --plan-db nova_memory \
            --plan-user nova \
            --output-json "$PLAN" \
            --no-color >/dev/null 2>&1
    )

    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1
    run "$VENV_PYTHON" "$STRIPPER" --plan "$REORDERED" --output "$FILTERED" "${EXTRA_STRIP_ARGS[@]}"
    rm -rf "$SCRATCH"
}

@test "TC-792-001: Victoria table names absent from both ignore files" {
    run git -C "$REPO_ROOT" grep -nE 'trades|cash_ledger|portfolios|positions|instruments' database/.pgschemaignore database/.pgschemaignore-peer
    [ "$status" -eq 1 ]
    [ -z "$output" ]

    local f name
    for f in "$REPO_ROOT/database/.pgschemaignore" "$REPO_ROOT/database/.pgschemaignore-peer"; do
        for name in "${VICTORIA_NAMES[@]}"; do
            if grep -qF "$name" "$f"; then
                echo "Found Victoria name '$name' in $f" >&3
                false
            fi
        done
    done
}

@test "TC-792-002: generic *_local pattern preserved in both files" {
    grep -F '"*_local"' "$REPO_ROOT/database/.pgschemaignore"
    grep -F '"*_local"' "$REPO_ROOT/database/.pgschemaignore-peer"
}

@test "TC-792-003: peer-only federation objects preserved in .pgschemaignore-peer only" {
    grep -qF 'nova_bootstrap_context' "$REPO_ROOT/database/.pgschemaignore-peer"
    grep -qF 'bootstrap_context_view_' "$REPO_ROOT/database/.pgschemaignore-peer"
    grep -qF 'protect_bootstrap_context_writes_v2' "$REPO_ROOT/database/.pgschemaignore-peer"

    if [ -f "$REPO_ROOT/database/.pgschemaignore" ]; then
        run grep -nE 'nova_bootstrap_context|bootstrap_context_view_|protect_bootstrap_context_writes_v2' "$REPO_ROOT/database/.pgschemaignore"
        [ "$status" -eq 1 ]
        [ -z "$output" ]
    fi
}

@test "TC-792-004: both ignore files still parse as valid TOML" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available"
    fi
    python3 - <<PY
import sys, tomllib
for p in [
    "$REPO_ROOT/database/.pgschemaignore",
    "$REPO_ROOT/database/.pgschemaignore-peer",
]:
    with open(p, "rb") as fh:
        tomllib.load(fh)
PY
}

@test "TC-792-005: .pgschemaignore-peer stays in sync with base file for non-Victoria, non-federation entries" {
    local py
    py=$(cat <<'PY'
import re, sys, tomllib

def load_section_text(path, section):
    with open(path, "r") as fh:
        text = fh.read()
    m = re.search(rf"^\[{re.escape(section)}\].*?(?=^\[|^\Z)", text, re.MULTILINE | re.DOTALL)
    return m.group(0) if m else ""

def load_patterns(path, section):
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    return list(data.get(section, {}).get("patterns", []))

base = load_patterns(sys.argv[1], "tables")
peer = load_patterns(sys.argv[2], "tables")
peer_no_fed = [p for p in peer if p != "nova_bootstrap_context"]
if base != peer_no_fed:
    print("base tables:", base, file=sys.stderr)
    print("peer tables (without federation):", peer_no_fed, file=sys.stderr)
    sys.exit(1)

for section in ("views", "functions", "triggers"):
    peer_patterns = load_patterns(sys.argv[2], section)
    for name in sys.argv[3:]:
        if name in peer_patterns:
            print(f"Victoria name {name!r} found in peer [{section}]", file=sys.stderr)
            sys.exit(1)

# Federation sections must be byte-for-byte unchanged outside the [tables] array.
expected_functions = ['bootstrap_context_view_*', 'protect_bootstrap_context_writes_v2']
actual_functions = load_patterns(sys.argv[2], "functions")
if actual_functions != expected_functions:
    print("peer functions changed:", actual_functions, file=sys.stderr)
    sys.exit(1)
expected_triggers = ['protect_bootstrap_context', 'heartbeat_content_changed', 'zz_touch_updated_at']
actual_triggers = load_patterns(sys.argv[2], "triggers")
if actual_triggers != expected_triggers:
    print("peer triggers changed:", actual_triggers, file=sys.stderr)
    sys.exit(1)
PY
)
    "$VENV_PYTHON" - "$REPO_ROOT/database/.pgschemaignore" "$REPO_ROOT/database/.pgschemaignore-peer" "${VICTORIA_NAMES[@]}" <<PY
$py
PY
}

@test "TC-792-081: schema.sql has no FK referencing a Victoria/agent-local table" {
    local name
    for name in "${VICTORIA_NAMES[@]}"; do
        if grep -nE "REFERENCES\s+\(?\s*${name}\b" "$REPO_ROOT/database/schema.sql" >/dev/null 2>&1; then
            echo "schema.sql references $name via FK" >&3
            false
        fi
    done
}

@test "TC-792-010: fresh empty DB full pipeline exit 0 with zero destructive ops" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    FILTERED=$(mktemp)

    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]
    [[ "$output" == "0" ]]

    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    local expected_count actual_count
    expected_count=$(grep -cE '^CREATE TABLE ' "$REPO_ROOT/database/schema.sql")
    actual_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';")
    [ "$actual_count" -eq "$expected_count" ]

    local victoria_left
    victoria_left=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ($(printf "'%s'," "${VICTORIA_NAMES[@]}" | sed 's/,$//'));")
    [ "$victoria_left" -eq 0 ]

    rm -f "$PLAN" "$REORDERED" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-792-011: fresh install is idempotent on second run" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    FILTERED=$(mktemp)

    # First run
    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]
    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    # Second run: plan should be empty and strip count 0.
    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]
    [[ "$output" == "0" ]]

    run "$VENV_PYTHON" -c "import json; p=json.load(open('$FILTERED')); print(len(p.get('groups', [])))"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]

    rm -f "$PLAN" "$REORDERED" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-792-030: existing managed table missing sender_name gets column added" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    FILTERED=$(mktemp)

    # Bring the DB to the full schema.sql state, then drop only the column
    # under test and insert rows.  This isolates the test to a single ADD
    # COLUMN step rather than a broad diff against a hand-built partial table.
    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]
    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
ALTER TABLE extraction_failures DROP COLUMN sender_name;
INSERT INTO extraction_failures (session_key, content, status) VALUES
    ('s1', 'hello', 'pending'),
    ('s2', 'world', 'pending');
SQL

    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]

    run "$VENV_PYTHON" - <<PY
import json
with open('$REORDERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
for s in steps:
    if s.get('path') == 'public.extraction_failures.sender_name':
        print(s.get('operation'), s.get('type'))
        break
else:
    print('MISSING')
PY
    [ "$status" -eq 0 ]
    # pgschema emits ADD COLUMN as operation "create", type "table.column"
    # (the TC doc guessed "alter"; adjusted to match observed behavior).
    [[ "$output" == "create table.column" ]]

    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    local sender_exists row_count null_count
    sender_exists=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='extraction_failures' AND column_name='sender_name';")
    [ "$sender_exists" -eq 1 ]
    row_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM extraction_failures;")
    [ "$row_count" -eq 2 ]
    null_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM extraction_failures WHERE sender_name IS NULL;")
    [ "$null_count" -eq 2 ]

    rm -f "$PLAN" "$REORDERED" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-792-031: existing managed table missing retry_count gets NOT NULL DEFAULT backfilled" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    FILTERED=$(mktemp)

    # Bring the DB to the full schema.sql state, then drop only the column
    # under test and insert rows.
    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]
    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
ALTER TABLE extraction_failures DROP COLUMN retry_count;
INSERT INTO extraction_failures (session_key, content, status) VALUES
    ('s1', 'hello', 'pending'),
    ('s2', 'world', 'pending');
SQL

    _run_schema_management "$DB" "$PLAN" "$REORDERED" "$FILTERED"
    [ "$status" -eq 0 ]

    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    [ "$status" -eq 0 ]

    local retry_exists zero_count
    retry_exists=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='extraction_failures' AND column_name='retry_count';")
    [ "$retry_exists" -eq 1 ]
    zero_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM extraction_failures WHERE retry_count = 0;")
    [ "$zero_count" -eq 2 ]

    rm -f "$PLAN" "$REORDERED" "$FILTERED"
    _drop_test_db "$DB"
}
