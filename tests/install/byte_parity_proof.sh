#!/usr/bin/env bash
# Byte-parity proof for #429 fix round: installer Node step vs plugin buildAgentsList.
# Simulates PostgreSQL's jsonb canonical key order for an entry with both heartbeat
# and subagents, runs it through the installer's serialization step, and compares
# the result to the agent_config_sync plugin's buildAgentsList() output.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/cognition/focus/agent-config-sync"
INSTALLER_NODE_SCRIPT='
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
    const rows = JSON.parse(input);
    const entries = {};
    for (const row of rows) {
        // #770 — legacy default marker is never emitted under agents.ownership=explicit.
        const entry = { model: row.model };
        if (typeof row.thinking === "string" && row.thinking.length > 0) entry.thinkingDefault = row.thinking;
        if (row.subagents) entry.subagents = row.subagents;
        if (row.heartbeat) {
            const hb = { every: row.heartbeat.every };
            if (row.heartbeat.target) hb.target = row.heartbeat.target;
            if (row.heartbeat.to) hb.to = row.heartbeat.to;
            entry.heartbeat = hb;
        }
        entries[row.id] = entry;
    }
    const sorted = {};
    for (const key of Object.keys(entries).sort((a, b) => a.localeCompare(b))) {
        sorted[key] = entries[key];
    }
    process.stdout.write(JSON.stringify(sorted, null, 2) + "\n");
});
'

# Fixture: one agent with both heartbeat and subagents, deliberately ordered in
# PostgreSQL jsonb canonical key order (length, then lexicographic) to prove the
# installer step reconstructs plugin insertion order rather than preserving it.
PG_ORDERED_INPUT='[
  {
    "id": "nova",
    "model": "anthropic/claude-opus-4",
    "thinking": "high",
    "heartbeat": {
      "to": "channel:1234",
      "every": "5m",
      "target": "discord"
    },
    "subagents": {
      "allowAgents": ["coder", "gem"]
    }
  }
]'

# Installer output (reconstruction + sort + Node JSON.stringify)
INSTALLER_OUT="$(printf '%s' "$PG_ORDERED_INPUT" | node -e "$INSTALLER_NODE_SCRIPT")"

# Plugin output (buildAgentsList().entries from the same raw DB row shape)
PLUGIN_OUT="$(cd "$PLUGIN_DIR" && npx tsx -e '
import { buildAgentsList } from "./src/sync.ts";
const rows = [
  {
    name: "nova",
    model: "anthropic/claude-opus-4",
    fallback_models: null,
    thinking: "high",
    instance_type: "primary",
    is_default: true,
    allowed_subagents: ["gem", "coder"],
    heartbeat_enabled: true,
    heartbeat_every: "5m",
    heartbeat_target: "discord",
    heartbeat_to: "channel:1234",
  },
];
const data = buildAgentsList(rows);
process.stdout.write(JSON.stringify(data.entries, null, 2) + "\n");
')"

INSTALLER_FILE="$(mktemp)"
PLUGIN_FILE="$(mktemp)"
trap 'rm -f "$INSTALLER_FILE" "$PLUGIN_FILE"' EXIT
printf '%s\n' "$INSTALLER_OUT" > "$INSTALLER_FILE"
printf '%s\n' "$PLUGIN_OUT" > "$PLUGIN_FILE"

if diff -u "$PLUGIN_FILE" "$INSTALLER_FILE"; then
    echo "BYTE-PARITY OK: installer output is byte-identical to plugin serialization"
else
    echo "BYTE-PARITY FAIL" >&2
    exit 1
fi
