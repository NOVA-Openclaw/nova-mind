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
  4.   Assemble the dynamic block (entity + domain + recall) and the reminders/guard
       block (turn reminders + honorific guard), then place the dynamic block
       according to `placement` (see [Configuration → placement](#placement) below)
```

## Subsystems

| Subsystem | File | Description |
|-----------|------|-------------|
| **Classifier** | `classifier.ts` | Classifies messages into `info_request`, `action`, `conversation`, `continuation`, `command`. Rule-based first pass (~60-70%), Ollama LLM fallback for ambiguous cases. |
| **Domain Identifier** | `domain-identifier.ts` | Matches messages to subject-matter domains via keyword matching + embedding similarity against `agent_domains` table. Returns top 1-3 domains with assigned agents (via JOIN, not hardcoded). Tolerates a missing `agent_domains.keywords` column on drifted schemas — see [Schema-Drift Tolerance](#schema-drift-tolerance-domain-identifier) below. |
| **Entity Resolver** | `entity-resolver.ts` | Resolves sender identity via the entity-resolver library. Cache keyed by `sessionKey:senderId` (not just sessionKey) to support group channels. Returns both formatted text and numeric `entityId`. Formatted text (`formatEntityContext()`) includes pronouns and an optional trust suffix in the `👤 **Talking with:**` header, plus an optional `📊 Known contact:` relationship-stats line — see [Entity Context Formatting](#entity-context-formatting) below (#543). Also exports `resolveEntityForGuard()`, a lightweight resolution (id + display name only, no facts lookup) used by the honorific guard when `entity_resolver` is gated off. |
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

## Entity Context Formatting

`formatEntityContext()` (in `entity-resolver.ts`) is the pure function that renders the resolved
entity and its `getEntityProfile()` result into the injected `👤 **Talking with:**` block. As of
nova-mind#543 it renders up to three lines:

1. **Header (always present):** `👤 **Talking with:** {displayName}`, where `displayName` is
   `entity.fullName || entity.name`.
   - If `entity.pronouns` is set, it's appended in parentheses: `(she/her)`.
   - If `entity.trustLevel` is set **and is not `'unknown'`**, a trust suffix is appended:
     ` — trust: {trustLevel}`. `'unknown'` is the `entities.trust_level` column default and is
     suppressed as noise — every never-assessed entity would otherwise show `trust: unknown`.
     `trustLevel` is free-text (see `database/schema.sql`'s column comment) — any non-empty,
     non-`'unknown'` string renders as-is; there is no enforced value set.
2. **Relationship stats line (optional):** `📊 Known contact: {factCount} fact(s) · first seen
   {createdAt} · last message {timestamp} ({ref})`. Rendered only when there is something
   meaningful to show — i.e. `factCount > 0`, or `entity.createdAt`, or a resolved last message,
   or `entity.lastSeen` is present. A lone `factCount: 0` with no other metadata (a genuinely new,
   never-before-seen contact) suppresses the whole line rather than showing `0 facts` on its own.
   - The `last message` segment comes from `profile.stats.lastMessage` (most recent
     `channel_transcripts` row, via `getEntityProfile()`). If absent, falls back to
     `entity.lastSeen` labeled `last seen {lastSeen}` instead — never both.
   - Segments are joined with ` · ` and any missing segment (no last message/last seen, no
     createdAt) is cleanly omitted rather than leaving a stray separator.
3. **Fact bullet list (unchanged from pre-#543 behavior):** one `• **Label:** value` line per
   entry in `profile.facts` (the existing 7-key allowlist), rendered below the stats line.

### Data source and timeout interaction (#543)

`pronouns`, `trustLevel`, `lastSeen`, and `createdAt` are fetched as part of the **same,
already-cheap identifier-resolution query** used to find the entity in the first place
(`resolveEntityByIdentifiers()` in the entity-resolver library) — not as part of the heavier
`getEntityProfile()` stats/facts query. This means they are already on the `Entity` object before
`resolveEntityContext()` even starts the `getEntityProfile()` 1s `Promise.race`, so **pronouns and
trust survive a stats-query timeout**: on timeout, `profile` degrades to
`{ facts: {}, stats: { factCount: 0, lastMessage: null } }`, but the header line above it still
renders normally with pronouns/trust/lastSeen intact. Only the `📊 Known contact:` stats line and
the fact bullet list are affected by a stats-query timeout.

The honorific guard (`resolveEntityForGuard()`) never triggers the `getEntityProfile()` stats
query at all — it only needs entity id + display name.

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

## Schema-Drift Tolerance (Domain Identifier)

`domain-identifier.ts`'s `loadDomains()` tolerates ecosystem instances whose `agent_domains` table
predates the `keywords TEXT[]` column (schema drift — e.g. `victoria_memory`), instead of throwing
`column ad.keywords does not exist` on every turn.

### Probe semantics

On the first call in a process's lifetime, `loadDomains()` runs a one-time
`information_schema.columns` probe for `agent_domains.keywords`:

- **Column present:** executes the original, byte-identical keywords-included query. No behavior
  change from pre-tolerance code — same SQL text, same columns, same join, same ordering.
- **Column absent:** executes a fallback query that omits `ad.keywords` from the SELECT list.
  Every returned domain row gets `keywords: []` (never `null`/`undefined`), which downstream
  keyword matching (`matchKeywords()`) already treats as a no-op — keyword matching is effectively
  disabled for that process, while embedding-similarity matching is unaffected.
- **Probe failure** (transient error, permissions issue, etc.): treated as "assume column
  present" — the plugin proceeds with the normal keywords-included query, exactly as it did
  before this change. A failed probe is **not** cached, so the next cold call retries it.

### Cache lifetimes — two separate caches

This feature introduces a cache that is **independent of, and longer-lived than**, the existing
5-minute domain-row cache (`DOMAIN_CACHE_TTL_MS`):

| Cache | Scope | Lifetime | Reset condition |
|---|---|---|---|
| Domain row cache (`domainCache`) | Cached `DomainRow[]` results | 5 minutes | Expires and re-queries on every `loadDomains()` call after TTL |
| Column-presence cache (`keywordsColumnPresent`) | Whether `agent_domains.keywords` exists | Unbounded — full process lifetime | Never re-probed once a **successful** probe result is cached; only re-attempted if the previous probe failed |

Only a *successful* probe result (column present or absent) is ever cached — a probe failure
leaves the column-presence cache empty so the next call retries. This means the column-presence
determination outlives multiple domain-cache refresh cycles: once a process determines the column
is absent, it will not re-probe `information_schema.columns` again for the rest of that process's
lifetime, even after the 5-minute domain cache has expired and re-queried many times over. A
mid-process schema migration (column added while the process is still running) is not picked up
until the next process restart — this is intentional, accepted behavior, not a bug.

### Warning-once behavior

When the column is absent, exactly **one** warning is logged per process lifetime (not per turn,
not per domain-cache refresh):

```
[turn-context] agent_domains.keywords missing — keyword matching disabled; apply nova-mind schema migration
```

The warning-emitted flag is a separate, independently-set module-level flag from both caches above
— it is set synchronously immediately before the warning is logged, so it holds even under
concurrent/overlapping `loadDomains()` calls on a cold cache.

### No-change guarantee on canonical schemas

On any instance where `agent_domains.keywords` already exists (the canonical/current schema —
`nova_memory` and other up-to-date ecosystem databases), this feature is a no-op: the exact same
query runs, the exact same data is returned, and no warning is ever logged. The tolerance path
only activates when the probe detects the column is genuinely absent.

### Remediation

If you see the warning above, apply the nova-mind schema migration that adds
`agent_domains.keywords TEXT[]` to bring the instance back to the canonical schema. Restart the
process afterward to pick up the change (see [Cache lifetimes](#cache-lifetimes--two-separate-caches)
above).

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
- `placement`: where the dynamic entity/domain/recall block is injected relative to the
  prompt-cache boundary — see [placement](#placement) below (#439)

### `placement`

`openclaw.plugin.json`'s `configSchema` exposes a single `placement` option controlling where
the **dynamic** block (entity identity + domain routing + semantic recall — the segments built
in Step 4 above) is injected relative to the base system prompt. This does **not** affect turn
reminders or the honorific guard, which always land in `appendSystemContext` regardless of
`placement`.

| Value | Return key used for the dynamic block | Behavior |
|---|---|---|
| `system-prepend` (default) | `prependSystemContext` | Dynamic block is placed before the base system prompt, exactly as before this option existed — **no behavior change** for instances that do not set `placement`. |
| `turn-prepend` | `prependContext` | Dynamic block is placed adjacent to the current user turn instead of before the base system prompt. Because the base system prompt (which is comparatively static across turns) is no longer preceded by a per-turn-varying dynamic block, this preserves prompt-cache hits on the system-prompt prefix — the cache boundary no longer moves every turn just because entity/domain/recall content changed. |

Unknown or malformed `placement` values (missing config, wrong type, unrecognized string) fall
back to `system-prepend` rather than throwing — a misconfigured plugin never breaks prompt
assembly. See `resolvePlacement()` and `buildPromptResult()` in `src/index.ts`.

Set it in the plugin's OpenClaw config block, e.g.:

```json
{
  "plugins": {
    "turn-context": {
      "config": {
        "placement": "turn-prepend"
      }
    }
  }
}
```

To measure the actual prompt-cache impact of switching `placement` (cache-read/write deltas
before vs. after), see `scripts/measure-turn-cache-impact.py` (repo root `scripts/`) documented
in the root `README.md` and `CHANGELOG.md`. Installer wiring for that script is tracked
separately in nova-mind#445 (not yet installed automatically — run it directly from the repo).

## Issues

- #150 — Selective semantic recall + prompt preprocessing for domain routing
- #140 — Tiered recall strategy
- #168 — Visibility filter in semantic-recall hook
- #182 — Original plugin consolidation (semantic-recall + agent-turn-context hooks)
- #421 — Deterministic honorific guard (Step 2.6)
- #425 — Follow-up: post-merge multi-gateway `agentId` casing/deployment-consistency smoke check for the guard
- #384 — Domain identifier tolerates missing `agent_domains.keywords` column (schema drift)
- #439 — Configurable placement for the dynamic context block (prepend vs. turn-adjacent) to preserve prompt-cache hits, plus `scripts/measure-turn-cache-impact.py` for measuring the effect
- #445 — Follow-up (open, out of scope for #439): installer wiring for `scripts/measure-turn-cache-impact.py`
