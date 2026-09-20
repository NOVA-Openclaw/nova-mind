# SE Run #866, Step 9 — Documentation Audit Report

**Scope:** Document the nova-mind#660 fix (map DB `agents.thinking` → emitted `entry.thinkingDefault` in `agent_config_sync`'s `buildAgentsList()`) against the actual diff on branch `fix/660-thinking-thinkingdefault` (commits `fe918dd`, `5907700`, `b8fcfdb`, `d1d25cd`), and audit in-scope project documentation for stale references to the prior "thinking is not written to agents.json" behavior.

**Method:** Checked out `fix/660-thinking-thinkingdefault`, read the four #660-tagged commits' diffs directly (`sync.ts`, `sync.test.ts`, `sync.integration.test.ts`, `package.json`), read `tests/TEST-CASES-ISSUE-660.md` (Gem's test design) for ground truth on intended behavior, ran the plugin's test suite (`npm test` in `cognition/focus/agent-config-sync/`) to confirm the #660-specific tests pass, then grepped the full repo for `thinking` across all `*.md` files and read every hit for relevance.

## Files Updated (5)

| File | Why |
|---|---|
| `cognition/README.md` | Corrected the "thinking is never written to agents.json" bullet, which described the pre-#660 behavior as current. Now describes the actual `buildAgentsList()` mapping: valid schema-enum values become `entry.thinkingDefault`; invalid/null/empty values are omitted; spawn-time `sessions_spawn(thinking=...)` still overrides at the point of use, but the DB-configured default now actually reaches the runtime's `normalizeThinkLevel` resolution chain instead of being silently dropped. |
| `cognition/focus/agent-config-sync/HOOK.md` | Added `thinkingDefault` to the example JSON output and to the field-rules bullet list, so a reader following this hook doc sees the real output shape. |
| `cognition/focus/agent-config-sync/README.md` | Added a `thinkingDefault` row to the "Entry fields" table (source column, enum values, omission conditions) and a note under the DB Filter section pointing at it. This is the plugin's primary reference doc — the field reference table is the most load-bearing artifact for anyone extending or debugging the plugin. |
| `cognition/CHANGELOG.md` | New `### Fixed (#660 — ...)` entry under `## Unreleased` describing the mapping, the schema-enum-vs-DB-CHECK validation-source decision, the omission conditions, and the new unit/integration test coverage. Includes an explicit "Known gap (not fixed by this batch)" bullet documenting the `agent-install.sh` parity gap (see Discrepancies below) so it is not lost between now and whenever it is picked up. |
| `TEST-DESIGN-429-installer-agents-json.md` | F10 (a #429 ground-truth fact stating neither code path ever emits a `thinking` key) is now **half-stale**: true for the installer, false for the plugin post-#660. Added a second post-implementation note explaining the split, annotated F10 itself, and annotated `TC-429-P-06` (an installer/plugin *parity* test case whose expected result no longer holds for the plugin side) so a future reader of this historical test-design doc does not mistake it for current behavior. Did not rewrite F10/TC-429-P-06 in place — annotated instead, consistent with how the doc already handles the #429 pre/post-fix distinction (preserves the historical record while flagging staleness). |

## Audit Result

Grepped all `*.md` files repo-wide for `thinking` (23 files matched). Read every match.

- **Stale references found and fixed:** 2 — `cognition/README.md`'s "never written to agents.json" bullet (direct #660 contradiction) and `TEST-DESIGN-429-installer-agents-json.md`'s F10/TC-429-P-06 (indirect staleness — a #429 ground-truth fact about `sync.ts` that #660 falsified for one of the two code paths it covered).
- **All other 21 files:** confirmed NOT stale — none describe the `agents.json` thinking-field sync behavior. They fall into three buckets: (a) unrelated uses of the word "thinking" in a plain-English sense (SOUL.md templates, confidence-gating docs, pitfalls.md — "subagents are extensions of your thinking"); (b) references to the `agents.thinking` DB *column* itself (schema docs, delegation-context.md's live-rebuilt spawn-instructions section, agent-ecosystem SKILL.md's spawn-time lookup guidance) which remains accurate — the column's existence, type, and CHECK constraint are unchanged by #660; (c) historical/fixture test-case docs (`TEST-CASES-batch-agent-identity.md`, `test-cases-273-heartbeat-schema.md`, `memory/tests/TEST-CASES-ISSUE-127.md`, `tests/DOC-AUDIT-RUN333.md`, `tests/test-cases-batch-se-run-8.md`) that use `thinking` as DB-row fixture data for other issues, not as a claim about `agents.json` output shape.

No file made a claim that `agents.json` never contains a `thinking`/`thinkingDefault` key that would now be actively false, other than the two fixed above.

## Discrepancy Surfaced (implementation gap, not papered over)

**`agent-install.sh`'s `_generate_agents_json()` was not updated alongside the #660 `sync.ts` change.** Verified via `git diff main...fix/660-thinking-thinkingdefault -- agent-install.sh` — the only diff on that file on this branch is unrelated (an earlier unrelated line), and `agent-install.sh` was not touched by any of the four #660 commits (`fe918dd`, `5907700`, `b8fcfdb`, `d1d25cd`).

This matters because the installer's inline SQL query for `_generate_agents_json()` **explicitly documents itself** as mirroring `sync.ts`'s `buildAgentsList()` (comment: "Shape logic mirrors sync.ts's buildAgentsList()") and was the subject of a dedicated parity test suite (`TEST-DESIGN-429-installer-agents-json.md`, `TC-429-P-06`) asserting the installer and plugin produce identical output shapes. That parity claim is now false for this one field: the plugin emits `thinkingDefault` for valid DB values; the installer's fresh-install/`--regenerate-agents-json` path does not.

**Practical impact:** A fresh install (or an explicit `--regenerate-agents-json` run) will produce an `agents.json` missing `thinkingDefault` for every agent, even when the DB has valid `thinking` values set. This is silently self-correcting in the common case — the `agent_config_sync` plugin performs its own **initial sync** on gateway startup (per `HOOK.md` step 1 and `README.md`'s "On startup, the plugin performs an initial sync"), which calls the real `buildAgentsList()` and would overwrite the installer-generated file with the correct `thinkingDefault` values. But there is a window (between installer completion and first gateway startup, or in any deployment mode where the plugin doesn't run) where the installer-generated `agents.json` under-reports per-agent thinking defaults.

I have **not** attempted to fix `agent-install.sh` myself — that is a code change outside doc-audit scope and outside this task's authorization (the brief asks me to report discrepancies that suggest an implementation gap, not paper over them in docs). I've documented the gap in three places so it isn't lost:
1. `cognition/CHANGELOG.md`'s new #660 entry (explicit "Known gap" bullet)
2. `TEST-DESIGN-429-installer-agents-json.md` (F10 annotation + TC-429-P-06 annotation, since that's the doc whose own test case this breaks)
3. This report

**Recommend:** a follow-up issue (or an amendment to #660 before merge) to port the same `VALID_THINKING_DEFAULTS` enum check into `agent-install.sh`'s `INITIAL_SYNC_QUERY` CASE logic, plus a corresponding update to `TC-429-P-06`'s expected behavior once that lands. Flagging to Project Leadership / Coder rather than filing a new GitHub issue myself, since #660 is still open on this same branch and the right home for the fix (amend #660 vs. new issue) is a call for whoever owns the merge.

## Commit

Docs committed to `fix/660-thinking-thinkingdefault` at `0bb5247`.
