# Test Cases: Batch SE Run 8

**Issues:** #234, #232, #237  
**Branch:** `feature/batch-se-run-8` (or per-issue branches)  
**Deliverables:**  
- #234: Merge nova-motivation into nova-mind; `agents.entity_id` column; `agent_domains` constraint refactor  
- #232: `user_domains` table; `proactive_outreach` table; outreach cascade; proactive mode integration  
- #237: Drop `channel_activity` table; replace idle detection with native OpenClaw data  
**Author:** Gem (QA Lead)  
**Date:** 2026-05-17

---

## Scope

### What Is Being Tested

1. **#234** — nova-motivation repo content merged into `nova-mind/motivation/`; `agents.entity_id` FK column populated from entity name matches; `agent_domains` constraint changed from `UNIQUE (domain_topic)` to `UNIQUE (agent_id, domain_topic)` with added `priority INTEGER DEFAULT 1` column; README/installer/CHANGELOG updated; nova-motivation archived.
2. **#232** — `user_domains` table creation and seeding (17 rows across 5 users); `proactive_outreach` table creation; outreach cascade logic (domain → user lookup by priority, channel escalation, cooldown, user escalation, I)ruid fallback); integration into Proactive Mode workflow (id=27) steps 4, 5, 6; Tabby email entity_fact.
3. **#237** — `channel_activity` table dropped; idle detection in HEARTBEAT.md and proactive workflow replaced with native `sessions_list` / `message(action="read")` / inbound metadata; all references updated.

### What Is NOT Tested Here

- Bootstrap context delivery format changes beyond FK integrity (covered in prior migration test suites)
- Production memory extraction pipeline (covered in TEST-CASES-BATCH4-EXTRACTION.md)
- nova-motivation operational behavior after archive (repo is read-only after archival; no behavioral testing required)
- UI/channel-layer formatting of outreach messages (Hermes/agent responsibility)
- Confidence-check plugin and self-awareness triggers (covered in TEST-CASES-BATCH-SE-RUN2.md)

---

## Entry Criteria

- Staging environment running nova-openclaw fork with NOVA systems installed
- `nova_memory` database accessible on staging with required tables pre-migration
- `agents` table contains all production agents including nova (id=1), gem (id=2), coder (id=3), gidget (id=4), newhart (id=5), scout (id=6), athena (id=7), iris (id=8), ticker (id=11), quill (id=12), hermes (id=13), scribe (id=14), argus (id=16), conductor (id=18), marcie (id=20), graybeard (id=24), flint (id=25), cadence (id=27)
- `entities` table contains person-type records for Dustin Trammell (id=2), Tabatha Wilson (id=3), Carla (id=4), Regan (id=5), Rayven (id=6) — and at least 2 more for the 5-user seed requirement
- Current `agent_domains` has at least one domain_topic shared between issues (none exist yet — current unique constraint guarantees this)
- `channel_activity` table exists (pre-migration state)
- nova-motivation repo at `~/workspace/nova-motivation/` with all expected files
- nova-mind repo at `~/workspace/nova-mind/`
- Proactive Mode workflow (id=27) exists with steps 4, 5, 6 referencing tasks/problems/D100

---

## Exit Criteria

- All TC-PASS test cases pass on staging
- All TC-FAIL and TC-REJECT cases correctly reject invalid inputs or state
- Zero unhandled exceptions from any tested component
- No S1/S2 defects open; S3 defects documented with workaround
- All DB verifications runnable as SQL queries against staging `nova_memory`
- `channel_activity` table is absent post-migration

---

## Severity Legend

- **S1** — Blocker: data corruption, crashes, security issue
- **S2** — Critical: feature broken, no workaround
- **S3** — Major: feature degraded, workaround exists
- **S4** — Minor: cosmetic, documentation gap

---

---

# Issue #234 — Merge nova-motivation into nova-mind

---

## Section A: File Consolidation

### TC-234-A-001: motivation/ directory exists with nova-motivation content

**Severity:** S2  
**Preconditions:**
- nova-mind repo has been updated (migration applied)
- nova-motivation repo was at `~/workspace/nova-motivation/`

**Steps:**
```bash
ls ~/workspace/nova-mind/motivation/
```

**Expected Result:**
- Directory exists
- Contains at minimum: `README.md`, `WORKFLOW.md`, `ARCHITECTURE.md`, `DEPLOYMENT.md`, `agent-install.sh`, `hooks/`, `scripts/`, `docs/`, `tests/`
- All top-level files from nova-motivation root are present (excluding `.git/`)

**DB Verification:** N/A (filesystem check)

---

### TC-234-A-002: README.md in nova-mind updated to reference motivation/

**Severity:** S3  
**Preconditions:** Migration applied

**Steps:**
```bash
grep -i "motivation" ~/workspace/nova-mind/README.md
```

**Expected Result:**
- At least one reference to `motivation/` directory or the Motivation System
- Should describe what the motivation/ subdirectory contains

---

### TC-234-A-003: nova-mind installer references motivation/ content if needed

**Severity:** S3  
**Preconditions:** Migration applied

**Steps:**
```bash
grep -i "motivation" ~/workspace/nova-mind/agent-install.sh
grep -i "motivation" ~/workspace/nova-mind/shell-install.sh
```

**Expected Result:**
- If nova-motivation had install steps (hooks, scripts), those are incorporated or explicitly noted as included
- No broken references to `nova-motivation` paths that no longer apply

---

### TC-234-A-004: CHANGELOG.md updated with merge entry

**Severity:** S4  
**Preconditions:** Migration applied

**Steps:**
```bash
grep -i "motivation\|234\|merge" ~/workspace/nova-mind/CHANGELOG.md | head -20
```

**Expected Result:**
- Entry exists describing the nova-motivation merge (issue #234 or equivalent description)
- Entry is at or near the top (most recent entry)

---

### TC-234-A-005: nova-motivation pre-push hook preserved in motivation/hooks/

**Severity:** S3  
**Preconditions:** Migration applied

**Steps:**
```bash
cat ~/workspace/nova-mind/motivation/hooks/pre-push
```

**Expected Result:**
- File exists and is readable
- Content matches original nova-motivation pre-push hook content

---

### TC-234-A-006: Original nova-motivation repo is archived (GitHub check)

**Severity:** S2  
**Preconditions:** Migration fully complete, including archive step

**Steps:**
```bash
# Use gh CLI to check archive status
gh api repos/OWNER/nova-motivation --jq '.archived'
```

**Expected Result:**
- Returns `true`
- Repo is read-only

**Note:** Replace `OWNER` with the actual GitHub owner/org. This test may require network access to GitHub.

---

## Section B: agents.entity_id Column

### TC-234-B-001: agents table has entity_id column with FK

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'agents' AND column_name = 'entity_id';
```

**Expected Result:**
```
 column_name | data_type | is_nullable
-------------+-----------+-------------
 entity_id   | integer   | YES
```

**Steps (FK check):**
```sql
SELECT tc.constraint_name, kcu.column_name, ccu.table_name AS referenced_table,
       ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name = 'agents' AND tc.constraint_type = 'FOREIGN KEY'
  AND kcu.column_name = 'entity_id';
```

**Expected Result:**
- One row returned with `referenced_table = 'entities'` and `referenced_column = 'id'`

---

### TC-234-B-002: Existing agents populated with entity_id from name match

**Severity:** S2  
**Preconditions:** Migration applied; entities table has records for agent names

**Steps:**
```sql
SELECT a.name, a.entity_id, e.name AS entity_name
FROM agents a
LEFT JOIN entities e ON a.entity_id = e.id
WHERE a.status = 'active'
ORDER BY a.id;
```

**Expected Result:**
- Agents whose name matches an entity record (nova, gem, coder, gidget, newhart, scout, athena, iris, ticker, quill, hermes, scribe, argus, conductor, marcie, graybeard, flint, cadence) have non-NULL `entity_id`
- `entity_name` matches `a.name` for all populated rows
- Agents with no entity match have `entity_id = NULL` (acceptable, not an error)

---

### TC-234-B-003: agents.entity_id FK enforces referential integrity

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
-- Attempt to set entity_id to a non-existent entity
UPDATE agents SET entity_id = 999999 WHERE name = 'nova';
```

**Expected Result:**
- Error: foreign key constraint violation
- `update` fails with `ERROR: insert or update on table "agents" violates foreign key constraint`

**Cleanup:**
```sql
-- Restore correct value if needed
UPDATE agents SET entity_id = (SELECT id FROM entities WHERE name = 'nova' AND type = 'agent') WHERE name = 'nova';
```

---

### TC-234-B-004: agents.entity_id allows NULL (column is nullable)

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
-- Find an agent that may have no entity match, or use a test agent
-- Confirm NULL is accepted
SELECT COUNT(*) FROM agents WHERE entity_id IS NULL;
```

**Expected Result:**
- Query succeeds (no constraint error)
- Count ≥ 0 (some agents may have no entity match — that's fine)

---

### TC-234-B-005: No duplicate entity_id assignments (each entity matched once)

**Severity:** S2  
**Preconditions:** Migration applied; each agent should map to a distinct entity

**Steps:**
```sql
SELECT entity_id, COUNT(*) AS agent_count
FROM agents
WHERE entity_id IS NOT NULL
GROUP BY entity_id
HAVING COUNT(*) > 1;
```

**Expected Result:**
- Zero rows returned (no entity_id shared by multiple agents)

---

## Section C: agent_domains Constraint Refactor

### TC-234-C-001: UNIQUE (domain_topic) constraint is dropped

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT constraint_name
FROM information_schema.table_constraints
WHERE table_name = 'agent_domains'
  AND constraint_type = 'UNIQUE';
```

**Expected Result:**
- No row with constraint covering only `domain_topic`
- Old constraint `agent_domains_domain_topic_key` should be absent

---

### TC-234-C-002: UNIQUE (agent_id, domain_topic) constraint exists

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT kcu.constraint_name, kcu.column_name
FROM information_schema.key_column_usage kcu
JOIN information_schema.table_constraints tc ON kcu.constraint_name = tc.constraint_name
WHERE tc.table_name = 'agent_domains'
  AND tc.constraint_type = 'UNIQUE'
ORDER BY kcu.constraint_name, kcu.ordinal_position;
```

**Expected Result:**
- One unique constraint covering both `agent_id` and `domain_topic` (two rows in result, same constraint_name)

---

### TC-234-C-003: priority column exists with DEFAULT 1

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'agent_domains' AND column_name = 'priority';
```

**Expected Result:**
```
 column_name | data_type | column_default | is_nullable
-------------+-----------+----------------+-------------
 priority    | integer   | 1              | YES
```

---

### TC-234-C-004: All existing agent_domains rows have priority = 1

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT COUNT(*) FROM agent_domains WHERE priority != 1 OR priority IS NULL;
```

**Expected Result:**
- `count = 0` — all existing rows have priority = 1 as specified

---

### TC-234-C-005: Two agents can now share the same domain_topic

**Severity:** S1  
**Preconditions:** Migration applied; new constraint allows this

**Steps:**
```sql
-- Find an existing agent and domain
SELECT agent_id, domain_topic FROM agent_domains LIMIT 1;

-- Insert a second agent on the same domain (use a different agent_id)
-- Replace values with actual agent_id and domain_topic from above
INSERT INTO agent_domains (agent_id, domain_topic, priority)
VALUES (<different_agent_id>, '<existing_domain_topic>', 2);
```

**Expected Result:**
- INSERT succeeds (no unique constraint violation)
- Two rows now exist for the same domain_topic with different agent_ids

**Cleanup:**
```sql
DELETE FROM agent_domains WHERE agent_id = <different_agent_id> AND domain_topic = '<existing_domain_topic>';
```

---

### TC-234-C-006: Duplicate (agent_id, domain_topic) pair is still rejected

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
-- Get an existing (agent_id, domain_topic) pair
SELECT agent_id, domain_topic FROM agent_domains LIMIT 1;

-- Try to insert exact same pair
INSERT INTO agent_domains (agent_id, domain_topic, priority)
VALUES (<same_agent_id>, '<same_domain_topic>', 1);
```

**Expected Result:**
- Error: unique constraint violation on `(agent_id, domain_topic)`
- INSERT fails

---

### TC-234-C-007: New INSERT without priority uses default value 1

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
-- Use a test agent_id and novel domain_topic
INSERT INTO agent_domains (agent_id, domain_topic)
VALUES (1, 'TC-234-TEST-DOMAIN-NOPRIORITY');

SELECT priority FROM agent_domains WHERE domain_topic = 'TC-234-TEST-DOMAIN-NOPRIORITY';
```

**Expected Result:**
- `priority = 1`

**Cleanup:**
```sql
DELETE FROM agent_domains WHERE domain_topic = 'TC-234-TEST-DOMAIN-NOPRIORITY';
```

---

### TC-234-C-008: get_agent_bootstrap function still returns correct domains

**Severity:** S1  
**Preconditions:** Migration applied; `get_agent_bootstrap` function exists

**Steps:**
```sql
-- Call bootstrap for a known agent (e.g., nova, id=1)
SELECT get_agent_bootstrap('nova');
```

**Expected Result:**
- Returns JSON/text blob including nova's domains (Project Leadership, NOVA Operations)
- No SQL errors
- Domain topics match what's in agent_domains for agent_id=1

---

### TC-234-C-010: Priority ordering query returns lower numbers first

**Severity:** S2

The priority semantic is "lower number = contact first." Verify ORDER BY priority returns priority 1 before priority 2.

**Setup:** Insert two agent_domains rows for the same domain_topic with priority 1 and priority 2.

```sql
SELECT agent_id, domain_topic, priority
FROM agent_domains
WHERE domain_topic = '<test_domain>'
ORDER BY priority;
```

**Expected Result:** Priority 1 row appears before priority 2 row. Combined with RANDOM() for equal priorities: `ORDER BY priority, RANDOM()`.

**Cleanup:** Remove test rows.

---

### TC-234-C-009: protect_agent_domains triggers remain intact post-migration

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT trigger_name, event_manipulation, event_object_table
FROM information_schema.triggers
WHERE event_object_table = 'agent_domains'
ORDER BY trigger_name;
```

**Expected Result:**
- `protect_agent_domains_delete` trigger present
- `protect_agent_domains_insert` trigger present
- `protect_agent_domains_update` trigger present

---

---

# Issue #232 — Proactive Mode User Prompting

---

## Section D: user_domains Table

### TC-232-D-001: user_domains table exists with correct schema

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
\d user_domains
```

**Expected Result:**
- Table exists
- Columns: `id` (serial/int PK), `entity_id` (integer, FK → entities.id), `domain_topic` (varchar/text), `priority` (integer, default 1)
- UNIQUE constraint on `(entity_id, domain_topic)`
- FK constraint: `entity_id → entities(id)`

---

### TC-232-D-002: user_domains seeded with 17 rows across 5 users

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT COUNT(*) FROM user_domains;

SELECT entity_id, COUNT(*) AS domain_count
FROM user_domains
GROUP BY entity_id
ORDER BY entity_id;
```

**Expected Result:**
- Total count = 17
- Exactly 5 distinct entity_ids (5 users)

---

### TC-232-D-003: user_domains seed references valid entity_ids

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT ud.entity_id, e.name
FROM user_domains ud
LEFT JOIN entities e ON ud.entity_id = e.id
WHERE e.id IS NULL;
```

**Expected Result:**
- Zero rows (all entity_ids reference valid entities)

---

### TC-232-D-004: user_domains UNIQUE (entity_id, domain_topic) constraint enforced

**Severity:** S1  
**Preconditions:** Migration applied; at least one row exists in user_domains

**Steps:**
```sql
-- Get an existing row
SELECT entity_id, domain_topic FROM user_domains LIMIT 1;

-- Try to insert a duplicate
INSERT INTO user_domains (entity_id, domain_topic, priority)
VALUES (<existing_entity_id>, '<existing_domain_topic>', 1);
```

**Expected Result:**
- Error: unique constraint violation
- INSERT fails

---

### TC-232-D-005: Same domain_topic can be assigned to multiple users

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
-- Check if any domain_topic appears for multiple users in the seed data
SELECT domain_topic, COUNT(DISTINCT entity_id)
FROM user_domains
GROUP BY domain_topic
HAVING COUNT(DISTINCT entity_id) > 1;
```

**Expected Result:**
- This is valid behavior; at least one domain_topic shared by multiple users confirms the design is correct
- If none shared in seed data, manually verify that the constraint does NOT prevent it:

```sql
-- Find a domain_topic used by one user, insert it for another
SELECT entity_id, domain_topic FROM user_domains LIMIT 1;
-- (use a different entity_id)
INSERT INTO user_domains (entity_id, domain_topic, priority)
VALUES (<other_entity_id>, '<same_domain_topic>', 1);
```

**Expected Result:** INSERT succeeds

**Cleanup:** DELETE the test row

---

### TC-232-D-006: user_domains priority column defaults to 1

**Severity:** S3  
**Preconditions:** Migration applied

**Steps:**
```sql
INSERT INTO user_domains (entity_id, domain_topic)
VALUES (2, 'TC-232-TEST-DOMAIN');

SELECT priority FROM user_domains WHERE entity_id = 2 AND domain_topic = 'TC-232-TEST-DOMAIN';
```

**Expected Result:**
- `priority = 1`

**Cleanup:**
```sql
DELETE FROM user_domains WHERE entity_id = 2 AND domain_topic = 'TC-232-TEST-DOMAIN';
```

---

### TC-232-D-007: Verify specific seed data values match agreed assignments

**Severity:** S2

The 17 seed rows were agreed with I)ruid. Validate the exact values:

```sql
SELECT e.name, ud.domain_topic, ud.priority
FROM user_domains ud
JOIN entities e ON ud.entity_id = e.id
ORDER BY e.name, ud.domain_topic;
```

**Expected Result:** Exactly 17 rows with these assignments:
- I)ruid (entity 2): Database (1), Information Security (1), IT Security (1), NOVA Operations (1), Penetration Testing (1), Project Leadership (1), Software Engineering (1), Systems Administration (1)
- Neva (entity 8): Marketing/Branding (1), Visual Art (1)
- Regan (entity 5): Creative Writing (1), Marketing/Branding (1)
- Tabatha Wilson (entity 3): Crafting (1), Visual Art (2)
- Zonk Ruehl (entity 56): DevOps (1), Information Security (1), Music (1)

Key validations:
- Neva and Regan share Marketing/Branding at priority 1 (equal weight)
- I)ruid and Zonk share Information Security at priority 1 (equal weight)
- Tabatha Wilson is priority 2 for Visual Art (after Neva), priority 1 for Crafting

---

## Section E: proactive_outreach Table

### TC-232-E-001: proactive_outreach table exists with correct schema

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
\d proactive_outreach
```

**Expected Result:**
- Table exists
- Columns (at minimum):
  - `id` (serial/int PK)
  - `entity_id` (integer, FK → entities.id) — the person or agent contacted
  - `blocker_type` (varchar/text) — type of blocker referenced (e.g., 'task', 'workflow_step', 'unsolved_problem')
  - `blocker_id` (integer) — the blocker's record id
  - `channel_used` (varchar/text) — which channel was attempted (discord, signal, slack, email)
  - `attempted_at` (timestamp with time zone)
  - `response_received` (text, nullable) — response if any

---

### TC-232-E-002: proactive_outreach records insert and retrieve correctly

**Severity:** S2  
**Preconditions:** Migration applied; entities table has entity id=2 (Dustin Trammell)

**Steps:**
```sql
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES (2, 'task', 99999, 'discord', NOW())
RETURNING id, entity_id, blocker_type, blocker_id, channel_used, attempted_at;
```

**Expected Result:**
- Row inserted successfully, id returned
- All fields match inserted values

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE blocker_type = 'task' AND blocker_id = 99999;
```

---

### TC-232-E-003: proactive_outreach FK on entity_id enforces referential integrity

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES (999999, 'task', 1, 'discord', NOW());
```

**Expected Result:**
- Error: foreign key constraint violation
- INSERT fails

---

### TC-232-E-004: Cooldown query — 3-day per-blocker per-user cooldown correctly filters

**Severity:** S1  
**Preconditions:** Migration applied; test rows inserted

**Setup:**
```sql
-- Insert an outreach attempt 2 days ago for entity 2, task blocker 100
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES (2, 'task', 100, 'discord', NOW() - INTERVAL '2 days');

-- Insert an outreach attempt 4 days ago for entity 2, task blocker 101
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES (2, 'task', 101, 'discord', NOW() - INTERVAL '4 days');
```

**Cooldown check query:**
```sql
-- Returns entity+blocker combos that are still in cooldown (last attempt < 3 days ago)
SELECT entity_id, blocker_type, blocker_id, MAX(attempted_at) AS last_attempt
FROM proactive_outreach
WHERE attempted_at > NOW() - INTERVAL '3 days'
GROUP BY entity_id, blocker_type, blocker_id;
```

**Expected Result:**
- One row: entity_id=2, blocker_type='task', blocker_id=100 (2 days ago = still in cooldown)
- blocker_id=101 (4 days ago) does NOT appear (cooldown expired)

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE entity_id = 2 AND blocker_id IN (100, 101);
```

---

### TC-232-E-005: Multiple channel attempts for same blocker are all stored

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES
  (2, 'task', 200, 'discord', NOW() - INTERVAL '2 hours'),
  (2, 'task', 200, 'discord', NOW() - INTERVAL '1 hour'),
  (2, 'task', 200, 'signal', NOW() - INTERVAL '30 minutes');

SELECT channel_used, attempted_at
FROM proactive_outreach
WHERE entity_id = 2 AND blocker_id = 200
ORDER BY attempted_at;
```

**Expected Result:**
- 3 rows returned (all attempts stored, including multiple Discord attempts)
- Channels: discord, discord, signal in chronological order

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE entity_id = 2 AND blocker_id = 200;
```

---

## Section F: Outreach Cascade Logic

### TC-232-F-001: Domain lookup finds users by domain_topic

**Severity:** S1  
**Preconditions:** user_domains seeded; entities present

**Steps:**
```sql
-- Given a domain_topic (e.g., the domain of a blocked task), find assigned users
-- Replace 'Software Development' with any domain from the seed data
SELECT ud.entity_id, e.name, ud.priority
FROM user_domains ud
JOIN entities e ON ud.entity_id = e.id
WHERE ud.domain_topic = '<seeded_domain_topic>'
ORDER BY ud.priority DESC, RANDOM();
```

**Expected Result:**
- Returns at least one user row
- Columns: entity_id, name, priority present
- Priority ordering is descending (higher priority first)

---

### TC-232-F-002: Equal-priority users are selected randomly (not deterministically)

**Severity:** S2  
**Preconditions:** user_domains seeded with at least two users at same priority for one domain

**Steps:**
```sql
-- Verify at least two users share same priority for a domain
SELECT domain_topic, entity_id, priority
FROM user_domains
WHERE priority = 1
GROUP BY domain_topic, entity_id, priority
HAVING COUNT(*) >= 1
ORDER BY domain_topic;

-- Run the lookup query multiple times and observe ORDER of entity_ids
SELECT ud.entity_id, e.name, ud.priority
FROM user_domains ud
JOIN entities e ON ud.entity_id = e.id
WHERE ud.domain_topic = '<domain_with_equal_priority_users>'
ORDER BY ud.priority DESC, RANDOM()
LIMIT 1;
```

**Expected Result:**
- When run 10+ times, not always the same entity_id returned first (RANDOM() is non-deterministic)
- Both users appear across multiple runs

**Note:** This is a probabilistic test; run at least 10 iterations to validate randomness. Failure = same user always returned.

---

### TC-232-F-003: Channel escalation order is Discord → Signal → Slack → Email

**Severity:** S1  
**Preconditions:** Cascade logic implemented; cascade can be traced via proactive_outreach inserts

**Scenario:** Blocked task triggers outreach cascade for user with all channels available.

**Steps:**
```sql
-- Before cascade: no recent outreach for this entity+blocker
SELECT * FROM proactive_outreach
WHERE entity_id = 2 AND blocker_type = 'task' AND blocker_id = 300;
-- (should be empty)
```

Then trigger the cascade for entity_id=2 on blocker task_id=300.

After cascade attempt (one channel per run):

```sql
SELECT channel_used, attempted_at
FROM proactive_outreach
WHERE entity_id = 2 AND blocker_type = 'task' AND blocker_id = 300
ORDER BY attempted_at;
```

**Expected Result:**
- First attempt: `channel_used = 'discord'`
- Second attempt (next cascade run, no Discord response): `channel_used = 'discord'` again (second attempt per spec)
- Third attempt: `channel_used = 'signal'`
- Fourth attempt: `channel_used = 'slack'`
- Fifth attempt: `channel_used = 'email'`

**Note:** If spec is 2 Discord attempts → 1 Signal → 1 Slack → 1 Email, verify each step has a single row in proactive_outreach before escalating.

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE entity_id = 2 AND blocker_id = 300;
```

---

### TC-232-F-004: Cooldown prevents re-contact within 3 days for same blocker+user

**Severity:** S1  
**Preconditions:** proactive_outreach has a row within 3 days for entity+blocker

**Setup:**
```sql
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES (2, 'task', 400, 'discord', NOW() - INTERVAL '1 day');
```

**Steps:** Trigger cascade logic for same entity_id=2, task blocker 400.

**Expected Result:**
- No new outreach attempt created (cooldown active)
- `proactive_outreach` still has exactly 1 row for this entity+blocker combo
- Cascade moves to next eligible user in domain (if any), skipping entity 2

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE entity_id = 2 AND blocker_id = 400;
```

---

### TC-232-F-005: User escalation within domain when all primary users are in cooldown

**Severity:** S2  
**Preconditions:** user_domains has at least 2 users for a domain; first user in cooldown; second user not in cooldown

**Setup:**
```sql
-- Put user entity_id=2 in cooldown for task 500
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES (2, 'task', 500, 'discord', NOW() - INTERVAL '1 day');
```

**Steps:** Trigger cascade for domain-matched task (task 500), where entity_id=2 is first by priority.

**Expected Result:**
- entity_id=2 skipped (in cooldown)
- Next user for the domain (e.g., entity_id=3) is contacted instead
- New row in proactive_outreach for entity_id=3, blocker_id=500

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE blocker_id = 500;
```

---

### TC-232-F-006: I)ruid (entity_id=2) is final fallback when all domain users exhausted

**Severity:** S1  
**Preconditions:** All users in user_domains for a given domain are in cooldown; entity_id=2 is NOT in cooldown for this specific blocker

**Steps:** Trigger cascade for a task whose domain has no non-cooldown users remaining.

**Expected Result:**
- I)ruid (entity_id=2) is contacted as final fallback
- New row in proactive_outreach with entity_id=2

**Note:** If I)ruid is also in cooldown, test what happens — spec should define whether cascade aborts silently or logs a "could not reach anyone" state.

---

### TC-232-F-007: Cascade integrates into Proactive Mode step 4 (Work on Pending Tasks)

**Severity:** S2  
**Preconditions:** Proactive Mode workflow (id=27) steps updated; step_id=197 (step_order=4) references blocker outreach

**Steps:**
```sql
SELECT description
FROM workflow_steps
WHERE workflow_id = 27 AND step_order = 4;
```

**Expected Result:**
- Description references outreach cascade when a task is blocked
- Language like "invoke outreach cascade" or "contact domain user" present
- No longer says only "set blocked=true, blocked_reason, notify human if needed" without cascade logic

---

### TC-232-F-008: Cascade integrates into Proactive Mode step 5 (Unsolved Problems)

**Severity:** S2  
**Preconditions:** Step_id=198 (step_order=5) updated

**Steps:**
```sql
SELECT description
FROM workflow_steps
WHERE workflow_id = 27 AND step_order = 5;
```

**Expected Result:**
- Description includes outreach cascade reference for when unsolved problems are blocked

---

### TC-232-F-009: Cascade integrates into Proactive Mode step 6 (D100)

**Severity:** S2  
**Preconditions:** Step_id=199 (step_order=6) updated

**Steps:**
```sql
SELECT description
FROM workflow_steps
WHERE workflow_id = 27 AND step_order = 6;
```

**Expected Result:**
- Description includes reference to cascade/outreach when D100 task hits a blocker

---

### TC-232-F-010: Tabby's email stored as entity_fact for entity_id=3

**Severity:** S2  
**Preconditions:** Migration applied; entity_id=3 is Tabatha Wilson

**Steps:**
```sql
SELECT ef.key, ef.value
FROM entity_facts ef
WHERE ef.entity_id = 3 AND ef.key ILIKE '%email%';
```

**Expected Result:**
- At least one row returned
- Value contains `yellowsubtab@gmail.com`
- Key is something like `email` or `email_address`

---

### TC-232-F-011: Cascade respects peer agent recipients (not only humans)

**Severity:** S2  
**Preconditions:** proactive_outreach entity_id can reference agent entities; Hermes (agent, entity exists) is reachable

**Steps:**
```sql
-- Confirm entity exists for an agent (e.g., hermes)
SELECT id, name, type FROM entities WHERE name = 'hermes';

-- Insert an outreach attempt for a peer agent
INSERT INTO proactive_outreach (entity_id, blocker_type, blocker_id, channel_used, attempted_at)
VALUES ((SELECT id FROM entities WHERE name = 'hermes' AND type = 'agent'), 'task', 600, 'discord', NOW())
RETURNING *;
```

**Expected Result:**
- INSERT succeeds (peer agents are valid outreach targets)
- Row in proactive_outreach with agent entity_id

**Cleanup:**
```sql
DELETE FROM proactive_outreach WHERE blocker_id = 600;
```

---

### TC-232-F-012: I)ruid final fallback for domain where he has no user_domains entry

**Severity:** S1

Test: Domain "Crafting" has only Tabatha Wilson (entity 3). After exhausting all her channels and cooldowns, I)ruid (entity 2) should be contacted as final fallback even though he has no user_domains row for Crafting.

**Setup:** Insert cooldown rows for entity 3 on a Crafting-domain blocker covering all channels.

**Expected Result:** Cascade reaches I)ruid (entity 2) as final fallback. New proactive_outreach row for entity 2.

---

### TC-232-F-013: Graceful handling when ALL users including I)ruid are in cooldown

**Severity:** S2

Test: All domain users AND I)ruid (final fallback) are in cooldown for a specific blocker. Cascade should handle this gracefully — log it and skip, do not loop or error.

**Setup:** Insert cooldown rows for all relevant entities for a blocker.

**Expected Result:** No new outreach attempt created. No exception/error. Blocker remains in "awaiting response" state. Cascade completes without action.

---

---

# Issue #237 — Drop channel_activity, Fix Idle Detection

---

## Section G: channel_activity Table Removal

### TC-237-G-001: channel_activity table does not exist post-migration

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'channel_activity'
);
```

**Expected Result:**
- `exists = false`

---

### TC-237-G-002: No foreign keys referencing channel_activity remain

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT tc.table_name, kcu.column_name, ccu.table_name AS referenced_table
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_name = 'channel_activity';
```

**Expected Result:**
- Zero rows (no FKs pointing to channel_activity)

---

### TC-237-G-003: No views or functions depend on channel_activity

**Severity:** S1  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_definition ILIKE '%channel_activity%';

SELECT viewname
FROM pg_views
WHERE definition ILIKE '%channel_activity%';
```

**Expected Result:**
- Zero rows from both queries

---

## Section H: HEARTBEAT.md Idle Detection Update

### TC-237-H-001: HEARTBEAT.md no longer references channel_activity

**Severity:** S2  
**Preconditions:** Migration applied; HEARTBEAT.md updated

**Steps:**
```bash
grep -i "channel_activity" ~/workspace/nova-mind/HEARTBEAT.md
```

**Expected Result:**
- Zero matches

---

### TC-237-H-002: HEARTBEAT.md references native idle detection method

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```bash
grep -iE "sessions_list|message.*read|inbound|last_seen|timestamp" ~/workspace/nova-mind/HEARTBEAT.md
```

**Expected Result:**
- At least one match describing the native idle detection approach (sessions_list timestamps, message(action="read") timestamps, or inbound message metadata)

---

### TC-237-H-003: Proactive Mode workflow idle detection step does not reference channel_activity

**Severity:** S1  
**Preconditions:** Migration applied; workflow steps updated

**Steps:**
```sql
SELECT description
FROM workflow_steps
WHERE workflow_id = 27
  AND description ILIKE '%channel_activity%';
```

**Expected Result:**
- Zero rows

---

### TC-237-H-004: Proactive Mode workflow idle detection references sessions_list or message timestamps

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```sql
SELECT step_order, LEFT(description, 200) AS excerpt
FROM workflow_steps
WHERE workflow_id = 27
  AND (description ILIKE '%sessions_list%'
    OR description ILIKE '%message%read%'
    OR description ILIKE '%last_seen%'
    OR description ILIKE '%inbound%'
    OR description ILIKE '%channel.*timestamp%');
```

**Expected Result:**
- At least one row returned describing the native idle detection approach

---

### TC-237-H-005: No other tables, code files, or scripts reference channel_activity

**Severity:** S2  
**Preconditions:** Migration applied

**Steps:**
```bash
grep -rn "channel_activity" ~/workspace/nova-mind/ --include="*.md" --include="*.sh" --include="*.js" --include="*.ts" --include="*.py" --include="*.sql"
```

**Expected Result:**
- Zero matches across the nova-mind repo

---

### TC-237-H-006: HEARTBEAT.md bootstrap context record updated in database

**Severity:** S2

HEARTBEAT.md is not just a repo file — it's also an `agent_bootstrap_context` record. Verify the database record is updated too.

```sql
SELECT content FROM agent_bootstrap_context
WHERE context_type = 'AGENT' AND agent_name = 'nova' AND file_key = 'HEARTBEAT';
```

**Expected Result:** Content does NOT contain 'channel_activity'. Content DOES reference native idle detection (sessions_list, message timestamps, or similar).

---

## Section I: Native Idle Detection Behavior

### TC-237-I-001: sessions_list data is sufficient to determine last activity time

**Severity:** S2  
**Preconditions:** OpenClaw gateway running; at least one session active

**Steps:**
```bash
# Verify sessions_list returns timestamps (conceptual — run via OpenClaw tool)
# Confirm output includes a timestamp field per session
openclaw sessions list --json 2>/dev/null | jq '.[0] | keys' || echo "sessions_list not available via CLI; test via agent tool call"
```

**Expected Result:**
- Session records contain a timestamp or last_activity field
- Field is usable to determine idle duration

**Note:** This test may require a live agent turn using the `sessions_list` OpenClaw tool rather than CLI. Verify the tool return payload in a test agent run.

---

### TC-237-I-002: message(action="read") returns timestamps usable for idle detection

**Severity:** S2  
**Preconditions:** Active Discord channel with message history

**Steps:** (Conceptual — verify via test agent turn)  
Use `message(action="read", channel="discord", limit=1)` and confirm the returned payload includes a timestamp field.

**Expected Result:**
- Response includes `timestamp` or equivalent field on each message
- Timestamp can be compared to current time to determine idle duration

---

### TC-237-I-003: Idle detection does not fail when channel is newly created (no message history)

**Severity:** S2  
**Preconditions:** A channel exists with no prior messages

**Steps:** Configure idle detection to check `message(action="read")` on an empty channel.

**Expected Result:**
- No exception or crash
- Idle detection treats absence of messages as "channel is idle since creation"
- Agent does not enter a broken state

---

### TC-237-I-004: False-idle detection bug is not reproducible post-migration

**Severity:** S1  
**Preconditions:** Post-migration; channel_activity dropped; native detection in place

**Scenario:** Simulate an active conversation by sending several messages to the agent within 5 minutes.

**Steps:**
1. Send 5 messages to NOVA within a 3-minute window
2. Immediately after the last message, check if NOVA enters proactive mode (should NOT)
3. Wait 20 minutes of genuine silence, then verify NOVA does enter proactive mode (should)

**Expected Result:**
- During active conversation: proactive mode NOT triggered
- After genuine idle period: proactive mode triggered
- Confirms channel_activity table was the source of false-idle detection; native timestamps resolve it

---

---

# Cross-Issue Integration Tests

---

## Section J: Schema Integrity (All Three Issues Combined)

### TC-INT-J-001: Full schema validation post all migrations

**Severity:** S1  
**Preconditions:** All three issue migrations applied

**Steps:**
```sql
-- Verify all new tables exist
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('user_domains', 'proactive_outreach')
ORDER BY table_name;

-- Verify dropped table is gone
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'channel_activity';

-- Verify agents.entity_id exists
SELECT column_name FROM information_schema.columns
WHERE table_name = 'agents' AND column_name = 'entity_id';

-- Verify agent_domains.priority exists
SELECT column_name FROM information_schema.columns
WHERE table_name = 'agent_domains' AND column_name = 'priority';
```

**Expected Result:**
- user_domains: present
- proactive_outreach: present
- channel_activity: absent
- agents.entity_id: present
- agent_domains.priority: present

---

### TC-INT-J-002: Bootstrap context delivery unaffected by agent_domains constraint change

**Severity:** S1  
**Preconditions:** All migrations applied; get_agent_bootstrap function exists

**Steps:**
```sql
-- Test bootstrap for several agents
SELECT get_agent_bootstrap('nova');
SELECT get_agent_bootstrap('coder');
SELECT get_agent_bootstrap('newhart');
```

**Expected Result:**
- All three return valid bootstrap JSON/text
- No SQL errors
- Domains are listed correctly per agent
- No agent gets another agent's domains

---

### TC-INT-J-003: Outreach cascade can route to domain owners via new agent_domains priority

**Severity:** S2  
**Preconditions:** agent_domains has priority column; user_domains seeded; cascade logic implemented

**Scenario:** A task is blocked. The task's domain has both a primary agent owner (priority=1) and a secondary owner (priority=2) via agent_domains.

**Steps:**
- Insert an agent_domains row for a domain with priority=2 for a second agent
- Trigger cascade for a task in that domain
- Confirm the cascade queries user_domains first (human users), then falls back appropriately

**Expected Result:**
- Cascade follows user_domains priority order for human outreach
- agent_domains priority ordering is separately respected when routing to agents vs users

---

### TC-INT-J-004: nova-mind motivation/ files do not conflict with existing directories

**Severity:** S2  
**Preconditions:** All migrations applied; nova-mind repo updated

**Steps:**
```bash
# Check no naming conflicts with existing nova-mind top-level dirs
ls ~/workspace/nova-mind/ | sort
# motivation/ should appear alongside cognition/, database/, memory/, etc.
```

**Expected Result:**
- `motivation/` exists as a new directory
- No existing directory was overwritten or renamed
- All original nova-mind directories still present: `cognition/`, `memory/`, `psyche/`, `relationships/`, `skills/`, `tests/`

---

### TC-INT-J-005: Proactive Mode workflow steps 4, 5, 6 all reference both outreach and idle detection correctly

**Severity:** S2  
**Preconditions:** All migrations applied; workflow updated

**Steps:**
```sql
SELECT step_order, LEFT(description, 500)
FROM workflow_steps
WHERE workflow_id = 27 AND step_order IN (4, 5, 6)
ORDER BY step_order;
```

**Expected Result:**
- Step 4: References outreach cascade when task is blocked; no channel_activity reference
- Step 5: References outreach cascade when unsolved problem hits a blocker; no channel_activity reference
- Step 6: References outreach cascade for D100 blockers; no channel_activity reference
- None of the three steps mention channel_activity

---

---

# Regression Tests

---

## Section K: Backward Compatibility

### TC-REG-K-001: Existing agent_domains queries (by agent_id) still work

**Severity:** S1  
**Preconditions:** All migrations applied

**Steps:**
```sql
SELECT domain_topic FROM agent_domains WHERE agent_id = 1 ORDER BY domain_topic;
SELECT domain_topic FROM agent_domains WHERE agent_id = 3 ORDER BY domain_topic;
```

**Expected Result:**
- Returns same domains as before migration for each agent
- No errors

---

### TC-REG-K-002: Existing SELECT * FROM agent_domains still returns valid rows

**Severity:** S1  
**Preconditions:** All migrations applied

**Steps:**
```sql
SELECT id, agent_id, domain_topic, priority, vote_count, created_at FROM agent_domains ORDER BY id LIMIT 10;
```

**Expected Result:**
- Returns rows with all columns
- priority = 1 for all original rows
- No NULL values in unexpected columns

---

### TC-REG-K-003: agents table retains all existing columns and data

**Severity:** S1  
**Preconditions:** All migrations applied

**Steps:**
```sql
SELECT id, name, model, status, thinking, entity_id
FROM agents
WHERE status = 'active'
ORDER BY id;
```

**Expected Result:**
- All agents present with correct existing data
- `entity_id` populated for name-matched agents
- No existing data corrupted

---

### TC-REG-K-004: protect_agent_writes trigger still blocks unauthorized domain writes

**Severity:** S1  
**Preconditions:** All migrations applied; domain ownership triggers intact

**Steps:**
```bash
# Connect as a non-owner agent user (e.g., scout) and try to insert into agent_domains for nova
psql -U scout -d nova_memory -h localhost -c "
INSERT INTO agent_domains (agent_id, domain_topic) VALUES (1, 'TC-REG-TEST-DOMAIN');
"
```

**Expected Result:**
- Error from trigger: `protect_agent_writes` or similar message indicating unauthorized write
- INSERT blocked

---

### TC-REG-K-005: entity_facts for known entities unaffected by migrations

**Severity:** S2  
**Preconditions:** All migrations applied

**Steps:**
```sql
SELECT COUNT(*) FROM entity_facts WHERE entity_id = 2;
-- Also spot-check one known fact
SELECT key, LEFT(value, 100) FROM entity_facts WHERE entity_id = 2 AND key = 'discord_username' LIMIT 1;
```

**Expected Result:**
- Count unchanged from pre-migration
- Known fact (discord_username = 'I)ruid') still present

---

---

# Test Execution Checklist

## Pre-Test Setup
- [ ] Stage environment deployed with all three issue migrations applied in order
- [ ] Database state backed up before testing
- [ ] nova-motivation repo accessible at `~/workspace/nova-motivation/`
- [ ] nova-mind repo updated at `~/workspace/nova-mind/`
- [ ] All entry criteria verified

## Test Execution Order (Recommended)

1. **Schema Validation** — Section B, C, D, E first (foundational)
2. **File/Content Tests** — Section A (motivation/ merge)
3. **Logic Tests** — Section F (outreach cascade)
4. **Idle Detection** — Sections G, H, I
5. **Integration** — Section J
6. **Regression** — Section K (run last to confirm nothing broken)

## Test Result Recording

For each test case, record:
- **Status:** PASS / FAIL / SKIP
- **Tester:** Agent name
- **Date:** ISO date
- **Notes:** Defects found, deviations from expected, workarounds

## Defect Reporting

File defects in the nova-mind GitHub repo with:
- Test case ID in the title (e.g., `[TC-232-F-003] Channel escalation order incorrect`)
- Severity label (s1/s2/s3/s4)
- Steps to reproduce, expected vs actual result
- Label: `bug`, `batch-se-run-8`
