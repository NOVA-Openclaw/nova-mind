# SE Run #1231, Step 9 — Documentation Audit Report

Scope: nova-mind `fix/se1231-openclaw-2026.9-regressions` (af1be95) and nova-workspace
`fix/se1231-gate-check-250` (a15e492) vs origin/main. Full-tree doc audit per workflow 4
step 9. Tracking: nova-mind#715.

## Fixes applied (nova-mind)

- `memory/docs/memory-extraction-pipeline.md` — rewrote ~28 stale "memory-extract hook" /
  `handler.ts` references to "memory-extract plugin" / `extraction.ts`, and
  `openclaw hooks enable/list memory-extract` to `openclaw plugins enable/list` (#726:
  legacy hook deleted, migrated to `memory/plugins/memory-extract/`).
- `memory/README.md` — same hook→plugin terminology fix across install/enable/disable
  instructions; moved memory-extract from "Available Hooks" to "Available Plugins".
- `ARCHITECTURE.md`, `memory/ARCHITECTURE.md` — fixed data-flow diagrams and failure-handling
  prose still saying "memory-extract hook".
- `HEARTBEAT.md` (nova-mind root) — Idle Detection section still said the gate check reads
  `~/.openclaw/agents/nova/sessions/sessions.json`; it now uses `openclaw sessions --json`
  (#710/#714). Added the fail-closed/exit-3/scrubbed-error contract, which was undocumented.
- nova-workspace `docs/dashboard-context-producer.md` — added a known-gap note
  (nova-workspace#264) that this script, unlike the gate check (#250), has not been migrated
  off `sessions.json`.

Confirmed already correct (devs' own commits): `memory/docs/integration-overview.md`,
`memory/docs/deployment-setup-guide.md`, `memory/docs/semantic-recall.md`,
`database-config.md`, nova-workspace `HEARTBEAT.md`, `README.md` (#250 section).

## Flagged, not fixed (out of scope / pre-existing)

- `skills/proactive-mode/SKILL.md` (nova-workspace) — already flagged stale by a prior
  SE#1014 audit (tasks table → OpenProject migration); unrelated to #1231, needs a full
  rewrite per its own note.
- #728 (extraction 0 facts on deepseek-v4-flash), #729 (48h liveness alarm), #264 (dashboard
  producer sessions.json) — documented as known-open per issue #715, not fixed (SE scope).
- `memory/docs/memory-extraction-pipeline.md`'s pre-existing `memory-catchup.sh` →
  `process-input.sh` latent-bug note — left as-is (already correctly flagged, not new).

## Not found stale (checked)

CHANGELOG.md / memory/CHANGELOG.md hook→plugin wording already updated by the feature
commits; schema-reference.md row counts match schema.sql; motivation/README.md cadence note
(30m, 20m pending) still accurate; agent-config-sync README/HOOK.md not touched (no #707
drift found in prose).
