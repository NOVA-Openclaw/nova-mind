-- ============================================
-- Library Domain Schema Migration
-- Adds structured storage for written works
-- (papers, books, poems, articles, etc.)
-- ============================================

-- Supporting Table: Authors
CREATE TABLE IF NOT EXISTS library_authors (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    biography TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE library_authors IS 'Library domain: normalized author records.';

-- Supporting Table: Tags/Subjects
CREATE TABLE IF NOT EXISTS library_tags (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE library_tags IS 'Library domain: subject/genre/topic tags for works.';

-- Main Table: Library Works
CREATE TABLE IF NOT EXISTS library_works (
    id SERIAL PRIMARY KEY,

    -- Core Metadata (ALL REQUIRED - forces complete ingestion)
    title TEXT NOT NULL,
    work_type TEXT NOT NULL,
    publication_date DATE NOT NULL,
    language TEXT NOT NULL DEFAULT 'en',

    -- Summary for embedding (REQUIRED - must be generated during ingestion)
    summary TEXT NOT NULL,

    -- Identifiers
    url TEXT,
    doi TEXT,
    arxiv_id TEXT,
    isbn TEXT,
    external_ids JSONB DEFAULT '{}',

    -- Extended Content
    abstract TEXT,
    content_text TEXT,
    insights TEXT NOT NULL,

    -- Classification
    subjects TEXT[] NOT NULL DEFAULT '{}',

    -- Provenance
    publisher TEXT,
    source_path TEXT,
    shared_by TEXT NOT NULL,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Search
    search_vector tsvector,

    -- Notable quotes for semantic recall
    notable_quotes TEXT[],

    -- Catch-all for type-specific metadata
    extra_metadata JSONB DEFAULT '{}',

    -- Constraints
    CONSTRAINT valid_work_type CHECK (work_type IN (
        'paper', 'book', 'novel', 'poem', 'short_story', 'essay',
        'article', 'blog_post', 'whitepaper', 'report', 'thesis',
        'dissertation', 'magazine', 'newsletter', 'speech', 'other'
    )),
    CONSTRAINT summary_not_empty CHECK (length(trim(summary)) > 50),
    CONSTRAINT insights_not_empty CHECK (length(trim(insights)) > 20)
);

COMMENT ON TABLE library_works IS 'Library domain: all written works (papers, books, poems, etc). '
    'ALL core fields are NOT NULL — ingestion agent must generate summary and insights. '
    'The summary field is used for semantic embedding (200-400 words, high-density). '
    'On semantic recall hit, query this table for full details.';

COMMENT ON COLUMN library_works.summary IS 'REQUIRED. Concise semantic summary for embedding. 200-400 words. '
    'Must capture: what the work is, who wrote it, key findings/themes, and why it matters.';

COMMENT ON COLUMN library_works.insights IS 'REQUIRED. Key takeaways, relevance to existing knowledge, notable connections.';

COMMENT ON COLUMN library_works.abstract IS 'Original abstract verbatim from source. May be NULL if source has none (e.g. poems).';

COMMENT ON COLUMN library_works.content_text IS 'Full text of the work. Optional — only store if available and not too large.';

-- Junction Table: Authorship
CREATE TABLE IF NOT EXISTS library_work_authors (
    work_id INTEGER NOT NULL REFERENCES library_works(id) ON DELETE CASCADE,
    author_id INTEGER NOT NULL REFERENCES library_authors(id) ON DELETE CASCADE,
    author_order INTEGER DEFAULT 0,
    PRIMARY KEY (work_id, author_id)
);

COMMENT ON TABLE library_work_authors IS 'Links works to their authors. author_order preserves original ordering.';

-- Junction Table: Tagging
CREATE TABLE IF NOT EXISTS library_work_tags (
    work_id INTEGER NOT NULL REFERENCES library_works(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES library_tags(id) ON DELETE CASCADE,
    PRIMARY KEY (work_id, tag_id)
);

COMMENT ON TABLE library_work_tags IS 'Links works to subject/topic tags.';

-- Self-Relationship Table
CREATE TABLE IF NOT EXISTS library_work_relationships (
    from_work_id INTEGER NOT NULL REFERENCES library_works(id) ON DELETE CASCADE,
    to_work_id INTEGER NOT NULL REFERENCES library_works(id) ON DELETE CASCADE,
    relation_type TEXT NOT NULL,
    PRIMARY KEY (from_work_id, to_work_id, relation_type)
);

COMMENT ON TABLE library_work_relationships IS 'Tracks relationships between works (citations, sequels, responses, etc).';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_library_works_search ON library_works USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_library_works_type ON library_works(work_type);
CREATE INDEX IF NOT EXISTS idx_library_works_subjects ON library_works USING GIN(subjects);
CREATE INDEX IF NOT EXISTS idx_library_works_arxiv ON library_works(arxiv_id) WHERE arxiv_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_library_works_isbn ON library_works(isbn) WHERE isbn IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_library_works_doi ON library_works(doi) WHERE doi IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_library_authors_name ON library_authors(name);

-- Search vector trigger
CREATE OR REPLACE FUNCTION library_works_search_trigger() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.abstract, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.insights, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(array_to_string(NEW.notable_quotes, ' '), '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.content_text, '')), 'D');
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_library_works_search ON library_works;
CREATE TRIGGER trg_library_works_search BEFORE INSERT OR UPDATE
ON library_works FOR EACH ROW EXECUTE FUNCTION library_works_search_trigger();

-- Register in memory type priorities for semantic recall
INSERT INTO memory_type_priorities (source_type, priority, description)
VALUES ('library', 1.00, 'Library works - papers, books, poems, articles. Query library_works for full details on hit.')
ON CONFLICT (source_type) DO UPDATE SET priority = 1.00, description = EXCLUDED.description;
