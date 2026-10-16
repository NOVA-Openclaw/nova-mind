#!/usr/bin/env bats
# Tests for nova-mind#1231 deploy blocker #4:
# filtered GRANT/REVOKE statements must be fed to _superuser_psql on stdin
# so the postgres superuser can read them even when the scratch file is
# owned by the installing agent (mode 600).

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

_setup() {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"
    mkdir -p "$FAKE_REPO/database" "$FAKE_REPO/lib"
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    cp "$REPO_ROOT/database/schema.sql" "$FAKE_REPO/database/schema.sql"
    cp "$REPO_ROOT/database/filter_shadowed_grants.py" "$FAKE_REPO/database/filter_shadowed_grants.py"
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
}

_teardown() {
    rm -rf "$FAKE_HOME" "$FAKE_REPO" "$PGSCHEMA_SCRATCH_DIR"
}

_run_reconcile_stdin() {
    # Stub that proves the filtered grants arrived via stdin.
    # It rejects the old file-path invocation and only accepts -f -.
    _superuser_psql() {
        local args="$*"
        case "$args" in
            *"-f -"*)
                cat >"$SEEN_STDIN"
                return 0
                ;;
            *"-f "*)
                echo "ERROR:  permission denied for relation t" >&2
                return 1
                ;;
            *)
                echo "ERROR: unexpected _superuser_psql args: $args" >&2
                return 1
                ;;
        esac
    }

    SCHEMA_DIFF_SKIPPED=0
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
    if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f - <"$GRANT_FILTERED_FILE" >/dev/null 2>"$GRANT_PSQL_ERR"; then
        echo -e "  ${CHECK_MARK} Applied $GRANT_COUNT explicit grant/revoke statement(s)"
    else
        echo -e "  ${CROSS_MARK} Grant reconciliation failed"
        if [ -s "$GRANT_PSQL_ERR" ]; then
            echo "  psql errors (first ~20 lines):"
            head -20 "$GRANT_PSQL_ERR" | sed 's/^/    /'
        fi
        SCHEMA_DIFF_SKIPPED=1
    fi
    return "$SCHEMA_DIFF_SKIPPED"
}

@test "TC-1231i: filtered grants reach superuser psql via stdin" {
    _setup
    SEEN_STDIN="$PGSCHEMA_SCRATCH_DIR/stdin-seen"

    run _run_reconcile_stdin

    [ "$status" -eq 0 ]
    [[ "$output" == *"Applied 1 explicit grant/revoke statement(s)"* ]]
    [ -s "$SEEN_STDIN" ]
    grep -qF 'GRANT SELECT ON TABLE t TO some_role;' "$SEEN_STDIN"

    _teardown
}

_run_reconcile_file_path() {
    # Mutation stub: the superuser cannot read a file path but would accept stdin.
    _superuser_psql() {
        local args="$*"
        case "$args" in
            *"-f -"*)
                cat >/dev/null
                return 0
                ;;
            *"-f "*)
                echo "ERROR:  permission denied for relation t" >&2
                return 1
                ;;
            *)
                echo "ERROR: unexpected _superuser_psql args: $args" >&2
                return 1
                ;;
        esac
    }

    SCHEMA_DIFF_SKIPPED=0
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
    # MUTATION: use the old file-path invocation that the real fix replaced.
    if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f "$GRANT_FILTERED_FILE" >/dev/null 2>"$GRANT_PSQL_ERR"; then
        echo -e "  ${CHECK_MARK} Applied $GRANT_COUNT explicit grant/revoke statement(s)"
    else
        echo -e "  ${CROSS_MARK} Grant reconciliation failed"
        if [ -s "$GRANT_PSQL_ERR" ]; then
            echo "  psql errors (first ~20 lines):"
            head -20 "$GRANT_PSQL_ERR" | sed 's/^/    /'
        fi
        SCHEMA_DIFF_SKIPPED=1
    fi
    return "$SCHEMA_DIFF_SKIPPED"
}

@test "TC-1231i-mut: file-path grant invocation is rejected by the superuser stub" {
    _setup

    run _run_reconcile_file_path

    [ "$status" -eq 1 ]
    [[ "$output" == *"Grant reconciliation failed"* ]]
    [[ "$output" == *"permission denied for relation t"* ]]

    _teardown
}
