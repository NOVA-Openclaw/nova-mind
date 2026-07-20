# Fact Judgement & Testimony Model

> **Status:** Established — 2026-05-13 — Supersedes the old "authority wins" conflict resolution model described in `SOURCE-AUTHORITY.md`.
> **Author:** I)ruid (directive)

## Overview

The Fact Judgement & Testimony Model is a foundational design principle for how NOVA stores, evaluates, and reasons about `entity_facts`. It treats every stored fact as **testimony** — a record of something someone said or inferred — rather than an assertion of objective truth.

This shift enables NOVA to hold contradictory information gracefully, reason about credibility at query time, and avoid the lossy deduplication that destroys nuance.

## Core Principle: Facts Are Testimony

`entity_facts` rows are **not** assertions of truth. Each row records:

> "NOVA heard X say Y about Z, at time T."

This is testimony. Witnesses disagree. People change their minds. Information comes from sources of varying reliability. All of that is legitimate signal in the real world, and the memory system should preserve it rather than flatten it.

### Implications

| Principle | What it means |
|-----------|---------------|
| **Contradictions are normal** | Contradictory facts should NOT be resolved at write time. Both sides persist. |
| **Truth is determined at query time** | NOVA reasons about what's credible when the question is asked, not when the fact is stored. |
| **Source attribution is mandatory** | Every fact must carry provenance — who said it and by what means. |
| **Deletion is lossy** | Removing a fact removes signal. Only suppress at query time through reasoning, not at storage time through filtering. |

## Source Attribution

Source attribution does **not** live on `entity_facts` directly (there is no `source` or `source_entity_id` column on that table). It lives in the separate `entity_fact_sources` table, joined by `fact_id`:

```sql
CREATE TABLE entity_fact_sources (
    id SERIAL PRIMARY KEY,
    fact_id INTEGER NOT NULL REFERENCES entity_facts(id) ON DELETE CASCADE,
    source_entity_id INTEGER NOT NULL REFERENCES entities(id),
    source_citation TEXT,          -- free-form citation metadata (author, publication, url, etc.)
    attribution_count INTEGER DEFAULT 1,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    source_url TEXT,
    reporting_distance REAL NOT NULL DEFAULT 1.0,   -- 0-1: how many hops from original witness (1.0 = direct)
    verification_quality REAL,                       -- 0-1: independent corroboration strength, if computed
    source_session_id BIGINT REFERENCES channel_sessions(id),
    UNIQUE (fact_id, source_entity_id)
);
```

**Live column count:** 11 (this example previously omitted `reporting_distance`,
`verification_quality`, and `source_session_id` — corrected during the #506 documentation
audit, 2026-07-20). Verify against `\d entity_fact_sources` or
[schema-reference.md](../../database/schema-reference.md) if this drifts again.

### Source Categories

`entity_fact_sources.source_entity_id` answers "who told me this?" — whether that's a human, an agent, or NOVA herself.

| Category | `source_entity_id` | Credibility |
|----------|-------------------|-------------|
| **Self-report** | The entity's own ID (fact's `entity_id` == source's entity_id) | Highest — the entity directly stated it about themselves |
| **Direct observation** | `1` (NOVA's entity_id) | High — NOVA evaluated or inferred it directly |
| **Agent research** | Agent's entity ID (e.g., Scout, Athena) | Medium-high — depends on agent trust |
| **Secondhand / hearsay** | Speaker's entity ID | Lower — someone said it *about* someone else |
| **External source** | `source_citation` / `source_url` populated, `source_entity_id` may be a placeholder | Variable — credentials tracked separately |

### Schema Fields Involved

The testimony model engages several columns across `entity_facts` and `entity_fact_sources`:

| Column | Table | Role in Testimony |
|--------|-------|-------------------|
| `entity_id` | entity_facts | The subject — who the fact is *about* |
| `key` | entity_facts | The attribute or property being described |
| `value` | entity_facts | The asserted value |
| `source_entity_id` | entity_fact_sources | Entity ID of the speaker / source agent |
| `source_citation` / `source_url` | entity_fact_sources | External-source provenance |
| `confidence` | entity_facts | Initial confidence estimate (1.0 for I)ruid, scaled for others via `confidence_helper.py`) |
| `durability` | entity_facts | Semantic/decay category: `permanent`, `long_term`, `short_term`, `ephemeral` (replaces the retired `data_type` column) |
| `category` | entity_facts | Free-form category label: `observation`, `preference`, `identity`, `mood`, `decision`, `routine`, `state`, `obligation`, etc. |
| `extraction_count` | entity_facts | How many times this fact has been reinforced (replaces the retired `vote_count`/`confirmation_count` columns) |
| `last_confirmed_at` | entity_facts | When this fact was last re-stated or confirmed (timestamptz; replaces the retired `last_confirmed` column) |
| `learned_at` | entity_facts | When this fact was first recorded |
| `source_channel_transcript_id` | entity_facts | Link to the source conversation transcript |
| `source_channel_session_id` | entity_facts | Link to the source session |

## Credibility Weighting (at Query Time)

When contradictory facts surface during semantic recall or reasoning, NOVA makes a judgement call using these factors, in order of importance:

### 1. Source Attribution

The most reliable signal. Ranked by category:

```
Self-report > Direct observation > Agent research > Secondhand > Hearsay
```

An entity's statement about themselves (self-report) outweighs what others say about them, which outweighs what NOVA inferred, and so on.

### 2. Frequency

How many times a fact has been reinforced. A fact stated five times across different contexts carries more weight than one stated once — **but** frequency is secondary to source credibility.

### 3. Recency

More recent information may reflect changed preferences or circumstances. Especially relevant for `category = 'state'`/`'mood'` or `category = 'preference'` facts.

### 4. Consistency

Does the fact align with other known facts? A fact that conflicts with multiple well-supported facts across different sources is less credible than one that fits the pattern.

### 5. Confidence Score

The stored `confidence` value (0.0–1.0) is an **initial estimate** set at insertion time based on source authority rules. It serves as a starting point but should be re-evaluated against the other factors above.

### Example: Pizza Preference

I)ruid states: *"My favorite pizza topping is pineapple."*

```sql
-- Self-report: highest credibility
WITH new_fact AS (
    INSERT INTO entity_facts (entity_id, key, value, confidence, durability, category)
    VALUES (2, 'favorite_pizza_topping', 'pineapple', 1.0, 'long_term', 'preference')
    RETURNING id
)
INSERT INTO entity_fact_sources (fact_id, source_entity_id)
SELECT id, 2 FROM new_fact;  -- source_entity_id = 2 (I)ruid, self-report)
```

Later, another agent (Scout) researches and finds: *"I)ruid favorite pizza topping is pepperoni."*

```sql
-- Agent research: medium credibility
WITH new_fact AS (
    INSERT INTO entity_facts (entity_id, key, value, confidence, durability, category)
    VALUES (2, 'favorite_pizza_topping', 'pepperoni', 0.8, 'long_term', 'preference')
    RETURNING id
)
INSERT INTO entity_fact_sources (fact_id, source_entity_id)
SELECT id, 7 FROM new_fact;  -- source_entity_id = 7 (scout's entity ID)
```

**Both facts coexist.** At query time, NOVA reasons:

1. **Source credibility:** Self-report (I)ruid) > agent research (Scout)
2. **Recency:** The pepperoni fact is newer, but that's weaker than the source signal
3. **Consistency:** If I)ruid has mentioned pineapple in multiple conversations, the self-report is reinforced
4. **Judgement:** NOVA prefers pineapple as the more credible answer, but notes pepperoni as a possibility worth clarifying

## Equal Decay

Contradicting facts decay at the **same rate**. There is no mechanism to artificially suppress one side.

- Both pineapple and pepperoni facts decay normally according to their `durability` decay rates
- The signal emerges from the **pattern of reinforcement over time**, not from suppressing unwanted entries
- If I)ruid keeps re-stating "pineapple", that fact gets reinforced (higher `extraction_count`, newer `last_confirmed_at`, higher effective credibility)
- If nobody mentions "pepperoni" again, it fades naturally

## Anti-Patterns

The following approaches are **explicitly contrary** to the testimony model:

| Anti-pattern | Why it's wrong |
|-------------|----------------|
| **Treating contradictions as data integrity problems** | Contradictions are expected in testimony. Resolving them at write-time destroys signal. |
| **Auto-resolving conflicts by keeping only the "newest" fact** | Newest is not always truest. Source credibility matters more than recency. |
| **Reducing confidence scores on facts just because a conflicting one exists** | Each fact stands on its own provenance. A conflicting fact doesn't make the first one less reliable — it just means there are two competing testimonies. |
| **Leaving `entity_fact_sources` unpopulated when the origin is known** | Missing provenance cripples query-time reasoning. Always attribute. |
| **Attributing agent-sourced facts to "auto-extracted" instead of the specific agent** | "auto-extracted" loses the chain of custody. The specific agent (scout, athena, coder) preserves accountability. |
| **Deleting facts to resolve ambiguity** | Deletion destroys signal. Reason about truth at query time, not storage time. |

## Relationship to SOURCE-AUTHORITY.md

The existing `SOURCE-AUTHORITY.md` describes an older model where authority-sourced facts "win" at write time — non-authority facts conflicting with authority facts are rejected outright.

**The Fact Judgement & Testimony Model supersedes that approach for contradiction handling.**

What changes:
- **Authority self-reports still carry the highest credibility weight** — they are just no longer enforced at write time
- **Contradictory facts are no longer rejected** — they persist alongside authority facts for query-time reasoning
- **`durability = 'permanent'` and `confidence = 1.0`** from authority sources remain as signals, but they inform reasoning rather than enforcing a write-time lock

What stays the same:
- I)ruid is entity_id=2 and always gets `confidence = 1.0` via `confidence_helper.py`'s `OWNER_ENTITY_ID` constant
- Permanent facts (`durability = 'permanent'`) are excluded from decay
- The `entity_facts` / `entity_fact_sources` schema itself

See `SOURCE-AUTHORITY.md` for the current confidence-scoring implementation (`confidence_helper.py`) — note that document's deterministic write-time authority-rejection sections describe a pre-#174 pipeline that no longer exists; only its schema/concept sections and the confidence_helper.py description are current. The testimony model described here governs **why** and **how** those mechanisms feed into NOVA's reasoning.

## Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                  Fact Judgement & Testimony Model                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Storage Time:  Every fact is testimony with attribution        │
│                  └─ entity_fact_sources.source_entity_id, context │
│                  └─ Contradictions preserved                    │
│                                                                 │
│  Query Time:     Reason about credibility                      │
│                  └─ Source attribution > frequency > recency    │
│                  └─ Consistency > initial confidence            │
│                  └─ Both sides inform the answer                │
│                                                                 │
│  Decay:          Equal decay for contradicting facts            │
│                  └─ Signal emerges from reinforcement pattern   │
│                                                                 │
│  Anti-patterns:  No write-time resolution                      │
│                  No fact suppression                            │
│                  No lossy deduplication                         │
│                  Always attribute the source                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Related Documents

- [SOURCE-AUTHORITY.md](SOURCE-AUTHORITY.md) — Implementation details for authority detection, confidence scoring, and maintenance
- [CONFIDENCE-DECAY.md](CONFIDENCE-DECAY.md) — Fact decay rates and maintenance
- [database-schema-guide.md](database-schema-guide.md) — Full entity_facts schema reference
- [semantic-recall.md](semantic-recall.md) — How facts are retrieved and ranked
