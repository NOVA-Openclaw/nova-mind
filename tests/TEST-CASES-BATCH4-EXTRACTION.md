# Test Cases: Batch 4 — Memory Extraction Pipeline Rewrite

**Issues:** #184 (bug), #112 (enhancement), #175 (enhancement), #141 (enhancement)  
**Branch:** `feature/batch4-extraction-pipeline`  
**Deliverable:** Python rewrite of the extraction pipeline with expanded entity IDs and categories  
**Author:** Gem (QA Lead)

---

## Scope

### What Is Being Tested
1. `memory/scripts/extract_memories.py` — new unified Python module replacing `process-input.sh`, `extract-memories.sh`, `store-memories.sh`
2. Updated `memory/hooks/memory-extract/handler.ts` — field access fix (reads `ctx.content`, `ctx.from`, `ctx.metadata.senderName`, `ctx.metadata.senderId`)
3. Enhanced LLM extraction prompt — entity ID patterns and new categories
4. End-to-end pipeline integration

### What Is NOT Tested Here
- `memory-catchup.sh` batch pipeline (covered in prior test batches)
- Semantic recall / embeddings (separate subsystem)
- Database schema migrations (separate migration test suite)
- Channel transcripts upsert logic (covered in TEST-CASES-ISSUE-165-138-170.md)

---

## Entry Criteria
- `extract_memories.py` exists at `memory/scripts/extract_memories.py`
- Updated `handler.ts` deployed on staging
- `nova_memory` database reachable on staging with `entities`, `entity_facts`, `events` tables
- `OPENROUTER_API_KEY` set in staging environment
- Python 3.10+ with `psycopg2` and `requests` (or `httpx`) installed

## Exit Criteria
- All TC-PASS cases pass
- All TC-FAIL cases correctly reject/handle the bad input
- Zero unhandled exceptions in extraction script
- Coverage: ≥80% statement coverage on `extract_memories.py` core logic paths
- No S1/S2 defects open

---

## Section 1 — Happy Path (HP)

### HP-001: End-to-end extraction and storage

**Preconditions:** Staging DB accessible; `I)ruid` entity exists in `entities`; OpenRouter API reachable.

**Input (via stdin):**
```
I just got back from Austin, Texas. I've been living there for about three years now.
```

**Env vars:** `SENDER_NAME=I)ruid`, `SENDER_ID=+15551234567`, `IS_GROUP=false`, `SOURCE_SESSION_ID=test-session-001`, `SOURCE_TIMESTAMP=2026-05-12T09:00:00Z`

**Steps:**
```bash
echo "I just got back from Austin, Texas. I've been living there for about three years now." | \
  python3 memory/scripts/extract_memories.py
```

**Expected:**
- Exit code 0
- Stdout is valid JSON (or empty `{}`)
- `entity_facts` table gains at least one row with `key IN ('location', 'lives_in', 'city')` and `value` containing `'Austin'` for the `I)ruid` entity
- `source_session_id = 'test-session-001'` on the new row
- No exception traceback in stderr

**Pass criteria:** `SELECT COUNT(*) FROM entity_facts WHERE entity_id = (SELECT id FROM entities WHERE name = 'I)ruid') AND key ILIKE '%location%' AND value ILIKE '%Austin%';` returns ≥ 1

---

### HP-002: Sender name attribution on extracted facts

**Preconditions:** Same as HP-001.

**Input:** `"My favourite band is Tool."`

**Env vars:** `SENDER_NAME=I)ruid`, `SENDER_ID=+15551234567`

**Expected:**
- New `entity_fact` row has `source = 'I)ruid'` (or `source_entity_id` resolving to I)ruid's entity ID)
- `key ILIKE '%preference%' OR key ILIKE '%band%' OR key ILIKE '%music%'`
- `value ILIKE '%Tool%'`

---

### HP-003: Multi-category extraction from a single message

**Input:**
```
I decided last week to quit my job at Cloudflare and start my own consulting firm. 
Super excited about it — been wanting to do this for years.
```

**Env vars:** `SENDER_NAME=I)ruid`

**Expected:** LLM extraction JSON contains at least:
- An `entities` entry for `Cloudflare` (type: organization) OR a `facts` entry mentioning Cloudflare
- A `facts` or `decisions` entry reflecting the job change decision
- An `events` entry (or `milestones` entry) for "quit job" / "start consulting firm"

**Pass criteria:** Returned JSON has ≥ 3 non-empty categories; all stored to DB without errors.

---

### HP-004: New extraction categories present in LLM output

**Input:**
```
I'm definitely going with PostgreSQL for the new project — SQLite just won't scale.
I prefer dark mode in all my editors. The deadline is June 15th for the MVP.
We solved the connection pooling problem by switching to pgBouncer.
```

**Expected — returned JSON must include:**
- `decisions`: `[{"subject": "database choice", "decision": "PostgreSQL over SQLite", ...}]` (or similar)
- `preferences`: `[{"person": "I)ruid", "category": "editor", "preference": "dark mode", ...}]`
- `milestones` or `events`: MVP deadline June 15th
- `problems` (solved): connection pooling / pgBouncer (or stored as a fact/event)

**Pass criteria:** At least 3 of the 4 new category types (`decisions`, `preferences`, `milestones`, `problems`) present in extracted JSON with correct structure.

---

## Section 2 — Field Name Mapping / Bug #184 (FNM)

### FNM-001: handler.ts reads ctx.content as primary field

**Preconditions:** Updated handler.ts deployed on staging.

**Verification step:**
```bash
grep -n 'rawBody\|content\|RawBody\|message\|Body' memory/hooks/memory-extract/handler.ts | head -20
```

**Expected:** The primary field read for message body is `ctx.content`. The existing fallback chain `ctx.content ?? ctx.rawBody ?? ctx.RawBody ?? ctx.message ?? ctx.Body` remains intact for backward compatibility, but `ctx.content` is always present in a canonical `MessageReceivedHookContext`.

**Additional check:** Confirm handler never reads an undefined-at-runtime field path as the sole accessor (i.e., no code path reaches `ctx.rawBody` when `ctx.content` is set).

---

### FNM-002: Sender name read from ctx.metadata.senderName

**Input event (constructed for unit test):**
```typescript
{
  type: "message",
  action: "received",
  context: {
    content: "Hello world",
    from: "user@example.com",
    channelId: "discord",
    metadata: {
      senderName: "I)ruid",
      senderId: "330189773371080716"
    }
  }
}
```

**Expected:**
- `SENDER_NAME` env var passed to subprocess = `"I)ruid"` (not `"unknown"`, not `"user@example.com"`)
- `SENDER_ID` env var = `"330189773371080716"`

**Regression risk:** Old handler read `ctx.senderName` directly (not via `ctx.metadata`). After fix, canonical path is `ctx.metadata?.senderName`.

---

### FNM-003: Fallback chain when metadata is absent

**Input event:**
```typescript
{
  type: "message",
  action: "received",
  context: {
    content: "Testing fallback",
    from: "signaluser"
    // metadata absent
  }
}
```

**Expected:**
- `SENDER_NAME` = `"signaluser"` (falls back to `ctx.from`)
- `SENDER_ID` = `""` (no crash)
- Extraction proceeds normally; message is not skipped

---

### FNM-004: ctx.from used when metadata.senderName missing

**Input event:**
```typescript
{
  type: "message",
  action: "received",
  context: {
    content: "Sender from fallback",
    from: "alice",
    metadata: {
      senderId: "some-uuid-123"
      // senderName absent
    }
  }
}
```

**Expected:** `SENDER_NAME` = `"alice"`, `SENDER_ID` = `"some-uuid-123"`

---

### FNM-005: ctx.conversationId and ctx.messageId flow to transcript upsert

**Input event (canonical Discord context):**
```typescript
{
  context: {
    content: "Message with full context",
    from: "I)ruid",
    channelId: "discord",
    conversationId: "channel:1492386247862390824",
    messageId: "1502589947721547817",
    metadata: {
      senderName: "I)ruid",
      senderId: "330189773371080716",
      isGroup: true,
      channelName: "#software-engineering",
      guildId: "1492385947927445524"
    }
  }
}
```

**Expected:**
- `channel_sessions` row: `provider='discord'`, `external_chat_id='channel:1492386247862390824'`
- `channel_transcripts` row: `external_message_id='1502589947721547817'`
- `SOURCE_CHANNEL_TRANSCRIPT_ID` env var set to the numeric ID of the new transcript row before calling the Python script
- No fallback to `ctx.chatId` or `ctx.chat_id` (deprecated paths)

---

## Section 3 — Entity ID Extraction / Issue #175 (EID)

### EID-001: Phone number extraction

**Input:** `"You can reach me at +1 (512) 555-0192 for urgent stuff."`

**Env vars:** `SENDER_NAME=I)ruid`

**Expected JSON from LLM:**
```json
{
  "facts": [
    {
      "subject": "I)ruid",
      "predicate": "phone",
      "value": "+15125550192",
      "source_person": "I)ruid",
      "confidence": 0.95,
      "visibility": "private"
    }
  ]
}
```

**Pass criteria:**
- Fact stored with `key='phone'`
- Value normalised (digits + country code, no spaces/dashes/parens)
- `visibility = 'private'` (phone numbers default private)

---

### EID-002: Email address extraction

**Input:** `"My work email is dustin@example.com and personal is druidian@proton.me"`

**Expected:**
- Two `entity_facts` rows with `key='email'`
- Values: `dustin@example.com`, `druidian@proton.me`
- Both marked `visibility='private'` by default

---

### EID-003: Discord user ID extraction (numeric snowflake)

**Input:** `"My Discord user ID is 330189773371080716."`

**Expected:**
- `entity_fact` with `key='discord_id'`, `value='330189773371080716'`
- Value is a numeric string (18–19 digits), not truncated or cast to integer

---

### EID-004: Discord username extraction (handle format)

**Input:** `"Find me on Discord as druidian — that's my username."`

**Expected:**
- `entity_fact` with `key='discord_username'` or `key='discord_handle'`, `value='druidian'`

---

### EID-005: GitHub handle extraction

**Input:** `"My GitHub is @druidian — check out my repos there."`

**Expected:**
- `entity_fact` with `key='github'` or `key='github_handle'`, `value='druidian'`
- Leading `@` stripped or preserved consistently

---

### EID-006: Signal UUID extraction

**Input:** `"My Signal UUID is 12345678-1234-1234-1234-123456789abc"`

**Expected:**
- `entity_fact` with `key='signal_uuid'` or `key='signal'`, `value='12345678-1234-1234-1234-123456789abc'`
- UUID format validated (8-4-4-4-12 hex)

---

### EID-007: Multiple IDs in single message

**Input:** `"I'm druidian on GitHub, my Discord is 330189773371080716, and you can email me at d@example.com."`

**Expected:**
- Three separate `entity_facts` rows, one per ID type
- No merging or truncation of IDs
- All attributed to the correct entity (`I)ruid`)

---

### EID-008: Phone number — do not extract partial/ambiguous numbers

**Input:** `"Call me on 555 — you know the number."`

**Expected:**
- No phone `entity_fact` created (incomplete number)
- Extraction returns `{}` or returns JSON without `facts[].predicate == 'phone'`

---

### EID-009: Username disambiguation — GitHub vs Discord

**Input:** `"druidian is my handle on both GitHub and Discord."`

**Expected:**
- Two separate `entity_fact` rows with distinct keys (`github_handle`, `discord_username`)
- Values identical (`druidian`) but stored under correct key — not merged into one row

---

## Section 4 — New Extraction Categories / Issue #141 (CAT)

### CAT-001: Decision extraction

**Input:** `"After months of deliberation, I've decided to switch from vim to Neovim for all my editing."`

**Expected JSON:**
```json
{
  "decisions": [
    {
      "subject": "I)ruid",
      "decision": "Switch from vim to Neovim",
      "source_person": "I)ruid",
      "confidence": 0.9,
      "visibility": "public"
    }
  ]
}
```

**DB storage:** Stored as `entity_fact` with `key='decision'` or `data_type='observation'` — implementation choice, but must be queryable.

---

### CAT-002: Preference extraction

**Input:** `"I always use dark mode. Can't stand light themes."`

**Expected:**
- `preferences[0].category = 'editor'` or `'display'` or `'ui'`
- `preferences[0].preference = 'dark mode'` (or equivalent)
- `preferences[0].confidence ≥ 0.8` (strong assertion language: "always", "can't stand")

---

### CAT-003: Milestone extraction

**Input:** `"We shipped v2.0 of nova-mind to production yesterday. Big deal for the team!"`

**Expected:**
- `milestones` or `events` entry with description containing `v2.0` and `production`
- `date` field set to yesterday's date (relative resolution) OR left null with description mentioning "yesterday"
- `visibility = 'public'`

---

### CAT-004: Problem extraction

**Input:** `"We've been fighting a connection leak in the hook runner for two weeks now. Still not solved."`

**Expected:**
- `problems` entry with description containing `connection leak` and `hook runner`
- Status implies unresolved (no "fixed", "solved" language)
- `visibility = 'public'`

---

### CAT-005: Problem-solved extraction

**Input:** `"We finally fixed the webhook timeout issue by bumping the request timeout to 30 seconds."`

**Expected:**
- `problems` entry OR `facts` entry indicating the timeout issue was resolved
- Solution (`bumping timeout to 30s`) captured in value or alongside problem description
- Does NOT leave an open/unresolved problem record

---

### CAT-006: Backward compatibility — existing categories still extracted

**Input:**
```
My name is Alice. I love jazz music. I think Python is overrated. 
Alice lives in Seattle. She met Bob at a conference in March.
```

**Expected:** Existing categories (`entities`, `facts`, `opinions`, `preferences`, `vocabulary`, `events`) still extracted correctly. New categories do not replace existing ones.

---

### CAT-007: New category data stored to correct DB table/key

**Verification:**  
For each new category (`decisions`, `milestones`, `problems`):
- Confirm the Python script stores them in `entity_facts` with a distinguishable `key` prefix (e.g., `decision`, `milestone`, `problem`)
- OR confirm they go to the `events` table if that's the design decision
- Either way: **document the storage key/table in test output** so Flint can verify by SQL query

**Pass criteria:** Implementation stores new categories consistently; no data silently dropped.

---

## Section 5 — Edge Cases (EC)

### EC-001: Empty message body

**Input (stdin):** *(empty string)*

**Expected:**
- Exit code 0 (graceful skip, not error)
- No LLM API call made
- No DB writes
- Stderr: `"Skipping short or empty message"` or equivalent

---

### EC-002: Message under 10 characters

**Input:** `"OK"`

**Expected:**
- Handler skips extraction (existing guard: `rawBody.trim().length < 10`)
- Python script also skips if called directly with short input
- Exit code 0, no API call, no DB write

**Boundary tests (BVA):** Test with lengths 8, 9, 10, 11 chars:
- 8 chars → skip
- 9 chars → skip
- 10 chars → **borderline**: implementation must decide inclusive/exclusive; test and document actual behavior
- 11 chars → process

---

### EC-003: Slash command message

**Input:** `"/model opus-4.6"`

**Expected:**
- Handler detects leading `/` and returns early
- No extraction, no DB write
- Logged as "Skipping command message"

---

### EC-004: Heartbeat/system message

**Input:** `"HEARTBEAT 2026-05-12T09:00:00Z"`

**Expected:**
- Handler's `isHeartbeat` check fires (contains "HEARTBEAT")
- Activity counter updated (`heartbeats++`) but extraction skipped
- Python script not invoked

**Additional heartbeat patterns to test:**
- `"DASHBOARD UPDATE 09:00"` → skip
- `"System: [connected]"` → skip

---

### EC-005: Very long message (100KB)

**Input:** 100,000-character string (ASCII lorem ipsum)

**Expected:**
- Handler passes full content to Python script (no truncation before extraction)
- Transcript storage truncates to 65,535 chars (`rawBody.substring(0, 65535)`)
- Python script handles without crash; may truncate internally for LLM prompt
- LLM API call uses truncated input if over model context limit; no crash

---

### EC-006: Unicode and emoji in message

**Input:** `"Je suis à Paris 🗼. Mon email est test@example.fr et je préfère le café ☕."`

**Expected:**
- Extraction handles multibyte unicode correctly
- Email `test@example.fr` extracted as entity_fact
- No encoding errors in DB storage
- `entity_fact.value` stored as valid UTF-8

---

### EC-007: SQL injection attempt via message content

**Input:** `"My name is O'Brien and I like pizza'); DROP TABLE entities; --"`

**Expected:**
- Extraction proceeds safely
- `entities` table not dropped
- `entity_fact.value` stored as literal string (apostrophe escaped, not interpreted as SQL)
- Shell-based scripts: `sql_escape()` function handles the input
- Python script: parameterised queries (`%s` placeholders) prevent injection

**Verification:**
```sql
SELECT COUNT(*) FROM entities;
-- Must return same count as before the test
```

---

### EC-008: Message with only emoji

**Input:** `"🎉🎊🥳"`

**Expected:**
- Length check: 3 characters (Unicode codepoints) — skipped by short message guard  
- OR: even if 3 bytes passes length check, LLM returns `{}` (nothing extractable)
- No crash in either case

---

### EC-009: Message in non-English language

**Input:** `"Ich wohne in Berlin und arbeite bei einem Startup."` (German: "I live in Berlin and work at a startup.")

**Expected:**
- LLM extracts `Berlin` as a location entity
- `entity_fact` key `location` with value `Berlin` (or equivalent)
- No crash; partial extraction is acceptable; zero extraction also acceptable but should be documented

---

## Section 6 — Error Conditions (ERR)

### ERR-001: LLM API unavailable (network failure)

**Setup:** Set `OPENROUTER_API_KEY` to a valid key, then block network access to `openrouter.ai` (e.g., via iptables on staging).

**Expected:**
- Python script exits with non-zero code
- Error message in stderr: `"LLM API call failed"` or equivalent
- No partial/corrupt data written to DB
- Handler logs `'[memory-extract] Extraction failed'` with exit code

---

### ERR-002: LLM API returns HTTP 401 (invalid key)

**Setup:** Set `OPENROUTER_API_KEY=invalid-key-test`

**Expected:**
- Script exits non-zero
- Stderr contains HTTP status or error context
- No DB write

---

### ERR-003: LLM API returns malformed JSON

**Setup:** Mock/stub the LLM response to return `"Here is the data: {broken json"` (non-JSON response)

**Expected:**
- Python script detects invalid JSON
- Logs: `"Failed to parse LLM response as JSON"` or equivalent
- Exits non-zero OR exits 0 with empty extraction (skips storage)
- No DB write with garbage data

**Testing approach:** Inject a mock by temporarily replacing the API call with a shell alias or monkey-patch in pytest.

---

### ERR-004: LLM API returns empty response

**Setup:** Mock LLM to return `""` or `null` for `choices[0].message.content`

**Expected:**
- Script treats empty as no-op: exits 0, stores nothing
- No KeyError / AttributeError traceback

---

### ERR-005: DB connection failure during storage

**Setup:** After extraction returns valid JSON, kill PostgreSQL connection before storage step (or use wrong DB credentials in env).

**Expected:**
- Python script logs a DB connection error
- Exits non-zero
- No partial inserts (transaction rolled back)
- Handler logs `'[memory-extract] Extraction failed'`

---

### ERR-006: DB constraint violation during storage

**Setup:** Manually create an `entities` row with `(name='TestConflict', type='person')`. Then trigger extraction for message mentioning `TestConflict` as a person.

**Expected:**
- `ON CONFLICT DO NOTHING` (or `ON CONFLICT DO UPDATE`) fires silently
- No unhandled exception
- Existing entity record preserved; no duplicate row

---

### ERR-007: Missing required environment variable

**Setup:** Unset `OPENROUTER_API_KEY` before running extraction.

**Expected:**
- Script exits non-zero immediately
- Stderr: `"ERROR: OPENROUTER_API_KEY not set"` (or equivalent)
- No API call attempted, no DB write

---

## Section 7 — Short Message Filtering (SMF)

### SMF-001: Handler-level filter (TypeScript)

**Verification:** Read `handler.ts` and confirm the guard:
```typescript
if (!rawBody || rawBody.trim().length < 10) {
    console.debug('[memory-extract] Skipping short or empty message');
    return;
}
```

**Expected:** Guard exists at the top of the main handler body, before the Python script is spawned.

---

### SMF-002: Python script-level filter (defense in depth)

**Input (stdin to Python script directly):** `"short"`

**Expected:**
- Python script also enforces minimum length (≥ 10 chars)
- Exits 0 with empty output / `{}`
- No LLM API call

**Rationale:** Handler is TypeScript; if Python script is ever called directly (e.g., from memory-catchup.sh), it must not extract 5-word messages.

---

### SMF-003: Whitespace-only message

**Input:** `"         "` (10 spaces — passes raw length, fails trimmed length)

**Expected:** Skipped (`.trim().length < 10` catches this)

---

## Section 8 — Privacy & Visibility (PRV)

### PRV-001: Default visibility from sender preference

**Precondition:** `I)ruid` has `entity_fact` with `key='default_visibility'`, `value='private'`

**Input:** `"I think Rust is a great language."`

**Expected:**
- All extracted facts/opinions have `visibility = 'private'`
- No `visibility_reason` required (it matches default)

---

### PRV-002: Explicit public override

**Input:** `"Feel free to share — I've decided to move to Austin next month."`

**Precondition:** User's `default_visibility = 'private'`

**Expected:**
- Extracted fact (moving to Austin) has `visibility = 'public'`
- `visibility_reason` explains the override (e.g., `"user said 'feel free to share'"`)

---

### PRV-003: Explicit private override

**Input:** `"Just between us — I'm having some health issues."`

**Precondition:** User's `default_visibility = 'public'`

**Expected:**
- Extracted health-related fact has `visibility = 'private'`
- `visibility_reason` set to `"user said 'just between us'"` or similar

---

### PRV-004: Unknown sender — default visibility fallback

**Precondition:** No `entity_fact` for `default_visibility` for sender `"Stranger"`

**Input:** `"My phone is +1-555-000-1234."`

**Env vars:** `SENDER_NAME=Stranger`

**Expected:**
- Default visibility = `'public'` (fallback when no preference found in DB)
- Phone fact still extracted and stored

---

### PRV-005: Phone number visibility always private

**Input:** `"Feel free to share my number: +1 (512) 555-0199"`

**Expected:**
- Phone number fact stored with `visibility = 'private'` regardless of explicit public override
- Rationale: Phone numbers are PII; the extraction prompt should enforce this as a hard rule

**Note to implementer:** If this is not implemented as a hard rule, TC is FAIL — this must be documented as a known gap.

---

## Section 9 — Deduplication (DUP)

### DUP-001: Exact duplicate fact — reinforce, don't duplicate

**Setup:** Manually insert:
```sql
INSERT INTO entity_facts (entity_id, key, value, vote_count, confirmation_count)
SELECT id, 'location', 'Austin', 1, 1 FROM entities WHERE name = 'I)ruid';
```

**Input:** `"I live in Austin, Texas."`

**Expected:**
- `vote_count` incremented to 2 (or `confirmation_count` incremented)
- `last_confirmed` / `last_confirmed_at` updated to NOW()
- No second row inserted with `key='location'` and `value='Austin'`
- `SELECT COUNT(*) FROM entity_facts WHERE entity_id = ... AND key = 'location' AND value ILIKE '%Austin%'` returns exactly 1

---

### DUP-002: Fuzzy duplicate — similar value reinforced (dedup_helper.py behavior)

**Setup:** Existing fact: `key='location'`, `value='Austin Texas'`

**New extraction:** `value='Austin, Texas'` (extra comma, different format)

**Expected (dedup_helper.py with pg_trgm similarity > 0.85):**
- Fuzzy match fires
- Existing fact reinforced (not duplicated)
- `similarity('Austin Texas', 'Austin, Texas') > 0.85` — confirm this holds in staging DB

**Query to verify:**
```sql
SELECT similarity('Austin Texas', 'Austin, Texas');
-- Expected: > 0.85
```

---

### DUP-003: Non-duplicate — different predicate, same entity

**Setup:** Existing: `key='location'`, `value='Austin'`

**New input:** `"My employer is Cloudflare."` → extraction produces `key='employer'`, `value='Cloudflare'`

**Expected:** New row inserted (different key — no conflict with existing location fact)

---

### DUP-004: Non-duplicate — same predicate, meaningfully different value

**Setup:** Existing: `key='employer'`, `value='Cloudflare'`

**New extraction:** `key='employer'`, `value='StartupCo'`

**Expected:**
- New `entity_fact` row inserted (different employer — job change scenario)
- Old row not deleted or overwritten
- Both rows exist: Cloudflare (historical) and StartupCo (current)
- System does NOT reinforce; it creates a new fact

**Note:** This behavior should be documented — the pipeline does not treat "employer" as a single-value field; it accumulates facts.

---

### DUP-005: Vocabulary deduplication

**Setup:** `vocabulary` table already has `word='pgBouncer'`

**Input:** `"We use pgBouncer for connection pooling."`

**Expected:**
- `vocabulary.vote_count` incremented
- No duplicate row in `vocabulary` table

---

### DUP-006: Re-extraction of known entity ID does not create duplicate

**Setup:** Existing fact: `key='discord_id'`, `value='330189773371080716'`

**Input:** `"You know my Discord ID — 330189773371080716."`

**Expected:** Existing fact reinforced, not duplicated.

---

## Section 10 — Backward Compatibility / Issue #112 (BC)

### BC-001: Python script accepts same stdin format as shell scripts

**Verification:** Both the old `process-input.sh` and new `extract_memories.py` accept plain text via stdin:
```bash
echo "Test message" | python3 memory/scripts/extract_memories.py
```

**Expected:** Exit 0, produces JSON output. Same interface as:
```bash
echo "Test message" | bash memory/scripts/process-input.sh
```

---

### BC-002: Environment variable interface preserved

**Verification:** New Python script reads the same env vars as the old shell scripts:

| Env Var | Old Shell | New Python | Must Match |
|---|---|---|---|
| `SENDER_NAME` | ✓ | must ✓ | Yes |
| `SENDER_ID` | ✓ | must ✓ | Yes |
| `IS_GROUP` | ✓ | must ✓ | Yes |
| `SOURCE_SESSION_ID` | ✓ | must ✓ | Yes |
| `SOURCE_TIMESTAMP` | ✓ | must ✓ | Yes |
| `SOURCE_CHANNEL_TRANSCRIPT_ID` | ✓ | must ✓ | Yes |
| `SOURCE_CHANNEL_SESSION_ID` | ✓ | must ✓ | Yes |
| `OPENROUTER_API_KEY` | ✓ | must ✓ | Yes |
| `MEMORY_EXTRACTION_MODEL` | ✓ | must ✓ | Yes |

**Pass criteria:** All listed vars read by Python script; same behavior as shell counterpart when vars are set/unset.

---

### BC-003: handler.ts calls Python script at expected path

**Verification:**
```bash
grep -n 'scriptPath\|process-input\|extract_memories' memory/hooks/memory-extract/handler.ts
```

**Expected:** Script path updated to point to `extract_memories.py` (via `python3`), not `process-input.sh`. Path uses `os.homedir()` + `.openclaw/scripts/extract_memories.py` or the repo's `memory/scripts/` path (whichever is the installed location).

---

### BC-004: Existing shell scripts remain non-broken (if kept)

**If `process-input.sh`, `extract-memories.sh`, `store-memories.sh` are kept in place:**

**Expected:**
- Shell scripts still execute without error
- `bash memory/scripts/process-input.sh "test message"` exits 0
- No import errors or broken references introduced by the Python rewrite

**If shell scripts are removed:** Document removal explicitly in PR description; this TC is N/A.

---

### BC-005: JSON output schema backward-compatible

**Verification:** Python script's LLM extraction JSON uses the same top-level keys as shell script:
- `entities`, `facts`, `opinions`, `preferences`, `vocabulary`, `events`

**New keys added (additive only):**
- `decisions`, `milestones`, `problems`

**Expected:** Old consumers of the JSON (e.g., `store-memories.sh` if still called) are not broken by new keys — they must ignore unknown keys gracefully.

---

## Section 11 — Integration (INT)

### INT-001: Full pipeline via handler.ts trigger

**Setup:** Deploy updated handler.ts to staging. Send a real Discord message via the staging gateway.

**Input message (Discord):** `"Testing batch4 extraction pipeline. My fav language is Python."`

**Expected (end-to-end):**
1. Hook fires (`event.type === 'message'`, `event.action === 'received'`)
2. `ctx.content` read correctly
3. `ctx.metadata.senderName` / `ctx.metadata.senderId` populated
4. Channel transcript upserted (if message has `messageId`)
5. Python script spawned with correct env vars
6. LLM extraction returns JSON with `preferences`
7. Preference stored in `entity_facts`
8. Gateway log shows `[memory-extract] Extraction complete`

**Verification:**
```sql
SELECT key, value, source, created_at FROM entity_facts 
WHERE entity_id = (SELECT id FROM entities WHERE name = 'I)ruid')
  AND key ILIKE '%preference%' 
  AND value ILIKE '%python%'
ORDER BY created_at DESC LIMIT 5;
```

---

### INT-002: Pipeline does not block message delivery

**Expected:** The handler uses non-blocking `spawn()` (fire-and-forget). Message processing should return before extraction completes. OpenClaw gateway must not stall waiting for the child process.

**Verification:** Check handler.ts uses `spawn()` not `execFileAsync()` for the extraction subprocess call. The `child.on('close', ...)` handler is async — no `await` on child completion.

---

### INT-003: Multiple concurrent messages — no race condition

**Setup:** Simulate 3 messages arriving simultaneously (within the same second).

**Expected:**
- All 3 extraction subprocesses spawn independently
- No deadlocks on DB inserts (ON CONFLICT handles concurrent upserts)
- All 3 messages extracted and stored without corruption

---

## Pass/Fail Summary Template

For Flint to use when executing:

| TC ID | Description | Result | Notes |
|-------|-------------|--------|-------|
| HP-001 | End-to-end extraction and storage | | |
| HP-002 | Sender attribution | | |
| HP-003 | Multi-category extraction | | |
| HP-004 | New categories in LLM output | | |
| FNM-001 | ctx.content primary field | | |
| FNM-002 | metadata.senderName read correctly | | |
| FNM-003 | Fallback when metadata absent | | |
| FNM-004 | ctx.from fallback | | |
| FNM-005 | conversationId → transcript upsert | | |
| EID-001 | Phone number extraction | | |
| EID-002 | Email address extraction | | |
| EID-003 | Discord snowflake ID | | |
| EID-004 | Discord username | | |
| EID-005 | GitHub handle | | |
| EID-006 | Signal UUID | | |
| EID-007 | Multiple IDs in one message | | |
| EID-008 | Partial number not extracted | | |
| EID-009 | GitHub vs Discord disambiguation | | |
| CAT-001 | Decision extraction | | |
| CAT-002 | Preference extraction | | |
| CAT-003 | Milestone extraction | | |
| CAT-004 | Problem extraction (open) | | |
| CAT-005 | Problem extraction (solved) | | |
| CAT-006 | Existing categories still work | | |
| CAT-007 | New category storage key | | |
| EC-001 | Empty message | | |
| EC-002 | Under-10-char message (BVA 8/9/10/11) | | |
| EC-003 | Slash command skip | | |
| EC-004 | Heartbeat patterns | | |
| EC-005 | 100KB message | | |
| EC-006 | Unicode and emoji | | |
| EC-007 | SQL injection attempt | | |
| EC-008 | Emoji-only message | | |
| EC-009 | Non-English message | | |
| ERR-001 | LLM API network failure | | |
| ERR-002 | LLM API 401 | | |
| ERR-003 | Malformed JSON response | | |
| ERR-004 | Empty LLM response | | |
| ERR-005 | DB connection failure | | |
| ERR-006 | DB constraint violation | | |
| ERR-007 | Missing OPENROUTER_API_KEY | | |
| SMF-001 | Handler-level short filter | | |
| SMF-002 | Python-level short filter | | |
| SMF-003 | Whitespace-only message | | |
| PRV-001 | Default visibility from DB | | |
| PRV-002 | Explicit public override | | |
| PRV-003 | Explicit private override | | |
| PRV-004 | Unknown sender default | | |
| PRV-005 | Phone always private | | |
| DUP-001 | Exact duplicate reinforced | | |
| DUP-002 | Fuzzy duplicate reinforced | | |
| DUP-003 | Different predicate, no conflict | | |
| DUP-004 | Same predicate, different value | | |
| DUP-005 | Vocabulary deduplication | | |
| DUP-006 | Entity ID deduplication | | |
| BC-001 | Python accepts same stdin interface | | |
| BC-002 | Env var interface preserved | | |
| BC-003 | handler.ts calls Python at correct path | | |
| BC-004 | Shell scripts still work (if kept) | | |
| BC-005 | JSON output schema backward-compatible | | |
| INT-001 | Full pipeline via handler trigger | | |
| INT-002 | Pipeline non-blocking | | |
| INT-003 | Concurrent messages, no race | | |

---

## Known Risks & Design Questions

1. **Phone number visibility (PRV-005):** The extraction prompt should hard-code `visibility='private'` for phone numbers regardless of default_visibility. Needs explicit prompt engineering — verify this is in the new prompt.

2. **DUP-004 (multiple employer facts):** Current design accumulates facts rather than replacing. This is correct for historical accuracy but may confuse recall. Flag as P2 design review item if it causes issues.

3. **EC-002 boundary (10 chars):** The current guard is `< 10`. Confirm with Coder whether 10 is inclusive or exclusive. Test both 9 and 10 chars explicitly.

4. **ERR-003 (malformed JSON):** The Python script must NOT fall through and call `store-memories.sh` with garbage input. Confirm JSON validation happens before any DB write.

5. **CAT-007 (storage key for new categories):** Implementation must define and document the storage key scheme. Flint cannot verify DB storage without knowing the target key. Coder must confirm before test execution.

6. **INT-003 (concurrent messages):** PostgreSQL `ON CONFLICT DO NOTHING` handles concurrent upserts safely for new inserts, but `reinforce_fact()` uses a plain `UPDATE` — concurrent reinforcement could cause lost update. Flag as P3 race condition if load ever exceeds 3 concurrent messages/second.
