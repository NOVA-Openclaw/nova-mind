# Test Cases — Issue #273: Heartbeat config in agents.json

## TC-1: Agent with heartbeat enabled + full config
**Input row:** `{ name: "nova", heartbeat_enabled: true, heartbeat_every: "5m", heartbeat_target: "discord", heartbeat_to: "channel:123" }`
**Expected:** Entry includes `heartbeat: { every: "5m", target: "discord", to: "channel:123" }`

## TC-2: Agent with heartbeat explicitly disabled
**Input row:** `{ name: "scout", heartbeat_enabled: false, heartbeat_every: null, heartbeat_target: null, heartbeat_to: null }`
**Expected:** Entry includes `heartbeat: false`

## TC-3: Agent with heartbeat_enabled = null (legacy/unset)
**Input row:** `{ name: "legacy", heartbeat_enabled: null }`
**Expected:** Entry does NOT include a `heartbeat` key (omitted entirely)

## TC-4: heartbeat_enabled = true but heartbeat_every is null
**Input row:** `{ name: "misconfigured", heartbeat_enabled: true, heartbeat_every: null, heartbeat_target: "discord", heartbeat_to: "channel:123" }`
**Expected:** Entry includes `heartbeat: false` (enabled but no interval = effectively disabled)

## TC-5: heartbeat_enabled = true with partial config (no target/to)
**Input row:** `{ name: "partial", heartbeat_enabled: true, heartbeat_every: "10m", heartbeat_target: null, heartbeat_to: null }`
**Expected:** Entry includes `heartbeat: { every: "10m" }` (only non-null fields emitted)

## TC-6: Mixed agents in same batch
**Input rows:** nova (enabled), scout (disabled), legacy (null)
**Expected:** Each agent has correct heartbeat config per TC-1/TC-2/TC-3

## TC-7: Existing fields unaffected
**Input row:** Agent with model, fallbacks, default, subagents, AND heartbeat config
**Expected:** All existing fields (id, model, default, subagents) are identical to pre-change output; heartbeat is additive only

## TC-8: End-to-end sync round-trip
**Action:** Update heartbeat config in DB → trigger NOTIFY → check agents.json
**Expected:** agents.json reflects the heartbeat config from the DB
