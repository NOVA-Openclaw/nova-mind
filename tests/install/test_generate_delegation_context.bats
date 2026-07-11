#!/usr/bin/env bats
# BATS tests for generate-delegation-context.sh (#414).
#
# These tests exercise the script against a disposable fixture schema in the
# configured Postgres database (default nova_memory). The fixture schema is
# created/owned by the nova DB user because the test runner DB user (coder)
# lacks CREATE on the database; all data operations and the script under test
# run as coder.
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

run_psql() {
    env -u PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$@"
}

run_psql_nova() {
    # Used only for schema-level DDL that the test user cannot perform.
    env -u PGPASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U nova -d "$DB_NAME" "$@"
}

ensure_test_schema() {
    run_psql_nova -c "CREATE SCHEMA IF NOT EXISTS $TEST_SCHEMA; GRANT ALL ON SCHEMA $TEST_SCHEMA TO coder;" >/dev/null
}

load_fixture() {
    run_psql -f "$FIXTURE" >/dev/null
}

setup() {
    ensure_test_schema
    load_fixture

    # Environment for the script under test.
    export PGOPTIONS="-c search_path=$TEST_SCHEMA"
    export DELEGATION_CONTEXT_DB_HOST="$DB_HOST"
    export DELEGATION_CONTEXT_DB_PORT="$DB_PORT"
    export DELEGATION_CONTEXT_DB_NAME="$DB_NAME"
    export DELEGATION_CONTEXT_DB_USER="$DB_USER"
}

# -----------------------------------------------------------------------------
# TC-1 — Happy Path
# -----------------------------------------------------------------------------
@test "TC-1: full generation against live-shaped schema" {
    local outfile
    outfile="$(mktemp)"
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run_psql -c "DROP TABLE workflow_steps_detail CASCADE;" >/dev/null

    local outfile
    outfile="$(mktemp)"
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run_psql -c "DROP TABLE agents CASCADE;" >/dev/null

    local outfile
    outfile="$(mktemp)"
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    [ ! -s "$outfile" ] || grep -q '> ⚠️' "$outfile" || true
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
    [ "$status" -eq 0 ]

    ! grep -q 'Decision criteria: NULL' "$outfile"
    # alpha has a populated value; match it regardless of surrounding markdown bold markers.
    grep -q 'Decision criteria:\*\* Handle coding tasks' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-10 — Multi-domain step
# -----------------------------------------------------------------------------
@test "TC-10: multi-domain step renders joined domains" {
    local outfile
    outfile="$(mktemp)"
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
    [ "$status" -eq 0 ]

    grep -q '| 2 | QA, Engineering | Review feature | report |' "$outfile"
    ! grep -q '{QA,Engineering}' "$outfile"
    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-11 — Empty active workflow set
# -----------------------------------------------------------------------------
@test "TC-11: empty active workflow set renders explicit statement" {
    run_psql -c "UPDATE workflows SET status = 'inactive';" >/dev/null

    local outfile
    outfile="$(mktemp)"
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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

    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
    [ "$status" -eq 0 ]

    local generated_ts
    generated_ts="$(grep '^\*\*Generated:\*\*' "$outfile" | sed 's/^\*\*Generated:\*\* //')"
    [ -n "$generated_ts" ]

    local expected_ts
    expected_ts="$(date -u +'%Y-%m-%d %H:%M UTC')"
    [ "$generated_ts" = "$expected_ts" ]
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
    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
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

    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
    [ "$status" -eq 0 ]

    run env -u PGPASSWORD bash "$SCRIPT" "$outfile"
    [ "$status" -eq 0 ]

    [ "$(grep -c '^# Delegation Context' "$outfile")" -eq 1 ]
    [ "$(grep -c '^---$' "$outfile")" -eq 1 ]

    rm -f "$outfile"
}

# -----------------------------------------------------------------------------
# TC-18 — Schema regression guard
# -----------------------------------------------------------------------------
@test "TC-18: regression guard detects required and removed columns" {
    run run_psql -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workflow_steps_detail'
          AND column_name = 'agent_name';
    "
    [ -z "$output" ]

    run run_psql -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'agents'
          AND column_name = 'seed_context';
    "
    [ -z "$output" ]

    run run_psql -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'workflow_steps_detail'
          AND column_name IN ('domain', 'domains')
        ORDER BY column_name;
    "
    [ "$output" = $'domain\ndomains' ]

    run run_psql -t -A -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'agents'
          AND column_name IN ('nickname', 'model', 'thinking', 'context_type', 'allowed_subagents', 'decision_criteria')
        ORDER BY column_name;
    "
    [ "$output" = $'allowed_subagents\ncontext_type\ndecision_criteria\nmodel\nnickname\nthinking' ]
}
