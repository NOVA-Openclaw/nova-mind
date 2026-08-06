-- Migration: 504-provenance-grading
-- Issue: nova-mind#504 — Source credibility & assertion-intent grading for entity_facts
-- Author: newhart
-- Date: 2026-07-20
--
-- Adds:
--   1. assertion_intent enum on entity_facts (gates grading machinery)
--   2. mutability_class enum on entity_facts (drives query-time resolution)
--   3. reporting_distance + verification_quality on entity_fact_sources (per-source D and V axes)
--   4. source_session_id on entity_fact_sources (independence dedup for corroboration)
--   5. entity_credibility table (computed S axis, per entity×domain)
--
-- Design decisions incorporated:
--   - NULL verification_quality = "not yet assessed"; 0.0 = "assessed and failed verification."
--     Aggregate computation treats NULL as neutral default (0.5) so ungraded sources participate
--     rather than vanishing. Stated in CHECK + COMMENT.
--   - Mutability class conflict across rows for the same (entity_id, key) resolved by
--     strictest-class rule: immutable > slow_changing > stateful. Extraction pipeline carries
--     key-pattern hints in code (nova-mind versioned), not a DB registry.
--   - v1 contradiction detector: differing values on the same (entity_id, key) where the
--     strictest mutability_class is 'immutable' AND the values genuinely differ. Verdict
--     outcomes (#468) are the richer signal wired in v2.
--   - Corroboration = independent sources. Independence determined by source_session_id —
--     two facts from the same conversation are one witness. entity_fact_sources gains
--     source_session_id FK to channel_sessions for dedup.
--   - Daily recompute is a deterministic SCRIPT that writes entity_credibility directly.
--     Agent involvement limited to reading results and flagging anomalies.
--     (Per CRON_DESIGN: DB writes belong in scripts, not agent prompts.)
--   - S×D×V is NEVER materialized on rows. Computed at query time (three multiplications).
--     Avoids invalidation cascades when entity credibility recomputes.
--
-- Backfill strategy:
--   - assertion_intent defaults 'asserted' (all existing facts came from conversation)
--   - mutability_class defaults 'slow_changing' (safe middle ground; pipeline refines going forward)
--   - reporting_distance defaults 1.0 (existing facts are overwhelmingly self-reported in conversation)
--   - verification_quality defaults NULL (not yet assessed — neutral 0.5 at query time)
--   - entity_credibility starts empty; first recompute run populates it
--
-- Rollback: see 504-provenance-grading-rollback.sql

BEGIN;

-- ============================================================================
-- 1. assertion_intent on entity_facts
-- ============================================================================

-- Create the enum type
CREATE TYPE assertion_intent_enum AS ENUM (
    'asserted',       -- source intends claim to be believed true
    'speculative',    -- source signals uncertainty ("I think...", "probably...")
    'fictional',      -- known-false by contract (novels, stories, RP)
    'disclaimed',     -- source explicitly flagged as false ("people say X but it's not true")
    'hypothetical'    -- suppositions, thought experiments, sarcasm/jokes
);

ALTER TABLE entity_facts
    ADD COLUMN assertion_intent assertion_intent_enum NOT NULL DEFAULT 'asserted';

COMMENT ON COLUMN entity_facts.assertion_intent IS
    'Epistemological intent of the claim. Grading machinery (S×D×V) only engages for asserted+speculative. '
    'fictional/disclaimed/hypothetical are stored with full provenance but never compete as truth claims. '
    'Determination happens at ingestion/extraction time.';

CREATE INDEX idx_entity_facts_assertion_intent
    ON entity_facts (assertion_intent);

-- Partial index for the grading-eligible subset (the hot path)
CREATE INDEX idx_entity_facts_gradable
    ON entity_facts (entity_id, key)
    WHERE assertion_intent IN ('asserted', 'speculative');


-- ============================================================================
-- 2. mutability_class on entity_facts
-- ============================================================================

CREATE TYPE mutability_class_enum AS ENUM (
    'immutable',       -- birthdate, birthplace — conflicts are genuine contradictions
    'slow_changing',   -- profession, address — conflict within short window suspicious, across years = drift
    'stateful'         -- preferences, favorites, current projects — new claim supersedes, no contradiction
);

ALTER TABLE entity_facts
    ADD COLUMN mutability_class mutability_class_enum NOT NULL DEFAULT 'slow_changing';

COMMENT ON COLUMN entity_facts.mutability_class IS
    'Controls query-time resolution and contradiction detection. '
    'immutable: conflicting values = genuine contradiction → credibility impact. '
    'slow_changing: conflict within short window suspicious, across years = natural drift. '
    'stateful: latest value is current; full trajectory preserved; no credibility damage from drift. '
    'When mixed classes exist for the same (entity_id, key), resolution uses the STRICTEST class '
    '(immutable > slow_changing > stateful).';

CREATE INDEX idx_entity_facts_mutability
    ON entity_facts (mutability_class)
    WHERE mutability_class = 'immutable';


-- ============================================================================
-- 3. reporting_distance + verification_quality on entity_fact_sources
-- ============================================================================

ALTER TABLE entity_fact_sources
    ADD COLUMN reporting_distance REAL NOT NULL DEFAULT 1.0
        CHECK (reporting_distance > 0.0 AND reporting_distance <= 1.0),
    ADD COLUMN verification_quality REAL DEFAULT NULL
        CHECK (verification_quality >= 0.0 AND verification_quality <= 1.0),
    ADD COLUMN source_session_id BIGINT
        REFERENCES channel_sessions(id);

COMMENT ON COLUMN entity_fact_sources.reporting_distance IS
    'Transmission hops from the subject (D axis). '
    'Self-report/autobiography = 1.0; direct observation ≈ 0.9; secondhand ≈ 0.8; further decays. '
    'Decay rate is tunable per source type (a cited biography does not decay like barroom gossip). '
    'Set at extraction time based on source relationship to subject.';

COMMENT ON COLUMN entity_fact_sources.verification_quality IS
    'Citation density, corroboration, peer review quality (V axis). '
    'NULL = not yet assessed (query-time computation treats as neutral 0.5). '
    '0.0 = assessed and FAILED verification. '
    'Maps to research_citations.reliability scale (0–1). '
    'This distinction matters: NULL sources participate at neutral weight; 0.0 sources actively drag down.';

COMMENT ON COLUMN entity_fact_sources.source_session_id IS
    'FK to channel_sessions — identifies the originating conversation. '
    'Used for corroboration independence: two facts from the same session are one witness, not two. '
    'Required for the v1 corroboration ratio in entity_credibility recompute.';

CREATE INDEX idx_efs_source_session
    ON entity_fact_sources (source_session_id)
    WHERE source_session_id IS NOT NULL;


-- ============================================================================
-- 4. entity_credibility table (computed S axis)
-- ============================================================================

CREATE TABLE entity_credibility (
    id              SERIAL PRIMARY KEY,
    entity_id       INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    domain          VARCHAR(100) NOT NULL DEFAULT '_global',
    score           REAL NOT NULL DEFAULT 0.5
                    CHECK (score >= 0.0 AND score <= 1.0),
    claim_count     INTEGER NOT NULL DEFAULT 0,
    corroborated_count INTEGER NOT NULL DEFAULT 0,
    contradicted_count INTEGER NOT NULL DEFAULT 0,
    last_computed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    computation_version INTEGER NOT NULL DEFAULT 1,
    evidence_snapshot JSONB NOT NULL DEFAULT '{}',
    UNIQUE (entity_id, domain)
);

COMMENT ON TABLE entity_credibility IS
    'Computed per-(entity, domain) source credibility (S axis of S×D×V). '
    'NEVER hand-assigned — derived from claim track record + verification events. '
    'v1 algorithm: corroboration ratio with recency decay (90-day half-life). '
    'Recomputed by daily maintenance script (not agent prompt). '
    'Domain taxonomy starts coarse — reuses entity_facts.category vocabulary + agent_domains topics. '
    '''_global'' is the fallback for entities with too few domain-specific claims.';

COMMENT ON COLUMN entity_credibility.computation_version IS
    'Algorithm version that produced this score. Allows phased upgrades (v1 = simple ratio, '
    'v2 = TruthFinder-style iteration) without invalidating audit trail.';

COMMENT ON COLUMN entity_credibility.evidence_snapshot IS
    'Audit trail: inputs that fed the last computation (claim ids, corroboration events, '
    'contradiction events, recency weights). Supports debugging and algorithm upgrades.';

CREATE INDEX idx_entity_credibility_entity
    ON entity_credibility (entity_id);

CREATE INDEX idx_entity_credibility_domain
    ON entity_credibility (domain);

CREATE INDEX idx_entity_credibility_score
    ON entity_credibility (score)
    WHERE score < 0.3;  -- quick identification of low-credibility entities


-- ============================================================================
-- 5. Convenience view: fact grades (S×D×V computed at query time)
-- ============================================================================

CREATE OR REPLACE VIEW v_fact_grades AS
SELECT
    ef.id AS fact_id,
    ef.entity_id,
    ef.key,
    ef.value,
    ef.assertion_intent,
    ef.mutability_class,
    efs.id AS source_id,
    efs.source_entity_id,
    efs.reporting_distance AS d_axis,
    -- NULL verification_quality → neutral 0.5
    COALESCE(efs.verification_quality, 0.5) AS v_axis,
    -- S axis: look up source entity's credibility in the fact's category domain, fall back to _global
    COALESCE(
        ec_domain.score,
        ec_global.score,
        0.5  -- no credibility record yet → neutral
    ) AS s_axis,
    -- Composite grade
    COALESCE(ec_domain.score, ec_global.score, 0.5)
        * efs.reporting_distance
        * COALESCE(efs.verification_quality, 0.5) AS composite_grade,
    efs.source_session_id
FROM entity_facts ef
JOIN entity_fact_sources efs ON efs.fact_id = ef.id
LEFT JOIN entity_credibility ec_domain
    ON ec_domain.entity_id = efs.source_entity_id
    AND ec_domain.domain = ef.category
LEFT JOIN entity_credibility ec_global
    ON ec_global.entity_id = efs.source_entity_id
    AND ec_global.domain = '_global'
WHERE ef.assertion_intent IN ('asserted', 'speculative');

COMMENT ON VIEW v_fact_grades IS
    'Query-time S×D×V grade computation. Only includes gradable claims (asserted/speculative). '
    'S looked up from entity_credibility (domain-specific with _global fallback). '
    'D from entity_fact_sources.reporting_distance. '
    'V from entity_fact_sources.verification_quality (NULL → 0.5 neutral). '
    'Never materialized — three multiplications per row is trivially fast.';


-- ============================================================================
-- 6. Convenience view: current stateful facts (latest per entity+key)
-- ============================================================================

CREATE OR REPLACE VIEW v_current_stateful_facts AS
SELECT DISTINCT ON (ef.entity_id, ef.key)
    ef.id,
    ef.entity_id,
    ef.key,
    ef.value,
    ef.last_confirmed_at,
    ef.learned_at,
    ef.confidence
FROM entity_facts ef
WHERE ef.mutability_class = 'stateful'
ORDER BY ef.entity_id, ef.key, ef.last_confirmed_at DESC NULLS LAST;

COMMENT ON VIEW v_current_stateful_facts IS
    'Resolves stateful (preference/current-state) facts to the latest value per (entity, key). '
    'Full trajectory remains in entity_facts — this view gives the current snapshot. '
    'Supersession is query-time, not deletion.';


-- ============================================================================
-- 7. Helper function: strictest mutability class for a (entity_id, key) group
-- ============================================================================

CREATE OR REPLACE FUNCTION get_strictest_mutability(p_entity_id INTEGER, p_key VARCHAR)
RETURNS mutability_class_enum
LANGUAGE SQL STABLE
AS $$
    SELECT CASE
        WHEN bool_or(mutability_class = 'immutable') THEN 'immutable'::mutability_class_enum
        WHEN bool_or(mutability_class = 'slow_changing') THEN 'slow_changing'::mutability_class_enum
        ELSE 'stateful'::mutability_class_enum
    END
    FROM entity_facts
    WHERE entity_id = p_entity_id AND key = p_key;
$$;

COMMENT ON FUNCTION get_strictest_mutability IS
    'Returns the strictest mutability class present for a (entity_id, key) group. '
    'Ordering: immutable > slow_changing > stateful. '
    'Used by contradiction detection: if ANY row for this key is immutable, conflicting values '
    'are genuine contradictions regardless of other rows'' classes.';


-- ============================================================================
-- 8. Backfill: source_session_id on existing entity_fact_sources
-- ============================================================================

-- Populate source_session_id from the parent fact's source_channel_session_id where available.
-- This gives existing sources a session anchor for independence deduplication.
UPDATE entity_fact_sources efs
SET source_session_id = ef.source_channel_session_id
FROM entity_facts ef
WHERE efs.fact_id = ef.id
  AND ef.source_channel_session_id IS NOT NULL
  AND efs.source_session_id IS NULL;


-- ============================================================================
-- 9. Grants — match existing privilege model
-- ============================================================================
-- entity_credibility: newhart owns writes (domain-protected), all agents get SELECT
-- Grants follow the pattern in the existing schema (default privileges + explicit)

-- All agents need to read credibility scores at query time
GRANT SELECT ON entity_credibility TO
    argus, athena, coder, conductor, gem, gidget, iris, marcie, quill, scout, scribe, ticker;

GRANT SELECT, USAGE ON SEQUENCE entity_credibility_id_seq TO
    argus, athena, coder, conductor, gem, gidget, iris, marcie, quill, scout, scribe, ticker;

-- Views
GRANT SELECT ON v_fact_grades TO
    argus, athena, coder, conductor, gem, gidget, iris, marcie, quill, scout, scribe, ticker;

GRANT SELECT ON v_current_stateful_facts TO
    argus, athena, coder, conductor, gem, gidget, iris, marcie, quill, scout, scribe, ticker;

-- Function
GRANT EXECUTE ON FUNCTION get_strictest_mutability TO
    argus, athena, coder, conductor, gem, gidget, iris, marcie, quill, scout, scribe, ticker;


COMMIT;
