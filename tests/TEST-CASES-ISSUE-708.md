# Test Cases — nova-mind#708, #710, #706, #703 (Chunk B: sessions/transcripts)

**SE run #1231, step 3 — QA test-case design (Chunk B)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #708 (external_thread_id/last_message_at upsert), #710 (retire JSONL ingest/rm, fix other
`sessions/*.jsonl` readers), #706 (anchor memory sources only to `nova_memory` channel_sessions/channel_transcripts),
#703 (memory-extract handler fails loudly on unresolved `<peer>_memory`, no fallback). Chunk B of tracking issue
#715. Continues in the same pinned clone/branch as Chunk A.

---

## 0. Pinned source artifacts

- **nova-mind:** same clone, `~/repos/se1231-nova-mind`, branch `fix/se1231-openclaw-2026.9-regressions`, base
  `12ecc0b`. Chunk A revisions already committed on top (`872add5`, `5052241`); working tree clean before this
  analysis.
- **OpenClaw host behavior reference:** `/home/nova/nova-openclaw-production` at `6ced19b` (2026.9.6),
  `src/plugins/hook-message.types.ts` — read-only reference for `message_received`'s actual event shape.
- **Source under test:** `memory/hooks/memory-extract/handler.ts` (598 lines, read in full), `memory/scripts/
  memory-catchup.sh` (JSONL ingest block, lines ~257–449, read in full), `memory/scripts/extract_memories.py`
  (`store_extracted`/persistence path, read in part).
- **Live DB inventory (read-only, `psql -U gem`, `dt.sh` run first per instructions):** `nova_memory` on
  `localhost`, schemas for `channel_sessions`, `channel_transcripts`, `entity_facts`, `memory_embeddings`
  retrieved via `dt.sh`; row-level facts below via plain `SELECT`/`GROUP BY` — no writes performed.

---

## 1. Inventory findings (REQUIRED pre-step for #706; also resolves a live #708 contradiction)

**Schema today** (via `dt.sh`):
- `channel_sessions`: unique index `idx_channel_sessions_provider_chat` on `(provider, external_chat_id,
  COALESCE(external_thread_id, ''))`. Columns include `external_thread_id` (nullable text), `last_message_at`
  (nullable timestamptz), `raw_metadata` (nullable jsonb) — all three exist in schema already; the bug is that
  nothing writes them on the live code path.
- `channel_transcripts`: unique index `idx_channel_transcripts_provider_msg` on `(session_id,
  external_message_id)`; `raw_metadata` jsonb, nullable.
- `entity_facts`: already has `source_channel_transcript_id` (FK → `channel_transcripts.id`) and
  `source_channel_session_id` (FK → `channel_sessions.id`) — i.e., the "anchor only to nova_memory sessions/
  transcripts" mechanism #706 wants is ALREADY the schema's intended FK shape. #706 is a data-integrity/consistency
  question (are these FKs actually always populated correctly, with nothing anchored elsewhere), not a schema
  migration.
- `memory_embeddings`: anchors via `(source_type, source_id)`, unique on that pair. Live `source_type`
  distribution (`GROUP BY`, read-only): `agent_chat` 48,172 · `entity_fact` 23,090 · `research` 8,097 ·
  `memory_file` 7,575 · `research_finding` 6,206 · `vocabulary` 4,677 · `event` 3,767 · `lesson` 2,334 ·
  `workflow_run` 1,222 · `entity` 1,083 · (+9 smaller types). Sampled `entity_fact`-typed rows: `source_id` is a
  bare `entity_facts.id` integer string (e.g. `"10031"`), i.e. NOT a direct `channel_transcripts`/`channel_sessions`
  id — it's one join away (`entity_facts.source_channel_transcript_id`). This is the existing anchor chain
  §3 (#706) tests must verify stays intact (embedding → entity_facts.id → source_channel_transcript_id →
  channel_transcripts), not re-anchor embeddings directly to transcripts (out of scope / unnecessary churn).

**Empirical check that resolves a direct contradiction in #708's scope (REQUIRED — flagging per source-artifact
pinning discipline, do not silently pick a side):**
- The #715 step-2 design comment and this run's Chunk B dispatch both state #708 is **fix-forward only, no
  backfill, because `raw_metadata` is empty on every row**.
- #708's own issue comment (same date, same author) instead says: *"fix the code AND run a one-time backfill that
  re-splits the 34,702 misattached transcripts... using `raw_metadata` thread/chat ids plus timestamps."*
- **Live read-only query:** `SELECT count(*) FROM channel_transcripts WHERE raw_metadata IS NOT NULL` → **0 of
  42,818 rows** (100% NULL). `channel_sessions`: `raw_metadata` non-null = **0 of 155**; `external_thread_id`
  non-null = **0 of 155**; `last_message_at` non-null = **0 of 155**.
- **Mechanistic explanation (reconciles, rather than just flags, the contradiction):** the real-time path
  (`memory-extract/handler.ts`, `INSERT INTO channel_transcripts` at lines 414–427) **never includes
  `raw_metadata` in its column list at all** — only `session_id, external_message_id, timestamp, role, content`
  plus optional sender columns. The **only** code path that ever wrote `raw_metadata` is the JSONL-ingest block in
  `memory-catchup.sh` (`raw_meta=$(echo "$line" | jq -c '.' ...)`, inserted via `ct_cols="...,  raw_metadata"`,
  catchup script lines ~mid-300s) — the exact code #710 removes, and which #706's own comment already says found
  nothing to ingest since the 2.9.x upgrade. **Conclusion: #708's backfill premise (re-splitting from live
  `raw_metadata`) is not executable against current `nova_memory` data — there is nothing there to re-split on.**
  If a backfill is still wanted, its only possible source is the external OpenClaw SQLite backup #706 itself
  mentions ("backfill whatever is only in the 10-11 SQLite backup straight from SQLite") — a structurally different
  operation (cross-database migration from a backup snapshot) than "re-split from `nova_memory.raw_metadata`" as
  #708's comment literally states. **This is flagged as Open Question #1 below — it blocks writing a correct
  backfill test until the orchestrator clarifies which operation is actually intended**, but does not block the
  fix-forward test cases in §2, which are unaffected either way.

---

## 2. Adversarial/config-seam coverage index

| Requirement | Satisfied by |
|---|---|
| Wrong-type/malformed value at a config seam | TC-703-007 (`PGDATABASE` unset), TC-703-008 (`PGDATABASE` set to a nonexistent DB), TC-703-009 (spoofed/malformed `session_key` prefix) |
| Non-identity fixture values | TC-708-003 (two threads in one chat use genuinely different non-empty thread ids, not `""`/`"0"`), TC-703-005 (stranded-row replay fixture has >1 distinct peer, not a single-peer trivial case) |
| Config→runtime seam populated by production code | TC-706-004 (migration runs against the real live-shaped anchor data sampled in §1, not a hand-built fixture) |
| INTENT-level check vs. a live source system | §1's empirical `raw_metadata`/`external_thread_id`/`last_message_at` NULL counts (not asserted from the issue text alone) |
| Source-artifact pinning verified before analysis | §0; `git rev-parse HEAD` checked; `dt.sh` run before any table query per instructions |

---

## 3. #708 — `channel_sessions` upsert: `external_thread_id`, `last_message_at`, uniqueness (9 cases: TC-708-001…009)

**Host-contract citation (REQUIRED — "cite which fields"):** `message_received`'s event type,
`PluginHookMessageReceivedEvent` (production fork `6ced19b`, `src/plugins/hook-message.types.ts:165-182`),
carries `threadId?: string | number` **directly on the event** (line ~169), alongside `senderId?`, `sessionKey?`,
`messageId?`, `metadata?: PluginHookInboundMessageMetadata`. **`handler.ts` never reads `event.threadId` or any
`ctx`/`meta` equivalent anywhere in its 598 lines** — the session-upsert block (lines 379–393) only derives
`chatId`/`provider`/`groupSubject`/`groupSpace`, never a thread id, so `external_thread_id` is always omitted
from the `INSERT` and is therefore always `NULL` (matches §1's live count: 0/155). This is the exact field the
fix must start reading.

### TC-708-001 — Session upsert INSERT includes `external_thread_id` when the host provides `event.threadId`
**Priority:** P1 (Critical) — direct acceptance test.
**Preconditions:** Inbound message with a non-null `threadId` (e.g. a Discord forum/thread reply).
**Steps:** Trigger `message_received` → handler's session-upsert path.
**Expected:** The `INSERT INTO channel_sessions` column list includes `external_thread_id` with the stringified
`threadId` value (handle both the `string` and `number` union member — a numeric `threadId` must be coerced to
text before insertion, not passed as a raw SQL numeric literal next to a `text`-typed column).

### TC-708-002 — Session upsert sets `last_message_at` on both INSERT and the `ON CONFLICT` UPDATE branch
**Priority:** P1 (Critical) — direct acceptance test; closes the literal #708 ask.
**Preconditions:** None special.
**Steps:** Send a message to a brand-new session, then a second message to the same session.
**Expected:** After message 1, `last_message_at` is set (not left `NULL` as it is today on the `INSERT` branch —
today's code has no `last_message_at` column at all in the `INSERT`, matching §1's 0/155 live count). After
message 2, the existing `ON CONFLICT ... DO UPDATE SET` clause (currently only `updated_at = NOW()`, line 392)
also sets `last_message_at = NOW()` (or the message's own timestamp — confirm which timestamp source is intended:
server receipt time vs. message-embedded time, and test the one chosen).

### TC-708-003 — Two threads in the same chat produce two distinct `channel_sessions` rows
**Priority:** P1 (Critical) — direct acceptance test for the compound unique index; non-identity-fixture case (uses
two genuinely distinct, non-empty thread ids, not `""`/`"0"`/omitted, so a collapsed-to-one-row bug is visible).
**Preconditions:** Same `provider` + same `external_chat_id` (e.g. same Discord channel), two different
`threadId` values (e.g. two different forum threads in that channel).
**Steps:** Send one message in thread A, one message in thread B.
**Expected:** Two rows in `channel_sessions`, both sharing `(provider, external_chat_id)` but differing in
`external_thread_id`; each has its own `channel_transcripts` rows (via `session_id` FK); the
`idx_channel_sessions_provider_chat` index does not collapse them (it is keyed on the triple including
`external_thread_id`, so this should already structurally hold — this test exists to catch a regression where the
`INSERT`'s `ON CONFLICT` target column list in code drifts out of sync with the live index definition).

### TC-708-004 — A missing/absent thread id maps to `NULL` consistently across repeated upserts (not `''`/`'0'`/a new row each time)
**Priority:** P1 (Critical) — direct acceptance test; also an adversarial "never silently invent a value" case.
**Preconditions:** A provider/channel that has no thread concept (e.g. a 1:1 DM) — `threadId` absent on every
message.
**Steps:** Send 3 messages in the same DM conversation.
**Expected:** All 3 resolve to the SAME `channel_sessions` row (the `COALESCE(external_thread_id, '')` unique
index treats `NULL` as equal to itself for conflict purposes across repeated `NULL`s — this must be verified
empirically, since `NULL <> NULL` in raw SQL but `COALESCE(..., '')` normalizes it for the index/`ON CONFLICT`
target). The stored `external_thread_id` is `NULL`, never an empty string or the literal string `"undefined""/"none"`.

### TC-708-005 — `threadId` is a number (not a string) → stored as consistent text, not a mixed-type collision
**Priority:** P1 (Critical) — adversarial wrong-type case (the union type is `string | number`).
**Preconditions:** One message with `threadId = 123456789` (number), a second message with `threadId = "123456789"`
(string, same logical thread).
**Steps:** Send both messages.
**Expected:** Both resolve to the SAME `channel_sessions` row (number and its string form must be normalized to the
identical text representation before comparison/storage) — a naive implementation that stores one upsert as
`'123456789'` and computes the conflict key differently for the number-typed input would silently create two rows
for what the channel considers one thread.

### TC-708-006 — `threadId` is an empty string `""` → distinguished from `NULL`/absent per the adversarial step-3 rule
**Priority:** P2 (High) — adversarial malformed-value case, mirrors Chunk A's TC-712-009 pattern.
**Preconditions:** `event.threadId = ""`.
**Steps:** Trigger the upsert.
**Expected:** The implementation does not treat `""` as "no thread" silently equal to the `NULL` case from
TC-708-004 without an explicit decision — assert which behavior is intended (most likely: normalize `""` to
`NULL` before storage, since `COALESCE(external_thread_id, '')` already treats stored `NULL` as `''` for
uniqueness, so storing a literal `''` string is otherwise indistinguishable from `NULL` at the index level but
NOT at the application level if other code checks `IS NULL` explicitly, e.g. `idx_entity_facts_channel_session"'s
`WHERE ... IS NOT NULL` partial-index pattern used elsewhere in this schema).

### TC-708-007 — Uniqueness index `(provider, external_chat_id, COALESCE(external_thread_id,''))` is actually exercised by a true duplicate attempt, not just asserted present
**Priority:** P1 (Critical) — INTENT-level check against the live index, not a spec-vs-spec assertion.
**Preconditions:** An existing `channel_sessions` row for `(provider='discord', external_chat_id='X',
external_thread_id=NULL)`.
**Steps:** Attempt a raw duplicate `INSERT` (bypassing the application's `ON CONFLICT` clause, i.e. a plain
`INSERT` without the conflict target) for the identical `(provider, external_chat_id)` pair with `external_thread_id`
also `NULL`.
**Expected:** PostgreSQL raises a unique-violation at the DB layer (proves the index itself, not just the
application's `ON CONFLICT` clause, enforces the invariant — if the index were ever dropped/altered, the
application-level `ON CONFLICT` target would start failing loudly rather than silently duplicating rows).

### TC-708-008 — Concurrent upserts for the same `(provider, external_chat_id, threadId)` race safely (no duplicate row, no lost `last_message_at`)
**Priority:** P2 (High) — concurrency case, mirrors Chunk A's non-attribution requirement for a different seam.
**Preconditions:** Two near-simultaneous messages in the same thread (e.g. rapid double-send).
**Steps:** Fire both upserts with overlapping timing.
**Expected:** Exactly one `channel_sessions` row exists afterward; `last_message_at` reflects the LATER of the two
messages, not whichever `UPDATE` happened to commit last if that is earlier in message-time than the other
(i.e., if timestamps are used rather than `NOW()`, the update should be monotonic — assert the actual chosen
semantics from TC-708-002).

### TC-708-009 — Backfill (CONDITIONAL — see Open Question #1; do not implement until scope is confirmed)
**Priority:** Blocked/Deferred.
**Note:** Per §1's empirical finding, a backfill sourced from `nova_memory.channel_transcripts.raw_metadata` has
no data to operate on (0/42,818 populated). If the orchestrator confirms the backfill is instead meant to run
against the external OpenClaw SQLite backup (#706's "10-11 SQLite backup"), this test case needs a full rewrite
with that artifact pinned explicitly (source-artifact pinning rule) before any test design proceeds. Placeholder
only — not counted as a real test case in the Chunk B total.

---

## 4. #710 — Retire JSONL ingest/`rm`, fix/retire other `sessions/*.jsonl` readers (7 cases: TC-710-001…007)

### TC-710-001 — `memory-catchup.sh`'s JSONL-ingest block is completely absent after the fix (not just disabled/no-op)
**Priority:** P1 (Critical) — direct acceptance test.
**Preconditions:** Fixed `memory-catchup.sh`.
**Steps:** `grep` the fixed script for `find.*sessions.*jsonl`, `rm -f.*jsonl_file`, and the
`ALL_SESSIONS_DIR`/`INGEST_COUNT` variables from the current block (lines ~257–449 in the pinned ref).
**Expected:** Zero matches — the block is deleted, not commented out or gated behind an always-false flag (a
disabled-but-present block is exactly the kind of dead code the #697/#361 classifier distinct-logging problem
warns against: it looks inert during review but is one config flip from reactivating a path that deletes
OpenClaw-owned files).

### TC-710-002 — Negative test: nothing in nova-mind reads from OpenClaw's agent SQLite store
**Priority:** P1 (Critical) — REQUIRED negative test per the dispatch brief.
**Preconditions:** Full fixed-branch checkout.
**Steps:** `grep -rn` the entire repo (scripts, hooks, Python, TypeScript) for `.sqlite`, `better-sqlite3`,
`sqlite3`, and the literal path fragment `.openclaw/agents` used as a DB connection target (as opposed to a
JSONL-file-glob target, which is being removed anyway).
**Expected:** Zero hits outside of comments/documentation that explicitly describe the OpenClaw-owned store as
out-of-bounds (e.g. the #706/#710 scope-decision comments themselves, if mirrored into source comments — those are
fine; a live `sqlite3.connect(...)`/`new Database(...)` call against that path is not).

### TC-710-003 — Negative test: nothing in nova-mind DELETES from OpenClaw's agent SQLite store or its session files
**Priority:** P1 (Critical) — REQUIRED negative test, distinct from TC-710-002 (read vs. delete are different risk
classes — the current bug is specifically a delete, `rm -f`, line 443 of the pinned `memory-catchup.sh`).
**Steps:** `grep -rn` for `rm -f`/`rm -rf`/`unlink`/`os.remove`/`fs.unlink` within any path containing
`sessions`, `.openclaw/agents`, or `*.jsonl`.
**Expected:** Zero hits. This is the direct regression guard for the exact defect #710 is fixing — a future
contributor must not be able to reintroduce a JSONL-cleanup habit even in a rewritten/refactored form.

### TC-710-004 — `publish-active-sessions.py` is located, then either fixed (no longer reads `sessions/*.jsonl`) or retired (deleted + any scheduler reference removed)
**Priority:** P1 (Critical) — direct acceptance test; **BLOCKED pending artifact location** (see Open Question #2
below — this file was not found anywhere under the pinned nova-mind clone during this design pass; it may live in a
peer repo such as `nova-workspace`, matching the pattern already seen for the agent_chat listener relocation in
`tests/TEST-CASES-ISSUE-579.md`).
**Steps (once located):** Inspect its session-discovery logic.
**Expected:** It reads active-session state from `nova_memory.channel_sessions` (or another sanctioned nova_memory
source), never from `~/.openclaw/agents/*/sessions/*.jsonl` directly.

### TC-710-005 — "The rest" of the `sessions/*.jsonl` readers — full inventory before any fix is accepted
**Priority:** P1 (Critical) — the dispatch brief explicitly says "the rest," implying more than the two named
scripts; an incomplete inventory would let a third reader survive the fix undetected.
**Steps:** `grep -rln` the ENTIRE fixed branch (not just `memory/`) for the glob pattern `sessions/*.jsonl` or
equivalent path-construction code (e.g. `path.join(..., "sessions", ...)` combined with a `.jsonl` filter).
**Expected:** Every hit is enumerated in the PR description and each one is independently triaged as fixed/retired/
confirmed-out-of-scope (e.g., belongs to a different repo) — not silently left unaddressed because the dispatch
brief only named two scripts by example.

### TC-710-006 — Removing the JSONL ingest does not regress live-ingest row counts (the hook path remains the system of record)
**Priority:** P2 (High) — regression guard tied to #706's own importer-findings comment ("Live ingest still works...
that's probably the memory-extract hook... not file import").
**Preconditions:** Before/after row counts on `channel_transcripts`/`channel_sessions` for a fixed observation
window with no JSONL files present (already true today per §1/#706's finding — "since 2.9.x there are no JSONL
files left to find").
**Expected:** No change in ingest rate attributable to removing the JSONL block, since it already finds nothing
today — this test exists to prove that claim empirically on staging rather than relying on the issue comment's
assertion alone (INTENT-level check vs. a live system).

### TC-710-007 — Stale hardcoded path (`agents/main/sessions`, `memory-catchup.sh` line ~23 in the pinned ref) does not resurface in whatever replaces/surrounds the removed block
**Priority:** P2 (High) — regression guard for a second, smaller defect noted in #706's comment but not named in
#710's own text.
**Expected:** The fixed script contains no single-agent-hardcoded session path; any remaining non-ingest uses of
`TRANSCRIPT_DIR` (the existing cache/state-file logic above the ingest block, which is NOT part of the JSONL-ingest
removal) are reviewed for the same staleness and flagged if still hardcoded to `agents/main`.

---

## 5. #706 — Anchor memory sources only to `nova_memory` sessions/transcripts (6 cases: TC-706-001…006)

### TC-706-001 — Inventory (COMPLETE — see §1): current anchor mechanism is already FK-shaped, not ad hoc
**Priority:** Informational / baseline. No action needed beyond what §1 already established: `entity_facts` has
direct FK columns to `channel_transcripts`/`channel_sessions`; `memory_embeddings` anchors one hop further via
`entity_facts.id` for the `entity_fact` source type. This baseline is the reference every other TC-706 case
compares against.

### TC-706-002 — No `entity_facts` row anchors to anything OTHER than `nova_memory` `channel_sessions`/`channel_transcripts`
**Priority:** P1 (Critical) — direct acceptance test; INTENT-level, run against live data.
**Steps:** `SELECT` all distinct non-NULL `(source_channel_transcript_id, source_channel_session_id)` pairs from
`entity_facts` and confirm every `source_channel_transcript_id` resolves via the FK to a real
`channel_transcripts` row (already DB-enforced by the FK constraint, so this test is really about finding rows
that violate the INTENDED invariant in a softer way: e.g. a NULL `source_channel_transcript_id` but a non-NULL
free-text column elsewhere that encodes an OpenClaw-SQLite-origin pointer instead). Grep the `entity_facts`/
`entity_fact_sources` schema and any `source_citation`-shaped text columns for OpenClaw SQLite path fragments
(`.openclaw/agents`, `.sqlite`) smuggled in as string content rather than a structured FK.
**Expected:** Zero such smuggled anchors.

### TC-706-003 — `memory_embeddings` for non-`entity_fact` source types (e.g. `event`, `lesson`, `research`) also resolve to a `nova_memory`-anchored chain, or are explicitly out of scope with a documented reason
**Priority:** P2 (High) — §1's inventory only sampled `entity_fact`; other types (`event` 3,767 rows, `lesson`
2,334 rows, etc.) need the same anchor-chain check before #706 can claim "anchored only to nova_memory
sessions/transcripts" as a system-wide property rather than an `entity_fact`-only one.
**Steps:** For each distinct `source_type`, sample `source_id` and trace it to its owning table; confirm that
table in turn either IS `channel_sessions`/`channel_transcripts` or has its own FK chain back to them, OR is
explicitly documented as anchor-exempt (e.g. `vocabulary`/`library` entries may have no conversational anchor by
design — confirm with the orchestrator which `source_type`s are expected to have no transcript anchor at all).

### TC-706-004 — Migration of existing anchors preserves every currently-valid FK (config→runtime seam: run against real sampled data, not a hand-built fixture)
**Priority:** P1 (Critical) — REQUIRED config→runtime seam case.
**Preconditions:** A snapshot/copy of the real `entity_facts`/`memory_embeddings` anchor data sampled in §1 (not
synthetic rows).
**Steps:** Run whatever migration #706 introduces (if any schema/data change is needed beyond the invariant-audit
above) against this real snapshot on **staging**, never production.
**Expected:** Every row with a pre-migration, DB-FK-valid anchor still resolves to the identical
`channel_transcripts`/`channel_sessions` row post-migration; row counts per `source_type` are unchanged except for
rows the migration was explicitly designed to fix.

### TC-706-005 — New anchors created after the fix use transcript/session ids exclusively — verified on a real staging turn, not asserted from code review alone
**Priority:** P1 (Critical) — direct acceptance test, staging-run (pairs with TC-INT-001's pattern from Chunk A).
**Steps:** On staging (2026.9.6, post-#710/#708 fixes), send one real message that produces a new `entity_facts`
row.
**Expected:** The new row's `source_channel_transcript_id`/`source_channel_session_id` are both populated and
non-NULL, pointing at the SAME turn's real `channel_transcripts`/`channel_sessions` rows (cross-checked by
timestamp/content, not just "a number is present").

### TC-706-006 — Duplicate-transcript tracking note (nova-openclaw#225) does not block Chunk B's own test pass/fail criteria
**Priority:** P3 (Low) — scope-boundary clarity only. The #706 decision comment explicitly defers OpenClaw-SQLite/
nova_memory duplication unification to a separate repo's issue #225. No test in this file asserts anything about
that duplication being resolved; TC-710-002/003's negative tests only assert nova-mind-side read/delete behavior,
which is independent of whether the duplication itself persists.

---

## 6. #703 — memory-extract handler fails loudly on unresolved `<peer>_memory`, no fallback, stranded-row replay (9 cases: TC-703-001…009)

**Note on current-code baseline:** the pinned `handler.ts` (read in full, §0) always targets
`process.env.PGDATABASE || 'nova_memory'` (lines 275, 381, 413, 442 — four separate call sites, all with the same
`|| 'nova_memory'` fallback) for every `psql` invocation it makes directly. **This literal fallback-to-nova_memory
pattern, repeated at all four `execFileAsync('psql', ...)` call sites in `handler.ts`, is itself the "#621/#487"
defect #703 is closing** — distinct from (and in addition to) whatever peer-resolution logic lives in
`extract_memories.py`'s own DB connection setup (not fully traced in this pass — see Open Question #3). Any fix
must address all four `handler.ts` call sites, not just the main extraction script's connection logic.

**Peer-identification mechanism (from live data, read-only):** `extraction_failures.session_key` values observed
follow the pattern `agent:<peer>:...` (e.g. `agent:newhart:agent_chat`, `agent:victoria:discord:channel:...`),
matching #703's own per-agent failure-row counts (nova 4255, newhart 4037, graybeard 1665, victoria 424, athena 4).
This is almost certainly the string peer-resolution derives from — confirm exact parsing logic in implementation
review; test cases below treat this prefix as the resolution input under test.

### TC-703-001 — Unresolvable `<peer>_memory` → loud failure, zero rows written to `nova_memory`
**Priority:** P1 (Critical) — direct acceptance test, the core of #703's decision #1.
**Preconditions:** A `session_key` with peer prefix `agent:unknownpeer:...` where no `unknownpeer_memory` database
exists.
**Steps:** Trigger the handler for this session.
**Expected:** The handler logs an explicit, loud error identifying the unresolved peer/database (not swallowed into
the existing generic `[memory-extract] Unexpected handler error` catch-all at line 592, which per the dispatch
brief's "fail loudly" ask needs its own distinct log signature); **zero** rows are written to `nova_memory` as a
side effect of this turn (verify via a targeted `SELECT` scoped to this test's unique marker content, not a
blanket table count, to avoid false negatives from concurrent unrelated writes on a shared staging DB); the
`extraction_failures` row (if one is still written, per the existing `insertExtractionFailure` pattern) is written
to the CORRECT target — i.e. this failure-logging path must not itself be the accidental `nova_memory` fallback
that #703 is trying to close, since `insertExtractionFailure` (line 275) currently hardcodes the same
`|| 'nova_memory'` pattern.

### TC-703-002 — Resolvable `<peer>_memory` → all writes land in that peer's own DB, never `nova_memory`
**Priority:** P1 (Critical) — direct acceptance test, positive case.
**Preconditions:** `session_key` prefixed `agent:newhart:...`, `newhart_memory` DB exists and is reachable.
**Steps:** Trigger the handler.
**Expected:** `channel_sessions`/`channel_transcripts`/`entity_facts`/`extraction_failures` writes all target
`newhart_memory`; a scoped query against `nova_memory` for this test's unique marker content returns zero rows.

### TC-703-003 — Split stranded `nova_memory` rows by their session_key peer prefix
**Priority:** P1 (Critical) — direct acceptance test for the one-time replay/split operation.
**Preconditions:** A **staging** copy of `nova_memory` seeded with the real stranded-row shape (peer-prefixed
`session_key`s pointing at content that should have gone to `newhart_memory`/`graybeard_memory`/`victoria_memory`).
**Steps:** Run the split/replay tool.
**Expected:** Every stranded row is copied into the correct peer DB with content byte-for-byte identical to the
source row; the original `nova_memory` row is either deleted or explicitly marked migrated (confirm which, and
test that choice) — never left duplicated silently without a marker, which would make a second accidental run
double-insert.

### TC-703-004 — Split/replay is idempotent — running it twice does not double-insert into peer DBs
**Priority:** P1 (Critical) — REQUIRED idempotency case, directly requested in the dispatch brief.
**Preconditions:** TC-703-003 has run once.
**Steps:** Run the split/replay tool again against the same (now partially-migrated) `nova_memory` state.
**Expected:** Row counts in each peer DB are unchanged by the second run; no unique-constraint violations; no
duplicate `entity_facts`/`channel_transcripts` rows for content already migrated.

### TC-703-005 — Multi-peer stranded-row fixture (non-identity case): replay correctly discriminates ≥2 distinct peers in the same batch
**Priority:** P1 (Critical) — REQUIRED non-identity-fixture adversarial case; a single-peer fixture could pass a
split tool that actually just copies everything to one hardcoded target DB.
**Preconditions:** Stranded rows for at least `newhart` AND `victoria` prefixes in the same staging `nova_memory`
snapshot.
**Steps:** Run the split/replay tool once over the mixed batch.
**Expected:** `newhart`-prefixed rows land only in `newhart_memory`; `victoria`-prefixed rows land only in
`victoria_memory`; cross-contamination (a `newhart` row appearing in `victoria_memory` or vice versa) is checked
explicitly, not just "did newhart's rows arrive somewhere."

### TC-703-006 — Victoria's 424 stranded rows despite no DML grant — traced, not just replayed
**Priority:** P2 (High) — #703's own comment flags this as unexplained ("candidates are another role's credentials
or a SECURITY DEFINER path. Needs tracing.") and explicitly still-open in the Decisions comment ("3. Still open:
trace how Victoria's 424 rows got written despite having no grant."). This is a **forensic test, not a fix
acceptance test** — design it to CAPTURE evidence (which role/function actually executed the writes, via
`pg_stat_statements`/audit log if available, or by tracing `extraction_failures`/`entity_facts` row metadata for
a session/connection fingerprint) rather than to assert a specific resolution, since the mechanism is still
unknown at design time.
**Note:** grant changes themselves are explicitly Graybeard's to execute per #703's Decision #2 — this suite only
needs a test that the eventual grant model is as specified (TC-703-010, if added once Graybeard's grant change
lands — flagged as Open Question #4, likely belongs to a later step once grants are actually changed).

### TC-703-007 — Adversarial: `PGDATABASE` unset entirely
**Priority:** P1 (Critical) — REQUIRED adversarial case per dispatch brief; also a direct regression test against
`handler.ts`'s current `process.env.PGDATABASE || 'nova_memory'` pattern at all 4 call sites.
**Preconditions:** Handler invoked in an environment where `PGDATABASE` is not set at all (today's code: the
`||` fallback silently resolves to `'nova_memory'` in this exact case — this is precisely decision #1's target).
**Steps:** Trigger the handler with `PGDATABASE` unset and a peer-prefixed `session_key`.
**Expected:** Loud failure (same signature as TC-703-001), not a silent `nova_memory` write. This test must FAIL
against the pinned `handler.ts` as-is and is the direct acceptance test for removing the `|| 'nova_memory'`
literal.

### TC-703-008 — Adversarial: `PGDATABASE` set to a database name that does not exist
**Priority:** P1 (Critical) — REQUIRED adversarial case; distinct failure mode from TC-703-007 (unset vs.
set-but-wrong).
**Preconditions:** `PGDATABASE=nonexistent_peer_memory_db`.
**Steps:** Trigger the handler.
**Expected:** `psql`'s own connection failure (`FATAL: database "nonexistent_peer_memory_db" does not exist`) is
caught and surfaced as a loud, distinct-reason failure (not silently swallowed by the existing generic
`logPsqlError`, which today logs only `err.message` at a single generic site, line 218-225 — confirm the fix adds
a classification, mirroring the Chunk A classifier-distinct-reason pattern accepted in step 4); no write occurs
anywhere, including no accidental fallback write to `nova_memory` if `PGDATABASE` was ALSO technically resolvable
as a secondary fallback in some code path.

### TC-703-009 — Adversarial: spoofed/malformed `session_key` prefix
**Priority:** P1 (Critical) — REQUIRED adversarial case per dispatch brief.
**Preconditions:** Three variants: (a) `session_key = "agent:nova:agent_chat"` content but `PGDATABASE` pre-set to
`newhart_memory` by the caller (prefix/env mismatch — which wins, and is the mismatch itself detected and
rejected?); (b) `session_key` with a peer segment that doesn't match any known peer at all (e.g.
`"agent:totallymadeuppeer:x"`); (c) `session_key` missing the `agent:<peer>:` prefix shape entirely (e.g. a bare
`"discord:channel:123"` string with no `agent:` segment, if that shape is possible for any current caller).
**Steps:** Trigger the handler for each variant.
**Expected:** (a) is detected as a mismatch and fails loudly rather than silently trusting one source over the
other without validation; (b) and (c) both fail loudly with a reason identifying parse failure (distinct from
"peer resolved but DB unreachable," TC-703-008) — none of the three silently falls back to `nova_memory`.

---

## 7. Open questions for the orchestrator / Project Leadership review

1. **#708 backfill scope contradiction (§1, REQUIRED resolution before TC-708-009 can be written for real):**
   #715's step-2 comment and this run's dispatch both say #708 is fix-forward-only because `raw_metadata` is empty
   on every live row — confirmed empirically (0/42,818). #708's own issue comment instead describes a backfill
   using `raw_metadata` thread/chat ids, which has no data to operate on today. Is the backfill (if any) actually
   meant to run against the external OpenClaw SQLite backup mentioned in #706's comment (a different artifact,
   needing its own pinning), or is #708's comment simply stale/superseded by the step-2 design decision? This
   changes whether TC-708-009 is real work or drops out of Chunk B entirely.
2. **`publish-active-sessions.py` location (TC-710-004):** not found anywhere in the pinned nova-mind clone. Likely
   relocated to a peer repo (`nova-workspace`?) per the same pattern already documented in
   `tests/TEST-CASES-ISSUE-579.md`'s agent_chat-listener relocation note. Needs a pinned artifact location before
   TC-710-004/005 can be finalized.
3. **#706's scope for non-`entity_fact` `memory_embeddings` source types (TC-706-003):** confirming whether
   `vocabulary`/`library`/`agent_chat`-typed embeddings are expected to have a `nova_memory` conversational
   anchor at all, or are intentionally anchor-exempt by design.
4. **#703's Victoria-write-path tracing (TC-703-006)** and the **grant-hardening step** are explicitly still-open/
   deferred to Graybeard per the issue's own Decisions comment. Confirming these stay out of Chunk B's pass/fail
   bar (this suite only tests the handler's fail-loud/no-fallback/replay behavior, not the grant model itself).
5. **`handler.ts`'s 4 separate `|| 'nova_memory'` call sites (§6 note)** vs. whatever peer-resolution logic exists
   in `extract_memories.py`'s own connection setup, which was not fully traced in this pass (the Python script's
   DB-connection construction wasn't located within the time budget for this design pass — `store_extracted`'s
   `conn` parameter is passed in from a caller not yet traced). Confirming both code paths are in scope for the
   same PR, since a fix to only `handler.ts`'s `psql` calls would leave the Python extraction path's own
   connection logic unaudited.
