# Test Cases: Insight Extraction (Issue #50)

## Overview
Tests for extracting "insights" — moments where a user demonstrates understanding of something during conversation. Triggered by phrases like "Got it", "I see", "Ah, so...", etc.

## Schema Recommendation

**Recommendation: Extend `lessons` table with a `type` column.**

Rationale:
- Insights and lessons share the same structure (text, context, source, confidence, timestamps)
- Both use the same decay/reinforcement lifecycle
- `lessons_archive` works for both without duplication
- Embedding pipeline (`memory_embeddings`) already handles `lesson` source_type — just add `insight` or keep unified
- Avoids yet another table + archive table + indexes + grants

```sql
ALTER TABLE lessons ADD COLUMN type VARCHAR(20) DEFAULT 'lesson'
  CHECK (type IN ('lesson', 'insight', 'correction'));
ALTER TABLE lessons_archive ADD COLUMN type VARCHAR(20) DEFAULT 'lesson';
```

---

## 1. Pattern Detection — Trigger Phrases

### 1.1 Positive Detection (should extract insight)

| # | Input | Expected Insight | Notes |
|---|-------|-----------------|-------|
| 1.1.1 | "Oh, I see — so the API uses OAuth not API keys" | "the API uses OAuth not API keys" | Classic "I see" + explanation |
| 1.1.2 | "Got it, the cron runs every minute not every hour" | "the cron runs every minute not every hour" | "Got it" + what was understood |
| 1.1.3 | "Ah, so you need to restart the service after config changes" | "need to restart the service after config changes" | "Ah, so..." pattern |
| 1.1.4 | "Ohhh that makes sense now — it's because of the cache" | "it's because of the cache" | "makes sense" variant |
| 1.1.5 | "Now I understand, the entity_facts table uses vote_count for reinforcement" | "entity_facts table uses vote_count for reinforcement" | "Now I understand" |
| 1.1.6 | "Right, so the visibility is inherited from the user's default" | "visibility is inherited from the user's default" | "Right, so..." |
| 1.1.7 | "Interesting — so embeddings are stored in both SQLite and Postgres" | "embeddings are stored in both SQLite and Postgres" | "Interesting" + insight |
| 1.1.8 | "Aha, so that's why the tests were failing — wrong DB name" | "tests were failing because of wrong DB name" | "Aha" + cause-effect |
| 1.1.9 | "Oh wait, so MEMORY.md only loads in main sessions for security?" | "MEMORY.md only loads in main sessions for security" | Question form insight |
| 1.1.10 | "I didn't realize the extraction runs async every minute" | "extraction runs async every minute" | "I didn't realize" = insight |

### 1.2 False Positives (should NOT extract insight)

| # | Input | Context | Why Skip |
|---|-------|---------|----------|
| 1.2.1 | "Got it, thanks!" | No preceding explanation | Acknowledgment only, no substance |
| 1.2.2 | "I see." | Standalone | No content to extract |
| 1.2.3 | "Got it. Can you also check the logs?" | Task request follows | "Got it" is just polite ack, no learning content |
| 1.2.4 | "Ah, so you're here too?" | Greeting in group chat | Social phrase, not understanding |
| 1.2.5 | "I see three options in the menu" | Literal visual "I see" | Not an understanding phrase |
| 1.2.6 | "The movie 'I See You' was creepy" | Media title contains trigger | False match on title |
| 1.2.7 | "That makes sense for the timeline" | Agreement without new understanding | Agreeing, not learning |
| 1.2.8 | "Got it from the store yesterday" | "Got it" = obtained | Different meaning of "got it" |
| 1.2.9 | "Right, right, right" | Filler agreement | No substantive content |
| 1.2.10 | "Interesting." | Standalone with period | Polite acknowledgment, nothing to extract |

### 1.3 Edge Cases

| # | Input | Expected Behavior | Notes |
|---|-------|-------------------|-------|
| 1.3.1 | "Oh I see, so X... wait no, I think it's actually Y" | Extract Y not X | Self-correction — final understanding wins |
| 1.3.2 | "Got it! So A, and also B, and C" | Extract all three (or combined) | Multiple insights in one message |
| 1.3.3 | "I think I understand... maybe?" | Extract with lower confidence (0.5) | Uncertain insight |
| 1.3.4 | "Oh! So THAT'S what you meant!" | Need context to extract | Requires looking at preceding NOVA message |
| 1.3.5 | "💡 the config needs to be in YAML not JSON" | Extract insight | Emoji lightbulb as insight signal |

---

## 2. Context Extraction — Identifying WHAT Was Understood

### 2.1 Context from Preceding Messages

| # | Context (prior messages) | Current Message | Expected Insight Content |
|---|-------------------------|-----------------|--------------------------|
| 2.1.1 | NOVA: "The store-memories.sh script deduplicates by checking entity_facts before insertion" | USER: "Ah, got it" | "store-memories.sh deduplicates by checking entity_facts before insertion" |
| 2.1.2 | NOVA: "The confidence score decays over time. If a fact isn't reinforced within 30 days, it drops." | USER: "Oh interesting, so it's like a forgetting curve" | "confidence score implements a forgetting curve — facts decay without reinforcement" |
| 2.1.3 | USER: "Why did the hook fail?" / NOVA: "Because ANTHROPIC_API_KEY wasn't set — hooks inherit env from OpenClaw" | USER: "Ohhh I see, so the hooks don't have their own env" | "hooks inherit environment from OpenClaw, they don't have their own env" |
| 2.1.4 | Long back-and-forth about privacy visibility system | USER: "Ok so basically: public=anyone, trusted=close, private=source only. And privacy_scope overrides all of those" | Full summary is the insight | Multi-turn synthesis |

### 2.2 Attribution

| # | Scenario | Expected `source` | Expected `context` |
|---|----------|-------------------|-------------------|
| 2.2.1 | User "I)ruid" says "Got it, so X" | source="conversation", correction_source="I)ruid" | The preceding explanation |
| 2.2.2 | NOVA explains X, user understands | source="conversation" | Link to conversation/session |
| 2.2.3 | Group chat: Alice explains, Bob says "Oh I see" | source="conversation", correction_source="Bob understood Alice's explanation" | Group context |

---

## 3. Extraction Prompt Integration

### 3.1 New Category in extract-memories.sh

The extraction prompt should add an `insights` category:

```
insights: [{
  insight: "what was understood",
  trigger_phrase: "Got it|I see|Ah so|...",
  context: "what prompted this understanding",
  source_person: "who had the insight",
  confidence: 0.0-1.0,
  visibility: "public|private|trusted"
}]
```

### 3.2 Prompt Injection Tests

| # | Test | Expected |
|---|------|----------|
| 3.2.1 | Message with insight phrase → extract-memories.sh | JSON includes `insights` array |
| 3.2.2 | Message with no insight phrase → extract-memories.sh | JSON has no `insights` key or empty array |
| 3.2.3 | Message with false positive → extract-memories.sh | No insight extracted |
| 3.2.4 | Multiple insights in one message | `insights` array has multiple entries |

---

## 4. Storage Integration (store-memories.sh)

### 4.1 Insert Path

| # | Test | Expected |
|---|------|----------|
| 4.1.1 | `insights` array in JSON → store-memories.sh | Row inserted in `lessons` with `type='insight'` |
| 4.1.2 | Insight with context | `context` column populated with preceding conversation |
| 4.1.3 | Insight with confidence | `confidence` column set from extraction |
| 4.1.4 | Duplicate insight (same content) | Skipped or reinforced (vote_count++) |

### 4.2 Deduplication

| # | Test | Expected |
|---|------|----------|
| 4.2.1 | Same insight extracted twice from same conversation | Only stored once |
| 4.2.2 | Similar but not identical insight | Fuzzy match — reinforce existing |
| 4.2.3 | Insight that matches an existing lesson | Consider linking, not duplicating |

---

## 5. Embedding Pipeline

| # | Test | Expected |
|---|------|----------|
| 5.1 | New insight stored → triggers embedding | `memory_embeddings` row with `source_type='insight'` (or 'lesson') |
| 5.2 | Semantic search for related topic | Insight surfaces in `proactive-recall.py` results |
| 5.3 | `memory_type_priorities` has insight entry | Priority weight configured for insight source_type |

---

## 6. End-to-End Integration Tests

### 6.1 Full Pipeline

```bash
# Test: Conversation with insight → extraction → storage → retrieval
export SENDER_NAME="test-user"
export SENDER_ID="test-123"

echo '[USER]: Why does the cron run every minute?
[NOVA]: Because chat messages arrive continuously and we want near-real-time memory extraction. The 1-minute interval balances freshness with API cost.
[CURRENT USER MESSAGE]: Oh I see, so it is a tradeoff between latency and cost' \
  | bash scripts/extract-memories.sh \
  | bash scripts/store-memories.sh

# Verify: lessons table has new insight
psql -c "SELECT * FROM lessons WHERE type='insight' ORDER BY learned_at DESC LIMIT 1;"
```

### 6.2 Round-Trip Verification

| # | Test | Verify |
|---|------|--------|
| 6.2.1 | Extract → Store → Query | `SELECT * FROM lessons WHERE type='insight'` returns row |
| 6.2.2 | Extract → Store → Embed → Search | `proactive-recall.py` finds the insight |
| 6.2.3 | Extract → Store → Decay → Archive | Insight moves to `lessons_archive` after decay |

---

## 7. Migration & Backwards Compatibility

| # | Test | Expected |
|---|------|----------|
| 7.1 | Add `type` column to `lessons` | Existing rows default to `type='lesson'` |
| 7.2 | All existing queries still work | `WHERE type='lesson'` or no type filter both work |
| 7.3 | `lessons_archive` gets `type` column too | Archive preserves type information |
| 7.4 | Views/grants unaffected | No permission errors after migration |

---

## Implementation Notes

1. **Extraction prompt change**: Add `insights` to the extraction categories in `extract-memories.sh` (line ~105)
2. **Storage handler**: Add insight processing block in `store-memories.sh` (after lessons block)
3. **Schema migration**: Single `ALTER TABLE` for the type column
4. **Embedding**: Add `'insight'` to `memory_type_priorities` table
5. **No new archive table needed** — `lessons_archive` handles both types
