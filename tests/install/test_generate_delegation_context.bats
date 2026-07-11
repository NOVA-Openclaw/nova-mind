#!/usr/bin/env bats
# BATS tests for generate-delegation-context.sh (#414).
#
# These tests exercise the script against a disposable fixture schema
# (`delegation_context_test`) inside the configured Postgres database. All
# destructive statements are schema-qualified and a pre-flight isolation guard
# refuses to run if any target table resolves outside the fixture schema.
#
# NEVER run this suite against production nova_memory without the isolation
# guard in place. The default database is nova_memory only because the script's
# own default targets nova_memory; the fixture schema keeps test data separate.
#
# Run: bats tests/install/test_generate_delegation_context.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SCRIPT="$REPO_ROOT/cognition/scripts/generate-delegation-context.sh"
FIXTURE="$REPO_ROOT/tests/fixtures/delegation_context_seed.sql"

TEST_SCHEMA="delegation_context_test"

DB_HOST="${DELEGATION_CONTEXT_DB_HOST:-localhost}"
DB_PORT="${DELEGATION_CONTEXT_DB_PORT:-5432}"
DB_NAME="${DELEGATION_CONTEXT_DB_NAME:-nova_memory}"
DB_USER="${DELEGATION_CONTEXT_DB_USER:-coder}"

# Base psql invocation for the test-runner user against the configured DB.
# Always scopes to the disposable fixture schema so unqualified names resolve
# there, and never there accidentally.
run_psql() {
    env -u PGPASSWORD PGOPTIONS="-c search_path=$TEST_SCHEMA" \
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$@"
}

# Privileged psql invocation used only for schema-level DDL that the test user
# cannot perform (CREATE SCHEMA, ownership grants).
run_psql_nova() {
    env -u PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U nova -d "$DB_NAME" "$@"
}

# Create the disposable schema and grant the test user access.
ensure_test_schema() {
    run_psql_nova -c "CREATE SCHEMA IF NOT EXISTS $TEST_SCHEMA; GRANT ALL ON SCHEMA $TEST_SCHEMA TO coder;" >/dev/null
}

# Load fixture tables into the disposable schema.
load_fixture() {
    run_psql -f "$FIXTURE" >/dev/null
}

# Defense-in-depth isolation guard. Verifies that the fixture schema is first
# in search_path and that the unqualified target tables resolve inside it.
# Fails the calling test loudly if any target resolves to public.* (or anywhere
# else), preventing destructive statements from touching production tables.
assert_fixture_isolation() {
    local current resolved
    current=$(run_psql -t -A -c "SELECT current_schema();")
    [ "$current" = "$TEST_SCHEMA" ]

    for tbl in agents workflows workflow_steps_detail; do
        resolved=$(run_psql -t -A -c "
            SELECT n.nspname
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relname = '$tbl'
              AND pg_table_is_visible(c.oid);
        ")
        [ "$resolved" = "$TEST_SCHEMA" ]
    done
}

# Run the script under test against the configured test environment.
run_script() {
    local outfile="$1"
    env -u PGPASSWORD \
        PGOPTIONS="-c search_path=$TEST_SCHEMA" \
        DELEGATION_CONTEXT_DB_HOST="$DB_HOST" \
        DELEGATION_CONTEXT_DB_PORT="$DB_PORT" \
        DELEGATION_CONTEXT_DB_NAME="$DB_NAME" \
        DELEGATION_CONTEXT_DB_USER="$DB_USER" \
        bash "$SCRIPT" "$outfile"
}

# Run psql for the configured test environment; used by TC-18 regression guard
# which intentionally checks the public schema, so it does NOT set search_path.
run_psql_public() {
    env -u PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$@"
}

setup() {
    ensure_test_schema
    load_fixture
    assert_fixture_isolation
}

# -----------------------------------------------------------------------------
# TC-1 — Happy Path
# -----------------------------------------------------------------------------
@test "TC-1: full generation against live-shaped schema" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    grep -q '^# Delegation Context' "$outfile"
    grep -q '^\*\*Generated:\*\*' "$outfile"
    grep -q '^## Available Agents' "$outfile"
    grep -q '^## Active Workflows' "$outfile"
    grep -q '^## Spawn Instructions' "$outfile"
    grep -q '^\*Auto-generated from nova_memory database. Do not edit manually\.\*$' "$outfile"

    grep -q '| Nickname | Role | Model | Description |' "$outfile"
    grep -q '| alpha | Coder | model-a | Primary coding agent |' "$outfile"
    grep -q '| beta | Tester | model-b | QA agent |' "$outfile"
    grep -q '| gamma | Peer | model-c | Peer helper |' "$outfile"

    grep -q '### Normal Workflow' "$outfile"
    grep -q "### Test's Workflow" "$outfile"
    grep -q '### Heading Collision Workflow' "$outfile"
    grep -q '### Zero Step Workflow' "$outfile"
    ! grep -q 'Inactive Workflow' "$outfile"

    grep -q '| Step | Domains | Description | Deliverable |' "$outfile"
    grep -q '| 2 | QA, Engineering | Review feature | report |' "$outfile"

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-2 — Query 4 (workflow steps) failure degrades gracefully
# -----------------------------------------------------------------------------
@test "TC-2: workflow step query failure emits degradation marker and exits non-zero" {
    assert_fixture_isolation
    run_psql -c "DROP TABLE $TEST_SCHEMA.workflow_steps_detail CASCADE;" >/dev/null

    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -ne 0 ]

    grep -q '> ⚠️ Failed to generate workflow step data' "$outfile"
    grep -q '^## Available Agents' "$outfile"
    grep -q '^## Spawn Instructions' "$outfile"

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-3 — Query 5 (agents/spawn) failure degrades gracefully
# -----------------------------------------------------------------------------
@test "TC-3: agents query failure emits degradation marker and exits non-zero" {
    assert_fixture_isolation
    run_psql -c "DROP TABLE $TEST_SCHEMA.agents CASCADE;" >/dev/null

    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -ne 0 ]

    grep -q '> ⚠️ Failed to generate agent roster' "$outfile"
    grep -q '> ⚠️ Failed to generate spawn instructions' "$outfile"
    grep -q '^## Active Workflows' "$outfile"

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-4 — Database unreachable
# -----------------------------------------------------------------------------
@test "TC-4: unreachable database fails cleanly with non-zero exit" {
    local outfile
    outfile="$(mktemp)"

    run env -u PGPASSWORD \
        DELEGATION_CONTEXT_DB_HOST="127.0.0.1" \
        DELEGATION_CONTEXT_DB_PORT="65432" \
        bash "$SCRIPT" "$outfile"

    [ "$status" -ne 0 ]
    # The script writes the header, fails the first query, and emits a marker.
    grep -q '^# Delegation Context' "$outfile"
    grep -q '> ⚠️ Failed to generate agent roster' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-5 — Wrong DB user (permission/auth failure)
# -----------------------------------------------------------------------------
@test "TC-5: invalid DB user fails cleanly with non-zero exit" {
    local outfile
    outfile="$(mktemp)"

    run env -u PGPASSWORD \
        DELEGATION_CONTEXT_DB_USER="nonexistent_user_$(date +%s)" \
        bash "$SCRIPT" "$outfile"

    [ "$status" -ne 0 ]
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-6 — Workflow name contains apostrophe
# -----------------------------------------------------------------------------
@test "TC-6: workflow name with apostrophe renders correctly" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    grep -q "### Test's Workflow" "$outfile"
    grep -q '| 1 | QA | Test apostrophe | test |' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-7 — Workflow description contains markdown heading syntax
# -----------------------------------------------------------------------------
@test "TC-7: embedded heading syntax is escaped" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    grep -q '^\\# Not A Heading' "$outfile"
    grep -q '^\\## Also Not A Heading' "$outfile"

    # Only the document title should be a level-1 heading.
    [ "$(grep -c '^# ' "$outfile")" -eq 1 ]
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-8 — Workflow with zero steps
# -----------------------------------------------------------------------------
@test "TC-8: zero-step workflow shows explicit marker" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    grep -q '### Zero Step Workflow' "$outfile"
    grep -q '> No steps defined for this workflow.' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-9 — Agent with NULL decision_criteria
# -----------------------------------------------------------------------------
@test "TC-9: NULL decision_criteria renders without literal NULL" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    ! grep -q 'Decision criteria: NULL' "$outfile"
    # alpha has a populated value; match it regardless of surrounding markdown.
    grep -q 'Decision criteria:\*\* Handle coding tasks' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-10 — Multi-domain step
# -----------------------------------------------------------------------------
@test "TC-10: multi-domain step renders joined domains" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    grep -q '| 2 | QA, Engineering | Review feature | report |' "$outfile"
    ! grep -q '{QA,Engineering}' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-11 — Empty active workflow set
# -----------------------------------------------------------------------------
@test "TC-11: empty active workflow set renders explicit statement" {
    assert_fixture_isolation
    run_psql -c "UPDATE $TEST_SCHEMA.workflows SET status = 'inactive';" >/dev/null

    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    grep -q 'No active workflows found.' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-12 — Output path override
# -----------------------------------------------------------------------------
@test "TC-12: output path override writes to specified file only" {
    local outfile
    outfile="$(mktemp -t custom-delegation-XXXXXX.md)"

    run run_script "$outfile"
    [ "$status" -eq 0 ]
    [ -s "$outfile" ]
    grep -q '^# Delegation Context' "$outfile"

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-13 — Valid markdown heading hierarchy
# -----------------------------------------------------------------------------
@test "TC-13: heading hierarchy is consistent" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    [ "$(grep -c '^# ' "$outfile")" -eq 1 ]
    grep -q '^## Available Agents' "$outfile"
    grep -q '^## Active Workflows' "$outfile"
    grep -q '^## Spawn Instructions' "$outfile"

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-14 — Generated timestamp is UTC
# -----------------------------------------------------------------------------
@test "TC-14: generated timestamp is UTC" {
    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]

    local generated_ts
    generated_ts="$(grep '^\*\*Generated:\*\*' "$outfile" | sed 's/^\*\*Generated:\*\* //')"
    [ -n "$generated_ts" ]
    # Assert format explicitly to avoid a minute-rollover flake.
    [[ "$generated_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}\ UTC$ ]]
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-15 — No PGPASSWORD dependency
# -----------------------------------------------------------------------------
@test "TC-15: script authenticates via pgpass and contains no PGPASSWORD references" {
    [ "$(grep -c PGPASSWORD "$SCRIPT")" -eq 0 ]
    [ "$(grep -c '2>/dev/null' "$SCRIPT")" -eq 0 ]

    local outfile
    outfile="$(mktemp)"
    run run_script "$outfile"
    [ "$status" -eq 0 ]
    [ -s "$outfile" ]
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-16 — Installer wiring
# -----------------------------------------------------------------------------
@test "TC-16: installer copies script to runtime scripts directory" {
    [ -x "$SCRIPT" ]
    grep -q 'generate-delegation-context.sh' "$REPO_ROOT/agent-install.sh"
    grep -q '\$HOME/.openclaw/workspace/scripts/generate-delegation-context.sh' "$REPO_ROOT/agent-install.sh"
}

# -----------------------------------------------------------------------------
# TC-17 — Idempotent re-run
# -----------------------------------------------------------------------------
@test "TC-17: second run overwrites output cleanly" {
    local outfile
    outfile="$(mktemp)"

    run run_script "$outfile"
    [ "$status" -eq 0 ]

    run run_script "$outfile"
    [ "$status" -eq 0 ]

    [ "$(grep -c '^# Delegation Context' "$outfile")" -eq 1 ]
    [ "$(grep -c '^---$' "$outfile")" -eq 1 ]

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-18 — Schema regression guard
# -----------------------------------------------------------------------------
@test "TC-18: regression guard detects required and removed columns" {
    run run_psql_public -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workflow_steps_detail'
          AND column_name = 'agent_name';
    "
    [ -z "$output" ]

    run run_psql_public -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'agents'
          AND column_name = 'seed_context';
    "
    [ -z "$output" ]

    run run_psql_public -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workflow_steps_detail'
          AND column_name IN ('domain', 'domains')
        ORDER BY column_name;
    "
    [ "$output" = $'domain\ndomains' ]

    run run_psql_public -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'agents'
          AND column_name IN ('nickname', 'model', 'thinking', 'context_type', 'allowed_subagents', 'decision_criteria')
        ORDER BY column_name;
    "
    [ "$output" = $'allowed_subagents\ncontext_type\ndecision_criteria\nmodel\nnickname\nthinking' ]
}
