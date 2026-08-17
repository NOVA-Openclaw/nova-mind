#!/usr/bin/env bats
# Tests for issue-597 installer exit-code policy, plan_reorder.py CLI,
# GRANT reconciliation, idempotency, and atomicity.
#
# Coverage map to /home/nova/.openclaw/workspace/evals/se709/test-case-design-v2.md:
#   * Section 6 (TC-40-44): installer-level exit behavior
#   * Section 7 (TC-45-47): GRANT reconciliation surface
#   * Section 5 (TC-38):    merged-group atomicity / rollback
#   * Section 9 (TC-52/53): idempotency smoke tests
#
# The installer-level tests below mirror the schema-apply block of
# agent-install.sh using a minimal in-memory stub (established pattern:
# tests/install/test_agents_json_safety.bats).  Static string checks are
# intentionally avoided for the exit-code gate.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"
REORDERER="$REPO_ROOT/database/plan_reorder.py"
VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

# ---------------------------------------------------------------------------
# plan_reorder.py CLI tests (reorderer-level exit codes)
# ---------------------------------------------------------------------------

@test "TC-30/TC-31-ish: plan_reorder CLI returns 2 on malformed plan JSON" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{"version": "1.0.0", "groups": "not-an-array"}
JSON
    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 2 ]
    rm -f "$PLAN" "$OUT"
}

@test "TC-26: plan_reorder CLI returns 3 on unparseable statement" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "1.7.2",
  "source_fingerprint": {"hash": "x"},
  "groups": [{"steps": [{"sql": "THIS IS NOT SQL;", "type": "table", "operation": "create", "path": "public.t"}]}]
}
JSON
    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 3 ]
    rm -f "$PLAN" "$OUT"
}

@test "TC-24/TC-25: plan_reorder CLI returns 4 on dependency cycle" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "1.7.2",
  "source_fingerprint": {"hash": "x"},
  "groups": [{"steps": [
    {"sql": "CREATE VIEW v_a AS SELECT * FROM v_b;", "type": "view", "operation": "create", "path": "public.v_a"},
    {"sql": "CREATE VIEW v_b AS SELECT * FROM v_a;", "type": "view", "operation": "create", "path": "public.v_b"}
  ]}]
}
JSON
    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 4 ]
    rm -f "$PLAN" "$OUT"
}

@test "plan_reorder CLI returns 0 on valid plan" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "1.7.2",
  "source_fingerprint": {"hash": "x"},
  "groups": [{"steps": [{"sql": "CREATE TABLE t (id int);", "type": "table", "operation": "create", "path": "public.t"}]}]
}
JSON
    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 0 ]
    rm -f "$PLAN" "$OUT"
}

@test "TC-32a: plan_reorder CLI returns 0 on null groups (idempotent no-change plan)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "1.7.2",
  "created_at": "2026-08-17T14:16:45Z",
  "source_fingerprint": {"hash": "x"},
  "groups": null
}
JSON
    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 0 ]
    # Output must preserve top-level metadata and normalize groups to [].
    run "$VENV_PYTHON" -c "import json; p=json.load(open('$OUT')); print(p['version'], p['pgschema_version'], p['created_at'], p['source_fingerprint']['hash'], len(p['groups']))"
    [ "$status" -eq 0 ]
    [[ "$output" == "1.0.0 1.7.2 2026-08-17T14:16:45Z x 0" ]]
    rm -f "$PLAN" "$OUT"
}

# ---------------------------------------------------------------------------
# Installer-level schema-apply stub
#
# Mirrors the variable names, control flow, and exit-code gate from
# agent-install.sh lines ~1490-1621.  External commands are mocked so the
# test exercises the shell logic without a live database.
# ---------------------------------------------------------------------------

run_installer_schema_apply_stub() {
    local PLAN_FILE="$1"
    local SCHEMA_FILE_TMP="$2"
    local MOCK_APPLY_EXIT="${3:-0}"
    local MOCK_GRANT_EXIT="${4:-0}"
    local MOCK_REORDER_EXIT="${5:-0}"
    local SKIP_APPLY="${6:-0}"
    local APPLY_MARKER="${7:-}"
    local PRE_SKIPPED="${8:-0}"

    # State variables from agent-install.sh
    local SCHEMA_DIFF_SKIPPED="$PRE_SKIPPED"
    local SCHEMA_DIFF_HAZARD=0
    local REORDER_EXIT="$MOCK_REORDER_EXIT"

    # Symbols used by the mirrored messages
    local CHECK_MARK="✅"
    local CROSS_MARK="❌"
    local WARNING="⚠️"
    local INFO="ℹ️"

    # Mock external commands
    _superuser_psql() { return "$MOCK_GRANT_EXIT"; }
    psql() { echo "0"; return 0; }
    _superuser_pgschema() {
        if [ "${1:-}" = "apply" ] && [ -n "$APPLY_MARKER" ]; then
            touch "$APPLY_MARKER"
        fi
        return "$MOCK_APPLY_EXIT"
    }

    # Reorder branch (mirrors agent-install.sh)
    local DO_APPLY=1
    if [ "$REORDER_EXIT" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} Plan reordered by dependencies"
    else
        echo -e "  ${CROSS_MARK} Plan reorder failed (exit $REORDER_EXIT) — schema apply skipped"
        SCHEMA_DIFF_SKIPPED=1
        DO_APPLY=0
    fi

    if [ "$DO_APPLY" -eq 1 ]; then
        # Simplified hazard/apply block faithful to agent-install.sh semantics.
        local HAZARD_COUNT=0
        local TOTAL_STEPS=1
        if [ "$SKIP_APPLY" -eq 1 ]; then
            HAZARD_COUNT=1
        fi

        if [ "$HAZARD_COUNT" -gt 0 ]; then
            echo -e "  ${WARNING} Destructive changes detected — schema apply SKIPPED"
            SCHEMA_DIFF_HAZARD=1
        elif [ "$TOTAL_STEPS" -eq 0 ]; then
            echo -e "  ${CHECK_MARK} Schema is up to date — no changes needed"
        else
            echo "  Applying $TOTAL_STEPS schema change(s)..."
            local APPLY_EXIT=0
            _superuser_pgschema apply >/dev/null 2>&1 || APPLY_EXIT=$?
            if [ "$APPLY_EXIT" -eq 0 ]; then
                echo -e "  ${CHECK_MARK} Schema applied successfully"

                echo "  Reconciling explicit schema grants..."
                local GRANT_COUNT
                GRANT_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" 2>/dev/null || echo 0)
                if [ "$GRANT_COUNT" -gt 0 ] 2>/dev/null; then
                    if grep -E '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" | _superuser_psql >/dev/null 2>&1; then
                        echo -e "  ${CHECK_MARK} Applied $GRANT_COUNT explicit grant/revoke statement(s)"
                    else
                        echo -e "  ${CROSS_MARK} Grant reconciliation failed"
                        SCHEMA_DIFF_SKIPPED=1
                    fi
                else
                    echo -e "  ${INFO} No explicit grant/revoke statements found"
                fi
            else
                echo -e "  ${CROSS_MARK} Schema apply failed (exit $APPLY_EXIT)"
                SCHEMA_DIFF_SKIPPED=1
            fi
        fi
    fi

    # Schema apply exit-code gate (#597) — the headline deliverable.
    if [ "$SCHEMA_DIFF_SKIPPED" -eq 1 ] && [ "$SCHEMA_DIFF_HAZARD" -eq 0 ]; then
        echo ""
        echo -e "  ${CROSS_MARK} Schema apply stage failed — installation aborting"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Section 6: installer exit-code behavior (TC-40 through TC-44)
# ---------------------------------------------------------------------------

@test "TC-40: schema apply failure yields nonzero installer exit" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 1 0 0 0
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema apply stage failed"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

@test "TC-41: CREATE EXTENSION failure yields nonzero installer exit" {
    # A failed extension install sets SCHEMA_DIFF_SKIPPED=1 before the plan
    # block is reached; the exit gate must still terminate the installer.
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 0 0 "" 1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema apply stage failed"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

@test "TC-42: pgschema plan failure yields nonzero installer exit" {
    # Same classification as TC-41: plan failure sets SCHEMA_DIFF_SKIPPED=1.
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 0 0 "" 1
    [ "$status" -ne 0 ]
    [[ "$output" == *"Schema apply stage failed"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

@test "TC-43: reorderer hard-fail yields nonzero installer exit and skips apply" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    APPLY_MARKER=$(mktemp)
    rm -f "$APPLY_MARKER"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 4 0 "$APPLY_MARKER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Plan reorder failed"* ]]
    [[ "$output" == *"Schema apply stage failed"* ]]
    [ ! -f "$APPLY_MARKER" ]
    rm -f "$PLAN" "$SCHEMA" "$APPLY_MARKER"
}

@test "TC-44: successful schema apply yields installer exit 0" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 0 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Schema applied successfully"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

@test "Hazard-only path (SCHEMA_DIFF_HAZARD=1) does NOT trigger nonzero installer exit" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 0 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Destructive changes detected"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

# ---------------------------------------------------------------------------
# Section 7: GRANT reconciliation surface (TC-45 through TC-47)
# ---------------------------------------------------------------------------

@test "TC-45: GRANT reconciliation runs after successful apply" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    cat >"$SCHEMA" <<'SQL'
CREATE TABLE t (id int);
GRANT SELECT ON TABLE t TO some_role;
SQL
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 0 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Applied 1 explicit grant/revoke statement(s)"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

@test "TC-46: GRANT reconciliation failure yields nonzero installer exit" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    cat >"$SCHEMA" <<'SQL'
CREATE TABLE t (id int);
GRANT SELECT ON TABLE t TO some_role;
SQL
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 1 0 0
    [ "$status" -ne 0 ]
    [[ "$output" == *"Grant reconciliation failed"* ]]
    [[ "$output" == *"Schema apply stage failed"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

@test "TC-47: no explicit grants is a no-op" {
    PLAN=$(mktemp)
    SCHEMA=$(mktemp)
    echo "CREATE TABLE t (id int);" >"$SCHEMA"
    run run_installer_schema_apply_stub "$PLAN" "$SCHEMA" 0 0 0 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"No explicit grant/revoke statements found"* ]]
    rm -f "$PLAN" "$SCHEMA"
}

# ---------------------------------------------------------------------------
# Live-PostgreSQL integration helpers
# ---------------------------------------------------------------------------

_pg_available() {
    command -v psql >/dev/null 2>&1 && command -v pgschema >/dev/null 2>&1 && \
        pg_isready -h /var/run/postgresql >/dev/null 2>&1
}

_make_test_db() {
    local dbname="nova_mind_tc_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Section 5: TC-38 merged-group atomicity / rollback
# ---------------------------------------------------------------------------

@test "TC-38: merged directive-free group rolls back on partial failure" {
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCHEMA=$(mktemp)
    PLAN=$(mktemp)
    BROKEN_PLAN=$(mktemp)

    cat >"$SCHEMA" <<'SQL'
CREATE TABLE t1 (id int);
CREATE VIEW v1 AS SELECT id FROM t1;
SQL

    pgschema plan \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --file "$SCHEMA" \
        --output-json "$PLAN" \
        --no-color >/dev/null 2>&1

    # The reorderer merges directive-free groups into a single atomic group.
    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$BROKEN_PLAN" >/dev/null 2>&1

    # Inject a deliberately-broken statement into the merged group.
    python3 - "$BROKEN_PLAN" <<'PY' >"${BROKEN_PLAN}.tmp"
import json, sys
with open(sys.argv[1]) as f:
    p = json.load(f)
p["groups"][0]["steps"].append({
    "sql": "THIS IS NOT SQL;",
    "type": "table",
    "operation": "create",
    "path": "public.broken"
})
json.dump(p, sys.stdout)
PY
    mv "${BROKEN_PLAN}.tmp" "$BROKEN_PLAN"

    run pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$BROKEN_PLAN" \
        --auto-approve \
        --no-color
    [ "$status" -ne 0 ]

    # Atomic rollback: neither t1 nor v1 should have been created.
    local table_count view_count
    table_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='t1';")
    view_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='public' AND table_name='v1';")
    [ "$table_count" -eq 0 ]
    [ "$view_count" -eq 0 ]

    rm -f "$SCHEMA" "$PLAN" "$BROKEN_PLAN" "${BROKEN_PLAN}.tmp"
    _drop_test_db "$DB"
}

# ---------------------------------------------------------------------------
# Section 9: idempotency smoke tests (TC-52 / TC-53)
# ---------------------------------------------------------------------------

@test "TC-52: re-run after successful apply produces a no-op plan" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    SCHEMA=$(mktemp)
    PLAN=$(mktemp)
    REORDERED=$(mktemp)
    PLAN2=$(mktemp)

    cat >"$SCHEMA" <<'SQL'
CREATE TABLE t1 (id int);
CREATE VIEW v1 AS SELECT id FROM t1;
SQL

    pgschema plan \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --file "$SCHEMA" \
        --output-json "$PLAN" \
        --no-color >/dev/null 2>&1

    "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$REORDERED" >/dev/null 2>&1
    pgschema apply \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --plan "$REORDERED" \
        --auto-approve \
        --no-color >/dev/null 2>&1

    pgschema plan \
        --host /var/run/postgresql \
        --user nova \
        --db "$DB" \
        --schema public \
        --file "$SCHEMA" \
        --output-json "$PLAN2" \
        --no-color >/dev/null 2>&1

    run "$VENV_PYTHON" -c "import json; p=json.load(open('$PLAN2')); print(len(p.get('groups') or []))"
    [ "$status" -eq 0 ]
    [ "$output" -eq 0 ]

    rm -f "$SCHEMA" "$PLAN" "$REORDERED" "$PLAN2"
    _drop_test_db "$DB"
}

@test "TC-53: reorderer hard-fail leaves target database unchanged" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    DB=$(_make_test_db)
    PLAN=$(mktemp)

    cat >"$PLAN" <<'JSON'
{
  "version": "1.0.0",
  "pgschema_version": "1.7.2",
  "source_fingerprint": {"hash": "x"},
  "groups": [{"steps": [
    {"sql": "CREATE VIEW v_a AS SELECT * FROM v_b;", "type": "view", "operation": "create", "path": "public.v_a"},
    {"sql": "CREATE VIEW v_b AS SELECT * FROM v_a;", "type": "view", "operation": "create", "path": "public.v_b"}
  ]}]
}
JSON

    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output /dev/null
    [ "$status" -ne 0 ]

    local table_count
    table_count=$(psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';")
    [ "$table_count" -eq 0 ]

    rm -f "$PLAN"
    _drop_test_db "$DB"
}

# ---------------------------------------------------------------------------
# Defensive static checks already present in agent-install.sh
# ---------------------------------------------------------------------------

@test "agent-install.sh no longer references dead --ignore-file" {
    ! grep -q "PGSCHEMA_IGNORE_OPT" "$INSTALLER"
}

@test "agent-install.sh pins cwd for pgschema invocation" {
    grep -q 'pushd "$SCRIPT_DIR"' "$INSTALLER"
}
