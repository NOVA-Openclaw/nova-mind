-- Migration 083: Workflow 27 (Proactive Mode) — blocker curation + dedicated
-- outreach step, forced D100 step renumbering.
-- Issues #356 (heartbeat-integrated blocker outreach) and #358 (forced D100 >12h)
--
-- Summary of changes:
--   1. Step 6 (Work on Pending Tasks): replace inline blocker handling with
--      curation semantics — upsert into `blockers` (migration 082), resolve
--      the responsible entity, NO immediate outreach from this step.
--   2. Step 7 (Work on Open GitHub Issues): same curation semantics; REMOVE
--      the existing inline outreach cascade + 3-day cooldown text entirely.
--   3. New step 8 (Blocker Outreach): the dedicated, heartbeat-integrated
--      outreach step driven by proactive-gate-check.py's
--      check_step8_blocker_outreach() (see migration 082 / CHUNK 2).
--   4. Renumber old steps 8/9/10 (Unsolved Problems, Filesystem Hygiene,
--      D100) to 9/10/11. Uses a temporary offset to avoid violating the
--      (workflow_id, step_order) UNIQUE constraint mid-migration.
--
-- No step-number cross-references appear inside any step's description text
-- (verified against the live rows before writing this migration), so no
-- description edits are needed for the pure renumbering of steps 8/9/10.

-- ---------------------------------------------------------------------------
-- 1. Renumber steps 8, 9, 10 -> 9, 10, 11 using a temporary offset to avoid
--    violating the workflow_steps_workflow_id_step_order_key UNIQUE
--    constraint (workflow_id, step_order) while the new step 8 is inserted
--    below.
-- ---------------------------------------------------------------------------
UPDATE workflow_steps
SET step_order = step_order + 1000
WHERE workflow_id = 27 AND step_order IN (8, 9, 10);

UPDATE workflow_steps
SET step_order = step_order - 1000 + 1
WHERE workflow_id = 27 AND step_order IN (1008, 1009, 1010);

-- ---------------------------------------------------------------------------
-- 2. Step 6 (Work on Pending Tasks) — curation semantics, no immediate
--    outreach. Blocked tasks are upserted into `blockers`; the dedicated
--    step 8 handles all outreach.
-- ---------------------------------------------------------------------------
UPDATE workflow_steps
SET description = E'## Work on Pending Tasks\n\n```sql\nSELECT id, title, priority, description FROM tasks\nWHERE status = ''pending'' AND assigned_to = 1\nAND (blocked IS NULL OR blocked = false)\nORDER BY priority DESC, created_at ASC LIMIT 1;\n```\n\n**Actionable means actionable NOW.** A task is actionable only if it can be progressed in this session without waiting for human input, authorization, or an external dependency. Tasks that are open but blocked, awaiting discussion, or need information you don''t have are NOT actionable — skip them. Do not treat "open" as "actionable."\n\nIf an actionable task exists:\n- Set status to `in_progress`, update `last_worked_at`\n- Work on it (spawn subagents as needed)\n- If completed → mark `completed`, pick next\n- If blocked → set `blocked = true`, `blocked_reason`, and **curate it into the blocker registry**:\n  - Resolve the responsible entity: check `agent_domains` first (task domain → agent), then `user_domains` (lower priority number wins; tiebreak random among equal-priority matches); if no match, fall back to entity_id = 2 (I)ruid)\n  - `INSERT INTO blockers (source_type, source_ref, description, needs, entity_id, priority) VALUES (''task'', <task id as text>, <task title/description>, <blocked_reason>, <resolved entity_id>, <task priority>) ON CONFLICT (source_type, source_ref) DO UPDATE SET last_seen = NOW(), description = EXCLUDED.description, needs = EXCLUDED.needs;`\n  - Do **not** send outreach from this step — the dedicated Blocker Outreach step (step 8) owns all outreach cadence and channel escalation\n- If interrupted by new message → pause, update `work_notes` with progress\n\n**If no pending tasks:** advance to next step.\n\n---\n\n**Step reporting requirement:** After completing this step (whether work was performed or the step was skipped via gate check), post a concise summary of the step''s outcome to Discord <#1504054635231445112> (#proactive-mode). Include: step number/name, action taken or reason skipped, and any notable findings. Keep it brief — one short paragraph or a few bullets.'
WHERE workflow_id = 27 AND step_order = 6;

-- ---------------------------------------------------------------------------
-- 3. Step 7 (Work on Open GitHub Issues) — same curation semantics; the
--    inline outreach cascade + 3-day cooldown text is removed entirely.
-- ---------------------------------------------------------------------------
UPDATE workflow_steps
SET description = E'## Work on Open GitHub Issues\n\nCheck open issues across all repos in the NOVA-Openclaw GitHub account:\n\n```bash\n# List all repos, then check each for open issues\ngh repo list NOVA-Openclaw --no-archived --limit 50 --json name -q ''.[].name'' | while read repo; do\n  count=$(gh issue list --repo NOVA-Openclaw/$repo --state open --json number -q ''length'')\n  [ "$count" -gt 0 ] && echo "NOVA-Openclaw/$repo: $count open issues"\ndone\n```\n\n**Actionable means actionable NOW.** An issue is actionable only if it can be progressed in this session without waiting for human input, authorization, or an external dependency. Issues that are open but blocked on discussion, need human decisions, or require authorization you don''t have are NOT actionable — skip them. Do not treat "open" as "actionable."\n\nFor each open issue:\n- Can it be worked without human input? → Start an SE workflow or delegate to the appropriate agent\n- Is it blocked and needs human input? → **Curate it into the blocker registry** (do not contact anyone from this step):\n  - Resolve the responsible entity: check `agent_domains` first (issue label/repo domain → agent), then `user_domains` (lower priority number wins; tiebreak random among equal-priority matches); if no match, fall back to entity_id = 2 (I)ruid)\n  - `INSERT INTO blockers (source_type, source_ref, description, needs, entity_id, priority) VALUES (''github_issue'', <repo>#<issue number>, <issue title>, <what''s needed to unblock>, <resolved entity_id>, <priority>) ON CONFLICT (source_type, source_ref) DO UPDATE SET last_seen = NOW(), description = EXCLUDED.description, needs = EXCLUDED.needs;`\n  - All outreach cadence and channel escalation is owned exclusively by the dedicated Blocker Outreach step (step 8)\n- Is it already being worked (has an open PR or active workflow run)? → Skip\n- Is it a bug I can reproduce and fix? → Start SE workflow\n\nPrioritize by labels (bug > enhancement), staleness (older first), and whether blockers can be cleared.\n\n**If no workable issues:** advance to next step.\n\n---\n\n**Step reporting requirement:** After completing this step (whether work was performed or the step was skipped via gate check), post a concise summary of the step''s outcome to Discord <#1504054635231445112> (#proactive-mode). Include: step number/name, action taken or reason skipped, and any notable findings. Keep it brief — one short paragraph or a few bullets.'
WHERE workflow_id = 27 AND step_order = 7;

-- ---------------------------------------------------------------------------
-- 4. New step 8 — Blocker Outreach.
--
--    Driven by proactive-gate-check.py's check_step8_blocker_outreach()
--    (migration 082 / CHUNK 2), which curates the eligible top-3-per-entity
--    blocker set, cascade level, and target channel as a data payload for
--    this step to act on.
-- ---------------------------------------------------------------------------
INSERT INTO workflow_steps (
    workflow_id, step_order, description, domain,
    required, requires_authorization, requires_discussion
)
VALUES (
    27, 8,
    E'## Blocker Outreach\n\nThe gate check (`proactive-gate-check.py`) curates eligible blockers into this step''s data payload: up to 3 blockers per responsible entity, ordered by priority ASC, first_seen ASC, id ASC, filtered by cooldown eligibility (see below). Work from that payload — do not re-query `blockers` independently unless the payload is empty and you need to double-check.\n\n**Before selecting outreach targets — reconcile satisfied blockers:**\n- For any blocker in the registry whose underlying condition has cleared (task completed, issue closed, question answered, etc.), mark it `status = ''satisfied''`, `satisfied_at = NOW()`.\n- If a previously-satisfied blocker''s condition recurs (reopened issue, task re-blocked), **reopen it**: set `status = ''open''` and clear `satisfied_at` back to `NULL` — do not create a duplicate row (the `(source_type, source_ref)` unique constraint on `blockers` prevents this anyway; rely on the `ON CONFLICT ... DO UPDATE` upsert from steps 6/7).\n\n**Eligibility (enforced by the gate check, informational here):**\n- Entity master cooldown: an entity is eligible for a new message only if more than 24h have elapsed since ANY prior `proactive_outreach` row for that entity (strict >; exactly 24h still blocks).\n- Per-blocker cooldown: a specific blocker is eligible only if more than 72h have elapsed since the last `proactive_outreach` row for `(entity_id, blocker_type=''blocker'', blocker_id)` (strict >).\n- Top 3 blockers per eligible entity are selected, ordered by `priority ASC, first_seen ASC, id ASC`.\n\n**Sending outreach — one message per entity:**\n- Send **exactly ONE message per entity** this step, even when multiple blockers were selected for them.\n- The message channel is the **most-escalated requested level** among that entity''s selected blockers. Cascade level for a blocker = the count of prior `proactive_outreach` rows for `(entity_id, ''blocker'', blocker_id)` + 1. Levels map onto that entity''s available contact channels (per `entity_facts`: `discord_id` → discord mention, then discord DM, then `signal`, then `slack`, then `email`, skipping any missing channel) — or `agent_chat` unconditionally for entities that are agents (row exists in `agents` with matching `entity_id`).\n- The message should summarize all selected blockers for that entity, not just the most-escalated one.\n\n**Logging — one row per blocker, not per message:**\n- Log **one `proactive_outreach` row per blocker** included in the message (even though only one message was sent), recording the **actual channel used** to deliver that message — not the requested/theoretical channel for that specific blocker''s own cascade level.\n- Cascade position for the NEXT attempt is derived purely from the count of prior `proactive_outreach` rows for that blocker, regardless of which channel actually delivered any given attempt. Do not track cascade position by channel.\n\n**Channel exhaustion — reassignment, not skip:**\n- If an entity has exhausted all of their available contact channels (cascade level exceeds the number of channels the mapping helper found for them) and they are not I)ruid, **reassign the blocker to the next domain entity** (re-resolve via `agent_domains`/`user_domains` excluding the exhausted entity) rather than continuing to message someone with no reachable channel left.\n- If reassignment eventually exhausts every domain entity, escalate to **I)ruid (entity_id=2) as the final fallback**.\n- If I)ruid himself is exhausted (all of his channels already used at his highest cascade level), **hold the blocker at his last available channel/level** and continue trying him on the normal 72h cadence — do not loop reassignment past him and do not drop the blocker.\n\n**If no entities are eligible this cycle:** advance to next step; no outreach is sent.\n\n---\n\n**Step reporting requirement:** After completing this step (whether work was performed or the step was skipped via gate check), post a concise summary of the step''s outcome to Discord <#1504054635231445112> (#proactive-mode). Include: step number/name, action taken or reason skipped, and any notable findings. Keep it brief — one short paragraph or a few bullets.',
    'NOVA Operations',
    true, false, false
);
