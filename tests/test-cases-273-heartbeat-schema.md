# Test Cases — Issue #273: Heartbeat Schema Fix (omit key when disabled)

## Summary

**Bug:** `buildAgentsList()` emits `"heartbeat": false` (boolean) for agents with heartbeat disabled.
**OpenClaw schema requirement:** `heartbeat` must be an object or **omitted entirely** — never a boolean.
**Fix:** For `heartbeat_enabled = false | NULL`, omit the `heartbeat` key entirely from the agent entry.

---

## Part 1: Updates to Existing Tests

### TC-262-U-02 (Updated)
**Was:** "heartbeat_enabled=false → emits `heartbeat: false`"
**Now:** "heartbeat_enabled=false → heartbeat key is ABSENT from entry"

**Preconditions:**
- Single `AgentRow` with `heartbeat_enabled: false`, all heartbeat sub-fields null.

**Inputs:**
```ts
makeAgentRow("coder", false)
```

**Updated Assertions (replacing old assertions):**
1. `entry.heartbeat` is `undefined`
2. `Object.prototype.hasOwnProperty.call(entry, "heartbeat")` is `false`
3. `typeof entry.heartbeat !== "boolean"` — heartbeat is never a boolean

**Pass criteria:** All three assertions pass.
**Fail criteria:** Entry has a `heartbeat` property at all.

---

### TC-262-U-03 (Updated)
**Was:** "heartbeat_enabled=null → emits `heartbeat: false`"
**Now:** "heartbeat_enabled=null → heartbeat key is ABSENT from entry"

**Preconditions:**
- Single `AgentRow` with `heartbeat_enabled: null`, all heartbeat sub-fields null.

**Inputs:**
```ts
makeAgentRow("gem", null)
```

**Updated Assertions (replacing old assertions):**
1. `entry.heartbeat` is `undefined`
2. `Object.prototype.hasOwnProperty.call(entry, "heartbeat")` is `false`
3. `typeof entry.heartbeat !== "boolean"` — heartbeat is never a boolean

**Pass criteria:** All three assertions pass.
**Fail criteria:** Entry has a `heartbeat` property at all.

---

### TC-262-U-04 (Updated)
**Was:** "ALL agents in list have explicit heartbeat key" — asserted `hasOwnProperty("heartbeat")` for every entry, including disabled ones.
**Now:** "heartbeat key present IFF enabled; absent when disabled or null"

**Preconditions:**
- Mixed rows: one with `heartbeat_enabled=true`, one `false`, one `null`.

**Inputs:**
```ts
[
  makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
  makeAgentRow("coder", false),
  makeAgentRow("gem", null),
]
```

**Updated Assertions (replacing old assertions):**
1. nova entry: `Object.prototype.hasOwnProperty.call(entry, "heartbeat")` is `true`
2. nova entry: `typeof entry.heartbeat === "object"` (not boolean)
3. coder entry: `Object.prototype.hasOwnProperty.call(entry, "heartbeat")` is `false`
4. coder entry: `entry.heartbeat === undefined`
5. gem entry: `Object.prototype.hasOwnProperty.call(entry, "heartbeat")` is `false`
6. gem entry: `entry.heartbeat === undefined`

**Pass criteria:** All six assertions pass.
**Fail criteria:** Any disabled agent has a `heartbeat` key, or any enabled agent lacks one.

---

## Part 2: New Test Cases

### TC-273-U-01: Boolean guard — no agent entry ever has `typeof heartbeat === "boolean"`
**Category:** Schema compliance guard
**Design method:** Equivalence partitioning — any row configuration must never produce a boolean heartbeat

**Preconditions:** None

**Inputs:** Build a list from all three `heartbeat_enabled` states plus an agent with the field absent:
```ts
[
  makeAgentRow("nova",    true,  "5m", "discord", "channel:1234", true),
  makeAgentRow("coder",   false),
  makeAgentRow("gem",     null),
  {
    name: "iris",
    model: "anthropic/claude-sonnet-4",
    fallback_models: null,
    thinking: null,
    instance_type: "subagent",
    is_default: false,
    allowed_subagents: null,
    // heartbeat_enabled field entirely absent (undefined)
  },
]
```

**Expected outcome:**
- `buildAgentsList()` returns 4 entries
- For every entry: `typeof entry.heartbeat !== "boolean"`
- No entry has `entry.heartbeat === false`
- No entry has `entry.heartbeat === true`

**Pass criteria:** Loop over all entries asserts `typeof heartbeat !== "boolean"` (undefined is acceptable for disabled agents; object is acceptable for enabled agents).
**Fail criteria:** Any entry has `typeof entry.heartbeat === "boolean"`.

---

### TC-273-U-02: Schema compliance — heartbeat values are objects or undefined, never false/null/true
**Category:** Schema compliance, exhaustive partition check
**Design method:** Equivalence partitioning across all valid `heartbeat_enabled` values

**Inputs:** 5 rows covering every meaningful partition:
```ts
[
  makeAgentRow("agent-enabled",   true,  "5m", "discord", "ch:123"),  // enabled, all fields
  makeAgentRow("agent-partial",   true,  "1m", null, null),            // enabled, partial fields
  makeAgentRow("agent-min",       true,  null, null, null),            // enabled, no sub-fields
  makeAgentRow("agent-false",     false),                               // disabled explicit false
  makeAgentRow("agent-null",      null),                                // disabled null
]
```

**Expected outcomes:**
| Agent          | heartbeat key present? | type      | value             |
|----------------|------------------------|-----------|-------------------|
| agent-enabled  | YES                    | object    | `{every, target, to}` |
| agent-partial  | YES                    | object    | `{every: "1m"}`   |
| agent-min      | YES                    | object    | `{}`              |
| agent-false    | NO                     | undefined | `undefined`       |
| agent-null     | NO                     | undefined | `undefined`       |

**Assertions:**
1. agent-enabled: `hasOwnProperty("heartbeat")` true, `typeof heartbeat === "object"`, not null
2. agent-partial: `hasOwnProperty("heartbeat")` true, `typeof heartbeat === "object"`, only `every` key present
3. agent-min: `hasOwnProperty("heartbeat")` true, `deepStrictEqual(heartbeat, {})`
4. agent-false: `hasOwnProperty("heartbeat")` false, `heartbeat === undefined`
5. agent-null: `hasOwnProperty("heartbeat")` false, `heartbeat === undefined`

**Pass criteria:** All five assertions pass.
**Fail criteria:** Any disabled agent has a heartbeat key, or any enabled agent lacks one, or any heartbeat value is a boolean.

---

### TC-273-U-03: Mixed scenario — enabled agents get objects, disabled/null agents omit the key
**Category:** Integration-style scenario, primary regression test for #273
**Design method:** Mixed-state scenario

**Preconditions:** None

**Inputs:**
```ts
[
  makeAgentRow("nova",    true,  "5m",  "discord",  "channel:1234", true),
  makeAgentRow("coder",   true,  "10m", "slack",    "channel:5678"),
  makeAgentRow("gem",     false),
  makeAgentRow("scout",   null),
  makeAgentRow("iris",    true,  null,  null,        null),
]
```

**Expected outcomes:**
- `nova`: heartbeat present, value `{every: "5m", target: "discord", to: "channel:1234"}`
- `coder`: heartbeat present, value `{every: "10m", target: "slack", to: "channel:5678"}`
- `gem`: heartbeat key ABSENT
- `scout`: heartbeat key ABSENT
- `iris`: heartbeat present, value `{}`

**Assertions (5 agents, 9 total):**
1. nova heartbeat: `deepStrictEqual({every:"5m", target:"discord", to:"channel:1234"})`
2. coder heartbeat: `deepStrictEqual({every:"10m", target:"slack", to:"channel:5678"})`
3. gem: `!hasOwnProperty("heartbeat")` AND `typeof gem.heartbeat === "undefined"`
4. scout: `!hasOwnProperty("heartbeat")` AND `typeof scout.heartbeat === "undefined"`
5. iris: `hasOwnProperty("heartbeat")` AND `deepStrictEqual(iris.heartbeat, {})`
6. All enabled agents: `typeof heartbeat === "object"` (not boolean)
7. All disabled agents: `heartbeat === undefined`
8. Count of entries with heartbeat key: 3 (nova, coder, iris)
9. Count of entries without heartbeat key: 2 (gem, scout)

**Pass criteria:** All 9 assertions pass.
**Fail criteria:** Any disabled agent entry contains `heartbeat` key, or JSON output contains `"heartbeat":false`.

---

### TC-273-U-04: JSON serialization guard — `JSON.stringify` output never contains `"heartbeat":false`
**Category:** Schema output compliance, end-to-end serialization
**Design method:** Black-box output validation

**Motivation:** Even if the TypeScript object omits the key, a type-assert or default value bug could cause `heartbeat: false` to appear in JSON output. This test checks the serialized form.

**Preconditions:** None

**Inputs:**
```ts
[
  makeAgentRow("nova",  true,  "5m", "discord", "channel:1234", true),
  makeAgentRow("coder", false),
  makeAgentRow("gem",   null),
]
```

**Steps:**
1. Call `buildAgentsList(rows)`
2. Call `JSON.stringify(result)` on the output

**Expected outcome:**
- The resulting JSON string does NOT contain the substring `"heartbeat":false`
- The resulting JSON string does NOT contain the substring `"heartbeat": false`
- The resulting JSON string DOES contain `"heartbeat"` exactly once (for nova's enabled entry)
- The `"heartbeat"` occurrence in JSON is followed by `{`, not `false`

**Assertions:**
1. `!jsonStr.includes('"heartbeat":false')`
2. `!jsonStr.includes('"heartbeat": false')`
3. `(jsonStr.match(/"heartbeat"/g) || []).length === 1`
4. The match in jsonStr is followed by `:{` (an object), never `:false`

**Pass criteria:** All 4 assertions pass.
**Fail criteria:** The serialized JSON contains `"heartbeat":false` or `"heartbeat": false` anywhere.

---

### TC-273-U-05: TypeScript type guard — heartbeat field is `HeartbeatConfig | undefined`, not `| false`
**Category:** Type system compliance (compile-time + runtime)
**Design method:** Equivalence partitioning on return type

**Note:** This test validates the TypeScript type change: `heartbeat?: HeartbeatConfig` vs `heartbeat: HeartbeatConfig | false`.

**Preconditions:** After fix, `AgentListEntry.heartbeat` type is `HeartbeatConfig | undefined` (optional).

**Runtime check inputs:**
```ts
[
  makeAgentRow("coder", false),
  makeAgentRow("gem",   null),
]
```

**Assertions:**
1. For coder: `entry.heartbeat === undefined` (not `=== false`)
2. For gem: `entry.heartbeat === undefined` (not `=== false`)
3. Strict equality: `entry.heartbeat !== false` (must not be boolean false)
4. `Object.values(entry).every(v => typeof v !== "boolean" || /* ...other fields */ false)` — no boolean heartbeat in any value set

**Pass criteria:** No entry's heartbeat is `false`; all disabled agents' heartbeat is `undefined`.
**Fail criteria:** `entry.heartbeat === false` for any agent.

---

### TC-273-U-06: Edge case — empty rows input produces empty output
**Category:** Boundary value (zero-length input)
**Design method:** BVA — minimum boundary

**Inputs:**
```ts
buildAgentsList([])
```

**Expected outcome:**
- Returns `[]` (empty array)
- No crash, no undefined behavior

**Assertions:**
1. `result.length === 0`
2. `Array.isArray(result)` is true

**Pass criteria:** Returns an empty array without error.
**Fail criteria:** Throws, or returns non-array.

---

### TC-273-U-07: Edge case — `heartbeat_enabled` field entirely absent (undefined)
**Category:** Boundary value — missing DB column
**Design method:** BVA — undefined/absent field

**Motivation:** The `heartbeat_enabled` field is optional on `AgentRow` (typed `heartbeat_enabled?: boolean | null`). If the DB function does not return these columns (e.g., pre-migration), the fields are `undefined`. The fix must handle this gracefully: treat `undefined` the same as `null` — omit the heartbeat key.

**Inputs:**
```ts
const row: AgentRow = {
  name: "legacy-agent",
  model: "anthropic/claude-sonnet-4",
  fallback_models: null,
  thinking: null,
  instance_type: "subagent",
  is_default: false,
  allowed_subagents: null,
  // heartbeat_enabled, heartbeat_every, etc. are all absent (undefined)
}
buildAgentsList([row])
```

**Expected outcome:**
- Entry for "legacy-agent" is in output
- `heartbeat` key is ABSENT from entry
- No crash

**Assertions:**
1. `result.length === 1`
2. `result[0].id === "legacy-agent"`
3. `!Object.prototype.hasOwnProperty.call(result[0], "heartbeat")`
4. `result[0].heartbeat === undefined`
5. `typeof result[0].heartbeat !== "boolean"`

**Pass criteria:** All 5 assertions pass.
**Fail criteria:** Entry has heartbeat key with any value, or throws.

---

### TC-273-U-08: All-disabled scenario — zero agents have heartbeat key
**Category:** Scenario — all disabled
**Design method:** Homogeneous partition (all inputs in the "disabled" equivalence class)

**Inputs:**
```ts
[
  makeAgentRow("nova",    false,  null, null, null, true),
  makeAgentRow("coder",   false),
  makeAgentRow("gem",     null),
  makeAgentRow("scout",   null),
  makeAgentRow("iris",    false),
]
```

**Expected outcome:**
- 5 entries returned
- Not a single entry has a `heartbeat` property

**Assertions:**
1. `result.length === 5`
2. `result.every(e => !Object.prototype.hasOwnProperty.call(e, "heartbeat"))`
3. `result.every(e => e.heartbeat === undefined)`
4. `JSON.stringify(result)` does not contain `"heartbeat"`

**Pass criteria:** All 4 assertions pass.
**Fail criteria:** Any entry has a heartbeat key.

---

### TC-273-U-09: All-enabled scenario — every agent has heartbeat object
**Category:** Scenario — all enabled
**Design method:** Homogeneous partition (all inputs in the "enabled" equivalence class)

**Inputs:**
```ts
[
  makeAgentRow("nova",    true, "5m",  "discord", "ch:1", true),
  makeAgentRow("coder",   true, "10m", "slack",   "ch:2"),
  makeAgentRow("gem",     true, null,  null,      null),
]
```

**Expected outcome:**
- 3 entries returned
- Every entry has a `heartbeat` property that is an object (not boolean, not undefined)

**Assertions:**
1. `result.length === 3`
2. `result.every(e => Object.prototype.hasOwnProperty.call(e, "heartbeat"))`
3. `result.every(e => typeof e.heartbeat === "object")`
4. `result.every(e => e.heartbeat !== null)` (objects, not null)
5. `result.every(e => e.heartbeat !== false)` (not boolean)

**Pass criteria:** All 5 assertions pass.
**Fail criteria:** Any entry lacks a heartbeat key, or has a non-object heartbeat.

---

### TC-273-U-10: heartbeat_enabled=true with only `to` field set — partial object correct
**Category:** BVA — sub-field combinations
**Design method:** BVA — single sub-field, each field in isolation

**Inputs (3 separate sub-tests):**
```ts
// Sub-test A: only `every` set
makeAgentRow("a1", true, "5m", null, null)

// Sub-test B: only `target` set
makeAgentRow("a2", true, null, "discord", null)

// Sub-test C: only `to` set
makeAgentRow("a3", true, null, null, "channel:1234")
```

**Expected outcomes:**
- A1: `heartbeat` = `{every: "5m"}` (no target, no to keys)
- B1: `heartbeat` = `{target: "discord"}` (no every, no to keys)
- C1: `heartbeat` = `{to: "channel:1234"}` (no every, no target keys)

**Assertions per sub-test:**
1. `hasOwnProperty("heartbeat")` is true
2. `deepStrictEqual(entry.heartbeat, <expected partial object>)`
3. `!hasOwnProperty("every"|"target"|"to")` for keys not in the expected object

**Pass criteria:** Each partial heartbeat object contains exactly the non-null fields.
**Fail criteria:** Any absent null field appears as `null` in the heartbeat object, or key is boolean.

---

## Coverage Summary

| Test ID        | Coverage Area                                            |
|----------------|----------------------------------------------------------|
| TC-262-U-02    | (Updated) disabled → key absent, not boolean false      |
| TC-262-U-03    | (Updated) null → key absent, not boolean false          |
| TC-262-U-04    | (Updated) enabled have key; disabled/null do not        |
| TC-273-U-01    | Boolean guard: no typeof heartbeat === "boolean" ever   |
| TC-273-U-02    | Schema compliance: object or undefined, exhaustive      |
| TC-273-U-03    | Mixed scenario: primary regression for #273             |
| TC-273-U-04    | JSON serialization: no "heartbeat":false in output      |
| TC-273-U-05    | TypeScript type: heartbeat is HeartbeatConfig? not false|
| TC-273-U-06    | Edge: empty input → empty output, no crash              |
| TC-273-U-07    | Edge: heartbeat_enabled field entirely absent (pre-migration) |
| TC-273-U-08    | Scenario: all agents disabled → zero heartbeat keys     |
| TC-273-U-09    | Scenario: all agents enabled → all have heartbeat objects|
| TC-273-U-10    | BVA: partial heartbeat objects (each sub-field in isolation) |

**Total new/updated test cases: 13** (3 updated existing + 10 new)

**Coverage areas:**
- Schema compliance (heartbeat type constraint)
- Boolean guard (typeof !== "boolean")
- JSON serialization correctness
- All `heartbeat_enabled` partitions: `true`, `false`, `null`, `undefined`
- Homogeneous scenarios: all-enabled, all-disabled
- Mixed enabled/disabled scenario
- Sub-field combinations (BVA on partial heartbeat objects)
- Edge: empty input, pre-migration rows without heartbeat columns
