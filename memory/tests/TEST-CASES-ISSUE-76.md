# Test Cases: Issue #76 - resolveAgentName() Returns Empty for Valid Agents

**Issue:** nova-memory#76  
**Bug:** resolveAgentName() function returns empty for valid agents  
**File:** channel.ts  
**Function:** `resolveAgentName()`  
**Date:** 2026-02-13

---

## Problem

The `resolveAgentName()` function in `channel.ts` should resolve agent identifiers (name, nickname, or alias) to the canonical agent name, but it's returning empty results for valid agents.

The function should:
1. Match direct agent names (case-insensitive)
2. Match nicknames (case-insensitive)
3. Match aliases from agent_aliases table (case-insensitive)
4. Return the canonical agent name from the `agents.name` field
5. Return empty/null ONLY for truly non-existent agents

---

## Test Case 1: Resolve by Direct Name

**ID:** TC-76-001  
**Priority:** Critical

**Given:** 
- Agent exists in database with name "newhart"

**When:** 
- `resolveAgentName(client, "newhart")` is called

**Then:**
- Returns "newhart"
- No error is thrown

**Variations:**
- "newhart" → "newhart" ✓
- "NEWHART" → "newhart" ✓ (case-insensitive)
- "Newhart" → "newhart" ✓ (case-insensitive)

---

## Test Case 2: Resolve by Nickname

**ID:** TC-76-002  
**Priority:** Critical

**Given:**
- Agent exists with:
  - `name`: "newhart"
  - `nickname`: "Newhart"

**When:**
- `resolveAgentName(client, "Newhart")` is called

**Then:**
- Returns "newhart" (the canonical name)
- Nickname matching is case-insensitive

**Variations:**
- "Newhart" → "newhart" ✓
- "newhart" → "newhart" ✓
- "NEWHART" → "newhart" ✓

---

## Test Case 3: Resolve by Alias

**ID:** TC-76-003  
**Priority:** High

**Given:**
- Agent "newhart" has aliases:
  - "bob" (from agent_aliases table)
  - "newhart-bot" (from agent_aliases table)

**When:**
- `resolveAgentName(client, "bob")` is called

**Then:**
- Returns "newhart"
- Alias matching is case-insensitive

**Variations:**
- "bob" → "newhart" ✓
- "BOB" → "newhart" ✓
- "newhart-bot" → "newhart" ✓
- "NEWHART-BOT" → "newhart" ✓

---

## Test Case 4: Non-existent Agent Handling

**ID:** TC-76-004  
**Priority:** High

**Given:**
- No agent exists with name/nickname/alias "ghost-agent"

**When:**
- `resolveAgentName(client, "ghost-agent")` is called

**Then:**
- Throws error with message: "Agent not found: ghost-agent"
- Does NOT return empty string
- Error message is helpful for debugging

---

## Test Case 5: Empty/Whitespace Input

**ID:** TC-76-005  
**Priority:** Medium

**Given:**
- Function receives empty or whitespace-only input

**When:**
- `resolveAgentName(client, "")` is called
- `resolveAgentName(client, "   ")` is called

**Then:**
- Throws error: "Target cannot be empty"
- Does NOT query database
- Fails fast

---

## Test Case 6: Multiple Agents with Similar Names

**ID:** TC-76-006  
**Priority:** Medium

**Given:**
- Agent "test-agent-1" exists
- Agent "test-agent-2" exists
- Agent "test-agent-1" has nickname "Tester"

**When:**
- `resolveAgentName(client, "Tester")` is called

**Then:**
- Returns exactly "test-agent-1"
- Does NOT return multiple results
- LIMIT 1 ensures only one result

---

## Current Implementation Analysis

### Function Location
```typescript
// File: channel.ts
// Lines: ~113-143
async function resolveAgentName(client: pg.Client, target: string): Promise<string>
```

### SQL Query
```sql
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = $1
  OR LOWER(a.nickname) = $1
  OR LOWER(aa.alias) = $1
LIMIT 1
```

### Potential Issues to Check

1. **Parameter binding**: Is `$1` correctly bound to `normalizedTarget`?
2. **NULL handling**: Are NULL nicknames handled properly in the WHERE clause?
3. **Case sensitivity**: LOWER() functions applied correctly on both sides?
4. **Join type**: Should LEFT JOIN be INNER JOIN for aliases?
5. **Empty result handling**: Is `result.rows[0]` check sufficient?

---

## Debugging Tests

### Test Query Directly
```bash
# Test the SQL query directly
psql -U nova -d nova_memory -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('Newhart')
  OR LOWER(a.nickname) = LOWER('Newhart')
  OR LOWER(aa.alias) = LOWER('Newhart')
LIMIT 1;
"
```

### Test with Various Inputs
```typescript
// Test cases to run
await resolveAgentName(client, "newhart");    // Should return "newhart"
await resolveAgentName(client, "Newhart");      // Should return "newhart"
await resolveAgentName(client, "NEWHART");      // Should return "newhart"
await resolveAgentName(client, "bob");          // Should return "newhart" (if alias exists)
await resolveAgentName(client, "nonexistent");  // Should throw error
await resolveAgentName(client, "");             // Should throw "Target cannot be empty"
```

---

## Expected Fix

The issue is likely in one of these areas:
1. Query not matching case-insensitively on all fields
2. NULL values in nickname/alias causing comparison failures
3. Parameter not being passed correctly
4. Result not being returned properly

The function should work correctly for all valid identifier types and only fail for truly non-existent agents.

---

## Acceptance Criteria

- [ ] Resolves agent by direct name (case-insensitive)
- [ ] Resolves agent by nickname (case-insensitive)
- [ ] Resolves agent by alias (case-insensitive)
- [ ] Returns canonical agent name (agents.name field)
- [ ] Throws helpful error for non-existent agents
- [ ] Handles empty/whitespace input gracefully
- [ ] Works with NULL nicknames
- [ ] Returns only one result when multiple identifiers match same agent
