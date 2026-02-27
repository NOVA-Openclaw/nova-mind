# Test Cases: Entity Merge for Overlapping Authenticated Data (Issue #40)

## Design Review Notes

### Schema Observations
- `entity_facts` already has `source` (varchar 255) and `confidence` (float 0-1) but **no `trust_level`** column — needs adding
- `entity_facts` has `data_type` with values: permanent, identity, preference, temporal, observation — identity facts are natural merge keys
- `entity_facts_archive` exists with `archive_reason` and `archived_by` — reusable for merge archival
- `entity_fact_conflicts` table already exists — merge should leverage this for conflict logging
- **16 tables reference `entities(id)`** — all FK updates must be handled:
  - agent_actions, agent_domains, certificates, entity_fact_conflicts, entity_facts (×2: entity_id + source_entity_id), entity_relationships (×2: entity_a + entity_b), event_entities, gambling_logs, media_consumed, media_queue, preferences, project_entities, tasks (×3: assigned_to + blocked_on + created_by), vehicles

### Design Gaps / Edge Cases to Address
1. **Unique constraint on `entities(name, type)`** — merged entity keeps primary's name; what if secondary has a different name that other systems reference?
2. **Unique constraint on `entities(user_id)`** — if both entities have `user_id`, which wins?
3. **Unique constraint on `entity_relationships(entity_a, entity_b, relationship)`** — merging may create duplicate relationship rows
4. **Unique constraint on `event_entities(event_id, entity_id)`** — same event linked to both entities → conflict on merge
5. **`entity_facts.source_entity_id`** — other entities' facts may reference the secondary as source; must update
6. **`entity_fact_conflicts`** — existing conflicts referencing secondary entity need migration
7. **Nicknames array on entities** — should merge/union nicknames from both
8. **`entities.last_seen`** — should take MAX of both
9. **Rollback strategy** — if merge fails mid-way, need transaction safety
10. **Ordering ambiguity** — "choose primary" needs deterministic rules (older entity? more facts? explicit choice?)

---

## Schema Additions Required

```sql
-- 1. Add trust_level to entity_facts
ALTER TABLE entity_facts ADD COLUMN trust_level varchar(20) DEFAULT 'unknown'
  CHECK (trust_level IN ('verified', 'stated', 'inferred', 'unknown'));

-- 2. Create merge log table
CREATE TABLE entity_merge_log (
  id serial PRIMARY KEY,
  primary_entity_id integer NOT NULL REFERENCES entities(id),
  secondary_entity_id integer NOT NULL, -- no FK, entity may be archived/deleted
  secondary_entity_name varchar(255),
  merge_reason text,
  matching_facts jsonb, -- the overlapping facts that triggered merge
  facts_moved integer DEFAULT 0,
  relationships_moved integer DEFAULT 0,
  conflicts_created integer DEFAULT 0,
  dry_run boolean DEFAULT false,
  merged_by varchar(100),
  merged_at timestamptz DEFAULT now(),
  rollback_data jsonb -- snapshot for potential undo
);
```

---

## Test Cases

### Setup: Test Fixtures

```sql
-- Base test entities
INSERT INTO entities (id, name, type, created_at, last_seen, nicknames, user_id)
VALUES
  (9001, 'John Smith', 'person', '2025-01-01', '2026-01-15', ARRAY['Johnny'], NULL),
  (9002, 'J. Smith', 'person', '2025-06-01', '2026-02-01', ARRAY['JS'], NULL),
  (9003, 'Jane Doe', 'person', '2025-03-01', '2026-01-20', NULL, NULL),
  (9004, 'Unrelated Bob', 'person', '2025-01-01', '2025-12-01', NULL, NULL),
  (9005, 'Chain Entity A', 'person', '2025-01-01', NULL, NULL, NULL),
  (9006, 'Chain Entity B', 'person', '2025-02-01', NULL, NULL, NULL),
  (9007, 'Chain Entity C', 'person', '2025-03-01', NULL, NULL, NULL);

-- Identity facts with trust levels
INSERT INTO entity_facts (entity_id, key, value, data_type, trust_level, confidence, source)
VALUES
  -- John Smith: verified email
  (9001, 'email', 'john@example.com', 'identity', 'verified', 1.0, 'oauth_google'),
  (9001, 'phone', '+1-555-0101', 'identity', 'stated', 0.9, 'user_input'),
  (9001, 'occupation', 'engineer', 'observation', 'stated', 0.8, 'conversation'),
  -- J. Smith: same verified email (merge candidate!)
  (9002, 'email', 'john@example.com', 'identity', 'verified', 1.0, 'oauth_google'),
  (9002, 'occupation', 'software developer', 'observation', 'stated', 0.7, 'linkedin'),
  (9002, 'city', 'Portland', 'temporal', 'stated', 0.8, 'conversation'),
  -- Jane Doe: inferred-only overlap (should NOT trigger merge)
  (9003, 'email', 'john@example.com', 'identity', 'inferred', 0.3, 'email_cc_guess'),
  -- Chain entities
  (9005, 'sso_id', 'SSO-ABC', 'identity', 'verified', 1.0, 'sso'),
  (9006, 'sso_id', 'SSO-ABC', 'identity', 'verified', 1.0, 'sso'),
  (9006, 'phone', '+1-555-9999', 'identity', 'verified', 1.0, 'twilio'),
  (9007, 'phone', '+1-555-9999', 'identity', 'verified', 1.0, 'twilio');
```

---

### TC-01: Happy Path — Verified Email Overlap Merge

**Precondition:** Entities 9001 and 9002 share `email=john@example.com` with `trust_level=verified`

**Steps:**
1. Call `find_merge_candidates()` 
2. Verify (9001, 9002) appears in results with matching fact `email=john@example.com`
3. Call `merge_entities(9001, 9002)` (9001 is primary — older entity)
4. Verify entity 9002 is archived/soft-deleted
5. Verify all entity_facts from 9002 now belong to 9001
6. Verify entity 9001.nicknames includes both `['Johnny', 'JS']`
7. Verify entity 9001.last_seen = '2026-02-01' (MAX of both)
8. Verify entity 9001.full_name or notes references "J. Smith" as alias

**Expected:** Merge succeeds, 9002's facts (city=Portland, occupation=software developer) transferred to 9001

---

### TC-02: Trust Level Filter — Inferred-Only Match Rejected

**Precondition:** Entity 9003 shares `email=john@example.com` with 9001, but 9003's fact is `trust_level=inferred`

**Steps:**
1. Call `find_merge_candidates()` with minimum trust = 'verified' or 'stated'
2. Check results

**Expected:** Pair (9001, 9003) does NOT appear in merge candidates. Only verified/high-confidence stated matches qualify.

---

### TC-03: Trust Level Filter — Stated with High Confidence Qualifies

**Precondition:** Two entities share phone number with `trust_level=stated, confidence >= 0.8`

**Steps:**
1. Create two entities sharing `phone=+1-555-0101` both with `trust_level=stated, confidence=0.9`
2. Call `find_merge_candidates(min_trust='stated', min_confidence=0.8)`

**Expected:** Pair appears as candidate

---

### TC-04: Trust Level Filter — Stated with Low Confidence Rejected

**Steps:**
1. Two entities share a fact with `trust_level=stated, confidence=0.4`
2. Call `find_merge_candidates(min_trust='stated', min_confidence=0.8)`

**Expected:** Pair does NOT appear

---

### TC-05: Conflict Resolution — Same Key, Different Values

**Precondition:** Entity 9001 has `occupation=engineer` (confidence 0.8), entity 9002 has `occupation=software developer` (confidence 0.7)

**Steps:**
1. Merge 9001 ← 9002
2. Check entity_facts for entity 9001 with key='occupation'

**Expected:**
- Primary's fact (`engineer`, confidence 0.8) is kept as active
- Secondary's fact (`software developer`, confidence 0.7) is either:
  - (a) Recorded in `entity_fact_conflicts` for manual review, OR
  - (b) Kept as secondary fact with lower confidence
- Neither fact is silently dropped

---

### TC-06: Conflict Resolution — Secondary Has Higher Confidence

**Precondition:** Primary has `city=Seattle` (confidence 0.5), secondary has `city=Portland` (confidence 0.9)

**Steps:**
1. Merge primary ← secondary

**Expected:** Higher-confidence value wins OR conflict is flagged. Document the chosen strategy. Both values should be preserved in some form.

---

### TC-07: FK Updates — entity_relationships

**Precondition:** 
- Entity 9002 has relationship: `entity_a=9002, entity_b=9003, relationship='colleague'`
- Entity 9001 does NOT have this relationship with 9003

**Steps:**
1. Merge 9001 ← 9002
2. Query entity_relationships

**Expected:** Relationship now shows `entity_a=9001, entity_b=9003, relationship='colleague'`

---

### TC-08: FK Updates — Duplicate Relationship Prevention

**Precondition:**
- Entity 9001 has: `entity_a=9001, entity_b=9003, relationship='friend'`
- Entity 9002 has: `entity_a=9002, entity_b=9003, relationship='friend'`

**Steps:**
1. Merge 9001 ← 9002

**Expected:** No unique constraint violation. Duplicate is either skipped (with note in log) or the existing one is kept. Unique constraint `(entity_a, entity_b, relationship)` must not be violated.

---

### TC-09: FK Updates — event_entities Dedup

**Precondition:**
- event_entities has (event_id=100, entity_id=9001) and (event_id=100, entity_id=9002)

**Steps:**
1. Merge 9001 ← 9002

**Expected:** Only one row (event_id=100, entity_id=9001) remains. PK `(event_id, entity_id)` not violated.

---

### TC-10: FK Updates — All 16 Referencing Tables

**Steps:**
1. Create references to entity 9002 in ALL referencing tables:
   - agent_actions (agent_id)
   - agent_domains (source_entity_id)
   - certificates (entity_id)
   - entity_fact_conflicts (entity_id)
   - entity_facts (entity_id, source_entity_id)
   - entity_relationships (entity_a, entity_b)
   - event_entities (entity_id)
   - gambling_logs (entity_id)
   - media_consumed (consumed_by)
   - media_queue (requested_by)
   - preferences (entity_id)
   - project_entities (entity_id)
   - tasks (assigned_to, blocked_on, created_by)
   - vehicles (owner_id)
2. Merge 9001 ← 9002

**Expected:** Every FK reference to 9002 is updated to 9001 (or handled for unique conflicts). No orphaned references remain.

---

### TC-11: Dry-Run Mode — No Side Effects

**Steps:**
1. Record full state: count of entity_facts, entity_relationships, entities
2. Call `merge_entities(9001, 9002, dry_run=True)`
3. Re-check all counts

**Expected:**
- Returns a preview report: facts to move, relationships to update, conflicts detected
- Zero rows changed in any table
- entity_merge_log entry created with `dry_run=true`

---

### TC-12: Dry-Run Mode — Matches Actual Merge

**Steps:**
1. Run dry-run, capture report (facts_moved, relationships_moved, conflicts)
2. Run actual merge
3. Compare counts

**Expected:** Dry-run predictions match actual merge results exactly

---

### TC-13: Audit Log Completeness

**Steps:**
1. Merge 9001 ← 9002
2. Query entity_merge_log

**Expected:** Log entry contains:
- primary_entity_id = 9001
- secondary_entity_id = 9002
- secondary_entity_name = 'J. Smith'
- matching_facts includes `{"key": "email", "value": "john@example.com"}`
- facts_moved = correct count
- relationships_moved = correct count
- conflicts_created = correct count
- merged_by = caller identity
- rollback_data = snapshot sufficient to undo

---

### TC-14: Audit Log — Rollback Data Sufficient

**Steps:**
1. Merge 9001 ← 9002
2. Extract rollback_data from entity_merge_log
3. Verify it contains: secondary entity's original row, all moved facts with original entity_id, all moved relationships

**Expected:** rollback_data is complete enough to reconstruct pre-merge state

---

### TC-15: Self-Merge Prevention

**Steps:**
1. Call `merge_entities(9001, 9001)`

**Expected:** Error raised: "Cannot merge entity with itself"

---

### TC-16: Merge Already-Merged Entity Prevention

**Steps:**
1. Merge 9001 ← 9002 (9002 archived)
2. Call `merge_entities(9001, 9002)` again

**Expected:** Error: "Secondary entity 9002 is already archived/merged"

---

### TC-17: Chain Merge — A→B then B→C Equivalent

**Precondition:** 
- 9005 and 9006 share `sso_id=SSO-ABC` (verified)
- 9006 and 9007 share `phone=+1-555-9999` (verified)

**Steps:**
1. `find_merge_candidates()` — should find both pairs
2. Merge 9005 ← 9006
3. Now 9005 has the phone from 9006
4. `find_merge_candidates()` — should now find (9005, 9007) via phone
5. Merge 9005 ← 9007

**Expected:** 
- After both merges, entity 9005 has all facts from 9005+9006+9007
- Two merge log entries exist
- Entities 9006 and 9007 are both archived

---

### TC-18: Chain Merge — Transitive Discovery

**Steps:**
1. Call `find_merge_candidates(transitive=True)` 

**Expected:** System identifies that 9005↔9006↔9007 form a connected component and suggests merging all three in one operation (or flags the chain for review)

---

### TC-19: Concurrent Merge Prevention

**Steps:**
1. Begin transaction T1: `merge_entities(9001, 9002)`
2. Before T1 commits, begin T2: `merge_entities(9001, 9002)`

**Expected:** T2 either:
- Blocks until T1 completes (row-level lock), then fails with "already merged"
- Fails immediately with conflict error
- No data corruption in either case

---

### TC-20: Concurrent Merge — Same Secondary, Different Primary

**Steps:**
1. T1: `merge_entities(9001, 9002)` 
2. T2: `merge_entities(9003, 9002)` (concurrent)

**Expected:** Only one succeeds. The other gets an error. Entity 9002 cannot be merged into two different primaries.

---

### TC-21: No Overlap — Entities with Zero Shared Facts

**Steps:**
1. Call `find_merge_candidates()` for entities 9001 and 9004 (no shared identity facts)

**Expected:** Pair (9001, 9004) does NOT appear in candidates

---

### TC-22: Overlap on Non-Identity Facts Ignored

**Precondition:** Two entities both have `occupation=engineer` with `data_type=observation`

**Steps:**
1. Call `find_merge_candidates()`

**Expected:** Pair does NOT appear — merge only triggers on identity-type facts (email, phone, SSO ID), not general observations

---

### TC-23: Merge Preserves Fact Metadata

**Steps:**
1. Entity 9002 has fact with specific `learned_at`, `source`, `confidence`, `visibility`, `data_type`, `vote_count`
2. Merge 9001 ← 9002

**Expected:** Transferred facts retain all original metadata (learned_at, source, confidence, etc.) — only `entity_id` changes

---

### TC-24: Entity with user_id Conflict

**Precondition:** 
- Entity 9001 has `user_id = 'user-alpha'`
- Entity 9002 has `user_id = 'user-beta'`

**Steps:**
1. Merge 9001 ← 9002

**Expected:** Since `user_id` has a UNIQUE constraint, merge must handle this:
- Keep primary's user_id
- Log secondary's user_id in rollback_data
- Or flag as conflict requiring manual resolution

---

### TC-25: Merge with entities.trust_level Consideration

**Precondition:** Primary entity has `trust_level='unknown'`, secondary has `trust_level='verified'` (on entities table — note this is different from entity_facts.trust_level)

**Steps:**
1. Merge primary ← secondary

**Expected:** Resulting entity should have the higher trust_level (verified), not downgrade to unknown

---

### TC-26: Large Merge — Entity with Many Facts/Relationships

**Steps:**
1. Create entity with 500 facts and 50 relationships
2. Merge into another entity
3. Verify all transferred, measure execution time

**Expected:** Completes within reasonable time (<5s), no facts lost

---

### TC-27: Merge Candidate Scoring

**Steps:**
1. Entity A shares 1 verified fact with B, 3 verified facts with C
2. Call `find_merge_candidates()` for entity A

**Expected:** Results are ranked — C scores higher than B as merge candidate (more overlapping evidence)

---

### TC-28: Privacy/Visibility Preservation on Merge

**Precondition:** Secondary entity has facts with `visibility='private'` and `privacy_scope=[9002]`

**Steps:**
1. Merge 9001 ← 9002

**Expected:** 
- Private facts transferred with visibility intact
- `privacy_scope` updated from `[9002]` to `[9001]` where appropriate

---

### TC-29: Archived Facts Not Duplicated

**Precondition:** entity_facts_archive contains old facts for entity 9002

**Steps:**
1. Merge 9001 ← 9002
2. Check entity_facts_archive

**Expected:** Archived facts for 9002 have entity_id updated to 9001 (or kept with note), no duplication

---

### TC-30: Idempotent Candidate Discovery

**Steps:**
1. Call `find_merge_candidates()` twice

**Expected:** Same results both times (no side effects from discovery)

---

## Summary

| Category | Test Cases | Count |
|----------|-----------|-------|
| Happy path | TC-01 | 1 |
| Trust level filtering | TC-02, TC-03, TC-04 | 3 |
| Conflict resolution | TC-05, TC-06 | 2 |
| FK updates | TC-07, TC-08, TC-09, TC-10 | 4 |
| Dry-run mode | TC-11, TC-12 | 2 |
| Audit logging | TC-13, TC-14 | 2 |
| Self/duplicate prevention | TC-15, TC-16 | 2 |
| Chain merges | TC-17, TC-18 | 2 |
| Concurrency | TC-19, TC-20 | 2 |
| No-match / negative | TC-21, TC-22 | 2 |
| Data integrity | TC-23, TC-24, TC-25, TC-28, TC-29 | 5 |
| Performance | TC-26 | 1 |
| Scoring/ranking | TC-27 | 1 |
| Idempotency | TC-30 | 1 |
| **Total** | | **30** |
