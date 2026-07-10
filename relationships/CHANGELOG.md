# Changelog

## Unreleased

### Added
- **5 new platform identifier types** (#8, #159, #164) — `discordId`, `telegramId`, `slackMemberId`, `signalUuid`, `signalUsername` added to `EntityIdentifiers` interface and entity resolver. Each maps to a snake_case `entity_facts.key` via the `IDENTIFIER_TO_DB_KEY` constant.
- **`resolveEntityByIdentifiers()` function** (#8, #159, #164) — New resolver function with conflict detection. Fetches ALL matching entities (no `LIMIT 1`) and returns a `ResolveResult` discriminated union. If identifiers resolve to different entities, returns `{ ok: false, conflict: true }` with a descriptive message instead of silently picking a winner.
- **`ResolveResult` type** (#8, #159, #164) — New discriminated union type for conflict-aware entity resolution results.
- **`agent-install.sh` npm-installs entity-resolver in place** (#8, #159, #164) — installer runs `npm install` inside `lib/entity-resolver/` at the repo checkout path (it does not copy the library to `~/.openclaw/lib/`); hooks import it directly from wherever the repo is checked out, e.g. `<checkout-path>/lib/entity-resolver`.

### Changed
- **Migrated POSTGRES_* → PG* env vars** — all scripts now use standard PostgreSQL variable names (`PGHOST`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`) instead of legacy `POSTGRES_*` names; updated README environment configuration section ([#18](https://github.com/nova-openclaw/nova-relationships/issues/18))

### Added
- **Prerequisite check in `agent-install.sh`** — installer verifies `~/.openclaw/lib/env-loader.sh` (from nova-memory) exists before proceeding; exits with clear guidance if missing ([#18](https://github.com/nova-openclaw/nova-relationships/issues/18))
