# Test Cases: SE Run #60 — Issues #150, #140, #168
**Issues:**
- #150 — Selective semantic recall + prompt preprocessing / domain routing
- #140 — Tiered recall strategy
- #168 — Visibility filter in semantic-recall hook

**Branch:** `feature/se-run-60-selective-recall-domain-routing` (or equivalent)
**Plugin:** `memory/plugins/turn-context/src/`
**Recall script:** `~/.openclaw/scripts/proactive-recall.py`

---

## Overview

This batch extends the `turn-context` plugin with five major capabilities:

1. **Message Type Classifier** (`classifier.ts`) — rule-based + Ollama LLM fallback
2. **Domain Identifier** (`domain-identifier.ts`) — embedding similarity + keyword matching against `agent_domains`
3. **Prompt Helper Config** (`prompt_helper_config` table) — message_type → subsystem dispatch gating
4. **Tiered Recall** (refactored `semantic-recall.ts`) — gate subsystems by message type; domain-scoped search first
5. **Visibility Filtering** (`proactive-recall.py`) — filter `entity_facts` by `visibility` for group vs DM

Plus one bug fix:
- **Entity Resolver Cache Bugfix** (`entity-resolver.ts`) — cache key changed from `sessionKey` → `sessionKey+senderId`

---

## Test Area 1: Message Type Classifier

### TC-001: Rule-based classification — info_request (question mark)
**File:** `classifier.ts`
**Preconditions:** Classifier initialised; no Ollama call expected
**Input:** `content = "What time is it in Tokyo?"`
**Expected:**
- Returns `{ type: "info_request" }` without invoking Ollama
- Ollama call count: 0
- Rule matched: question-mark heuristic or interrogative word detection

### TC-002: Rule-based classification — info_request (interrogative word)
**Input:** `content = "Who owns this repository?"`
**Expected:**
- Returns `{ type: "info_request" }`
- No Ollama call

### TC-003: Rule-based classification — action (imperative verb)
**Input:** `content = "Search GitHub for open PRs tagged bug"`
**Expected:**
- Returns `{ type: "action" }`
- No Ollama call

### TC-004: Rule-based classification — action (explicit verb words)
**Input:** `content = "Create a new task for fixing the DB migration"`
**Expected:**
- Returns `{ type: "action" }`
- No Ollama call

### TC-005: Rule-based classification — command (slash prefix)
**Input:** `content = "/status"`
**Expected:**
- Returns `{ type: "command" }`
- No Ollama call

### TC-006: Rule-based classification — command (bang prefix)
**Input:** `content = "!help"`
**Expected:**
- Returns `{ type: "command" }`
- No Ollama call

### TC-007: Rule-based classification — continuation (very short message)
**Input:** `content = "ok"` (≤ 5 chars, single word)
**Expected:**
- Returns `{ type: "continuation" }`
- No Ollama call

### TC-008: Rule-based classification — continuation (affirmation words)
**Input:** `content = "got it"` or `"sure"` or `"yep"`
**Expected:**
- Returns `{ type: "continuation" }`
- No Ollama call

### TC-009: Rule-based classification — conversation (greeting)
**Input:** `content = "Hey, how are you doing today?"`
**Expected:**
- Returns `{ type: "conversation" }`
- No Ollama call

### TC-010: Rule-based classification — 60-70% coverage threshold
**Preconditions:** Representative sample of 100 varied messages
**Steps:**
1. Feed 100 messages through classifier (mix of all types)
2. Count Ollama calls vs rule-matched results
**Expected:**
- At least 60 of 100 resolved by rules alone (Ollama call count ≤ 40)
- This documents the promised 60-70% rule coverage

### TC-011: Ollama fallback — ambiguous message triggers LLM
**Preconditions:** Ollama running and accessible; mock Ollama to record calls
**Input:** `content = "Tell me about the situation"` (ambiguous — could be info_request or conversation)
**Expected:**
- Rule-based pass does NOT classify with certainty
- Ollama is called with the message text
- Returns one of the valid types: `info_request | action | conversation | continuation | command`
- Response includes the type from Ollama's classification

### TC-012: Ollama fallback — returns domain hints when available
**Preconditions:** Ollama configured and running
**Input:** `content = "What's the current state of the payments integration?"` (ambiguous domain context)
**Expected:**
- Returns `{ type: "info_request", domainHints: ["payments", "integration"] }` (or similar)
- domainHints is present and non-empty

### TC-013: Ollama down — graceful degradation
**Preconditions:** Ollama service stopped / connection refused
**Input:** `content = "Tell me about that"` (would normally go to Ollama)
**Expected:**
- Classifier does NOT throw
- Returns a fallback classification (e.g., `{ type: "conversation" }`) rather than crashing
- Error is logged at warn/error level
- No unhandled rejection propagates to caller

### TC-014: Ollama timeout — graceful degradation
**Preconditions:** Ollama mock configured to delay > classifier's timeout
**Input:** Any ambiguous message
**Expected:**
- Classifier returns fallback type within the timeout window
- Does not hang indefinitely
- Error logged

### TC-015: Empty content — classification
**Input:** `content = ""`
**Expected:**
- Returns `{ type: "continuation" }` OR a well-defined default type
- Does NOT crash or throw
- No Ollama call for empty input

### TC-016: Very long message (> 2000 chars) — rule-based still applies
**Input:** `content` = 2500 character string that starts with a question
**Expected:**
- Rule-based pattern matching works on the beginning/full string
- Classification succeeds without truncation errors
- If Ollama is called, input is truncated or sampled safely

### TC-017: Message with only whitespace
**Input:** `content = "   \n\t  "`
**Expected:**
- Treated the same as empty content
- Returns safe default type
- No crash

### TC-018: Message with special characters (emoji, unicode)
**Input:** `content = "🔥 What's happening with the build? 🚨"`
**Expected:**
- Classification succeeds
- Emoji/unicode does not break rule matching
- Returns `info_request` (question mark present)

### TC-019: Classifier returns extracted domain hints from rules
**Input:** `content = "Check the GitHub CI status for nova-mind"`
**Expected:**
- type: `action` or `info_request`
- domainHints includes something like `["github", "ci"]` or `["software_engineering"]`
- Domain hints flow downstream to domain-identifier

### TC-020: Classifier output structure validation
**Input:** Any valid message
**Expected:**
- Return type has exactly: `type` (string, one of the 5 valid values) and optional `domainHints` (string array or undefined)
- No extra undocumented fields
- Type value is always one of: `info_request | action | conversation | continuation | command`

### TC-020b: Rule-based classification — single `>` treated as continuation
**Input:** `content = ">"` (exactly one greater-than character, no other text)
**Preconditions:** This is I)ruid's workflow advance signal per GLOBAL/PROCESS_AND_COORDINATION
**Expected:**
- Returns `{ type: "continuation" }` without invoking Ollama
- NOT misclassified as a blockquote marker, comparison operator, or command
- Ollama call count: 0
- Rule matched: single-character message → continuation heuristic
**Note:** This is a documented convention: "When I)ruid responds with a single `>` character, it means proceed to the next step."

---

## Test Area 2: Domain Identifier

### TC-021: Domain match via keyword — exact keyword hit
**Preconditions:** `agent_domains` seeded; domain "github" has keyword `["github", "gh", "pull request", "pr"]`
**Input:** `message = "check the github pr"`, domainHints = []
**Expected:**
- Returns domain match for "github" or equivalent domain
- Matched via keyword, not vector (or both confirm the same domain)
- Includes `agent` from JOIN on `agent_domains` (not hardcoded)

### TC-022: Domain match via vector similarity — semantic match
**Preconditions:** Domain descriptions embedded; `memory_embeddings` populated with domain descriptions
**Input:** `message = "I need to inspect the distributed transaction trace for a slow query"`
**Expected:**
- Returns domain for distributed tracing / observability (e.g., "jaeger" or "tracing" domain)
- Similarity score above threshold
- Match via embedding similarity

### TC-023: Domain match — keyword wins over low-similarity vector
**Preconditions:** A message with a clear keyword match but ambiguous embedding
**Input:** `message = "check slack messages"` (keyword: "slack")
**Expected:**
- Returns Slack domain
- Does not return a different domain with slightly higher vector similarity

### TC-024: NO DOMAIN IDENTIFIED — low similarity, no keyword match
**Input:** `message = "hmm interesting"`
**Expected:**
- Returns `{ domain: "NO DOMAIN IDENTIFIED" }` or equivalent sentinel
- No agent is returned
- No crash

### TC-025: NO DOMAIN IDENTIFIED — threshold boundary (below threshold)
**Preconditions:** Threshold = 0.4 (or configured value); mock embedding returns similarity 0.39
**Input:** Any message
**Expected:**
- Below-threshold similarity → `NO DOMAIN IDENTIFIED`
- NOT a domain match

### TC-026: Domain identified — threshold boundary (at threshold)
**Preconditions:** Mock embedding returns similarity exactly at threshold (e.g., 0.40)
**Input:** Any message
**Expected:**
- At-threshold similarity → domain IS matched (inclusive lower bound)
- Returns the matched domain

### TC-027: Domain identified — above threshold
**Preconditions:** Mock embedding returns similarity 0.85
**Expected:**
- Domain matched confidently
- Included in output

### TC-028: Agent lookup — agent returned via JOIN, not hardcoded
**Preconditions:** `agent_domains` table has domain "discord" with `agent_id` FK pointing to the "iris" row in `agents`
**SQL the domain identifier must use:**
```sql
SELECT ad.domain_topic, a.name AS agent_name
FROM agent_domains ad
JOIN agents a ON ad.agent_id = a.id
WHERE ...
```
**Input:** Message matching discord domain
**Expected:**
- Returned agent name is "iris" (resolved via `agent_domains.agent_id → agents.name` JOIN)
- `agent_domains` does NOT have an `agent_name` column — the JOIN is mandatory
- If the agents table row for iris is renamed, returned value changes without any code change
- No hardcoded agent name strings in `domain-identifier.ts`
- Confirm: `grep -r 'iris\|gidget\|coder\|scout' src/domain-identifier.ts` returns zero hits

### TC-029: Agent_domains — keywords column populated for all 38 domains
**Preconditions:** Migration `080_prompt_helper_config.sql` applied
**Steps:**
```sql
SELECT domain_topic FROM agent_domains WHERE keywords IS NULL OR array_length(keywords, 1) = 0;
```
**Expected:**
- Zero rows returned — all 38 domains have non-empty keywords arrays
- The `keywords` column is TEXT[] and was added by this migration to the pre-existing `agent_domains` table

### TC-030: Agent_domains — notes populated for all 38 domains
**Preconditions:** Migration applied
**Steps:**
```sql
SELECT domain_topic FROM agent_domains WHERE notes IS NULL OR notes = '';
```
**Expected:**
- Zero rows returned — all 38 pre-existing domains have notes populated
- The migration UPDATES existing rows; it does not INSERT new domain rows
- `notes` column existed prior; migration fills in any gaps

### TC-031: Domain descriptions embedded in memory_embeddings
**Preconditions:** Seeding step ran
**Steps:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'agent_domain';
```
**Expected:**
- COUNT = 38 (one embedding per domain)
- Each row has non-null embedding vector
- Dimension matches configured embedding model

### TC-032: 5-minute cache TTL — domain data cached
**Preconditions:** Domain identifier initialised; first call triggers DB query
**Steps:**
1. Call domain identifier → note DB query count = 1
2. Call again immediately → DB query count still 1 (cache hit)
3. Wait 5 minutes + 1 second (or mock time) → call again → DB query count = 2 (cache miss)
**Expected:**
- Cache hit for calls within 5-minute window
- Cache miss after TTL expires
- Refreshed data after TTL

### TC-033: Cache TTL — multiple domains resolved, all cached together
**Preconditions:** Cache loaded with domain data
**Input:** Two sequential messages matching different domains
**Expected:**
- Second message lookup uses cached domain data (no second DB round-trip for domain table)

### TC-034: Domain identifier — empty message
**Input:** `message = ""`
**Expected:**
- Returns `NO DOMAIN IDENTIFIED`
- Does NOT embed empty string
- No crash

### TC-035: Domain identifier — DB unavailable
**Preconditions:** PostgreSQL stopped or connection refused
**Expected:**
- Returns `NO DOMAIN IDENTIFIED` (graceful degradation)
- Logged error at appropriate level
- Does not throw unhandled error

### TC-036: Domain identifier — Ollama embedding service unavailable
**Preconditions:** Ollama embedding endpoint returns 500 or connection refused
**Expected:**
- Returns `NO DOMAIN IDENTIFIED`
- Error logged
- No crash

### TC-037: Domain identifier — multiple keywords match single domain
**Preconditions:** Domain "github" has keywords `["github", "pr", "pull request", "gh"]`
**Input:** `message = "open a PR on github"`
**Expected:**
- Matches "github" domain exactly once (no duplicate matches)
- Single domain returned

### TC-038: Domain identifier — ambiguous multi-domain message
**Input:** `message = "create a github issue and post about it on slack"`
**Expected:**
- Returns the highest-confidence domain match (one result)
- Does not error on ambiguity
- Optionally: returns top-N domains if spec supports it

### TC-038b: Domain identifier — top-ranked multi-domain results returned
**Input:** `message = "create a GitHub issue for the database migration"` (legitimately spans Git Operations, Software Engineering, AND Database domains)
**Expected:**
- Domain identifier returns ranked list of 1-3 matches ordered by descending similarity/confidence
- All returned domains have similarity above threshold
- Caller (tiered recall) uses the top match for domain-scoped search
- Remaining matches may be used as domain context hints in the output
- No crash from multiple matches
- Verify: at minimum, whichever of Git Operations / Software Engineering / Database scores highest is returned first

### TC-039: Domain identifier output structure
**Input:** Any message with a match
**Expected:**
- Output has: `domain` (string), `agent` (string from DB via agents JOIN), `similarity` (float), `matchedBy` (`"keyword" | "vector" | "both"`)
- When NO DOMAIN IDENTIFIED: `domain = "NO DOMAIN IDENTIFIED"`, `agent = null`

### TC-039b: Domain identifier — injected context format in prompt
**Preconditions:** Domain identifier returns a match; result is assembled into prependSystemContext
**Input:** Message matching "Git Operations" domain → agent = "gidget"
**Expected:**
- The string injected into the agent's context includes all of: domain name, assigned agent name
- Example format: `🏷️ Domain: Git Operations → gidget (Version Control)` or equivalent
- The parent domain / category label is included if available (e.g., "Version Control" as parent of "Git Operations")
- Agent name is the resolved string from the agents JOIN, NOT an ID number
- Format is human-readable (agent can act on the domain routing hint)
**Note:** Exact format TBD by implementation; this TC establishes minimum required fields.

### TC-040: Domain seeding — 38 domains confirmed in pre-existing table
**Note:** The `agent_domains` table already contains 38 rows. Migration 080 enriches them (adds keywords, fills notes). It does NOT insert new domain rows.
**Steps:**
```sql
SELECT COUNT(*) FROM agent_domains;
```
**Expected:**
- COUNT = 38 (exact — same as before migration; no rows added or removed)
- Verify: row count is 38 both before AND after applying migration 080

---

## Test Area 3: Prompt Helper Config

### TC-041: Migration creates prompt_helper_config table
**Preconditions:** Migration `080_prompt_helper_config.sql` applied fresh
**Steps:**
```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'prompt_helper_config'
ORDER BY ordinal_position;
```
**Expected columns (minimum):**
- `id` (integer or serial, PK)
- `message_type` (text or enum)
- `helper_name` (text)
- `agent_name` (text, nullable — for overrides, NOT routing)
- `enabled` (boolean)

### TC-042: Default rows — all message types covered
**Steps:**
```sql
SELECT message_type, helper_name, agent_name FROM prompt_helper_config WHERE agent_name IS NULL ORDER BY message_type;
```
**Expected:**
- Rows present for: `info_request`, `action`, `conversation`, `continuation`, `command`
- Default (agent_name=NULL) rows define baseline dispatch for each type

### TC-043: info_request — full recall pipeline enabled
**Steps:**
```sql
SELECT helper_name, enabled FROM prompt_helper_config
WHERE message_type = 'info_request' AND agent_name IS NULL;
```
**Expected:**
- Rows for `semantic_recall`, `domain_identifier`, `entity_resolver` all have `enabled = true`

### TC-044: action — full recall pipeline enabled
**Steps:**
```sql
SELECT helper_name, enabled FROM prompt_helper_config
WHERE message_type = 'action' AND agent_name IS NULL;
```
**Expected:**
- Same helpers enabled as info_request

### TC-045: conversation — entity context only, recall disabled
**Steps:**
```sql
SELECT helper_name, enabled FROM prompt_helper_config
WHERE message_type = 'conversation' AND agent_name IS NULL;
```
**Expected:**
- `entity_resolver`: enabled = true
- `semantic_recall`: enabled = false
- `domain_identifier`: enabled = false (or absent)

### TC-046: continuation — all recall subsystems disabled
**Steps:**
```sql
SELECT helper_name, enabled FROM prompt_helper_config
WHERE message_type = 'continuation' AND agent_name IS NULL;
```
**Expected:**
- `semantic_recall`: enabled = false
- `domain_identifier`: enabled = false
- `entity_resolver`: enabled = false (or present but skipped)

### TC-047: command — all recall subsystems disabled
**Steps:**
```sql
SELECT helper_name, enabled FROM prompt_helper_config
WHERE message_type = 'command' AND agent_name IS NULL;
```
**Expected:**
- Same as continuation: all recall disabled

### TC-047b: Turn reminders fire for ALL message types including continuation and command
**Preconditions:** `getTurnReminders()` configured; DB returns reminders for the agent
**Input:** Messages classified as each of: `continuation`, `command`, `conversation`, `info_request`, `action`
**Expected:**
- `getTurnReminders(agentId)` is called for ALL five message types
- The gating logic (prompt_helper_config / message type checks) applies ONLY to recall/domain/entity subsystems
- Turn reminders are NEVER gated by message type — they always run
- `appendSystemContext` contains `📌 Per-Turn Reminders:` content regardless of message type
- Verify: even a bare `content = ">"` (continuation) still yields appendSystemContext with reminders
**Rationale:** Turn reminders are operational rules the agent must always see. Skipping them for "simple" messages would cause the agent to miss critical per-turn instructions.

### TC-048: Agent-specific override — custom config respected
**Preconditions:** Insert override row:
```sql
INSERT INTO prompt_helper_config (message_type, helper_name, agent_name, enabled)
VALUES ('conversation', 'semantic_recall', 'nova', true);
```
**Input:** Message type = `conversation`, agentId = `nova`
**Expected:**
- Nova's pipeline enables `semantic_recall` for conversation (override wins)
- Other agents still use the default (disabled) for conversation

### TC-049: Agent-specific override — agent_name is NOT routing target
**Preconditions:** Table has agent_name = 'nova' override
**Steps:** Review config loading logic
**Expected:**
- `agent_name` column determines WHOSE dispatch config to use
- Does NOT route the message to that agent
- The field is purely a config-scoping key

### TC-050: prompt_helper_config — invalid message_type rejected by CHECK constraint
**Steps:**
```sql
INSERT INTO prompt_helper_config (message_type, helper_name, enabled)
VALUES ('unknown_type', 'semantic_recall', true);
```
**Expected:**
- Rejected by a CHECK constraint (NOT a PostgreSQL enum type)
- Constraint form:
  ```sql
  CHECK (message_type IN ('info_request', 'action', 'conversation', 'continuation', 'command'))
  ```
- Error message references the constraint name
- Row not inserted
**Note:** Implementation uses CHECK, not `CREATE TYPE ... AS ENUM`. This allows adding new message types via ALTER TABLE without enum migration complexity.

---

## Test Area 4: Tiered Recall — Gating and Tier Selection

### TC-051: continuation → skip recall entirely
**Preconditions:** Classifier output = `{ type: "continuation" }`; prompt_helper_config defaults loaded
**Input:** `content = "ok"` (classified as continuation)
**Expected:**
- `runSemanticRecall()` is NOT called
- `runDomainIdentifier()` is NOT called
- `proactive-recall.py` is NOT spawned
- Log confirms recall skipped: `[turn-context] Skipping recall: message type=continuation`

### TC-052: command → skip recall entirely
**Preconditions:** Classifier output = `{ type: "command" }`
**Input:** `content = "/status"`
**Expected:**
- Same as TC-051: recall and domain identifier not invoked

### TC-053: conversation → entity context only, recall skipped
**Preconditions:** Classifier output = `{ type: "conversation" }`
**Input:** `content = "Hey, how's your day going?"`
**Expected:**
- Entity resolver IS called
- `runSemanticRecall()` is NOT called
- Domain identifier is NOT called
- Log confirms: `[turn-context] recall=skipped(conversation) entity=invoked`

### TC-054: info_request → full recall pipeline runs
**Preconditions:** Classifier output = `{ type: "info_request" }`; domain identified
**Input:** `content = "What does the entity resolver do?"`
**Expected:**
- Entity resolver is called
- Domain identifier is called
- Domain-scoped recall runs first
- Full vector search runs as fallback (or domain results return, fallback skipped)

### TC-055: action → full recall pipeline runs
**Preconditions:** Classifier output = `{ type: "action" }`
**Input:** `content = "Create a GitHub issue for the cache bug"`
**Expected:**
- Full pipeline: entity + domain identifier + recall
- Same as info_request behavior

### TC-056: Domain-scoped search first, results returned — fallback not triggered
**Preconditions:** Domain identified = "github"; domain-scoped DB query returns ≥ 1 result above threshold
**Expected:**
- Domain-scoped SQL executes first (filtered to github domain embeddings)
- Full vector search does NOT run (domain results sufficient)
- Observability log: `tier=domain`

### TC-057: Domain-scoped search returns zero results — full vector search fallback triggers
**Preconditions:** Domain identified = "github"; mock DB returns 0 results for domain-scoped query
**Expected:**
- Domain-scoped query runs first, returns nothing
- Full vector search runs as fallback
- Observability log: `tier=full_fallback`

### TC-058: NO DOMAIN IDENTIFIED — full vector search runs directly (no domain-scoped phase)
**Preconditions:** Domain identifier returns `NO DOMAIN IDENTIFIED`
**Expected:**
- Domain-scoped search is skipped entirely
- Full vector search runs immediately
- Observability log: `tier=full_nodomain`

### TC-059: Tier observability — tier logged in structured format
**Preconditions:** Any recall run
**Expected:**
- Log line includes: `tier=<domain|full_fallback|full_nodomain|skipped>`
- Format is consistent (parseable by log aggregation)
- Tier is emitted even when no memories found

### TC-060: Tiered recall — token budget respected across both tiers
**Preconditions:** info_request message; domain-scoped returns 3 results; full search would return 10 more
**Expected:**
- Total tokens across all tiers ≤ TOKEN_BUDGET (default 1000)
- Domain-scoped results are NOT double-counted if they overlap with full search

### TC-061: Tiered recall — domain-scoped results deduped against full search
**Preconditions:** Domain-scoped search + full search both return same memory ID
**Expected:**
- Memory appears in output exactly once
- No duplicate entries in `memories[]` output

### TC-062: Tiered recall — empty content bypasses all recall
**Preconditions:** `cached?.content` is empty string
**Input:** Before-prompt-build fires with no cached content (cache miss)
**Expected:**
- Recall is skipped (as in current implementation)
- Log: `recall=skipped(no content)` or equivalent

### TC-063: Tiered recall — classifier error falls back to full pipeline
**Preconditions:** Classifier throws an unexpected error
**Expected:**
- Classifier error is caught
- Pipeline defaults to full recall (safe fallback — do not skip recall on classifier failure)
- Error logged; no unhandled rejection

### TC-064: Tiered recall — domain identifier error falls back to full vector search
**Preconditions:** Domain identifier throws (DB down, embedding timeout, etc.)
**Expected:**
- Error caught in domain identifier
- Full vector search runs as fallback
- Tier logged as `full_fallback`

---

## Test Area 5: Visibility Filtering

**Architecture note:** `memory_embeddings` does NOT have a `visibility` column. When `source_type = 'entity_fact'`, the recall script must JOIN back to `entity_facts` to apply the visibility filter. The WHERE clause lives on the JOIN result, not directly on `memory_embeddings`.

The SQL pattern for group-chat filtering must be:
```sql
SELECT m.source_type, m.source_id, m.content, ...
FROM memory_embeddings m
LEFT JOIN entity_facts ef
  ON m.source_type = 'entity_fact' AND m.source_id = ef.id::text
WHERE ...
  AND (
    m.source_type != 'entity_fact'           -- non-entity memories unaffected
    OR ef.visibility = 'public'              -- entity facts: public only (group)
  )
```
For DM (`is_group = false`), the JOIN is still performed but the visibility WHERE clause is omitted.

### TC-065: Group chat — only public entity_facts returned
**Preconditions:** `proactive-recall.py` receives `is_group = true`, `entity_id = 42`
**Setup:**
```sql
-- Insert mixed-visibility facts
INSERT INTO entity_facts (entity_id, key, value, visibility) VALUES
  (42, 'location', 'Austin TX', 'public'),
  (42, 'salary', '150000', 'private'),
  (42, 'nickname', 'Druid', 'public');
```
**Steps:**
```bash
echo '{"content": "who is this person", "entity_id": 42, "is_group": true}' | python proactive-recall.py
```
**Expected:**
- `location` and `nickname` facts included in output
- `salary` (private) NOT included
- Filter applied via JOIN from `memory_embeddings` → `entity_facts` on `source_type = 'entity_fact'`
- No error

### TC-066: DM/private chat — all entity_facts returned (no visibility filter)
**Preconditions:** `is_group = false` (or absent); same entity as TC-065
**Steps:**
```bash
echo '{"content": "who is this person", "entity_id": 42, "is_group": false}' | python proactive-recall.py
```
**Expected:**
- All three facts included: `location`, `salary`, `nickname`
- Visibility JOIN clause omitted from SQL query (or present but unconstrained)
- No `visibility = 'public'` filter in WHERE

### TC-067: is_group absent from payload — treated as DM (no filter)
**Preconditions:** stdin JSON has no `is_group` field
**Steps:**
```bash
echo '{"content": "message text", "entity_id": 42}' | python proactive-recall.py
```
**Expected:**
- Treated as `is_group = false`
- No visibility filtering applied
- All entity_facts for entity 42 eligible for recall

### TC-068: entity_id absent from payload — visibility filter not applied
**Preconditions:** stdin JSON has no `entity_id` field (e.g., unknown sender)
**Steps:**
```bash
echo '{"content": "message text", "is_group": true}' | python proactive-recall.py
```
**Expected:**
- No entity-specific fact filtering (no entity_id to filter on)
- General memory recall (non-entity_fact rows) still functions unaffected
- No crash or SQL error

### TC-069: Group chat — entity with zero public facts
**Preconditions:** entity_id = 99; all facts are `visibility = 'private'`
**Steps:**
```bash
echo '{"content": "test", "entity_id": 99, "is_group": true}' | python proactive-recall.py
```
**Expected:**
- Zero entity_fact memories in output (all private, filtered by JOIN)
- Non-entity_fact source types (e.g., `session`, `lesson`) NOT affected by visibility filter
- No error

### TC-070: Group chat — entity with zero facts at all
**Preconditions:** entity_id = 999 (no rows in entity_facts)
**Expected:**
- JOIN produces no rows for entity_fact source_type
- No SQL error (empty JOIN result is valid)
- Non-entity_fact memories unaffected and returned normally

### TC-071: Visibility JOIN — non-entity_fact sources are never filtered
**Preconditions:** memory_embeddings contains rows with `source_type = 'session'`, `source_type = 'lesson'`, etc.
**Input:** Group chat (`is_group = true`)
**Expected:**
- Only `source_type = 'entity_fact'` rows are subject to the visibility JOIN filter
- All other source types pass through unfiltered regardless of group/DM status
- Confirm via EXPLAIN or SQL review: the visibility WHERE condition is inside an OR/CASE that excludes non-entity_fact rows

### TC-072: Visibility — null visibility value in entity_facts
**Preconditions:** entity_id = 55 has a fact with `visibility = NULL` (stored in entity_facts)
**Input:** Group chat (`is_group = true`)
**Expected:**
- NULL visibility fact NOT included after JOIN filter (NULL ≠ 'public' in SQL)
- Consistent with strict equality: `ef.visibility = 'public'` excludes NULLs

### TC-073: Visibility — 'public' value exactly (case-sensitive)
**Preconditions:** One entity_fact has `visibility = 'Public'` (capital P); one has `visibility = 'public'`
**Input:** Group chat
**Expected:**
- Only the lowercase `'public'` fact passes the JOIN filter (SQL equality is case-sensitive by default)
- `'Public'` is treated as non-public and excluded
- Document this behavior in test notes

### TC-074: domain_hints passed via stdin — accepted without error
**Preconditions:** proactive-recall.py receives domain_hints in payload
**Steps:**
```bash
echo '{"content": "check the pipeline", "domain_hints": ["software_engineering"], "is_group": false}' | python proactive-recall.py
```
**Expected:**
- Script accepts domain_hints without crashing
- domain_hints are used if tiered recall uses them (or gracefully ignored if not yet wired)

### TC-075: entity_id and is_group flow from semantic-recall.ts to proactive-recall.py
**Preconditions:** `semantic-recall.ts` receives `isGroup: true` and `senderId` resolves to `entity_id = 42`
**Steps:** Trace the stdin JSON payload logged by proactive-recall.py
**Expected:**
- stdin JSON contains `"entity_id": 42`
- stdin JSON contains `"is_group": true`
- Values match the resolved entity and channel type
- Confirm: entity_id is the integer PK from the `entities` table (not senderId string)

---

## Test Area 6: Entity Resolver Cache Bugfix

### TC-076: Bug baseline — old behavior (keyed by sessionKey alone)
**Preconditions:** Unfixed code (or documented as baseline for regression)
**Scenario:** Group channel where sessionKey is constant; two users message in sequence
1. User A (senderId=111) messages first → entity for User A cached under sessionKey
2. User B (senderId=222) messages second → cache returns User A's entity (wrong!)
**Expected (buggy behavior to confirm fix prevents):**
- WITHOUT fix: User B gets User A's cached entity context — WRONG
- WITH fix: User B gets their own entity context — CORRECT

### TC-077: Fix — cache keyed by sessionKey+senderId (group channel)
**Preconditions:** Fixed `entity-resolver.ts` with cache key = `sessionKey + ":" + senderId`
**Scenario:** Same group channel; User A then User B messages
**Steps:**
1. Message from User A (senderId=111) in session "group-channel-xyz"
   - Cache lookup: `group-channel-xyz:111` → miss → resolve → cache write
2. Message from User B (senderId=222) in same session
   - Cache lookup: `group-channel-xyz:222` → miss → resolve → cache write
3. Second message from User A
   - Cache lookup: `group-channel-xyz:111` → HIT → returns User A's entity
**Expected:**
- Cache key format: `{sessionKey}:{senderId}`
- Each user gets their own cached entity
- Cache hits work for the same user in subsequent messages

### TC-078: Fix — DM channel (single user, one cache entry)
**Preconditions:** Fixed code; DM channel where only one user ever sends
**Scenario:** User A sends 5 messages in DM session "dm-session-abc"
**Expected:**
- Cache hit from message 2 onward
- Cache key: `dm-session-abc:{senderId-A}` (consistent)
- Entity resolved once, cached thereafter

### TC-079: Cache key collision — different channels, same senderId
**Scenario:** User A (senderId=111) is in two different group channels
- Channel 1: sessionKey = "group-abc"; entity = EntityA1
- Channel 2: sessionKey = "group-def"; entity = EntityA2 (same user, different channel context)
**Expected:**
- Cache keys: `group-abc:111` and `group-def:111` are distinct
- No cross-channel cache bleed

### TC-080: Cache key — senderId undefined (anonymous or missing)
**Preconditions:** senderId is not provided (cache miss scenario)
**Expected:**
- Cache lookup skipped OR key constructed defensively (e.g., `sessionKey:undefined`)
- No entity resolved (returns null gracefully)
- No crash

### TC-081: Cache eviction — stale entry (30-minute TTL from index.ts)
**Preconditions:** Entity cached; 30 minutes + 1 second pass (or mock time)
**Expected:**
- Cache entry is considered stale on read
- Fresh resolution attempted
- Old stale entry not served

### TC-082: Cache max size — 1000 entries; oldest evicted on overflow
**Preconditions:** 999 distinct sessionKey:senderId pairs already cached
**Steps:**
1. Add entry #1000 → cache size = 1000 (OK, no eviction yet)
2. Add entry #1001 → eviction fires; oldest by timestamp removed
**Expected:**
- Cache never exceeds 1000 entries
- Oldest entry removed (not random, not newest)
- Evicted entry is re-resolved on next access (cold miss)

### TC-083: Concurrent messages from same user — no double-resolution race
**Preconditions:** Two simultaneous before_prompt_build hooks fire for same sessionKey+senderId
**Expected:**
- Entity resolved once (or at most twice with race, but result is consistent)
- No cache corruption from concurrent writes
- No Promise rejection

---

## Test Area 7: Integration Scenarios

### TC-084: Full happy path — info_request, domain found, memories recalled
**Scenario:** I)ruid sends "What's the status of the GitHub CI for nova-mind?"
**Steps:**
1. `message_received` fires → sender info cached
2. `before_prompt_build` fires
3. Classifier → `info_request`
4. Domain identifier → matches "github" domain
5. Entity resolver → resolves I)ruid's entity, loads facts
6. Tiered recall → domain-scoped search first, returns 3 relevant memories
7. Result assembled and returned
**Expected:**
- `prependSystemContext` contains:
  - `👤 Talking with: I)ruid` (entity context)
  - `🧠 Relevant Context:` with 3 memories (recall)
- `appendSystemContext` contains `📌 Per-Turn Reminders:` (if reminders exist)
- All memories are from github/CI-related content
- No errors in any subsystem

### TC-085: Full happy path — action, no domain match, full vector search fallback
**Scenario:** "Do a thing with that stuff" (action type, ambiguous domain)
**Expected:**
- Classifier → `action`
- Domain identifier → `NO DOMAIN IDENTIFIED`
- Full vector search runs
- Results returned based on full search
- Tier logged as `full_nodomain`

### TC-086: Full happy path — conversation, entity only (no recall)
**Scenario:** "Hey Nova, how's it going?"
**Expected:**
- Classifier → `conversation`
- Entity resolver runs → entity context in prepend
- Recall NOT run
- Domain identifier NOT run
- `prependSystemContext` = entity context only
- `appendSystemContext` = turn reminders only

### TC-087: Full happy path — continuation, nothing runs
**Scenario:** "ok" (single-word acknowledgment)
**Expected:**
- Classifier → `continuation`
- Entity resolver NOT run
- Recall NOT run
- Domain identifier NOT run
- Return: `undefined` OR only turn reminders (appendSystemContext) if those are not gated

### TC-088: Classifier + domain identifier + tiered recall — domain-scoped then fallback
**Scenario:** "What's happening with the Discord bot?" (info_request, discord domain)
**Setup:** Domain-scoped search returns 0 results (no embeddings for discord in DB)
**Expected:**
- domain-scoped phase: 0 results
- fallback phase: full vector search runs → returns general memories
- Final output includes relevant memories from full search
- Tier log shows `full_fallback`

### TC-089: Group channel — entity resolver + visibility filter + recall
**Scenario:** Unknown user in group channel sends "What's the plan for today?"
- `is_group = true`
- entity resolved to entity_id = 77 with mixed-visibility facts
**Expected:**
- Entity resolver returns entity context (public facts only)
- `proactive-recall.py` called with `is_group: true, entity_id: 77`
- Private facts NOT in output
- Recall memories from full vector search (group has no domain context)

### TC-090: Cache miss → resolution → cache hit on next message — all subsystems
**Scenario:** Same user sends two messages in quick succession
**Expected:**
- Message 1: entity resolver cache miss → resolved → cached
- Message 2: entity resolver cache hit (no DB call)
- Domain cache hit (within 5-minute TTL)
- Sender cache hit (from message_received)
- Second message processed faster than first

### TC-091: All subsystems fail — graceful total degradation
**Preconditions:** DB down, Ollama down
**Input:** Any message
**Expected:**
- Classifier → fails → fallback type returned
- Domain identifier → fails → NO DOMAIN IDENTIFIED
- Entity resolver → fails → null
- Recall → fails → null
- Return: `undefined` (no context to inject) OR only turn reminders if they were cached
- No crash; no unhandled rejection
- All errors logged

### TC-092: Classifier + domain hint feeds domain identifier
**Preconditions:** Classifier returns `domainHints = ["slack"]`
**Expected:**
- Domain identifier receives these hints
- Keyword matching cross-references against hints
- If "slack" matches a domain keyword, confidence boosted or domain matched faster

### TC-093: message_received race condition — before_prompt_build fires before cache write
**Preconditions:** Node.js event ordering; cache write is synchronous (per code)
**Expected:**
- Cache write in `message_received` occurs BEFORE any `await`
- If `before_prompt_build` fires concurrently, it either gets the cached value or gracefully handles miss
- The implementation's existing "cache write MUST happen before any await" comment is enforced

---

## Test Area 8: Boundary Values and Thresholds

### TC-094: Similarity threshold — at 0.4 (default)
**Preconditions:** `DEFAULT_THRESHOLD = 0.4`; mock result with similarity 0.40
**Expected:**
- Result included in output (inclusive)

### TC-095: Similarity threshold — below 0.4
**Input:** Mock result with similarity 0.39
**Expected:**
- Result excluded from output

### TC-096: High confidence threshold — at 0.7 (default)
**Input:** Memory with similarity 0.70
**Expected:**
- Full content returned (not summary)
- Indicator: `🎯`

### TC-097: High confidence threshold — just below 0.7
**Input:** Memory with similarity 0.69
**Expected:**
- Summary returned (truncated)
- Indicator: `📝`

### TC-098: Token budget — exactly at limit
**Preconditions:** `TOKEN_BUDGET = 1000`; mock results that sum to exactly 1000 tokens
**Expected:**
- All results included
- No results dropped

### TC-099: Token budget — first result alone exceeds budget
**Preconditions:** One result with estimated tokens > 1000
**Expected:**
- High-confidence: shorter version tried → if fits, included
- If still exceeds: skipped
- Output may be empty (`memories: []`) — no crash

### TC-100: Token budget — 95% threshold triggers early stop
**Preconditions:** Results accumulate; 10th result would push total to 96% of budget
**Expected:**
- Loop stops after reaching 95% threshold (per `if tokens_used >= token_budget * 0.95: break`)
- 10th result is NOT included

### TC-101: CACHE_MAX_SIZE boundary — exactly 1000 entries
**Preconditions:** senderCache has 1000 entries
**Steps:** Add entry #1000
**Expected:**
- No eviction (size = max, not over max)
- Entry #1000 stored

### TC-102: CACHE_MAX_SIZE boundary — 1001st entry triggers eviction
**Steps:** Add entry #1001 to a 1000-entry cache
**Expected:**
- `evictOldestIfFull()` fires
- Oldest entry removed before new entry written
- Post-insertion size = 1000 (not 1001)

### TC-103: CACHE_STALE_MS boundary — exactly 30 minutes
**Preconditions:** Entry timestamped exactly 30 minutes ago (1,800,000ms)
**Expected:**
- `now - timestamp = CACHE_STALE_MS` exactly
- Entry treated as stale (eviction fires) OR not stale (off-by-one check)
- Document behavior clearly: < or <=

### TC-104: Domain cache TTL — 5 minutes (300,000ms)
**Preconditions:** Domain data cached at T=0
**At T+299s:** cache still valid (hit)
**At T+301s:** cache expired (miss, DB re-queried)
**Expected:**
- Boundary honored within 1-second tolerance

### TC-105: Recall content truncation — max_summary boundary
**Preconditions:** Low-confidence result (< 0.7); content exactly at max_summary length
**Expected:**
- Content returned as-is (no truncation)
- No `[summary]` suffix

### TC-106: Recall content truncation — one char over max_summary
**Preconditions:** Low-confidence result; content length = max_summary + 1
**Expected:**
- Content truncated at word boundary
- `[summary]` suffix appended

### TC-107: Dynamic content limits — single result vs 10 results
**Preconditions:** 1 result → max_full limit applies; 10 results → min_full limit applies
**Expected:**
- Single result gets longer content truncation limit than result #10 in a 10-result set
- Ratio consistent with `calculate_dynamic_limits()` implementation

### TC-108: Spawn timeout — 5 seconds (SPAWN_TIMEOUT_MS)
**Preconditions:** proactive-recall.py mocked to sleep 6 seconds
**Expected:**
- Process killed via SIGTERM at 5000ms
- `reject(new Error("proactive-recall.py timed out..."))` thrown
- Caller receives null (graceful)
- No zombie process left running

### TC-109: Entity resolution timeout — 2000ms
**Preconditions:** `resolveEntityByIdentifiers` mocked to delay 2500ms
**Expected:**
- `Promise.race` timeout wins at 2000ms
- Returns null entity (graceful degradation)
- No wait for 2500ms resolution

### TC-110: Entity facts timeout — 1000ms
**Preconditions:** `getEntityProfile` mocked to delay 1500ms
**Expected:**
- `Promise.race` timeout wins at 1000ms
- Returns empty facts `{}`
- Entity name still displayed (partial entity context)

---

## Test Area 9: Error Conditions

### TC-111: proactive-recall.py — non-zero exit code
**Preconditions:** Mocked script exits with code 1
**Expected:**
- `spawnWithTimeout` rejects with error including exit code and stderr
- Caller logs error and returns null
- No crash in parent plugin

### TC-112: proactive-recall.py — invalid JSON output
**Preconditions:** Script exits 0 but stdout is not valid JSON
**Expected:**
- `JSON.parse` throws
- Rejection: `"Failed to parse recall output: ..."`
- Caller returns null

### TC-113: proactive-recall.py — empty stdout on exit 0
**Preconditions:** Script exits 0 with no stdout
**Expected:**
- `spawnWithTimeout` rejects OR resolves to empty (depending on implementation)
- Either way: caller returns null
- No crash

### TC-114: proactive-recall.py — Python binary not found
**Preconditions:** Both STANDARD_VENV and WORKSPACE_VENV paths don't exist
**Expected:**
- `child.on("error")` fires with ENOENT
- Rejection caught
- Caller returns null

### TC-115: DB connection failure — PostgreSQL entirely down
**Preconditions:** `psycopg2.connect()` raises exception
**Expected:**
- `recall()` returns `{"error": "<message>", "memories": []}`
- proactive-recall.py exits 0 with that JSON output
- `runSemanticRecall()` returns null (no memories)

### TC-116: Ollama embedding failure — HTTP 500
**Preconditions:** Ollama returns 500 on embedding request
**Expected:**
- `get_embedding()` raises `urllib.error.HTTPError`
- `recall()` catches → returns error JSON
- No crash in proactive-recall.py

### TC-117: turn-reminders DB failure — pool connection error
**Preconditions:** `pool.connect()` throws
**Expected:**
- `queryTurnContext()` throws
- `getTurnReminders()` propagates error
- Caught in `before_prompt_build` `Promise.allSettled`
- `turnRemindersResult.status === "rejected"`
- Other subsystems still run

### TC-118: Entity resolver library not installed
**Preconditions:** `~/.openclaw/lib/entity-resolver/index.ts` does not exist
**Expected:**
- `ensureEntityResolver()` returns false
- `resolveEntityContext()` returns null
- Logged as warn (not error)
- Plugin continues functioning without entity context

### TC-119: Classifier Ollama returns malformed JSON
**Preconditions:** Ollama mock returns `"not json at all"` as classification
**Expected:**
- Classifier catches parse error
- Falls back to default type
- Error logged
- No crash

### TC-120: Domain identifier embedding returns wrong dimensions
**Preconditions:** Embedding API returns vector of wrong length (e.g., 512 vs 1024)
**Expected:**
- `ValueError: Dimension mismatch` raised
- Domain identifier catches error → returns NO DOMAIN IDENTIFIED
- Error logged

---

## Test Area 10: Observability and Logging

### TC-121: Classifier logs selected type and method (rule vs Ollama)
**Expected log pattern:** `[turn-context] classifier type=info_request method=rule` or similar
- `method` field present: values `"rule"` or `"ollama"`

### TC-122: Domain identifier logs matched domain and similarity score
**Expected log pattern:** `[turn-context] domain=github similarity=0.82 matchedBy=keyword`
- When NO DOMAIN IDENTIFIED: `domain=none`

### TC-123: Tiered recall logs tier used
**Expected log pattern:** `[turn-context] recall tier=domain results=3` or `tier=full_fallback results=7` or `tier=skipped reason=continuation`

### TC-124: before_prompt_build logs total duration and subsystem breakdown
**Expected:** Existing log structure preserved and extended:
```
[turn-context] before_prompt_build DONE in Xms — injecting prepend=Nchars append=Mchars
```
New additions:
```
[turn-context] classifier=Xms domain=Xms recall=Xms entity=Xms
```
Or equivalent per-subsystem timing.

### TC-125: Recall tier logged when recall skipped (continuation/command)
**Expected:** Log line confirms skip reason:
`[turn-context] recall=skipped reason=message_type:continuation`

### TC-126: Visibility filter applied — logged in proactive-recall.py stderr
**Expected:** When `is_group = true`:
```
[proactive-recall] applying visibility filter: is_group=true entity_id=42
```
When `is_group = false`: no filter log (or explicit "no filter applied")

### TC-127: No double-logging on cache hits
**Preconditions:** Second message hits all caches (sender, domain, entity, turn reminders)
**Expected:**
- Single log line per subsystem indicating cache hit
- No duplicate "resolving..." log entries

---

## Test Area 11: Migration Validation

### TC-128: Migration 080 — applies cleanly to fresh DB
**Steps:**
```bash
psql -U gem -d nova_memory < migrations/080_prompt_helper_config.sql
```
**Expected:**
- Applies without errors
- `prompt_helper_config` table created
- `agent_domains.keywords` column added
- `agent_domains.notes` column updated for all 38 rows

### TC-129: Migration 080 — idempotent (IF NOT EXISTS guards)
**Steps:** Apply migration twice
**Expected:**
- Second application does not error
- No duplicate rows in prompt_helper_config

### TC-130: Migration 080 — rollback/down migration
**Preconditions:** If down migration is provided
**Expected:**
- Down migration removes prompt_helper_config table
- Removes keywords column from agent_domains
- DB returns to pre-080 state

### TC-131: agent_domains — keywords column is TEXT[] type
**Steps:**
```sql
SELECT data_type, udt_name FROM information_schema.columns
WHERE table_name = 'agent_domains' AND column_name = 'keywords';
```
**Expected:**
- `data_type = 'ARRAY'`
- `udt_name = '_text'`

### TC-132: prompt_helper_config — PK constraint on id
**Steps:**
```sql
INSERT INTO prompt_helper_config (id, message_type, helper_name, enabled)
VALUES (1, 'action', 'semantic_recall', true);
-- (if id=1 already exists)
```
**Expected:**
- Duplicate PK error raised
- Constraint enforced

---

## Test Coverage Summary

| Area | TCs | Coverage Focus |
|---|---|---|
| 1. Message Type Classifier | TC-001 – TC-020, TC-020b | Rule-based + `>` continuation convention (21 TCs) |
| 2. Domain Identifier | TC-021 – TC-040, TC-038b, TC-039b | Embedding + keywords + multi-match + format (22 TCs) |
| 3. Prompt Helper Config | TC-041 – TC-050, TC-047b | Table schema + dispatch config + reminders always-on (12 TCs) |
| 4. Tiered Recall | TC-051 – TC-064 | Gating + tier selection (14 TCs) |
| 5. Visibility Filtering | TC-065 – TC-075 | Group vs DM, JOIN-based public/private filter (11 TCs) |
| 6. Entity Resolver Cache Bugfix | TC-076 – TC-083 | sessionKey+senderId key fix (8 TCs) |
| 7. Integration Scenarios | TC-084 – TC-093 | End-to-end flows (10 TCs) |
| 8. Boundary Values | TC-094 – TC-110 | Thresholds, limits, timeouts (17 TCs) |
| 9. Error Conditions | TC-111 – TC-120 | Failure modes + degradation (10 TCs) |
| 10. Observability | TC-121 – TC-127 | Logging + structured output (7 TCs) |
| 11. Migration Validation | TC-128 – TC-132 | Schema integrity (5 TCs) |
| **TOTAL** | **137 test cases** | |

---

## Entry / Exit Criteria

### Entry Criteria (before execution begins)
- Migration `080_prompt_helper_config.sql` applied to staging DB
- `classifier.ts` and `domain-identifier.ts` implemented and compiled
- `agent_domains` seeded with 38 domains (keywords + notes + embeddings)
- `proactive-recall.py` updated with `entity_id`/`is_group`/`domain_hints` support
- `entity-resolver.ts` cache key fix merged
- `semantic-recall.ts` tiered recall refactor implemented
- Plugin builds without TypeScript errors (`npm run build` clean)
- Staging environment available

### Exit Criteria (before QA sign-off)
- All TC-001 through TC-132 executed
- Zero S1/S2 defects open
- TC-010 (60-70% rule coverage) verified with representative sample
- TC-076/TC-077 entity resolver cache bugfix confirmed via group channel scenario
- TC-128 migration applies cleanly on staging
- Observability logs (TC-121 to TC-127) parseable by log aggregation tools
- No unhandled Promise rejections observed across any test scenario

---

## Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| Ollama latency causes classifier timeout | S2 | TC-014 verifies graceful fallback; tune timeout |
| Domain embedding similarity tuning needed | S2 | TC-025/TC-026 establish threshold boundaries; adjust empirically |
| Group channel cache bug regression | S1 | TC-076/TC-077 must pass; add to regression suite |
| Visibility SQL NULL edge case | S2 | TC-072 covers NULL visibility; verify SQL behavior |
| Migration not idempotent causes staging breakage | S2 | TC-129 validates idempotency |
| Token budget not respected across domain+full tiers | S3 | TC-060 validates cross-tier budget tracking |
