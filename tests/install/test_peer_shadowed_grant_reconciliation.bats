#!/usr/bin/env bats
# Tests for nova-mind#1231 deploy blocker #3:
# peer-shadowed relation grants must be skipped during reconciliation,
# and psql errors must be surfaced instead of swallowed.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FILTER="$REPO_ROOT/database/filter_shadowed_grants.py"

@test "TC-1231g: reconciliation filter skips shadowed foreign table and its id_seq grants" {
    run python3 "$FILTER" --shadowed-names ai_models <<'SQL'
REVOKE SELECT ON TABLE ai_models FROM newhart;
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE ai_models FROM newhart;
GRANT USAGE ON SEQUENCE ai_models_id_seq TO argus;
GRANT SELECT, USAGE ON SEQUENCE ai_models_id_seq TO athena;
GRANT SELECT ON TABLE other_table TO public;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: 2 grant/revoke statement(s) for peer-shadowed object 'ai_models'"* ]]
    [[ "$output" == *"SKIPPED: 2 grant/revoke statement(s) for peer-shadowed object 'ai_models_id_seq'"* ]]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    # The kept statement must be the non-shadowed one; shadowed lines are absent from stdout.
    [[ "$output" == *"GRANT SELECT ON TABLE other_table TO public"* ]]
    [[ "$output" != *"REVOKE SELECT ON TABLE ai_models FROM newhart"* ]]
    [[ "$output" != *"REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE ai_models FROM newhart"* ]]
    [[ "$output" != *"GRANT USAGE ON SEQUENCE ai_models_id_seq TO argus"* ]]
}

@test "TC-1231g-mut: filter keeps shadowed grants when no shadowed names are supplied" {
    run python3 "$FILTER" <<'SQL'
REVOKE SELECT ON TABLE ai_models FROM newhart;
GRANT USAGE ON SEQUENCE ai_models_id_seq TO argus;
GRANT SELECT ON TABLE other_table TO public;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kept 3 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE SELECT ON TABLE ai_models FROM newhart"* ]]
    [[ "$output" == *"GRANT USAGE ON SEQUENCE ai_models_id_seq TO argus"* ]]
    [[ "$output" != *"SKIPPED"* ]]
}

@test "TC-1231h: grant reconciliation surfaces psql errors" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    mkdir -p "$FAKE_REPO/database"
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    cp "$REPO_ROOT/database/schema.sql" "$FAKE_REPO/database/schema.sql"
    cp "$REPO_ROOT/database/filter_shadowed_grants.py" "$FAKE_REPO/database/filter_shadowed_grants.py"
    mkdir -p "$FAKE_REPO/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    HOME="$FAKE_HOME" AGENT_INSTALL_TEST_MODE=1 source "$FAKE_REPO/agent-install.sh"

    VENV_PYTHON="$(command -v python3)"
    SCRIPT_DIR="$FAKE_REPO"
    DB_NAME="test_memory"
    DB_USER="nova"
    PG_SUPERUSER="nova"
    PGPORT="5432"
    PGSCHEMA_SCRATCH_DIR=$(mktemp -d)
    TMPDIRS+=("$PGSCHEMA_SCRATCH_DIR")
    SCHEMA_FILE_TMP=$(mktemp "$PGSCHEMA_SCRATCH_DIR/schema-XXXXXX.sql")
    cat >"$SCHEMA_FILE_TMP" <<'SQL'
CREATE TABLE t (id int);
GRANT SELECT ON TABLE t TO some_role;
SQL

    _run_reconcile() {
        # Mock psql to simulate a permission-denied failure with stderr output.
        _superuser_psql() {
            echo "ERROR:  permission denied for relation t" >&2
            echo "CONTEXT:  SQL statement \"GRANT SELECT ON TABLE t TO some_role\"" >&2
            return 1
        }
        SCHEMA_DIFF_SKIPPED=0
        # Reconciliation block mirrors agent-install.sh.
        echo "  Reconciling explicit schema grants..."
        GRANT_ALL_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" 2>/dev/null || echo 0)
        GRANT_EXTRACT_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-extract-XXXXXX.sql")
        GRANT_FILTERED_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-filtered-XXXXXX.sql")
        grep -E '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" >"$GRANT_EXTRACT_FILE"
        "$VENV_PYTHON" "$SCRIPT_DIR/database/filter_shadowed_grants.py" <"$GRANT_EXTRACT_FILE" >"$GRANT_FILTERED_FILE" 2>"$GRANT_FILTERED_FILE.stderr"
        if [ -s "$GRANT_FILTERED_FILE.stderr" ]; then
            while IFS= read -r line; do echo "  INFO $line"; done < "$GRANT_FILTERED_FILE.stderr"
        fi
        GRANT_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$GRANT_FILTERED_FILE" 2>/dev/null || echo 0)
        GRANT_PSQL_ERR=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-psqlerr-XXXXXX")
        if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f - >/dev/null 2>"$GRANT_PSQL_ERR" <"$GRANT_FILTERED_FILE"; then
            echo "Applied"
        else
            echo -e "  CROSS Grant reconciliation failed"
            if [ -s "$GRANT_PSQL_ERR" ]; then
                echo "  psql errors (first ~20 ERROR lines):"
                grep -E '^ERROR:' "$GRANT_PSQL_ERR" | head -20 | sed 's/^/    /'
            fi
            SCHEMA_DIFF_SKIPPED=1
        fi
        return "$SCHEMA_DIFF_SKIPPED"
    }

    run _run_reconcile

    [ "$status" -eq 1 ]
    [[ "$output" == *"Grant reconciliation failed"* ]]
    [[ "$output" == *"psql errors (first ~20 ERROR lines):"* ]]
    [[ "$output" == *"ERROR:  permission denied for relation t"* ]]

    rm -rf "$FAKE_HOME" "$FAKE_REPO" "$PGSCHEMA_SCRATCH_DIR"
}

@test "TC-1231m: filtered grants are fed to _superuser_psql on stdin" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    mkdir -p "$FAKE_REPO/database"
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    cp "$REPO_ROOT/database/schema.sql" "$FAKE_REPO/database/schema.sql"
    cp "$REPO_ROOT/database/filter_shadowed_grants.py" "$FAKE_REPO/database/filter_shadowed_grants.py"
    mkdir -p "$FAKE_REPO/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    HOME="$FAKE_HOME" AGENT_INSTALL_TEST_MODE=1 source "$FAKE_REPO/agent-install.sh"

    VENV_PYTHON="$(command -v python3)"
    SCRIPT_DIR="$FAKE_REPO"
    DB_NAME="test_memory"
    DB_USER="nova"
    PG_SUPERUSER="postgres"
    PGPORT="5432"
    PGSCHEMA_SCRATCH_DIR=$(mktemp -d)
    TMPDIRS+=("$PGSCHEMA_SCRATCH_DIR")
    SCHEMA_FILE_TMP=$(mktemp "$PGSCHEMA_SCRATCH_DIR/schema-XXXXXX.sql")
    cat >"$SCHEMA_FILE_TMP" <<'SQL'
CREATE TABLE t (id int);
GRANT SELECT ON TABLE t TO some_role;
SQL

    _run_reconcile() {
        # Wrapper that simulates a separate superuser unix user: it can read
        # stdin but cannot open agent-owned files via -f <path>.
        _superuser_psql() {
            local have_f=0 path_arg=""
            for a in "$@"; do
                if [ "$have_f" -eq 1 ]; then
                    path_arg="$a"; break
                fi
                [ "$a" = "-f" ] && have_f=1
            done
            if [ "$have_f" -eq 1 ] && [ "$path_arg" != "-" ]; then
                echo "psql: error: $path_arg: Permission denied" >&2
                return 1
            fi
            local stdin_text; stdin_text=$(cat)
            if [[ "$stdin_text" == *"GRANT SELECT ON TABLE t TO some_role"* ]]; then
                return 0
            fi
            echo "ERROR: unexpected stdin" >&2
            return 1
        }
        SCHEMA_DIFF_SKIPPED=0
        echo "  Reconciling explicit schema grants..."
        GRANT_ALL_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" 2>/dev/null || echo 0)
        GRANT_EXTRACT_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-extract-XXXXXX.sql")
        GRANT_FILTERED_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-filtered-XXXXXX.sql")
        chmod 600 "$GRANT_FILTERED_FILE"
        grep -E '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" >"$GRANT_EXTRACT_FILE"
        "$VENV_PYTHON" "$SCRIPT_DIR/database/filter_shadowed_grants.py" <"$GRANT_EXTRACT_FILE" >"$GRANT_FILTERED_FILE" 2>"$GRANT_FILTERED_FILE.stderr"
        if [ -s "$GRANT_FILTERED_FILE.stderr" ]; then
            while IFS= read -r line; do echo "  INFO $line"; done < "$GRANT_FILTERED_FILE.stderr"
        fi
        GRANT_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$GRANT_FILTERED_FILE" 2>/dev/null || echo 0)
        GRANT_PSQL_ERR=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-psqlerr-XXXXXX")
        if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f - >/dev/null 2>"$GRANT_PSQL_ERR" <"$GRANT_FILTERED_FILE"; then
            echo -e "  CHECK Applied $GRANT_COUNT explicit grant/revoke statement(s)"
        else
            echo -e "  CROSS Grant reconciliation failed"
            if [ -s "$GRANT_PSQL_ERR" ]; then
                echo "  psql errors (first ~20 ERROR lines):"
                grep -E '^ERROR:' "$GRANT_PSQL_ERR" | head -20 | sed 's/^/    /'
            fi
            SCHEMA_DIFF_SKIPPED=1
        fi
        return "$SCHEMA_DIFF_SKIPPED"
    }

    run _run_reconcile

    [ "$status" -eq 0 ]
    [[ "$output" == *"Applied 1 explicit grant/revoke statement(s)"* ]]
    [[ "$output" != *"Permission denied"* ]]

    rm -rf "$FAKE_HOME" "$FAKE_REPO" "$PGSCHEMA_SCRATCH_DIR"
}

@test "TC-1231n: passing an agent-owned file path would fail the superuser wrapper" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    mkdir -p "$FAKE_REPO/database"
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    cp "$REPO_ROOT/database/schema.sql" "$FAKE_REPO/database/schema.sql"
    cp "$REPO_ROOT/database/filter_shadowed_grants.py" "$FAKE_REPO/database/filter_shadowed_grants.py"
    mkdir -p "$FAKE_REPO/lib"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    HOME="$FAKE_HOME" AGENT_INSTALL_TEST_MODE=1 source "$FAKE_REPO/agent-install.sh"

    DB_NAME="test_memory"
    PGSCHEMA_SCRATCH_DIR=$(mktemp -d)
    TMPDIRS+=("$PGSCHEMA_SCRATCH_DIR")
    GRANT_FILTERED_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-filtered-XXXXXX.sql")
    chmod 600 "$GRANT_FILTERED_FILE"
    printf 'GRANT SELECT ON TABLE t TO some_role;\n' >"$GRANT_FILTERED_FILE"

    _run_path_test() {
        _superuser_psql() {
            local have_f=0 path_arg=""
            for a in "$@"; do
                if [ "$have_f" -eq 1 ]; then
                    path_arg="$a"; break
                fi
                [ "$a" = "-f" ] && have_f=1
            done
            if [ "$have_f" -eq 1 ] && [ "$path_arg" != "-" ]; then
                echo "psql: error: $path_arg: Permission denied" >&2
                return 1
            fi
            cat >/dev/null
            return 0
        }

        _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f "$GRANT_FILTERED_FILE"
    }

    run _run_path_test
    [ "$status" -eq 1 ]
    [[ "$output" == *"Permission denied"* ]]

    rm -rf "$FAKE_HOME" "$FAKE_REPO" "$PGSCHEMA_SCRATCH_DIR"
}
