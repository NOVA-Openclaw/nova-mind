#!/usr/bin/env bats
# Tests for nova-mind#608 / #1231: peer-shadowed relations (VIEWs and FOREIGN
# TABLEs that schema.sql declares as TABLEs) must be left alone during schema
# apply, while nova_memory continues to manage the real tables.
#
# Verifies the installer's dynamic peer-detection (database/detect_peer_shadowed.py)
# + peer-only .pgschemaignore + --ignore-objects filter pipeline.

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
    local dbname="nova_mind_608_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

# Run the installer's plan-filter pipeline against a fixture database.
# Uses dynamic peer-shadowed detection (#1231): queries the fixture DB for
# public f/v relations matching schema.sql tables and feeds them to the
# post-plan strip filter.  In "peer" mode the static .pgschemaignore-peer is
# used as a base and the detected names are injected into [tables]/[views].
# Args: DB_NAME PEER_MODE(0|1)
_run_installer_filter_pipeline() {
    local DB="$1"
    local PEER_MODE="$2"
    local PLAN="$3"
    local FILTERED="$4"

    local SCRATCH IGNORE_FILE OBJ_FILTER
    SCRATCH=$(mktemp -d /tmp/pgschema-608-XXXXXX)

    cp "$REPO_ROOT/database/schema.sql" "$SCRATCH/schema.sql"

    # Detect shadowed relations dynamically, exactly as the installer does.
    local SHADOWED_JSON SHADOWED_NAMES SHADOWED_RELKINDS SHADOWED_CSV
    SHADOWED_JSON=$("$VENV_PYTHON" "$REPO_ROOT/database/detect_peer_shadowed.py" \
        --schema-file "$SCRATCH/schema.sql" \
        --dsn "host=/var/run/postgresql dbname=$DB user=nova" 2>/dev/null) || SHADOWED_JSON=""
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

    if [ "$PEER_MODE" -eq 1 ] && [ "${#SHADOWED_NAMES[@]}" -gt 0 ]; then
        IGNORE_FILE="$REPO_ROOT/database/.pgschemaignore-peer"
        SHADOWED_CSV=$(IFS=,; echo "${SHADOWED_NAMES[*]}")
        OBJ_FILTER="--ignore-objects $SHADOWED_CSV --log-exclusions"
    else
        IGNORE_FILE="$REPO_ROOT/database/.pgschemaignore"
        OBJ_FILTER=""
    fi
    cp "$IGNORE_FILE" "$SCRATCH/.pgschemaignore"

    # Inject detected names into the scratch ignore file, mirroring the
    # installer's Python helper.
    if [ "$PEER_MODE" -eq 1 ] && [ "${#SHADOWED_NAMES[@]}" -gt 0 ]; then
        local names_csv relkinds_csv
        names_csv=$(IFS=,; echo "${SHADOWED_NAMES[*]}")
        relkinds_csv=$(IFS=,; echo "${SHADOWED_RELKINDS[*]}")
        "$VENV_PYTHON" "$REPO_ROOT/database/inject_peer_shadowed_ignores.py" \
            --ignore-file "$SCRATCH/.pgschemaignore" \
            --names "$names_csv" \
            --relkinds "$relkinds_csv"
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
            --output-json "$PLAN" \
            --no-color >/dev/null 2>&1
    )

    # shellcheck disable=SC2086
    run "$VENV_PYTHON" "$STRIPPER" --plan "$PLAN" --output "$FILTERED" $OBJ_FILTER
    rm -rf "$SCRATCH"
}

# Helper: seed a peer fixture. Args: DB_NAME HAS_FUNCTIONS(0|1) HAS_TRIGGERS(0|1)
_seed_peer_fixture() {
    local DB="$1"
    local HAS_FUNCTIONS="$2"
    local HAS_TRIGGERS="$3"
    local FIXTURE
    FIXTURE=$(mktemp)

    cat > "$FIXTURE" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DO $$
BEGIN
    EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L)', 'localhost', current_database());
END $$;
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

_assert_no_fdw_ops() {
    local FILTERED="$1"
    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
violations = []
for s in steps:
    sql = s.get('sql', '').upper()
    path = s.get('path', '')
    if re.search(r'CREATE\s+TABLE\s+AGENT_BOOTSTRAP_CONTEXT', sql):
        violations.append('CREATE TABLE agent_bootstrap_context')
    if s.get('type') == 'table.trigger' and 'agent_bootstrap_context' in path:
        violations.append('table.trigger on agent_bootstrap_context: ' + path)
    if s.get('operation') == 'drop' and (
        path == 'public.agent_bootstrap_context' or
        path == 'public.nova_bootstrap_context' or
        path.startswith('public.bootstrap_context_view_')
    ):
        violations.append('DROP FDW object: ' + path)
print('\n'.join(violations))
PY
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Assert that no step (of any type) references agent_bootstrap_context excluding
# the _local table, nor agent_bootstrap_context_id_seq.
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

@test "TC-608a-newhart: plain peer VIEW (no functions/triggers) excludes FDW ops" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)
    _seed_peer_fixture "$DB" 0 0
    _run_installer_filter_pipeline "$DB" 1 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]
    _assert_no_fdw_ops "$FILTERED"
    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-608a-graybeard: peer VIEW with bootstrap_context_view_* functions (no triggers) excludes FDW ops" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)
    _seed_peer_fixture "$DB" 1 0
    _run_installer_filter_pipeline "$DB" 1 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]
    _assert_no_fdw_ops "$FILTERED"
    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-608a-victoria: peer VIEW with INSTEAD OF triggers + functions excludes FDW ops" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)
    _seed_peer_fixture "$DB" 1 1
    _run_installer_filter_pipeline "$DB" 1 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]
    _assert_no_fdw_ops "$FILTERED"
    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-608b: canonical TABLE shape still manages agent_bootstrap_context" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)

    # Seed the canonical table shape, but drift it so pgschema plans a change.
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE agent_bootstrap_context (
    id serial PRIMARY KEY,
    context_type text NOT NULL,
    file_key text NOT NULL,
    content text NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    updated_by text DEFAULT CURRENT_USER,
    agent_name text,
    domain_names text[]
);
-- Drift: missing the expected check constraint by inserting a bad row is not
-- possible with a check, so instead drop the unique index schema.sql expects.
SQL

    _run_installer_filter_pipeline "$DB" 0 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]

    # The table must still be managed: at minimum there should be an index or
    # constraint step touching agent_bootstrap_context, and no exclusion of the
    # table itself from the plan.
    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
touching = [s for s in steps if 'agent_bootstrap_context' in s.get('path', '') and s.get('type') != 'privilege']
print(len(touching))
for s in touching[:5]:
    print(s.get('type'), s.get('operation'), s.get('path'))
PY
    [ "$status" -eq 0 ]
    [ "$output" != "0" ]

    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-608c: mutation - removing peer ignore entries exposes FDW objects" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)

    # Peer fixture (victoria shape: functions + INSTEAD OF triggers).
    _seed_peer_fixture "$DB" 1 1

    # Use the base ignore file (no peer patterns) and no trigger filter.
    SCRATCH=$(mktemp -d /tmp/pgschema-608-mut-XXXXXX)
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
    run "$VENV_PYTHON" "$STRIPPER" --plan "$PLAN" --output "$FILTERED"
    rm -rf "$SCRATCH"
    [ "$status" -eq 0 ]

    # With the peer patterns removed, the plan must contain at least one
    # offending operation (CREATE TABLE on the view or a trigger on it).
    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
violations = []
for s in steps:
    sql = s.get('sql', '').upper()
    path = s.get('path', '')
    if re.search(r'CREATE\s+TABLE\s+AGENT_BOOTSTRAP_CONTEXT', sql):
        violations.append('CREATE TABLE agent_bootstrap_context')
    if s.get('type') == 'table.trigger' and 'agent_bootstrap_context' in path:
        violations.append('table.trigger on agent_bootstrap_context: ' + path)
print('\n'.join(violations))
PY
    [ "$status" -eq 0 ]
    [ -n "$output" ]

    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

# Seed a foreign-table-shaped peer fixture for a schema.sql table (ai_models).
# This reproduces the nova-mind#1231 failure mode where ai_models is a FOREIGN
# TABLE on the peer and schema.sql declares it as a TABLE.
_seed_foreign_table_fixture() {
    local DB="$1"
    local FIXTURE
    FIXTURE=$(mktemp)

    cat > "$FIXTURE" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname = 'loopback') THEN
        EXECUTE format('CREATE SERVER loopback FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, dbname %L)', 'localhost', current_database());
    END IF;
END $$;
CREATE TABLE ai_models_local (
    id serial PRIMARY KEY,
    provider text NOT NULL,
    model text NOT NULL,
    input_price_per_mtok numeric,
    output_price_per_mtok numeric,
    description text,
    supports_vision boolean DEFAULT false,
    supports_reasoning boolean DEFAULT false,
    context_window integer,
    updated_at timestamptz DEFAULT now()
);
CREATE FOREIGN TABLE ai_models (
    id int,
    provider text,
    model text,
    input_price_per_mtok numeric,
    output_price_per_mtok numeric,
    description text,
    supports_vision boolean,
    supports_reasoning boolean,
    context_window integer,
    updated_at timestamptz
) SERVER loopback OPTIONS (schema_name 'public', table_name 'ai_models_local');
SQL

    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 -f "$FIXTURE" >/dev/null
    rm -f "$FIXTURE"
}

# Assert that no step references NAME as a whole path component, excluding
# any *_local variant.  Reusable for both VIEW and FOREIGN TABLE shadows.
_assert_no_shadow_refs() {
    local FILTERED="$1"
    local NAME="$2"
    run "$VENV_PYTHON" -c "
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
violations = []
for s in steps:
    path = s.get('path', '')
    if re.search(r'(?<!\w)' + re.escape('$NAME') + r'(?!\w)', path) and '_local' not in path:
        violations.append(path)
print('\n'.join(violations))
"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "TC-1231a: peer FOREIGN TABLE (ai_models) is excluded from plan" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)
    _seed_foreign_table_fixture "$DB"
    _run_installer_filter_pipeline "$DB" 1 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]
    _assert_no_shadow_refs "$FILTERED" "ai_models"
    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-1231b: peer VIEW + FOREIGN TABLE together are both excluded from plan" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)
    # Both the bootstrap view stack and the ai_models foreign table.
    _seed_peer_fixture "$DB" 0 0
    _seed_foreign_table_fixture "$DB"
    _run_installer_filter_pipeline "$DB" 1 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]
    _assert_no_fdw_ops "$FILTERED"
    _assert_no_shadow_refs "$FILTERED" "agent_bootstrap_context"
    _assert_no_shadow_refs "$FILTERED" "ai_models"
    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-1231c: mutation - disabling dynamic detection exposes foreign-table ops" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)
    _seed_foreign_table_fixture "$DB"

    # Plan with the base ignore file and no dynamic object filter.
    SCRATCH=$(mktemp -d /tmp/pgschema-1231-mut-XXXXXX)
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
    run "$VENV_PYTHON" "$STRIPPER" --plan "$PLAN" --output "$FILTERED"
    rm -rf "$SCRATCH"
    [ "$status" -eq 0 ]

    # Without dynamic exclusion there must be at least one offending step
    # referencing ai_models (CREATE TABLE, privilege, index, etc.).
    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
violations = []
for s in steps:
    sql = s.get('sql', '').upper()
    path = s.get('path', '')
    if re.search(r'(?<!\w)ai_models(?!\w)', path) and '_local' not in path:
        violations.append(path)
print('\n'.join(violations))
PY
    [ "$status" -eq 0 ]
    [ -n "$output" ]

    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}

@test "TC-608d: peer mode filtered plan contains zero agent_bootstrap_context refs (excluding _local) and zero id_seq refs" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)
    FILTERED=$(mktemp)

    # Peer fixture (victoria shape: functions + INSTEAD OF triggers).
    _seed_peer_fixture "$DB" 1 1

    # With the full peer pipeline there must be no references at all.
    _run_installer_filter_pipeline "$DB" 1 "$PLAN" "$FILTERED"
    [ "$status" -eq 0 ]
    _assert_no_bootstrap_refs "$FILTERED"

    # Mutation: use the base ignore file (no peer patterns) and drop the
    # post-plan object filter. The resulting plan must contain at least one
    # bootstrap-context or bootstrap-context_id_seq reference (otherwise the
    # test is not checking anything real).
    SCRATCH=$(mktemp -d /tmp/pgschema-608-mut2-XXXXXX)
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
    run "$VENV_PYTHON" "$STRIPPER" --plan "$PLAN" --output "$FILTERED"
    rm -rf "$SCRATCH"
    [ "$status" -eq 0 ]

    run "$VENV_PYTHON" - <<PY
import json, re
with open('$FILTERED') as f:
    p = json.load(f)
steps = [s for g in (p.get('groups') or []) for s in g.get('steps', [])]
refs = []
for s in steps:
    path = s.get('path', '')
    if re.search(r'(?<!\w)agent_bootstrap_context_id_seq(?!\w)', path):
        refs.append(path)
    elif re.search(r'(?<!\w)agent_bootstrap_context(?!\w)', path) and '_local' not in path:
        refs.append(path)
print(len(refs))
PY
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]

    rm -f "$PLAN" "$FILTERED"
    _drop_test_db "$DB"
}
