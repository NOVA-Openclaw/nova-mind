# Turn Context Plugin

OpenClaw plugin that injects per-turn context into agent prompts via the `before_prompt_build` hook.

## Architecture

```
message_received → cache sender info (keyed by sessionKey:senderId)
                        ↓
before_prompt_build:
  1.   Classifier (rule-based + Ollama fallback) → message_type
  2.   prompt_helper_config lookup → which subsystems are enabled
  2.5. Entity resolution (gated) → resolvedEntityId, for prependSystemContext + recall input
  2.6. Honorific guard (always-on) → reuses 2.5's result if gated ON, own lightweight call if OFF
  3.   Run remaining subsystems in parallel (Promise.allSettled)
  4.   Assemble prependSystemContext + appendSystemContext
```

## Subsystems

| Subsystem | File | Description |
|-----------|------|-------------|
| **Classifier** | `classifier.ts` | Classifies messages into `info_request`, `action`, `conversation`, `continuation`, `command`. Rule-based first pass (~60-70%), Ollama LLM fallback for ambiguous cases. |
| **Domain Identifier** | `domain-identifier.ts` | Matches messages to subject-matter domains via keyword matching + embedding similarity against `agent_domains` table. Returns top 1-3 domains with assigned agents (via JOIN, not hardcoded). |
| **Entity Resolver** | `entity-resolver.ts` | Resolves sender identity via the entity-resolver library. Cache keyed by `sessionKey:senderId` (not just sessionKey) to support group channels. Returns both formatted text and numeric `entityId`. Also exports `resolveEntityForGuard()`, a lightweight resolution (id + display name only, no facts lookup) used by the honorific guard when `entity_resolver` is gated off. |
| **Semantic Recall** | `semantic-recall.ts` | Spawns `proactive-recall.py` for memory retrieval. Supports tiered recall (domain-scoped first, full fallback) and visibility filtering (group channels → public facts only). |
| **Turn Reminders** | `turn-reminders.ts` | Queries `agent_turn_context` table for per-turn reminder text. **Always fires regardless of message type** — not gated by prompt_helper_config. |
| **Honorific Guard** | `honorific-guard.ts` | Deterministic (non-LLM) instruction appended after the base system prompt, enforcing the "Sir" honorific policy based on the resolved sender entity and the responding agent. **Always fires regardless of message type or `entity_resolver` gating** — see [Honorific Guard](#honorific-guard) below. |

## Message Type → Subsystem Gating

Controlled by the `prompt_helper_config` table. Default configuration:

| Message Type | entity_resolver | semantic_recall | domain_identifier | turn_reminders |
|---|---|---|---|---|
| `info_request` | ✅ | ✅ | ✅ | ✅ (always) |
| `action` | ✅ | ✅ | ✅ | ✅ (always) |
| `conversation` | ✅ | ❌ | ❌ | ✅ (always) |
| `continuation` | ❌ | ❌ | ❌ | ✅ (always) |
| `command` | ❌ | ❌ | ❌ | ✅ (always) |

Per-agent overrides: insert rows with `agent_name` set to override defaults for a specific agent.

On classifier failure, defaults to `info_request` (full pipeline) — safe fallback.

## Honorific Guard

Deterministic, non-LLM guard that appends a short instruction to `appendSystemContext` (Step 2.6
of `before_prompt_build`, immediately after entity resolution) enforcing the "Sir" honorific
policy. Unlike every other subsystem in this plugin, **the guard is never gated by
`prompt_helper_config` or message type** — it runs on every turn, including `continuation` and
`command` messages where `entity_resolver` is gated off by default (see the gating table above).

### Behavior

The guard resolves the sender's entity ID and the responding agent's ID, then picks exactly one
of three outcomes:

| Sender entity | Responding agent | Outcome | Appended line |
|---|---|---|---|
| I)ruid (`entity_id = 2`) | `nova` (exact, case-sensitive) | **No guard** | *(nothing appended)* |
| I)ruid (`entity_id = 2`) | anything else (including missing/null/empty `agentId`) | **Exclusivity** | `The user is I)ruid. "Sir" is reserved exclusively for NOVA — address I)ruid normally using conversational pronouns.` |
| Anyone/anything else, or entity unresolved | any agent | **Prohibition** | `You are talking with {preferredName}. Do not use "Sir", "Ma'am", or other formal honorifics — address {preferredName} by name or with normal conversational pronouns.` (falls back to `Do not use "Sir", "Ma'am", or other formal honorifics — address this sender by name or with normal conversational pronouns.` when no preferred name is available) |

`preferredName` is `entity.fullName || entity.name` from the resolver (no extra `entity_facts`
lookup) and is interpolated **only** in the prohibition line — the exclusivity line always says
"I)ruid" literally, never a resolved preferred name.

### Fail-closed semantics

The guard is deliberately fail-**closed** toward over-prohibiting, never fail-open toward
exclusivity:

- **Unresolved/unknown sender** (entity resolution returns `null`, times out, hits a cache miss,
  or the session has no sender info at all — e.g. subagent sessions, a cold sender-cache
  immediately after a gateway restart) → **prohibition line**, never the exclusivity line and
  never silence. This is a known, accepted UX gap: for a short window immediately after every
  gateway restart, even I)ruid's own messages will show the prohibition line to `nova` until
  `message_received` repopulates the sender cache.
- **Missing, null, or empty-string `agentId`** → treated as **not** `"nova"` (fails closed to
  the exclusivity/prohibition side, never defaults to `"nova"` and never suppresses the guard).
  A warning is logged (`ctx.agentId missing for honorific guard — treating as non-NOVA`).
- **`agentId` matching is case-sensitive, exact-match on the literal string `"nova"`** — no
  `.trim()`/`.toLowerCase()` normalization. `"Nova"`, `"NOVA"`, `" nova "`, and any other agent
  name all fail closed to the exclusivity line for I)ruid.
- Exactly one guard string is ever emitted per turn; the entity check runs before the agent
  check, so an unresolved entity always short-circuits straight to the prohibition line without
  ever consulting `agentId`.

### Config interaction with `entity_resolver` gating

The guard needs a resolved entity ID every turn, but `entity_resolver` itself is gated off for
`continuation` and `command` message types by default (see the gating table above). To avoid
regressing the no-guard case for I)ruid+nova on those message types, Step 2.6 uses one of two
mutually exclusive paths depending on the gating state, so there is never more than one entity
resolution call (and never any timeout stacking) per turn:

- **`entity_resolver` ON:** reuses the entity ID and display name already resolved by Step 2.5 —
  zero extra calls.
- **`entity_resolver` OFF:** calls `resolveEntityForGuard()` (in `entity-resolver.ts`) directly —
  a lightweight resolution that skips the `entity_facts` lookup and text formatting that
  `resolveEntityContext()` does for `prependSystemContext`. It shares the same
  `sessionKey:senderId` cache as the main resolver, so warm-path cost is near zero.

A guard-resolution error is caught independently and does not affect turn reminders or any other
subsystem (isolated try/catch, no shared `Promise.allSettled` slot).

See `nova-mind#421` for the full design history and binding decisions (A1–A7).

## Database Dependencies

- **`prompt_helper_config`** — subsystem gating config (migration 081)
- **`agent_domains`** — domain topics with `keywords TEXT[]` column and `notes` descriptions
- **`agent_turn_context`** — per-turn reminder records
- **`memory_embeddings`** — domain description embeddings (`source_type='agent_domain'`)
- **Entity resolver library** — `~/.openclaw/lib/entity-resolver/index.ts`

## Migration Notes

Migration `081_prompt_helper_config.sql` must be run in two parts due to table ownership:
1. **As newhart** (owns `agent_domains`): `ALTER TABLE`, `UPDATE` statements for keywords/notes
2. **As nova** (owns `prompt_helper_config`): `CREATE TABLE`, `INSERT` seed data

After migration, run `memory/scripts/seed-domain-embeddings.py` to embed domain descriptions.

## Configuration

- Plugin timeout: 8000ms for `before_prompt_build` (configurable via OpenClaw plugin config)
- Domain cache TTL: 5 minutes
- Helper config cache TTL: 5 minutes
- Ollama classifier timeout: 2000ms
- Embedding model: configured via `memory/scripts/embedding-config.json`

## Issues

- #150 — Selective semantic recall + prompt preprocessing for domain routing
- #140 — Tiered recall strategy
- #168 — Visibility filter in semantic-recall hook
- #182 — Original plugin consolidation (semantic-recall + agent-turn-context hooks)
- #421 — Deterministic honorific guard (Step 2.6)
- #425 — Follow-up: post-merge multi-gateway `agentId` casing/deployment-consistency smoke check for the guard
