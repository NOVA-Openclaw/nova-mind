# Library Schema

A structured storage system for written works — research papers, books, novels, poems, essays, articles, and more — with semantic search via embeddings and full-text search via tsvector.

## Overview

The library stores all kinds of written works in a normalized schema with:

- **Required metadata** — Database constraints enforce complete records (title, summary, insights, etc.)
- **Semantic embedding** — Title, authors, summary, notable quotes, and tags are combined into a single embedding per work for meaning-based recall
- **Full-text search** — Weighted tsvector index for keyword queries
- **Normalized authors** — Deduplicated author records linked via junction table
- **Tagging system** — Flexible subject/topic tags
- **Work relationships** — Track citations, sequels, responses between works

## Design Philosophy

### Constraints as Workflow Enforcement

All core fields use `NOT NULL` constraints. This means an ingestion agent **cannot** store a work without generating:

- A **summary** (>50 chars) — primary body of the semantic embedding
- **Insights** (>20 chars) — key takeaways and relevance notes
- **Publication date**, **work type**, **language**, and **shared_by** provenance

If any required field is missing, the INSERT fails with a clear error indicating what's needed. This enforces a complete ingestion workflow at the database level, not just policy.

### Embedding Content

Each library work produces a single embedding in `memory_embeddings`. The embedded text includes:

- **Title** — with edition when present
- **Authors** — in original order, or "Unknown" if none recorded
- **Work type and publication date**
- **Summary** — the primary semantic content (200-400 words)
- **Notable quotes** — if present, appended as `Notable quotes: ...` (improves recall for quoted passages)
- **Tags** — if any tags are linked via `library_work_tags`, appended as `Topics: tag1, tag2, ...` (alphabetically ordered)

This approach gives one high-density embedding per work rather than chunking full text. On a recall hit, the full record (abstract, content, insights) is fetched from the database. Tags and notable quotes are included so semantic search can match on topic keywords and key phrases.

## Tables

### library_works (main table)

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | SERIAL | auto | Primary key |
| title | TEXT | ✅ | Work title |
| work_type | TEXT | ✅ | paper, book, novel, poem, short_story, essay, article, blog_post, whitepaper, report, thesis, dissertation, magazine, newsletter, speech, other |
| publication_date | DATE | ✅ | Date of publication |
| language | TEXT | ✅ | ISO language code (default: 'en') |
| summary | TEXT | ✅ | Concise semantic summary (200-400 words). Generated during ingestion. Primary body of the semantic embedding. |
| url | TEXT | | Link to the work |
| doi | TEXT | | Digital Object Identifier |
| arxiv_id | TEXT | | arXiv identifier |
| isbn | TEXT | | ISBN for books |
| external_ids | JSONB | | Other identifiers (PMID, etc.) |
| abstract | TEXT | | Original abstract verbatim |
| content_text | TEXT | | Full text (optional, for deep reading) |
| insights | TEXT | ✅ | Key takeaways, relevance notes |
| subjects | TEXT[] | ✅ | Topic array, e.g. `{'AI Safety', 'Agent Architecture'}` |
| notable_quotes | TEXT[] | | 3-10 memorable or frequently cited passages from the work. Included in semantic embedding. |
| publisher | TEXT | | Publisher name |
| source_path | TEXT | | Path to local file (if any) |
| shared_by | TEXT | ✅ | Who shared/recommended the work |
| extra_metadata | JSONB | | Type-specific fields (conference, meter, etc.) |
| edition | TEXT | | Edition identifier (e.g., "5th Edition", "2nd Edition"); nullable |
| embed | BOOLEAN | ✅ (default true) | Whether to include this work in semantic embedding; set false to exclude |
| search_vector | tsvector | auto | Auto-generated full-text search vector |
| added_at | TIMESTAMPTZ | auto | When the record was created |
| updated_at | TIMESTAMPTZ | auto | Last modification time |

**Check constraints:**
- `work_type` must be one of the allowed values
- `summary` must be >50 characters
- `insights` must be >20 characters

### library_authors

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | SERIAL | auto | Primary key |
| name | TEXT | ✅ | Author's full name (UNIQUE) |
| biography | TEXT | | Optional bio |

### library_work_authors (junction)

| Column | Type | Description |
|--------|------|-------------|
| work_id | INTEGER | FK → library_works |
| author_id | INTEGER | FK → library_authors |
| author_order | INTEGER | Preserves original author ordering |

### library_tags

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| id | SERIAL | auto | Primary key |
| name | TEXT | ✅ | Tag name (UNIQUE) |

### library_work_tags (junction)

| Column | Type | Description |
|--------|------|-------------|
| work_id | INTEGER | FK → library_works |
| tag_id | INTEGER | FK → library_tags |

### library_work_relationships

| Column | Type | Description |
|--------|------|-------------|
| from_work_id | INTEGER | FK → library_works |
| to_work_id | INTEGER | FK → library_works |
| relation_type | TEXT | 'cites', 'references', 'sequel_to', 'response_to', 'related' |

## Indexes

- `GIN(search_vector)` — Full-text search
- `GIN(subjects)` — Array containment queries
- `btree(work_type)` — Filter by type
- Partial indexes on `arxiv_id`, `isbn`, `doi` (WHERE NOT NULL)
- **Unique index** on `(LOWER(TRIM(title)), COALESCE(edition, ''))` — prevents duplicate records with the same title and edition
- **Partial index** on `embed WHERE embed = true` — optimizes embedding pipeline queries (only considers embeddable works)

## Search Vector Weights

The tsvector is built with weighted fields:

| Weight | Field | Priority |
|--------|-------|----------|
| A | title | Highest |
| B | summary, abstract | High |
| C | insights | Medium |
| D | content_text | Low |

## Embedding Integration

### Source Type

The library uses source_type `library` in `memory_embeddings` and `memory_type_priorities`.

### Embedding Query

Only works where `embed = true` are included in the semantic embedding pipeline. This allows selectively excluding works (e.g., drafts or exact duplicates of another edition).

```sql
-- Fetch works to embed (respects the embed flag)
SELECT w.id,
    w.title ||
    COALESCE(' (' || w.edition || ')', '') ||
    ' by ' ||
    COALESCE((
        SELECT string_agg(a.name, ', ' ORDER BY wa.author_order)
        FROM library_authors a
        JOIN library_work_authors wa ON a.id = wa.author_id
        WHERE wa.work_id = w.id
    ), 'Unknown') ||
    ' (' || w.work_type || ', ' || w.publication_date || '). ' ||
    w.summary ||
    COALESCE(' Notable quotes: ' || array_to_string(w.notable_quotes, ' | '), '') ||
    COALESCE(' Topics: ' || (
        SELECT string_agg(t.name, ', ' ORDER BY t.name)
        FROM library_tags t
        JOIN library_work_tags wt ON t.id = wt.tag_id
        WHERE wt.work_id = w.id
    ), '')
FROM library_works w
WHERE w.embed = true
```

### Edition Handling

Use the `edition` field to distinguish multiple editions of the same work. The unique index on `(LOWER(TRIM(title)), COALESCE(edition, ''))` prevents accidental duplicates:

```sql
-- Correct: two distinct editions coexist
INSERT INTO library_works (title, edition, ...) VALUES ('Thinking, Fast and Slow', NULL, ...);
INSERT INTO library_works (title, edition, ...) VALUES ('Thinking, Fast and Slow', '10th Anniversary Edition', ...);

-- Error: duplicate (same title, same edition)
INSERT INTO library_works (title, edition, ...) VALUES ('Thinking, Fast and Slow', NULL, ...);
-- → violates unique constraint idx_library_works_title_edition

-- Exclude an older edition from embedding in favor of a newer one
UPDATE library_works SET embed = false WHERE title = 'Thinking, Fast and Slow' AND edition IS NULL;
```

### Priority

Default priority: `1.00` in `memory_type_priorities`. Adjust as needed:

```sql
UPDATE memory_type_priorities SET priority = 1.00 WHERE source_type = 'library';
```

## Ingestion Workflow

1. **Collect metadata** — title, authors, URL, identifiers, abstract
2. **Generate summary** — 200-400 words, semantically dense, covering key concepts
3. **Generate insights** — Takeaways, relevance, connections to existing knowledge
4. **Create author records** — `INSERT INTO library_authors ... ON CONFLICT DO NOTHING`
5. **Insert work** — `INSERT INTO library_works` (constraints enforce completeness)
6. **Link authors** — `INSERT INTO library_work_authors` with correct ordering
7. **Add tags** — Create tags, link via `library_work_tags`
8. **Verify** — SELECT back to confirm

## Example Queries

```sql
-- Full-text search
SELECT id, title, ts_rank(search_vector, q) AS rank
FROM library_works, plainto_tsquery('english', 'agent safety red team') q
WHERE search_vector @@ q
ORDER BY rank DESC;

-- Find by subject
SELECT id, title, work_type FROM library_works
WHERE subjects @> ARRAY['AI Safety'];

-- Find by author
SELECT w.title, w.work_type, w.publication_date
FROM library_works w
JOIN library_work_authors wa ON w.id = wa.work_id
JOIN library_authors a ON wa.author_id = a.id
WHERE a.name ILIKE '%shapira%';

-- Related works
SELECT w2.title, r.relation_type
FROM library_work_relationships r
JOIN library_works w2 ON r.to_work_id = w2.id
WHERE r.from_work_id = 1;
```

## Migration

See `patches/add-library-schema.sql` for the complete migration script.
