#!/usr/bin/env bats
# Tests for pre-migration 009: get_agent_export_rows() return-type upgrade.
#
# Verifies the upgrade path from the 11-column (#714 pre-isolatedSession)
# function definition to the 12-column schema.sql definition, plus the
# fresh-install and idempotency requirements.
#
# Run: bats tests/install/test_pre_migration_009.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
PRE_MIGRATION="$REPO_ROOT/database/pre-migrations/009-drop-and-recreate-get-agent-export-rows.sql"
SCHEMA_FILE="$REPO_ROOT/database/schema.sql"

_pg_available() {
    command -v psql >/dev/null 2>&1 && pg_isready -h /var/run/postgresql >/dev/null 2>&1
}

_make_test_db() {
    local dbname="se1231_r5fix_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    createdb -U nova "$dbname" >/dev/null 2>&1
    echo "$dbname"
}

_drop_test_db() {
    local dbname="$1"
    dropdb -U nova "$dbname" >/dev/null 2>&1 || true
}

_run_pre_migration() {
    local db="$1"
    psql -U nova -d "$db" -v ON_ERROR_STOP=1 -f "$PRE_MIGRATION" >/dev/null 2>&1
}

# Extract the function body from schema.sql (between AS $$ and $$;).
_expected_body() {
    awk '
        /^CREATE OR REPLACE FUNCTION get_agent_export_rows\(\)/ { in_func = 1 }
        in_func && /^[[:space:]]*AS \$\$/ { in_body = 1; next }
        in_body && /^\$\$;[[:space:]]*$/ { exit }
        in_body { print }
    ' "$SCHEMA_FILE"
}

# Extract the full CREATE OR REPLACE FUNCTION statement from schema.sql.
_expected_create_statement() {
    awk '
        /^CREATE OR REPLACE FUNCTION get_agent_export_rows\(\)/ { in_func = 1 }
        in_func { print }
        in_func && /^\$\$;[[:space:]]*$/ { exit }
    ' "$SCHEMA_FILE"
}

@test "TC-009-upgrade: 11-column function is recreated with heartbeat_isolated_session" {
    if ! _pg_available; then skip "live PostgreSQL not available"; fi

    DB=$(_make_test_db)

    # Simulate a pre-#714 database: agents table without heartbeat_isolated_session
    # and the 11-column get_agent_export_rows().
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE agents (
    id serial PRIMARY KEY,
    name varchar(100) NOT NULL,
    model varchar(100),
    fallback_models text[],
    thinking varchar(20),
    instance_type varchar(20),
    allowed_subagents text[],
    heartbeat_enabled boolean DEFAULT false,
    heartbeat_every text,
    heartbeat_target text,
    heartbeat_to text,
    parent_agents text[],
    status varchar(20) DEFAULT 'active'
);

CREATE OR REPLACE FUNCTION get_agent_export_rows()
RETURNS TABLE(name text, model text, fallback_models text[], thinking text, instance_type text, is_default boolean, allowed_subagents text[], heartbeat_enabled boolean, heartbeat_every text, heartbeat_target text, heartbeat_to text)
LANGUAGE sql
STABLE
AS $$
  SELECT
    a.name::text,
    a.model::text,
    a.fallback_models,
    a.thinking::text,
    a.instance_type::text,
    TRUE AS is_default,
    a.allowed_subagents,
    a.heartbeat_enabled,
    a.heartbeat_every,
    a.heartbeat_target,
    a.heartbeat_to
  FROM agents a
  WHERE a.name = session_user
    AND a.status = 'active'
    AND a.model IS NOT NULL

  UNION ALL

  SELECT
    a.name::text,
    a.model::text,
    a.fallback_models,
    a.thinking::text,
    a.instance_type::text,
    FALSE AS is_default,
    a.allowed_subagents,
    a.heartbeat_enabled,
    a.heartbeat_every,
    a.heartbeat_target,
    a.heartbeat_to
  FROM agents a
  WHERE session_user = ANY (a.parent_agents)
    AND a.status = 'active'
    AND a.model IS NOT NULL

  ORDER BY 6 DESC, 1;
$$;
SQL

    run _run_pre_migration "$DB"
    [ "$status" -eq 0 ]

    # The agents table now has heartbeat_isolated_session with default false.
    run psql -U nova -d "$DB" -tAc \
        "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='agents' AND column_name='heartbeat_isolated_session';"
    [ "$status" -eq 0 ]
    [ "${output//[[:space:]]/}" = "1" ]

    run psql -U nova -d "$DB" -tAc \
        "SELECT column_default FROM information_schema.columns WHERE table_schema='public' AND table_name='agents' AND column_name='heartbeat_isolated_session';"
    [ "$status" -eq 0 ]
    [ "${output//[[:space:]]/}" = "false" ]

    # The function now returns 12 columns.
    run psql -U nova -d "$DB" -tAc "SELECT pg_get_function_result('get_agent_export_rows()'::regprocedure);"
    [ "$status" -eq 0 ]
    [[ "$output" == *"heartbeat_isolated_session"* ]]

    # Function body matches schema.sql (normalized).
    expected=$(_expected_body)
    run psql -U nova -d "$DB" -tAc "SELECT prosrc FROM pg_proc WHERE proname='get_agent_export_rows';"
    [ "$status" -eq 0 ]
    actual="$output"
    run python3 -c '
import re, sys
norm = lambda s: re.sub(r"\s+", " ", s.strip())
exp = norm(sys.argv[1])
act = norm(sys.argv[2])
if exp != act:
    print("EXPECTED:", repr(exp))
    print("ACTUAL:  ", repr(act))
    sys.exit(1)
' "$expected" "$actual"
    [ "$status" -eq 0 ]

    # Default PUBLIC EXECUTE privilege is preserved (proacl NULL).
    run psql -U nova -d "$DB" -tAc "SELECT proacl IS NULL FROM pg_proc WHERE proname='get_agent_export_rows';"
    [ "$status" -eq 0 ]
    [ "${output//[[:space:]]/}" = "t" ]

    _drop_test_db "$DB"
}

@test "TC-009-fresh: pre-migration is a clean no-op on an empty database" {
    if ! _pg_available; then skip "live PostgreSQL not available"; fi

    DB=$(_make_test_db)

    run _run_pre_migration "$DB"
    [ "$status" -eq 0 ]

    run psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='agents';"
    [ "$status" -eq 0 ]
    [ "${output//[[:space:]]/}" = "0" ]

    run psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM pg_proc WHERE proname='get_agent_export_rows';"
    [ "$status" -eq 0 ]
    [ "${output//[[:space:]]/}" = "0" ]

    _drop_test_db "$DB"
}

@test "TC-009-idempotent: running the pre-migration twice produces the same result" {
    if ! _pg_available; then skip "live PostgreSQL not available"; fi

    DB=$(_make_test_db)

    # Seed the upgrade state.
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE agents (
    id serial PRIMARY KEY,
    name varchar(100) NOT NULL,
    model varchar(100),
    fallback_models text[],
    thinking varchar(20),
    instance_type varchar(20),
    allowed_subagents text[],
    heartbeat_enabled boolean DEFAULT false,
    heartbeat_every text,
    heartbeat_target text,
    heartbeat_to text,
    parent_agents text[],
    status varchar(20) DEFAULT 'active'
);

CREATE OR REPLACE FUNCTION get_agent_export_rows()
RETURNS TABLE(name text, model text, fallback_models text[], thinking text, instance_type text, is_default boolean, allowed_subagents text[], heartbeat_enabled boolean, heartbeat_every text, heartbeat_target text, heartbeat_to text)
LANGUAGE sql
STABLE
AS $$
  SELECT a.name::text, a.model::text, a.fallback_models, a.thinking::text, a.instance_type::text,
         TRUE AS is_default, a.allowed_subagents, a.heartbeat_enabled, a.heartbeat_every, a.heartbeat_target, a.heartbeat_to
  FROM agents a
  WHERE a.name = session_user AND a.status = 'active' AND a.model IS NOT NULL
  UNION ALL
  SELECT a.name::text, a.model::text, a.fallback_models, a.thinking::text, a.instance_type::text,
         FALSE AS is_default, a.allowed_subagents, a.heartbeat_enabled, a.heartbeat_every, a.heartbeat_target, a.heartbeat_to
  FROM agents a
  WHERE session_user = ANY (a.parent_agents) AND a.status = 'active' AND a.model IS NOT NULL
  ORDER BY 6 DESC, 1;
$$;
SQL

    run _run_pre_migration "$DB"
    [ "$status" -eq 0 ]

    first_body=$(psql -U nova -d "$DB" -tAc "SELECT prosrc FROM pg_proc WHERE proname='get_agent_export_rows';")

    run _run_pre_migration "$DB"
    [ "$status" -eq 0 ]

    second_body=$(psql -U nova -d "$DB" -tAc "SELECT prosrc FROM pg_proc WHERE proname='get_agent_export_rows';")

    [ "$first_body" = "$second_body" ]

    run psql -U nova -d "$DB" -tAc "SELECT pg_get_function_result('get_agent_export_rows()'::regprocedure);"
    [ "$status" -eq 0 ]
    [[ "$output" == *"heartbeat_isolated_session"* ]]

    _drop_test_db "$DB"
}

@test "TC-009-mutation: upgrade fails without the pre-migration" {
    if ! _pg_available; then skip "live PostgreSQL not available"; fi

    DB=$(_make_test_db)

    # Seed the old 11-column state, then add the new column. This mirrors the
    # real pgschema plan order: schema.sql's ALTER TABLE ADD COLUMN is applied
    # before the CREATE OR REPLACE FUNCTION. With the column present, the new
    # function body is valid, so Postgres rejects it solely because the return
    # type changed (SQLSTATE 42P13).
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE agents (
    id serial PRIMARY KEY,
    name varchar(100) NOT NULL,
    model varchar(100),
    fallback_models text[],
    thinking varchar(20),
    instance_type varchar(20),
    allowed_subagents text[],
    heartbeat_enabled boolean DEFAULT false,
    heartbeat_every text,
    heartbeat_target text,
    heartbeat_to text,
    parent_agents text[],
    status varchar(20) DEFAULT 'active'
);

CREATE OR REPLACE FUNCTION get_agent_export_rows()
RETURNS TABLE(name text, model text, fallback_models text[], thinking text, instance_type text, is_default boolean, allowed_subagents text[], heartbeat_enabled boolean, heartbeat_every text, heartbeat_target text, heartbeat_to text)
LANGUAGE sql
STABLE
AS $$
  SELECT a.name::text, a.model::text, a.fallback_models, a.thinking::text, a.instance_type::text,
         TRUE AS is_default, a.allowed_subagents, a.heartbeat_enabled, a.heartbeat_every, a.heartbeat_target, a.heartbeat_to
  FROM agents a
  WHERE a.name = session_user AND a.status = 'active' AND a.model IS NOT NULL
  UNION ALL
  SELECT a.name::text, a.model::text, a.fallback_models, a.thinking::text, a.instance_type::text,
         FALSE AS is_default, a.allowed_subagents, a.heartbeat_enabled, a.heartbeat_every, a.heartbeat_target, a.heartbeat_to
  FROM agents a
  WHERE session_user = ANY (a.parent_agents) AND a.status = 'active' AND a.model IS NOT NULL
  ORDER BY 6 DESC, 1;
$$;

ALTER TABLE agents ADD COLUMN heartbeat_isolated_session boolean DEFAULT false;
SQL

    # Attempt to apply the new 12-column definition directly (what pgschema
    # would emit). This must fail with 42P13. \errverbose exposes the SQLSTATE
    # because psql's default error text does not include it.
    expected_stmt=$(_expected_create_statement)
    run psql -U nova -d "$DB" -v ON_ERROR_STOP=0 <<PSQL 2>&1
${expected_stmt}
\errverbose
PSQL
    [[ "$output" == *"42P13:"* ]]

    _drop_test_db "$DB"
}

@test "TC-009-preheartbeat: agents table missing heartbeat_* and parent_agents gets columns added" {
    if ! _pg_available; then skip "live PostgreSQL not available"; fi

    DB=$(_make_test_db)

    # Simulate a pre-heartbeat agents table: none of the columns referenced by
    # the 12-column get_agent_export_rows() exist yet (nova-mind#773).
    psql -U nova -d "$DB" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE TABLE agents (
    id serial PRIMARY KEY,
    name varchar(100) NOT NULL,
    model varchar(100),
    fallback_models text[],
    thinking varchar(20),
    instance_type varchar(20),
    allowed_subagents text[],
    status varchar(20) DEFAULT 'active'
);
SQL

    run _run_pre_migration "$DB"
    [ "$status" -eq 0 ]

    for col in parent_agents heartbeat_enabled heartbeat_every heartbeat_target heartbeat_to heartbeat_isolated_session; do
        run psql -U nova -d "$DB" -tAc \
            "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='agents' AND column_name='$col';"
        [ "$status" -eq 0 ]
        [ "${output//[[:space:]]/}" = "1" ]
    done

    # No old function existed, so schema.sql will create the new one later.
    run psql -U nova -d "$DB" -tAc "SELECT COUNT(*) FROM pg_proc WHERE proname='get_agent_export_rows';"
    [ "$status" -eq 0 ]
    [ "${output//[[:space:]]/}" = "0" ]

    _drop_test_db "$DB"
}

@test "TC-009-shellcheck: bats test file passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}
