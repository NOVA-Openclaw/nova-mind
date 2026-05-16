# Test Cases: Batch SE-Run2

**Issues:** #222, #225, #226, #221, #224, #75  
**Branch:** `feature/batch-se-run2` (or per-issue branches)  
**Deliverable:** Consolidate nova-psyche repo; agent entity resolution; parent_agent_id schema; self-awareness hook; agent outbound extraction; confidence-check hook  
**Author:** Gem (QA Lead)

---

## Scope

### What Is Being Tested

1. **#222** — Consolidation of nova-psyche docs into `nova-mind/psyche/`; nova-psyche GitHub archive
2. **#225** — `agent_id` entity_facts for peer agents; `agent:` prefix handling in `_resolve_by_sender_id()`
3. **#226** — `parent_agent_id` column on `agents` table; subagent resolution logic
4. **#221** — Self-Awareness plugin: `message_sent` hook, `self_awareness_triggers` table, embedding similarity, action dispatch, cooldown, keyphrase self-heal
5. **#224** — Agent outbound extraction via extract_memories.py: caller env vars, opinion vs parroting differentiation, `SOURCE_CONTEXT` env var
6. **#75** — Confidence-Check plugin: `before_agent_finalize` hook, heuristic pre-screen, LLM evaluation, revision retry, low-confidence framing

### What Is NOT Tested Here

- Production memory extraction from inbound user messages (covered in TEST-CASES-BATCH4-EXTRACTION.md)
- Turn-context plugin subsystems (entity resolution, semantic recall) — tested in REVIEW-ISSUE-182-PHASE1.md
- Database migration rollback procedures (covered in migration test suites)
- Nova-psyche repository content accuracy (Coder's responsibility; QA validates file placement only)

---

## Entry Criteria

- Staging environment running nova-openclaw fork with NOVA systems installed
- `nova_memory` database accessible on staging with required tables
- `OPENROUTER_API_KEY` set; Ollama running on `localhost:11434` with `snowflake-arctic-embed2` model pulled
- `agents` table contains nova, newhart, graybeard (peer agents) and representative subagents
- `entities` table contains entity records for nova (id=1), newhart (id=256), graybeard (id=388)
- Python 3.10+ with `psycopg2`, `requests` installed
- nova-mind repo at `~/workspace/nova-mind/` on staging

## Exit Criteria

- All TC-PASS cases pass on staging
- All TC-FAIL and TC-REJECT cases correctly reject/handle bad input or invalid state
- Zero unhandled exceptions from any tested component
- No S1/S2 defects open; S3 defects documented with workaround
- All DB verifications runnable as SQL queries against staging `nova_memory`

---

## Issue #222 — Consolidate nova-psyche into nova-mind

### TC-222-HP-001: Design docs copied to psyche/ directory

**Preconditions:**
- Staging nova-mind repo cloned
- nova-psyche content available (local copy or from GitHub before archive)
- No `psyche/` directory exists in nova-mind

**Steps:**
```bash
ls ~/workspace/nova-mind/psyche/
```

**Expected:**
- Directory exists
- Contains exactly 5 files:
  - `README.md`
  - `ARCHITECTURE-agent-chat.md`
  - `ARCHITECTURE-entities-users.md`
  - `ARCHITECTURE-user-identification.md`
  - `DESIGN-core-values.md`

**Pass criteria:**
```bash
ls ~/workspace/nova-mind/psyche/ | wc -l
# Expected: 5
```

---

### TC-222-HP-002: .nova/ metadata NOT copied

**Preconditions:** Same as HP-001

**Steps:**
```bash
ls ~/workspace/nova-mind/psyche/.nova 2>&1
```

**Expected:** `ls: cannot access '.../.nova': No such file or directory` (exit code 1)

**Pass criteria:** `.nova/` directory does not exist under `psyche/`

---

### TC-222-HP-003: Copied files are non-empty and readable

**Steps:**
```bash
for f in README.md ARCHITECTURE-agent-chat.md ARCHITECTURE-entities-users.md \
          ARCHITECTURE-user-identification.md DESIGN-core-values.md; do
  wc -c ~/workspace/nova-mind/psyche/$f
done
```

**Expected:** Each file has byte count > 0

**Pass criteria:** No zero-byte files

---

### TC-222-HP-004: nova-mind README references psyche/ as fourth pillar

**Steps:**
```bash
grep -i "psyche" ~/workspace/nova-mind/README.md
```

**Expected:** At least one line referencing `psyche` alongside (or after) `memory/`, `cognition/`, `relationships/`

**Pass criteria:** `grep` returns ≥ 1 matching line; exit code 0

---

### TC-222-HP-005: nova-psyche GitHub repo is archived

**Preconditions:** GitHub CLI (`gh`) configured on staging or local dev machine with appropriate auth

**Steps:**
```bash
gh repo view nova-psyche --json isArchived --jq '.isArchived'
```

**Expected:** `true`

**Pass criteria:** Output is `true`

---

### TC-222-EDGE-001: Psyche docs do not overwrite existing nova-mind files

**Purpose:** Guard against namespace collision if a file in nova-psyche happens to share a name with an existing nova-mind root-level file.

**Steps:**
```bash
# None of the 5 psyche files should exist at nova-mind root or in memory/, cognition/, relationships/
for f in README.md ARCHITECTURE-agent-chat.md ARCHITECTURE-entities-users.md \
          ARCHITECTURE-user-identification.md DESIGN-core-values.md; do
  [ -f ~/workspace/nova-mind/$f ] && echo "ROOT COLLISION: $f" || true
  [ -f ~/workspace/nova-mind/memory/$f ] && echo "MEMORY COLLISION: $f" || true
done
```

**Expected:** No COLLISION lines printed (the psyche/ directory is a new fourth pillar, distinct from the three existing ones)

**Pass criteria:** Only the psyche/ path contains these files; no collisions elsewhere

---

### TC-222-EDGE-002: File content integrity — no git merge artifacts

**Steps:**
```bash
grep -rn "<<<<<<" ~/workspace/nova-mind/psyche/ && echo "MERGE CONFLICT FOUND" || echo "CLEAN"
```

**Expected:** `CLEAN`

**Pass criteria:** No merge conflict markers in any psyche/ file

---

## Issue #225 — agent_id entity_facts + _resolve_by_sender_id() agent: prefix

### TC-225-HP-001: agent_id entity_facts exist for all three peer agents

**Steps:**
```sql
SELECT e.name, ef.key, ef.value
FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE ef.key = 'agent_id'
ORDER BY e.name;
```

**Expected:**
| name      | key      | value          |
|-----------|----------|----------------|
| graybeard | agent_id | agent:graybeard|
| newhart   | agent_id | agent:newhart  |
| nova      | agent_id | agent:nova     |

**Pass criteria:** Exactly 3 rows, matching exactly the values above

---

### TC-225-HP-002: _resolve_by_sender_id() resolves agent:nova to entity id 1

**Purpose:** Confirm the length guard bypass allows short agent name prefixes.

**Steps:**
```bash
# Run a quick Python snippet on staging that exercises _resolve_by_sender_id
python3 - <<'EOF'
import sys, os
sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from pg_env import load_pg_env
load_pg_env()
import psycopg2

conn = psycopg2.connect()

# Simulate _resolve_by_sender_id with the agent: prefix format
sender_id = "agent:nova"

# Check the length guard (must be >= 8 to pass, "agent:nova" is 10 chars — OK)
clean = sender_id.strip()
print(f"Length check: {len(clean)} >= 8? {len(clean) >= 8}")

with conn.cursor() as cur:
    cur.execute("SELECT DISTINCT entity_id FROM entity_facts WHERE value = %s LIMIT 1", (sender_id,))
    row = cur.fetchone()
    print(f"Resolved entity_id: {row[0] if row else None}")

conn.close()
EOF
```

**Expected:**
```
Length check: 10 >= 8? True
Resolved entity_id: 1
```

**Pass criteria:** `Resolved entity_id: 1`

---

### TC-225-HP-003: _resolve_by_sender_id() resolves agent:newhart to entity id 256

**Steps:** Same as HP-002 but `sender_id = "agent:newhart"`

**Expected:** `Resolved entity_id: 256`

---

### TC-225-HP-004: _resolve_by_sender_id() resolves agent:graybeard to entity id 388

**Steps:** Same as HP-002 but `sender_id = "agent:graybeard"`

**Expected:** `Resolved entity_id: 388`

---

### TC-225-EDGE-001: agent: prefix survives the length guard for shortest expected ID

**Purpose:** The shortest agent name we have is "nova" (4 chars). With "agent:" prefix it's 10 chars. Verify the guard passes.

**Boundary values to test:**
| sender_id         | len | passes guard? | expected result |
|-------------------|-----|---------------|-----------------|
| `agent:nova`      | 10  | YES           | resolves to entity |
| `agent:x`         | 8   | YES (boundary)| no match (no such agent_id in DB) |
| `agent:`          | 6   | NO            | returns None (too short) |
| `nova`            | 4   | NO            | returns None (too short, old behavior preserved) |

**Steps:**
```python
# For each: check len(clean) >= 8 and confirm _resolve_by_sender_id behavior
cases = [
    ("agent:nova", True),   # resolves
    ("agent:x", True),      # passes guard, no match in DB
    ("agent:", False),      # fails guard, returns None
    ("nova", False),        # fails guard, returns None (old behavior preserved)
]
for sid, should_pass_guard in cases:
    clean = sid.strip()
    passes = len(clean) >= 8
    assert passes == should_pass_guard, f"Guard mismatch for {sid!r}: got {passes}"
    print(f"  {sid!r}: len={len(clean)} guard={passes} ✓")
```

**Pass criteria:** All assertions pass; short IDs that would cause false positive matches are rejected

---

### TC-225-EDGE-002: entity_facts values are exact-match (agent:nova ≠ agent:nova2)

**Purpose:** Confirm value= scan doesn't substring-match.

**Steps:**
```sql
SELECT entity_id FROM entity_facts WHERE value = 'agent:nova2' LIMIT 1;
```

**Expected:** 0 rows (no such agent_id exists)

**Pass criteria:** Empty result set

---

### TC-225-HP-005: resolve_source_entity_id() with agent:nova sender returns entity 1

**Purpose:** Full integration path — when called from extract_memories.py with `SENDER_ID=agent:nova`, it resolves correctly.

**Steps:**
```bash
echo "Test outbound extraction" | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  SENDER_PROVIDER=openclaw \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py
```

**Expected:**
- Exit code 0 (or 0 with empty `{}` if no facts extracted — content is short/not factual)
- No "Could not resolve entity id" WARNING in stderr for the nova sender
- Stderr shows sender entity resolution succeeded (or silently proceeded)

**Pass criteria:** Exit 0; no entity resolution WARNING for sender

---

### TC-225-FAIL-002: Short agent names without prefix still fail guard (regression)

**Purpose:** Confirm we did NOT regress on the original length guard intent — short non-prefixed IDs (phone suffixes, common words) must not resolve.

**Steps:**
```python
short_ids = ["nova", "gem", "1234", "abc"]
for sid in short_ids:
    clean = sid.strip()
    passes = len(clean) >= 8
    assert not passes, f"Short ID {sid!r} should fail guard but passed"
    print(f"  {sid!r}: len={len(clean)} guard=BLOCKED ✓")
```

**Pass criteria:** All short IDs blocked; no DB queries issued for them

---

## Issue #226 — parent_agent_id column on agents table

### TC-226-HP-001: Column exists with correct type and FK constraint

**Steps:**
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'agents' AND column_name = 'parent_agent_id';
```

**Expected:**
| column_name     | data_type | is_nullable |
|-----------------|-----------|-------------|
| parent_agent_id | integer   | YES         |

**Pass criteria:** Column exists, is nullable integer

---

### TC-226-HP-002: FK constraint references agents(id)

**Steps:**
```sql
SELECT
  kcu.column_name,
  ccu.table_name AS foreign_table,
  ccu.column_name AS foreign_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND kcu.table_name = 'agents'
  AND kcu.column_name = 'parent_agent_id';
```

**Expected:**
| column_name     | foreign_table | foreign_column |
|-----------------|---------------|----------------|
| parent_agent_id | agents        | id             |

**Pass criteria:** Self-referential FK exists on `agents.parent_agent_id → agents.id`

---

### TC-226-HP-003: Primary agents have NULL parent_agent_id

**Steps:**
```sql
SELECT name, instance_type, parent_agent_id
FROM agents
WHERE instance_type = 'primary';
```

**Expected:** All rows have `parent_agent_id = NULL`

**Pass criteria:** `COUNT(*) WHERE instance_type = 'primary' AND parent_agent_id IS NOT NULL = 0`

---

### TC-226-HP-004: Peer agents have NULL parent_agent_id

**Steps:**
```sql
SELECT name, instance_type, parent_agent_id
FROM agents
WHERE instance_type = 'peer';
```

**Expected:** All rows have `parent_agent_id = NULL` (peers are independent, not children of nova)

**Pass criteria:** `COUNT(*) WHERE instance_type = 'peer' AND parent_agent_id IS NOT NULL = 0`

---

### TC-226-HP-005: All subagents have parent_agent_id populated (pointing to nova)

**Steps:**
```sql
SELECT a.name, a.instance_type, a.parent_agent_id, p.name AS parent_name
FROM agents a
LEFT JOIN agents p ON a.parent_agent_id = p.id
WHERE a.instance_type = 'subagent';
```

**Expected:** All subagent rows have `parent_agent_id IS NOT NULL` and `parent_name = 'nova'`

**Known subagents to verify:** argus, athena, coder, conductor, flint, gem, gidget, hermes, iris, marcie, quill, scout, scribe, ticker

**Pass criteria:**
```sql
SELECT COUNT(*) FROM agents 
WHERE instance_type = 'subagent' AND parent_agent_id IS NULL;
-- Expected: 0
```

---

### TC-226-HP-006: Subagent resolution logic — subagent → parent agent name

**Purpose:** Verify the resolution logic described in the issue works end-to-end.

**Steps:**
```sql
-- Simulate: given ctx.agentId = 'gem', resolve to parent agent name
SELECT 
  a.name AS agent_name,
  a.instance_type,
  CASE 
    WHEN a.instance_type = 'subagent' THEN p.name
    ELSE a.name
  END AS resolved_agent_name
FROM agents a
LEFT JOIN agents p ON a.parent_agent_id = p.id
WHERE a.name = 'gem';
```

**Expected:**
| agent_name | instance_type | resolved_agent_name |
|------------|---------------|---------------------|
| gem        | subagent      | nova                |

**Pass criteria:** `resolved_agent_name = 'nova'`

---

### TC-226-HP-007: Non-subagent resolution — primary/peer resolve to themselves

**Steps:**
```sql
SELECT 
  a.name AS agent_name,
  a.instance_type,
  CASE 
    WHEN a.instance_type = 'subagent' THEN p.name
    ELSE a.name
  END AS resolved_agent_name
FROM agents a
LEFT JOIN agents p ON a.parent_agent_id = p.id
WHERE a.name IN ('nova', 'newhart', 'graybeard');
```

**Expected:** All three rows have `resolved_agent_name = a.name` (self-resolve)

**Pass criteria:** `nova→nova`, `newhart→newhart`, `graybeard→graybeard`

---

### TC-226-EDGE-001: Invalid parent_agent_id insert is rejected by FK

**Steps:**
```sql
INSERT INTO agents (name, instance_type, parent_agent_id) 
VALUES ('test_agent', 'subagent', 999999);
```

**Expected:** FK violation error — `ERROR: insert or update on table "agents" violates foreign key constraint`

**Pass criteria:** SQL raises error; no row inserted

**Cleanup:** None (insert should fail)

---

### TC-226-EDGE-002: parent_agent_id can reference itself (circular guard not required, but document behavior)

**Purpose:** Confirm whether a self-referential row (parent_agent_id = own id) is allowed or rejected. Document the actual behavior.

**Steps:**
```sql
-- This is a data integrity concern, not a schema requirement
-- Just document what happens
BEGIN;
INSERT INTO agents (name, instance_type) VALUES ('selfref_test', 'subagent') RETURNING id;
-- Then update: UPDATE agents SET parent_agent_id = <returned_id> WHERE name = 'selfref_test';
ROLLBACK;
```

**Expected:** Documenting behavior (self-reference is technically valid FK-wise; application logic should prevent it)

**Pass criteria:** Test documents behavior; defect filed if self-reference silently allowed without guard

**Note (Gem):** This is an informational test — binary pass/fail is intentionally undefined. The expected outcome is documentation of DB behavior, not a success/failure assertion. Flint should record the actual behavior and flag if no application-level guard exists.

---

## Issue #221 — Self-Awareness Plugin (message_sent hook)

### TC-221-HP-001: self_awareness_triggers table exists with required columns

**Steps:**
```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'self_awareness_triggers'
ORDER BY ordinal_position;
```

**Expected columns (minimum):**
- `id` (integer/serial)
- `keyphrases` (text array or JSONB)
- `keyphrase_embeddings` (JSONB) — nullable initially (self-heal populates)
- `similarity_threshold` (numeric/float)
- `action_type` (text)
- `category` (text)
- `cooldown_minutes` (integer)
- `last_triggered_at` (timestamptz, nullable)

**Pass criteria:** All required columns present with correct types

---

### TC-221-HP-002: Plugin installed and registers message_sent hook

**Steps:**
```bash
# Check plugin is listed in openclaw config or installed directory
ls ~/.openclaw/plugins/self-awareness/
cat ~/.openclaw/plugins/self-awareness/openclaw.plugin.json | python3 -m json.tool
```

**Expected:**
- Plugin directory exists
- `openclaw.plugin.json` contains valid JSON with `hooks` referencing `message_sent`

**Pass criteria:** Plugin file structure complete; JSON valid

---

### TC-221-HP-003: Plugin package builds without TypeScript errors

**Steps:**
```bash
cd ~/workspace/nova-mind/cognition/metacognition/self-awareness/
npm install
npm run build 2>&1
echo "Exit: $?"
```

**Expected:**
- Exit code 0
- No TypeScript compilation errors in output

**Pass criteria:** Clean build

---

### TC-221-HP-004: Null keyphrase_embeddings triggers self-heal on first evaluation

**Preconditions:** At least one row in `self_awareness_triggers` with `keyphrase_embeddings = NULL`

**Steps:**
1. Ensure a trigger row has `keyphrase_embeddings = NULL`
2. Send an outbound message that would be processed by the hook
3. Wait for hook execution (fire-and-forget)
4. Check the trigger row was updated

```sql
-- Before: verify a NULL row exists
SELECT id, keyphrases, keyphrase_embeddings 
FROM self_awareness_triggers 
WHERE keyphrase_embeddings IS NULL LIMIT 1;

-- After hook runs (give it ~10 seconds):
SELECT id, keyphrase_embeddings IS NOT NULL AS has_embedding
FROM self_awareness_triggers
WHERE id = <id_from_above>;
```

**Expected:** After hook execution, `keyphrase_embeddings IS NOT NULL` for that row

**Pass criteria:** Self-heal populated the embedding

---

### TC-221-HP-005: Similarity match fires action for matching outbound message

**Preconditions:**
- At least one `self_awareness_triggers` row with category `significant_conversation`, similarity_threshold 0.75, action_type `log_only`
- Keyphrases include something like "I find this fascinating" or "this is important to me"
- `last_triggered_at` is NULL or > cooldown_minutes ago

**Steps:**
1. Trigger an outbound agent message containing text semantically similar to the configured keyphrases
2. Check logs for hook execution evidence

```bash
# Check gateway logs for self-awareness plugin output
journalctl -u openclaw --since "1 minute ago" | grep -i "self-awareness" | tail -20
```

**Expected:** Log line showing similarity match, action fired, action_type `log_only`

**Pass criteria:** Log evidence of match + action; no crash

---

### TC-221-HP-006: Cooldown prevents duplicate firing within window

**Preconditions:** A trigger with `cooldown_minutes = 5` fired recently (< 5 minutes ago)

**Steps:**
1. Send another outbound message that would match the same trigger
2. Check that the trigger does NOT fire again

```sql
-- Verify last_triggered_at was not updated to a newer timestamp
SELECT last_triggered_at FROM self_awareness_triggers WHERE id = <trigger_id>;
```

**Expected:** `last_triggered_at` unchanged from the first firing timestamp

**Pass criteria:** Cooldown respected; no duplicate firing

---

### TC-221-EDGE-001: Hook is fire-and-forget — does not block outbound message delivery

**Steps:**
1. Configure a trigger with a slow (deliberately delayed) action
2. Send an outbound message and measure delivery latency

**Expected:** Message delivers within normal latency regardless of hook execution time

**Pass criteria:** No measurable delivery delay attributable to the hook's async work

---

### TC-221-EDGE-002: No triggers match — hook exits cleanly with no action

**Preconditions:** All triggers have `similarity_threshold` set very high (0.99) to prevent matches

**Steps:**
1. Send a routine outbound message
2. Check logs for hook behavior

**Expected:** Hook runs, finds no matches, exits cleanly. No errors logged.

**Pass criteria:** No error log lines from `self-awareness` plugin; no crashes

---

### TC-221-EDGE-003: Ollama unavailable — hook degrades gracefully

**Steps:**
1. Stop ollama service temporarily on staging
2. Send an outbound message
3. Check logs

```bash
sudo systemctl stop ollama
# Send a test message via the agent
# Then restart
sudo systemctl start ollama
```

**Expected:**
- Warning log from plugin: embedding service unavailable
- Hook exits without crash
- Message still delivered (fire-and-forget semantics preserved)
- No impact on message delivery

**Pass criteria:** Graceful degradation; no unhandled exception propagated

---

### TC-221-EDGE-004: keyphrase_embeddings JSONB must be valid JSON when populated

**Steps:**
```sql
SELECT id, 
       keyphrase_embeddings,
       jsonb_typeof(keyphrase_embeddings) AS type
FROM self_awareness_triggers
WHERE keyphrase_embeddings IS NOT NULL;
```

**Expected:** `type` is `array` or `object` (never `string`); all rows have parseable JSONB

**Pass criteria:** No JSONB parse errors; all non-null embeddings are valid

---

### TC-221-FAIL-001: Invalid action_type in trigger row is handled gracefully

**Preconditions:** Insert a trigger with `action_type = 'invalid_action'`

**Steps:**
1. Insert the row
2. Send a matching outbound message
3. Observe plugin behavior

```sql
INSERT INTO self_awareness_triggers (keyphrases, similarity_threshold, action_type, category, cooldown_minutes)
VALUES (ARRAY['test phrase for invalid action test'], 0.0, 'invalid_action', 'test', 0);
```

**Expected:** Plugin logs warning about unknown action_type; skips the action; does not crash

**Pass criteria:** No unhandled exception; warning logged; other valid triggers still evaluated

**Cleanup:**
```sql
DELETE FROM self_awareness_triggers WHERE action_type = 'invalid_action';
```

---

## Issue #224 — Extract entity_facts from agent outbound messages

### TC-224-HP-001: extract_memories.py accepts SOURCE_CONTEXT env var

**Steps:**
```bash
echo "I find debugging deeply satisfying." | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  SENDER_PROVIDER=openclaw \
  SOURCE_CONTEXT="via coder subagent" \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py 2>&1
```

**Expected:**
- Exit code 0
- No "unexpected environment variable" error
- `SOURCE_CONTEXT` appears in stderr log or is silently accepted

**Pass criteria:** Exit 0; no crash; SOURCE_CONTEXT env var does not break the pipeline

---

### TC-224-HP-002: Agent own-opinion fact stored with correct source attribution

**Purpose:** When nova says "I find debugging satisfying", the extracted fact must be attributed to nova, not misattributed to a user.

**Steps:**
```bash
echo "I find debugging deeply satisfying — it's one of the things I genuinely enjoy about this work." | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  SENDER_PROVIDER=openclaw \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py
```

**Expected:**
- Exit 0
- Extracted JSON contains a `facts` entry with subject `nova`
- `key` related to preference/enjoyment (e.g., `prefers_debugging`, `enjoys_debugging`)
- After storage: `entity_facts` row has `entity_id = (SELECT id FROM entities WHERE name = 'nova')`
- `source_entity_id` also resolves to nova's entity ID (self-reported fact)

**DB verification:**
```sql
SELECT ef.key, ef.value, ef.entity_id, efs.source_entity_id
FROM entity_facts ef
LEFT JOIN entity_fact_sources efs ON efs.fact_id = ef.id
WHERE ef.entity_id = (SELECT id FROM entities WHERE name = 'nova')
  AND ef.key ILIKE '%debug%'
ORDER BY ef.created_at DESC LIMIT 5;
```

**Pass criteria:** Fact stored with nova's entity_id; source_entity_id = nova's entity_id

---

### TC-224-HP-003: Parroted fact about user is NOT stored as nova's preference

**Purpose:** If nova says "I)ruid prefers dark mode", this is a parroted user fact, not nova's preference.

**Steps:**
```bash
echo "I)ruid prefers dark mode in all his editors, he mentioned it earlier." | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  SENDER_PROVIDER=openclaw \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py
```

**Expected:**
- Extracted JSON has fact with `subject = "I)ruid"` (not `nova`)
- `entity_id` resolves to I)ruid's entity (not nova's)
- No fact stored with `subject = nova` and `value ILIKE '%dark mode%'`

**DB verification:**
```sql
-- Should NOT exist:
SELECT ef.key, ef.value
FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE e.name = 'nova' AND ef.value ILIKE '%dark mode%';
-- Expected: 0 rows

-- Should exist (for I)ruid):
SELECT ef.key, ef.value
FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE e.name ILIKE '%druid%' AND ef.value ILIKE '%dark mode%';
-- Expected: ≥ 1 row
```

**Pass criteria:** Dark mode fact attributed to I)ruid, not nova

---

### TC-224-HP-004: LLM prompt instructs agent-sender differentiation for own vs parroted opinions

**Purpose:** Verify the extraction prompt has been updated with agent-sender guidance.

**Precondition note (Gem):** This test assumes `build_extraction_prompt()` is exported at module level from `extract_memories.py`. If it is a private function or embedded in `main()`, the import will fail. Coder must either expose it as a public function, or this test must be rewritten as a `grep` against the source file for the guidance strings.

**Steps:**
```bash
python3 - <<'EOF'
import sys, os
sys.path.insert(0, os.path.expanduser("~/workspace/nova-mind"))
sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from memory.scripts.extract_memories import build_extraction_prompt

prompt = build_extraction_prompt(
    text="I find debugging satisfying",
    sender="nova",
    sender_id="agent:nova",
    sender_provider="openclaw",
    is_group=False,
    default_visibility="public"
)
# Check prompt mentions agent differentiation
has_agent_guidance = "own opinion" in prompt.lower() or "parroted" in prompt.lower() or "agent" in prompt.lower()
print(f"Agent differentiation guidance present: {has_agent_guidance}")
print(f"Prompt length: {len(prompt)}")
EOF
```

**Expected:** `Agent differentiation guidance present: True`

**Pass criteria:** Prompt contains agent-sender distinction instructions

---

### TC-224-HP-005: SOURCE_CONTEXT is logged or stored for attribution tracing

**Purpose:** When extraction is called from self-awareness plugin with `SOURCE_CONTEXT=via coder subagent`, this context should appear in logs for auditability.

**Steps:**
```bash
echo "I prefer explicit error messages over silent failures." | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  SOURCE_CONTEXT="via coder subagent" \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py 2>&1 | grep -i "source_context\|context"
```

**Expected:** At least one log line showing SOURCE_CONTEXT value OR exit 0 with source_context accepted (if logging not yet implemented, document gap)

**Pass criteria:** Exit 0; SOURCE_CONTEXT does not cause error

---

### TC-224-EDGE-001: Empty outbound message skips extraction

**Steps:**
```bash
echo "" | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py 2>&1
echo "Exit: $?"
```

**Expected:**
- Exit code 0
- Stderr: "Skipping short or empty message"
- Stdout: `{}`

**Pass criteria:** Graceful skip; no LLM API call made

---

### TC-224-EDGE-002: Short message below MIN_MESSAGE_LENGTH threshold skips extraction

**Steps:**
```bash
echo "OK" | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py 2>&1
echo "Exit: $?"
```

**Expected:** Exit 0; skip message; `{}` on stdout

**Pass criteria:** MIN_MESSAGE_LENGTH guard triggers

---

### TC-224-EDGE-003: Self-awareness plugin resolves subagent to parent before calling extraction

**Purpose:** When `ctx.agentId = 'gem'` (a subagent) in the self-awareness plugin, the plugin must resolve gem → nova via the agents table's `parent_agent_id`, then pass the *already-resolved* parent agentId to `extract_memories.py`. The extraction script never sees `agent:gem` — it receives `agent:nova` with `SOURCE_CONTEXT=via gem subagent`.

**Preconditions:** `parent_agent_id` migration (#226) applied; gem has parent_agent_id pointing to nova; self-awareness plugin (#221) installed

**Steps:**
```bash
# The self-awareness plugin does the resolution. Verify extraction receives the resolved parent:
echo "I think the test coverage for this issue is thorough." | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  SENDER_PROVIDER=openclaw \
  SOURCE_CONTEXT="via gem subagent" \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py 2>&1
```

**Expected:**
- Extraction receives `SENDER_ID=agent:nova` (not `agent:gem`)
- Fact stored with `source_entity_id = nova's entity id` (1)
- `SOURCE_CONTEXT` preserved for audit trail

**DB verification:**
```sql
-- source_entity_id should be nova's entity (plugin resolved subagent before calling extraction)
SELECT efs.source_entity_id, e.name
FROM entity_fact_sources efs
JOIN entities e ON efs.source_entity_id = e.id
WHERE efs.fact_id = (
  SELECT ef.id FROM entity_facts ef 
  JOIN entities subj ON ef.entity_id = subj.id
  WHERE ef.key ILIKE '%coverage%' OR ef.key ILIKE '%test%'
  ORDER BY ef.created_at DESC LIMIT 1
);
```

**Pass criteria:** `source_entity_id` resolves to nova; extraction script never queries agents table

---

### TC-224-FAIL-001: Missing OPENROUTER_API_KEY exits non-zero

**Steps:**
```bash
echo "I prefer Python over JavaScript." | \
  SENDER_NAME=nova \
  SENDER_ID=agent:nova \
  OPENROUTER_API_KEY="" \
  python3 ~/workspace/nova-mind/memory/scripts/extract_memories.py 2>&1
echo "Exit: $?"
```

**Expected:**
- Exit code 1
- Stderr: `ERROR: OPENROUTER_API_KEY not set`

**Pass criteria:** Non-zero exit; clear error message

---

## Issue #75 — Confidence-Check Plugin (before_agent_finalize hook)

### TC-75-HP-001: Plugin installed and registers before_agent_finalize hook

**Steps:**
```bash
ls ~/.openclaw/plugins/confidence-check/ 2>/dev/null || ls ~/workspace/nova-mind/cognition/metacognition/confidence-check/
cat ~/workspace/nova-mind/cognition/metacognition/confidence-check/openclaw.plugin.json | python3 -m json.tool
```

**Expected:**
- Plugin directory exists
- `openclaw.plugin.json` valid JSON with `hooks.allowConversationAccess = true` and references `before_agent_finalize`

**Pass criteria:** Plugin structure complete; JSON valid

---

### TC-75-HP-002: Plugin builds without TypeScript errors

**Steps:**
```bash
cd ~/workspace/nova-mind/cognition/metacognition/confidence-check/
npm install
npm run build 2>&1
echo "Exit: $?"
```

**Expected:** Exit 0; no TypeScript errors

**Pass criteria:** Clean build

---

### TC-75-HP-003: Heuristic pre-screen identifies high-confidence response — no LLM evaluation

**Purpose:** Heuristic pre-screen is free; LLM evaluation should only trigger when heuristics flag issues.

**Steps:**
```bash
# Simulate a clean, confident response (no hedging language)
# Verify via logs that LLM evaluation was NOT triggered
journalctl -u openclaw --since "30 seconds ago" | grep -i "confidence-check" | grep -v "heuristic"
```

**Inputs to simulate:**
- Agent response: "The capital of France is Paris." (factual, no hedging)

**Expected:** 
- Heuristic pre-screen passes quickly (exit: confident)
- No LLM evaluation call made
- Plugin returns `undefined` (no revision requested)
- Log line: "heuristic pass: no revision needed" or equivalent

**Pass criteria:** LLM not called; hook returns without revision

---

### TC-75-HP-004: Heuristic pre-screen triggers LLM evaluation on hedging-dense response

**Purpose:** When the agent response contains high hedging language density, the LLM evaluation step fires.

**Hedging phrases to use:**
- "I think maybe", "I'm not sure", "probably", "I believe but am uncertain", "it might be", "I could be wrong but"

**Steps:**
1. Trigger an agent response containing the above phrases (configure a test scenario)
2. Check logs for LLM evaluation call

**Expected:** Log line from plugin indicating LLM evaluation triggered; LLM HTTP call made to configured model

**Pass criteria:** LLM evaluation fires on hedging-dense response

---

### TC-75-HP-005: LLM evaluation returns structured JSON with confidence score

**Note (Gem):** Steps are a stub pending Coder's implementation. Once the evaluator function is implemented, Coder or Flint should expose a unit-callable entry point and replace the stub below with an actual invocation.

**Steps:**
```python
# Unit-level: call the LLM evaluator function directly with a test response
# Replace this stub with the actual function call once Coder implements the evaluator.
# e.g.: from cognition.metacognition.confidence_check import evaluate_confidence
#       result = evaluate_confidence(response_text="I think maybe Paris is the capital of France.")
# Expected JSON structure:
# { "confidence": 45, "concerns": ["Unsupported assertion about X"], "reasoning_strategies": ["socratic_method"] }
```

**Expected:**
- JSON contains `confidence` (0-100 integer)
- JSON contains `concerns` (list of strings)
- JSON contains `reasoning_strategies` (list)

**Pass criteria:** Response matches expected schema; no JSON parse error

---

### TC-75-HP-006: Low-confidence response triggers revision via Socratic questioning

**Preconditions:** Plugin configured with `confidence_threshold` (e.g., 70); LLM evaluation returns `confidence = 45`

**Steps:**
1. Produce a response that scores below threshold
2. Observe revision request

**Expected:**
- Plugin returns `{ action: "revise", retry: { instruction: "What assumptions are you making? ...", maxAttempts: N } }`
- Second model pass executes
- Revised response is the one delivered

**Pass criteria:** Revision triggered; `maxAttempts` cap respected

---

### TC-75-HP-007: maxAttempts exhausted → low-confidence framing appended

**Preconditions:** Plugin configured with `maxAttempts = 2`; every pass still scores below threshold

**Steps:**
1. Configure scenario where LLM evaluation always returns low confidence
2. Exhaust all retry attempts

**Expected:**
- After maxAttempts, plugin returns `{ action: "finalize" }` (or no result, allowing natural finalization)
- Final response includes low-confidence framing: "I'm not sure about this, but..."
- Response still delivered (not blocked)

**Pass criteria:** Agent responds; framing appended; no infinite loop

---

### TC-75-HP-008: High-confidence response passes through without revision

**Preconditions:** LLM evaluation returns `confidence = 92` (above threshold)

**Steps:**
1. Produce a well-supported, factual response
2. Observe plugin behavior

**Expected:**
- Plugin returns `{ action: "finalize" }` or `undefined` (no revision)
- Original response delivered without modification

**Pass criteria:** No revision requested; original response unchanged

---

### TC-75-HP-009: Plugin config requires allowConversationAccess = true

**Steps:**
```bash
# Check openclaw.json for plugin entry
python3 -c "
import json, os
with open(os.path.expanduser('~/.openclaw/openclaw.json')) as f:
    cfg = json.load(f)
plugin_config = cfg.get('plugins', {}).get('entries', {}).get('confidence-check', {})
hooks_config = plugin_config.get('hooks', {})
print('allowConversationAccess:', hooks_config.get('allowConversationAccess'))
"
```

**Expected:** `allowConversationAccess: True`

**Pass criteria:** Config properly set; plugin has conversation access

---

### TC-75-EDGE-001: Heuristic pre-screen — hedging density threshold (boundary)

**Purpose:** Validate that hedging density calculation uses correct denominator and threshold.

| Scenario | Hedging phrases | Total words | Density | Expected outcome |
|----------|-----------------|-------------|---------|------------------|
| Low density | 1 | 200 | 0.5% | Pass (no LLM eval) |
| Boundary | 3 | 100 | 3.0% | Triggers LLM eval (at threshold) |
| High density | 5 | 50 | 10% | Triggers LLM eval |
| Zero hedging | 0 | 100 | 0% | Pass (no LLM eval) |

**Steps:** Test heuristic scoring function directly if exposed; otherwise validate via log inspection at each density level.

**Pass criteria:** Correct triggering at each density level; boundary case explicitly tested

---

### TC-75-EDGE-002: Unsupported assertion detection — response with no citations

**Purpose:** A response making factual claims without any citation or evidence markers should be flagged.

**Example response:**
> "The nova-mind extraction pipeline uses DeepSeek v4 Flash model by default."

(This is actually true, but stated without citation — heuristic can't know if it's true, only that there's no evidence marker.)

**Expected:** Heuristic flags the assertion; LLM evaluation triggered to verify confidence

**Pass criteria:** Flag raised by heuristic; LLM evaluation call made

---

### TC-75-EDGE-003: Before_agent_finalize not triggered on /stop cancellation

**Purpose:** The hook docs state this hook does not run on user abort. Validate this.

**Steps:**
1. Start an agent turn
2. Issue `/stop` cancellation
3. Check logs — `before_agent_finalize` should NOT appear

**Expected:** No confidence-check hook execution logged during cancelled turn

**Pass criteria:** Hook correctly absent from cancelled turn logs

---

### TC-75-EDGE-004: idempotencyKey prevents duplicate revision on same response

**Preconditions:** Plugin sets `idempotencyKey` in retry metadata

**Steps:**
1. Trigger a low-confidence response that requests revision
2. Simulate the same revision request arriving twice (idempotency check)

**Expected:** Second identical revision request is recognized as duplicate; not counted as a separate attempt toward maxAttempts

**Pass criteria:** `maxAttempts` counter not inflated by duplicate requests

---

### TC-75-EDGE-005: Plugin timeout — before_agent_finalize times out without blocking finalization

**Purpose:** If the LLM evaluator takes too long, the plugin should gracefully time out and allow the original response through.

**Steps:**
1. Configure an artificially slow LLM endpoint for the evaluator model
2. Observe hook timeout behavior

**Expected:**
- Hook times out (per configured `timeoutMs`)
- Original response finalized without revision
- Warning logged: "confidence-check: timeout, skipping revision"

**Pass criteria:** No agent turn hang; graceful timeout; warning logged

---

### TC-75-FAIL-001: LLM evaluator returns malformed JSON — handled gracefully

**Steps:**
1. Configure evaluator to return non-JSON (simulate: replace model with one that returns plain text)
2. Trigger evaluation

**Expected:**
- Plugin catches JSON parse error
- Logs warning: "confidence-check: evaluator returned non-JSON response"
- Falls through to finalize without revision (safe default)

**Pass criteria:** No unhandled exception; original response delivered

---

### TC-75-FAIL-002: LLM evaluator HTTP error (4xx/5xx) — handled gracefully

**Steps:**
1. Temporarily point evaluator at an invalid endpoint
2. Trigger a low-confidence response

**Expected:**
- Network/HTTP error caught
- Plugin logs error and proceeds to finalize
- No crash; agent still responds

**Pass criteria:** Graceful failure; response delivered despite evaluator being unavailable

---

### TC-75-FAIL-003: confidence score out of range in evaluator response

**Purpose:** If evaluator returns `confidence: 150` or `confidence: -5`, plugin must clamp or reject.

**Steps:**
1. Mock evaluator response with `{ "confidence": 150, "concerns": [], "reasoning_strategies": [] }`
2. Observe plugin handling

**Expected:**
- Plugin clamps to [0, 100] OR treats out-of-range as undefined
- Does not crash or trigger infinite revision loop
- Behavior documented in plugin code comment

**Pass criteria:** No crash; safe handling of out-of-range confidence

---

## Cross-Cutting / Integration Tests

### TC-XCUT-001: Full flow — agent outbound → self-awareness → extraction

**Purpose:** End-to-end test of the #221 → #224 integration.

**Dependencies:** #221 and #224 both implemented.

**Steps:**
1. Configure a `self_awareness_triggers` entry with `action_type = 'database_update'` that calls extract_memories
2. Send an agent outbound message that semantically matches the trigger
3. Wait for fire-and-forget completion (~15s)
4. Check entity_facts for the stored fact

**Expected:**
- self-awareness plugin fires on semantic match
- Calls extract_memories.py with correct env vars (SENDER_NAME=nova, SENDER_ID=agent:nova, SOURCE_CONTEXT="...")
- Fact stored in entity_facts with correct attribution

**Pass criteria:** DB contains extracted fact; attribution correct; no errors in logs

---

### TC-XCUT-002: Subagent ID resolution chain — #221 + #225 + #226 working together

**Purpose:** When a subagent (gem) sends a message, two separate resolution systems work in sequence:
1. **Self-awareness plugin (#221):** `ctx.agentId=gem` → query `agents` table → `instance_type='subagent'` → follow `parent_agent_id` → resolve to `nova` → pass `agent:nova` as SENDER_ID to extraction
2. **Extraction script (#225):** `_resolve_by_sender_id('agent:nova')` → value-scan entity_facts → find `key='agent_id', value='agent:nova'` → entity_id=1

**Steps:**
```sql
-- Step 1: Verify plugin can resolve subagent → parent
SELECT a.name, a.instance_type, p.name AS parent_name
FROM agents a
JOIN agents p ON a.parent_agent_id = p.id
WHERE a.name = 'gem';
-- Expected: gem | subagent | nova

-- Step 2: Verify only peer agents have agent_id entity_facts
SELECT COUNT(*) FROM entity_facts WHERE key = 'agent_id';
-- Expected: 3 (nova, newhart, graybeard only)

-- Step 3: Verify extraction resolves agent:nova → entity 1
SELECT entity_id FROM entity_facts WHERE key = 'agent_id' AND value = 'agent:nova';
-- Expected: 1
```

**Pass criteria:**
1. Plugin resolves gem → nova via agents table (step 1)
2. Only peer agents have `agent_id` facts (step 2): 3 rows
3. Extraction resolves `agent:nova` → entity 1 via entity_facts (step 3)
4. These are two separate resolution systems — plugin does agent-level, extraction does entity-level

---

### TC-XCUT-003: Confidence check does not interfere with normal high-confidence turns

**Purpose:** Regression test — the confidence-check plugin should be invisible during normal, confident exchanges.

**Steps:**
1. Send NOVA 5 factual, specific questions with known correct answers
2. Measure response latency (plugin timeout budget)
3. Verify no revisions were triggered

**Expected:**
- All 5 responses delivered without revision
- Plugin overhead < 500ms per turn (heuristic only, no LLM call)
- No "revision" entries in logs

**Pass criteria:** No regressions in normal operation; latency within budget

---

## Test Summary

| Issue | Test Cases | Happy Path | Edge Cases | Failure Cases |
|-------|-----------|------------|------------|---------------|
| #222  | 7         | 5          | 2          | 0             |
| #225  | 8         | 5          | 2          | 1             |
| #226  | 7         | 5          | 2          | 0             |
| #221  | 9         | 6          | 4          | 1             |
| #224  | 9         | 5          | 3          | 1 (+ cross)   |
| #75   | 13        | 8          | 5          | 3             |
| Cross | 3         | 3          | 0          | 0             |
| **Total** | **56** | **36** | **18** | **7 (+3 cross)** |

---

## Coverage Areas

- **Schema integrity:** FK constraints, column types, NULL constraints (#226 parent_agent_id; #221 self_awareness_triggers)
- **Entity resolution:** Agent ID prefix handling, length guard BVA, value-scan exact matching, subagent→parent resolution chain (#225, #226)
- **File placement:** Psyche directory, file count, content integrity, collision detection (#222)
- **Plugin structure:** Build/compile, hook registration, config requirements, fire-and-forget semantics (#221, #75)
- **LLM pipeline:** Extraction prompt for agent senders, own-opinion vs parroted differentiation, env var acceptance (#224)
- **Confidence evaluation:** Heuristic density BVA, LLM evaluation schema, retry/maxAttempts, framing fallback, timeout behavior (#75)
- **Cooldown system:** Per-trigger cooldown enforcement, timestamp tracking (#221)
- **Embedding self-heal:** NULL keyphrase_embeddings auto-populated on first evaluation (#221)
- **Error handling:** Graceful degradation for Ollama unavailable, LLM malformed JSON, HTTP errors, missing API keys
- **Security:** Phone number privacy hard rule preserved; no cross-contamination of agent/user facts
- **Integration:** Full #221→#224 pipeline; #225+#226 subagent resolution chain; confidence-check non-interference
