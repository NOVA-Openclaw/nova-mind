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
    if [ -n "${NOVA_MIND_TEST_TEMPLATE:-}" ]; then
        createdb -T "$NOVA_MIND_TEST_TEMPLATE" -U nova "$dbname" >/dev/null 2>&1
    else
        createdb -U nova "$dbname" >/dev/null 2>&1
    fi
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

# --- CHUNK 3 helpers (TC-792-020 .. TC-792-025, TC-792-080) ---

CHECK_SUPERUSER="$REPO_ROOT/database/plan_check_superuser.py"
DETECTOR="$REPO_ROOT/database/detect_peer_shadowed.py"
INJECTOR="$REPO_ROOT/database/inject_peer_shadowed_ignores.py"

# Copied from tests/install/test_608_peer_fdw_bootstrap_context.bats so the
# #792 suite can build the same peer-shadowed bootstrap-context fixture.
_seed_peer_fixture() {
    local DB="$1"
    local HAS_FUNCTIONS="$2"
    local HAS_TRIGGERS="$3"
    local FIXTURE
    FIXTURE=$(mktemp)

    # The template DB may have postgres_fdw installed but not grant USAGE on
    # the wrapper to nova.  Detect that before trying to create a server and
    # fall back to a view-only peer shape.  A VIEW alone is enough to make
    # detect_peer_shadowed.py switch into peer mode for #792's gating tests.
    local fdw_usable
    fdw_usable=$(psql -U nova -d "$DB" -tAc "SELECT CASE WHEN has_foreign_data_wrapper_privilege(current_user,'postgres_fdw','USAGE') THEN 1 ELSE 0 END;")
    if [ "$fdw_usable" != "1" ]; then
        echo "TC-792 peer fixture: postgres_fdw USAGE not granted; using view-only peer shape" >&3
    fi

    cat > "$FIXTURE" <<'SQL'
CREATE TABLE agent_bootstrap_context_local (
    id serial PRIMARY KEY,
    context_type text NOT NULL,
    domain_names text[],
    file_key text NOT NULL,
    content text NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    updated_by text DEFAULT CURRENT_USER,
    agent_name text
);
SQL

    if [ "$fdw_usable" = "1" ]; then
        cat >> "$FIXTURE" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='postgres_fdw') THEN
    CREATE EXTENSION postgres_fdw;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname='loopback') THEN
    EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L)', 'localhost', current_database());
  END IF;
END $$;
CREATE FOREIGN TABLE nova_bootstrap_context (
    id int,
    context_type text,
    domain_names text[],
    file_key text,
    content text,
    description text,
    updated_at timestamptz,
    updated_by text,
    agent_name text
) SERVER loopback OPTIONS (schema_name 'public', table_name 'agent_bootstrap_context_local');
CREATE VIEW agent_bootstrap_context AS
    SELECT id, context_type, domain_names, file_key, content, description, updated_at, updated_by, agent_name
      FROM nova_bootstrap_context
     WHERE context_type = ANY(ARRAY['UNIVERSAL','GLOBAL'])
    UNION ALL
    SELECT id, context_type, domain_names, file_key, content, description, updated_at, updated_by, agent_name
      FROM agent_bootstrap_context_local
     WHERE context_type <> ALL(ARRAY['UNIVERSAL','GLOBAL']);
SQL
    else
        cat >> "$FIXTURE" <<'SQL'
CREATE VIEW agent_bootstrap_context AS
    SELECT id, context_type, domain_names, file_key, content, description, updated_at, updated_by, agent_name
      FROM agent_bootstrap_context_local;
SQL
    fi

    if [ "$HAS_FUNCTIONS" -eq 1 ]; then
        cat >> "$FIXTURE" <<'SQL'
CREATE FUNCTION bootstrap_context_view_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END; $$;
CREATE FUNCTION bootstrap_context_view_update() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END; $$;
CREATE FUNCTION bootstrap_context_view_delete() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END; $$;
SQL
    fi

    if [ "$HAS_TRIGGERS" -eq 1 ]; then
        cat >> "$FIXTURE" <<'SQL'
CREATE TRIGGER bootstrap_context_view_on_insert INSTEAD OF INSERT ON agent_bootstrap_context FOR EACH ROW EXECUTE FUNCTION bootstrap_context_view_insert();
CREATE TRIGGER bootstrap_context_view_on_update INSTEAD OF UPDATE ON agent_bootstrap_context FOR EACH ROW EXECUTE FUNCTION bootstrap_context_view_update();
CREATE TRIGGER bootstrap_context_view_on_delete INSTEAD OF DELETE ON agent_bootstrap_context FOR EACH ROW EXECUTE FUNCTION bootstrap_context_view_delete();
SQL
    fi

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -f "$FIXTURE" >/dev/null
    rm -f "$FIXTURE"
}

# Copied from tests/install/test_608_peer_fdw_bootstrap_context.bats.
_assert_no_bootstrap_refs() {
    local FILTERED="$1"
    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
violations = []
for s in steps:
    path = s.get('path', '')
    if re.search(r'(?<!\w)agent_bootstrap_context_id_seq(?!\w)', path):
        violations.append(path)
    elif re.search(r'(?<!\w)agent_bootstrap_context(?!\w)', path) and '_local' not in path:
        violations.append(path)
print('\n'.join(violations))
PY
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Subset of Victoria trading-table names used in the drift-seeded fixtures.
VICTORIA_TRADING_TABLES=(
  portfolios
  instruments
  positions
  trades
  cash_ledger
)

# Hand-built DDL for a Victoria-shaped trading fixture.  Used as the fallback
# when a real schema-only dump of victoria_memory is unavailable.
_victoria_trading_ddl() {
    cat <<'SQL'
CREATE TABLE IF NOT EXISTS portfolios (
    id serial PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS instruments (
    id serial PRIMARY KEY,
    symbol text UNIQUE NOT NULL
);
CREATE TABLE IF NOT EXISTS positions (
    id serial PRIMARY KEY,
    portfolio_id int REFERENCES portfolios(id),
    instrument_id int REFERENCES instruments(id),
    quantity numeric NOT NULL
);
CREATE TABLE IF NOT EXISTS trades (
    id serial PRIMARY KEY,
    position_id int REFERENCES positions(id),
    side text NOT NULL,
    qty numeric NOT NULL,
    price numeric NOT NULL,
    traded_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS cash_ledger (
    id serial PRIMARY KEY,
    portfolio_id int REFERENCES portfolios(id),
    amount numeric NOT NULL,
    entry_type text NOT NULL,
    posted_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_positions_portfolio ON positions(portfolio_id);
CREATE INDEX IF NOT EXISTS idx_trades_position ON trades(position_id);

CREATE OR REPLACE FUNCTION touch_portfolios_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.created_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS portfolios_updated_at ON portfolios;
CREATE TRIGGER portfolios_updated_at
    BEFORE UPDATE ON portfolios
    FOR EACH ROW
    EXECUTE FUNCTION touch_portfolios_updated_at();
SQL
}

# Seed the Victoria-shaped trading fixture.
# Args: DB_NAME [OWNER_ROLE]
_seed_victoria_trading_fixture() {
    local DB="$1"
    local OWNER_ROLE="${2:-}"
    local FIXTURE
    FIXTURE=$(mktemp)

    _victoria_trading_ddl > "$FIXTURE"

    if [ -n "$OWNER_ROLE" ]; then
        {
            # The owner role needs CREATE on public to create the fixture
            # objects.  Nova is the DB owner, so it can grant that.
            echo "GRANT CREATE ON SCHEMA public TO \"$OWNER_ROLE\";"
            echo "SET ROLE \"$OWNER_ROLE\";"
            cat "$FIXTURE"
        } > "${FIXTURE}.owned"
        mv "${FIXTURE}.owned" "$FIXTURE"
    fi

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -f "$FIXTURE" >/dev/null
    rm -f "$FIXTURE"
}

# Seed non-trivial row counts with FK linkage.
# Args: DB_NAME
_seed_victoria_trading_rows() {
    local DB="$1"
    # The hand-built fixture and the real dump from victoria_memory have
    # different column shapes.  Detect which one is loaded and seed accordingly.
    local is_real_shape
    is_real_shape=$(psql -U nova -d "$DB" -tAc "SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='portfolios' AND column_name='portfolio_id' LIMIT 1;")
    if [ "$is_real_shape" = "1" ]; then
        _seed_victoria_trading_rows_real "$DB"
    else
        _seed_victoria_trading_rows_handbuilt "$DB"
    fi
}

_seed_victoria_trading_rows_handbuilt() {
    local DB="$1"
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
INSERT INTO portfolios (name) VALUES ('alpha'), ('beta'), ('gamma');
INSERT INTO instruments (symbol) VALUES
    ('AAPL'), ('MSFT'), ('GOOGL'), ('TSLA'), ('NVDA');
INSERT INTO positions (portfolio_id, instrument_id, quantity)
SELECT p.id, i.id, (random() * 100)::numeric
  FROM portfolios p, instruments i;
DELETE FROM positions WHERE id > 10;
INSERT INTO trades (position_id, side, qty, price)
SELECT id, CASE WHEN random() < 0.5 THEN 'buy' ELSE 'sell' END,
       (random() * 10)::numeric, (random() * 1000)::numeric
  FROM generate_series(1,3) g, positions;
INSERT INTO cash_ledger (portfolio_id, amount, entry_type)
SELECT id, (random() * 1000)::numeric,
       CASE WHEN random() < 0.5 THEN 'credit' ELSE 'debit' END
  FROM generate_series(1,5) g, portfolios;
SQL
}

_seed_victoria_trading_rows_real() {
    local DB="$1"
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
-- The real schema has FKs from instruments to portfolio_asset_classes and
-- from positions/trades/cash_ledger to portfolios/instruments.  Seed a
-- small, self-consistent graph that satisfies the table CHECK constraints.
INSERT INTO portfolio_asset_classes (code, name) VALUES ('STOCK', 'Stocks');
INSERT INTO portfolios (slug, name, mode) VALUES
    ('alpha', 'Alpha', 'paper'),
    ('beta', 'Beta', 'paper'),
    ('gamma', 'Gamma', 'paper');
INSERT INTO instruments (symbol, asset_class, name) VALUES
    ('AAPL', 'STOCK', 'Apple Inc.'),
    ('MSFT', 'STOCK', 'Microsoft Corp.'),
    ('GOOGL', 'STOCK', 'Alphabet Inc.'),
    ('TSLA', 'STOCK', 'Tesla Inc.'),
    ('NVDA', 'STOCK', 'NVIDIA Corp.');
INSERT INTO positions (instrument_id, quantity, cost_basis, opened_at, portfolio_id)
SELECT i.instrument_id, (random() * 100)::numeric, (random() * 1000)::numeric, now(), p.portfolio_id
  FROM portfolios p, instruments i;
DELETE FROM positions WHERE id > 10;
INSERT INTO trades (executed_at, instrument_id, side, quantity, source, portfolio_id)
SELECT now(), pos.instrument_id,
       CASE WHEN random() < 0.5 THEN 'buy' ELSE 'sell' END,
       (random() * 10)::numeric, 'seed', pos.portfolio_id
  FROM generate_series(1,3) g, positions pos;
INSERT INTO cash_ledger (delta, portfolio_id)
SELECT (random() * 1000)::numeric, portfolio_id
  FROM generate_series(1,5) g, portfolios;
SQL
}

# The fixture itself tolerates a postgres_fdw installation that does not
# grant USAGE to nova by falling back to a view-only peer shape.  Do not
# skip gating tests just because the FDW server cannot be created.
_skip_unless_fdw() {
    return 0
}

# Apply database/schema.sql to a scratch DB using the additive pipeline (no
# ownership gate, no plan_check_superuser gate).  This brings the DB to a
# production-like state where schema.sql objects already exist, so the real
# test pipeline plans only drift steps and plan_check_superuser does not flag
# CREATE OR REPLACE steps as missing objects.
# Args: DB_NAME
_apply_schema_sql_to_db() {
    local DB="$1"
    local SCRATCH PLAN REORDERED FILTERED
    SCRATCH=$(mktemp -d /tmp/pgschema-792-schema-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    cp "$REPO_ROOT/database/schema.sql" "$SCRATCH/schema.sql"
    cp "$REPO_ROOT/database/.pgschemaignore" "$SCRATCH/.pgschemaignore"

    # Use the target DB as the plan DB so the resulting DB matches schema.sql
    # exactly.  Using nova_memory would propagate any drift in nova_memory
    # (e.g. an extra table comment) into later drift-detect steps.
    (
        cd "$SCRATCH" || exit 1
        pgschema plan \
            --host /var/run/postgresql \
            --user nova \
            --db "$DB" \
            --schema public \
            --file schema.sql \
            --plan-host /var/run/postgresql \
            --plan-db "$DB" \
            --plan-user nova \
            --output-json "$PLAN" \
            --no-color >/dev/null 2>&1
    ) || {
        rm -rf "$SCRATCH"
        return 1
    }

    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1 || {
        rm -rf "$SCRATCH"
        return 1
    }
    "$VENV_PYTHON" "$STRIPPER" --plan "$REORDERED" --output "$FILTERED" >/dev/null 2>&1 || {
        rm -rf "$SCRATCH"
        return 1
    }
    pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color >/dev/null 2>&1
    local apply_status=$?
    rm -rf "$SCRATCH"
    return $apply_status
}

# Capture row counts for the Victoria trading tables as JSON.
# Args: DB_NAME OUT_FILE
_capture_victoria_row_counts() {
    local DB="$1"
    local OUT="$2"
    {
        echo "{"
        local first=1
        local t cnt
        for t in "${VICTORIA_TRADING_TABLES[@]}"; do
            cnt=$(psql -U nova -d "$DB" -tAc "SELECT count(*) FROM \"$t\"")
            [ "$first" -eq 1 ] || echo ","
            echo "  \"$t\": $cnt"
            first=0
        done
        echo "}"
    } > "$OUT"
}

# Capture full object inventory for the Victoria trading tables as JSON.
# Args: DB_NAME OUT_FILE
_capture_victoria_object_inventory() {
    local DB="$1"
    local OUT="$2"
    local table_list index_list seq_list
    table_list=$(printf "'%s'," "${VICTORIA_TRADING_TABLES[@]}" | sed 's/,$//')
    index_list=$table_list
    seq_list=$(printf "'%s_id_seq'," "${VICTORIA_TRADING_TABLES[@]}" | sed 's/,$//')

    psql -U nova -d "$DB" -tAc "SELECT json_build_object(
        'tables', (SELECT coalesce(json_agg(json_build_object('name', table_name, 'type', table_type) ORDER BY table_name), '[]') FROM information_schema.tables WHERE table_schema='public' AND table_name IN ($table_list)),
        'columns', (SELECT coalesce(json_agg(json_build_object('table', table_name, 'column', column_name, 'data_type', data_type, 'is_nullable', is_nullable) ORDER BY table_name, column_name), '[]') FROM information_schema.columns WHERE table_schema='public' AND table_name IN ($table_list)),
        'indexes', (SELECT coalesce(json_agg(json_build_object('table', tablename, 'index', indexname) ORDER BY tablename, indexname), '[]') FROM pg_indexes WHERE schemaname='public' AND tablename IN ($index_list)),
        'constraints', (SELECT coalesce(json_agg(json_build_object('table', conrelid::regclass::text, 'name', conname, 'type', contype::text) ORDER BY conrelid::regclass::text, conname), '[]') FROM pg_constraint c JOIN pg_class cl ON cl.oid=c.conrelid JOIN pg_namespace n ON n.oid=cl.relnamespace WHERE n.nspname='public' AND cl.relname IN ($table_list)),
        'triggers', (SELECT coalesce(json_agg(json_build_object('table', tgrelid::regclass::text, 'name', tgname) ORDER BY tgrelid::regclass::text, tgname), '[]') FROM pg_trigger tg JOIN pg_class cl ON cl.oid=tgrelid JOIN pg_namespace n ON n.oid=cl.relnamespace WHERE n.nspname='public' AND cl.relname IN ($table_list) AND NOT tgisinternal),
        'sequences', (SELECT coalesce(json_agg(json_build_object('name', c.relname) ORDER BY c.relname), '[]') FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='S' AND c.relname IN ($seq_list))
    );" > "$OUT"
}

# Run the full installer pipeline: detect peer shadowed, inject ignores, plan,
# reorder, strip destructive, plan_check_superuser, apply.  Copies the filtered
# plan to FILTERED_OUT if provided.
# Args: DB_NAME PEER_MODE(0|1) STRIP_LOG [FILTERED_OUT]
_run_full_installer_pipeline() {
    local DB="$1"
    local PEER_MODE="$2"
    local STRIP_LOG="$3"
    local FILTERED_OUT="${4:-}"

    local SCRATCH PLAN REORDERED FILTERED
    SCRATCH=$(mktemp -d /tmp/pgschema-792-full-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    cp "$REPO_ROOT/database/schema.sql" "$SCRATCH/schema.sql"

    # Detect shadowed relations.
    local SHADOWED_JSON SHADOWED_NAMES SHADOWED_RELKINDS SHADOWED_CSV
    SHADOWED_JSON=$("$VENV_PYTHON" "$DETECTOR" \
        --schema-file "$SCRATCH/schema.sql" \
        --dbname "$DB" 2>/dev/null) || SHADOWED_JSON=""
    SHADOWED_NAMES=()
    SHADOWED_RELKINDS=()
    while IFS= read -r line; do
        local name relkind
        name=$(printf '%s' "$line" | jq -r '.name // empty')
        relkind=$(printf '%s' "$line" | jq -r '.relkind // empty')
        if [ -n "$name" ]; then
            SHADOWED_NAMES+=("$name")
            SHADOWED_RELKINDS+=("$relkind")
        fi
    done <<< "$SHADOWED_JSON"

    local IGNORE_FILE
    if [ "$PEER_MODE" -eq 1 ] && [ "${#SHADOWED_NAMES[@]}" -gt 0 ]; then
        IGNORE_FILE="$REPO_ROOT/database/.pgschemaignore-peer"
    else
        IGNORE_FILE="$REPO_ROOT/database/.pgschemaignore"
    fi
    cp "$IGNORE_FILE" "$SCRATCH/.pgschemaignore"

    if [ "$PEER_MODE" -eq 1 ] && [ "${#SHADOWED_NAMES[@]}" -gt 0 ]; then
        local names_csv relkinds_csv
        names_csv=$(IFS=,; echo "${SHADOWED_NAMES[*]}")
        relkinds_csv=$(IFS=,; echo "${SHADOWED_RELKINDS[*]}")
        "$VENV_PYTHON" "$INJECTOR" \
            --ignore-file "$SCRATCH/.pgschemaignore" \
            --names "$names_csv" \
            --relkinds "$relkinds_csv" >/dev/null 2>&1 || {
                rm -rf "$SCRATCH"
                return 1
            }
    fi

    # Plan.  Use the target DB as the plan DB (matches agent-install.sh).
    # Using nova_memory here produced a source_fingerprint mismatch on the
    # apply step whenever the scratch DB contained drift-seeded objects that
    # survived stripping.
    (
        cd "$SCRATCH" || exit 1
        pgschema plan \
            --host /var/run/postgresql \
            --user nova \
            --db "$DB" \
            --schema public \
            --file schema.sql \
            --plan-host /var/run/postgresql \
            --plan-db "$DB" \
            --plan-user nova \
            --output-json "$PLAN" \
            --no-color >/dev/null 2>&1
    ) || {
        rm -rf "$SCRATCH"
        return 1
    }

    # Reorder.
    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1 || {
        rm -rf "$SCRATCH"
        return 1
    }

    # Strip.
    local STRIP_ARGS=(
        --plan "$REORDERED"
        --output "$FILTERED"
        --db-user nova
        --dbname "$DB"
        --host /var/run/postgresql
        --port 5432
    )
    if [ "$PEER_MODE" -eq 1 ] && [ "${#SHADOWED_NAMES[@]}" -gt 0 ]; then
        SHADOWED_CSV=$(IFS=,; echo "${SHADOWED_NAMES[*]}")
        STRIP_ARGS+=(--ignore-objects "$SHADOWED_CSV" --log-exclusions)
    fi

    "$VENV_PYTHON" "$STRIPPER" "${STRIP_ARGS[@]}" 2>"$STRIP_LOG"
    local strip_status=$?
    if [ $strip_status -ne 0 ]; then
        rm -rf "$SCRATCH"
        return $strip_status
    fi

    if [ -n "$FILTERED_OUT" ]; then
        cp "$FILTERED" "$FILTERED_OUT"
    fi

    # Fail-closed superuser/ownership gate, exactly as agent-install.sh does.
    if ! "$VENV_PYTHON" "$CHECK_SUPERUSER" \
            --plan "$FILTERED" \
            --host /var/run/postgresql \
            --port 5432 \
            --dbname "$DB" \
            --db-user nova >/dev/null 2>&1; then
        rm -rf "$SCRATCH"
        return 1
    fi

    # Apply only if there are non-privilege steps.  When all steps were
    # stripped (e.g. the only drift is ignored peer/Victoria objects), the
    # filtered plan is empty and pgschema apply would fail with a source
    # fingerprint mismatch because the DB still contains those ignored
    # objects.  agent-install.sh makes the same skip-when-empty decision.
    local total_steps
    total_steps=$(jq '[(.groups // [])[] | .steps[] | select(.type != "privilege")] | length' "$FILTERED" 2>/dev/null || echo 0)
    if [ "$total_steps" -gt 0 ]; then
        pgschema apply \
            --host /var/run/postgresql \
            --user nova \
            --db "$DB" \
            --schema public \
            --plan "$FILTERED" \
            --auto-approve \
            --no-color >/dev/null 2>&1
        local apply_status=$?
        rm -rf "$SCRATCH"
        return $apply_status
    fi

    rm -rf "$SCRATCH"
    return 0
}

# Build fixture SQL.  Primary path: a shared schema-only dump of Victoria's
# trading objects.  The dump is supplied out-of-band because nova has no
# SELECT privilege on victoria_memory's trading tables, so pg_dump cannot be
# run directly against that DB.  We still probe victoria_memory via pg_class
# (which is visibility-agnostic) to confirm the tables exist there, but we
# never read their DDL from the live DB.
#
# Why the helper previously printed "file absent": the shared dump is owned
# by graybeard:agents with mode 640.  Nova is in the agents group, but a
# shell started before that group membership became effective can see the
# file via stat (so -s/-f succeed) yet cannot read it (so grep/cat fail).
# Using -r (readable) catches the real condition instead of relying on size.
#
# Args: OUT_FILE
# Returns 0 if the shared dump was used, 1 if fallback was used.
_build_victoria_fixture_sql() {
    local OUT="$1"
    local SHARED_DUMP="/opt/agents/shared-diagnostics/victoria-trading-schema.sql"

    # Probe victoria_memory with pg_class, not information_schema, because
    # information_schema hides tables the current role has no privileges on.
    local found
    found=$(PGDATABASE=victoria_memory psql -U nova -h /var/run/postgresql -tAc "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN ($(printf "'%s'," "${VICTORIA_TRADING_TABLES[@]}" | sed 's/,$//'));")
    echo "TC-792-024: pg_class probe found $found victoria_memory trading table(s)" >&3

    local used_real=1
    if [ -r "$SHARED_DUMP" ] && [ -s "$SHARED_DUMP" ] && grep -q 'CREATE TABLE' "$SHARED_DUMP"; then
        cat "$SHARED_DUMP" > "$OUT"
        # The dump preserves the original owner role (victoria).  Nova is not
        # a member of that role here, so the OWNER TO clauses would fail to
        # load.  Strip them from the scratch copy only; the shared file is
        # left untouched.
        sed -i -E '/^ALTER (TABLE|SEQUENCE|FUNCTION|TRIGGER|PROCEDURE|ROUTINE|DOMAIN|TYPE|SCHEMA|DATABASE|LARGE OBJECT) .* OWNER TO /d' "$OUT"
        echo "TC-792-024: using shared schema dump $SHARED_DUMP" >&3
    else
        {
            echo "-- FALLBACK: hand-built fixture (real schema dump not available)"
            _victoria_trading_ddl
        } > "$OUT"
        echo "FALLBACK: hand-built fixture (real schema dump not available)" >&3
        used_real=0
    fi

    # The shared dump currently ships the four trigger definitions but not the
    # trigger functions they call.  Create minimal stub functions so the fixture
    # loads; never modify the shared file itself.
    if [ "$used_real" -eq 1 ]; then
        local missing=()
        for fn in open_orders_touch victoria_order_adjustments_immutable victoria_trades_immutable assert_cash_ledger_balance_chain; do
            if ! grep -qE "CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+.*\b${fn}\s*\(" "$OUT"; then
                missing+=("$fn")
            fi
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            local stubs
            stubs=$(mktemp)
            {
                echo "-- STUBBED trigger functions (shared dump is missing the bodies):"
                for fn in "${missing[@]}"; do
                    echo "CREATE OR REPLACE FUNCTION public.${fn}() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RETURN COALESCE(NEW, OLD); END; \$\$;"
                done
                echo ""
                cat "$OUT"
            } > "$stubs"
            mv "$stubs" "$OUT"
            echo "STUBBED trigger functions: ${missing[*]}" >&3
        fi
        return 0
    fi
    return 1
}

# Assert that a filtered plan contains zero steps referencing Victoria trading
# tables (excluding any *_local variants).
_assert_no_victoria_refs() {
    local FILTERED="$1"
    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
violations = []
names = [re.escape(n) for n in ['portfolios','instruments','positions','trades','cash_ledger']]
pat = re.compile(r'(?<!\w)(' + '|'.join(names) + r')(?!\w)')
for s in steps:
    path = s.get('path', '')
    if pat.search(path) and '_local' not in path:
        violations.append(path)
print('\n'.join(violations))
PY
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "TC-792-020: Victoria-shaped peer DB full apply succeeds with zero row loss" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    FILTERED=$(mktemp)
    BEFORE=$(mktemp)
    AFTER=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1
    _seed_victoria_trading_fixture "$DB"
    _seed_victoria_trading_rows "$DB"

    _capture_victoria_row_counts "$DB" "$BEFORE"

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG" "$FILTERED"
    [ "$status" -eq 0 ]

    _capture_victoria_row_counts "$DB" "$AFTER"
    diff "$BEFORE" "$AFTER"

    _assert_no_bootstrap_refs "$FILTERED"

    rm -f "$STRIP_LOG" "$FILTERED" "$BEFORE" "$AFTER"
    _drop_test_db "$DB"
}

@test "TC-792-021: Victoria-shaped standalone DB full apply succeeds with zero row loss" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    BEFORE=$(mktemp)
    AFTER=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _seed_victoria_trading_fixture "$DB"
    _seed_victoria_trading_rows "$DB"

    _capture_victoria_row_counts "$DB" "$BEFORE"

    run _run_full_installer_pipeline "$DB" 0 "$STRIP_LOG"
    [ "$status" -eq 0 ]

    _capture_victoria_row_counts "$DB" "$AFTER"
    diff "$BEFORE" "$AFTER"

    rm -f "$STRIP_LOG" "$BEFORE" "$AFTER"
    _drop_test_db "$DB"
}

@test "TC-792-022: INTENT-level object inventory is unchanged after peer apply" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    BEFORE=$(mktemp)
    AFTER=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1
    _seed_victoria_trading_fixture "$DB"
    _seed_victoria_trading_rows "$DB"

    _capture_victoria_object_inventory "$DB" "$BEFORE"

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG"
    [ "$status" -eq 0 ]

    _capture_victoria_object_inventory "$DB" "$AFTER"
    diff "$BEFORE" "$AFTER"

    rm -f "$STRIP_LOG" "$BEFORE" "$AFTER"
    _drop_test_db "$DB"
}

@test "TC-792-023: peer install with zero rows leaves row counts at zero" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    BEFORE=$(mktemp)
    AFTER=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1
    _seed_victoria_trading_fixture "$DB"
    # Deliberately do NOT seed rows.

    _capture_victoria_row_counts "$DB" "$BEFORE"

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG"
    [ "$status" -eq 0 ]

    _capture_victoria_row_counts "$DB" "$AFTER"
    diff "$BEFORE" "$AFTER"

    rm -f "$STRIP_LOG" "$BEFORE" "$AFTER"
    _drop_test_db "$DB"
}

@test "TC-792-024: fixture from real schema-only dump or hand-built fallback applies cleanly" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    BEFORE=$(mktemp)
    AFTER=$(mktemp)
    FIXTURE=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1

    if _build_victoria_fixture_sql "$FIXTURE"; then
        echo "TC-792-024: using real schema-only dump from victoria_memory" >&3
    else
        echo "FALLBACK: hand-built fixture" >&3
    fi

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -f "$FIXTURE" >/dev/null
    _seed_victoria_trading_rows "$DB"

    _capture_victoria_row_counts "$DB" "$BEFORE"

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG"
    [ "$status" -eq 0 ]

    _capture_victoria_row_counts "$DB" "$AFTER"
    diff "$BEFORE" "$AFTER"

    rm -f "$STRIP_LOG" "$BEFORE" "$AFTER" "$FIXTURE"
    _drop_test_db "$DB"
}

@test "TC-792-025: Victoria tables owned by a second role are excluded via nonowned gate" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    # Use the pre-provisioned victoria_app_test role if nova can SET ROLE to
    # it.  Never CREATE ROLE here; if the role is absent or unusable, skip.
    local owner_role="victoria_app_test"
    local role_exists can_set_role
    role_exists=$(psql -U nova -d postgres -tAc "SELECT COUNT(*) FROM pg_roles WHERE rolname='$owner_role';")
    if [ "$role_exists" -eq 0 ]; then
        skip "role $owner_role does not exist (Graybeard provisions it)"
    fi
    can_set_role=$(psql -U nova -d postgres -tAc "SELECT CASE WHEN pg_has_role(CURRENT_USER, '$owner_role', 'MEMBER') THEN 1 ELSE 0 END;")
    if [ "$can_set_role" -ne 1 ]; then
        skip "nova cannot SET ROLE to $owner_role"
    fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    BEFORE=$(mktemp)
    AFTER=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1
    _seed_victoria_trading_fixture "$DB" "$owner_role"
    _seed_victoria_trading_rows "$DB"

    _capture_victoria_row_counts "$DB" "$BEFORE"

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG"
    [ "$status" -eq 0 ]

    _capture_victoria_row_counts "$DB" "$AFTER"
    diff "$BEFORE" "$AFTER"

    # Assert that the ownership gate (not just the universal drop-strip) did
    # real work on the newly-un-ignored Victoria objects.
    run grep -E "SKIPPED:.*owner=$owner_role" "$STRIP_LOG"
    [ "$status" -eq 0 ]
    [ -n "$output" ]

    rm -f "$STRIP_LOG" "$BEFORE" "$AFTER"
    _drop_test_db "$DB"
}

@test "TC-792-080: dependent objects of Victoria tables survive and stay functional" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    FILTERED=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1
    _seed_victoria_trading_fixture "$DB"
    _seed_victoria_trading_rows "$DB"

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG" "$FILTERED"
    [ "$status" -eq 0 ]

    # The filtered plan must contain no steps referencing Victoria tables.
    _assert_no_victoria_refs "$FILTERED"

    # Index still exists and is usable.
    local idx_used
    idx_used=$(psql -U nova -d "$DB" -tAc "EXPLAIN (COSTS OFF) SELECT * FROM trades WHERE position_id = 1;")
    echo "$idx_used" | grep -q 'idx_trades_position'

    # FK still enforced: invalid position_id must be rejected.
    run psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -c "INSERT INTO trades (position_id, side, qty, price) VALUES (-1, 'buy', 1, 100);"
    [ "$status" -ne 0 ]

    # Trigger still fires on UPDATE.
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -c "UPDATE portfolios SET name = name WHERE id = 1;" >/dev/null
    local trigger_fired
    trigger_fired=$(psql -U nova -d "$DB" -tAc "SELECT count(*) FROM portfolios WHERE id = 1 AND created_at IS NOT NULL;")
    [ "$trigger_fired" -eq 1 ]

    rm -f "$STRIP_LOG" "$FILTERED"
    _drop_test_db "$DB"
}


# --- CHUNK 4: RECORD-ONLY live characterizations + GATING #686 guard ---

# Run pgschema plan against a throwaway schema.sql in a scratch directory.
# Args: DB_NAME SCRATCH_DIR SCHEMA_SQL_FILE PLAN_OUT
_pgschema_plan_to_file() {
    local DB="$1"
    local SCRATCH="$2"
    local SCHEMA="$3"
    local OUT="$4"

    # Copy only if the source is not already the scratch target; avoids a
    # noisy but harmless 'cp: same file' warning when tests build schema.sql
    # directly inside the scratch directory.
    if [ "$(realpath -m "$SCHEMA")" != "$(realpath -m "$SCRATCH/schema.sql")" ]; then
        cp "$SCHEMA" "$SCRATCH/schema.sql"
    fi
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
            --output-json "$OUT" \
            --no-color >/dev/null 2>&1
    )
}

@test "TC-792-050: malformed TOML ignore file behavior (RECORD-ONLY)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-050-XXXXXX)
    PLAN="$SCRATCH/plan.json"

    # Deliberately malformed: unterminated string in [tables] array.
    cat > "$SCRATCH/.pgschemaignore" <<'EOF'
[tables]
patterns = [
  "definitely_not_a_real_table_xyz
]
EOF
    cat > "$SCRATCH/schema.sql" <<'EOF'
CREATE TABLE t792_050 (id serial PRIMARY KEY);
EOF

    run _pgschema_plan_to_file "$DB" "$SCRATCH" "$SCRATCH/schema.sql" "$PLAN"
    local plan_status=$status

    if [ "$plan_status" -eq 0 ]; then
        echo "RECORD-ONLY TC-792-050: pgschema silently ignored malformed TOML (fail-open)" >&3
    else
        echo "RECORD-ONLY TC-792-050: pgschema failed fast on malformed TOML (exit $plan_status)" >&3
        echo "$output" >&3
    fi

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}

@test "TC-792-053: local table collides with schema.sql table (RECORD-ONLY)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-053-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    # Pick a real schema.sql table.  Create a local ordinary table with the
    # same name but missing one schema.sql column and carrying an extra local
    # column not present in schema.sql.
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
DROP TABLE IF EXISTS d100_roll_log;
CREATE TABLE d100_roll_log (
    id serial PRIMARY KEY,
    roll integer NOT NULL,
    extra_local_col text NOT NULL DEFAULT 'local'
);
INSERT INTO d100_roll_log (roll, extra_local_col) VALUES (42, 'keep-me');
SQL

    cp "$REPO_ROOT/database/schema.sql" "$SCRATCH/schema.sql"
    cp "$REPO_ROOT/database/.pgschemaignore" "$SCRATCH/.pgschemaignore"

    _pgschema_plan_to_file "$DB" "$SCRATCH" "$REPO_ROOT/database/schema.sql" "$PLAN"
    [ $? -eq 0 ]

    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1
    "$VENV_PYTHON" "$STRIPPER" --plan "$REORDERED" --output "$FILTERED" >/dev/null 2>&1

    # Record findings.
    run "$VENV_PYTHON" - <<PY
import json
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
for s in steps:
    if 'd100_roll_log' in s.get('path', ''):
        print(s.get('operation'), s.get('type'), s.get('path'))
PY
    echo "RECORD-ONLY TC-792-053: filtered d100_roll_log steps:" >&3
    echo "$output" >&3

    # Apply and record whether extra_local_col survived (drop-stripped).
    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$FILTERED" \
        --auto-approve \
        --no-color
    local apply_status=$status
    echo "RECORD-ONLY TC-792-053: apply exit status=$apply_status" >&3

    local extra_col_exists
    extra_col_exists=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='d100_roll_log' AND column_name='extra_local_col';")
    echo "RECORD-ONLY TC-792-053: extra_local_col present after apply=$extra_col_exists" >&3

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}

@test "TC-792-060: column type narrowing planned as alter, not stripped (RECORD-ONLY)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-060-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE t792_060 (id serial PRIMARY KEY, code text);
INSERT INTO t792_060 (code) VALUES ('AB'), ('CD');
SQL

    cat > "$SCRATCH/schema.sql" <<'EOF'
CREATE TABLE t792_060 (id serial PRIMARY KEY, code varchar(1));
EOF
    cat > "$SCRATCH/.pgschemaignore" <<'EOF'
[tables]
patterns = []
EOF

    _pgschema_plan_to_file "$DB" "$SCRATCH" "$SCRATCH/schema.sql" "$PLAN"
    [ $? -eq 0 ]

    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1
    "$VENV_PYTHON" "$STRIPPER" --plan "$REORDERED" --output "$FILTERED" >/dev/null 2>&1

    run "$VENV_PYTHON" - <<PY
import json
with open('$PLAN') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
for s in steps:
    if 't792_060.code' in s.get('path', ''):
        print('RAW', s.get('operation'), s.get('type'))
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
for s in steps:
    if 't792_060.code' in s.get('path', ''):
        print('FILTERED', s.get('operation'), s.get('type'))
PY
    echo "RECORD-ONLY TC-792-060: $output" >&3

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}

@test "TC-792-061: SET NOT NULL on column with existing NULLs (RECORD-ONLY)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-061-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE t792_061 (id serial PRIMARY KEY, label text);
INSERT INTO t792_061 (label) VALUES ('x'), (NULL);
SQL

    cat > "$SCRATCH/schema.sql" <<'EOF'
CREATE TABLE t792_061 (id serial PRIMARY KEY, label text NOT NULL);
EOF
    cat > "$SCRATCH/.pgschemaignore" <<'EOF'
[tables]
patterns = []
EOF

    _pgschema_plan_to_file "$DB" "$SCRATCH" "$SCRATCH/schema.sql" "$PLAN"
    [ $? -eq 0 ]

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
    echo "RECORD-ONLY TC-792-061: apply exit status=$status" >&3
    echo "$output" >&3

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}

@test "TC-792-062: column type narrowing silently loses precision (RECORD-ONLY)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-062-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE t792_062 (id serial PRIMARY KEY, amt numeric(10,4));
INSERT INTO t792_062 (amt) VALUES (123.4567);
SQL

    cat > "$SCRATCH/schema.sql" <<'EOF'
CREATE TABLE t792_062 (id serial PRIMARY KEY, amt numeric(10,2));
EOF
    cat > "$SCRATCH/.pgschemaignore" <<'EOF'
[tables]
patterns = []
EOF

    _pgschema_plan_to_file "$DB" "$SCRATCH" "$SCRATCH/schema.sql" "$PLAN"
    [ $? -eq 0 ]

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
    echo "RECORD-ONLY TC-792-062: apply exit status=$status" >&3

    local final_value
    final_value=$(psql -U nova -d "$DB" -tAc "SELECT amt::text FROM t792_062 WHERE id=1;")
    echo "RECORD-ONLY TC-792-062: final amt value=$final_value" >&3

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}

@test "TC-792-070: unguarded #686 phantom CHECK drop+recreate (RECORD-ONLY)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-070-XXXXXX)
    PLAN="$SCRATCH/plan.json"
    REORDERED="$SCRATCH/reordered.json"
    FILTERED="$SCRATCH/filtered.json"

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE t792_070 (id serial PRIMARY KEY, status text);
ALTER TABLE t792_070 ADD CONSTRAINT t792_070_status_check CHECK (status::text = ANY (ARRAY['a','b','c']::text[]));
SQL

    cat > "$SCRATCH/schema.sql" <<'EOF'
CREATE TABLE t792_070 (
    id serial PRIMARY KEY,
    status text,
    CONSTRAINT t792_070_status_check CHECK (status::text IN ('a','b','c'))
);
EOF
    cat > "$SCRATCH/.pgschemaignore" <<'EOF'
[tables]
patterns = []
EOF

    _pgschema_plan_to_file "$DB" "$SCRATCH" "$SCRATCH/schema.sql" "$PLAN"
    [ $? -eq 0 ]

    # Confirm phantom diff exists in raw plan.
    run "$VENV_PYTHON" - <<PY
import json
with open('$PLAN') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
drop_steps = [s for s in steps if s.get('path') == 'public.t792_070.t792_070_status_check' and s.get('operation') == 'drop']
create_steps = [s for s in steps if s.get('path') == 'public.t792_070.t792_070_status_check' and s.get('operation') == 'create']
print(f"drop_steps={len(drop_steps)} create_steps={len(create_steps)}")
PY
    echo "RECORD-ONLY TC-792-070: raw plan $output" >&3

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
    echo "RECORD-ONLY TC-792-070: apply exit status=$status" >&3
    echo "$output" >&3

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}

@test "TC-792-071: #686 collision does not newly expose Victoria tables (GATING)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    STRIP_LOG=$(mktemp)
    FILTERED=$(mktemp)

    run _apply_schema_sql_to_db "$DB"
    [ "$status" -eq 0 ]

    _skip_unless_fdw "$DB"
    psql -U nova -d "$DB" -c "DROP TABLE IF EXISTS agent_bootstrap_context;" >/dev/null 2>&1
    _seed_peer_fixture "$DB" 1 1
    _seed_victoria_trading_fixture "$DB"
    _seed_victoria_trading_rows "$DB"

    # Add a CHECK constraint in Postgres-canonical = ANY(ARRAY[]) form on a
    # Victoria table.  Because the table is not declared by schema.sql, the
    # only pgschema step for it should be a DROP TABLE (universally stripped),
    # not a constraint-level alter/drop/create that could hit the #686 mode.
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
ALTER TABLE trades ADD CONSTRAINT trades_side_check CHECK (side::text = ANY (ARRAY['buy','sell']::text[]));
SQL

    run _run_full_installer_pipeline "$DB" 1 "$STRIP_LOG" "$FILTERED"
    [ "$status" -eq 0 ]

    # The filtered plan must have zero constraint/index/trigger-level steps
    # touching trades (or any other Victoria table).
    _assert_no_victoria_refs "$FILTERED"

    rm -f "$STRIP_LOG" "$FILTERED"
    _drop_test_db "$DB"
}

# --- CHUNK 5: adversarial live seams + regression gate ---

@test "TC-792-052: ignore pattern matching nothing is harmless (GATING)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCRATCH=$(mktemp -d /tmp/pgschema-792-052-XXXXXX)
    PLAN="$SCRATCH/plan.json"

    cat > "$SCRATCH/.pgschemaignore" <<'EOF'
[tables]
patterns = ["definitely_not_a_real_table_xyz"]
EOF
    cat > "$SCRATCH/schema.sql" <<'EOF'
CREATE TABLE t792_052 (id serial PRIMARY KEY);
EOF

    run _pgschema_plan_to_file "$DB" "$SCRATCH" "$SCRATCH/schema.sql" "$PLAN"
    [ "$status" -eq 0 ]

    run "$VENV_PYTHON" - <<PY
import json
with open('$PLAN') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
print(len(steps))
PY
    [ "$status" -eq 0 ]
    # The single create step for t792_052 should still be present.
    [ "$output" -eq 1 ]

    rm -rf "$SCRATCH"
    _drop_test_db "$DB"
}
