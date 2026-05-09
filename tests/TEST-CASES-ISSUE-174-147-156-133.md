# Test Cases: Issues #174, #147, #156, #133 — Hook Context Keys, Path Hygiene, Semantic Recall JSON, Grammar Parser Removal

**Branch:** `feature/issue-174-hook-context-and-path-fixes`

---

## #174 — memory-extract hook canonical context keys

### TC-001: Discord message — content extraction
**Input:** Discord message with `ctx.content = "I like meat pizza and cheeseburgers plain & dry"`
**Expected:** Hook reads `ctx.content` (not `ctx.rawBody`), passes full message to extraction pipeline. Gateway log shows `[memory-extract] Processing message` with correct messageLength and preview.

### TC-002: Signal message — content extraction
**Input:** Signal group message with `ctx.content = "Let's meet at 3pm tomorrow"`
**Expected:** Same extraction path works. Provider detected from context keys.

### TC-003: Sender field mapping from canonical context
**Input:** Discord message with:
- `ctx.senderId = "330189773371080716"`
- `ctx.senderName = "I)ruid"`
- `ctx.senderUsername = "druidian"`
**Expected:** Hook passes `SENDER_NAME=I)ruid`, `SENDER_ID=330189773371080716` to extraction subprocess. Channel transcript upsert uses these fields.

### TC-004: Channel transcript upsert uses canonical keys
**Input:** Message with:
- `ctx.conversationId = "channel:1492386247862390824"`
- `ctx.messageId = "1502589947721547817"`
- `ctx.channelId = "discord"`
- `ctx.guildId = "1492385947927445524"`
- `ctx.channelName = "#software-engineering"`
- `ctx.isGroup = true`
**Expected:** `channel_sessions` row created with correct `provider='discord'`, `external_chat_id`, `group_space_id`, `group_subject`. `channel_transcripts` row created with correct `external_message_id`.

### TC-005: entity_facts source pointers populated in real-time
**Input:** Message triggers fact extraction that produces a new entity_fact.
**Expected:** `source_channel_transcript_id` and `source_channel_session_id` are non-NULL on the new entity_facts row.

### TC-006: entity_facts reinforcement with new context keys
**Input:** Duplicate fact extracted from a newer message.
**Expected:** `vote_count` incremented. Source pointers updated to newer message. Existing reinforcement logic still works with the new context key mappings.

### TC-007: Empty content — skip gracefully
**Input:** Message with `ctx.content = ""` or `ctx.content = undefined`
**Expected:** Hook logs "Skipping short or empty message" and does NOT crash. No transcript row created.

### TC-008: Very long message content
**Input:** Message with `ctx.content` = 100KB of text
**Expected:** Content truncated to 65535 chars for transcript storage. Extraction pipeline receives full text. No crash.

### TC-009: Missing sender fields
**Input:** Message with `ctx.senderId = undefined`, `ctx.senderName = undefined`
**Expected:** Hook defaults to `senderName = "unknown"`, `senderId = ""`. Transcript row still created with NULL sender fields. No crash.

### TC-010: Slash command — skip extraction
**Input:** Message with `ctx.content = "/model opus-4.6"`
**Expected:** Hook logs "Skipping command message" and returns early. No extraction or transcript upsert.

### TC-011: All context key fallbacks
**Verification:** Hook code reads `ctx.content` as primary, with fallbacks:
```typescript
const rawBody = ctx.content ?? ctx.rawBody ?? ctx.RawBody ?? ctx.message ?? ctx.Body ?? "";
```
**Expected:** Each fallback tested — only `ctx.content` should match in the canonical context from any channel.

---

## #147 — Stale relative paths

### TC-012: memory-extract hook — no relative path traversals
**Verification:** `grep -n '../../' memory/hooks/memory-extract/handler.ts`
**Expected:** Zero matches. All script paths use `os.homedir()` or `process.env.HOME`.

### TC-013: semantic-recall hook — no relative path traversals
**Verification:** `grep -n '../../' memory/hooks/semantic-recall/handler.ts`
**Expected:** Zero matches. `RECALL_SCRIPT` uses `join(os.homedir(), '.openclaw', 'scripts', 'proactive-recall.py')`.

### TC-014: session-init hook — no relative path traversals
**Verification:** `grep -n '../../' memory/hooks/session-init/handler.ts`
**Expected:** Zero matches. Script path uses `join(os.homedir(), '.openclaw', 'scripts', 'generate-session-context.sh')`.

### TC-015: Full repo path audit
**Verification:**
```bash
grep -rn '\.\./' memory/hooks/ --include='*.ts' | grep -v node_modules | grep -v '.git'
```
**Expected:** Zero matches across all hook handler files.

---

## #156 — semantic-recall structured JSON over stdin

### TC-016: Structured JSON input to proactive-recall.py
**Verification:** semantic-recall hook constructs a JSON object with:
```json
{
  "content": "message text",
  "senderId": "330189773371080716",
  "senderName": "I)ruid",
  "provider": "discord",
  "conversationId": "channel:1492386247862390824",
  "isGroup": true,
  "channelName": "#software-engineering"
}
```
and passes it via `spawnSync` `input` parameter (stdin).
**Expected:** No CLI argument injection possible. The recall script receives parseable JSON on stdin.

### TC-017: proactive-recall.py handles JSON stdin
**Verification:** The recall script can parse the JSON blob and extract the message content for query. Falls back gracefully if plain text is received (backward compat).

### TC-018: Shell metacharacters in message content
**Input:** Message containing backticks, `$(command)`, single quotes, double quotes, semicolons, pipes.
**Expected:** All characters pass safely through stdin JSON. No shell interpretation. No crash.

---

## #133 — Remove ~/clawd hardcoded paths

### TC-019: No ~/clawd references in any hook
**Verification:**
```bash
grep -rn 'clawd' memory/hooks/ --include='*.ts' | grep -v node_modules
```
**Expected:** Zero matches.

### TC-020: No ~/clawd references in any script
**Verification:**
```bash
grep -rn 'clawd' memory/scripts/ --include='*.sh' --include='*.py'
```
**Expected:** Zero matches.

### TC-021: Correct venv path in semantic-recall
**Verification:** `PYTHON_VENV` resolves to `~/.local/share/nova/venv/bin/python` (standard location) or falls back to workspace venv. Never references `~/clawd/`.

### TC-022: Cron path audit (tracked for ops follow-up)
**Verification:** `crontab -l | grep clawd`
**Expected:** Document any stale entries. Create ops task for cleanup. Not a code fix in this PR.

---

## Grammar Parser Removal

### TC-023: grammar_parser directory deleted
**Verification:** `ls memory/grammar_parser/` returns "No such file or directory"

### TC-024: process-input-with-grammar.sh deleted
**Verification:** `ls memory/scripts/process-input-with-grammar.sh` returns "No such file or directory"

### TC-025: test_grammar_integration.sh deleted
**Verification:** `ls memory/tests/test_grammar_integration.sh` returns "No such file or directory"

### TC-026: No remaining grammar parser references
**Verification:**
```bash
grep -rn 'grammar' memory/ --include='*.ts' --include='*.sh' --include='*.py' | grep -v node_modules | grep -v __pycache__ | grep -v TEST-CASES
```
**Expected:** Zero matches in active codepaths. Only acceptable in CHANGELOG or historical docs.

### TC-027: Installer does not reference grammar parser
**Verification:** `grep -n 'grammar' agent-install.sh`
**Expected:** Zero matches.

---

## Cross-cutting

### TC-028: All hooks use canonical event gating
**Verification:** Each hook checks `event.type === "message" && event.action === "received"` before processing.

### TC-029: No remaining references to old context key names
**Verification:**
```bash
grep -n 'ctx\.rawBody\|ctx\.RawBody\|ctx\.Body\|ctx\.message[^I]' memory/hooks/memory-extract/handler.ts
```
**Expected:** Only as fallbacks after `ctx.content`, never as primary.

### TC-030: Gateway restart and hook registration
**Verification:** After deploying fixes, restart gateway and confirm all three hooks register:
```
Registered hook: memory-extract -> message:received
Registered hook: semantic-recall -> message:received  
Registered hook: session-init -> session:start
```
