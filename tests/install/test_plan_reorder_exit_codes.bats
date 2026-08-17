#!/usr/bin/env bats
# Tests for issue-597 installer exit-code policy and plan_reorder.py CLI.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"
    REORDERER="${REPO_ROOT}/database/plan_reorder.py"
    if [ ! -x "$VENV_PYTHON" ]; then
        skip "venv python not available at $VENV_PYTHON"
    fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then
        skip "pglast not installed in $VENV_PYTHON"
    fi
}

@test "plan_reorder CLI returns 0 on valid plan" {
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

@test "plan_reorder CLI returns 2 on malformed plan JSON" {
    PLAN=$(mktemp)
    OUT=$(mktemp)
    cat >"$PLAN" <<'JSON'
{"version": "1.0.0", "groups": "not-an-array"}
JSON
    run "$VENV_PYTHON" "$REORDERER" --plan "$PLAN" --output "$OUT"
    [ "$status" -eq 2 ]
    rm -f "$PLAN" "$OUT"
}

@test "plan_reorder CLI returns 3 on unparseable statement" {
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

@test "plan_reorder CLI returns 4 on dependency cycle" {
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

@test "agent-install.sh contains schema-apply exit gate" {
    grep -q "Schema apply stage failed" "${REPO_ROOT}/agent-install.sh"
}

@test "agent-install.sh no longer references dead --ignore-file" {
    ! grep -q "PGSCHEMA_IGNORE_OPT" "${REPO_ROOT}/agent-install.sh"
}

@test "agent-install.sh pins cwd for pgschema invocation" {
    grep -q 'pushd "$SCRIPT_DIR"' "${REPO_ROOT}/agent-install.sh"
}
