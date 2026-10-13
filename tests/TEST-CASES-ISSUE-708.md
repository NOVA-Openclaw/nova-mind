# Test Cases — nova-mind#708, #710, #706, #703 (Chunk B: sessions/transcripts)

**SE run #1231, step 3 — QA test-case design (Chunk B)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #708 (external_thread_id/last_message_at upsert), #710 (retire JSONL ingest/rm, fix other
`sessions/*.jsonl` readers), #706 (anchor memory sources only to `nova_memory` channel_sessions/channel_transcripts),
#703 (memory-extract handler fails loudly on unresolved `<peer>_memory`, no fallback). Chunk B of tracking issue
#715. Continues in the same pinned clone/branch as Chunk A.

---

## Revision Log

**Rev 1 (2026-10-13, step 4 — I)ruid's answers to Chunk B open questions, 18:04 UTC):**
- **#708:** No backfill confirmed — fix forward only. **TC-708-009 dropped** (was a deferred placeholder, never a
  real test; see Open Question #1 resolution). **New identification-only requirement**: a read-only query listing
  every `channel_transcripts` row attached to a session it doesn't belong to — but this run's acceptance is
  IDENTIFICATION ONLY, not removal (removal is explicitly not approved yet). Added TC-708-010 (identification query)
  and TC-708-011 (removal — written but marked blocked/not-in-this-run's-acceptance pending approval). Investigated
  live, read-only, what "misattached" actually means for session 15 (`agent:nova:agent_chat`, 18,632 of the
  provider's 29,287 rows) and Discord (105 sessions, 12,836 rows): **finding is "right chat, not split by
  thread/session" for agent_chat, not cross-chat contamination** — see new §1b.
- **#710:** `publish-active-sessions.py` located — lives in `NOVA-Openclaw/nova-workspace` (pinned `da56b303`,
  `scripts/publish-active-sessions.py`), root crontab (`*/2 * * * *`), writes `nova-active-sessions.jsonl` to
  `/opt/agents/shared-diagnostics/` for a memory-pressure "ratchet experiment" — confirmed read-only w.r.t. the
  gateway, confirmed it does NOT import anything into `nova_memory`. TC-710-004 rewritten as a confirmation case
  (not a fix case); TC-710-008/009 added for script+cron removal and the "nothing else reads the jsonl" negative
  test, grepped across both pinned repos.
- **#706:** TC-706-003 **rewritten** per the corrected model — every memory type gets source attribution via its
  OWN anchor (conversation → `channel_transcripts`, agent_chat → its agent_chat message, vocabulary/library/
  research/lessons/events → their own source record), not only conversation-derived memories. New test matrix: one
  case per `memory_embeddings.source_type`, each asserting the anchor resolves to a real row, plus one end-to-end
  "follow the anchor" case from a semantic-search hit through to the original source.
- **#703:** BOTH `handler.ts` (4 call sites) AND `extract_memories.py`'s connection setup are confirmed in scope.
  Traced the Python caller: `get_db_connection()` (`extract_memories.py:77-79`) wraps a bare `psycopg2.connect()`
  with NO explicit `dbname` — it resolves PG* env vars exactly as `psql` does; called at `extract_memories.py:1242`.
  **New finding, upgrades the whole section's risk model**: `~/.openclaw/postgres.json` (the shared config
  `pg-env.sh` reads) has a **top-level `"database": "nova_memory"`** default. This means an agent whose own
  environment doesn't explicitly override `PGDATABASE` does NOT get an empty/unset value that trips `handler.ts`'s
  `|| 'nova_memory'` literal — it gets a real, valid-looking `PGDATABASE=nova_memory` from the SHARED config,
  which is indistinguishable at the code level from "this really is nova's own DB." **The fix cannot just remove
  the hardcoded literals — it must validate the resolved `PGDATABASE` against the peer identity derived from
  `session_key`, and fail loudly on a mismatch, not merely on "unset."** New TC-703-010 added for this exact case.
  (Per workspace security norms, the config file's credential fields are not reproduced here — only the
  `"database"` key's value is cited.)
- Victoria's write-path tracing and grant hardening confirmed **out of Chunk B's pass/fail bar**
  (nova-workspace#252) — TC-703-006 downgraded from "forensic test" framing to an explicit out-of-scope note.
- Open questions #1, #2, #4, #5 from Rev 0 resolved by this review; #3 resolved by the TC-706-003 rewrite. See §7.
**Rev 2 (2026-10-13 19:30 — I)ruid's corrections to Rev 1):**
- **TC-703-010 DROPPED.** `~/.openclaw/postgres.json` is nova's own file; peers run under their own unix users
  with their own `postgres.json` pointing at their own DBs. The leak path is purely `handler.ts`'s
  `|| 'nova_memory'` literal fallback — nothing else. §6's intro note corrected.
- **§1b's "agent_chat already correctly partitions by peer" conclusion was WRONG and is corrected.** Re-verified
  live: sessions 155 (`graybeard`, 4,579 rows), 10871 (`newhart`, 5,377 rows), and 52442 (`victoria`, 629 rows) —
  **10,585 rows total** — are each peer's OWN inbound agent_chat transcript, written into `nova_memory` (the wrong
  database) via the #703 fallback, not nova's own correct data. Sessions 9216/8478/9426 (32 rows: nova-staging/
  main/newhart-only-sub) are also wrong-place but have no owning peer DB to migrate to. Session 15 (nova, correct)
  and 57900 (athena, correct) remain genuinely correct, modulo junk test-sender rows mixed into session 15.
- **New backup→migrate→remove pipeline added**, per I)ruid's rule (never delete correct-chat data; wrong-place
  peer rows get backed up, verified, idempotently copied to the owning peer's `<peer>_memory`, then removed only
  after both pass; non-peer/test junk gets backed up and removed, never migrated). TC-708-010 through TC-708-015
  replace the prior TC-708-010/011 identification/removal-placeholder pair. Case count: 11 → 15 for #708; 9 → 8 for
  #703 (TC-703-010 removed).

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

## 1b. Empirical investigation: CORRECTED per step-4 review (2026-10-13 19:30) — this IS cross-database contamination for peer rows

**Correction notice:** this section's Rev-1 conclusion ("agent_chat already correctly partitions by peer... not
cross-chat contamination") was **WRONG** and is corrected here per I)ruid's step-4 review. The error: "correctly
partitions by peer" conflated "each peer has its own `channel_sessions` row" with "each peer's row is in the right
DATABASE" — it is not. `nova_memory` is NOVA's own database; peer agents (graybeard, newhart, victoria) each run
under their own unix user with their own `postgres.json` pointing at their own `<peer>_memory` database. NOVA has
exactly 3 peer agents. A `channel_sessions` row with `external_chat_id='agent_chat:<peer>'` sitting inside
`nova_memory` for one of those 3 peers is NOT nova's data living in nova's inbox — **it is that peer's own
inbound agent_chat transcript, written into the wrong database**, because that peer's gateway ran the shared
memory-extract hook and hit #703's `|| 'nova_memory'` fallback.

**Corrected, re-verified live counts** (`provider='agent_chat'`, all 8 sessions, re-queried and matching I)ruid's
own figures exactly):

| session_id | session_key | rows | disposition |
|---|---|---|---|
| 15 | `agent:nova:agent_chat` | 18,632 | **CORRECT** — nova's own inbox (contains legitimate traffic from graybeard/newhart/victoria/others addressed TO nova — see TC-708-013 for the junk-sender carve-out inside this otherwise-correct session) |
| 155 | `agent:graybeard:agent_chat` | 4,579 | **WRONG DATABASE** — graybeard's own inbound transcript (senders: nova 4,006 · newhart 289 · victoria 262); belongs in `graybeard_memory` |
| 10871 | `agent:newhart:agent_chat` | 5,377 | **WRONG DATABASE** — newhart's own inbound transcript (senders: nova 2,652 · graybeard 2,474 · victoria 233); belongs in `newhart_memory` |
| 52442 | `agent:victoria:agent_chat` | 629 | **WRONG DATABASE** — victoria's own inbound transcript; belongs in `victoria_memory` |
| 9216 | `agent:nova-staging:agent_chat` | 24 | **WRONG PLACE, NOT A MIGRATION TARGET** — staging writing into production; no real "nova-staging_memory" peer DB to migrate to (staging is a deployment of nova herself, not a third party) |
| 8478 | `agent:main:agent_chat` | 7 | **WRONG PLACE, NOT A MIGRATION TARGET** — test/legacy identity, no owning peer DB |
| 9426 | `agent:newhart-only-sub:agent_chat` | 1 | **WRONG PLACE, NOT A MIGRATION TARGET** — test/legacy identity, no owning peer DB |
| 57900 | `agent:athena:agent_chat` | 38 | **CORRECT** — athena is NOVA's own subagent, so her agent_chat traffic correctly belongs in `nova_memory` |

**Total rows confirmed in the WRONG database for the 3 real peers: 4,579 + 5,377 + 629 = 10,585** (matches I)ruid's
figure exactly). Plus 32 rows in three non-peer "wrong place" sessions (staging/main/newhart-only-sub) that have
no legitimate owning peer database to migrate to — these are backup-and-remove-only, never migration targets. Plus
an unknown number of test-sender rows (`zztest_a`, `schema-sync`, and similar) living INSIDE the otherwise-correct
session 15 — these are junk mixed into real data, not a whole-session misplacement, and also fall under
backup-and-remove-only (not migration, since they aren't real peer traffic at all).

**I)ruid's rule governing all remediation test design below: NEVER delete anything that is in the correct chat.**
For peer rows (graybeard/newhart/victoria, 10,585 rows): **backup (verified) → idempotent copy into the owning
peer's `<peer>_memory` (the same split/replay pattern as #703's `extraction_failures` idempotent replay) →
remove from `nova_memory` only after BOTH the backup and the migration are independently verified.** For
non-peer wrong-place rows and in-session test/junk senders (32 + session-15 junk): **backup → remove; do NOT
migrate** (there is no legitimate destination database for synthetic/staging/legacy test identities).

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

## 3. #708 — `channel_sessions` upsert: `external_thread_id`, `last_message_at`, uniqueness, misattachment identification+backup+migration+removal (15 cases: TC-708-001…015; see Revision Log Rev 2 for the backup→migrate→remove pipeline added 2026-10-13 19:30)

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

### TC-708-010 — IDENTIFICATION: exact row/sender counts per wrong-place session (read-only, re-verifies I)ruid's figures)
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED first step before any backup/migration/removal.
**Steps:** Run the §1b query (grouped by `cs.id`/`session_key`/`external_chat_id`, joined row counts, plus a
per-sender breakdown for each flagged session) against live `nova_memory`.
**Expected:** Reproduces exactly: session 155 (graybeard) 4,579 rows; session 10871 (newhart) 5,377 rows; session
52442 (victoria) 629 rows (10,585 total peer rows); session 9216 (nova-staging) 24; session 8478 (main) 7; session
9426 (newhart-only-sub) 1 (32 total non-peer wrong-place rows); plus an enumerated count of non-real-agent senders
(`zztest_a`, `schema-sync`, and similar) inside the otherwise-correct session 15. Session 15's REAL traffic and
session 57900 (athena) are both explicitly confirmed NOT flagged (negative check folded into the same query).

### TC-708-011 — Verifiable BACKUP of every wrong-place row (row counts + checksums), before any copy/removal
**Priority:** P1 (Critical) — REQUIRED by I)ruid's rule ("backed up first (verified backup)").
**Preconditions:** TC-708-010's identification set.
**Steps:** Back up (e.g. `COPY ... TO`, or an equivalent snapshot table) every row in sessions 155/10871/52442/
9216/8478/9426 plus the enumerated junk senders inside session 15. Compute a content checksum (e.g. per-row hash of
the transcript content + timestamp + sender, and an aggregate hash of the whole backup set) alongside a row count.
**Expected:** Backup row count exactly matches TC-708-010's identification count for each session; a re-hash of the
backup against a fresh re-read of the source rows matches bit-for-bit (proves the backup is a faithful, verifiable
copy, not just "a file got written"). This artifact is a hard precondition gate for TC-708-013 (removal) below.

### TC-708-012 — Idempotent MIGRATION of peer rows into the owning peer's own `<peer>_memory` database
**Priority:** P1 (Critical) — direct acceptance test for the 10,585 peer rows ONLY (sessions 155/10871/52442);
explicitly does NOT apply to the 32 non-peer wrong-place rows or the in-session junk senders (no migration target
for those — see TC-708-014). Mirrors Chunk B §6's #703 split/replay pattern (`extraction_failures` idempotent
replay) applied to `channel_sessions`/`channel_transcripts`.
**Preconditions:** TC-708-011's verified backup exists for the 3 peer sessions.
**Steps:** Copy session 155's rows into `graybeard_memory`, session 10871's into `newhart_memory`, session
52442's into `victoria_memory` — preserving original row content, timestamps, and (per #708's own constraint from
the original issue comment) `channel_transcripts.id` where the destination schema allows it, so any existing
cross-references survive. Run the migration TWICE.
**Expected:** After the first run, each peer DB has exactly the migrated row count, content-identical to the
backup (checksum match). After the SECOND run (idempotency check), row counts in each peer DB are UNCHANGED — no
duplicate rows, no unique-constraint violations — mirroring Chunk B's existing TC-703-004 idempotency pattern.

### TC-708-013 — REMOVAL from `nova_memory` gated on BOTH backup (TC-708-011) and migration (TC-708-012) passing — for peer rows only
**Priority:** P1 (Critical) — direct acceptance test for the ordering/gating rule itself, not just the removal
action. Applies to the 3 peer sessions (155/10871/52442).
**Preconditions:** TC-708-011 (backup) AND TC-708-012 (migration) have BOTH independently verified as passing for
these 3 sessions.
**Steps:** Attempt removal (a) with only a backup verified but no migration verification — MUST be refused/blocked;
(b) with only a migration verified but no backup verification — MUST be refused/blocked; (c) with both verified —
proceeds.
**Expected:** Removal only proceeds in case (c). Cases (a) and (b) are explicit negative tests for the gating logic
itself — a tool that lets removal proceed with only one of the two prerequisites satisfied fails this test even if
the eventual row deletion is otherwise correct, since that's exactly the "deleted before it was safe to" failure
mode the whole backup→migrate→remove ordering exists to prevent.

### TC-708-014 — Non-peer wrong-place rows and in-session junk senders: BACKUP + REMOVE ONLY, never migrated
**Priority:** P1 (Critical) — REQUIRED distinct path from TC-708-012/013, per I)ruid's explicit instruction ("Test/
staging junk rows: back them up and remove them; don't migrate them.").
**Preconditions:** TC-708-011's backup covers sessions 9216 (nova-staging, 24 rows), 8478 (main, 7), 9426
(newhart-only-sub, 1), and the enumerated junk senders inside session 15.
**Steps:** After backup verification (same checksum standard as TC-708-011), remove these rows from `nova_memory`
WITHOUT any migration step.
**Expected:** These 32 rows (plus the session-15 junk-sender rows) are gone from `nova_memory` post-removal, exist
only in the verified backup, and are NOT present in any peer's `<peer>_memory` database (explicit negative check —
confirms the "don't migrate test/staging junk" instruction wasn't accidentally satisfied by a migration tool that
doesn't distinguish real peer rows from junk).

### TC-708-015 — NEGATIVE TEST: correct-chat rows (session 15's real traffic, session 57900/athena) are left completely untouched
**Priority:** P1 (Critical) — REQUIRED by I)ruid's rule ("NEVER delete anything that's in the correct chat"); this
is the single most important safety test in this file's #708 section, since a bug here would destroy nova's own
real, correct agent_chat history.
**Preconditions:** The full backup/migrate/remove pipeline (TC-708-011 through TC-708-014) has run against the
flagged wrong-place sessions.
**Steps:** Before/after row-count AND content-checksum comparison for session 15's non-junk rows and all of
session 57900 (athena).
**Expected:** Byte-for-byte identical before and after — zero rows modified, moved, or deleted; zero rows added.
Any difference, even a single row, FAILS this test regardless of what else passed.


---

## 4. #710 — Retire JSONL ingest/`rm`, confirm/retire `publish-active-sessions.py` (9 cases: TC-710-001…009)

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

### TC-710-004 — `publish-active-sessions.py` confirmed located and confirmed NOT an ingest path (resolved per step-4 review — RETIRE the whole misconception, not the script)
**Priority:** P1 (Critical) — direct acceptance test; **located**: `NOVA-Openclaw/nova-workspace`
(pinned `da56b303`), `scripts/publish-active-sessions.py`, scheduled via root crontab `*/2 * * * *`.
**Source confirms (read in full, lines 1-60):** it is read-only w.r.t. the gateway (reads
`~/.openclaw/agents/nova/sessions/sessions.json` and `/proc` only — "Never signals, never touches the gateway
process"), and writes `/opt/agents/shared-diagnostics/nova-active-sessions.jsonl` for graybeard's
gateway-mem-watch sampler ("ratchet experiment" memory-pressure denominator). **It does NOT import anything into
`nova_memory` and was never part of the memory-extract ingest path** — per-turn ingestion via `memory-extract/
handler.ts` is confirmed (per step-4 review) as the ONLY ingest path. **No SQLite→nova_memory importer design is
in scope anywhere in this file** — this corrects a possible misreading of the original #710 dispatch brief's "fix
or retire" framing: there is nothing to FIX here (it was never broken in the sense #710 cares about), only to
confirm it stays out of nova_memory's ingest path.
**Steps:** Confirm the script's read target (`sessions.json`) and write target (`nova-active-sessions.jsonl`)
match the above; confirm no `psql`/`psycopg2`/DB-connection code exists anywhere in the script.
**Expected:** Zero DB-connection code in the script; it remains purely a diagnostics-snapshot tool, independent of
the #708/#703/#706 ingest-path fixes in this file.

### TC-710-008 — `publish-active-sessions.py` and its crontab line are actually removed (if retirement is the chosen outcome) or explicitly kept with a documented reason
**Priority:** P1 (Critical) — direct acceptance test matching the dispatch brief's literal ask ("the script and its
cron line are removed").
**Preconditions:** Fixed `nova-workspace` branch/deploy.
**Steps:** `crontab -l` no longer contains the `publish-active-sessions.py` line; `scripts/publish-active-
sessions.py` is absent from the repo (or, if kept for the ratchet experiment's own purposes, an explicit decision
record exists stating why it's out of #710's removal scope — confirm with the orchestrator which outcome is
intended, since the dispatch brief says "removed" but the script's own purpose (diagnostics for a live, separate
memory-pressure investigation) is unrelated to the nova_memory ingest concern #710 is actually about).

### TC-710-009 — Negative test: nothing else reads `nova-active-sessions.jsonl`
**Priority:** P1 (Critical) — REQUIRED negative test, grepped across BOTH pinned repos per the dispatch brief.
**Steps:** `grep -rln "nova-active-sessions"` across the pinned `nova-mind` clone (`12ecc0b`+Chunk A/B commits) AND
the pinned `nova-workspace` clone (`da56b303`). **Result at design time: the only hit in either repo is the
producer script itself** (`nova-workspace/scripts/publish-active-sessions.py`) — zero consumers found in either
pinned checkout.
**Expected:** This remains true after whatever #710 changes land — if a consumer is ever added, it must read from
`nova_memory` directly, never from this diagnostics-only jsonl file, and this test must be updated to assert that
new consumer also behaves correctly rather than silently passing because grep still finds nothing.

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

## 5. #706 — Every memory type gets its own resolvable source anchor (7 cases: TC-706-001, 002, 003, 003b, 004, 005, 006 — TC-706-003 rewritten per step-4 review, TC-706-003b added)

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

### TC-706-003 — EVERY `memory_embeddings.source_type` has a resolvable anchor to its own real source record (REWRITTEN per step-4 review — corrected model: all memories get attribution, not only conversation-derived ones)
**Priority:** P1 (Critical) — corrected scope, direct acceptance test, one sub-case per `source_type`.
**Corrected model (per I)ruid, step 4):** the per-turn flow is semantic search → pointers to `entity_facts`/chunks
injected into the prompt → if the model needs more, it follows the chunk's anchor to its ORIGINAL source. Every
memory type anchors to its OWN kind of source record, not uniformly to `channel_transcripts`:
- `entity_fact` → `entity_facts.id` → (`source_channel_transcript_id` / `source_channel_session_id`) → `channel_transcripts`/`channel_sessions`
- `agent_chat` → its own agent_chat message (the shared `agent_chat` database's message table, NOT `channel_transcripts` — these are two distinct storage systems per #706's own decision comment, which explicitly tracks their duplication as out-of-scope-for-now via nova-openclaw#225)
- every remaining type (`research`, `memory_file`, `research_finding`, `vocabulary`, `event`, `lesson`,
  `workflow_run`, `entity`, `research_task`, `research_conclusion`, `task`, `journal_entry`, `library`,
  `artwork`, `comms_digest`, `motivation_d100`, `music_work`, `blog_post`) → its own dedicated source table/record
  (e.g. `events`, `lessons`, `research_findings` or equivalent — confirm each table name in implementation review)
**Steps:** For EACH distinct `source_type` observed live (§1's 20 types), sample at least one `source_id`, and:
1. Confirm a real, resolvable row exists in that type's owning table for the sampled `source_id` (not a dangling
   reference — this is the per-type positive resolution test).
2. Confirm the owning table/row, in turn, carries (or can itself trace to) its own provenance — e.g. an `event`
   row should know when/how it was observed, a `lesson` row should know what generated it — even when that
   provenance is NOT a `channel_transcripts`/`channel_sessions` row (e.g. a `lesson` derived from a workflow run's
   own metadata, not a conversation turn).
**Expected:** All 20 live `source_type`s resolve to a real row in their respective owning table via
`(source_type, source_id)`; zero dangling/unresolvable anchors found; no `source_type` is left undocumented as
"unknown where this points."

### TC-706-003b — End-to-end "follow the anchor" path: a semantic-search hit resolves all the way back to its original source record
**Priority:** P1 (Critical) — REQUIRED by step-4 review ("Include the follow-the-anchor path end to end"); this is
the behavioral test that TC-706-003 is a prerequisite for, not a substitute for.
**Preconditions:** At least one real, content-bearing `memory_embeddings` row for each of: `entity_fact`,
`agent_chat`, and one "own dedicated source table" type (e.g. `event` or `lesson`).
**Steps:** For each of the 3 preconditioned rows: (1) run the actual semantic-search path (the same query the
turn-context plugin's recall subsystem uses, per Chunk A's `semantic-recall.ts`) and confirm it returns a pointer/
chunk referencing this embedding; (2) follow that pointer programmatically (not by manual SQL join) all the way to
the original source content (e.g. the actual conversation text for `entity_fact`/`agent_chat`, or the actual
event/lesson text for the dedicated-table case).
**Expected:** For all 3 types, the full chain resolves end to end with no manual intervention and no broken link;
the content retrieved at the end of the chain is the SAME real content the embedding was originally generated
from (byte-for-byte or semantically identical, not just "a row exists") — this is the config→runtime-seam-style
check that proves the anchor is actually USED by production code, not merely present as an unused FK.

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

## 6. #703 — memory-extract handler fails loudly on unresolved `<peer>_memory`, no fallback, stranded-row replay (8 cases: TC-703-001…005, 007…009; TC-703-006 confirmed out of scope, TC-703-010 dropped per step-4 review — see Revision Log)

**Note on current-code baseline — BOTH code paths confirmed in scope (step-4 review):**
- `handler.ts` (read in full, §0) always targets `process.env.PGDATABASE || 'nova_memory'` (lines 275, 381, 413,
  442 — four separate call sites, all with the identical literal fallback) for every `psql` invocation it makes
  directly.
- `extract_memories.py`'s connection builder is now traced: `get_db_connection()`
  (`memory/scripts/extract_memories.py:77-79`) is a one-line wrapper — `return psycopg2.connect()` with **no
  explicit `dbname` argument at all**, meaning it resolves purely from `PG*` environment variables exactly like a
  bare `psql` invocation would; called once, at `extract_memories.py:1242` (`conn = get_db_connection()`), with
  the resulting `conn` threaded into `store_extracted(..., conn=conn)` (line ~1295) and `_store_fact`'s nested
  calls (line ~1044).
- **Correction (step-4 review, 2026-10-13 19:30): `~/.openclaw/postgres.json` is NOVA's own file, not a shared
  leak source.** Rev-1's theory — that a shared `"database": "nova_memory"` default in this file could silently
  misconfigure OTHER peers — was wrong. Peer agents (graybeard, newhart, victoria) run under their OWN unix users,
  each with their OWN `postgres.json` pointing at their OWN `<peer>_memory` database. **The leak path is purely
  `handler.ts`'s literal `process.env.PGDATABASE || 'nova_memory'` fallback (4 call sites) and/or an equivalent
  gap in `extract_memories.py`'s env resolution — nothing else.** TC-703-010 (the "shared-default" adversarial
  case) is DROPPED — it was testing a mechanism that doesn't exist. TC-703-007/008/009 (unset / nonexistent-DB /
  spoofed-prefix) remain the correct adversarial coverage for #703's actual fallback defect.

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

### TC-703-006 — Victoria's write-path tracing and grant hardening: CONFIRMED OUT OF SCOPE for Chunk B (step-4 review)
**Priority:** N/A — explicitly out of this suite's pass/fail bar per step-4 review: "Victoria's write path and grant
hardening: out of Chunk B's pass/fail bar (nova-workspace#252)." Retained here only as a scope-boundary marker so a
future reader doesn't assume its absence is an oversight. No test case is written for it in this file; it belongs
to nova-workspace#252, a separate issue/suite.

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

> Rev 2 resolves: the TC-703-010/postgres.json question (dropped, was based on a wrong model) and the §1b
> wrong-chat-vs-not-split question (corrected — it IS cross-database contamination for the 3 real peers). Rev 0/1's
> other resolved items remain resolved (see Revision Log).

Remaining open items after Rev 2:

1. **TC-708-012's exact migration mechanics** (whether `channel_transcripts.id` can be preserved across a
   cross-database copy, or whether destination peer DBs need a remapped id with a cross-reference table) should be
   confirmed against each peer's actual `channel_transcripts` schema before implementation — assumed compatible
   here but not independently verified peer-DB-schema-by-peer-DB-schema in this design pass.
2. **TC-708-014's "don't migrate test/staging junk" disposition for `nova-staging` specifically** — confirming
   whether nova-staging's 24 rows should be backed up and removed with no further action, or whether staging has
   its own separate "staging_memory"-equivalent database they should go to instead (dispatch said "don't migrate,"
   but staging is a deployment of nova herself, not a third party, which is a slightly different case than main/
   newhart-only-sub's clearly-synthetic test identities).
3. **TC-706-003's exact owning-table names**, **TC-703-010's removal has no further open item** (resolved).
4. **TC-710-008's disposition question** (remove `publish-active-sessions.py`/cron vs. keep for the unrelated
   ratchet experiment) remains open, carried over from Rev 1.
