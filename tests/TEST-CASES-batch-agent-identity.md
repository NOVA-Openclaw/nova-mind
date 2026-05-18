# Test Cases — Batch Agent Identity (#244 + #243)

**Author:** Gem (QA Lead)  
**SE Workflow Run:** #14, Step 3 (Test Case Design)  
**Date:** 2026-05-18  
**Status:** Design complete — ready for Coder implementation (Step 4)  
**Repos:** nova-mind (#244), nova-openclaw (#243)

---

## Overview

This document covers two co-deployed PRs:

| PR | Repo | Change |
|----|------|--------|
| #244 | nova-mind | Replace inline `AGENTS_QUERY` with `get_agent_export_rows()`; capitalize `get_agent_bootstrap()` source literals |
| #243 | nova-openclaw | Preserve synthetic bootstrap path identifiers through `sanitizeBootstrapFiles` |

**Deploy coupling:** See [Coordination Notes](#coordination-notes) at the bottom. The PRs are independent in code but coupled in correctness at runtime. Read that section before Step 4 kickoff.

---

## Part 1 — PR #244: nova-mind / `agent_config_sync` + schema function casing

### Background

`get_agent_export_rows()` is already deployed to production. It uses `session_user` (the PostgreSQL role of the connecting process) to scope the result:
- Returns the connecting agent's own row with `is_default = TRUE`
- Returns every subagent where `session_user = ANY(parent_agents)` with `is_default = FALSE`
- The deployed column is `agents.parent_agents` (text[], plural)

The inline `AGENTS_QUERY` in `sync.ts` (current, buggy) uses `instance_type != 'peer'` — a gateway-agnostic filter that returns the same rows regardless of which gateway is connecting. This causes peer gateways (newhart, graybeard) to receive NOVA's subagents and fall back to NOVA as default.

`get_agent_bootstrap()` currently emits lowercase source literals (`'universal'`, `'global'`, `'domain:...'`, etc.). The hook handler (`bootstrap-context/hook/handler.ts:59`) constructs paths as `` `db:${row.source}/${row.filename}` ``, so the casing fix here is what produces the `db:UNIVERSAL/...` paths that #243 needs to preserve.

---

### 1.1 — Unit Tests: `buildAgentsList()` with function-sourced rows

**File:** `cognition/focus/agent-config-sync/src/sync.test.ts`  
**Framework:** Jest / Vitest (match existing test runner)  
**Approach:** Call `buildAgentsList()` with synthetic row arrays representing what `get_agent_export_rows()` returns for different session_users.

#### TC-244-U-01: NOVA session — self as default, NOVA's subagents only

**Preconditions:** Rows represent `get_agent_export_rows()` result when `session_user = 'nova'`

**Input rows:**
```ts
const rows = [
  { name: 'nova',  model: 'anthropic/claude-opus-4',   fallback_models: null,  thinking: 'high',   instance_type: 'primary',  is_default: true,  allowed_subagents: ['gem','coder','scout'] },
  { name: 'coder', model: 'anthropic/claude-sonnet-4', fallback_models: null,  thinking: 'medium', instance_type: 'subagent', is_default: false, allowed_subagents: null },
  { name: 'gem',   model: 'google/gemini-flash',       fallback_models: null,  thinking: null,     instance_type: 'subagent', is_default: false, allowed_subagents: null },
  { name: 'scout', model: 'google/gemini-flash',       fallback_models: null,  thinking: null,     instance_type: 'subagent', is_default: false, allowed_subagents: null },
];
```

**Expected output:**
```ts
// nova has default: true
expect(result.find(e => e.id === 'nova')?.default).toBe(true);
// subagents do NOT have default key at all
expect(result.find(e => e.id === 'coder')?.default).toBeUndefined();
expect(result.find(e => e.id === 'gem')?.default).toBeUndefined();
// all four agents present
expect(result.map(e => e.id).sort()).toEqual(['coder', 'gem', 'nova', 'scout']);
// nova's allowed_subagents are sorted and surfaced
expect(result.find(e => e.id === 'nova')?.subagents?.allowAgents).toEqual(['coder', 'gem', 'scout']);
```

**Pass criteria:** `default: true` on nova only; all subagents present; no newhart/graybeard entries.

---

#### TC-244-U-02: Newhart session — self as default, Newhart's subagents only

**Preconditions:** Rows represent `get_agent_export_rows()` result when `session_user = 'newhart'`

**Input rows:**
```ts
const rows = [
  { name: 'newhart', model: 'anthropic/claude-opus-4', fallback_models: null,  thinking: 'high', instance_type: 'peer',     is_default: true,  allowed_subagents: ['coder','scout'] },
  { name: 'coder',   model: 'anthropic/claude-sonnet-4', fallback_models: null, thinking: null,  instance_type: 'subagent', is_default: false, allowed_subagents: null },
  { name: 'scout',   model: 'google/gemini-flash',        fallback_models: null, thinking: null,  instance_type: 'subagent', is_default: false, allowed_subagents: null },
];
```

**Expected output:**
```ts
expect(result.find(e => e.id === 'newhart')?.default).toBe(true);
expect(result.find(e => e.id === 'coder')?.default).toBeUndefined();
// gem NOT present (gem's parent_agents does not include 'newhart')
expect(result.find(e => e.id === 'gem')).toBeUndefined();
// nova NOT present
expect(result.find(e => e.id === 'nova')).toBeUndefined();
expect(result.map(e => e.id).sort()).toEqual(['coder', 'newhart', 'scout']);
```

**Pass criteria:** Newhart is default; no NOVA; no gem (unless it's also a Newhart subagent in the actual DB).

---

#### TC-244-U-03: Mutual exclusion — NOVA and Newhart never see each other

**Preconditions:** Two independent `buildAgentsList()` calls with NOVA-scoped and Newhart-scoped rows respectively.

**Assertion:**
```ts
const novaResult = buildAgentsList(novaRows);
const newhartResult = buildAgentsList(newhartRows);

expect(novaResult.find(e => e.id === 'newhart')).toBeUndefined();
expect(newhartResult.find(e => e.id === 'nova')).toBeUndefined();
```

**Pass criteria:** Peer agents never appear in each other's agent list.

---

#### TC-244-U-04: Fallback model shape preserved from function rows

**Input:** Row with `fallback_models = ['openai/gpt-4o', 'google/gemini-pro']`

**Expected:**
```ts
expect(result.find(e => e.id === 'coder')?.model).toEqual({
  primary: 'anthropic/claude-sonnet-4',
  fallbacks: ['openai/gpt-4o', 'google/gemini-pro']
});
```

**Pass criteria:** Object form emitted when fallbacks are present; order preserved from DB array.

---

#### TC-244-U-05: Row with `is_default = null` emits no `default` key

**Input:** `{ is_default: null, ... }`

**Expected:**
```ts
expect(result.find(e => e.id === 'someagent')?.default).toBeUndefined();
```

---

### 1.2 — Function Tests: `get_agent_export_rows()`

**Framework:** pgTAP  
**File:** `database/tests/test_get_agent_export_rows.sql`  
**Setup:** Use `SET ROLE` or `SET SESSION AUTHORIZATION` to simulate different session_users.

> **Note to Coder:** pgTAP tests must run inside a transaction; use `BEGIN`/`ROLLBACK` wrapping. The `SET SESSION AUTHORIZATION` approach requires superuser; `SET ROLE` works if the role exists. Either pattern is acceptable — be consistent with existing pgTAP tests in this repo.

#### TC-244-DB-01: NOVA's default row

```sql
SET ROLE nova;
SELECT is(
  (SELECT is_default FROM get_agent_export_rows() WHERE name = 'nova'),
  TRUE,
  'nova row is_default = TRUE when session_user = nova'
);
```

**Pass criteria:** Exactly one row with `is_default = TRUE`; that row's name matches `session_user`.

---

#### TC-244-DB-02: NOVA's subagent count and is_default = FALSE

```sql
SET ROLE nova;
SELECT ok(
  (SELECT COUNT(*) FROM get_agent_export_rows() WHERE is_default = FALSE) > 0,
  'nova sees at least one subagent row'
);
SELECT is(
  (SELECT COUNT(*) FROM get_agent_export_rows() WHERE is_default = FALSE AND name = 'nova'),
  0::bigint,
  'nova does not appear twice as a subagent'
);
```

---

#### TC-244-DB-03: Newhart session returns newhart as default

```sql
SET ROLE newhart;
SELECT is(
  (SELECT is_default FROM get_agent_export_rows() WHERE name = 'newhart'),
  TRUE,
  'newhart row is_default = TRUE when session_user = newhart'
);
```

---

#### TC-244-DB-04: Newhart does NOT see NOVA's private subagents

This test requires knowing at least one subagent that exclusively has `'nova'` in `parent_agents` and NOT `'newhart'`. Use `gem` (or any confirmed nova-only subagent).

```sql
SET ROLE newhart;
-- gem's parent_agents = ARRAY['nova'] only
SELECT is(
  (SELECT COUNT(*) FROM get_agent_export_rows() WHERE name = 'gem'),
  0::bigint,
  'newhart does not see gem (nova-only subagent)'
);
```

**If gem is shared:** Substitute a confirmed nova-only subagent, or insert a synthetic one for the test.

---

#### TC-244-DB-05: Empty result for session_user with no agents row

```sql
-- Use a DB role that exists but has no row in the agents table
SET ROLE nova_memory_reader; -- or whichever role is DB-only with no agents row
SELECT is(
  (SELECT COUNT(*) FROM get_agent_export_rows()),
  0::bigint,
  'no rows returned for session_user with no agents entry'
);
```

**Note:** This role must exist as a PostgreSQL role (otherwise SET ROLE fails). Choose a known DB-only role. If none exists in the test environment, create one: `CREATE ROLE test_phantom_user;`.

---

#### TC-244-DB-06: Inactive agents excluded

**Setup:** Temporarily set a subagent's `status = 'inactive'`.

```sql
SET ROLE nova;
UPDATE agents SET status = 'inactive' WHERE name = 'iris'; -- example
SELECT is(
  (SELECT COUNT(*) FROM get_agent_export_rows() WHERE name = 'iris'),
  0::bigint,
  'inactive agents are excluded from export rows'
);
ROLLBACK; -- inside test transaction
```

---

#### TC-244-DB-07: Agents with NULL model excluded

```sql
SET ROLE nova;
UPDATE agents SET model = NULL WHERE name = 'iris'; -- example
SELECT is(
  (SELECT COUNT(*) FROM get_agent_export_rows() WHERE name = 'iris'),
  0::bigint,
  'agents with NULL model are excluded'
);
ROLLBACK;
```

---

### 1.3 — Function Tests: `get_agent_bootstrap()` source casing

**Framework:** pgTAP  
**File:** `database/tests/test_get_agent_bootstrap_casing.sql`

#### TC-244-BC-01: All source values are UPPERCASE literals

```sql
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM get_agent_bootstrap('nova')
    WHERE source !~ '^(UNIVERSAL|GLOBAL|DOMAIN:[A-Z]|WORKFLOW:[A-Za-z]|AGENT)$'
      AND source NOT ILIKE 'DOMAIN:%'
      AND source NOT ILIKE 'WORKFLOW:%'
  ),
  'all source values match UPPERCASE pattern for nova'
);
```

**More granular approach — separate assertions per tier:**

```sql
-- UNIVERSAL rows
SELECT ok(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source = 'UNIVERSAL') > 0,
  'at least one UNIVERSAL row for nova'
);
SELECT is(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source = 'universal'),
  0::bigint,
  'no lowercase universal rows'
);

-- GLOBAL rows
SELECT ok(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source = 'GLOBAL') > 0,
  'at least one GLOBAL row for nova'
);
SELECT is(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source = 'global'),
  0::bigint,
  'no lowercase global rows'
);

-- DOMAIN rows — prefix check
SELECT ok(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source LIKE 'DOMAIN:%') >= 0,
  'DOMAIN rows use DOMAIN: prefix (uppercase)'
);
SELECT is(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source LIKE 'domain:%'),
  0::bigint,
  'no lowercase domain: prefix'
);

-- WORKFLOW rows — prefix check (only if nova has workflow steps)
SELECT is(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source LIKE 'workflow:%'),
  0::bigint,
  'no lowercase workflow: prefix'
);

-- AGENT rows
SELECT is(
  (SELECT COUNT(*) FROM get_agent_bootstrap('nova') WHERE source = 'agent'),
  0::bigint,
  'no lowercase agent source'
);
```

---

#### TC-244-BC-02: DOMAIN source format — colon separator, uppercase prefix

For any DOMAIN-type row:

```sql
SELECT ok(
  (SELECT bool_and(source ~ '^DOMAIN:.+') FROM get_agent_bootstrap('gem') WHERE source LIKE 'DOMAIN:%'),
  'DOMAIN sources follow DOMAIN:<names> format for gem'
);
```

---

#### TC-244-BC-03: WORKFLOW source format — colon separator, uppercase prefix

```sql
SELECT ok(
  (SELECT bool_and(source ~ '^WORKFLOW:.+') FROM get_agent_bootstrap('gem') WHERE source LIKE 'WORKFLOW:%'),
  'WORKFLOW sources follow WORKFLOW:<name> format for gem'
);
```

**Note:** If the agent has no workflow steps assigned, this SELECT returns no rows and `bool_and` returns NULL. Wrap with `COALESCE(..., TRUE)` to make the no-rows case a pass (no workflow rows = no casing violation).

---

#### TC-244-BC-04: AGENT source — exact string, not prefixed

```sql
SELECT ok(
  (SELECT bool_and(source = 'AGENT') FROM get_agent_bootstrap('nova') WHERE source LIKE '%AGENT%' OR source LIKE '%agent%'),
  'AGENT source is exact string AGENT, not prefixed'
);
```

---

#### TC-244-BC-05: Path construction integrates correctly with handler

This is a conceptual assertion — the handler at `handler.ts:59` builds paths as `` `db:${row.source}/${row.filename}` ``. After the casing fix, verify the resulting paths use the expected format:

```sql
SELECT ok(
  (SELECT bool_and('db:' || source || '/' || filename = 'db:' || source || '/' || filename)
   FROM get_agent_bootstrap('nova')),
  'source values produce valid db:<SOURCE>/<filename> paths (sanity check)'
);
```

**Real assertion** (run in the bootstrap hook's test harness): verify that the returned path values for `nova` match the pattern `^db:[A-Z][A-Z_]*(:.*)?/[A-Z_]+\.md$`.

---

### 1.4 — Trigger End-to-End: `parent_agents` UPDATE → notify → sync → SIGUSR1

**Framework:** Integration test (shell script + psql + file assertion)  
**File:** `database/tests/test_agent_config_sync_trigger.sh`

> These tests require a running nova-openclaw gateway instance with the agent_config_sync plugin enabled. Run on staging only.

#### TC-244-E2E-01: UPDATE on `parent_agents` fires notify and rewrites agents.json

**Setup:**
```bash
AGENTS_JSON="$HOME/.openclaw/agents.json"
BEFORE_MTIME=$(stat -c %Y "$AGENTS_JSON")
```

**Action:**
```sql
-- Add a test subagent to nova's parent_agents, or touch an existing one
UPDATE agents SET parent_agents = parent_agents WHERE name = 'gem';
-- (or a real change that triggers the notify)
```

**Wait:** `sleep 2` (allow async notify processing)

**Assertions:**
```bash
AFTER_MTIME=$(stat -c %Y "$AGENTS_JSON")
[ "$AFTER_MTIME" -gt "$BEFORE_MTIME" ] || (echo "FAIL: agents.json not updated" && exit 1)
# Validate JSON is valid
jq empty "$AGENTS_JSON" || (echo "FAIL: agents.json is not valid JSON" && exit 1)
```

**Pass criteria:** File mtime advances; JSON parses cleanly.

---

#### TC-244-E2E-02: New agents.json shape reflects `get_agent_export_rows()` scoping

**After trigger fires, check that NOVA's agents.json:**

```bash
# nova is the default agent
jq '.[] | select(.default == true) | .id' "$AGENTS_JSON" | grep -q 'nova'
# No peer agent appears in the list
! jq -r '.[].id' "$AGENTS_JSON" | grep -qE '^(newhart|graybeard)$'
```

---

#### TC-244-E2E-03: Atomic write — no partial reads during update

**Approach:** While a sync is in progress, read `agents.json` multiple times in a tight loop and confirm every read produces valid JSON.

```bash
for i in $(seq 1 50); do
  jq empty "$AGENTS_JSON" 2>/dev/null || echo "PARTIAL READ at iteration $i"
done
```

**Pass criteria:** Zero partial-read failures observed (atomic rename ensures this).

---

### 1.5 — Backward Compatibility: NOVA's subagent set unchanged

**Purpose:** Confirm the query swap from inline SQL to function produces identical output for NOVA's gateway.

#### TC-244-COMPAT-01: Functional equivalence for NOVA's subagent set

**Setup:** Capture output with the old inline query (or a snapshot of current agents.json content), then compare with function output.

```sql
-- Old query (run as nova role for comparison)
SELECT name FROM agents WHERE instance_type != 'peer' AND model IS NOT NULL ORDER BY name;

-- New function
SELECT name FROM get_agent_export_rows() WHERE is_default = FALSE ORDER BY name;
```

**Assertion:** The set of subagent names returned by both queries is identical.

> **Important nuance:** The old query was NOT role-scoped, so it returned all non-peer agents regardless of who connected. For NOVA's own gateway, this happened to produce the correct result (coincidentally) because NOVA's subagents all had `instance_type = 'subagent'`, not `'peer'`. The test must verify the new function produces the same *set* for the nova role.

---

#### TC-244-COMPAT-02: Regression — confirm existing agents.json for NOVA produces zero diff

**Method:** On staging, after deploying the `sync.ts` change:
1. Run manual sync: `openclaw agent-config-sync --force` (or equivalent)
2. Compare new `agents.json` with a pre-deploy snapshot

```bash
diff pre-deploy-agents.json ~/.openclaw/agents.json
```

**Pass criteria:** Zero diff in NOVA's subagent entries (names, models, allowed_subagents). The `default: true` field may shift (previously may have been on NOVA implicitly, now explicitly from function).

---

### 1.6 — Doc Narrative Consistency

**Method:** `grep` assertions run against doc files in the PR diff.

#### TC-244-DOC-01: No `instance_type` filter reference in updated docs

```bash
grep -r "instance_type" \
  cognition/focus/agent-config-sync/HOOK.md \
  cognition/focus/agent-config-sync/README.md \
  cognition/README.md \
  && echo "FAIL: instance_type reference still present" \
  || echo "PASS: no instance_type references"
```

**Pass criteria:** Exit code 1 (grep finds nothing). Any remaining `instance_type` reference must be reviewed.

---

#### TC-244-DOC-02: `'instance_type != peer'` phrase eliminated

```bash
grep -r "instance_type != .peer" \
  cognition/focus/agent-config-sync/HOOK.md \
  cognition/focus/agent-config-sync/README.md \
  cognition/README.md \
  cognition/docs/bootstrap-context-workflow-changes.md \
  && echo "FAIL" || echo "PASS"
```

---

#### TC-244-DOC-03: WORKFLOW: example in bootstrap-context-workflow-changes.md uses UPPERCASE

```bash
grep "WORKFLOW:" cognition/docs/bootstrap-context-workflow-changes.md | grep -v "^#"
```

**Manual check:** Line 42 must read `'WORKFLOW:'` (uppercase W) not `'workflow:'`.

---

## Part 2 — PR #243: nova-openclaw / Synthetic path preservation

### Background

`sanitizeBootstrapFiles()` in `src/agents/bootstrap-files.ts` (lines ~153–172) currently applies `path.resolve(workspaceRoot, pathValue)` to all non-absolute path values. A synthetic identifier like `db:AGENT/HEARTBEAT.md` is not absolute, so it gets resolved to `/home/nova/.openclaw/workspace-gem/db:AGENT/HEARTBEAT.md` — an invalid filesystem path that produces wrong context block headers.

The plugin at `bootstrap-context/hook/handler.ts:59` already emits the correct format (`db:${row.source}/${row.filename}`). The bug is in the OpenClaw SDK sanitizer consuming those values.

**Recognition rule (as specified):** A path is synthetic if it matches `^[A-Za-z][A-Za-z0-9_-]*:` — an alphabetic leading char, followed by alphanumeric/underscore/dash chars, followed by a colon. Known namespaces: `db:`, `fallback:`, `emergency:`. The check is namespace-agnostic.

**Dedupe key for synthetic paths:** The literal synthetic path string (no workspace-relative resolution applied).

**Synthetic paths must NOT go through `path.isAbsolute()` or `path.resolve()` at all.**

---

### 2.1 — Unit Tests: `sanitizeBootstrapFiles()` — synthetic path preservation

**File:** `src/agents/bootstrap-files.test.ts` (add to existing `resolveBootstrapFilesForRun` describe block or add a new `describe('sanitizeBootstrapFiles — synthetic paths', ...)` block)

**Test approach:** Register a bootstrap hook that injects synthetic-path entries, then call `resolveBootstrapFilesForRun()` and assert on the output path values. This matches the established pattern in the existing test file.

#### TC-243-U-01: `db:AGENT/HEARTBEAT.md` passes through unchanged

```ts
it('preserves db:AGENT/HEARTBEAT.md synthetic path unchanged', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'HEARTBEAT.md', path: 'db:AGENT/HEARTBEAT.md', content: 'heartbeat', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const heartbeat = files.find(f => f.name === 'HEARTBEAT.md');

  expect(heartbeat?.path).toBe('db:AGENT/HEARTBEAT.md');
  // Must NOT be an absolute filesystem path
  expect(heartbeat?.path).not.toMatch(/^\//);
  expect(heartbeat?.path).not.toContain(workspaceDir);
});
```

---

#### TC-243-U-02: All canonical `db:` namespace variants pass through unchanged

```ts
it.each([
  ['db:UNIVERSAL/USER.md',                                    'USER.md'],
  ['db:GLOBAL/COMMUNICATION.md',                             'COMMUNICATION.md'],
  ['db:DOMAIN:Quality Assurance/AB_TESTING_METHODOLOGY.md', 'AB_TESTING_METHODOLOGY.md'],
  ['db:WORKFLOW:Daily Inspiration Art/WORKFLOW.md',          'WORKFLOW.md'],
  ['db:agent/SOUL.md',                                       'SOUL.md'], // lowercase db prefix still qualifies
])('preserves synthetic path %s unchanged', async (syntheticPath, name) => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name, path: syntheticPath, content: 'content', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const file = files.find(f => f.name === name);

  expect(file?.path).toBe(syntheticPath);
});
```

> **Design note:** The regex `^[A-Za-z][A-Za-z0-9_-]*:` is case-insensitive on the prefix. `db:` and `DB:` and `Db:` all qualify. The test above uses lowercase `db:agent/SOUL.md` to confirm this. I)ruid should confirm whether mixed-case namespace prefixes are expected in production — if only `db:`, `fallback:`, `emergency:` are valid, a stricter allowlist could replace the regex.

---

#### TC-243-U-03: `fallback:UNIVERSAL_SEED.md` passes through unchanged

```ts
it('preserves fallback: namespace path unchanged', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'UNIVERSAL_SEED.md', path: 'fallback:UNIVERSAL_SEED.md', content: 'seed', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const file = files.find(f => f.name === 'UNIVERSAL_SEED.md');

  expect(file?.path).toBe('fallback:UNIVERSAL_SEED.md');
});
```

---

#### TC-243-U-04: `emergency:RECOVERY.md` passes through unchanged

```ts
it('preserves emergency: namespace path unchanged', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'RECOVERY.md', path: 'emergency:RECOVERY.md', content: 'recovery', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const file = files.find(f => f.name === 'RECOVERY.md');

  expect(file?.path).toBe('emergency:RECOVERY.md');
});
```

---

#### TC-243-U-05: Normal workspace-relative path still resolved (no regression)

```ts
it('still resolves workspace-relative path AGENTS.md normally', async () => {
  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  await fs.writeFile(path.join(workspaceDir, 'AGENTS.md'), 'rules', 'utf8');

  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const agents = files.find(f => f.name === 'AGENTS.md');

  expect(agents?.path).toBe(path.join(workspaceDir, 'AGENTS.md'));
  // Must be an absolute path
  expect(path.isAbsolute(agents?.path ?? '')).toBe(true);
});
```

---

#### TC-243-U-06: Absolute filesystem path still resolved normally (no regression)

```ts
it('still handles absolute path /tmp/something.md normally', async () => {
  const absolutePath = '/tmp/openclaw-test-bootstrap-file.md';
  await fs.writeFile(absolutePath, 'absolute content', 'utf8');

  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'something.md', path: absolutePath, content: 'absolute content', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const file = files.find(f => f.name === 'something.md');

  expect(file?.path).toBe(absolutePath); // resolved absolute remains absolute
  await fs.unlink(absolutePath).catch(() => {});
});
```

---

### 2.2 — Dedupe Behavior with Synthetic Paths

#### TC-243-DEDUP-01: Two identical synthetic paths → one entry survives

```ts
it('deduplicates identical synthetic paths', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'HEARTBEAT.md', path: 'db:AGENT/HEARTBEAT.md', content: 'first',  missing: false },
      { name: 'HEARTBEAT.md', path: 'db:AGENT/HEARTBEAT.md', content: 'second', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const heartbeats = files.filter(f => f.path === 'db:AGENT/HEARTBEAT.md');

  expect(heartbeats).toHaveLength(1);
  expect(heartbeats[0]?.content).toBe('first'); // first-seen wins
});
```

---

#### TC-243-DEDUP-02: Synthetic path and workspace-relative with same-looking filename are NOT collapsed

**Rationale:** `db:AGENT/HEARTBEAT.md` and a workspace file named `HEARTBEAT.md` are distinct entries. They must not collide during deduplication.

```ts
it('does not collapse synthetic path and workspace-relative path with same filename', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'HEARTBEAT.md', path: 'db:AGENT/HEARTBEAT.md',            content: 'db content',        missing: false },
      { name: 'HEARTBEAT.md', path: path.join(ctx.workspaceDir, 'HEARTBEAT.md'), content: 'fs content', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  await fs.writeFile(path.join(workspaceDir, 'HEARTBEAT.md'), 'fs content', 'utf8');

  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const heartbeats = files.filter(f => f.name === 'HEARTBEAT.md');

  // Both entries survive — they have different resolved path keys
  expect(heartbeats).toHaveLength(2);
  const paths = heartbeats.map(f => f.path);
  expect(paths).toContain('db:AGENT/HEARTBEAT.md');
  expect(paths).toContain(path.join(workspaceDir, 'HEARTBEAT.md'));
});
```

> **Design question for I)ruid / Coder:** The existing dedupe uses `path.normalize(path.relative(workspaceRoot, resolvedPath))` as the key. For synthetic paths, the literal string itself must be the key. The implementation must NOT attempt `path.relative()` on synthetic paths. Confirm with Coder whether this produces two separate dedupe namespaces (synthetic strings vs relative FS keys) or requires a unified key scheme.

---

#### TC-243-DEDUP-03: Two different synthetic paths with same-looking suffix remain distinct

```ts
it('does not collapse distinct synthetic namespaces with same filename', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'USER.md', path: 'db:UNIVERSAL/USER.md', content: 'universal', missing: false },
      { name: 'USER.md', path: 'db:agent/USER.md',     content: 'agent',     missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const userFiles = files.filter(f => f.name === 'USER.md');

  expect(userFiles).toHaveLength(2);
});
```

---

### 2.3 — Negative Cases: Non-Synthetic Colon-Containing Paths

**Assertion:** The following path strings do NOT match `^[A-Za-z][A-Za-z0-9_-]*:` and must flow through normal path resolution (not the synthetic bypass).

#### TC-243-NEG-01: Numeric-leading "namespace" is not synthetic

```
:leading-colon.md         — starts with colon, no alpha prefix
1db:something.md          — leading digit, fails [A-Za-z] requirement
foo/db:bar.md             — colon not at position after the first segment (has slash before it)
```

**Test approach:**

```ts
it.each([
  [':leading-colon.md'],
  ['1db:something.md'],
  ['foo/db:bar.md'],
])('non-synthetic path %s goes through normal resolution', async (nonSyntheticPath) => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'weird.md', path: nonSyntheticPath, content: 'content', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const file = files.find(f => f.name === 'weird.md');

  // The path must be resolved (absolute), NOT the raw input string
  // (The file won't exist on disk, so the behavior depends on whether
  //  the sanitizer drops missing paths or includes them. Adjust assertion accordingly.)
  if (file) {
    expect(path.isAbsolute(file.path)).toBe(true);
    expect(file.path).not.toBe(nonSyntheticPath);
  }
  // If the file is dropped (missing path that doesn't exist), that's also acceptable —
  // the key point is it did NOT pass through as an opaque synthetic identifier.
});
```

> **Design clarification I need from I)ruid:** What is the expected behavior when a non-synthetic colon-containing path resolves to a real filesystem path? (e.g., if `/home/nova/workspace/foo/db:bar.md` actually exists). The test above accounts for both drop and include outcomes. Please confirm which is authoritative.

---

#### TC-243-NEG-02: Path with colon embedded deep in segments is not synthetic

`C:\Users\something.md` — Windows-style path. On Linux, path.isAbsolute returns false for this, so it would get `path.resolve()` applied. This is the cross-platform edge case (see TC-243-CROSS-01 below).

---

### 2.4 — Integration Test: End-to-End Context Injection with Synthetic Paths

**Framework:** Integration test using the OpenClaw test harness  
**Scope:** Confirm the system prompt's project-context block renders synthetic path names correctly, not as filesystem paths.

#### TC-243-INT-01: System prompt contains `## db:AGENT/HEARTBEAT.md`, not `## /home/.../workspace/db:AGENT/HEARTBEAT.md`

**Setup:**
1. Start a test session via the test harness with a mock bootstrap hook that returns synthetic-path entries (as the real `bootstrap-context` plugin does)
2. Capture the system prompt injected by the gateway

**Assertion:**
```ts
// system prompt excerpt
expect(systemPrompt).toMatch(/^## db:AGENT\/HEARTBEAT\.md/m);
expect(systemPrompt).not.toMatch(/^## \/home\/.+\/workspace\/db:AGENT\/HEARTBEAT\.md/m);
```

**Alternative assertion (path header pattern):**
```ts
// No header should contain an absolute path to a synthetic db: file
expect(systemPrompt).not.toMatch(/^## \/[^\n]+\/db:[^\n]+/m);
```

---

#### TC-243-INT-02: Section heading uses exact casing from source value

After both PRs deploy, the injected context block for NOVA should contain:
```
## db:UNIVERSAL/UNIVERSAL_SEED.md
## db:GLOBAL/COMMUNICATION.md
## db:agent/SOUL.md
## db:agent/IDENTITY.md
```

(UNIVERSAL/GLOBAL uppercase from `get_agent_bootstrap()` fix; agent lowercase from current schema output — confirm final casing with I)ruid based on TC-244-BC test results)

**Assertion:**
```ts
expect(systemPrompt).toMatch(/^## db:UNIVERSAL\//m);
expect(systemPrompt).toMatch(/^## db:GLOBAL\//m);
// NOT the old broken paths
expect(systemPrompt).not.toMatch(/^## \/home/m);
```

---

### 2.5 — Cross-Platform Path Semantics

#### TC-243-CROSS-01: Synthetic path bypass does NOT call `path.isAbsolute` or `path.resolve`

**Approach:** Code review assertion (no automated test needed, but should be verified in PR review).

The implementation must show that for any path matching `^[A-Za-z][A-Za-z0-9_-]*:`, the code returns the path value directly without calling `path.isAbsolute(pathValue)` or `path.resolve(workspaceRoot, pathValue)`.

**Rationale:** On Windows, `path.isAbsolute('db:AGENT/HEARTBEAT.md')` would return `false` (not a drive letter path), so the path would hit `path.resolve()`. `path.resolve('C:\\workspace', 'db:AGENT/HEARTBEAT.md')` on Windows produces `C:\workspace\db:AGENT\HEARTBEAT.md` — wrong. The synthetic regex bypass must be the first check, before any `path.*` calls.

**Automated proxy test:**
```ts
it('synthetic path is returned before any path.resolve is attempted', async () => {
  const syntheticPath = 'db:AGENT/HEARTBEAT.md';

  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'HEARTBEAT.md', path: syntheticPath, content: 'hb', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const files = await resolveBootstrapFilesForRun({ workspaceDir });
  const file = files.find(f => f.name === 'HEARTBEAT.md');

  // If path.resolve had been called, the result would be an absolute path.
  // If synthetic bypass works, the path is exactly the input string.
  expect(file?.path).toBe(syntheticPath);
  expect(file?.path.startsWith('/')).toBe(false);  // Not an absolute POSIX path
  expect(file?.path.match(/^[A-Za-z]:\\/)).toBeNull(); // Not a Windows drive path
});
```

**Document assumption:** This codebase runs on Linux (Ubuntu on AWS). Windows path semantics are not a production concern, but the synthetic check must structurally precede `path.*` calls to be correct on all platforms.

---

## Coordination Notes

### Deploy Coupling

| Scenario | Risk | Recommendation |
|----------|------|----------------|
| Ship #244 without #243 | Bootstrap context renders `db:universal/FILENAME.md` → `sanitizeBootstrapFiles` resolves it to `/home/.../workspace/db:universal/FILENAME.md`. **No behavior regression** — the path was already broken before #244, and the casing change doesn't make it worse. | Acceptable gap. |
| Ship #243 without #244's casing fix | `sanitizeBootstrapFiles` now preserves synthetic paths correctly, but `get_agent_bootstrap()` still emits `'universal'`/`'global'` — so paths are `db:universal/...` (lowercase). The context headers render with wrong casing. | Functionally works, aesthetically wrong. Acceptable short gap but should be same-day resolved. |
| Ship #243 without #244's `agent_config_sync` swap | Peer gateways (newhart, graybeard) still get wrong agents.json. Completely unrelated to #243. | Ship #244 first or together. |

**Recommended deploy order:** Stage and test #244 first (larger impact, DB side), then #243 (SDK side, narrower blast radius). A coordinated same-deploy-window rollout is ideal.

### Staging Environment Checklist

- [ ] nova-openclaw staging clone running (`nova-staging@localhost`)
- [ ] nova-mind installed on same host via `bash agent-install.sh`
- [ ] Both gateways (nova and newhart) pointed at the same `nova_memory` PostgreSQL instance
- [ ] `get_agent_export_rows()` confirmed deployed (it is — run `SELECT * FROM get_agent_export_rows();` as the nova role to verify)
- [ ] pgTAP installed in staging PostgreSQL (`CREATE EXTENSION IF NOT EXISTS pgtap`)
- [ ] Test subagent with exclusive `parent_agents = ARRAY['nova']` confirmed (or created) for TC-244-DB-04

### Casing Scheme Confirmation Needed

The task specifies: `db:UNIVERSAL/...`, `db:GLOBAL/...`, `db:DOMAIN:Quality Assurance/...`, `db:WORKFLOW:Daily Inspiration Art/...`, `db:agent/...`.

The pattern appears to be: section-level names (`UNIVERSAL`, `GLOBAL`, `DOMAIN`, `WORKFLOW`) are UPPERCASE; the namespace prefix `db:` itself is lowercase. **Confirm before Step 4:** Is `db:agent/SOUL.md` the correct casing, or is it `db:AGENT/SOUL.md`? The `get_agent_bootstrap()` fix capitalizes the source values — so if `source = 'AGENT'` after the fix, the path would be `db:AGENT/SOUL.md`. I need I)ruid to confirm the intended final casing before Coder implements the schema change.

---

## Spec Gaps & Questions for I)ruid

1. **`db:agent/` vs `db:AGENT/` casing:** After the `get_agent_bootstrap()` fix, the source literal will be `'AGENT'`, producing `db:AGENT/SOUL.md`. Is this the intended form? My test cases use `db:AGENT/HEARTBEAT.md` per the task spec, but I want Coder to be explicit in the implementation.

2. **Shared subagents (TC-244-DB-04):** If `scout` is in both `nova.parent_agents` and `newhart.parent_agents`, then Newhart will see scout in its agents.json. The test for "Newhart doesn't see NOVA's private subagents" needs a confirmed nova-exclusive subagent to use. What agent is confirmed nova-only?

3. **Non-synthetic colon path behavior (TC-243-NEG-01):** When a path like `foo/db:bar.md` goes through normal resolution and the file doesn't exist, is the entry dropped or kept with the resolved path? The existing `sanitizeBootstrapFiles` doesn't drop missing paths — it only validates the path field. Confirm expected behavior.

4. **`sanitizeBootstrapFiles` export:** The function is currently unexported (`function sanitizeBootstrapFiles`, not `export function`). To write truly isolated unit tests, it should be exported. As a design decision, do you want direct unit tests (requires export) or all-indirect tests via `resolveBootstrapFilesForRun` hooks (current pattern)? My test cases above use the hook-injection pattern — no export needed — but direct tests would be cleaner.

5. **pgTAP test role for TC-244-DB-05:** Which DB-only role (no agents row) exists in the test environment and can be used with `SET ROLE`?

---

## Additional Test Cases Beyond the Spec

### TC-243-U-EXTRA-01: Warning NOT emitted for synthetic paths

Synthetic paths are valid by design — the sanitizer must not warn about them. Verify no warning is emitted when a synthetic path is encountered.

```ts
it('does not emit a warning for valid synthetic paths', async () => {
  registerInternalHook('agent:bootstrap', (event) => {
    const ctx = event.context as AgentBootstrapHookContext;
    ctx.bootstrapFiles = [
      ...ctx.bootstrapFiles,
      { name: 'HEARTBEAT.md', path: 'db:AGENT/HEARTBEAT.md', content: 'hb', missing: false },
    ];
  });

  const workspaceDir = await makeTempWorkspace('openclaw-bootstrap-');
  const warnings: string[] = [];
  await resolveBootstrapFilesForRun({
    workspaceDir,
    warn: (msg) => warnings.push(msg),
  });

  expect(warnings.filter(w => w.includes('db:AGENT'))).toHaveLength(0);
});
```

---

### TC-244-DB-EXTRA-01: `get_agent_export_rows()` ORDER BY — default row first

The function has `ORDER BY 6 DESC, 1` (column 6 = is_default DESC, column 1 = name ASC). Verify the default agent appears first.

```sql
SET ROLE nova;
SELECT is(
  (SELECT name FROM get_agent_export_rows() LIMIT 1),
  'nova',
  'nova (the default) appears first in get_agent_export_rows()'
);
```

---

### TC-244-COMPAT-EXTRA-01: Package.json version bump is present

```bash
# After PR #244 is applied
grep '"version"' cognition/focus/agent-config-sync/package.json | head -1
```

**Manual check:** Version string must have been incremented relative to the pre-PR value.

---

## Summary: Pass/Fail Criteria for QA Sign-Off

### PR #244 (nova-mind)

| Gate | Test IDs | Required for sign-off |
|------|----------|-----------------------|
| Unit: buildAgentsList() scoping | TC-244-U-01 through 05 | All pass |
| DB: get_agent_export_rows() scoping | TC-244-DB-01 through 07 | All pass |
| DB: get_agent_bootstrap() source casing | TC-244-BC-01 through 05 | All pass |
| E2E: trigger → file write chain | TC-244-E2E-01 through 03 | 01 and 02 required; 03 recommended |
| Backward compat: NOVA subagent set | TC-244-COMPAT-01, 02 | Both pass |
| Doc: no stale instance_type reference | TC-244-DOC-01 through 03 | All pass |

### PR #243 (nova-openclaw)

| Gate | Test IDs | Required for sign-off |
|------|----------|-----------------------|
| Unit: synthetic path preservation | TC-243-U-01 through 06 | All pass |
| Dedupe: synthetic paths | TC-243-DEDUP-01 through 03 | All pass |
| Negative cases: non-synthetic colons | TC-243-NEG-01, 02 | NEG-01 required; NEG-02 documented |
| Integration: system prompt headers | TC-243-INT-01, 02 | INT-01 required |
| Cross-platform: no path.resolve on synthetic | TC-243-CROSS-01 | Pass (code review + test) |
| No spurious warnings | TC-243-U-EXTRA-01 | Pass |

**No S1/S2 open defects at time of sign-off.**  
**Coverage gate:** TypeScript changes must not drop statement coverage below existing baseline (measure with `vitest --coverage` on changed files).  
**pgTAP gate:** All SQL function tests pass with zero failures.
