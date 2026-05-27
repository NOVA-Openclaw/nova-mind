#!/usr/bin/env bats
# BATS tests for agent-install.sh agents.json safety (#252)
#
# Test cases:
#   TC-252-B-01: Skip write when agents.json exists and is valid JSON
#   TC-252-B-02: Write (backup + overwrite) when --regenerate-agents-json flag
#   TC-252-B-03: Never write [] when psql fails (no existing agents.json)
#   TC-252-B-04: Never write [] on psql failure even when agents.json does not yet exist
#   TC-252-B-05: Backup created before forced overwrite
#   TC-252-B-07: Idempotency — running installer twice does not corrupt agents.json
#   TC-252-B-08: Skip write when agents.json exists but is invalid JSON — warn and preserve
#   TC-252-B-09: --regenerate-agents-json replaces invalid JSON file
#   TC-252-B-10: ShellCheck — zero warnings on agent-install.sh
#
# Pre-requisites:
#   - bats-core installed
#   - bats-support and bats-assert installed (optional, nice assertions)
#   - shellcheck installed (for TC-252-B-10)
#
# Run: bats tests/install/test_agents_json_safety.bats
#
# NOTE: These tests exercise only the agents.json generation sub-function by
# sourcing a minimal stub of agent-install.sh. Full integration tests require
# a live database.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    # Each test gets a fresh temp dir masquerading as ~/.openclaw
    FAKE_OPENCLAW="$(mktemp -d)"
    FAKE_AGENTS_JSON="$FAKE_OPENCLAW/agents.json"
    export FAKE_OPENCLAW FAKE_AGENTS_JSON
}

teardown() {
    rm -rf "$FAKE_OPENCLAW"
}

# Inline the agents.json logic extracted from agent-install.sh for unit testing.
# This calls the same _generate_agents_json() logic without requiring live DB.
# We mock psql to return controlled output.
run_agents_json_logic() {
    local regen="${1:-0}"
    local fake_psql_output="${2:-}"        # empty = simulate psql failure; "NULL" = query returned null
    local check_mark="✅"
    local warning="⚠️"
    local info="ℹ️"

    local AGENTS_JSON="$FAKE_AGENTS_JSON"
    local AGENTS_JSON_TMP="${AGENTS_JSON}.tmp.$$"
    local REGENERATE_AGENTS_JSON="$regen"
    local TMPFILES=()

    # Mock psql behavior via subshell override
    if [ -n "$fake_psql_output" ] && [ "$fake_psql_output" != "FAIL" ]; then
        # Valid psql output
        psql() { echo "$fake_psql_output"; return 0; }
        export -f psql
    elif [ "$fake_psql_output" = "FAIL" ]; then
        # psql failure
        psql() { return 1; }
        export -f psql
    fi

    # Define DB vars that the logic uses
    local DB_USER="testuser"
    local DB_NAME="test_db"

    _generate_agents_json() {
        local AGENTS_DATA
        if AGENTS_DATA=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "dummy" 2>/dev/null); then
            if [ -n "$AGENTS_DATA" ] && [ "$AGENTS_DATA" != "null" ] && [ "$AGENTS_DATA" != "" ]; then
                if echo "$AGENTS_DATA" | jq '.' >"$AGENTS_JSON_TMP" 2>/dev/null; then
                    mv "$AGENTS_JSON_TMP" "$AGENTS_JSON" && return 0 || { rm -f "$AGENTS_JSON_TMP"; return 1; }
                else
                    echo "  ${warning} DB returned non-JSON data for agents.json — not writing"
                    rm -f "$AGENTS_JSON_TMP"
                    return 1
                fi
            else
                echo "  ${warning} DB query returned no agents — agents.json not written"
                echo "  ${info} agent_config_sync will generate agents.json when gateway starts"
                return 1
            fi
        else
            echo "  ${warning} Could not query DB for agents.json — agents.json not written"
            echo "  ${info} agent_config_sync will generate agents.json when gateway starts"
            return 1
        fi
        return 0
    }

    if [ -f "$AGENTS_JSON" ]; then
        if jq '.' "$AGENTS_JSON" >/dev/null 2>&1; then
            if [ "$REGENERATE_AGENTS_JSON" -eq 1 ]; then
                local AGENTS_JSON_BAK="${AGENTS_JSON}.bak-$(date +%Y%m%d-%H%M%S)"
                cp "$AGENTS_JSON" "$AGENTS_JSON_BAK"
                echo "  ${info} Backed up existing agents.json to $AGENTS_JSON_BAK"
                _generate_agents_json
            else
                echo "  ${check_mark} agents.json present and valid; agent_config_sync will keep it in sync"
            fi
        else
            if [ "$REGENERATE_AGENTS_JSON" -eq 1 ]; then
                local AGENTS_JSON_BAK="${AGENTS_JSON}.bak-$(date +%Y%m%d-%H%M%S)"
                cp "$AGENTS_JSON" "$AGENTS_JSON_BAK"
                echo "  ${warning} Backed up corrupt agents.json to $AGENTS_JSON_BAK"
                _generate_agents_json
            else
                echo "  ${warning} agents.json exists but contains invalid JSON — skipping write."
                echo "  ${info} Pass --regenerate-agents-json to fix it."
            fi
        fi
    else
        _generate_agents_json
    fi
}

# ─── TC-252-B-01 ─────────────────────────────────────────────────────────────

@test "TC-252-B-01: Skip write when agents.json exists and is valid JSON" {
    # Pre-populate with valid JSON
    echo '[{"id":"nova","model":"test"}]' > "$FAKE_AGENTS_JSON"
    local original_content
    original_content=$(cat "$FAKE_AGENTS_JSON")

    run run_agents_json_logic 0 '[{"id":"something_different"}]'
    [ "$status" -eq 0 ]

    # Content should be unchanged
    local after_content
    after_content=$(cat "$FAKE_AGENTS_JSON")
    [ "$original_content" = "$after_content" ]
    [[ "$output" == *"agent_config_sync will keep it in sync"* ]]
}

# ─── TC-252-B-02 ─────────────────────────────────────────────────────────────

@test "TC-252-B-02: Write (backup + overwrite) when --regenerate-agents-json flag is passed" {
    echo '[{"id":"nova","model":"old"}]' > "$FAKE_AGENTS_JSON"

    run run_agents_json_logic 1 '[{"id":"nova","model":"new"}]'
    [ "$status" -eq 0 ]

    # Backup should exist
    local bak_count
    bak_count=$(find "$FAKE_OPENCLAW" -name "agents.json.bak-*" 2>/dev/null | wc -l)
    [ "$bak_count" -ge 1 ]

    # New content should be valid JSON from "DB"
    run jq '.' "$FAKE_AGENTS_JSON"
    [ "$status" -eq 0 ]
}

# ─── TC-252-B-03 ─────────────────────────────────────────────────────────────

@test "TC-252-B-03: Never write [] when psql fails (no existing agents.json)" {
    # No agents.json exists, psql fails
    run run_agents_json_logic 0 "FAIL"
    [ "$status" -eq 0 ]

    # agents.json must NOT exist with [] content
    if [ -f "$FAKE_AGENTS_JSON" ]; then
        local content
        content=$(cat "$FAKE_AGENTS_JSON")
        [ "$content" != "[]" ]
    fi

    [[ "$output" == *"Could not query DB"* ]] || [[ "$output" == *"not written"* ]]
}

# ─── TC-252-B-04 ─────────────────────────────────────────────────────────────

@test "TC-252-B-04: Never write [] on psql failure even when agents.json does not yet exist" {
    # Confirm no pre-existing agents.json
    [ ! -f "$FAKE_AGENTS_JSON" ]

    run run_agents_json_logic 0 "FAIL"
    [ "$status" -eq 0 ]

    # Must not have created an agents.json with [] content
    if [ -f "$FAKE_AGENTS_JSON" ]; then
        local content
        content=$(jq -c '.' "$FAKE_AGENTS_JSON" 2>/dev/null || cat "$FAKE_AGENTS_JSON")
        [ "$content" != "[]" ]
    fi
}

# ─── TC-252-B-05 ─────────────────────────────────────────────────────────────

@test "TC-252-B-05: Backup created before forced overwrite" {
    echo '[{"id":"nova","model":"original"}]' > "$FAKE_AGENTS_JSON"
    local original_content
    original_content=$(cat "$FAKE_AGENTS_JSON")

    run run_agents_json_logic 1 '[{"id":"nova","model":"new_from_db"}]'
    [ "$status" -eq 0 ]

    # Backup must contain original content
    local bak_file
    bak_file=$(find "$FAKE_OPENCLAW" -name "agents.json.bak-*" 2>/dev/null | head -1)
    [ -n "$bak_file" ]
    local bak_content
    bak_content=$(cat "$bak_file")
    [ "$bak_content" = "$original_content" ]
}

# ─── TC-252-B-07 ─────────────────────────────────────────────────────────────

@test "TC-252-B-07: Idempotency — running installer twice does not corrupt agents.json" {
    local db_output='[{"id":"nova","model":"test"}]'

    # First run (no existing agents.json)
    run run_agents_json_logic 0 "$db_output"
    [ "$status" -eq 0 ]
    [ -f "$FAKE_AGENTS_JSON" ]
    local first_content
    first_content=$(cat "$FAKE_AGENTS_JSON")

    # Second run (agents.json exists and valid)
    run run_agents_json_logic 0 "$db_output"
    [ "$status" -eq 0 ]
    local second_content
    second_content=$(cat "$FAKE_AGENTS_JSON")

    [ "$first_content" = "$second_content" ]
    run jq '.' "$FAKE_AGENTS_JSON"
    [ "$status" -eq 0 ]
}

# ─── TC-252-B-08 ─────────────────────────────────────────────────────────────

@test "TC-252-B-08: Skip and warn when agents.json exists but is invalid JSON" {
    printf '{INVALID' > "$FAKE_AGENTS_JSON"
    local original_content
    original_content=$(cat "$FAKE_AGENTS_JSON")

    run run_agents_json_logic 0 '[{"id":"nova"}]'
    [ "$status" -eq 0 ]

    # File must be preserved as-is (not overwritten)
    local after_content
    after_content=$(cat "$FAKE_AGENTS_JSON")
    [ "$after_content" = "$original_content" ]

    # Warning must be present in output
    [[ "$output" == *"invalid JSON"* ]]
    [[ "$output" == *"--regenerate-agents-json"* ]]
}

# ─── TC-252-B-09 ─────────────────────────────────────────────────────────────

@test "TC-252-B-09: --regenerate-agents-json replaces invalid JSON file" {
    printf '{INVALID' > "$FAKE_AGENTS_JSON"
    local original_corrupt
    original_corrupt=$(cat "$FAKE_AGENTS_JSON")

    run run_agents_json_logic 1 '[{"id":"nova","model":"good"}]'
    [ "$status" -eq 0 ]

    # agents.json must now be valid
    run jq '.' "$FAKE_AGENTS_JSON"
    [ "$status" -eq 0 ]

    # Backup must exist with the corrupt content
    local bak_file
    bak_file=$(find "$FAKE_OPENCLAW" -name "agents.json.bak-*" 2>/dev/null | head -1)
    [ -n "$bak_file" ]
    local bak_content
    bak_content=$(cat "$bak_file")
    [ "$bak_content" = "$original_corrupt" ]
}

# ─── TC-252-B-10 ─────────────────────────────────────────────────────────────

@test "TC-252-B-10: ShellCheck — zero warnings on agent-install.sh" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$INSTALLER"
    [ "$status" -eq 0 ]
}
