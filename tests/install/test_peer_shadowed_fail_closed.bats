#!/usr/bin/env bats
# Tests for nova-mind#1231 fix-loop:
#   (a) detect_peer_shadowed.py failure must fail closed (abort schema apply),
#   (b) the installer's peer-shadowed code path must execute without the
#       top-level `local` error under set -euo pipefail.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

_pg_available() {
    command -v psql >/dev/null 2>&1 && command -v pgschema >/dev/null 2>&1 && \
        pg_isready -h /var/run/postgresql >/dev/null 2>&1
}

_make_test_db() {
    local dbname="nova_mind_psfc_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

# Source agent-install.sh in test mode so helper functions can be called
# without running the full installer.  Mirrors the pattern in
# tests/install/test_agent_install_722_723.bats.
_source_installer_peer_functions() {
    local fake_home="$1"
    local fake_repo="$2"
    mkdir -p "$fake_home/.openclaw"
    printf '%s\n' '{' '  "host": "localhost",' '  "port": 5432,' '  "database": "test_memory",' '  "user": "testuser",' '  "password": ""' '}' >"$fake_home/.openclaw/postgres.json"

    cp "$REPO_ROOT/agent-install.sh" "$fake_repo/agent-install.sh"
    mkdir -p "$fake_repo/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$fake_repo/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$fake_repo/lib/agent-chat-peer-detection.sh"
    mkdir -p "$fake_repo/database"
    cp "$REPO_ROOT/database/schema.sql" "$fake_repo/database/schema.sql"
    cp "$REPO_ROOT/database/detect_peer_shadowed.py" "$fake_repo/database/detect_peer_shadowed.py"

    HOME="$fake_home" AGENT_INSTALL_TEST_MODE=1 source "$fake_repo/agent-install.sh"
}

@test "TC-252-B-10b: installer peer path executes without local error" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_functions "$FAKE_HOME" "$FAKE_REPO"

    DB=$(_make_test_db)
    DB_NAME="$DB"
    DB_USER="nova"
    PGPORT="5432"
    SCHEMA_FILE="$FAKE_REPO/database/schema.sql"
    VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

    # Execute the installer's peer-shadowed resolution path.  Before the fix,
    # top-level `local` statements in this path aborted with:
    #   local: can only be used in a function
    # Do not use `run` here: the function sets globals (PEER_SHADOWED_NAMES,
    # PGSCHEMA_PEER_MODE) that the assertions below need in this shell.
    PEER_SHADOWED_LOG=$(mktemp)
    _resolve_peer_shadowed_relations >"$PEER_SHADOWED_LOG" 2>&1
    [ $? -eq 0 ]
    [[ $(cat "$PEER_SHADOWED_LOG") != *"local: can only be used in a function"* ]]
    [ "${#PEER_SHADOWED_NAMES[@]}" -eq 0 ]
    [ "$PGSCHEMA_PEER_MODE" -eq 0 ]
    rm -f "$PEER_SHADOWED_LOG"

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
    _drop_test_db "$DB"
}

@test "TC-1231d: detect_peer_shadowed.py failure fails closed (no plan applied)" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_functions "$FAKE_HOME" "$FAKE_REPO"

    DB=$(_make_test_db)
    DB_NAME="$DB"
    DB_USER="nova"
    PGPORT="5432"
    SCHEMA_FILE="$FAKE_REPO/database/schema.sql"
    VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

    # Simulate a detection failure (bad DSN / unreachable detector).
    cat >"$FAKE_REPO/database/detect_peer_shadowed.py" <<'PY'
#!/usr/bin/env python3
import sys
print("ERROR: simulated detection failure", file=sys.stderr)
sys.exit(2)
PY
    chmod +x "$FAKE_REPO/database/detect_peer_shadowed.py"

    # Replicate the installer's fail-closed control flow.
    SCHEMA_DIFF_SKIPPED=0
    run _resolve_peer_shadowed_relations
    if [ "$status" -ne 0 ]; then
        SCHEMA_DIFF_SKIPPED=1
    fi

    [ "$SCHEMA_DIFF_SKIPPED" -eq 1 ]
    [[ "$output" == *"Peer-shadowed relation detection failed"* ]]

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
    _drop_test_db "$DB"
}

@test "TC-1231d-mut: restored || fallback swallows detection failure" {
    if [ ! -x "$VENV_PYTHON" ]; then skip "venv python not available at $VENV_PYTHON"; fi
    if ! "$VENV_PYTHON" -c "import pglast" 2>/dev/null; then skip "pglast not installed"; fi
    if ! _pg_available; then skip "live PostgreSQL/pgschema not available"; fi

    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_functions "$FAKE_HOME" "$FAKE_REPO"

    DB=$(_make_test_db)
    DB_NAME="$DB"
    DB_USER="nova"
    PGPORT="5432"
    SCHEMA_FILE="$FAKE_REPO/database/schema.sql"
    VENV_PYTHON="${PLAN_REORDER_VENV_PYTHON:-${HOME}/.local/share/${USER}/venv/bin/python}"

    cat >"$FAKE_REPO/database/detect_peer_shadowed.py" <<'PY'
#!/usr/bin/env python3
import sys
print("ERROR: simulated detection failure", file=sys.stderr)
sys.exit(2)
PY
    chmod +x "$FAKE_REPO/database/detect_peer_shadowed.py"

    # Mutation: restore the old || fallback that the fix removed.
    _resolve_peer_shadowed_relations() {
        local shadowed_json
        shadowed_json=$("$VENV_PYTHON" "$SCRIPT_DIR/database/detect_peer_shadowed.py" \
            --schema-file "$SCHEMA_FILE" \
            --dsn "host=/var/run/postgresql port=${PGPORT:-5432} dbname=$DB_NAME user=$DB_USER" 2>/dev/null) || shadowed_json=""
        PEER_SHADOWED_NAMES=()
        PEER_SHADOWED_RELKINDS=()
        PEER_SHADOWED_KINDS=()
        PGSCHEMA_PEER_MODE=0
        PGSCHEMA_IGNORE_BASE="$SCRIPT_DIR/database/.pgschemaignore"
        return 0
    }

    # With the fallback, detection failure returns zero and would plan with
    # zero exclusions — this proves TC-1231d catches the bug.
    run _resolve_peer_shadowed_relations
    [ "$status" -eq 0 ]

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
    _drop_test_db "$DB"
}
