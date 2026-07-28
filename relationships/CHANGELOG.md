# Changelog

## Unreleased

### Added
- **Pronouns + relationship stats** (nova-mind#543) — `resolveEntity()`/`resolveEntityByIdentifiers()` now also select `entities.pronouns`, `entities.trust_level`, `entities.last_seen`, and `entities.created_at` via a new shared `mapDbEntity()` helper, so the returned `Entity` optionally carries `pronouns`, `trustLevel`, `lastSeen` (pre-rendered `YYYY-MM-DD HH24:MI UTC`), and `createdAt` (pre-rendered `YYYY-MM-DD`) — omitted when the underlying column is NULL. `getEntityProfile()`'s return type changed from a bare `EntityFacts` map to `EntityProfile` (`{ facts, stats }`, new `EntityRelationshipStats` type in `types.ts`): `stats.factCount` is an unfiltered `entity_facts` row count, and `stats.lastMessage` is the most recent `channel_transcripts` row (timestamp + `provider:external_chat_id` ref), both from a single aggregate query with two `LEFT JOIN LATERAL`s designed to stay inside the existing 1s timeout budget the `turn-context` plugin races it against. Consumed by `formatEntityContext()`/`resolveEntityContext()` in `memory/plugins/turn-context/src/entity-resolver.ts` — see root `CHANGELOG.md` (batch `entity-resolver-relationship-stats-543`) for the full consumer-side behavior change and `ARCHITECTURE-entity-resolver.md` for the updated API reference. **Breaking for direct consumers of `getEntityProfile()`:** code reading `profile.timezone` etc. directly must be updated to `profile.facts.timezone`.

### Fixed
- **`entities.last_seen` timezone-shift bug** (nova-mind#543) — rendering `last_seen` with `AT TIME ZONE 'UTC'` silently shifted the value under non-UTC sessions; fixed to use `to_char()` directly with no conversion, matching `created_at`. See RS-062 in `test.ts`.

### Changed
- **`entities.trust_level` column comment** (nova-mind#543, `database/schema.sql`) — updated from an enum-style description to reflect that the column is free-text and not enforced by a CHECK constraint.

### Tests
- `relationships/lib/entity-resolver/test.ts` (nova-mind#543) — integration scaffold plus RS-062 timezone regression test.
- `memory/plugins/turn-context/src/entity-resolver.test.ts` (nova-mind#543) — RS-001–RS-062 formatting matrix for `formatEntityContext()` (pure function).

### Added
- **IRC identifier support: `ircUsername` → `irc_username`** (nova-mind#522) — `ircUsername` added to `EntityIdentifiers` (`types.ts`) and `IDENTIFIER_TO_DB_KEY` (`resolver.ts`), mapping to the `irc_username` entity_facts key. This library only stores/matches the already-composed `<network>/<nick>` value — host/nick parsing and lowercasing happen upstream in the `turn-context` plugin (see `memory/CHANGELOG.md`). Companion pre-migration `database/pre-migrations/006-lowercase-irc-username-values.sql` normalizes existing mixed-case values. See root `CHANGELOG.md` (batch `irc-entity-resolver-522`) and `relationships/ARCHITECTURE-entity-resolver.md` for the full identifier-mapping table.

### Tests
- `relationships/lib/entity-resolver/test.ts` (nova-mind#522) — TC-522-013: regression test confirming combined non-IRC identifier conflict detection is unaffected by the new `ircUsername` mapping.

### Added
- **5 new platform identifier types** (#8, #159, #164) — `discordId`, `telegramId`, `slackMemberId`, `signalUuid`, `signalUsername` added to `EntityIdentifiers` interface and entity resolver. Each maps to a snake_case `entity_facts.key` via the `IDENTIFIER_TO_DB_KEY` constant.
- **`resolveEntityByIdentifiers()` function** (#8, #159, #164) — New resolver function with conflict detection. Fetches ALL matching entities (no `LIMIT 1`) and returns a `ResolveResult` discriminated union. If identifiers resolve to different entities, returns `{ ok: false, conflict: true }` with a descriptive message instead of silently picking a winner.
- **`ResolveResult` type** (#8, #159, #164) — New discriminated union type for conflict-aware entity resolution results.
- **`agent-install.sh` npm-installs entity-resolver in place** (#8, #159, #164) — installer runs `npm install` inside `lib/entity-resolver/` at the repo checkout path (it does not copy the library to `~/.openclaw/lib/`); hooks import it directly from wherever the repo is checked out, e.g. `<checkout-path>/lib/entity-resolver`.

### Changed
- **Migrated POSTGRES_* → PG* env vars** — all scripts now use standard PostgreSQL variable names (`PGHOST`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`) instead of legacy `POSTGRES_*` names; updated README environment configuration section ([#18](https://github.com/nova-openclaw/nova-relationships/issues/18))

### Added
- **Prerequisite check in `agent-install.sh`** — installer verifies `~/.openclaw/lib/env-loader.sh` (from nova-memory) exists before proceeding; exits with clear guidance if missing ([#18](https://github.com/nova-openclaw/nova-relationships/issues/18))
