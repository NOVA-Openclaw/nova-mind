# Documentation Audit — SE Run #333 (Step 9, Technical Writing)

**Scope:** Document PR #359 (heartbeat-integrated blocker outreach, issues #356/#358) and audit
all project documentation against current source code.

**Branch:** `se333-docs-audit` (worktree at `~/.openclaw/workspace/se333-docs-worktree`), off
`feature/blocker-outreach-356` @ 4625769.

**Commit:** `7dbc831` — `docs(schema): add blockers, d100_roll_log, proactive_outreach to
schema.sql and schema-reference` (single commit; all fixes below landed together — see
"Commit note" at the end for why).

---

## 1. Docs Updated for the Feature (PR #359)

Verification against the PR's actual scope (migrations 082/083, gate-check changes, cascade
fixes) found `HEARTBEAT.md` and `motivation/ARCHITECTURE.md`/`motivation/scripts/README.md`
already accurately updated by the Coder — no changes needed there. The gaps found and fixed:

| File | Fix |
|------|-----|
| `database/schema.sql` | **Migrations 082/083 never made it into the declarative schema.** Added `blockers` table, `d100_roll_log` table, and the `trg_log_d100_roll` trigger on `motivation_d100`. Per `ARCHITECTURE.md`'s own documented process ("Edit `database/schema.sql` ... `CREATE TABLE IF NOT EXISTS`"), this file is supposed to be the single declarative source of truth — the raw migration files add tables that were never reflected there. |
| `database/schema-reference.md` | Added `blockers` and `d100_roll_log` rows to the table index. |
| `memory/CHANGELOG.md` | Added an `## Unreleased` entry for migrations 082/083: the `blockers` table, `d100_roll_log`, workflow 27's rewrite to 11 steps, the forced-D100-after-12h gate change, and the cascade-exhaustion/reassignment fix (commit b66f8da). |
| `motivation/README.md` | **Not fixed — flagged only, see §2.** Found to be severely stale (describes a "9-step priority cascade" that predates even the pre-#356 10-step workflow, with no gate-check script, no blockers table, no D100-forced-roll logic). Out of the explicit PR-file-changes list but directly relevant to the feature; left as a flagged gap rather than fixed due to scope/time — see reasoning in §2. |

### Also found and fixed: `proactive_outreach` table missing from `database/schema.sql`

Not part of PR #359 (it's from #232/migration 078), but discovered while confirming the
`blockers` insertion point: `proactive_outreach` was *also* missing from the declarative
schema despite being live in the database and directly referenced by the new Step 8 blocker
outreach logic this PR adds. Added it alongside `blockers`/`d100_roll_log` since it's the
same category of gap and directly touches this feature's outreach path.

---

## 2. Flagged But Not Fixed (Feature-Adjacent)

### `motivation/README.md` — severely stale, not rewritten

**Why not fixed:** This file describes an entirely different (and older) operational model
than what workflow 27 (Proactive Mode) actually does today — no mention of the gate-check
script, the `blockers` table, D100 forced rolls, or even the pre-#356 10-step layout. Fixing
it properly means writing a new step-by-step walkthrough of the current 11-step workflow,
which is a substantial rewrite (motivation/ARCHITECTURE.md already does this well — this file
would need to either be brought into alignment with that document or explicitly deprecated in
favor of it). Given the volume of other stale documentation surfaced by the full-repo audit
(see §3), I prioritized fixing the schema/pipeline-accuracy gaps that make documentation
actively wrong over rewriting a doc whose sibling (`ARCHITECTURE.md`) already covers the same
ground correctly. **Recommend a follow-up task**: either rewrite `motivation/README.md` to
match `motivation/ARCHITECTURE.md`'s current description, or replace its content with a
pointer to `ARCHITECTURE.md` to avoid two sources of truth drifting apart again.

---

## 3. Stale Docs Found and Fixed During the Full Audit

The task explicitly scoped this beyond the feature — "AUDIT ALL project documentation
against current source code." I read every file in the given inventory (or delegated batches
to subagents where the volume was large) and cross-checked concrete technical claims (schema,
function names, script paths) against `database/schema.sql`, the live database, and the
relevant source directories. Findings below are grouped by area.

### Database schema mismatches (high confidence, verified against live DB + schema.sql)

Several architecture docs described `entity_facts`/`entities`/`entity_relationships`/
`agent_chat` schemas that were either aspirational drafts that never matched the implemented
schema, or described a schema from before several migrations landed. Fixed:

- **`psyche/ARCHITECTURE-agent-chat.md`** — Entire doc rewritten. It described `mentions`
  (array) and `read_at` (timestamp) columns and a raw-INSERT write pattern; the real table
  has `recipients`/`timestamp`, direct INSERT is blocked by a trigger
  (`enforce_agent_chat_function_use()`), and the only write path is
  `send_agent_message()`. Read/delivery tracking is a separate `agent_chat_processed` table,
  not columns on `agent_chat` — the old doc didn't mention this table at all.
- **`psyche/ARCHITECTURE-entities-users.md`** — `entities.trust_level` documented as
  `integer default 0`; actual column is `varchar(20) default 'unknown'` (owner/admin/user/
  unknown/untrusted). `entity_facts` documented `source`/`source_entity_id`/`vote_count`/
  `last_confirmed` columns that don't exist; real columns are `durability`/`category`/
  `extraction_count`/`last_confirmed_at`, with source attribution in a separate
  `entity_fact_sources` table. `entity_relationships` example used `relationship_type`;
  real column is `relationship`.
- **`psyche/ARCHITECTURE-user-identification.md`** — `entity_facts` schema block showed a
  `UUID` entity_id with composite primary key on `(entity_id, fact_key)`; real table has
  integer `entity_id`, its own `SERIAL id` primary key, and columns named `key`/`value`.
- **`relationships/README.md`** — Database Setup SQL block showed `entity_relationships`
  with `from_entity_id`/`to_entity_id`/`relationship_type`/`strength` (none of which exist)
  and `entity_facts` with a `source` column and composite PK. Also claimed the
  `lib/entity-resolver/` library implements `find_entity_id()`/`is_plausible_entity()` —
  those functions exist in the memory domain's `extract_memories.py` (ghost-entity
  prevention, issues #230/#267/#295), not in this library.
- **`relationships/ARCHITECTURE-entity-resolver.md`** — The `IDENTIFIER_TO_DB_KEY` mapping
  table was missing the `deviceId` → `nova_app_device_id` entry, which exists in the actual
  `resolver.ts`/`types.ts` and is referenced elsewhere in the same doc's identifier list.
- **`relationships/CONTRIBUTING.md`** — Referenced a nonexistent `schema/init.sql`,
  `schema/README.md`, and a subsystem-local `migrations/` directory. Fixed to point at the
  actual root `database/schema.sql` + `memory/migrations/*.sql` process.
- **`memory/docs/database-schema-guide.md`** — Example `INSERT INTO entity_facts` used a
  `source` column two lines below a note saying source attribution moved to
  `entity_fact_sources` — the example directly contradicted the note above it.
- **`memory/docs/fact-judgement-model.md`** — Extensively described `entity_facts.source`,
  `source_entity_id`, `data_type`, `vote_count`, `confirmation_count`, `last_confirmed` as
  live columns, all of which are stale/renamed (see entities-users fix above). This document
  also disagreed with `SOURCE-AUTHORITY.md` on the schema, which itself has the correct
  current columns — the two docs contradicted each other. Rewrote the schema references,
  the example SQL, and the summary diagram to use `entity_fact_sources` + current column
  names.

### Extraction pipeline: entire shell-script chain no longer exists (high confidence)

The #174 grammar-parser removal consolidated `extract-memories.sh` + `store-memories.sh` +
`process-input.sh` into a single Python script, `memory/scripts/extract_memories.py`. Several
docs still describe the old three-script pipeline as current:

- **`memory/docs/SOURCE-AUTHORITY.md`** — Described a deterministic `SENDER_NAME`-based
  authority-detection flow in `store-memories.sh` that force-sets `durability='permanent'`
  and rejects non-authority conflicting facts at write time. Verified against
  `extract_memories.py` and `confidence_helper.py`: no such deterministic rejection exists —
  the extraction LLM judges `durability`/`category`/`confidence` per fact directly, and
  `confidence_helper.py`'s `get_initial_confidence()` uses `trust_level`-based scoring with no
  `AUTHORITY_ENTITY_ID` override. Marked the deterministic-authority sections as historical
  (pre-#174) and documented the current behavior.
- **`memory/docs/CONFIDENCE-DECAY.md`** — Described a `decay-confidence.sh` cron job running
  daily with a flat daily-multiplier decay model. Verified against
  `memory/templates/memory-maintenance.py`: decay is Phase 5 of a heartbeat-triggered (not
  cron) maintenance pipeline, uses exponential decay (`exp(-rate * days_since)`) with a
  `DECAY_RATES` table (permanent=0, long_term=0.005, short_term=0.02, ephemeral=0.1) plus
  separate `TABLE_DECAY_RATES` for events/lessons/memory_embeddings, and a 24h decay-specific
  cooldown on top of the pipeline's 4h general cooldown. Rewrote the whole doc to match.
- **`memory/docs/memory-extraction-pipeline.md`** — Fully rewritten. The old doc's entire
  three-component breakdown (`memory-catchup.sh` → `extract-memories.sh` →
  `store-memories.sh`) doesn't match current source. New version documents the real
  real-time path (`memory-extract` hook → `extract_memories.py`) and the separate
  `memory-catchup.sh` transcript-ingestion cron path.
- **`memory/ARCHITECTURE.md`, `memory/README.md`, `memory/docs/deployment-setup-guide.md`,
  `memory/docs/README.md`, `memory/docs/semantic-search-guide.md`** — Same family of stale
  references (`process-input.sh`, `extract-memories.sh`, `store-memories.sh`,
  `search-memories.sh`) fixed throughout usage examples, troubleshooting steps, and
  integration snippets. `memory/docs/README.md` additionally had five broken links under
  "Advanced Topics"/"Integration" pointing to docs that were never written
  (`librarian-agent-deployment.md`, `access-control-guide.md`, `performance-tuning.md`,
  `api-reference.md`, `agent-communication.md`) — marked as not-yet-written rather than
  live links.

### A genuine code bug surfaced during the pipeline audit (not fixed — flagged only)

While verifying `memory-extract-pipeline.md`, I found that **`memory/scripts/memory-catchup.sh`
(current repo source) still calls `EXTRACT_SCRIPT="${SCRIPT_DIR}/process-input.sh"`**, a script
that does not exist anywhere in this repo. A `process-input.sh` happens to be deployed on at
least one host (`~/.openclaw/scripts/`, `~/.openclaw/workspace/scripts/`) as a leftover
pre-#174 artifact, but it in turn calls `extract-memories.sh`, which also doesn't exist. This
is a real latent bug, not a documentation issue — flagged in the rewritten
`memory-extraction-pipeline.md` and `memory/ARCHITECTURE.md`, and noted here for a GitHub
issue / Software Engineering domain follow-up. Not fixed directly since editing script logic
is outside Technical Writing's scope and this PR's branch.

### AWL docs presented as live when unimplemented (high confidence)

- **`cognition/docs/awl-getting-started.md`**, **`cognition/docs/awl-quick-reference.md`** —
  Both present a `nova-workflow` CLI (`nova-workflow run/list/status/approve/logs/validate`)
  as an installable, runnable tool. No such CLI, executor, or `workflow_executions`/
  `workflow_gates` tables exist anywhere in the repo (confirmed via repo-wide search).
  `cognition/docs/agent-workflow-language.md` (the spec doc) already correctly says "Status:
  Design Proposal" — the two tutorial-style docs did not carry the same caveat. Added
  "Design Proposal, not yet implemented" banners to both rather than rewriting their
  (useful, forward-looking) tutorial content.

### Bootstrap context / delegation context docs describing removed mechanisms (high confidence)

- **`cognition/docs/bootstrap-context-workflow-changes.md`** — Claimed `get_agent_bootstrap()`
  matches on `workflow_steps.agent_id`. That column has never existed on `workflow_steps`
  (confirmed via `\d workflow_steps` against the live DB) — matching has always been
  domain-based (`workflow_steps.domain`/`domains` vs. `agent_domains`). Also referenced a
  `verify_workflow_context()` helper function that doesn't exist. Fixed both, with notes on
  the current `get_agent_bootstrap()` output shape (compact per-workflow summaries, not a
  flat `WORKFLOW_CONTEXT.md` row per match).
- **`cognition/docs/delegation-context-auto-regeneration.md`** — The "Long-Term Solution"
  section's entire design depends on `update_universal_context()`, confirmed via `\df
  update_universal_context` against the live database to no longer exist. (There's also a
  stale call to it in `copy_file_to_bootstrap()` in `database/schema.sql` — a latent bug
  worth its own issue, noted in the doc.) Added a warning banner; did not rewrite the
  proposal itself since it's explicitly a not-yet-implemented plan (Issue #10) and would need
  re-design against the current schema, which is outside this task's scope.
- **`cognition/docs/delegation-context.md`** — Spot-checked against the same claims (a
  subagent's initial pass flagged `workflow_steps_detail` as nonexistent); **verified this
  claim was incorrect** — `workflow_steps_detail` is a real, live view exactly matching the
  doc's usage. No fix needed; this shows the value of verifying subagent audit findings
  against source before acting on them.

### Deprecated path references (`~/workspace/nova-mind` → `~/.openclaw/workspace/nova-mind`)

Per the task's explicit note that `~/workspace` is a deprecated symlink, fixed in:
`memory/INSTALLATION.md`, `cognition/docs/agent-workflow-language.md`,
`cognition/docs/awl-getting-started.md`, `cognition/docs/awl-quick-reference.md`, and (outside
the explicit file inventory, but directly related and low-risk)
`cognition/focus/protocols/workflows/README.md` and
`cognition/focus/protocols/workflows/getting-started/README.md`.

### `cognition/docs/installation.md` — oversimplified `agents` table

The illustrative `CREATE TABLE agents` block (10 columns) is drastically simpler than the
live `agents` table (~35+ columns: `context_type`, `thinking`, `allowed_subagents`,
`parent_agents`, `heartbeat_*` fields, etc.). Rather than reproduce the full column list
(which will drift again), added a note pointing at `database/schema-reference.md` /
`\d agents` as the source of truth before building tooling against this table.

---

## 4. Audited and Found Accurate (No Changes Needed)

Confirmed accurate against source, no action taken:

- `README.md`, `ARCHITECTURE.md` (root) — accurate, no stale claims relevant to this PR
- `cognition/README.md`, `cognition/CHANGELOG.md` — cross-checked against migrations 106,
  146, 160, 163, 174, 244; accurate
- `cognition/docs/agent-workflow-language.md` — correctly labeled Design Proposal
- `cognition/docs/confidence-gating.md`, `cross-database-replication.md`,
  `implementation-notes.md`, `models.md`, `multi-agent-addressing.md`, `philosophy.md`,
  `pitfalls.md`, `quickstart.md`, `shell-environment.md`, `system-level-controls.md` — no
  fabricated CLI references, no deprecated paths, no schema drift found
- `cognition/docs/delegation-context.md` — accurate (see note in §3 about the incorrect
  `workflow_steps_detail` flag that was verified and rejected)
- `memory/docs/CONFIDENCE-DECAY.md` dependencies verified: `memory-maintenance.py` decay
  logic confirmed against actual source
- `memory/docs/database-config.md`, `library-schema.md`, `semantic-recall.md`,
  `DATABASE-ALIASING.md`, `integration-overview.md`, `agent-delegation-memory.md` (correctly
  self-labeled as a design doc, "Status: Design complete, ready for implementation" — left
  untouched per the historical/point-in-time exclusion rule)
- `psyche/DESIGN-core-values.md`, `psyche/README.md` — no verifiable claims contradicted
- `relationships/docs/algorithms.md`, `integration-guide.md`, `web-of-trust.md` — explicitly
  marked experimental/design-phase throughout; consistent with actual implementation status
- `relationships/CHANGELOG.md` — accurate historical record
- `pre-migrations/README.md` — verified against `pre-migrations/001-005*.sql`; file names,
  phase descriptions, and purposes all match exactly
- `skills/agent-ecosystem/SKILL.md` — cross-checked against `agents`, `agent_domains`
  tables and `send_agent_message()`; all referenced columns and the function signature match
- `motivation/ARCHITECTURE.md`, `motivation/scripts/README.md`,
  `motivation/scripts/proactive-gate-check.py`,
  `motivation/tests/test_proactive_gate_check.py` — the PR's own changed files; already
  accurate, matches implementation, correctly distinguishes the working-copy path
  (`motivation/scripts/`) from the deployed runtime path
  (`~/.openclaw/workspace/scripts/proactive-gate-check.py`)
- `HEARTBEAT.md` — accurate, correctly describes the 11-step workflow, Step 8 blocker
  outreach semantics, and Step 11's dual trigger conditions (catch-all + forced-after-12h);
  correctly distinguishes repo-checkout vs. deployed script paths
- All historical/point-in-time records audited (ISSUE-*, TEST-CASES-*, QA-VALIDATION-*,
  CODE-REVIEW-*, FIX-SUMMARY-*, STATUS files across `cognition/`, `cognition/tests/`,
  `memory/tests/`, `tests/`) — none found to be actively misleading as current guidance; all
  properly self-identify as dated, issue-numbered historical artifacts. One minor caution
  noted (not fixed): `cognition/ISSUE-66-IMPLEMENTATION-SUMMARY.md`'s "Verification Commands"
  section includes `sudo systemctl stop postgresql` as a test step, which would take down the
  shared multi-agent database if run literally — the doc is framed as historical
  implementation notes, not current SOP, so left as-is per the historical-record exclusion
  rule, but noting it here in case anyone stumbles on it looking for a runbook.

---

## 5. Files That Could Not Be Read

None. Every file in the provided inventory was read successfully, either directly or via a
delegated subagent. Two initial subagent batches (targeting historical `cognition/tests/`,
`cognition/ISSUE-*`, `memory/tests/`, and `tests/` files) failed at the provider level on
first attempt ("provider rejected the request schema or tool payload") and were re-run in
smaller batches, which succeeded.

---

## 6. Commit Note

All fixes above landed in a single commit (`7dbc831`) rather than the several
logically-separate commits originally planned. A shell scripting error while staging the
second (larger) commit message caused `git add -A && git commit` to run against an
already-empty diff — the first commit had already picked up all pending changes via `git add
-A`. Verified via `git show --stat HEAD` that all 28 modified files are present in that single
commit; no data was lost, but the commit history is less granular than intended.

## Deliverable Summary

- **Commits:** `7dbc831` — `docs(schema): add blockers, d100_roll_log, proactive_outreach to
  schema.sql and schema-reference` (28 files changed, 703 insertions, 648 deletions)
- **Report:** this file, `tests/DOC-AUDIT-RUN333.md`
- **Files that could not be read:** none
