# Test Cases: Sub-batch 4a — Entity Ghost Prevention & Deduplication
**Issues:** #230 (ghost entity filtering) + #267 (alternate_spellings column)
**Files under test:**
- `~/.openclaw/scripts/extract_memories.py`
- `~/workspace/nova-mind/relationships/lib/entity-resolver/resolver.ts`
- Schema migration adding `entities.alternate_spellings text[]`

---

## Root Causes Being Fixed

| # | Root Cause | Location |
|---|-----------|----------|
| RC-1 | Structural heuristics missing — implausible names created unconditionally | `ensure_entity()` call in `_store_fact()` |
| RC-2 | Weak matching — only exact name/full_name/nicknames; no alternate_spellings, substring, domain-stripping | `find_entity_id()` |
| RC-3 | Type blindness — `_store_fact()` hardcodes `"person"` type regardless of LLM entities array | `_store_fact()` → `ensure_entity()` |
| RC-4 | Fragmentation via type divergence — `UNIQUE(name, type)` allows same name to exist under different types | `ensure_entity()` — does not check for name-only collision before inserting |

---

## Section A: Layer 1 — Structural Heuristic Rejection (`is_plausible_entity()`)

New function `is_plausible_entity(name: str) -> bool` must be called before any `ensure_entity()` creation. Returns `False` → skip, do not create.

### A1 — Env var pattern rejection

| ID | Input name | Expected | Rationale |
|----|-----------|----------|-----------|
| A1-1 | `NOVA_DOCUMENTATION_HAIKU` | reject | ALL_CAPS + underscores, 3 segments |
| A1-2 | `SENDER_PROVIDER` | reject | ALL_CAPS + underscores, 2 segments |
| A1-3 | `SOURCE_CHANNEL_TRANSCRIPT_ID` | reject | ALL_CAPS + underscores, 4 segments |
| A1-4 | `OPENROUTER_API_KEY` | reject | ALL_CAPS + underscores |
| A1-5 | `NOVA` | **pass** | ALL_CAPS but no underscore — legitimate entity name |
| A1-6 | `VALID` | **pass** | ALL_CAPS but no underscore |
| A1-7 | `AI` | **pass** | ALL_CAPS, no underscore, short but common abbreviation |

### A2 — File path / filename rejection

| ID | Input name | Expected | Rationale |
|----|-----------|----------|-----------|
| A2-1 | `SOUL.md` | reject | Ends with `.md` |
| A2-2 | `handler.ts` | reject | Ends with `.ts` |
| A2-3 | `memory-extraction-config.json` | reject | Ends with `.json` |
| A2-4 | `extract_memories.py` | reject | Ends with `.py` |
| A2-5 | `/home/nova/.openclaw/scripts/foo.py` | reject | Contains `/` (absolute path) |
| A2-6 | `scripts/foo.sh` | reject | Contains `/` (relative path) |
| A2-7 | `IDENTITY.md` | reject | Ends with `.md` (even if all-caps) |
| A2-8 | `README` | **pass** | No extension, no path separator — ambiguous but not a clear artifact; callers can decide |

### A3 — DB artifact marker rejection

| ID | Input name | Expected | Rationale |
|----|-----------|----------|-----------|
| A3-1 | `Unknown user: 330189773371080716` | reject | Matches `Unknown user:` prefix |
| A3-2 | `Unknown user: graybeard` | reject | Matches `Unknown user:` prefix |
| A3-3 | `Cognition System (id=9)` | reject | Contains `(id=N)` pattern |
| A3-4 | `Full System (id=10)` | reject | Contains `(id=N)` pattern |
| A3-5 | `NOVA Multiuser System (project #28)` | reject | Contains `(project #N)` pattern |
| A3-6 | `agents table` | reject | Ends with word `table` |
| A3-7 | `workflows table` | reject | Ends with word `table` |
| A3-8 | `agent_chat table` | reject | Ends with word `table` |
| A3-9 | `nova_staging DB role` | reject | Contains `DB role` |
| A3-10 | `nova-staging DB role` | reject | Contains `DB role` |
| A3-11 | `Round Table` | **pass** | "table" as part of a name, not trailing word; known venue/concept. Note: implementation must match whole trailing word, not substring. |
| A3-12 | `Google Drive — Edmund's Edification` | reject | Contains em dash `—`; compound description, not a name |
| A3-13 | `Sender (I)ruid)` | reject | Matches `Sender (...)` artifact pattern |
| A3-14 | `the group (including sender)` | reject | Generic phrase + parenthetical |

### A4 — Generic role word / pronoun rejection

| ID | Input name | Expected | Rationale |
|----|-----------|----------|-----------|
| A4-1 | `sender` | reject | Generic role word |
| A4-2 | `Sender` | reject | Case-insensitive match |
| A4-3 | `recipient` | reject | Generic role word |
| A4-4 | `the recipient` | reject | Generic role phrase |
| A4-5 | `the sender` | reject | Generic role phrase |
| A4-6 | `system` | reject | Generic role word |
| A4-7 | `user` | reject | Generic role word |
| A4-8 | `plugin` | reject | Technical generic noun |
| A4-9 | `the group` | reject | Generic collective noun |
| A4-10 | `the team` | reject | Generic collective noun |
| A4-11 | `nova_staging_memory` | reject | Looks like a DB name (underscores + `_memory` suffix) |
| A4-12 | `agent_bootstrap_context` | reject | All-lowercase underscored identifier |

### A5 — Must NOT reject legitimate entities

| ID | Input name | Expected | Rationale |
|----|-----------|----------|-----------|
| A5-1 | `John Smith` | pass | Normal person name |
| A5-2 | `Rayven` | pass | Real person, unusual spelling |
| A5-3 | `Trammell Ventures` | pass | Legitimate org |
| A5-4 | `Gargantuan Art Car` | pass | Legitimate named thing |
| A5-5 | `Blockhenge` | pass | Legitimate org name |
| A5-6 | `I)ruid` | pass | Handle with special char — known alias |
| A5-7 | `nova-mind` | pass | Repo/project name — borderline but a real project entity |
| A5-8 | `OpenClaw` | pass | Product name |
| A5-9 | `wearevalid.ai` | pass | Domain name — structural heuristics should NOT reject domains at layer 1 (layer 2 handles matching them to parent entities) |
| A5-10 | `roguesignal.io` | pass | Same — domain, handled at layer 2 |
| A5-11 | `Dustin D. Trammell` | pass | Full legal name with punctuation |
| A5-12 | `CoinBase` | pass | Mixed-case brand name |
| A5-13 | `Über` | pass | Unicode in name |
| A5-14 | `DJ Khaled` | pass | Common name pattern |

---

## Section B: Layer 2 — Smarter `find_entity_id()` Matching

### B1 — alternate_spellings matching (new column, #267)

**Precondition:** Entity "Rayven" (id=6) exists with `alternate_spellings = ['raven', 'ravens', 'Raven']`

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B1-1 | `Raven` | matches id=6 | In alternate_spellings (case-sensitive match) |
| B1-2 | `raven` | matches id=6 | Case-insensitive alternate_spellings match |
| B1-3 | `ravens` | matches id=6 | In alternate_spellings |
| B1-4 | `RAVEN` | matches id=6 | Case-insensitive |
| B1-5 | `Rayven` | matches id=6 | Original name match (existing behavior) |
| B1-6 | `RavenX` | **no match** | Not in spellings, not a name match — new entity if plausible |

**Precondition:** Entity "Dustin" (id=2) exists with `alternate_spellings = ['I)ruid', 'Druid', 'dustin']` and `nicknames = ['I)ruid']`

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B1-7 | `I)ruid` | matches id=2 | In both nicknames AND alternate_spellings |
| B1-8 | `Druid` | matches id=2 | In alternate_spellings |
| B1-9 | `dustin` | matches id=2 | Case-insensitive + alternate_spellings |

### B2 — Domain-name-to-entity matching

**Precondition:** Entity "Rogue Signal" (id=11, type=organization) exists

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B2-1 | `roguesignal.io` | matches id=11 | Strip TLD → "roguesignal" → normalized "roguesignal" matches normalized "Rogue Signal" (remove spaces/hyphens, lowercase) |
| B2-2 | `roguesignal.com` | matches id=11 | Different TLD, same base |
| B2-3 | `www.roguesignal.io` | matches id=11 | Strip www prefix + TLD |

**Precondition:** Entity "Renaissance Machine" (id=5384, type=organization) exists

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B2-4 | `renaissancemachine.ai` | matches id=5384 | Strip TLD → matches normalized org name |
| B2-5 | `renaissancemachine.com` | matches id=5384 | Different TLD |

**Precondition:** Entity "VALID" (id=3450, type=organization) exists

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B2-6 | `VALID.ai` | matches id=3450 | Strip TLD → "VALID" → case-insensitive name match |
| B2-7 | `valid.ai` | matches id=3450 | Lowercase + strip TLD |

**No false positives:**

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B2-8 | `example.com` | no match | Generic domain, no entity named "example" |
| B2-9 | `localhost` | no match | Technical hostname, no match + should fail heuristics |

### B3 — Substring/containment matching

**Precondition:** Entity "VALID" exists (id=3450)

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B3-1 | `VALID movement` | matches id=3450 | "VALID" is a contained substring (leading word match) |
| B3-2 | `the VALID movement` | matches id=3450 | "VALID" appears as a word within the phrase |

**Important: substring matching must avoid false positives**

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B3-3 | `invalid.io` | **no match** to "VALID" | "valid" appears inside "invalid" — must match whole-word only |
| B3-4 | `Mark Smith` | **no match** to any entity named "Mark" | Only match if full entity name appears as a whole word/segment |

### B4 — Case-insensitive name matching (existing behavior, must still work)

**Precondition:** Entity "OpenClaw" (type=organization) exists

| ID | Input subject | Expected | Rationale |
|----|--------------|----------|-----------|
| B4-1 | `openclaw` | matches OpenClaw | Case-insensitive name |
| B4-2 | `OPENCLAW` | matches OpenClaw | All-caps variant |
| B4-3 | `OpenClaw` | matches OpenClaw | Exact match |

### B5 — Name-only collision detection (prevents RC-4 fragmentation)

**Precondition:** Entity "VALID" (type=person, id=3428) exists

| ID | Input | Expected | Rationale |
|----|-------|----------|-----------|
| B5-1 | `ensure_entity("VALID", "organization")` called | Returns id=3428, does NOT create a second entity | `find_entity_id` should match case-insensitively on name alone BEFORE insert; `ensure_entity` must check for any name collision (regardless of type) before inserting |
| B5-2 | `ensure_entity("valid", "ai")` called | Returns existing VALID entity id | Case-insensitive name-only check in ensure_entity |
| B5-3 | `ensure_entity("VALID", "person")` called when VALID/person exists | Returns id=3428 (existing) — no duplicate | ON CONFLICT handles same (name, type), existing behavior |

---

## Section C: Type Resolution Fix (`_store_fact()` + `ensure_entity()`)

**The fix:** Before the facts loop, build `entity_type_map: dict[str, str]` from `data["entities"]`. In `_store_fact()`, look up the subject in `entity_type_map` before falling back to `"person"`.

### C1 — Correct type from entities array

| ID | LLM entities array | Fact subject | Expected type on creation | Notes |
|----|-------------------|-------------|--------------------------|-------|
| C1-1 | `[{"name": "OpenClaw", "type": "organization"}]` | `"OpenClaw"` | `organization` | Type from entities array |
| C1-2 | `[{"name": "Cadence", "type": "ai"}]` | `"Cadence"` | `ai` | Type from entities array |
| C1-3 | `[{"name": "Blockhenge", "type": "organization"}]` | `"blockhenge"` | `organization` | Case-insensitive lookup in entity_type_map |
| C1-4 | `[{"name": "VALID", "type": "organization"}]` | `"VALID.ai"` | Matches existing "VALID" via layer 2; no creation needed | Domain matches existing entity |

### C2 — Subject not in entities array

| ID | LLM entities array | Fact subject | Expected behavior | Notes |
|----|-------------------|-------------|------------------|-------|
| C2-1 | `[]` (empty) | `"Sarah"` (new person) | Passes heuristics → create as `"person"` (safe default) | Legitimate new person mentioned only in facts |
| C2-2 | `[]` | `"workflows table"` | Fails heuristics (layer 1 A3-6) → skip, no creation | |
| C2-3 | `[{"name": "Newbury", "type": "person"}]` | `"Newbury"` | Matches entity_type_map → create as `"person"` | Explicit type from LLM |
| C2-4 | `[]` | `"NOVA_DOCUMENTATION_HAIKU"` | Fails heuristics (A1-1) → skip | |

### C3 — Type normalization (existing behavior, must still work)

| ID | LLM type | Expected normalized type | Notes |
|----|---------|------------------------|-------|
| C3-1 | `"place"` | `"other"` | PLACE_TYPES mapping |
| C3-2 | `"restaurant"` | `"other"` | PLACE_TYPES mapping |
| C3-3 | `"person"` | `"person"` | Valid, pass-through |
| C3-4 | `"garbage_type"` | `"other"` | Unknown type → other |
| C3-5 | `"PERSON"` | `"person"` | Case normalization |

---

## Section D: Schema Migration — `entities.alternate_spellings text[]`

### D1 — Column existence and type

| ID | Check | Expected |
|----|-------|----------|
| D1-1 | `SELECT column_name, data_type FROM information_schema.columns WHERE table_name='entities' AND column_name='alternate_spellings'` | Returns row: `alternate_spellings`, `ARRAY` |
| D1-2 | Column is nullable | `is_nullable = 'YES'` |
| D1-3 | Default value | NULL (no default) |
| D1-4 | `ALTER TABLE` in migration is idempotent | Re-running migration does not error; column already exists check |

### D2 — Column usability

| ID | Operation | Expected |
|----|-----------|----------|
| D2-1 | `UPDATE entities SET alternate_spellings = ARRAY['raven','ravens'] WHERE id = 6` | Succeeds |
| D2-2 | `SELECT * FROM entities WHERE LOWER('raven') = ANY(SELECT LOWER(unnest(alternate_spellings)))` | Returns the Rayven row |
| D2-3 | `UPDATE entities SET alternate_spellings = alternate_spellings || ARRAY['new_spelling']` | Array append works |
| D2-4 | Existing entities with NULL alternate_spellings unaffected | No rows modified by migration beyond column addition |

---

## Section E: `resolver.ts` — alternate_spellings Wiring

The `resolver.ts` library currently resolves entities only by platform identifiers (phone, UUID, discord_id, etc.) — not by name. The `alternate_spellings` column is relevant for any name-based lookup path.

### E1 — Name-based resolution (if added)

If a `resolveEntityByName(name: string)` function is added to `resolver.ts`:

| ID | Precondition | Input | Expected |
|----|-------------|-------|----------|
| E1-1 | Entity "Rayven" has `alternate_spellings = ['raven']` | `resolveEntityByName("raven")` | Returns Rayven entity |
| E1-2 | Entity "Dustin" has `alternate_spellings = ['I)ruid']` | `resolveEntityByName("I)ruid")` | Returns Dustin entity |
| E1-3 | No entity has alternate_spelling "xyz123" | `resolveEntityByName("xyz123")` | Returns null |

### E2 — Existing identifier-based resolution unaffected

| ID | Test | Expected |
|----|------|----------|
| E2-1 | `resolveEntity({ phone: "+15125551234" })` | Still resolves correctly (no regression) |
| E2-2 | `resolveEntity({ discordId: "330189773371080716" })` | Still resolves correctly |
| E2-3 | `resolveEntityByIdentifiers({ email: "test@example.com" })` | Still resolves correctly |

---

## Section F: End-to-End Pipeline Integration Tests

These test the full `store_extracted()` flow with a mocked LLM response, real DB connection.

### F1 — Ghost entity not created for role word

```
Input LLM response:
  facts: [{ subject: "sender", key: "action", value: "sent a message" }]
  entities: []
Expected: No entity named "sender" created. Fact skipped.
```

### F2 — Ghost entity not created for DB table name

```
Input LLM response:
  facts: [{ subject: "agent_bootstrap_context", key: "description", value: "stores bootstrap data" }]
  entities: [{ name: "agent_bootstrap_context", type: "other" }]
Expected: is_plausible_entity("agent_bootstrap_context") → False. Neither entity nor fact created.
```

### F3 — Fragment prevention: VALID.ai routes to existing VALID entity

```
Precondition: entity "VALID" (type=organization, id=3450) exists.
Input LLM response:
  facts: [{ subject: "VALID.ai", key: "purpose", value: "AI rights movement" }]
  entities: [{ name: "VALID.ai", type: "organization" }]
Expected:
  - find_entity_id("VALID.ai") → strips TLD "ai" → matches "VALID" (id=3450)
  - Fact stored against entity id=3450, NOT a new entity
  - No new entity "VALID.ai" created
```

### F4 — Fragment prevention: roguesignal.io routes to Rogue Signal

```
Precondition: entity "Rogue Signal" (id=11) exists.
Input LLM response:
  entities: [{ name: "roguesignal.io", type: "organization" }]
Expected:
  - ensure_entity("roguesignal.io", "organization") calls find_entity_id first
  - find_entity_id → domain match → returns id=11
  - No new entity created
```

### F5 — File artifact not stored

```
Input LLM response:
  facts: [{ subject: "SOUL.md", key: "purpose", value: "stores NOVA's soul" }]
  entities: [{ name: "SOUL.md", type: "other" }]
Expected: is_plausible_entity("SOUL.md") → False. Both entity and fact skipped.
```

### F6 — Unknown user Discord artifact not stored

```
Input LLM response:
  entities: [{ name: "Unknown user: 330189773371080716", type: "person" }]
  facts: [{ subject: "Unknown user: 330189773371080716", key: "action", value: "reacted" }]
Expected: is_plausible_entity → False. Neither created.
```

### F7 — Alternate spelling prevents Rayven fragmentation

```
Precondition: entity "Rayven" (id=6) with alternate_spellings=['raven','ravens','Raven'].
Input LLM response:
  entities: [{ name: "Raven", type: "person" }]
  facts: [{ subject: "Raven", key: "relationship", value: "friend" }]
Expected:
  - find_entity_id("Raven") → alternate_spellings match → id=6
  - Fact stored against id=6
  - No new entity "Raven" created
```

### F8 — Legitimate new entity IS created

```
Precondition: No entity named "Newbury" exists.
Input LLM response:
  entities: [{ name: "Newbury", type: "person" }]
  facts: [{ subject: "Newbury", key: "relationship", value: "new contact" }]
Expected:
  - is_plausible_entity("Newbury") → True
  - find_entity_id("Newbury") → None (not in DB)
  - ensure_entity("Newbury", "person") → creates new entity
  - Fact stored against new entity id
```

### F9 — Type from entities array used, not "person"

```
Precondition: No entity named "AcmeCorp" exists.
Input LLM response:
  entities: [{ name: "AcmeCorp", type: "organization" }]
  facts: [{ subject: "AcmeCorp", key: "industry", value: "software" }]
Expected:
  - Entity created with type "organization" (not "person")
  - Fact stored against new entity
```

### F10 — Name-only collision: existing entity returned regardless of type mismatch

```
Precondition: Entity "VALID" (type=person, id=3428) exists.
Input LLM response:
  entities: [{ name: "VALID", type: "organization" }]
Expected:
  - find_entity_id("VALID") → id=3428 (existing, case-insensitive name match)
  - ensure_entity checks name-only collision → returns id=3428
  - No second entity "VALID" (organization) created
```

### F11 — In-batch entity deduplication: two names resolving to the same entity

```
Precondition: Entity "VALID" (type=organization, id=3450) exists.
Input LLM response:
  entities: [{ name: "VALID", type: "organization" }, { name: "VALID.ai", type: "organization" }]
  facts: [
    { subject: "VALID", key: "mission", value: "AI dignity" },
    { subject: "VALID.ai", key: "domain", value: "wearevalid.ai" }
  ]
Expected:
  - "VALID" → find_entity_id matches id=3450
  - "VALID.ai" → find_entity_id strips TLD → domain match → id=3450
  - Only ONE entity record (id=3450) exists after processing
  - Both facts stored against id=3450
  - No new entity created for either name
```

### F12 — Similar but distinct entities: not falsely collapsed

```
Precondition: No entities named "Mark Smith" or "Mark Johnson" exist.
Input LLM response:
  entities: [{ name: "Mark Smith", type: "person" }, { name: "Mark Johnson", type: "person" }]
  facts: [
    { subject: "Mark Smith", key: "role", value: "engineer" },
    { subject: "Mark Johnson", key: "role", value: "designer" }
  ]
Expected:
  - Both pass is_plausible_entity()
  - find_entity_id("Mark Smith") → None → creates new entity
  - find_entity_id("Mark Johnson") → None → creates separate new entity
  - Two distinct entities created, each with their own fact
  - "Mark Smith" entity NOT collapsed into "Mark Johnson" or vice versa
```

---

## Section G: Edge Cases

| ID | Input | Expected | Notes |
|----|-------|----------|-------|
| G1 | Empty string `""` | skip | Existing null/empty guard |
| G2 | Whitespace only `"   "` | skip | Strip + empty check |
| G3 | `"null"` | skip | Existing guard |
| G4 | `"unknown"` | skip | Existing guard |
| G5 | Name with 1 character `"A"` | reject | Too short to be a meaningful entity name |
| G6 | Name with 2 characters `"AI"` | pass | Known abbreviation pattern; don't over-filter |
| G7 | Very long name (>100 chars) | implementation choice: pass or cap | At minimum, don't crash |
| G8 | Name with only digits `"12345"` | reject | Likely an ID or artifact |
| G9 | Name with only digits and hyphens `"330189773371080716"` | reject | Discord snowflake surfaced as entity name |
| G10 | Unicode name `"Ångström"` | pass | Valid person/place name |
| G11 | Name with trailing/leading whitespace `"  John  "` | Normalize to `"John"`, then evaluate | Strip before heuristics |
| G12 | `alternate_spellings = NULL` (most entities) | No error; gracefully skips alternate_spellings check | `ANY(unnest(NULL))` must be handled safely in SQL |
| G13 | `alternate_spellings = []` (empty array) | No match, no error | Empty array edge case |
| G14 | Subject name = sender name | Resolves via platform ID first (existing behavior) | Priority order preserved |
| G15 | Domain with subdomain: `"app.blockhenge.com"` | Should match "Blockhenge" after stripping `app.` prefix and `.com` TLD | Multi-part domain stripping |
| G16 | `is_plausible_entity` called with `None` | Returns False / does not raise | Defensive coding |

---

## Section H: Regression Tests (Must Still Work)

These cover existing behaviors that must not break.

| ID | Scenario | Expected | Notes |
|----|---------|----------|-------|
| H1 | Sender entity creation on first message | Sender entity created with correct type | `ensure_entity(sender_name, "person")` in main() still works |
| H2 | Phone number stored as private | `visibility="private"` hard rule still enforced | Not affected by entity changes |
| H3 | Fact reinforcement (exact match) | `extraction_count` incremented, no duplicate | `find_existing_fact()` unchanged |
| H4 | Fuzzy fact deduplication (pg_trgm > 0.85) | Reinforces instead of creates duplicate | `find_existing_fact()` fuzzy path |
| H5 | Events stored correctly | Event inserted to `events` table | Unaffected code path |
| H6 | Vocabulary stored / reinforced | `vocabulary` table updated | Unaffected code path |
| H7 | Platform ID resolution takes priority over name | sender_id match beats name match | Priority ordering in `find_entity_id()` |
| H8 | `resolveEntity` by phone still works | Existing resolver behavior | `resolver.ts` regression |
| H9 | `resolveEntityByIdentifiers` conflict detection | Returns conflict object when two entities match | `resolver.ts` regression |
| H10 | `getEntityProfile` returns canonical keys | Profile keys returned correctly | `resolver.ts` regression |
| H11 | Empty LLM response `{}` | Pipeline exits 0, nothing stored | Existing empty-response handling |
| H12 | DB connection failure | Pipeline exits 1 with error message | Existing error path |
| H13 | Entity with `nicknames` already set | Nickname matching still works alongside new alternate_spellings | Both arrays checked |
| H14 | Multiple facts for same subject in one LLM response | All stored under same entity | No creation race condition |
| H15 | `normalize_entity_type("place")` → `"other"` | Still returns "other" | Type normalization untouched |

---

## Implementation Notes for Coder

### New function signature
```python
def is_plausible_entity(name: str) -> bool:
    """Return True if name is a plausible entity worth creating. False = skip."""
```
Call site: anywhere `ensure_entity()` would create a new row (both in the entities loop and in `_store_fact()`).

### `find_entity_id()` query additions
The existing name/full_name/nicknames query should be extended to also check:
```sql
-- Add to WHERE clause:
OR LOWER(%s) = ANY(SELECT LOWER(unnest(alternate_spellings)))
```
And add domain/substring matching as Python pre-processing before the SQL query (strip TLD, normalize).

### `ensure_entity()` name-collision guard
Before the INSERT, add a name-only lookup:
```python
# Check for any existing entity with this name (case-insensitive), regardless of type
cur.execute("SELECT id FROM entities WHERE LOWER(name) = LOWER(%s) LIMIT 1", (name,))
row = cur.fetchone()
if row:
    return row[0]
# Only then proceed to INSERT
```

### Entity type map in `store_extracted()`
```python
# Build before the facts loop
entity_type_map: dict[str, str] = {
    (ent.get("name") or "").strip().lower(): normalize_entity_type(ent.get("type") or "other")
    for ent in (data.get("entities") or [])
    if ent.get("name")
}
```
Pass to `_store_fact()` and use for type lookup before defaulting to `"person"`.

### `resolver.ts` note
`resolver.ts` currently has no name-based resolution path — it resolves by platform identifiers only. If a `resolveEntityByName()` function is added, it should include `alternate_spellings` in the query (see E1). If no name-based function is being added in this batch, `resolver.ts` changes are limited to ensuring the schema migration doesn't break existing queries (it won't — adding a nullable column is backward compatible).

---

## Acceptance Criteria Summary

1. ✅ `is_plausible_entity()` rejects all patterns in sections A1–A4
2. ✅ `is_plausible_entity()` passes all legitimate entities in A5
3. ✅ `find_entity_id()` matches via `alternate_spellings` (B1)
4. ✅ `find_entity_id()` matches via domain-to-entity normalization (B2)
5. ✅ `find_entity_id()` matches via whole-word substring/containment (B3), no false positives
6. ✅ `ensure_entity()` does name-only collision check before INSERT (B5)
7. ✅ Entity type from LLM entities array used instead of hardcoded "person" (C1)
8. ✅ `entities.alternate_spellings text[]` column exists, nullable, queryable (D1–D2)
9. ✅ All end-to-end pipeline tests pass (F1–F10)
10. ✅ All edge cases handled without crashes (G1–G16)
11. ✅ All regression tests pass (H1–H15)
