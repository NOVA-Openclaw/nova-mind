# Test Cases: Issue #10 — Auto-register Tables for Semantic Search

**Issue:** [#10 - Auto-register new tables for semantic search via event trigger](https://github.com/NOVA-Openclaw/nova-memory/issues/10)  
**Date:** 2026-02-11  
**Author:** Nova (subagent)

---

## Context

The feature extends the existing `schema_change_trigger` (DDL event trigger → `notify_schema_change()`) to automatically detect new tables with text columns, register them in `embeddable_tables`, create row-level INSERT/UPDATE triggers via `create_embedding_trigger()`, and queue rows in `embedding_queue` for async embedding into `memory_embeddings`.

### Key Tables (new)
- `embeddable_tables` — registry of tables to embed
- `embedding_queue` — async processing queue (UNIQUE on `table_name, row_id`)

### Key Functions (new/modified)
- `notify_schema_change()` — extended to detect CREATE TABLE + auto-register
- `queue_for_embedding()` — row-level trigger function (INSERT/UPDATE → queue)
- `create_embedding_trigger(tbl TEXT)` — generates per-table row triggers

### Existing Schema Reference
- `memory_embeddings` — vector(1536), columns: `source_type`, `source_id`, `content`, `embedding`
- `embed_chat_message()` — existing trigger pattern (model for new work)
- Embedding model: `text-embedding-3-small` (1536 dims)

---

## 1. Happy Path Tests

### TEST-1.1: New table with TEXT column auto-registered

| Field | Value |
|-------|-------|
| **Test Name** | `test_new_table_text_column_auto_registered` |
| **Description** | Creating a table with a TEXT column should auto-register it in `embeddable_tables` with `auto_registered=true` |
| **Setup** | Clean database with `embeddable_tables` empty. Event trigger active. |
| **Input/Action** | `CREATE TABLE blog_posts (id SERIAL PRIMARY KEY, title TEXT, content TEXT, created_at TIMESTAMPTZ);` |
| **Expected Result** | Row inserted into `embeddable_tables` with: `table_name='blog_posts'`, `content_column` is one of the TEXT columns (preferring `content` by name heuristic), `source_type='blog_posts'`, `enabled=true`, `auto_registered=true`. A row-level trigger `embed_blog_posts_trigger` exists on `blog_posts`. |
| **Test Type** | Integration |

### TEST-1.2: INSERT into auto-registered table queues embedding

| Field | Value |
|-------|-------|
| **Test Name** | `test_insert_triggers_embedding_queue` |
| **Description** | Inserting a row into an auto-registered table should add an entry to `embedding_queue` |
| **Setup** | `blog_posts` table created and auto-registered (TEST-1.1 completed). |
| **Input/Action** | `INSERT INTO blog_posts (title, content) VALUES ('Hello World', 'This is my first blog post about PostgreSQL triggers.');` |
| **Expected Result** | Row in `embedding_queue` with: `table_name='blog_posts'`, `row_id` matching the inserted row's id, `operation='INSERT'`, `processed_at IS NULL`. |
| **Test Type** | Integration |

### TEST-1.3: Processing queue generates embedding in memory_embeddings

| Field | Value |
|-------|-------|
| **Test Name** | `test_queue_processing_creates_embedding` |
| **Description** | The background processor should read from `embedding_queue`, fetch content, generate embedding, and insert into `memory_embeddings` |
| **Setup** | Row in `embedding_queue` for `blog_posts` row (TEST-1.2 completed). OpenAI API key available (or mocked). |
| **Input/Action** | Run `process-embedding-queue.py` (or invoke its main function). |
| **Expected Result** | 1. Row in `memory_embeddings` with `source_type='blog_posts'`, `source_id` matching the blog post id, `content` containing the blog post content, `embedding` is a non-null 1536-dim vector. 2. `embedding_queue` entry has `processed_at IS NOT NULL`. |
| **Test Type** | Integration |

### TEST-1.4: End-to-end flow — CREATE TABLE → INSERT → embedding

| Field | Value |
|-------|-------|
| **Test Name** | `test_end_to_end_auto_register_and_embed` |
| **Description** | Full lifecycle: create table → insert row → process queue → verify embedding exists |
| **Setup** | Clean database. Event trigger active. Background processor available. |
| **Input/Action** | 1. `CREATE TABLE notes (id SERIAL PRIMARY KEY, body TEXT);` 2. `INSERT INTO notes (body) VALUES ('Meeting notes from standup');` 3. Run background processor. |
| **Expected Result** | `memory_embeddings` contains a row with `source_type='notes'`, `content` including 'Meeting notes from standup', `embedding IS NOT NULL`. |
| **Test Type** | Integration (end-to-end) |

### TEST-1.5: Manual registration overrides auto-registration

| Field | Value |
|-------|-------|
| **Test Name** | `test_manual_registration_override` |
| **Description** | Manually inserting into `embeddable_tables` before creating the table should be respected (no duplicate auto-registration) |
| **Setup** | Pre-insert into `embeddable_tables`: `INSERT INTO embeddable_tables (table_name, content_column, source_type, auto_registered) VALUES ('articles', 'summary', 'article_summaries', false);` |
| **Input/Action** | `CREATE TABLE articles (id SERIAL PRIMARY KEY, title TEXT, summary TEXT, full_text TEXT);` |
| **Expected Result** | `embeddable_tables` still has exactly one row for `articles` with `content_column='summary'` and `auto_registered=false` (the manual entry). The row-level trigger uses the `summary` column. |
| **Test Type** | Integration |

---

## 2. Exclusion Tests

### TEST-2.1: Table in explicit exclusion list is skipped

| Field | Value |
|-------|-------|
| **Test Name** | `test_explicit_exclusion_list` |
| **Description** | Tables explicitly listed in exclusion config/table should not be auto-registered |
| **Setup** | Add exclusion: table name `audit_trail` added to exclusion mechanism (e.g., `INSERT INTO semantic_search_excluded (table_name) VALUES ('audit_trail');` or config). |
| **Input/Action** | `CREATE TABLE audit_trail (id SERIAL PRIMARY KEY, action TEXT, details TEXT, timestamp TIMESTAMPTZ);` |
| **Expected Result** | No row in `embeddable_tables` for `audit_trail`. No row-level trigger created on `audit_trail`. |
| **Test Type** | Integration |

### TEST-2.2: Table matching *_queue pattern is skipped

| Field | Value |
|-------|-------|
| **Test Name** | `test_queue_pattern_exclusion` |
| **Description** | Tables ending in `_queue` should be excluded by pattern matching |
| **Setup** | Event trigger active with pattern exclusion for `*_queue`. |
| **Input/Action** | `CREATE TABLE email_queue (id SERIAL PRIMARY KEY, recipient TEXT, body TEXT, sent_at TIMESTAMPTZ);` |
| **Expected Result** | No row in `embeddable_tables` for `email_queue`. No row-level trigger created. |
| **Test Type** | Integration |

### TEST-2.3: Table matching *_log pattern is skipped

| Field | Value |
|-------|-------|
| **Test Name** | `test_log_pattern_exclusion` |
| **Description** | Tables ending in `_log` should be excluded by pattern matching |
| **Setup** | Event trigger active with pattern exclusion for `*_log`. |
| **Input/Action** | `CREATE TABLE access_log (id SERIAL PRIMARY KEY, ip_address TEXT, request_path TEXT, response_code INT);` |
| **Expected Result** | No row in `embeddable_tables` for `access_log`. No row-level trigger created. |
| **Test Type** | Integration |

### TEST-2.4: pg_* system tables are never registered

| Field | Value |
|-------|-------|
| **Test Name** | `test_pg_prefix_exclusion` |
| **Description** | Tables starting with `pg_` (system catalog convention) should always be excluded |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE pg_custom_config (id SERIAL PRIMARY KEY, setting_name TEXT, setting_value TEXT);` (Note: This requires superuser or appropriate permissions; may need to be tested via inspection of the exclusion logic.) |
| **Expected Result** | No row in `embeddable_tables` for `pg_custom_config`. |
| **Test Type** | Unit (test the exclusion check function directly) |

### TEST-2.5: Tables in internal schemas excluded (information_schema, pg_catalog)

| Field | Value |
|-------|-------|
| **Test Name** | `test_system_schema_exclusion` |
| **Description** | Tables not in `public` schema (or configured schemas) should be skipped |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE SCHEMA internal; CREATE TABLE internal.temp_data (id SERIAL PRIMARY KEY, notes TEXT);` |
| **Expected Result** | No row in `embeddable_tables` for `internal.temp_data` (unless `internal` schema is explicitly opted in). |
| **Test Type** | Integration |

### TEST-2.6: The embedding_queue table itself is not registered

| Field | Value |
|-------|-------|
| **Test Name** | `test_meta_tables_excluded` |
| **Description** | Infrastructure tables (`embeddable_tables`, `embedding_queue`, `memory_embeddings`) should not be self-registered |
| **Setup** | Fresh setup where these tables are being created. |
| **Input/Action** | Verify after running schema setup that `embeddable_tables` does not contain entries for `embeddable_tables`, `embedding_queue`, or `memory_embeddings`. |
| **Expected Result** | Zero rows in `embeddable_tables` matching those table names. |
| **Test Type** | Integration |

### TEST-2.7: Exclusion pattern *_archive is skipped

| Field | Value |
|-------|-------|
| **Test Name** | `test_archive_pattern_exclusion` |
| **Description** | Tables ending in `_archive` should be excluded (they are historical copies) |
| **Setup** | Event trigger active with pattern exclusion for `*_archive`. |
| **Input/Action** | `CREATE TABLE memory_embeddings_archive_v2 (id SERIAL PRIMARY KEY, content TEXT);` |
| **Expected Result** | No row in `embeddable_tables` for `memory_embeddings_archive_v2`. |
| **Test Type** | Integration |

### TEST-2.8: Disabled table in embeddable_tables is not re-enabled

| Field | Value |
|-------|-------|
| **Test Name** | `test_disabled_table_not_reenabled` |
| **Description** | If a table exists in `embeddable_tables` with `enabled=false`, the auto-register logic should not re-enable it |
| **Setup** | `INSERT INTO embeddable_tables (table_name, content_column, enabled, auto_registered) VALUES ('user_feedback', 'comment', false, true);` Then drop and recreate the table. |
| **Input/Action** | `DROP TABLE IF EXISTS user_feedback; CREATE TABLE user_feedback (id SERIAL PRIMARY KEY, comment TEXT);` |
| **Expected Result** | `embeddable_tables` row for `user_feedback` still has `enabled=false`. |
| **Test Type** | Integration |

---

## 3. Edge Cases

### TEST-3.1: Table with no text columns is skipped

| Field | Value |
|-------|-------|
| **Test Name** | `test_no_text_columns_skipped` |
| **Description** | A table with only numeric/date columns should not be registered |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE sensor_readings (id SERIAL PRIMARY KEY, temperature FLOAT, humidity FLOAT, recorded_at TIMESTAMPTZ);` |
| **Expected Result** | No row in `embeddable_tables` for `sensor_readings`. No row-level trigger created. |
| **Test Type** | Integration |

### TEST-3.2: Table with multiple text columns — preferred name wins

| Field | Value |
|-------|-------|
| **Test Name** | `test_multiple_text_columns_preferred_name` |
| **Description** | When multiple text columns exist, prefer well-known names (`content`, `text`, `body`, `message`, `description`) |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE forum_posts (id SERIAL PRIMARY KEY, author TEXT, title TEXT, body TEXT, metadata TEXT);` |
| **Expected Result** | `embeddable_tables` row for `forum_posts` has `content_column='body'` (preferred name). |
| **Test Type** | Integration |

### TEST-3.3: Table with multiple text columns — no preferred name → first TEXT column

| Field | Value |
|-------|-------|
| **Test Name** | `test_multiple_text_columns_first_wins` |
| **Description** | When no preferred column names match, pick the first TEXT column (by ordinal position) |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE raw_data (id SERIAL PRIMARY KEY, field_a TEXT, field_b TEXT, field_c TEXT);` |
| **Expected Result** | `embeddable_tables` row for `raw_data` has `content_column='field_a'` (first by ordinal position). |
| **Test Type** | Integration |

### TEST-3.4: Table renamed — handle gracefully

| Field | Value |
|-------|-------|
| **Test Name** | `test_table_rename_updates_registry` |
| **Description** | Renaming a registered table should update `embeddable_tables` or handle it without errors |
| **Setup** | `blog_posts` table exists and is registered in `embeddable_tables`. |
| **Input/Action** | `ALTER TABLE blog_posts RENAME TO articles;` |
| **Expected Result** | One of: (a) `embeddable_tables` row updated to `table_name='articles'`, OR (b) old `blog_posts` entry marked disabled and new `articles` entry created, OR (c) at minimum, no errors and the system handles the stale reference on next queue processing. The DDL trigger fires and the rename is detected. |
| **Test Type** | Integration |

### TEST-3.5: Table dropped — cleanup registry and queue

| Field | Value |
|-------|-------|
| **Test Name** | `test_table_drop_cleanup` |
| **Description** | Dropping a registered table should clean up or disable the `embeddable_tables` entry and remove pending queue items |
| **Setup** | `blog_posts` table exists, is registered in `embeddable_tables`, and has pending items in `embedding_queue`. |
| **Input/Action** | `DROP TABLE blog_posts;` |
| **Expected Result** | `embeddable_tables` row for `blog_posts` either deleted or set to `enabled=false`. Pending `embedding_queue` entries for `blog_posts` are either removed or marked as cancelled. No orphaned data. |
| **Test Type** | Integration |

### TEST-3.6: CREATE TABLE IF NOT EXISTS on existing table

| Field | Value |
|-------|-------|
| **Test Name** | `test_create_if_not_exists_idempotent` |
| **Description** | `CREATE TABLE IF NOT EXISTS` on an already-registered table should not create duplicates |
| **Setup** | `blog_posts` table exists and is registered in `embeddable_tables`. |
| **Input/Action** | `CREATE TABLE IF NOT EXISTS blog_posts (id SERIAL PRIMARY KEY, content TEXT);` |
| **Expected Result** | No duplicate row in `embeddable_tables`. Exactly one row for `blog_posts`. No errors. |
| **Test Type** | Integration |

### TEST-3.7: Temporary table should not be registered

| Field | Value |
|-------|-------|
| **Test Name** | `test_temporary_table_skipped` |
| **Description** | Temporary tables should not be auto-registered (they're session-scoped) |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TEMPORARY TABLE tmp_import (id SERIAL, data TEXT);` |
| **Expected Result** | No row in `embeddable_tables` for `tmp_import`. |
| **Test Type** | Integration |

### TEST-3.8: Table with only a single VARCHAR(10) column

| Field | Value |
|-------|-------|
| **Test Name** | `test_short_varchar_skipped_or_registered` |
| **Description** | Very short VARCHAR columns (e.g., status codes) may not be useful for embedding. Design decision: skip VARCHAR < some threshold? |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE status_codes (id SERIAL PRIMARY KEY, code VARCHAR(10), label VARCHAR(20));` |
| **Expected Result** | **Design decision needed.** Either: (a) skipped because no column is long enough for meaningful embedding, or (b) registered with `label` as content column. Document the threshold. |
| **Test Type** | Unit |

### TEST-3.9: Column added to existing non-registered table

| Field | Value |
|-------|-------|
| **Test Name** | `test_alter_table_add_text_column` |
| **Description** | Adding a TEXT column to an existing table that was previously skipped (no text columns) — should it now be registered? |
| **Setup** | `sensor_readings` exists with only numeric columns (not registered). |
| **Input/Action** | `ALTER TABLE sensor_readings ADD COLUMN notes TEXT;` |
| **Expected Result** | **Design decision needed.** Either: (a) newly registered since it now has a text column, or (b) not registered (only CREATE TABLE triggers auto-registration). Document the behavior. |
| **Test Type** | Integration |

---

## 4. Column Detection Tests

### TEST-4.1: TEXT column detected

| Field | Value |
|-------|-------|
| **Test Name** | `test_detect_text_column` |
| **Description** | A column of type `TEXT` should be recognized as embeddable |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE docs (id SERIAL PRIMARY KEY, content TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='content'`. |
| **Test Type** | Unit (test the column detection function directly) |

### TEST-4.2: VARCHAR column detected

| Field | Value |
|-------|-------|
| **Test Name** | `test_detect_varchar_column` |
| **Description** | A column of type `VARCHAR` (or `CHARACTER VARYING`) should be recognized as embeddable |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE messages (id SERIAL PRIMARY KEY, body VARCHAR(5000));` |
| **Expected Result** | `embeddable_tables` row with `content_column='body'`. |
| **Test Type** | Unit |

### TEST-4.3: VARCHAR without length (unbounded) detected

| Field | Value |
|-------|-------|
| **Test Name** | `test_detect_varchar_unbounded` |
| **Description** | `VARCHAR` without length limit is equivalent to TEXT in PostgreSQL |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE snippets (id SERIAL PRIMARY KEY, code VARCHAR);` |
| **Expected Result** | `embeddable_tables` row with `content_column='code'`. |
| **Test Type** | Unit |

### TEST-4.4: JSONB column — design decision

| Field | Value |
|-------|-------|
| **Test Name** | `test_jsonb_column_handling` |
| **Description** | JSONB columns may contain text but are structured. Should they be included? |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE api_responses (id SERIAL PRIMARY KEY, payload JSONB, raw_text TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='raw_text'` (TEXT preferred over JSONB). If JSONB is the only candidate: **design decision** — skip or register with a note that extraction logic is needed. |
| **Test Type** | Unit |

### TEST-4.5: JSONB-only table — skip or register?

| Field | Value |
|-------|-------|
| **Test Name** | `test_jsonb_only_table` |
| **Description** | Table with only JSONB and no TEXT/VARCHAR — should it be registered? |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE json_store (id SERIAL PRIMARY KEY, data JSONB, metadata JSONB);` |
| **Expected Result** | **Design decision needed.** Recommended: skip. JSONB requires extraction logic that the generic queue processor doesn't have. |
| **Test Type** | Unit |

### TEST-4.6: Preferred column name 'content' selected over generic TEXT

| Field | Value |
|-------|-------|
| **Test Name** | `test_prefer_content_column_name` |
| **Description** | Column named `content` should be preferred over other TEXT columns |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE pages (id SERIAL PRIMARY KEY, url TEXT, content TEXT, metadata TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='content'`. |
| **Test Type** | Unit |

### TEST-4.7: Preferred column name 'message' selected

| Field | Value |
|-------|-------|
| **Test Name** | `test_prefer_message_column_name` |
| **Description** | Column named `message` should be preferred |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE chat_logs (id SERIAL PRIMARY KEY, sender TEXT, message TEXT, room TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='message'`. |
| **Test Type** | Unit |

### TEST-4.8: Preferred column name 'description' selected

| Field | Value |
|-------|-------|
| **Test Name** | `test_prefer_description_column_name` |
| **Description** | Column named `description` should be preferred |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE products (id SERIAL PRIMARY KEY, name TEXT, description TEXT, sku TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='description'`. |
| **Test Type** | Unit |

### TEST-4.9: Preferred column name 'body' selected

| Field | Value |
|-------|-------|
| **Test Name** | `test_prefer_body_column_name` |
| **Description** | Column named `body` should be preferred |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE emails (id SERIAL PRIMARY KEY, subject TEXT, body TEXT, sender TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='body'`. |
| **Test Type** | Unit |

### TEST-4.10: Preferred column name 'text' selected

| Field | Value |
|-------|-------|
| **Test Name** | `test_prefer_text_column_name` |
| **Description** | Column named `text` should be preferred |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE entries (id SERIAL PRIMARY KEY, label TEXT, text TEXT, category TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='text'`. |
| **Test Type** | Unit |

### TEST-4.11: Priority among preferred names

| Field | Value |
|-------|-------|
| **Test Name** | `test_preferred_name_priority_order` |
| **Description** | When multiple preferred names exist, verify priority order: `content` > `text` > `body` > `message` > `description` |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE multi_preferred (id SERIAL PRIMARY KEY, description TEXT, body TEXT, content TEXT);` |
| **Expected Result** | `embeddable_tables` row with `content_column='content'` (highest priority). |
| **Test Type** | Unit |

### TEST-4.12: id_column detection — non-standard primary key

| Field | Value |
|-------|-------|
| **Test Name** | `test_custom_id_column_detection` |
| **Description** | If the primary key column is not `id`, it should still be correctly identified |
| **Setup** | Event trigger active. |
| **Input/Action** | `CREATE TABLE wiki_pages (page_id SERIAL PRIMARY KEY, slug TEXT, content TEXT);` |
| **Expected Result** | `embeddable_tables` row with `id_column='page_id'` (or whatever the actual PK column is). |
| **Test Type** | Unit |

---

## 5. Queue / Processing Tests

### TEST-5.1: INSERT queues embedding

| Field | Value |
|-------|-------|
| **Test Name** | `test_insert_queues_embedding` |
| **Description** | An INSERT on a registered table should create a queue entry with operation=INSERT |
| **Setup** | `docs` table registered in `embeddable_tables` with trigger active. |
| **Input/Action** | `INSERT INTO docs (content) VALUES ('Some interesting document content');` |
| **Expected Result** | `embedding_queue` row: `table_name='docs'`, `row_id` = new row's id, `operation='INSERT'`, `processed_at IS NULL`. |
| **Test Type** | Integration |

### TEST-5.2: UPDATE queues embedding

| Field | Value |
|-------|-------|
| **Test Name** | `test_update_queues_embedding` |
| **Description** | An UPDATE on the content column of a registered table should create a queue entry with operation=UPDATE |
| **Setup** | `docs` table with existing row. Registered in `embeddable_tables` with trigger active. |
| **Input/Action** | `UPDATE docs SET content = 'Updated document content' WHERE id = 1;` |
| **Expected Result** | `embedding_queue` row: `table_name='docs'`, `row_id='1'`, `operation='UPDATE'`, `processed_at IS NULL`. |
| **Test Type** | Integration |

### TEST-5.3: Duplicate entries deduplicated via UNIQUE constraint

| Field | Value |
|-------|-------|
| **Test Name** | `test_queue_deduplication` |
| **Description** | Multiple changes to the same row before processing should result in only one pending queue entry |
| **Setup** | `docs` table registered. Row id=1 exists. |
| **Input/Action** | 1. `UPDATE docs SET content = 'First update' WHERE id = 1;` 2. `UPDATE docs SET content = 'Second update' WHERE id = 1;` |
| **Expected Result** | Only one unprocessed row in `embedding_queue` for `(table_name='docs', row_id='1')`. The UNIQUE constraint on `(table_name, row_id)` ensures dedup. The trigger should use `ON CONFLICT ... DO UPDATE` to update `operation` and `queued_at`. |
| **Test Type** | Integration |

### TEST-5.4: Processing clears queue (marks as processed)

| Field | Value |
|-------|-------|
| **Test Name** | `test_processing_marks_completed` |
| **Description** | After the background processor handles a queue entry, it should be marked as processed |
| **Setup** | Pending entries in `embedding_queue`. |
| **Input/Action** | Run background processor. |
| **Expected Result** | All formerly-pending entries now have `processed_at IS NOT NULL` with a recent timestamp. |
| **Test Type** | Integration |

### TEST-5.5: Batch INSERT queues multiple entries

| Field | Value |
|-------|-------|
| **Test Name** | `test_batch_insert_queues_all` |
| **Description** | A multi-row INSERT should queue each row individually |
| **Setup** | `docs` table registered. |
| **Input/Action** | `INSERT INTO docs (content) VALUES ('Doc one'), ('Doc two'), ('Doc three');` |
| **Expected Result** | Three rows in `embedding_queue`, one per inserted document. |
| **Test Type** | Integration |

### TEST-5.6: DELETE does not queue (or queues for cleanup)

| Field | Value |
|-------|-------|
| **Test Name** | `test_delete_handling` |
| **Description** | Deleting a row from a registered table — should this trigger cleanup of the corresponding embedding? |
| **Setup** | `docs` table registered with row id=1 that has been embedded. |
| **Input/Action** | `DELETE FROM docs WHERE id = 1;` |
| **Expected Result** | **Design decision needed.** Either: (a) queue a DELETE operation that the processor uses to remove from `memory_embeddings`, or (b) no queue entry (orphaned embedding cleaned up by maintenance). Recommended: queue DELETE for cleanup. |
| **Test Type** | Integration |

### TEST-5.7: UPDATE on non-content column doesn't re-queue

| Field | Value |
|-------|-------|
| **Test Name** | `test_update_non_content_column_skipped` |
| **Description** | Updating a column that isn't the registered content column should not trigger re-embedding |
| **Setup** | `blog_posts` table registered with `content_column='content'`. Row id=1 exists. |
| **Input/Action** | `UPDATE blog_posts SET title = 'New Title' WHERE id = 1;` |
| **Expected Result** | **Design decision needed.** Either: (a) no new queue entry (trigger checks if content column changed), or (b) queue entry created anyway (simpler but wasteful). Recommended: check `OLD.content IS DISTINCT FROM NEW.content` in trigger. |
| **Test Type** | Integration |

### TEST-5.8: Queue processing order — FIFO

| Field | Value |
|-------|-------|
| **Test Name** | `test_queue_fifo_processing` |
| **Description** | Queue should be processed in order of `queued_at` (oldest first) |
| **Setup** | Multiple entries in `embedding_queue` with different `queued_at` timestamps. |
| **Input/Action** | Run background processor with batch size = 2. |
| **Expected Result** | The two oldest entries are processed first. |
| **Test Type** | Unit (test processor's SELECT query ordering) |

### TEST-5.9: Concurrent inserts don't cause deadlocks

| Field | Value |
|-------|-------|
| **Test Name** | `test_concurrent_inserts_no_deadlock` |
| **Description** | Multiple simultaneous inserts into a registered table should not cause deadlocks on the queue |
| **Setup** | `docs` table registered. |
| **Input/Action** | Run 10 concurrent `INSERT INTO docs (content) VALUES ('Concurrent content N');` statements. |
| **Expected Result** | All 10 rows inserted successfully. All 10 queue entries created. No deadlocks or errors. |
| **Test Type** | Integration (load/stress) |

---

## 6. Error Handling Tests

### TEST-6.1: API failure during embedding — retry semantics

| Field | Value |
|-------|-------|
| **Test Name** | `test_api_failure_retry` |
| **Description** | If the OpenAI API call fails, the queue entry should remain unprocessed for retry |
| **Setup** | Entry in `embedding_queue`. Mock or break the OpenAI API endpoint. |
| **Input/Action** | Run background processor. |
| **Expected Result** | Queue entry remains with `processed_at IS NULL`. Error is logged. Processor does not crash. Entry will be retried on next run. |
| **Test Type** | Unit (mock API client) |

### TEST-6.2: API rate limiting — backoff

| Field | Value |
|-------|-------|
| **Test Name** | `test_api_rate_limit_backoff` |
| **Description** | When API returns 429 (rate limited), processor should back off |
| **Setup** | Many entries in queue. Mock API to return 429 after N requests. |
| **Input/Action** | Run background processor. |
| **Expected Result** | Processor processes first N entries, receives 429, backs off (sleeps/retries with delay), then continues. Remaining entries stay queued. |
| **Test Type** | Unit (mock API client) |

### TEST-6.3: NULL content in source table

| Field | Value |
|-------|-------|
| **Test Name** | `test_null_content_skipped` |
| **Description** | If the content column is NULL for a queued row, the processor should skip it |
| **Setup** | `docs` table registered. Insert row with `content = NULL`. |
| **Input/Action** | `INSERT INTO docs (content) VALUES (NULL);` then run processor. |
| **Expected Result** | Queue entry marked as processed (or with an error flag). No row inserted into `memory_embeddings`. No crash. |
| **Test Type** | Integration |

### TEST-6.4: Empty string content

| Field | Value |
|-------|-------|
| **Test Name** | `test_empty_content_skipped` |
| **Description** | Empty string content should be skipped (not worth embedding) |
| **Setup** | `docs` table registered. |
| **Input/Action** | `INSERT INTO docs (content) VALUES ('');` then run processor. |
| **Expected Result** | Queue entry marked processed. No embedding created. Warning logged. |
| **Test Type** | Integration |

### TEST-6.5: Very long content — truncation

| Field | Value |
|-------|-------|
| **Test Name** | `test_very_long_content_truncated` |
| **Description** | Content exceeding the embedding model's token limit (~8191 tokens for text-embedding-3-small) should be truncated |
| **Setup** | `docs` table registered. |
| **Input/Action** | `INSERT INTO docs (content) VALUES (repeat('word ', 50000));` (creates ~250K chars / ~62K tokens) then run processor. |
| **Expected Result** | Embedding created with truncated content. `memory_embeddings.content` stores the full or truncated content (design decision). Embedding generated from first ~8000 tokens. No API error. |
| **Test Type** | Integration |

### TEST-6.6: Source row deleted before processing

| Field | Value |
|-------|-------|
| **Test Name** | `test_source_row_deleted_before_processing` |
| **Description** | If the source row is deleted between queuing and processing, handle gracefully |
| **Setup** | Insert row into `docs`, verify queue entry, then delete the row. |
| **Input/Action** | Run background processor. |
| **Expected Result** | Processor detects missing row, marks queue entry as processed (or error). No crash. Warning logged. |
| **Test Type** | Integration |

### TEST-6.7: Source table dropped before processing

| Field | Value |
|-------|-------|
| **Test Name** | `test_source_table_dropped_before_processing` |
| **Description** | If the registered table is dropped while queue entries exist, handle gracefully |
| **Setup** | Queue entries for `temp_table`. Then `DROP TABLE temp_table;`. |
| **Input/Action** | Run background processor. |
| **Expected Result** | Processor catches the error (table doesn't exist), marks entries as failed, logs error, continues processing other tables' entries. |
| **Test Type** | Integration |

### TEST-6.8: Database connection failure during processing

| Field | Value |
|-------|-------|
| **Test Name** | `test_db_connection_failure` |
| **Description** | If database connection drops during processing, the processor should handle it |
| **Setup** | Queue entries exist. Simulate connection failure. |
| **Input/Action** | Run background processor with flaky connection. |
| **Expected Result** | Processor catches connection error, logs it, exits cleanly (or retries). No partial state corruption. Queue entries remain unprocessed for next run. |
| **Test Type** | Unit (mock database) |

### TEST-6.9: Embedding dimension mismatch

| Field | Value |
|-------|-------|
| **Test Name** | `test_embedding_dimension_mismatch` |
| **Description** | If the API returns a vector of unexpected dimensions, handle gracefully |
| **Setup** | Mock API to return wrong-dimension vector (e.g., 768 instead of 1536). |
| **Input/Action** | Run background processor. |
| **Expected Result** | Insert into `memory_embeddings` fails (vector column constraint). Error logged. Queue entry remains for retry or is marked as failed. |
| **Test Type** | Unit (mock API) |

### TEST-6.10: Processor idempotency — double-run safety

| Field | Value |
|-------|-------|
| **Test Name** | `test_processor_idempotent` |
| **Description** | Running the processor twice should not create duplicate embeddings |
| **Setup** | Queue entries exist. |
| **Input/Action** | Run processor twice. |
| **Expected Result** | First run processes entries. Second run finds nothing to process (all have `processed_at` set). No duplicate `memory_embeddings` rows. |
| **Test Type** | Integration |

---

## 7. Background Processor Script Tests

### TEST-7.1: Processor runs with no pending items

| Field | Value |
|-------|-------|
| **Test Name** | `test_processor_empty_queue` |
| **Description** | Running the processor when the queue is empty should exit cleanly |
| **Setup** | Empty `embedding_queue` (or all entries processed). |
| **Input/Action** | Run `process-embedding-queue.py`. |
| **Expected Result** | Script exits with code 0. Logs "No pending items" or similar. |
| **Test Type** | Unit |

### TEST-7.2: Processor batch size limiting

| Field | Value |
|-------|-------|
| **Test Name** | `test_processor_batch_size` |
| **Description** | Processor should respect a configurable batch size to avoid overwhelming the API |
| **Setup** | 100 pending entries in queue. Batch size configured to 10. |
| **Input/Action** | Run processor once. |
| **Expected Result** | Exactly 10 entries processed. 90 remain pending. |
| **Test Type** | Unit |

### TEST-7.3: Processor respects rate limits

| Field | Value |
|-------|-------|
| **Test Name** | `test_processor_rate_limiting` |
| **Description** | Processor should include delays between API calls to respect rate limits |
| **Setup** | Multiple pending entries. |
| **Input/Action** | Run processor with timing instrumentation. |
| **Expected Result** | Minimum delay between successive API calls is respected (e.g., 100ms or configurable). |
| **Test Type** | Unit |

### TEST-7.4: Processor handles missing OpenAI API key

| Field | Value |
|-------|-------|
| **Test Name** | `test_processor_missing_api_key` |
| **Description** | If `OPENAI_API_KEY` is not set, processor should fail fast with clear error |
| **Setup** | Unset `OPENAI_API_KEY` environment variable. |
| **Input/Action** | Run processor. |
| **Expected Result** | Script exits with non-zero code. Clear error message about missing API key. No queue entries modified. |
| **Test Type** | Unit |

### TEST-7.5: Processor handles database connection string

| Field | Value |
|-------|-------|
| **Test Name** | `test_processor_db_connection` |
| **Description** | Processor should connect using the same DB naming convention as `proactive-recall.py` (`{user}_memory`) |
| **Setup** | Correct database exists. |
| **Input/Action** | Run processor. |
| **Expected Result** | Successfully connects to database. Follows `get_db_name()` pattern from existing scripts. |
| **Test Type** | Unit |

---

## 8. Integration with Existing System

### TEST-8.1: Existing embed_chat_message trigger unaffected

| Field | Value |
|-------|-------|
| **Test Name** | `test_existing_chat_trigger_unaffected` |
| **Description** | The new auto-registration system should not interfere with the existing `embed_chat_message()` trigger |
| **Setup** | Full schema with both old and new triggers. |
| **Input/Action** | Insert into the table that uses `embed_chat_message()`. |
| **Expected Result** | Existing trigger still fires correctly. `memory_embeddings` gets the chat message entry as before. No conflicts. |
| **Test Type** | Integration (regression) |

### TEST-8.2: Proactive recall finds auto-registered embeddings

| Field | Value |
|-------|-------|
| **Test Name** | `test_proactive_recall_finds_new_embeddings` |
| **Description** | Embeddings created by the new system should be discoverable by `proactive-recall.py` |
| **Setup** | Auto-registered table with processed embeddings in `memory_embeddings`. |
| **Input/Action** | Run `proactive-recall.py "query matching embedded content"`. |
| **Expected Result** | Results include the auto-embedded content with appropriate `source_type` (the table name). |
| **Test Type** | Integration (end-to-end) |

### TEST-8.3: source_type in memory_embeddings is consistent

| Field | Value |
|-------|-------|
| **Test Name** | `test_source_type_consistency` |
| **Description** | Auto-registered tables should use the table name as `source_type` in `memory_embeddings`, consistent with existing patterns |
| **Setup** | Auto-registered `blog_posts` table with processed embeddings. |
| **Input/Action** | `SELECT DISTINCT source_type FROM memory_embeddings WHERE source_type = 'blog_posts';` |
| **Expected Result** | Rows exist. `source_type` matches the table name. Consistent with existing `source_type='agent_chat'` pattern. |
| **Test Type** | Integration |

---

## Summary

| Category | Count | Types |
|----------|-------|-------|
| Happy Path | 5 | Integration, E2E |
| Exclusion | 8 | Integration, Unit |
| Edge Cases | 9 | Integration, Unit |
| Column Detection | 12 | Unit, Integration |
| Queue/Processing | 9 | Integration, Unit, Stress |
| Error Handling | 10 | Unit, Integration |
| Background Processor | 5 | Unit |
| System Integration | 3 | Integration, Regression, E2E |
| **Total** | **61** | |

## Open Design Questions

These emerged during test case design and need resolution before implementation:

1. **JSONB handling:** Should JSONB-only tables be registered? (TEST-4.5) — Recommend: skip.
2. **Short VARCHAR threshold:** Minimum VARCHAR length to consider embeddable? (TEST-3.8) — Suggest: no minimum, but document.
3. **ALTER TABLE ADD COLUMN:** Should adding a text column to an existing table trigger registration? (TEST-3.9) — Suggest: yes, for completeness.
4. **DELETE handling:** Should row deletion queue a cleanup operation? (TEST-5.6) — Recommend: yes, queue DELETE operation.
5. **Non-content column updates:** Should updating a non-content column re-queue? (TEST-5.7) — Recommend: only re-queue when content column changes.
6. **Table rename behavior:** Update in place vs. disable + re-register? (TEST-3.4) — Suggest: update in place.
7. **Table drop cleanup:** Auto-cleanup or leave for maintenance? (TEST-3.5) — Recommend: auto-disable + clean pending queue.

---

*Generated for nova-memory issue #10. Tests reference existing schema patterns (see `schema.sql` lines 500-530 for `embed_chat_message()`, 630-660 for `notify_schema_change()`, 2681-2750 for `memory_embeddings`).*
