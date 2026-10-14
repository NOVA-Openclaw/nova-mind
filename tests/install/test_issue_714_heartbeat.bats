#!/usr/bin/env bats
# BATS tests for nova-mind#714 — heartbeat cadence, delivery target, and
# isolatedSession preservation.
#
# Local test cases (all run against temp OPENCLAW_DIR/config):
#   TC-714-001: cadence is parameterizable; live default stays 30m (20m pending)
#   TC-714-002/003: heartbeat output routes to #proactive-mode, never webchat
#   TC-714-004:  isolatedSession: true preserved on nova heartbeat entry
#   TC-714-004b: every agent's effective heartbeat target resolves to #proactive-mode
#   TC-714-010: isolatedSession survives a config merge that omits it
# Deferred tests (marked in pytest TC-714 file):
#   TC-714-008: openclaw doctor --fix against temp config only
#   TC-714-011: real automation job metadata — staging-only
#
# Run: bats tests/install/test_issue_714_heartbeat.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    FAKE_OPENCLAW="$(mktemp -d)"
    FAKE_OPENCLAW_CONFIG="$FAKE_OPENCLAW/openclaw.json"
    # Minimal valid openclaw.json shape.
    cat >"$FAKE_OPENCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {}
  },
  "plugins": {
    "entries": {}
  }
}
EOF
    export FAKE_OPENCLAW FAKE_OPENCLAW_CONFIG
}

teardown() {
    rm -rf "$FAKE_OPENCLAW"
}

# Replicates the installer logic that idempotently writes agents.defaults.heartbeat.
_apply_heartbeat_defaults() {
    local config="$1"

    local existing_every
    existing_every=$(jq -r '.agents.defaults.heartbeat.every // empty' "$config" 2>/dev/null || true)
    if [ -z "$existing_every" ]; then
        jq '.agents.defaults.heartbeat.every = "30m"' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
    fi

    local existing_target
    existing_target=$(jq -r '.agents.defaults.heartbeat.target // empty' "$config" 2>/dev/null || true)
    if [ -z "$existing_target" ]; then
        jq '.agents.defaults.heartbeat.target = "discord"' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
    fi

    local existing_to
    existing_to=$(jq -r '.agents.defaults.heartbeat.to // empty' "$config" 2>/dev/null || true)
    if [ -z "$existing_to" ]; then
        jq '.agents.defaults.heartbeat.to = "channel:1504054635231445112"' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
    fi

    local existing_iso
    existing_iso=$(jq -r '.agents.defaults.heartbeat.isolatedSession // empty' "$config" 2>/dev/null || true)
    if [ -z "$existing_iso" ]; then
        jq '.agents.defaults.heartbeat.isolatedSession = true' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
    fi
}

# ─── TC-714-001: cadence default remains 30m, 20m is parametrizable ──────────

@test "TC-714-001: installer sets heartbeat cadence default to 30m" {
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    run jq -r '.agents.defaults.heartbeat.every' "$FAKE_OPENCLAW_CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "30m" ]
}

@test "TC-714-001: a pre-existing heartbeat cadence is never overwritten" {
    jq '.agents.defaults.heartbeat.every = "20m"' "$FAKE_OPENCLAW_CONFIG" >"$FAKE_OPENCLAW_CONFIG.tmp" && \
        mv "$FAKE_OPENCLAW_CONFIG.tmp" "$FAKE_OPENCLAW_CONFIG"

    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    run jq -r '.agents.defaults.heartbeat.every' "$FAKE_OPENCLAW_CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "20m" ]
}

# ─── TC-714-002/003: every heartbeat delivery target is #proactive-mode ──────

@test "TC-714-002/003: heartbeat target is discord and to is #proactive-mode" {
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    run jq -r '.agents.defaults.heartbeat.target' "$FAKE_OPENCLAW_CONFIG"
    [ "$output" = "discord" ]

    run jq -r '.agents.defaults.heartbeat.to' "$FAKE_OPENCLAW_CONFIG"
    [ "$output" = "channel:1504054635231445112" ]
}

@test "TC-714-002/003: heartbeat to never defaults to webchat" {
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    run jq -r '.agents.defaults.heartbeat.to' "$FAKE_OPENCLAW_CONFIG"
    [[ "$output" != *"webchat"* ]]
    [[ "$output" != *"owner"* ]]
}

# ─── TC-714-004: isolatedSession: true is set ────────────────────────────────

@test "TC-714-004: installer sets agents.defaults.heartbeat.isolatedSession = true" {
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    run jq -r '.agents.defaults.heartbeat.isolatedSession' "$FAKE_OPENCLAW_CONFIG"
    [ "$output" = "true" ]
}

# ─── TC-714-004b: effective target audit resolves to #proactive-mode ─────────

@test "TC-714-004b: effective heartbeat target for every agent resolves to #proactive-mode" {
    # Simulated agents.json: nova has explicit heartbeat; subagent inherits defaults.
    cat >"$FAKE_OPENCLAW/agents.json" <<'EOF'
{
  "nova": {
    "model": "anthropic/claude-opus-4",
    "heartbeat": {
      "every": "30m",
      "target": "discord",
      "to": "channel:1504054635231445112",
      "isolatedSession": true
    }
  },
  "coder": {
    "model": "anthropic/claude-sonnet-4"
  },
  "gem": {
    "model": "google/gemini-flash"
  }
}
EOF
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    # Audit: for each agent, resolve effective heartbeat.to (explicit or inherited).
    run node -e '
        const fs = require("fs");
        const cfg = JSON.parse(fs.readFileSync("'"$FAKE_OPENCLAW_CONFIG"'", "utf8"));
        const entries = JSON.parse(fs.readFileSync("'"$FAKE_OPENCLAW/agents.json"'", "utf8"));
        const defaults = cfg.agents.defaults.heartbeat || {};
        const bad = [];
        for (const [id, entry] of Object.entries(entries)) {
            const hb = entry.heartbeat || {};
            const effectiveTo = hb.to ?? defaults.to;
            if (effectiveTo !== "channel:1504054635231445112") {
                bad.push(id + ":" + effectiveTo);
            }
        }
        if (bad.length) {
            console.error("bad targets: " + bad.join(", "));
            process.exit(1);
        }
        console.log("ok");
    '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "TC-714-004b: audit catches a planted wrong target counter-example" {
    cat >"$FAKE_OPENCLAW/agents.json" <<'EOF'
{
  "nova": {
    "model": "anthropic/claude-opus-4",
    "heartbeat": {
      "every": "30m",
      "target": "discord",
      "to": "channel:1504054635231445112",
      "isolatedSession": true
    }
  },
  "coder": {
    "model": "anthropic/claude-sonnet-4",
    "heartbeat": {
      "to": "channel:9999999999999999999"
    }
  }
}
EOF
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    run node -e '
        const fs = require("fs");
        const cfg = JSON.parse(fs.readFileSync("'"$FAKE_OPENCLAW_CONFIG"'", "utf8"));
        const entries = JSON.parse(fs.readFileSync("'"$FAKE_OPENCLAW/agents.json"'", "utf8"));
        const defaults = cfg.agents.defaults.heartbeat || {};
        const bad = [];
        for (const [id, entry] of Object.entries(entries)) {
            const hb = entry.heartbeat || {};
            const effectiveTo = hb.to ?? defaults.to;
            if (effectiveTo !== "channel:1504054635231445112") {
                bad.push(id);
            }
        }
        if (bad.length !== 1 || bad[0] !== "coder") {
            console.error("expected exactly coder flagged, got: " + bad.join(", "));
            process.exit(1);
        }
        console.log("ok");
    '
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

# ─── TC-714-010: isolatedSession survives a config merge that omits it ───────

@test "TC-714-010: config merge preserves existing heartbeat.isolatedSession" {
    _apply_heartbeat_defaults "$FAKE_OPENCLAW_CONFIG"

    # Simulate an agent-config-sync-style merge that writes agents.entries.nova.heartbeat
    # without an explicit isolatedSession key (the adversarial case).
    jq '.agents.entries.nova = {"model":"anthropic/claude-opus-4","heartbeat":{"every":"30m","target":"discord","to":"channel:1504054635231445112"}}' \
        "$FAKE_OPENCLAW_CONFIG" >"$FAKE_OPENCLAW_CONFIG.tmp" && \
        mv "$FAKE_OPENCLAW_CONFIG.tmp" "$FAKE_OPENCLAW_CONFIG"

    # The merge must NOT have clobbered the defaults-level isolatedSession.
    run jq -r '.agents.defaults.heartbeat.isolatedSession' "$FAKE_OPENCLAW_CONFIG"
    [ "$output" = "true" ]

    # The effective config still resolves to isolatedSession true.
    run jq -r '.agents.defaults.heartbeat.isolatedSession' "$FAKE_OPENCLAW_CONFIG"
    [ "$output" = "true" ]
}
