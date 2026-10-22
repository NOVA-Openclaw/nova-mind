#!/usr/bin/env bats
# BATS tests for nova-mind #775: per-agent fallback DB must resolve under the
# runtime user, not via systemd %u specifiers in Environment= lines.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SERVICE_FILE="$REPO_ROOT/cognition/systemd/agent-spawner.service"
CATCHUP_SCRIPT="$REPO_ROOT/memory/scripts/memory-catchup.sh"

@test "TC-775-001: agent-spawner.service has no %u in Environment= lines" {
    run grep -E '^Environment=.*%u' "$SERVICE_FILE"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-775-002: agent-spawner.service resolves NOVA_DB via User= wrapper" {
    run grep -E '^ExecStart=' "$SERVICE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolve_agent_db"* ]]
    [[ "$output" == *"NOVA_DB="* ]]
    [[ "$output" == *"NOVA_DB_USER="* ]]
}

@test "TC-775-003: memory-catchup.sh sources pg-env.sh and resolve_agent_db" {
    run grep -E 'pg-env\.sh|resolve_agent_db' "$CATCHUP_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pg-env.sh"* ]]
    [[ "$output" == *"resolve_agent_db"* ]]
}

@test "TC-775-004: memory-catchup.sh no longer hardcodes psql nova_memory" {
    run grep -E 'psql[[:space:]]+nova_memory' "$CATCHUP_SCRIPT"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}
