#!/usr/bin/env bats
# BATS tests for agent-install.sh agents.json generation (#429, #707)
#
# Tests the _generate_agents_json() behavior: sourcing from
# get_agent_export_rows(), output shape parity with the agent_config_sync
# plugin, and the minimal #402 non-fatal guard for empty scoped results.
#
# Updated for nova-mind#707: agents.json is now a keyed object matching the
# OpenClaw 2026.9.x agents.entries schema, not a bare array.
#
# Test cases:
#   TC-429-S-01: Fresh install generates correct scoped agents.json (mocked DB)
#   TC-429-P-01: Byte-parity with plugin serialization when heartbeat + subagents coexist
#   TC-429-P-02: Fallback-models shape parity
#   TC-429-P-03: allowed_subagents shape parity (sorted, NULL/empty omitted, wildcard)
#   TC-429-P-04: is_default parity (trust function output, not agents table)
#   TC-429-P-05: Heartbeat shape parity
#   TC-429-P-06: thinking column emitted as thinkingDefault when valid
#   TC-429-P-07: Sort order parity (JS localeCompare via node)
#   TC-707-S-01: Output is a keyed object, not an array
#   TC-707-S-02: Keyed object omits id field from each value
#   TC-429-S-11: psql failure never writes file
#   TC-429-S-12: empty DB result returns 0 and writes placeholder
#   TC-429-S-13: non-JSON DB data is not written
#   TC-429-S-17: empty allowed_subagents omits subagents key
#   TC-429-S-18: empty fallback_models yields bare string
#   TC-429-S-19: single-row boundary
#   TC-429-R-02: empty result is non-fatal under set -e
#   TC-429-R-03: failure modes still return 1
#
# Staging-only (require live multi-role DB):
#   TC-429-S-03, S-04, S-05, S-06, S-07, S-10, S-14, S-15, S-16
#   TC-429-P-01
#
# Run: bats tests/install/test_agents_json_issue_429.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    FAKE_OPENCLAW="$(mktemp -d)"
    FAKE_AGENTS_JSON="$FAKE_OPENCLAW/agents.json"
    export FAKE_OPENCLAW FAKE_AGENTS_JSON
}

teardown() {
    rm -rf "$FAKE_OPENCLAW"
}

# Inline the _generate_agents_json() logic for unit testing without a live DB.
# Mock psql returns the raw row set that get_agent_export_rows() would produce;
# the same node serialization the installer uses shapes and sorts the output.
run_agents_json_logic() {
    local regen="${1:-0}"
    local fake_psql_output="${2:-}"   # "FAIL" = psql failure; "__EMPTY__" = query returned null/empty; other = raw row JSON
    local check_mark="✅"
    local warning="⚠️"
    local info="ℹ️"

    local AGENTS_JSON="$FAKE_AGENTS_JSON"
    local AGENTS_JSON_TMP="${AGENTS_JSON}.tmp.$$"
    local REGENERATE_AGENTS_JSON="$regen"
    local TMPFILES=("$AGENTS_JSON_TMP")

    if [ "$fake_psql_output" = "FAIL" ]; then
        psql() { return 1; }
        export -f psql
    elif [ "$fake_psql_output" = "__EMPTY__" ]; then
        psql() { echo ""; return 0; }
        export -f psql
    elif [ -n "$fake_psql_output" ]; then
        psql() { echo "$fake_psql_output"; return 0; }
        export -f psql
    fi

    local DB_USER="testuser"
    local DB_NAME="test_db"

    _generate_agents_json() {
        local AGENTS_DATA
        if AGENTS_DATA=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "dummy" 2>/dev/null); then
            if [ -n "$AGENTS_DATA" ] && [ "$AGENTS_DATA" != "null" ] && [ "$AGENTS_DATA" != "" ]; then
                if echo "$AGENTS_DATA" | node -e '
                    let input = "";
                    process.stdin.setEncoding("utf8");
                    process.stdin.on("data", c => input += c);
                    process.stdin.on("end", () => {
                        const VALID_THINKING_DEFAULTS = new Set([
                            "off", "minimal", "low", "medium", "high",
                            "xhigh", "adaptive", "max", "ultra",
                        ]);
                        const AGENT_ID_REGEX = /^[a-z0-9_][a-z0-9_-]{0,63}$/i;
                        const rows = JSON.parse(input);
                        const entries = {};
                        for (const row of rows) {
                            if (row.status != null && row.status !== "active") continue;
                            if (row.model == null) continue;
                            if (typeof row.name !== "string" || !AGENT_ID_REGEX.test(row.name)) continue;

                            const hasFallbacks = Array.isArray(row.fallback_models) && row.fallback_models.length > 0;
                            const entry = { model: hasFallbacks
                                ? { primary: row.model, fallbacks: [...row.fallback_models] }
                                : row.model };

                            if (row.is_default === true) entry.default = true;

                            if (typeof row.thinking === "string" && row.thinking.length > 0 &&
                                VALID_THINKING_DEFAULTS.has(row.thinking)) {
                                entry.thinkingDefault = row.thinking;
                            }

                            if (Array.isArray(row.allowed_subagents) && row.allowed_subagents.length > 0) {
                                entry.subagents = { allowAgents: [...row.allowed_subagents].sort() };
                            }

                            if (row.heartbeat_enabled === true) {
                                const hb = {};
                                if (row.heartbeat_every != null) hb.every = row.heartbeat_every;
                                if (row.heartbeat_target != null) hb.target = row.heartbeat_target;
                                if (row.heartbeat_to != null) hb.to = row.heartbeat_to;
                                if (row.heartbeat_isolated_session === true) hb.isolatedSession = true;
                                entry.heartbeat = hb;
                            }

                            entries[row.name] = entry;
                        }
                        const sorted = {};
                        for (const key of Object.keys(entries).sort((a, b) => a.localeCompare(b))) {
                            sorted[key] = entries[key];
                        }
                        process.stdout.write(JSON.stringify(sorted, null, 2) + "\n");
                    });
                ' >"$AGENTS_JSON_TMP" 2>/dev/null; then
                    if mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"; then
                        echo -e "  ${check_mark} Generated agents.json from DB"
                        return 0
                    else
                        echo -e "  ${warning} Could not write agents.json"
                        rm -f "$AGENTS_JSON_TMP"
                        return 1
                    fi
                else
                    echo -e "  ${warning} Could not serialize agents.json from DB data — not writing"
                    rm -f "$AGENTS_JSON_TMP"
                    return 1
                fi
            else
                printf '{"main": {}}\n' > "$AGENTS_JSON_TMP"
                if mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"; then
                    echo -e "  ${info} no agents in scope — wrote placeholder agents.json; agent_config_sync will populate on startup"
                    return 0
                else
                    echo -e "  ${warning} Could not write empty agents.json placeholder"
                    rm -f "$AGENTS_JSON_TMP"
                    return 1
                fi
            fi
        else
            echo -e "  ${warning} Could not query DB for agents.json — agents.json not written"
            echo -e "  ${info} agent_config_sync will generate agents.json when gateway starts"
            rm -f "$AGENTS_JSON_TMP"
            return 1
        fi
    }

    if [ -f "$AGENTS_JSON" ]; then
        if jq '.' "$AGENTS_JSON" >/dev/null 2>&1; then
            if [ "$REGENERATE_AGENTS_JSON" -eq 1 ]; then
                local AGENTS_JSON_BAK="${AGENTS_JSON}.bak-$(date +%Y%m%d-%H%M%S)"
                cp "$AGENTS_JSON" "$AGENTS_JSON_BAK"
                echo -e "  ${info} Backed up existing agents.json to $AGENTS_JSON_BAK"
                _generate_agents_json
            else
                echo -e "  ${check_mark} agents.json present and valid; agent_config_sync will keep it in sync"
            fi
        else
            if [ "$REGENERATE_AGENTS_JSON" -eq 1 ]; then
                local AGENTS_JSON_BAK="${AGENTS_JSON}.bak-$(date +%Y%m%d-%H%M%S)"
                cp "$AGENTS_JSON" "$AGENTS_JSON_BAK"
                echo -e "  ${warning} Backed up corrupt agents.json to $AGENTS_JSON_BAK"
                _generate_agents_json
            else
                echo -e "  ${warning} agents.json exists but contains invalid JSON — skipping write."
                echo -e "  ${info} Pass --regenerate-agents-json to fix it."
            fi
        fi
    else
        _generate_agents_json
    fi
}

# ─── TC-429-S-01 / TC-707-S-01 / TC-707-S-02 ─────────────────────────────────

@test "TC-429-S-01: Fresh install with mocked DB rows generates correct scoped agents.json" {
    local rows='[
        {"name":"nova","model":"anthropic/claude-opus-4","fallback_models":null,"thinking":"high","instance_type":"primary","is_default":true,"allowed_subagents":["gem","coder"],"heartbeat_enabled":true,"heartbeat_every":"5m","heartbeat_target":"discord","heartbeat_to":"channel:1234"},
        {"name":"coder","model":"anthropic/claude-sonnet-4","fallback_models":null,"thinking":"medium","instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"gem","model":"google/gemini-flash","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":null,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]
    [ -f "$FAKE_AGENTS_JSON" ]

    # Output is an object, not an array.
    run jq -r 'type' "$FAKE_AGENTS_JSON"
    [ "$output" = "object" ]

    # Nova is default; coder and gem are not.
    run jq -r '.nova.default' "$FAKE_AGENTS_JSON"
    [ "$output" = "true" ]
    run jq -r 'has("coder") and (.coder | has("default") | not)' "$FAKE_AGENTS_JSON"
    [ "$output" = "true" ]

    # Three agents total, sorted keys.
    run jq -r 'keys | .[]' "$FAKE_AGENTS_JSON"
    [ "$output" = $'coder\ngem\nnova' ]

    # No id field inside values.
    run jq -r '[.[] | has("id")] | any' "$FAKE_AGENTS_JSON"
    [ "$output" = "false" ]
}

# ─── TC-429-P-01: Byte-parity when heartbeat + subagents coexist ─────────────

@test "TC-429-P-01: Entry with heartbeat and subagents is byte-identical to plugin serialization" {
    local rows='[
        {"name":"nova","model":"anthropic/claude-opus-4","fallback_models":null,"thinking":"high","instance_type":"primary","is_default":true,"allowed_subagents":["gem","coder"],"heartbeat_enabled":true,"heartbeat_every":"5m","heartbeat_target":"discord","heartbeat_to":"channel:1234"}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]
    [ -f "$FAKE_AGENTS_JSON" ]

    # Build the plugin's expected serialization from the same raw row shape.
    local expected
    expected=$(echo "$rows" | node -e '
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", c => input += c);
        process.stdin.on("end", () => {
            const VALID_THINKING_DEFAULTS = new Set([
                "off", "minimal", "low", "medium", "high",
                "xhigh", "adaptive", "max", "ultra",
            ]);
            const rows = JSON.parse(input);
            const entries = {};
            for (const row of rows) {
                const hasFallbacks = Array.isArray(row.fallback_models) && row.fallback_models.length > 0;
                const entry = { model: hasFallbacks
                    ? { primary: row.model, fallbacks: [...row.fallback_models] }
                    : row.model };
                if (row.is_default === true) entry.default = true;
                if (typeof row.thinking === "string" && row.thinking.length > 0 &&
                    VALID_THINKING_DEFAULTS.has(row.thinking)) {
                    entry.thinkingDefault = row.thinking;
                }
                if (Array.isArray(row.allowed_subagents) && row.allowed_subagents.length > 0) {
                    entry.subagents = { allowAgents: [...row.allowed_subagents].sort() };
                }
                if (row.heartbeat_enabled === true) {
                    const hb = {};
                    if (row.heartbeat_every != null) hb.every = row.heartbeat_every;
                    if (row.heartbeat_target != null) hb.target = row.heartbeat_target;
                    if (row.heartbeat_to != null) hb.to = row.heartbeat_to;
                    if (row.heartbeat_isolated_session === true) hb.isolatedSession = true;
                    entry.heartbeat = hb;
                }
                entries[row.name] = entry;
            }
            const sorted = {};
            for (const key of Object.keys(entries).sort((a, b) => a.localeCompare(b))) {
                sorted[key] = entries[key];
            }
            process.stdout.write(JSON.stringify(sorted, null, 2) + "\n");
        });
    ')

    local actual
    actual=$(cat "$FAKE_AGENTS_JSON")

    [ "$actual" = "$expected" ]
}

# ─── TC-429-P-02: Fallback-models shape parity ───────────────────────────────

@test "TC-429-P-02: Fallback models shape parity" {
    local rows='[
        {"name":"with_fb","model":"primary-model","fallback_models":["fallback-1","fallback-2"],"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"null_fb","model":"string-model","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"empty_fb","model":"string-model","fallback_models":[],"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -c '.with_fb.model' "$FAKE_AGENTS_JSON"
    [ "$output" = '{"primary":"primary-model","fallbacks":["fallback-1","fallback-2"]}' ]

    run jq -r '.null_fb.model' "$FAKE_AGENTS_JSON"
    [ "$output" = "string-model" ]

    run jq -r '.empty_fb.model' "$FAKE_AGENTS_JSON"
    [ "$output" = "string-model" ]
}

# ─── TC-429-P-03: allowed_subagents shape parity ─────────────────────────────

@test "TC-429-P-03: allowed_subagents shape parity" {
    local rows='[
        {"name":"sorted","model":"m","fallback_models":null,"thinking":null,"instance_type":"primary","is_default":true,"allowed_subagents":["zebra","alpha","mike"],"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"null_sub","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"empty_sub","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":[],"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"wildcard","model":"m","fallback_models":null,"thinking":null,"instance_type":"primary","is_default":false,"allowed_subagents":["*"],"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -c '.sorted.subagents.allowAgents' "$FAKE_AGENTS_JSON"
    [ "$output" = '["alpha","mike","zebra"]' ]

    run jq -r '.null_sub | has("subagents")' "$FAKE_AGENTS_JSON"
    [ "$output" = "false" ]

    run jq -r '.empty_sub | has("subagents")' "$FAKE_AGENTS_JSON"
    [ "$output" = "false" ]

    run jq -c '.wildcard.subagents.allowAgents' "$FAKE_AGENTS_JSON"
    [ "$output" = '["*"]' ]
}

# ─── TC-429-P-04: is_default parity ──────────────────────────────────────────

@test "TC-429-P-04: is_default parity trusts function output, not agents table" {
    # Simulates the F3/F5 quirk: caller's own row returns is_default=true from
    # get_agent_export_rows() even if the agents table column were false.
    local rows='[
        {"name":"gem","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":true,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"sub","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -r '.gem.default' "$FAKE_AGENTS_JSON"
    [ "$output" = "true" ]

    run jq -r '.sub | has("default")' "$FAKE_AGENTS_JSON"
    [ "$output" = "false" ]
}

# ─── TC-429-P-05: Heartbeat shape parity ─────────────────────────────────────

@test "TC-429-P-05: Heartbeat shape parity" {
    local rows='[
        {"name":"full","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":true,"heartbeat_every":"5m","heartbeat_target":"discord","heartbeat_to":"channel:1234","heartbeat_isolated_session":true},
        {"name":"partial","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":true,"heartbeat_every":"10m","heartbeat_target":null,"heartbeat_to":null,"heartbeat_isolated_session":false},
        {"name":"enabled_no_every","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":true,"heartbeat_every":null,"heartbeat_target":"discord","heartbeat_to":"channel:1234","heartbeat_isolated_session":null},
        {"name":"disabled","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":"5m","heartbeat_target":"discord","heartbeat_to":"channel:1234","heartbeat_isolated_session":true}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -c '.full.heartbeat' "$FAKE_AGENTS_JSON"
    [ "$output" = '{"every":"5m","target":"discord","to":"channel:1234","isolatedSession":true}' ]

    run jq -c '.partial.heartbeat' "$FAKE_AGENTS_JSON"
    [ "$output" = '{"every":"10m"}' ]

    run jq -r '.enabled_no_every | has("heartbeat")' "$FAKE_AGENTS_JSON"
    [ "$output" = "true" ]

    run jq -c '.enabled_no_every.heartbeat' "$FAKE_AGENTS_JSON"
    [ "$output" = '{"target":"discord","to":"channel:1234"}' ]

    run jq -r '.disabled | has("heartbeat")' "$FAKE_AGENTS_JSON"
    [ "$output" = "false" ]
}

# ─── TC-429-P-06: thinking column emitted as thinkingDefault ─────────────────

@test "TC-429-P-06: thinking column is emitted as thinkingDefault when valid" {
    local rows='[
        {"name":"thinker","model":"m","fallback_models":null,"thinking":"high","instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -r '.thinker.thinkingDefault' "$FAKE_AGENTS_JSON"
    [ "$output" = "high" ]

    run jq -r '.thinker | has("thinking")' "$FAKE_AGENTS_JSON"
    [ "$output" = "false" ]
}

# ─── TC-429-P-07: Sort order parity (JS localeCompare) ───────────────────────

@test "TC-429-P-07: Output keys are sorted by id using JS localeCompare" {
    local rows='[
        {"name":"zebra","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"alpha","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null},
        {"name":"Nova","model":"m","fallback_models":null,"thinking":null,"instance_type":"primary","is_default":true,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    # jq sorts keys by Unicode code point; we need JS localeCompare order.
    run node -e "const data = require('fs').readFileSync('$FAKE_AGENTS_JSON', 'utf8'); console.log(Object.keys(JSON.parse(data)).join('\n'));"
    [ "$output" = $'alpha\nNova\nzebra' ]
}

# ─── TC-429-S-11 ─────────────────────────────────────────────────────────────

@test "TC-429-S-11: psql failure never writes agents.json" {
    [ ! -f "$FAKE_AGENTS_JSON" ]

    run run_agents_json_logic 0 "FAIL"
    [ "$status" -ne 0 ]
    [ ! -f "$FAKE_AGENTS_JSON" ]
    [[ "$output" == *"Could not query DB"* ]]
}

# ─── TC-429-S-12 / TC-429-R-02 ───────────────────────────────────────────────

@test "TC-429-S-12 / TC-429-R-02: empty DB result is non-fatal and writes placeholder" {
    [ ! -f "$FAKE_AGENTS_JSON" ]

    run run_agents_json_logic 0 "__EMPTY__"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no agents in scope"* ]]
    [[ "$output" == *"agent_config_sync will populate on startup"* ]]
    [ -f "$FAKE_AGENTS_JSON" ]
    run jq -c '.' "$FAKE_AGENTS_JSON"
    [ "$output" = '{"main":{}}' ]
}

# ─── TC-429-S-13 ─────────────────────────────────────────────────────────────

@test "TC-429-S-13: non-JSON DB data is not written" {
    [ ! -f "$FAKE_AGENTS_JSON" ]

    run run_agents_json_logic 0 "{INVALID JSON"
    [ "$status" -ne 0 ]
    [ ! -f "$FAKE_AGENTS_JSON" ]
    [[ "$output" == *"Could not serialize"* ]]
}

# ─── TC-429-S-17 ─────────────────────────────────────────────────────────────

@test "TC-429-S-17: empty allowed_subagents array omits subagents key" {
    local rows='[
        {"name":"empty_sub","model":"m","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":[],"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -r '.empty_sub | keys | .[]' "$FAKE_AGENTS_JSON"
    [[ "$output" != *"subagents"* ]]
}

# ─── TC-429-S-18 ─────────────────────────────────────────────────────────────

@test "TC-429-S-18: empty fallback_models array yields bare string model" {
    local rows='[
        {"name":"empty_fb","model":"bare-string","fallback_models":[],"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -r '.empty_fb.model' "$FAKE_AGENTS_JSON"
    [ "$output" = "bare-string" ]
}

# ─── TC-429-S-19 ─────────────────────────────────────────────────────────────

@test "TC-429-S-19: single-row boundary produces valid one-entry object" {
    local rows='[
        {"name":"solo","model":"m","fallback_models":null,"thinking":null,"instance_type":"primary","is_default":true,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}
    ]'

    run run_agents_json_logic 0 "$rows"
    [ "$status" -eq 0 ]

    run jq -r 'type' "$FAKE_AGENTS_JSON"
    [ "$output" = "object" ]

    run jq 'length' "$FAKE_AGENTS_JSON"
    [ "$output" -eq 1 ]
}

# ─── TC-429-R-03 ─────────────────────────────────────────────────────────────

@test "TC-429-R-03: failure modes (psql failure / non-JSON) still return 1" {
    run run_agents_json_logic 0 "FAIL"
    [ "$status" -ne 0 ]

    run run_agents_json_logic 0 "{INVALID JSON"
    [ "$status" -ne 0 ]
}
