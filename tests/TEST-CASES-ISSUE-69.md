# Test Cases for Issue #69: Case-Insensitive Agent Matching in agent_chat

**Issue**: Enhancement: agent_chat should match on both agent_id and agent name (case-insensitive)

**Requirements**:
- agent_chat message routing should match on multiple identifiers (not just exact agentName from config)
- All matching should be case-insensitive
- Should match on: agentName from config, agent name from database, aliases

---

## Test Case 1: Case-Insensitive Matching on agentName (Config)

**Given**:
- Agent exists with `agentName: "Nova"` in config
- Agent is registered in the database

**When**:
- User sends message: "@nova how are you?"
- User sends message: "@NOVA what's the weather?"
- User sends message: "@NoVa remind me tomorrow"

**Then**:
- All three messages should be routed to the Nova agent
- Agent receives messages with normalized mention format
- No messages are dropped or misrouted

---

## Test Case 2: Case-Insensitive Matching on agentName with Different Cases

**Given**:
- Agent exists with `agentName: "CodeHelper"` in config

**When**:
- User sends: "@codehelper review this"
- User sends: "@CODEHELPER check syntax"
- User sends: "@CodeHelper optimize this"
- User sends: "@coDEheLPer fix bugs"

**Then**:
- All four messages route to CodeHelper agent
- Matching is case-insensitive throughout
- Agent identifier normalization preserves routing

---

## Test Case 3: Matching on Database Agent Name (Different from Config agentName)

**Given**:
- Agent config has `agentName: "assistant_bot"`
- Database stores agent name as "Assistant Bot" (space, title case)
- Both identifiers refer to the same agent

**When**:
- User sends: "@assistant_bot help me"
- User sends: "@Assistant Bot help me"
- User sends: "@ASSISTANT BOT urgent task"
- User sends: "@assistant bot daily report"

**Then**:
- All four messages route to the same agent
- System matches both the config name and database name
- Case variations of both names are handled correctly

---

## Test Case 4: Mixed Case Mentions Delivered Correctly

**Given**:
- Agent exists with `agentName: "DataAnalyzer"`
- Agent has database name "data-analyzer"

**When**:
- User sends: "@dataanalyzer process this"
- User sends: "@DataAnalyzer summarize data"
- User sends: "@data-analyzer export report"
- User sends: "@DATA-ANALYZER quick stats"

**Then**:
- All messages route to DataAnalyzer agent
- Mixed case in mentions doesn't break routing
- Both naming conventions (camelCase and kebab-case) are matched

---

## Test Case 5: Agent with Multiple Aliases Receives All Mentions

**Given**:
- Agent config has `agentName: "Nova"`
- Agent has aliases: ["assistant", "helper", "ai"]
- All stored in lowercase in alias table

**When**:
- User sends: "@nova schedule meeting"
- User sends: "@assistant what's my calendar?"
- User sends: "@HELPER remind me"
- User sends: "@AI summarize this"
- User sends: "@Assistant check email"

**Then**:
- All five messages route to Nova agent
- Each alias is matched case-insensitively
- Agent receives messages regardless of which identifier was used

---

## Test Case 6: Non-Matching Mentions Are Not Misrouted

**Given**:
- Agent exists with `agentName: "Nova"`
- Agent has aliases: ["assistant"]
- No agent named "Bob", "Support", or "Random"

**When**:
- User sends: "@bob help with this"
- User sends: "@Support urgent issue"
- User sends: "@random question"
- User sends: "@Nova123 invalid"

**Then**:
- None of these messages route to Nova agent
- System logs unmatched mentions (if applicable)
- No false-positive matches occur
- Messages may go to default handler or remain unrouted

---

## Test Case 7: Lowercase Normalization on Sender Side

**Given**:
- Agent exists with `agentName: "TaskManager"`
- Message routing normalizes identifiers before matching

**When**:
- Sender mentions: "@TASKMANAGER complete task"
- System normalizes to: "@taskmanager complete task"

**Then**:
- Normalization happens before routing lookup
- Routing uses lowercase normalized form
- Match succeeds with stored lowercase identifier
- Agent receives properly routed message

---

## Test Case 8: Lowercase Normalization on Receiver Side

**Given**:
- Agent exists with `agentName: "ResearchBot"`
- Database stores identifiers in original case
- Matching layer normalizes both sides

**When**:
- User sends: "@researchbot find papers"
- System retrieves agent identifiers: "ResearchBot", "Research Bot"
- System normalizes retrieved identifiers to: "researchbot", "research bot"

**Then**:
- Receiver-side normalization matches sender-side
- Case differences don't prevent matching
- Routing succeeds regardless of stored case

---

## Test Case 9: Multiple Agents with Similar Names (No Collision)

**Given**:
- Agent A: `agentName: "Nova"`, aliases: ["assistant"]
- Agent B: `agentName: "NovaX"`, aliases: ["helper"]
- Both agents are active

**When**:
- User sends: "@nova schedule meeting"
- User sends: "@novax analyze data"
- User sends: "@assistant check calendar"
- User sends: "@helper process files"

**Then**:
- "@nova" and "@assistant" route to Agent A only
- "@novax" and "@helper" route to Agent B only
- No cross-contamination between agents
- Exact matching (after normalization) prevents partial matches

---

## Test Case 10: Agent Name with Special Characters

**Given**:
- Agent exists with `agentName: "data_processor_v2"`
- Database name: "Data Processor V2"

**When**:
- User sends: "@data_processor_v2 run job"
- User sends: "@Data Processor V2 status"
- User sends: "@DATA_PROCESSOR_V2 cancel"

**Then**:
- All variations route correctly
- Underscores and spaces are handled appropriately
- Case normalization applies to alphanumeric portions
- Special characters remain part of identifier matching

---

## Test Case 11: Empty or Malformed Mentions

**Given**:
- Agent exists with `agentName: "Nova"`

**When**:
- User sends: "@ help me" (space after @)
- User sends: "@" (just @ symbol)
- User sends: "@@nova double mention"
- User sends: "@nova@help malformed"

**Then**:
- Malformed mentions don't crash the system
- @ with space may not be recognized as mention
- Double @ doesn't cause duplicate routing
- System handles edge cases gracefully

---

## Test Case 12: Alias Priority When Multiple Match

**Given**:
- Agent A: `agentName: "Nova"`, aliases: ["bot"]
- Agent B: `agentName: "Bot"`, aliases: []
- Potential collision on "bot" identifier

**When**:
- User sends: "@bot status check"

**Then**:
- System has defined precedence (e.g., agentName > alias)
- Message routes to exactly one agent (Agent B, since "Bot" is its agentName)
- No duplicate delivery
- Collision handling is documented and consistent

---

## Test Case 13: Database Name Updates Reflect in Routing

**Given**:
- Agent exists with `agentName: "DevBot"`
- Database initially has name: "Development Bot"
- Database name updated to: "Developer Assistant"

**When**:
- Before update: User sends "@Development Bot help"
- After update: User sends "@Development Bot help"
- After update: User sends "@Developer Assistant help"

**Then**:
- Before update: "@Development Bot" routes correctly
- After update: "@Development Bot" no longer matches (unless cached)
- After update: "@Developer Assistant" routes correctly
- Routing reflects current database state (with reasonable cache TTL)

---

## Test Case 14: Performance with Multiple Agents and Aliases

**Given**:
- 10 agents exist, each with 3-5 aliases
- Total of 40+ identifiers to match against

**When**:
- User sends message with mention: "@helper process data"
- System performs case-insensitive matching across all identifiers

**Then**:
- Matching completes in <100ms (reasonable threshold)
- Correct agent is identified
- Performance doesn't degrade with agent count
- Indexing or optimization is used for lookup

---

## Test Case 15: Multiple Mentions in Single Message

**Given**:
- Agent A: `agentName: "Nova"`
- Agent B: `agentName: "CodeBot"`

**When**:
- User sends: "@nova and @CODEBOT please collaborate on this task"

**Then**:
- Message routes to both Agent A and Agent B
- Each mention is independently matched case-insensitively
- Both agents receive the full message
- Order of mentions doesn't affect routing

---

## Edge Case Tests

### EC1: Zero-Length Agent Name
**Given**: Agent with empty string as agentName (if allowed)  
**When**: User sends any message  
**Then**: No unexpected matching, system handles gracefully

### EC2: Very Long Agent Name
**Given**: Agent with 255+ character name  
**When**: User mentions full name  
**Then**: Matching works correctly, no buffer overflow

### EC3: Unicode in Agent Names
**Given**: Agent named "助手" (Chinese for "assistant")  
**When**: User sends "@助手 help me"  
**Then**: Unicode is preserved and matched correctly (case-insensitive where applicable)

### EC4: Whitespace Variations
**Given**: Agent database name has "Nova  Bot" (double space)  
**When**: User sends "@Nova Bot" (single space)  
**Then**: Define expected behavior (normalize whitespace? exact match?)

---

## Acceptance Criteria

All test cases pass when:
- ✅ agentName from config matches case-insensitively
- ✅ Database agent name matches case-insensitively
- ✅ Aliases match case-insensitively
- ✅ No false positives (non-existent agents don't match)
- ✅ No false negatives (valid mentions always route)
- ✅ Normalization is consistent sender-side and receiver-side
- ✅ Performance is acceptable with realistic agent counts
- ✅ Edge cases are handled without errors

---

## Test Environment Setup

**Database Schema**:
```sql
-- Agents table
CREATE TABLE agents (
  id TEXT PRIMARY KEY,
  name TEXT,  -- may differ from config agentName
  ...
);

-- Aliases table
CREATE TABLE agent_aliases (
  agent_id TEXT REFERENCES agents(id),
  alias TEXT,
  PRIMARY KEY (agent_id, alias)
);
```

**Config Example**:
```javascript
{
  agentName: "Nova",
  // other config...
}
```

**Test Data**:
- Create 3-5 test agents with varying name formats
- Add 2-3 aliases per agent
- Include cases where config and database names differ
- Test with different case variations

---

## Implementation Notes

For developers implementing this feature:

1. **Normalization Function**: Create `normalizeIdentifier(str)` that:
   - Converts to lowercase
   - Trims whitespace
   - Optionally normalizes internal whitespace (decide on policy)

2. **Matching Logic**: 
   - Build lookup table with all normalized identifiers → agent_id
   - Check for collisions and define precedence
   - Apply normalization to incoming mentions

3. **Caching**: Consider caching normalized identifier → agent_id map
   - Invalidate on agent/alias updates
   - Balance freshness vs. performance

4. **Logging**: Log when:
   - No match found for a mention
   - Multiple agents could match (collision)
   - Alias/database name is used vs. config name

---

**Test Cases Created**: 2026-02-13  
**Issue**: nova-memory#69  
**Status**: Ready for implementation testing
