# Changelog

## Unreleased

### Changed
- **Migrated POSTGRES_* → PG* env vars** — all scripts now use standard PostgreSQL variable names (`PGHOST`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`) instead of legacy `POSTGRES_*` names; updated README environment configuration section ([#18](https://github.com/nova-openclaw/nova-relationships/issues/18))

### Added
- **Prerequisite check in `agent-install.sh`** — installer verifies `~/.openclaw/lib/env-loader.sh` (from nova-memory) exists before proceeding; exits with clear guidance if missing ([#18](https://github.com/nova-openclaw/nova-relationships/issues/18))
