# Test Cases: Issue #70 - Add Outbound Send Support to agent_chat Plugin

**Issue:** nova-memory#70  
**Feature:** Outbound send tool with automatic agent identifier lookup  
**Date:** 2026-02-13

---

## Test Case 1: Send Message by Nickname

**ID:** TC-70-001  
**Priority:** High  
**Prerequisite:** Agent "newhart" exists with nickname "Newhart" in agent registry

**Given:** 
- The agent_chat plugin is initialized
- Agent registry contains entry: `{agentName: "newhart", nickname: "Newhart"}`
- Current agent config has sender name configured

**When:** 
- User calls send tool with target "Newhart" and message "Hello from test"

**Then:**
- Target is resolved to agentName "newhart"
- Message is inserted into agent_chat table with:
  - `mentions` array contains "newhart"
  - `sender` field contains current agent's name
  - `message` field contains "Hello from test"
- Success confirmation is returned
- No errors are logged

---

## Test Case 2: Send Message by Database Name

**ID:** TC-70-002  
**Priority:** High  
**Prerequisite:** Agent "newhart" exists with database name "newhart"

**Given:**
- The agent_chat plugin is initialized
- Agent registry contains entry: `{agentName: "newhart", dbName: "newhart"}`
- Current agent is authenticated

**When:**
- User calls send tool with target "newhart" and message "Testing db name"

**Then:**
- Target is resolved to agentName "newhart"
- Message is inserted successfully with proper mentions array
- Lookup uses #69 infrastructure for name resolution
- Response confirms delivery to "newhart"

---

## Test Case 3: Send Message by agentName (Direct Match)

**ID:** TC-70-003  
**Priority:** High  
**Prerequisite:** Agent "newhart" exists in registry

**Given:**
- The agent_chat plugin is initialized
- Agent "newhart" exists in agent registry

**When:**
- User calls send tool with target "newhart" and message "Direct agentName test"

**Then:**
- Target matches agentName directly (no lookup required)
- Message is inserted with mentions=["newhart"]
- No additional resolution steps are performed
- Success response is returned immediately

---

## Test Case 4: Send Message by Alias

**ID:** TC-70-004  
**Priority:** Medium  
**Prerequisite:** Agent has configured alias

**Given:**
- Agent registry contains: `{agentName: "newhart", alias: "bob"}`
- Current agent has send permissions

**When:**
- User calls send tool with target "bob" and message "Alias test"

**Then:**
- Alias "bob" is resolved to agentName "newhart"
- Message is inserted with correct mentions array
- Lookup checks alias field in registry
- Confirmation indicates delivery to resolved agent

---

## Test Case 5: Case-Insensitive Target Resolution

**ID:** TC-70-005  
**Priority:** High  
**Prerequisite:** Agent "newhart" with nickname "Newhart" exists

**Given:**
- Agent registry contains case-sensitive identifiers
- Send tool accepts string target parameter

**When:**
- User calls send tool with variations:
  - "NEWHART" (all caps)
  - "newhart" (all lowercase)
  - "NewHart" (mixed case)

**Then:**
- All variations resolve to agentName "newhart"
- Case-insensitive matching is applied to:
  - nickname
  - dbName
  - agentName
  - alias
- Messages are delivered successfully in all cases
- No case-related errors occur

---

## Test Case 6: Error Handling - Unknown Target

**ID:** TC-70-006  
**Priority:** High  
**Prerequisite:** None

**Given:**
- Agent registry does not contain "nonexistent-agent"
- No agent has nickname/alias/dbName matching "unknown"

**When:**
- User calls send tool with target "unknown-agent" and message "Test"

**Then:**
- Lookup fails to resolve target
- Error is returned with message: "Agent not found: unknown-agent"
- No database INSERT is attempted
- Error suggests checking available agents or using list command
- Logging captures the failed lookup attempt

---

## Test Case 7: Proper Sender Name from Config

**ID:** TC-70-007  
**Priority:** High  
**Prerequisite:** Current agent config contains sender name

**Given:**
- Current agent config: `{agentName: "erato", displayName: "Erato"}`
- Target agent "newhart" exists and is valid

**When:**
- Agent sends message using send tool

**Then:**
- Message row contains sender field = "erato" (or configured sender identifier)
- Sender is derived from current agent's config, not hardcoded
- If displayName exists, it may be included in metadata
- Sender field format matches schema requirements

---

## Test Case 8: Message Delivery Confirmation

**ID:** TC-70-008  
**Priority:** Medium  
**Prerequisite:** Valid target agent exists

**Given:**
- Target agent "newhart" is valid and active
- Message content is non-empty

**When:**
- Send tool completes successfully

**Then:**
- Response includes confirmation message:
  - Target agent name (resolved)
  - Message ID or timestamp
  - Success status
- Example: "Message sent to newhart (Newhart) at 2026-02-13T10:59:00Z"
- Confirmation is returned to caller immediately after INSERT

---

## Test Case 9: Reply-to Threading (Optional)

**ID:** TC-70-009  
**Priority:** Low  
**Prerequisite:** Original message exists in agent_chat table

**Given:**
- Existing message with ID "msg-123" in agent_chat table
- Current agent wants to reply to this message

**When:**
- Send tool is called with:
  - target: "newhart"
  - message: "This is a reply"
  - replyTo: "msg-123" (optional parameter)

**Then:**
- New message is inserted with:
  - mentions=["newhart"]
  - replyTo or threadId field = "msg-123"
- Thread relationship is preserved
- Target agent can reconstruct conversation thread
- If replyTo is omitted, message is standalone (not in thread)

---

## Test Case 10: Multiple Target Validation

**ID:** TC-70-010  
**Priority:** Low  
**Prerequisite:** Multiple agents exist

**Given:**
- Registry contains "newhart" and "erato"
- Send tool accepts single target parameter

**When:**
- User attempts to send to multiple targets in one call

**Then:**
- Behavior is defined (either):
  - Only first target is used (with warning)
  - Error: "Multiple targets not supported, send separately"
  - OR: Future enhancement to support array of targets
- Current implementation handles single target only

---

## Test Case 11: Empty or Invalid Message Content

**ID:** TC-70-011  
**Priority:** Medium  
**Prerequisite:** Valid target exists

**Given:**
- Target "newhart" is valid

**When:**
- Send tool is called with:
  - Empty string message: ""
  - Null message: null
  - Whitespace-only: "   "

**Then:**
- Validation rejects empty/invalid messages
- Error returned: "Message content cannot be empty"
- No database INSERT occurs
- User is prompted to provide valid message

---

## Test Case 12: Integration with #69 Infrastructure

**ID:** TC-70-012  
**Priority:** High  
**Prerequisite:** Issue #69 (agent lookup infrastructure) is implemented

**Given:**
- #69 provides agent lookup/resolution utilities
- Send tool imports and uses these utilities

**When:**
- Any target resolution is performed

**Then:**
- Send tool calls #69 lookup functions (e.g., `resolveAgent(target)`)
- Does not duplicate resolution logic
- Inherits all #69 features:
  - Case-insensitive matching
  - Multi-field lookup (nickname, dbName, alias, agentName)
  - Consistent error handling
- Code reuse is maximized

---

## Test Case 13: Sender Not Configured

**ID:** TC-70-013  
**Priority:** Medium  
**Prerequisite:** Current agent config lacks sender identifier

**Given:**
- Current agent config is incomplete or missing
- No fallback sender name is available

**When:**
- Send tool attempts to send message

**Then:**
- Error or warning is generated: "Sender identity not configured"
- Either:
  - Message is rejected (recommended)
  - OR: Default/anonymous sender is used with warning
- User is prompted to configure agent identity

---

## Test Case 14: Database INSERT Failure Handling

**ID:** TC-70-014  
**Priority:** Medium  
**Prerequisite:** Database connection issues or constraint violations

**Given:**
- All parameters are valid
- Database is unavailable or INSERT fails

**When:**
- Send tool attempts INSERT operation

**Then:**
- Database error is caught and handled gracefully
- Error message returned to user: "Failed to deliver message: [error details]"
- No partial data is committed
- Logging captures full error stack for debugging
- User receives actionable error message

---

## Test Case 15: Special Characters in Message Content

**ID:** TC-70-015  
**Priority:** Low  
**Prerequisite:** Valid target exists

**Given:**
- Target agent is valid
- Message contains special characters: emoji, unicode, quotes, etc.

**When:**
- Send tool is called with message: "Hello 👋 "quoted text" & <special> chars"

**Then:**
- Message is stored correctly with all characters preserved
- No encoding/escaping issues occur
- Special characters are retrieved intact by recipient
- Database schema supports UTF-8 content

---

## Notes

- All test cases assume SQLite database backend (nova-memory default)
- Test execution should use isolated test database
- Mock agent registry for deterministic testing
- Verify schema compatibility (agent_chat table structure)
- Integration tests should use actual #69 lookup implementation

## Success Criteria

- All high-priority test cases (TC-70-001 through TC-70-007, TC-70-012) pass
- Error handling test cases demonstrate graceful failure modes
- Code coverage ≥80% for send tool implementation
- No regression in existing agent_chat functionality
