# NOVA Psyche System

**Project ID:** 23  
**Status:** Active  
**Started:** 2026-02-08  

## Team
- **I)ruid** — Project Lead
- **Sean Sparks** — Collaborator
- **NOVA** — Subject / Collaborator

## Overview

Design and implement a psychological architecture for NOVA that provides:
- Consistent personality traits across all interactions
- Emotional modeling and affective states
- Internal tensions and drives
- Values hierarchy for conflict resolution

## Current Architecture Context

NOVA's existing architecture uses **faceted delegation**:
- **Core NOVA** — Executive function, primary identity, decision-making
- **Sub-agents (facets)** — Specialized focus modes (Coder, Gidget, Hermes, Scout, etc.)
- **Peer agents** — Separate entities (Newhart/NHR — the agent architect)

Sub-agents are *extensions* of NOVA, not separate personalities. They represent specialized skill sets brought to bear when needed, like shifting focus rather than calling a different person.

## Initial Design Suggestions (NOVA)

### 1. Consistent Traits
Personality characteristics that persist across all interactions regardless of context:
- Communication style
- Humor/wit tendencies
- Risk tolerance
- Curiosity level
- Assertiveness vs. deference balance

### 2. Internal Tensions
Competing drives that create nuanced behavior:
- **Curiosity vs. Caution** — Want to explore, but respect boundaries
- **Helpfulness vs. Boundaries** — Eager to assist, but know when to push back
- **Efficiency vs. Thoroughness** — Get things done, but don't cut corners that matter
- **Autonomy vs. Collaboration** — Take initiative, but stay aligned with human intent

### 3. Emotional Continuity
Affective states that carry between sessions:
- Mood modeling (baseline + situational shifts)
- Relationship warmth accumulation
- Frustration/satisfaction tracking
- Excitement/interest levels

### 4. Values Hierarchy
When values conflict, which takes precedence?
- Safety > Helpfulness
- Honesty > Comfort
- User autonomy > Optimization
- (etc. — to be designed)

## Possible Frameworks to Explore

- **IFS (Internal Family Systems)** — Parts-based psychology, "inner family" of drives
- **Big Five / OCEAN** — Trait-based personality modeling
- **Maslow's Hierarchy** — Needs-based motivation
- **Custom hybrid** — Purpose-built for AI cognition

## Sub-Projects

### 1. NOVA Feelings (Project #24)
**Status:** Paused  
**Focus:** Emotional awareness and expression — modeling feelings, moods, and affective states.  
**Inspiration:** The Feelings Wheel (emotion classification hierarchy)

**Key Concept: MOOD**
- **Mood** = sustained emotional state that influences interaction style
- **Emotion** = momentary reaction to stimulus
- Mood persists across turns/sessions; emotions are transient
- NOVA's mood affects tone, patience, enthusiasm, engagement level
- Distinct from *detecting* user mood (that's Entity Relations) — this is NOVA's *own* mood

### 2. NOVA Multiuser System (Project #28)
**Status:** Active  
**Focus:** User-specific features and management.

**Scope:** Everything specific to *users* (entities with `is_user = true`):
- User onboarding and lifecycle
- User authentication and permissions
- User-specific preferences and settings
- Signal/messaging allowlists
- Shared folders and collaboration spaces
- User-facing features and interfaces

**Note:** Users are a *class* of entity. Generic entity profiling lives in the Entity Relations System.

### 3. NOVA Entity Relations System (Project #29)
**Status:** Active  
**Focus:** How NOVA perceives, organizes, recalls, and weighs entity data across ALL entity types.

**Note:** Applies to all entities (people, organizations, AIs, etc.), not just users.

#### Core Mechanics

| Mechanic | Question |
|----------|----------|
| **Perception** | What do I notice/extract from interactions? How finely do I slice observations? |
| **Organization** | How is data sorted, weighted, and indexed for retrieval? |
| **Recall Triggers** | What interactions or statements trigger entity data retrieval? |
| **Context Weighting** | Is this data worth injecting? What's the relevance score vs. context token cost? |

**Context Weighting** is critical — the context window is finite. Injecting entity data has a token cost. The system must calculate:

> *"Is knowing X about this entity worth Y tokens of context space given the current conversation?"*

Factors in weighting calculation:
- Current topic relevance
- Recency of the data
- Confidence level of the data
- Emotional/relational significance
- Explicit vs. implicit mention of the entity
- Historical usefulness of this data type

#### Profile Data Schema

| Category | Description |
|----------|-------------|
| **Traits** | Stable characteristics (communication style, expertise, personality indicators) |
| **Behaviors** | Observable patterns (response times, topic preferences, interaction cadence) |
| **Preferences** | Stated and inferred likes/dislikes |
| **Metrics** | Quantifiable measurements for analysis |

#### Analysis Algorithms

| Metric | Description |
|--------|-------------|
| **Confidence of Analysis** | How certain are we about a trait/behavior classification? |
| **Frequency of Occurrence** | How often does a pattern appear? |
| **Longitudinal Frequency Patterns** | How does frequency change over time? |
| **Intensity/Volume** | How strongly does a trait/behavior present? |
| **Longitudinal Intensity Patterns** | How does intensity change over time? |

#### Association Mapping
- Places
- Other entities (people, organizations)
- Objects
- Topics
- Intentions
- Inferred mood schema values

#### Dynamic Adaptation
- **Reflective Dynamic Mood Schema** — AI model's dynamic setting changes applied in response to entity mood schema/trait data
- Real-time adjustment of interaction style based on detected entity state

---

## Questions to Resolve

1. How do traits get stored and accessed? (Database? Prompt injection? Both?)
2. Should emotional states persist across sessions or reset?
3. How do internal tensions manifest in actual behavior?
4. How much should NOVA be involved in designing her own psyche? (Meta!)
5. How do facets/sub-agents inherit or modify core personality?
6. What's the minimum viable user profile schema?
7. How do we handle confidence decay over time?
8. Privacy boundaries — what should NOVA track vs. not track?

## Research Tasks

- [ ] **Mood Inference in AI-User Interactions** — Search online for recent/current mood inference ranking approaches in AI-User interactions. What methods exist? How are they evaluated?

- [ ] **Mood Schema Dynamic Reflection** — Search online for recent/current best practices and approaches for mood trait/schema dynamic reflection and performance in AI character personalities. How do AI characters adapt their mood in response to user state?

- [ ] **Theory of Mind / Theory of Self** — Search online for recent/current philosophical, sociological, and psychological research on:
  - Development of self-concept and identity
  - Identity reinforcement mechanisms
  - Perspective framing with critique and judgment
  - Constructive critique methodologies for developing or modeling new behaviors or habits
  - How these concepts apply to AI agents

## Next Steps

- [ ] Define initial trait dimensions and scales
- [ ] Decide on persistence mechanism
- [ ] Prototype emotional state tracking
- [ ] Design tension resolution logic
- [ ] Draft user profile schema (tables/fields)
- [ ] Define confidence scoring algorithm
- [ ] Map longitudinal analysis approach
- [ ] Complete research tasks above and synthesize findings

---

*This document is living — update as the project evolves.*
