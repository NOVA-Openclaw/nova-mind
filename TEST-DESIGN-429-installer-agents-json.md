# Test Design — nova-mind#429: `_generate_agents_json()` sourced from `get_agent_export_rows()`

**Author:** Gem (QA Lead) | **Workflow:** SE run #364, Step 3 | **NOVA task:** #138
**Scope:** Test design only — no implementation. Companion issue #402 (set -e / sparse-DB death) referenced where relevant; explicitly marked out-of-scope items are called out.

## 0. Ground Truth Established During Source Review

These facts were confirmed by reading `agent-install.sh` (~L2154–2262), `sync.ts`, and `nova-memory-schema.sql`, and by querying `get_agent_export_rows()` live as `gem`. **Any test design or implementation must account for these; they are not assumptions.**

> **Post-implementation note:** This table captures the state of `agent-install.sh` *at design time*, before the #429 fix landed (it since has, in `3c0a424`). F4 and F9 in particular describe pre-fix behavior (no `status = 'active'` filter; no heartbeat handling) that the fix was written to change — read them as the documented baseline the tests below validate against, not as current behavior. Line-number citations below have been updated to reflect the current file so they remain spot-checkable; the facts themselves are left as originally recorded.

| # | Fact | Source |
|---|---|---|
| F1 | `DB_USER="${PGUSER:-$(whoami)}"` (line 68 at design time; now line 74) — `psql -U "$DB_USER"` already connects as the unix/gateway user, so `session_user` inside `get_agent_export_rows()` naturally resolves to the correct gateway. No new connection-scoping code is needed in the installer — only the query text changes. | agent-install.sh:74 |
| F2 | `get_agent_export_rows()` returns the **caller's own row** (`a.name = session_user`) UNIONed with **all subagents where `session_user = ANY(a.parent_agents)`**, filtered to `status = 'active' AND model IS NOT NULL` in both branches. | database/schema.sql:4296-4338 |
| F3 | **`is_default` in the function's own-row branch is hardcoded `TRUE`**, and hardcoded `FALSE` in the subagent branch — it does **NOT** read `agents.is_default` from the table. Verified live: `gem`'s actual `agents.is_default` column is `f`, but `get_agent_export_rows()` returns `is_default = t` for gem's own row. | database/schema.sql:4307, 4326; live query |
| F4 | The pre-fix inline installer query had **no `status = 'active'` filter** — the function adds one. This was a *behavior change*, not purely a refactor: previously-inactive agents with a model set would have been included; after the fix (now landed) they are excluded. | agent-install.sh:2374-2404 (post-fix `_generate_agents_json()`) vs database/schema.sql |
| F5 | `sync.ts`'s `buildAgentsList()` sets `entry.default = true` **only when `row.is_default === true`** — i.e., it trusts whatever the query returns for `is_default`. Combined with F3, this means under the *plugin's* code path, every gateway's own row will emit `"default": true` and every subagent row will not — regardless of the real `agents.is_default` table value. The installer's ported CASE logic must replicate this same trust-the-column behavior, not re-derive `is_default` some other way. | sync.ts buildAgentsList() |
| F6 | Real DB boundary data exists today (no synthetic seeding needed for these): `nova.allowed_subagents = {*}` (literal single-element array containing the string `"*"`, not a wildcard expansion, not empty); `scout.allowed_subagents = {}` (empty array, distinct from NULL); `nova.heartbeat_enabled = true` with `heartbeat_every = NULL` (only `heartbeat_target`/`heartbeat_to` populated) — this trips the plugin's `if (heartbeat_enabled === true && heartbeat_every)` guard to **false**, so `nova`'s current real row emits **no** `heartbeat` key today despite `heartbeat_enabled=true`. | live psql query at design time — not re-verified by this audit |
| F7 | `scout` has 4 parents: `{nova,newhart,graybeard,ticker}` — the only multi-parent, cross-peer-and-subagent case in current data. Good real-world scoping test subject. | live psql query at design time — not re-verified by this audit |
| F8 | The installer's post-fix query builds JSON with `json_agg(entry)` in SQL (final `id`-ordering is now applied by the Node reconstruction step, mirroring `sync.ts`'s `.sort((a,b) => a.id.localeCompare(b.id))`) — both paths converge on the same lexicographic order for ASCII agent names, but worth an explicit locale/collation parity check if the DB's default collation differs from JS `localeCompare`. | agent-install.sh:2374-2450 vs sync.ts |
| F9 | The installer's CASE logic implements: fallbacks-present → `{primary, fallbacks}` object vs fallbacks-absent → bare string; `is_default` → `default:true` key only when true; `allowed_subagents` non-empty → sorted `subagents.allowAgents`; and (post-fix, now landed) heartbeat handling mirroring `sync.ts`'s `heartbeat_enabled === true && heartbeat_every` truthy-guard exactly (including the same "silently omit if enabled but every is NULL" quirk from F6). At design time this heartbeat handling was the 100%-new code the fix needed to add. | agent-install.sh:2374-2404 (CASE query) |
| F10 | `sync.ts` never emits the `thinking` key (explicit comment: not a valid per-agent config key; set at spawn time). The installer's ported query likewise never emits a `thinking` key even though `get_agent_export_rows()` returns a `thinking` column — confirmed still true post-fix. | sync.ts comment; agent-install.sh:2374-2450 |
| F11 | The whole `_generate_agents_json` block sits inside `if [ -d "$AGENT_CONFIG_SYNC_SOURCE" ]` (agent-config-sync plugin source must be present) — so scoping/shape tests should assume that precondition is met; the `else` branch just prints a warning and skips entirely (untouched by this fix, but worth one guard-rail test). | agent-install.sh:2259, 2262 |
| F12 | `#402` root cause: `_generate_agents_json` returns `1` on "psql failed", "non-JSON", and "no agents found" paths, and is invoked as a bare statement (not `if _generate_agents_json; then...`) at the three call sites (now lines 2511, 2523, 2532) under top-level `set -euo pipefail`. Switching the query source does not change this control-flow shape — the bug is orthogonal to *which* query is used, but the fix will make the "no agents found" path drastically **more likely to be hit** in the common case: a peer gateway (Newhart/Graybeard) whose parent_agents scoping legitimately returns very few or zero rows if run before task ownership rows exist. This raises the real-world hit rate of #402, so it is in-scope for regression coverage even though the fix for #402 itself may land in a separate PR. | agent-install.sh:2511, 2523, 2532; issue #402 |

## 1. Test Levels & Traceability

- **Shell-level (installer)**: BATS-style test cases against `_generate_agents_json()` and its call sites, run against a real/staging PostgreSQL instance connected as different roles. IDs: `TC-429-S-##`.
- **Cross-component parity (installer vs plugin)**: Compare the JSON `_generate_agents_json()` produces to the JSON `syncAgentsConfig()`/`buildAgentsList()` produces for identical seeded DB state. IDs: `TC-429-P-##`.
- **Regression / adjacency (#402)**: Confirm the fix doesn't newly break or newly worsen the `set -e` death mode. IDs: `TC-429-R-##`.
- Follow **BVA** for array/string boundaries (empty vs NULL vs single vs sorted-order), **equivalence partitioning** for role/scoping classes, and **decision-table** style for the fallback×default×subagents×heartbeat 4-factor CASE logic (per TEST_DESIGN_PATTERNS.md).

Existing unit coverage in `sync.test.ts` (TC-244-U-*, TC-262-U-*, TC-269-U-*, TC-273-U-*) already covers the **plugin's** `buildAgentsList()` shape logic exhaustively. This design does **not** duplicate those — it treats `sync.ts` output as the oracle for parity tests (TC-429-P-*) and focuses new coverage on the **shell installer's port** of that logic plus the DB-role-scoping behavior that is unique to the installer's initial-generation code path.

---

## 2. Happy Path

### TC-429-S-01 — Fresh install, no existing agents.json, DB has agents → correct scoped JSON generated
- **Setup:** Staging DB seeded with `nova` (primary, is_default per-table=true), 3 subagents with `parent_agents={nova}` and valid models, no `agents.json` at `$OPENCLAW_DIR/agents.json`.
- **Steps:** Run installer's agents.json section as unix user `nova` (or invoke `_generate_agents_json` directly after sourcing the script) with `psql -U nova`.
- **Expected:** `agents.json` is created; valid JSON array; contains exactly `nova` + the 3 seeded subagents (4 entries); no other agents from the DB appear; array sorted by `id`.

### TC-429-S-02 — Idempotent re-run when file already exists and is valid
- **Setup:** Valid `agents.json` present from a prior run.
- **Steps:** Run installer again without `--regenerate-agents-json`.
- **Expected:** File untouched (mtime/content unchanged); log line indicates "agents.json present and valid; agent_config_sync will keep it in sync"; `_generate_agents_json` is **not** invoked at all (verify via the `if [ -f "$AGENTS_JSON" ]` branch, not just output equality).

---

## 3. Scoping (session_user via `get_agent_export_rows()`)

### TC-429-S-03 — Run as `nova` → only nova + nova's parent_agents subagents
- **Setup:** Seed DB per live-schema shape: `nova` primary; subagents with `parent_agents` containing `{nova}` only, `{newhart}` only, `{nova,newhart}` (shared), and one peer `newhart` with no `parent_agents`.
- **Steps:** `psql -U nova` invocation of the new query.
- **Expected:** Output includes `nova`, the `{nova}`-only subagent, and the `{nova,newhart}` shared subagent. Does **NOT** include the `{newhart}`-only subagent or the `newhart` peer row itself.

### TC-429-S-04 — Run as `newhart` (peer gateway) → only newhart + newhart's subagents
- **Setup:** Same seed as TC-429-S-03.
- **Steps:** `psql -U newhart` invocation.
- **Expected:** Output includes `newhart`, the `{newhart}`-only subagent, and the `{nova,newhart}` shared subagent. Does **NOT** include `nova` or the `{nova}`-only subagent. **This is the core regression test for #429** — the current inline query (run as any user) returns the *same* global `instance_type != 'peer'` set regardless of caller, so this test must FAIL against the pre-fix code and PASS against the post-fix code. Include both runs in the test report for contrast.

### TC-429-S-05 — Run as `graybeard` with zero owned subagents (sparse scoping)
- **Setup:** `graybeard` peer row exists, but no agent has `graybeard` in `parent_agents` (matches current live data — verified via `psql`: no rows currently reference graybeard).
- **Steps:** `psql -U graybeard` invocation.
- **Expected:** Output = graybeard's own row only (1 entry) — not zero, since the function's first branch (`a.name = session_user`) always matches the caller's own row if it's active with a model. **Cross-reference to #402/TC-429-R-*:** this is NOT the "zero rows" case: `#402`'s "no agents found" path is only hit when even the caller's own row fails the `status='active' AND model IS NOT NULL` filter (e.g., own row inactive, or model NULL) — see TC-429-S-11/S-12 and TC-429-R-02.

### TC-429-S-06 — Multi-parent subagent (scout: `{nova,newhart,graybeard,ticker}`)
- **Setup:** Use `scout`'s real shape or an equivalent synthetic row with 4 parents including one non-gateway subagent parent (`ticker`, itself a subagent).
- **Steps:** Run as each of `nova`, `newhart`, `graybeard` in turn.
- **Expected:** `scout` appears in all three gateways' output (parent array overlap is OR-semantics, not exclusive-owner). Confirms shared-subagent fan-out scoping works as designed, not just single-parent scoping.

### TC-429-S-07 — Mutual exclusion — nova and newhart outputs never share a row inappropriately
- **Setup:** Same seed as TC-429-S-03/04.
- **Steps:** Diff the two JSON outputs from TC-429-S-03 and TC-429-S-04.
- **Expected:** The only overlapping agent name between the two outputs is the intentionally-shared `{nova,newhart}` subagent. `nova`'s own row never appears in newhart's output and vice versa. (Mirrors TC-244-U-03 from the plugin's unit suite, applied to the shell code path.)

---

## 4. Output-Shape Parity (installer vs `agent_config_sync` plugin)

### TC-429-P-01 — Identical DB state → byte-different-but-semantically-equal JSON, plugin's first sync is a no-op
- **Setup:** Fresh DB state, run installer's `_generate_agents_json()` first (writes `agents.json`). Then start the gateway (or invoke `syncAgentsConfig()` directly) so the plugin runs its "initial sync on startup" path against the *same* DB state.
- **Steps:** Compare the file the installer wrote vs. what the plugin would write; check plugin's `syncAgentsConfig()` return value (`true` = changed/wrote, `false` = already up to date).
- **Expected:** `syncAgentsConfig()` returns `false` (no rewrite) — this is the literal idempotence acceptance criterion (#429 AC #2). Content should be **semantically** identical: same set of entries, same key sets per entry, same nested value equality. **Byte-identical is NOT required** unless the installer's `jq '.'` pretty-print matches Node's `JSON.stringify(data, null, 2) + "\n"` exactly — call this out explicitly as an implementation risk (see §7 Q1).

### TC-429-P-02 — Fallback-models shape parity
- **Setup:** One agent with `fallback_models` = non-empty array, one with `fallback_models = NULL`, one with `fallback_models = '{}'` (empty array).
- **Expected:** Installer and plugin both emit: non-empty → `{"model": {"primary": ..., "fallbacks": [...]}}`; NULL or empty → `{"model": "<string>"}` (bare string, no object). Confirms the installer's existing `array_length(fallback_models,1) > 0` CASE branch condition is preserved unchanged by the #429 fix (only the FROM/WHERE source should change, not this logic).

### TC-429-P-03 — `allowed_subagents` shape parity (present/absent/sorted)
- **Setup:** One agent with `allowed_subagents = {zebra, alpha, mike}` (unsorted input), one with `NULL`, one with `{}` (empty array), one with the literal wildcard `{*}` (mirroring `nova`'s real row).
- **Expected:** Non-empty → `subagents.allowAgents` sorted ascending (`["alpha","mike","zebra"]`); NULL or empty → key omitted entirely (not `[]`, not `null`). The `{*}` case must round-trip as `["*"]` literally — confirm neither the installer's SQL nor the plugin's TS attempts to expand `*` into an actual agent list (it is opaque data at this layer).

### TC-429-P-04 — `is_default` flag parity, including the F3/F5 hardcoded-truth-source quirk
- **Setup:** Seed an agent whose **table column** `agents.is_default = false` but who is the caller (`session_user` match) — mirrors live `gem` data exactly.
- **Steps:** Run as that agent.
- **Expected:** Both installer and plugin output `"default": true` for that row (trusting `get_agent_export_rows()`'s hardcoded per-branch value, NOT the raw table column). This is a **required parity test**, not optional — a naive re-implementation that queries `agents.is_default` directly instead of consuming the function's `is_default` output column would silently diverge from the plugin and must be caught here.

### TC-429-P-05 — Heartbeat shape parity (new logic — no prior installer coverage)
- **Setup:** Four agents: (a) `heartbeat_enabled=true` + `heartbeat_every` set + `heartbeat_target`/`heartbeat_to` set; (b) `heartbeat_enabled=true` + `heartbeat_every` set, target/to NULL; (c) `heartbeat_enabled=true`, `heartbeat_every=NULL` (mirrors live `nova` row per F6); (d) `heartbeat_enabled=false` or `NULL`.
- **Expected:** (a) full `heartbeat: {every, target, to}` object; (b) partial `heartbeat: {every}` object only; (c) **no** `heartbeat` key at all (guard requires both `enabled===true` AND truthy `every`); (d) no `heartbeat` key. Installer and plugin must match on all four exactly. This is the highest-risk shape-parity item since the installer has **zero** existing heartbeat logic to adapt from (F9) — a straightforward "translate the CASE statement" pass will likely miss the `heartbeat_every` truthiness sub-condition in (c) if only `heartbeat_enabled` is checked.

### TC-429-P-06 — `thinking` column present in function output, absent from JSON (both code paths)
- **Setup:** Any agent with a non-NULL `thinking` value.
- **Expected:** Neither installer JSON nor plugin JSON contains a `thinking` key anywhere in the entry (F10). Guards against an over-eager port that naively maps every returned column to a JSON key.

### TC-429-P-07 — Sort-order parity across SQL vs JS sort mechanisms (F8)
- **Setup:** Agent names chosen to probe collation edge cases if feasible in the current environment: mixed case (`Athena` vs `athena`), leading digits, underscores vs hyphens (`agent_1` vs `agent-2`). If DB collation is `C`/ASCII-only, note that as a constraint and use at least one case-sensitivity pair.
- **Expected:** Installer's `ORDER BY (entry->>'id')` (SQL, DB collation) and plugin's `.sort((a,b)=>a.id.localeCompare(b.id))` (JS, locale-aware) produce the **same order**. If they diverge (e.g., DB uses `C` collation putting all uppercase before lowercase, while `localeCompare` interleaves case-insensitively), flag as a genuine parity bug, not a test defect — see §7 Q2.

---

## 5. Preserved #252 Safety Guards

### TC-429-S-08 — Existing valid agents.json is never touched
- **Setup:** Valid, hand-crafted `agents.json` present (content deliberately different from what DB would generate, to detect any overwrite).
- **Steps:** Run installer without `--regenerate-agents-json`.
- **Expected:** File byte-identical before/after (checksum compare). No `_generate_agents_json` invocation occurs on this path at all.

### TC-429-S-09 — Existing invalid-JSON agents.json → warn, not overwritten
- **Setup:** `agents.json` present containing malformed JSON (e.g., truncated, trailing comma).
- **Steps:** Run installer without `--regenerate-agents-json`.
- **Expected:** Warning printed (`agents.json exists but contains invalid JSON — skipping write` + hint about `--regenerate-agents-json`). File unchanged on disk.

### TC-429-S-10 — `--regenerate-agents-json` backs up then regenerates (valid existing file)
- **Setup:** Valid `agents.json` present.
- **Steps:** Run installer with `--regenerate-agents-json`.
- **Expected:** A `agents.json.bak-<timestamp>` backup is created with the pre-run content; `agents.json` is then regenerated from the (now session-user-scoped) DB query; new content reflects only the caller's scoped agent set, not the old global set.

### TC-429-S-10b — `--regenerate-agents-json` backs up then regenerates (corrupt existing file)
- **Setup:** Invalid-JSON `agents.json` present.
- **Steps:** Run installer with `--regenerate-agents-json`.
- **Expected:** Corrupt file backed up (with `${WARNING}` framing, distinct message from the valid-file backup case); regenerated from DB same as TC-429-S-10.

### TC-429-S-11 — psql failure → NEVER writes `[]` or any file
- **Setup:** Simulate psql failure (bad `DB_NAME`, or revoke `EXECUTE` on `get_agent_export_rows()` from the test role, or stop DB connectivity).
- **Steps:** Run installer against a state where `agents.json` does not yet exist.
- **Expected:** `_generate_agents_json` returns 1; no `agents.json` file is created; warning printed: "Could not query DB for agents.json — agents.json not written"; explicitly assert the file does **not** exist and is **not** `[]` afterward (this is the exact anti-pattern #252 exists to prevent).

### TC-429-S-12 — DB returns zero rows for the caller → NEVER writes `[]`
- **Setup:** A role with no active/modeled own-row and no subagents pointing to it in `parent_agents` (only reachable in practice for a brand-new, not-yet-seeded gateway role, or by temporarily setting the caller's own `status != 'active'` or `model = NULL`).
- **Steps:** Run `_generate_agents_json` as that role.
- **Expected:** Function returns 1; warning "DB query returned no agents — agents.json not written" + info line about agent_config_sync generating it later; **no file written, not even `[]`**. This is the scenario most likely to newly occur post-fix per F12 (a legitimately sparse but valid scoped result, as opposed to the old global query which almost always returned *something*).

### TC-429-S-13 — Non-JSON data returned by DB → warn, not written
- **Setup:** Force the query to return malformed output (e.g., temporarily break the `jsonb_strip_nulls`/`jsonb_build_object` chain in a throwaway test copy of the function, or pipe garbage through a stubbed `psql`).
- **Expected:** `echo "$AGENTS_DATA" | jq '.'` fails; warning "DB returned non-JSON data for agents.json — not writing"; tmp file removed (`rm -f "$AGENTS_JSON_TMP"`); function returns 1; target file untouched.

### TC-429-S-14 — Unwritable target directory/file
- **Setup:** `$OPENCLAW_DIR` (or `agents.json` itself) made read-only / owned by another user, in a scratch staging path (never production).
- **Steps:** Run `_generate_agents_json` with a valid, non-empty DB result.
- **Expected:** The `mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"` step fails; warning "Could not write agents.json"; `$AGENTS_JSON_TMP` is cleaned up (`rm -f`); function returns 1; original state of target (absent or prior content) preserved.

---

## 6. Boundary Values

### TC-429-S-15 — Agent with NULL model is excluded (both branches of the function)
- **Setup:** Seed an agent with `parent_agents={nova}` and `model = NULL`.
- **Steps:** Run as `nova`.
- **Expected:** Excluded from output entirely (function's `WHERE ... AND a.model IS NOT NULL` applies to both UNION branches per F2). Confirms the fix does not regress the original inline query's `model IS NOT NULL` filter — it's now enforced inside the function instead of the installer's WHERE clause, but must still hold.

### TC-429-S-16 — Agent with `status != 'active'` is excluded (new filter vs old query — F4)
- **Setup:** Seed an agent with valid model, `parent_agents={nova}`, `status = 'inactive'` (or any non-'active' value the schema allows).
- **Steps:** Run as `nova`, compare against what the **old** inline query would have returned for the same seed (old query has no status filter).
- **Expected:** New/fixed installer output excludes the inactive agent; explicitly document this as an **intentional behavior change** introduced by the fix (F4), not a defect — but flag for Project Leadership sign-off since it's a user-visible difference beyond pure refactor (see §7 Q3).

### TC-429-S-17 — `allowed_subagents` empty array vs NULL — both omit the `subagents` key identically
- **Setup:** One agent with `allowed_subagents = '{}'::text[]`, another with `allowed_subagents = NULL`.
- **Expected:** Both produce entries with no `subagents` key present (not `{"subagents":{"allowAgents":[]}}`, not `{"subagents":null}`). Exercises the `array_length(...,1) > 0` guard's NULL-safety (`array_length('{}',1)` is `NULL` in Postgres, not `0` — verify the existing CASE condition already handles this correctly, since it's unchanged logic per F9, but confirm post-port).

### TC-429-S-18 — `fallback_models` empty array vs NULL — both yield bare string model
- **Setup:** Mirror of TC-429-S-17 for `fallback_models`.
- **Expected:** Both produce `"model": "<string>"` (no object wrapper). Same NULL-safety concern as TC-429-S-17 applies (`array_length('{}',1) > 0` must correctly evaluate false, not error/null-propagate into a wrong branch).

### TC-429-S-19 — Single-row boundary (exactly 1 agent in scope)
- **Setup:** Role whose scoped result set is exactly the caller's own single row (mirrors live `graybeard`/`gem` shape).
- **Expected:** Valid single-element JSON array `[ {...} ]`, not a bare object — confirms `json_agg` wrapping and `jq '.'` validation both still produce an array for the n=1 case (a classic off-by-a-different-code-path bug class when refactoring aggregate queries).

---

## 7. Error Conditions (consolidated cross-reference)

| Condition | Test ID | Expected |
|---|---|---|
| psql connection/query failure | TC-429-S-11 | No file written, warn, return 1 |
| DB returns 0 rows (post-fix, scoped) | TC-429-S-12 | No file written (not `[]`), warn, return 1 |
| DB returns non-JSON garbage | TC-429-S-13 | No file written, warn, tmp cleaned, return 1 |
| Target unwritable | TC-429-S-14 | No file written, warn, tmp cleaned, return 1 |
| Existing file invalid JSON | TC-429-S-09 | Untouched, warn, hint shown |

---

## 8. `set -e` / #402 Adjacency

### TC-429-R-01 — Regenerate-flag path: bare `_generate_agents_json` call still kills the installer under `set -e` when scoped result is empty
- **Setup:** Peer gateway role (e.g., graybeard) with a valid own-row but before installer reaches SECTION 7/summary; force the "no rows" condition (e.g., own row's model temporarily NULL, or run as a brand-new role with no seeded own-row yet).
- **Steps:** Run the **full** installer (not just the function in isolation) end-to-end against a sparse/fresh DB as that role, with `--regenerate-agents-json` or on first install, exactly as #402 describes.
- **Expected (documenting current/expected-unfixed behavior):** Installer exits immediately after this section under `set -euo pipefail`, before SECTION 7 and the final summary, with no ERROR banner — reproducing #402 exactly. **This test is expected to FAIL (in the "installer completes successfully" sense) until #402 is separately fixed.** Its purpose here is to confirm #429's change does not alter this failure signature and to serve as the regression gate once #402 lands.

### TC-429-R-02 — #429 fix increases real-world hit rate of #402 for peer gateways
- **Setup:** Fresh/sparse staging DB, run installer as `newhart` or `graybeard` (peer gateways with few or no owned subagent rows yet).
- **Steps:** Full installer run.
- **Expected:** Document observed frequency: pre-fix, the global `instance_type != 'peer'` query almost always returns *some* rows (since it ignores caller identity), masking #402 in most manual test runs. Post-fix, a peer gateway with zero currently-parented subagents will hit the "no rows" `return 1` path far more often — because scoping is now correct, sparse-but-valid results become the common case rather than the rare one. **Recommend to Project Leadership:** #402 should be prioritized to land in the same release as #429, or #429's PR should include the minimal guard (`_generate_agents_json || true` style, or explicit empty-is-ok handling) rather than shipping the scoping fix while leaving the installer newly more fragile for exactly the population (peer gateways) that #429 is meant to help.

### TC-429-R-03 — Out-of-scope confirmation: `_generate_agents_json`'s internal `return 0`/`return 1` contract is unchanged by #429
- **Setup:** N/A — code inspection test.
- **Steps:** Diff the function's return-value contract (success=0, all failure modes=1) before and after the #429 patch.
- **Expected:** Contract identical; #429 only changes the SQL source (FROM/WHERE), not the surrounding success/failure/return plumbing. If the implementer touches the `return` logic while doing this fix, that expands scope beyond #429's acceptance criteria and should be split into (or explicitly folded into) the #402 fix with its own review.

---

## 9. Summary of Coverage vs. Requested Areas

| Requested area | Covered by |
|---|---|
| Happy path — fresh install | TC-429-S-01 |
| Scoping — different session_users | TC-429-S-03…07 |
| Output-shape parity / idempotence | TC-429-P-01…07 |
| Shape details (fallbacks, subagents, default, heartbeat) | TC-429-P-02…06 |
| #252 safety guards | TC-429-S-08…14 |
| Error conditions | §7 table |
| set -e / #402 adjacency | TC-429-R-01…03 |
| Boundary: NULL model, empty vs NULL arrays | TC-429-S-15…19 |

---

## 10. Coverage Questions / Scope Concerns for Project Leadership

1. **Byte-identical vs semantically-identical parity (TC-429-P-01):** The acceptance criterion says "idempotent on first plugin sync," which only requires the plugin's `syncAgentsConfig()` to detect no-op (string equality against its own `JSON.stringify(data, null, 2) + "\n"` serialization). This means the **installer's `jq '.'`-based pretty-print must byte-match Node's `JSON.stringify(..., null, 2)`** output exactly (same 2-space indent, same trailing newline, same key ordering within each object) or idempotence will fail on the very first plugin startup after install. Recommend the implementer either (a) verify `jq` default formatting matches, or (b) have the installer shell out to the same Node serialization path instead of `jq '.'` for final formatting. This needs explicit verification before merge, not just "looks fine."
2. **Sort-order parity (TC-429-P-07):** SQL `ORDER BY text` uses DB collation; JS uses `localeCompare()`. These are not guaranteed identical for non-trivial name sets. Low risk given current agent names are all lowercase ASCII, but worth one explicit test rather than assuming.
3. **Status filter behavior change (TC-429-S-16, F4):** The current inline query has no `status='active'` filter; `get_agent_export_rows()` adds one. This is a real behavior change beyond "just switch the data source" — any currently-inactive-but-modeled agent would silently disappear from a freshly generated `agents.json` after this fix. Recommend Project Leadership explicitly confirm this is desired (it almost certainly is, but it wasn't called out in the AC).
4. **#402 sequencing (TC-429-R-02):** Recommend #402 lands in the same PR/release as #429, or #429 adds a minimal non-fatal guard around the "no rows" return path. Shipping #429 alone increases the real-world frequency of #402's failure mode specifically for peer gateways — the population this fix is meant to help most.
5. **`is_default` semantics (TC-429-P-04, F3/F5):** Confirming this is intentional, not a latent function bug: `get_agent_export_rows()` deliberately overrides `is_default` per-branch (own row = true, subagent rows = false) rather than surfacing the table's actual `is_default` column. If this is intentional (e.g., "default" here means "is this gateway's identity row" rather than "is this the ecosystem-wide default agent"), no action needed — just confirming the test oracle (trust the function's output, not the table) is correct before I finalize pass/fail criteria against it.
6. **No test environment was available to actually execute these cases during design** (design-only per task constraints) — recommend Flint (QA Executor) run TC-429-S-03/04/07 first as the highest-value regression proof (they are the ones that should visibly flip from FAIL→PASS pre/post fix), followed by the full P-* parity suite, before broader sign-off.

---

*Test IDs use the `TC-429-<layer>-##` convention (S=shell/installer, P=parity, R=set -e/#402 regression), consistent with the existing `TC-<issue>-<layer>-##` scheme already established in `agent-config-sync/src/sync.test.ts`.*
