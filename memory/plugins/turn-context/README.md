# Turn Context Plugin

OpenClaw plugin that injects per-turn context into agent prompts via the `before_prompt_build` hook.

## Architecture

```
message_received → cache sender info (keyed by sessionKey:senderId)
                        ↓
before_prompt_build:
  1. Classifier (rule-based + Ollama fallback) → message_type
  2. prompt_helper_config lookup → which subsystems are enabled
  3. Run enabled subsystems in parallel (Promise.allSettled)
  4. Assemble prependSystemContext + appendSystemContext
```

## Subsystems

| Subsystem | File | Description |
|-----------|------|-------------|
| **Classifier** | `classifier.ts` | Classifies messages into `info_request`, `action`, `conversation`, `continuation`, `command`. Rule-based first pass (~60-70%), Ollama LLM fallback for ambiguous cases. |
| **Domain Identifier** | `domain-identifier.ts` | Matches messages to subject-matter domains via keyword matching + embedding similarity against `agent_domains` table. Returns top 1-3 domains with assigned agents (via JOIN, not hardcoded). |
| **Entity Resolver** | `entity-resolver.ts` | Resolves sender identity via the entity-resolver library. Cache keyed by `sessionKey:senderId` (not just sessionKey) to support group channels. Returns both formatted text and numeric `entityId`. |
| **Semantic Recall** | `semantic-recall.ts` | Spawns `proactive-recall.py` for memory retrieval. Supports tiered recall (domain-scoped first, full fallback) and visibility filtering (group channels → public facts only). |
| **Turn Reminders** | `turn-reminders.ts` | Queries `agent_turn_context` table for per-turn reminder text. **Always fires regardless of message type** — not gated by prompt_helper_config. |

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
