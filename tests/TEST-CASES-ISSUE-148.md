# Test Cases for nova-mind Issue #148: Switch Embedding Scripts from OpenAI to Ollama

## Overview
Comprehensive test cases for switching embedding from OpenAI `text-embedding-3-small` (1536 dims) to Ollama `mxbai-embed-large` (1024 dims). Covers 4 Python scripts, 1 TypeScript hook, config, DB migration, index rebuild, full re-embed, cron, and integration.

**Total Test Cases:** 45
**P0 (Critical):** 13
**P1 (High):** 20
**P2 (Medium):** 12

## Test Case Format
- **ID**: Unique identifier (e.g., TC-001)
- **Description**: Brief summary
- **Preconditions**: Setup required
- **Steps**: Numbered actions
- **Expected Result**: Observable outcomes
- **Priority**: P0/P1/P2

---

## 1. Shared Config (`memory/scripts/embedding-config.json`)

**TC-001**
**Description**: Load valid config file
**Preconditions**: `embedding-config.json` exists with `{"provider":"ollama","model":"mxbai-embed-large","base_url":"http://localhost:11434","dimensions":1024}`; Ollama running with model pulled.
**Steps**:
1. Run any embedding script (e.g., `embed-memories.py`).
**Expected Result**: Config loads successfully; logs show correct model, URL, dims=1024; no errors.
**Priority**: P0

**TC-002**
**Description**: Missing config file
**Preconditions**: No `embedding-config.json` in the script directory.
**Steps**:
1. Run `embed-memories.py`.
**Expected Result**: Script exits with clear error message indicating config file not found; no DB writes; exit code 1.
**Priority**: P0

**TC-003**
**Description**: Malformed JSON config
**Preconditions**: `embedding-config.json` with invalid JSON (e.g., missing quote).
**Steps**:
1. Run `embed-memories.py`.
**Expected Result**: JSON parse error; exits with code 1; no DB writes.
**Priority**: P0

**TC-004**
**Description**: Ollama returns wrong dimensions vs config
**Preconditions**: Config declares `dimensions: 1024`; Ollama running but returns a vector with dimension count that doesn't match (e.g., model swapped to one producing 768 dims).
**Steps**:
1. Run `embed-memories.py` with a test record.
**Expected Result**: Script detects actual embedding dimensions don't match configured `dimensions`; logs error with actual vs expected; exits code 1; no DB writes.
**Priority**: P1

**TC-046**
**Description**: Config file location resolution — relative to script directory
**Preconditions**: `embedding-config.json` in the script directory; cwd is a different directory (e.g., `/tmp`).
**Steps**:
1. `cd /tmp && python ~/.openclaw/scripts/embed-memories.py`
**Expected Result**: Config loaded from script's own directory, not from cwd. Script runs successfully.
**Priority**: P0

---

## 2. Database Migration & Index

**TC-005**
**Description**: Migrate `embedding` column dims from 1536 to 1024
**Preconditions**: DB has `memory_embeddings.embedding vector(1536)` with existing data.
**Steps**:
1. Run migration: `ALTER TABLE memory_embeddings DROP COLUMN embedding; ALTER TABLE memory_embeddings ADD COLUMN embedding vector(1024);`
2. Verify schema: `\d memory_embeddings`
**Expected Result**: Column is now `vector(1024)`; existing embeddings are cleared (will be re-embedded); other columns preserved.
**Priority**: P0

**TC-006**
**Description**: Rebuild IVFFlat index after migration
**Preconditions**: Post-migration; some 1024-dim vectors inserted.
**Steps**:
1. `DROP INDEX IF EXISTS idx_memory_embeddings_vector;`
2. `CREATE INDEX idx_memory_embeddings_vector ON memory_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists=100);`
3. `EXPLAIN ANALYZE SELECT * FROM memory_embeddings ORDER BY embedding <=> '[0.1,0.1,...]'::vector LIMIT 10;`
**Expected Result**: Index created successfully; query plan shows index scan; performance acceptable.
**Priority**: P0

**TC-007**
**Description**: No old 1536-dim vectors remain after migration + re-embed
**Preconditions**: Post-migration and full re-embed complete.
**Steps**:
1. `SELECT DISTINCT vector_dims(embedding) FROM memory_embeddings WHERE embedding IS NOT NULL;`
**Expected Result**: Only `1024` returned. No 1536-dim vectors exist.
**Priority**: P0

**TC-042**
**Description**: pgvector cosine distance ops work with 1024-dim vectors
**Preconditions**: At least 2 rows with 1024-dim embeddings in table.
**Steps**:
1. Manual insert of a known 1024-dim vector.
2. Query: `SELECT id, 1 - (embedding <=> test_vector::vector) AS similarity FROM memory_embeddings ORDER BY embedding <=> test_vector::vector LIMIT 5;`
**Expected Result**: Cosine similarity computed correctly; results ordered by similarity; no errors.
**Priority**: P0

---

## 3. embed-memories.py

**TC-008**
**Description**: Happy path — embed MEMORY.md and daily logs
**Preconditions**: Valid config; Ollama running; MEMORY.md and daily_log files exist; empty `memory_embeddings`.
**Steps**:
1. Run `python memory/scripts/embed-memories.py`.
2. `SELECT source_type, COUNT(*), vector_dims(embedding) FROM memory_embeddings WHERE source_type IN ('memory_md','daily_log') GROUP BY source_type, vector_dims(embedding);`
**Expected Result**: Rows inserted for both source types; all dims=1024; no errors.
**Priority**: P0

**TC-009**
**Description**: Edge — empty content chunk is skipped
**Preconditions**: Daily log file containing an empty section that produces an empty chunk.
**Steps**:
1. Run script.
**Expected Result**: Empty chunks are skipped with a log warning; no zero-vector rows inserted; other chunks embedded normally.
**Priority**: P1

**TC-010**
**Description**: Edge — very long text (>10k chars)
**Preconditions**: Daily log with very long content exceeding typical context windows.
**Steps**:
1. Run script.
**Expected Result**: Text is chunked per existing chunking logic; each chunk produces a valid 1024-dim embedding.
**Priority**: P1

**TC-011**
**Description**: Edge — special characters and Unicode
**Preconditions**: Content with UTF-8 emojis (🧠), accents (café), CJK characters, mathematical symbols.
**Steps**:
1. Run script.
**Expected Result**: All content embeds successfully; vectors are non-zero; no encoding errors.
**Priority**: P1

**TC-044**
**Description**: `embed-memories.py --reindex` flag
**Preconditions**: Table has existing `daily_log` and `memory_md` rows.
**Steps**:
1. Run `python memory/scripts/embed-memories.py --reindex`.
2. Check row counts and timestamps.
**Expected Result**: Existing `daily_log` and `memory_md` rows deleted; all re-embedded fresh with 1024-dim vectors; `created_at` timestamps are new.
**Priority**: P1

---

## 4. embed-full-database.py

**TC-012**
**Description**: Happy path — embed all DB tables
**Preconditions**: Valid config; Ollama up; post-migration empty `memory_embeddings`.
**Steps**:
1. Run `python memory/scripts/embed-full-database.py`.
2. `SELECT source_type, COUNT(*) FROM memory_embeddings GROUP BY source_type ORDER BY count DESC;`
**Expected Result**: Rows for all source types (entity_fact, agent_chat, entity, event, etc.); all dims=1024; total ~8800.
**Priority**: P0

**TC-013**
**Description**: Full re-embed workflow (truncate + embed)
**Preconditions**: Table has old 1536-dim data.
**Steps**:
1. Run `--reindex` (or manual TRUNCATE).
2. Run `embed-full-database.py`.
**Expected Result**: Table truncated; fresh 1024-dim embeddings for all source types.
**Priority**: P0

**TC-048**
**Description**: No source_type overlap between embed scripts
**Preconditions**: Run both `embed-full-database.py` and `embed-library.py`.
**Steps**:
1. Check `SELECT source_type, COUNT(*) FROM memory_embeddings WHERE source_type = 'library' GROUP BY source_type;`
2. Verify `embed-full-database.py` does NOT produce `library` rows.
**Expected Result**: `library` source_type only produced by `embed-library.py`; no overlap.
**Priority**: P1

---

## 5. embed-library.py

**TC-014**
**Description**: Happy path — embed library works
**Preconditions**: Library works exist (e.g., IDs 199-204); valid config; Ollama up.
**Steps**:
1. Run `python memory/scripts/embed-library.py`.
2. `SELECT source_id, vector_dims(embedding) FROM memory_embeddings WHERE source_type = 'library';`
**Expected Result**: Rows with source_type='library' for each work; all dims=1024.
**Priority**: P0

**TC-043**
**Description**: `embed-library.py --reindex` flag
**Preconditions**: Table has existing `source_type='library'` rows.
**Steps**:
1. Run `python memory/scripts/embed-library.py --reindex`.
2. Check row counts and content.
**Expected Result**: Existing library embeddings deleted; all library works re-embedded fresh with 1024-dim vectors.
**Priority**: P1

---

## 6. proactive-recall.py

**TC-015**
**Description**: Happy path — query embedding + cosine search
**Preconditions**: Table populated with 1024-dim vectors; Ollama up.
**Steps**:
1. Run `python memory/scripts/proactive-recall.py "What do I know about minotaurs?"`.
**Expected Result**: Query embedded via Ollama (1024 dims); top-k results returned with similarity scores; JSON output format preserved.
**Priority**: P0

**TC-016**
**Description**: Search quality — relevant results ranked higher
**Preconditions**: Post-re-embed table with diverse content including known library works about minotaurs.
**Steps**:
1. Run `proactive-recall.py "labyrinth minotaur mythology"`.
**Expected Result**: Library works about minotaurs (IDs 199-204) appear in top results with high similarity scores.
**Priority**: P1

**TC-045**
**Description**: `proactive-recall.py` with `--threshold` and `--max-tokens` flags
**Preconditions**: Table populated; Ollama up.
**Steps**:
1. Run `proactive-recall.py "test query" --threshold 0.8 --max-tokens 500`.
**Expected Result**: Only results with similarity > 0.8 returned; total content fits within ~500 token budget. CLI flags work correctly.
**Priority**: P1

---

## 7. Error Conditions (All Scripts)

**TC-017**
**Description**: Ollama not running
**Preconditions**: Ollama service stopped.
**Steps**:
1. Run any embedding script.
**Expected Result**: Connection refused error; graceful exit code 1; no partial DB writes (transaction rolled back).
**Priority**: P1

**TC-018**
**Description**: Model not pulled
**Preconditions**: Ollama up, but `mxbai-embed-large` not pulled.
**Steps**:
1. Run any embedding script.
**Expected Result**: Model not found error from Ollama; script exits code 1 with clear error message.
**Priority**: P1

**TC-019**
**Description**: Network/request timeout
**Preconditions**: Ollama responding very slowly or hanging.
**Steps**:
1. Run script (should have a timeout configured).
**Expected Result**: Timeout error after reasonable period; partial batch not committed; exit code 1.
**Priority**: P1

**TC-047**
**Description**: Batch API failure — fallback or retry
**Preconditions**: Ollama up; batch contains one very long text that exceeds model context window.
**Steps**:
1. Run embed script with a batch containing one oversized text.
**Expected Result**: Script handles the error gracefully — either retries individual items, skips the problematic text with a warning, or falls back to single-embed mode. Other items in the batch are still processed.
**Priority**: P1

**TC-021**
**Description**: Batch size boundary
**Preconditions**: Config BATCH_SIZE=50.
**Steps**:
1. Run with 49, 50, and 51 items to embed.
**Expected Result**: 49 and 50 processed in 1 batch; 51 splits into 2 batches (50 + 1); all items embedded correctly.
**Priority**: P2

---

## 8. semantic-recall/handler.ts

**TC-022**
**Description**: Hook runs without OPENAI_API_KEY (guard removed)
**Preconditions**: `OPENAI_API_KEY` not set in environment; Ollama running; hook deployed.
**Steps**:
1. Send a message that triggers the semantic-recall hook.
2. Check gateway logs.
**Expected Result**: Hook does NOT skip execution; calls `proactive-recall.py` successfully; memories injected into context.
**Priority**: P0

---

## 9. Cron Script

**TC-023**
**Description**: embed-memories-cron.sh end-to-end
**Preconditions**: Valid config; Ollama up; new daily log files exist since last run.
**Steps**:
1. Run `bash memory/scripts/embed-memories-cron.sh`.
2. Check log file at `~/.openclaw/logs/embed-memories.log`.
**Expected Result**: Both `embed-memories.py` and `embed-full-database.py` run successfully; new embeddings created; log shows exit 0 for both.
**Priority**: P1

---

## 10. Integration

**TC-024**
**Description**: End-to-end: hook → proactive-recall → pgvector search
**Preconditions**: All changes deployed; table fully re-embedded with 1024-dim vectors; OPENAI_API_KEY not set; Ollama running.
**Steps**:
1. Send a message to the agent (e.g., via Signal) about a topic with known embeddings.
2. Observe agent response for contextual awareness.
3. Check gateway logs for `[semantic-recall]` entries.
**Expected Result**: Hook fires; query embedded via Ollama; cosine search returns relevant memories; agent response incorporates recalled context.
**Priority**: P0

---

## 11. Additional Edge Cases

**TC-025**
**Description**: DB connection failure
**Preconditions**: Invalid database credentials.
**Steps**:
1. Run any embedding script.
**Expected Result**: Connection error; exits code 1; no partial state.
**Priority**: P2

**TC-026**
**Description**: Duplicate source_id handling (skip-if-exists)
**Preconditions**: Table has existing embeddings.
**Steps**:
1. Run embedding script twice without `--reindex`.
**Expected Result**: Second run skips already-embedded source_ids (checks `SELECT 1 FROM memory_embeddings WHERE source_type = %s AND source_id = %s`); no duplicate rows; logs "already embedded" or "skipping".
**Priority**: P1

**TC-027**
**Description**: High volume — embed 10k+ rows
**Preconditions**: Full database with ~8800 source records.
**Steps**:
1. Run `embed-full-database.py` with timing.
**Expected Result**: Completes in reasonable time; all rows processed; no OOM or timeout.
**Priority**: P2

**TC-029**
**Description**: Zero rows to embed
**Preconditions**: All source records already embedded; run without `--reindex`.
**Steps**:
1. Run any embed script.
**Expected Result**: Logs "nothing to embed" or similar; exits code 0; no errors.
**Priority**: P2

**TC-030**
**Description**: Unicode query in proactive-recall
**Preconditions**: Table populated; Ollama up.
**Steps**:
1. Run `proactive-recall.py "🧠 minotaur café"`.
**Expected Result**: Query embeds and searches correctly; results returned.
**Priority**: P2

**TC-031**
**Description**: Empty query string
**Preconditions**: Table populated; Ollama up.
**Steps**:
1. Run `proactive-recall.py ""`.
**Expected Result**: Returns zero results or exits gracefully; no crash.
**Priority**: P2

**TC-032**
**Description**: IVFFlat index is used in search queries
**Preconditions**: Index rebuilt; table has 1000+ rows.
**Steps**:
1. Run `EXPLAIN ANALYZE` on the proactive-recall cosine search query.
**Expected Result**: Query plan shows "Index Scan using idx_memory_embeddings_vector"; no sequential scan.
**Priority**: P2

---

## 12. Performance

**TC-033**
**Description**: Batch embedding is faster than single
**Preconditions**: Ollama up; 100 texts to embed.
**Steps**:
1. Time batch embed (POST /api/embed with 100 texts).
2. Time 100 individual embeds (POST /api/embeddings one at a time).
**Expected Result**: Batch is measurably faster (fewer HTTP round trips).
**Priority**: P2

**TC-034**
**Description**: Large batch size handling
**Preconditions**: Ollama up; 500+ items to embed.
**Steps**:
1. Run with BATCH_SIZE=50 on 500 items.
**Expected Result**: 10 batches processed; all 500 items embedded; no errors.
**Priority**: P2

---

## 13. Recovery & Idempotency

**TC-035**
**Description**: Partial failure recovery — script interrupted mid-batch
**Preconditions**: Large embed run in progress.
**Steps**:
1. Kill script mid-run (Ctrl+C or kill PID).
2. Re-run the same script.
**Expected Result**: Previously committed batches are skipped (skip-if-exists); remaining items embedded; final state is complete.
**Priority**: P1

**TC-036**
**Description**: Migration rollback
**Preconditions**: Migration applied (column changed to vector(1024)).
**Steps**:
1. Rollback: `ALTER TABLE memory_embeddings DROP COLUMN embedding; ALTER TABLE memory_embeddings ADD COLUMN embedding vector(1536);`
**Expected Result**: Column restored to 1536; would need full re-embed with old model. Documented as rollback path.
**Priority**: P1

**TC-038**
**Description**: `--reindex` flag clears and re-embeds
**Preconditions**: Table has existing embeddings for a source type.
**Steps**:
1. Run `embed-full-database.py --reindex`.
**Expected Result**: All existing embeddings for that script's source types deleted; fresh embeddings created; row count matches source data.
**Priority**: P1

**TC-039**
**Description**: Confidence column preserved
**Preconditions**: Existing rows have varied `confidence` values.
**Steps**:
1. After re-embed, check `SELECT DISTINCT confidence FROM memory_embeddings;`.
**Expected Result**: Default confidence (1.0) applied to new rows; confidence values are consistent.
**Priority**: P1

**TC-040**
**Description**: Timestamps set on new embeddings
**Preconditions**: Fresh embed run.
**Steps**:
1. `SELECT created_at, updated_at FROM memory_embeddings ORDER BY created_at DESC LIMIT 5;`
**Expected Result**: `created_at` and `updated_at` reflect the embed run time; not stale dates.
**Priority**: P1

**TC-041**
**Description**: Same source_id in different source_types are separate rows
**Preconditions**: source_id "1" exists for both `entity` and `task` source_types.
**Steps**:
1. `SELECT source_type, source_id FROM memory_embeddings WHERE source_id = '1';`
**Expected Result**: Separate rows for each source_type; no collision.
**Priority**: P1
