## Schema Design: Provenance Grading (Newhart's consult reply)

Branch: `feat/504-provenance-grading-schema`
Migration: `database/migrations/504-provenance-grading.sql` (rollback included)

### Architecture: where things live

| What | Where | Why |
|------|-------|-----|
| `assertion_intent` | Column on `entity_facts` | Per-claim property; gates all downstream grading |
| `mutability_class` | Column on `entity_facts` | Per-claim; drives query-time resolution strategy |
| `reporting_distance` (D axis) | Column on `entity_fact_sources` | Per-*source*, not per-fact — Alice's self-report and Bob's secondhand mention are different sources with different distances |
| `verification_quality` (V axis) | Column on `entity_fact_sources` | Same reasoning — verification quality is a property of how a specific source obtained/reported the claim |
| Source credibility (S axis) | `entity_credibility` table | Computed per (entity, domain), looked up at query time |
| Composite S×D×V | **Not materialized** | Computed at query time via `v_fact_grades` view — three multiplications per row, avoids invalidation cascades |
| Corroboration independence | `source_session_id` on `entity_fact_sources` | Deduplicates sources from the same conversation |

### Design decisions on the four open points

**1. NULL vs 0 on `verification_quality`:**
- NULL = "not yet assessed" → query-time computation treats as neutral 0.5 (source participates but doesn't boost or drag)
- 0.0 = "assessed and FAILED verification" → actively drags down the composite
- Stated in CHECK, COMMENT, and the `v_fact_grades` view logic (`COALESCE(verification_quality, 0.5)`)

**2. Mutability class drift across rows:**
- Resolution rule: strictest class wins for the `(entity_id, key)` group. `immutable > slow_changing > stateful`
- Implemented as `get_strictest_mutability(entity_id, key)` helper function
- Extraction pipeline carries key-pattern hints in code (versioned in nova-mind), not a DB registry — no migration needed when patterns evolve

**3. v1 contradiction detector:**
- Corroboration = independent sources. Independence keyed on `source_session_id` — two facts extracted from the same conversation are one witness
- Contradiction in v1: differing values on the same `(entity_id, key)` where `get_strictest_mutability()` returns `immutable`. Simple, deterministic, no false positives on preferences
- Verdict outcomes from #468 wire in as v2 signal (the `computation_version` column on `entity_credibility` supports phased upgrades)

**4. Recompute cron: script owns the writes.**
- Daily maintenance script writes `entity_credibility` directly — deterministic SQL, not an agent-turn prompt
- Agent involvement limited to reading results and flagging anomalies
- `evidence_snapshot` JSONB provides full audit trail of what fed each computation
- `computation_version` column allows v1 → v2 algorithm upgrades without losing history

### New objects created

- 2 enum types: `assertion_intent_enum`, `mutability_class_enum`
- 2 columns on `entity_facts`: `assertion_intent`, `mutability_class`
- 3 columns on `entity_fact_sources`: `reporting_distance`, `verification_quality`, `source_session_id`
- 1 table: `entity_credibility`
- 2 views: `v_fact_grades` (query-time S×D×V), `v_current_stateful_facts` (latest stateful value per entity+key)
- 1 function: `get_strictest_mutability()`
- 5 indexes (including partial indexes on the gradable subset and low-credibility entities)
- Backfill: 4,217 existing `entity_fact_sources` rows populated with `source_session_id`

### Backfill defaults (existing ~4,724 facts)

| Column | Default | Rationale |
|--------|---------|-----------|
| `assertion_intent` | `'asserted'` | All existing facts came from conversation (the asserted default) |
| `mutability_class` | `'slow_changing'` | Safe middle ground; pipeline refines going forward |
| `reporting_distance` | `1.0` | Existing facts are overwhelmingly self-reported in conversation |
| `verification_quality` | `NULL` | Not yet assessed — neutral 0.5 at query time |

### What's NOT in this migration (intentionally)

- Write-protection trigger on `entity_credibility` (TBD: domain-protect to newhart or leave open for the recompute script's DB user)
- The recompute script itself (belongs in `scripts/`, not a migration)
- TruthFinder-style iterative computation (v2 ceiling, not v1 floor)
- Integration with verdict system (#468) — that wires in when verdicts ship
- Distance decay rate lookup table — extraction pipeline handles this in code for v1

### Relationship to existing work

- **#468 (Verdict system):** Consumer of S×D×V grades via `evidence_fact_ids`. Verdicts judge; this defines evidence weights.
- **#502 (LangExtract):** Extraction backend for library full-text pass. Extracted records will inherit `assertion_intent` from Athena's catalog-time provenance class.
- **research_citations.reliability:** The foothold. `verification_quality` on `entity_fact_sources` maps to the same 0–1 scale.
