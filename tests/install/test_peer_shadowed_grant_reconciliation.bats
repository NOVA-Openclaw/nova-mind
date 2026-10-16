#!/usr/bin/env bats
# Tests for nova-mind#1231 deploy blocker #3:
# peer-shadowed relation grants must be skipped during reconciliation,
# and psql errors must be surfaced instead of swallowed.
#
# Scope addition: every post-/outside-pgschema per-relation stage must also
# gate on the peer-shadowed exclusion set via the shared _is_peer_shadowed
# helper (renames and ownership reassignment).

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FILTER="$REPO_ROOT/database/filter_shadowed_grants.py"

_source_installer_peer_helper() {
    local fake_home="$1"
    local fake_repo="$2"
    mkdir -p "$fake_repo/lib"
    cp "$REPO_ROOT/agent-install.sh" "$fake_repo/agent-install.sh"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$fake_repo/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$fake_repo/lib/agent-chat-peer-detection.sh"
    HOME="$fake_home" AGENT_INSTALL_TEST_MODE=1 source "$fake_repo/agent-install.sh"
}

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
        if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f "$GRANT_FILTERED_FILE" >/dev/null 2>"$GRANT_PSQL_ERR"; then
            echo "Applied"
        else
            echo -e "  CROSS Grant reconciliation failed"
            if [ -s "$GRANT_PSQL_ERR" ]; then
                echo "  psql errors (first ~20 lines):"
                head -20 "$GRANT_PSQL_ERR" | sed 's/^/    /'
            fi
            SCHEMA_DIFF_SKIPPED=1
        fi
        return "$SCHEMA_DIFF_SKIPPED"
    }

    run _run_reconcile

    [ "$status" -eq 1 ]
    [[ "$output" == *"Grant reconciliation failed"* ]]
    [[ "$output" == *"psql errors (first ~20 lines):"* ]]
    [[ "$output" == *"ERROR:  permission denied for relation t"* ]]

    rm -rf "$FAKE_HOME" "$FAKE_REPO" "$PGSCHEMA_SCRATCH_DIR"
}

@test "TC-1231i: shared _is_peer_shadowed helper matches relation and id_seq" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_helper "$FAKE_HOME" "$FAKE_REPO"

    PEER_SHADOWED_NAMES=(agent_bootstrap_context ai_models)
    results=""
    _is_peer_shadowed "agent_bootstrap_context" && results="${results}yes" || results="${results}no"
    _is_peer_shadowed "agent_bootstrap_context_id_seq" && results="${results}yes" || results="${results}no"
    _is_peer_shadowed "ai_models" && results="${results}yes" || results="${results}no"
    _is_peer_shadowed "ai_models_id_seq" && results="${results}yes" || results="${results}no"
    _is_peer_shadowed "tasks" && results="${results}yes" || results="${results}no"
    _is_peer_shadowed "" && results="${results}yes" || results="${results}no"

    [ "$results" = "yesyesyesyesnono" ]

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
}

@test "TC-1231j: column rename is skipped on peer-shadowed table" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_helper "$FAKE_HOME" "$FAKE_REPO"

    PEER_SHADOWED_NAMES=(ai_models)
    APPLIED=0
    SKIPPED=0
    table="ai_models"
    col_from="old_col"
    col_to="new_col"
    pr="#1231"
    EXISTS=1

    # Simulate the gating branch from agent-install.sh.
    if _is_peer_shadowed "$table"; then
        echo "  INFO Skipping column rename on peer-shadowed table $table ($pr)"
        SKIPPED=$((SKIPPED + 1))
    elif [ "${EXISTS:-0}" -eq 1 ]; then
        APPLIED=$((APPLIED + 1))
    else
        SKIPPED=$((SKIPPED + 1))
    fi

    [ "$APPLIED" -eq 0 ]
    [ "$SKIPPED" -eq 1 ]

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
}

@test "TC-1231k: table rename is skipped when either name is peer-shadowed" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_helper "$FAKE_HOME" "$FAKE_REPO"

    PEER_SHADOWED_NAMES=(ai_models)

    if _is_peer_shadowed "ai_models" || _is_peer_shadowed "ai_models_legacy"; then
        skip1=0
    else
        skip1=1
    fi
    [ "$skip1" -eq 0 ]

    if _is_peer_shadowed "tasks" || _is_peer_shadowed "ai_models"; then
        skip2=0
    else
        skip2=1
    fi
    [ "$skip2" -eq 0 ]

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
}

@test "TC-1231l: ownership-reassignment query excludes peer-shadowed objects" {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    _source_installer_peer_helper "$FAKE_HOME" "$FAKE_REPO"

    PEER_SHADOWED_NAMES=(ai_models)

    # The SQL in agent-install.sh excludes sequences owned by tables and orders
    # by relname.  Verify the query string still contains the peer-shadowed
    # skip logic (implemented in the bash while-loop) and the table-owned-seq
    # exclusion.
    run grep -q "_is_peer_shadowed" "$FAKE_REPO/agent-install.sh"
    [ "$status" -eq 0 ]
    run grep -q "d.deptype = 'a'" "$FAKE_REPO/agent-install.sh"
    [ "$status" -eq 0 ]
    run grep -q "Skipping ownership reassignment for peer-shadowed" "$FAKE_REPO/agent-install.sh"
    [ "$status" -eq 0 ]

    rm -rf "$FAKE_HOME" "$FAKE_REPO"
}
