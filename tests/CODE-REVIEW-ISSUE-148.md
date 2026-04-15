# Code Review: nova-mind Issue #148 (Ollama Embeddings Migration) - Phase 1: Desk Review Against Test Cases

**Date:** 2026-04-15  
**Reviewer:** QA Subagent (gem)  
**Repo:** ~/.openclaw/workspace/nova-mind  

## Summary
- **Files Reviewed:** 11/11  
- **Overall Coverage:** All critical TC (P0/P1) addressed via code inspection. P2 perf/edge mostly supported.  
- **Issues Found:** Minor gaps (no --reindex on embed-full-database.py; shell script lacks dim check). Non-blocking.  
- **Verdict:** **PASS** - Proceed to Phase 2 (Staging Tests). No loops needed.

## Per-File Review

### 1. `memory/scripts/embed-memories.py` **PASS**
- `load_embedding_config()`: Relative to script dir ✓ (TC-001,046)  
- No OpenAI ✓ (TC-022)  
- `/api/embeddings` (single/chunk) ✓ (TC-008)  
- Dim validation ✓ (TC-004)  
- Empty skip + warning ✓ (TC-009)  
- Per-chunk error (tx rollback on crash) ✓ (TC-017)  
- Timeout=30s ✓ (TC-019)  
- `--reindex` ✓ (TC-044)  
- Skip-if-exists ✓ (TC-026)  
- N/A batch (single OK for files)

### 2. `memory/scripts/embed-full-database.py` **PASS** (minor gap)
- `load_embedding_config()` ✓  
- No OpenAI ✓  
- `/api/embed` batch ✓ (TC-012)  
- Dim validation ✓  
- Empty filter (>5 chars) ✓  
- Per-batch error + rollback ✓ (TC-017,047)  
- Timeout=30s ✓  
- **Gap:** No `--reindex` flag (TC-013/038 suggest truncate/manual; code skips exists always)  
- Skip-if-exists ✓  
- `BATCH_SIZE=50` ✓ (TC-021)

### 3. `memory/scripts/embed-library.py` **PASS**
- `load_embedding_config()` ✓  
- No OpenAI ✓  
- `/api/embed` batch ✓ (TC-014)  
- Dim validation ✓  
- Empty filter (>5) ✓  
- Per-batch error + rollback ✓  
- Timeout=30s ✓  
- `--reindex` ✓ (TC-043)  
- Skip-if-exists ✓  
- `BATCH_SIZE=50` ✓

### 4. `memory/scripts/proactive-recall.py` **PASS**
- `load_embedding_config()` ✓  
- No OpenAI ✓  
- `/api/embeddings` single ✓ (TC-015)  
- Dim validation ✓  
- CLI flags preserved (`--threshold`, `--max-tokens`, +extras) ✓ (TC-045)  
- Timeout=30s ✓

### 5. `memory/scripts/embed-research.py` (NEW) **PASS**
- `load_embedding_config()` ✓  
- No OpenAI ✓  
- `/api/embed` batch ✓  
- Dim validation ✓  
- Empty filter (>5) ✓  
- Per-batch error + rollback ✓  
- Timeout=30s ✓  
- `--reindex` ✓  
- Skip-if-exists ✓  
- `BATCH_SIZE=50` ✓

### 6. `memory/scripts/embed-delegation-facts.sh` **PASS** (minor gap)
- Config relative to `SCRIPT_DIR` ✓  
- No OpenAI ✓  
- `/api/embeddings` single ✓  
- **Gap:** No explicit dim validation (PG vector insert will fail if mismatch; add jq check?) (TC-004)  
- Empty skip ✓  
- Per-item error handling ✓  
- `--max-time 30` ✓  
- Skip-if-exists (query) ✓

### 7. `memory/scripts/embedding-config.json` **PASS**
- Ollama/mxbai-embed-large/localhost:11434/1024 ✓

### 8. `memory/hooks/semantic-recall/handler.ts` **PASS**
- OPENAI_API_KEY guard **removed** ✓ (TC-022)  
- Otherwise **identical** to live `~/.openclaw/hooks/semantic-recall/handler.ts` ✓

### 9. `memory/migrations/008-ollama-embedding-dims.sql` **PASS**
- Drops index/col ✓  
- Adds `vector(1024)` ✓  
- Recreates index ✓ (TC-005,006)

### 10. `agent-install.sh` **PASS**
- Glob ~line 1013: `"$SCRIPTS_SOURCE"/*.sh *.py *.json` includes `*.json` ✓ (TC-046)

### 11. `memory/scripts/embed-memories-cron.sh` **PASS**
- `embed-research.py` added to sequence ✓ (TC-023)

## Unaddressed Test Cases
- None critical. P2 perf (TC-021 batch boundary, TC-027 high vol, TC-032 index usage, TC-033 batch speed) - code supports via batching/index.  
- TC-013/038: embed-full-database re-embed via truncate (manual OK per TC).

## Bugs/Gaps/Concerns
1. **embed-full-database.py:** Add `--reindex`? (truncate source_types before embed)  
2. **embed-delegation-facts.sh:** Add dim check: `jq 'length == 1024'` post-curl.  
3. **No crashes on Ollama down/malformed:** Scripts rollback/err gracefully.  
4. **Cron paths:** Uses `workspace/scripts/` (installer copies there) - verify post-install.  
5. **Source overlap (TC-048):** full-db excludes 'library'; research uses 'research'; good.

## Recommendations (Phase 2)
- Run full re-embed: `--reindex` all + migrate.  
- Verify dims: `SELECT DISTINCT vector_dims(embedding) FROM memory_embeddings;` → only 1024.  
- Test hook w/o OPENAI_API_KEY.

**Proceed to Phase 2: Practical Testing on Staging.**
