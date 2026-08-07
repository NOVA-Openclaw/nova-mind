# Changelog

### Batch: append-run-note-557 (Issue #557)

#### Added
- **`append_run_note(p_run_id integer, p_note text)` — server-side timestamped `workflow_runs.notes` append** (nova-mind#557) — Promotes lesson 757 ("append, don't overwrite, run notes") from convention to database-enforced behavior. Previously, agents updated `workflow_runs.notes` directly via ad-hoc `UPDATE ... SET notes = COALESCE(notes,'') || ...` statements, which meant every caller had to independently reproduce the correct concatenation and timestamp formatting — and nothing prevented a caller from clobbering existing notes with a plain `SET notes = '...'`. `append_run_note()` is now the single supported write path:
  - **Signature:** `append_run_note(p_run_id integer, p_note text) RETURNS void`.
  - **Security model:** `SECURITY DEFINER`, `SET search_path = public` pinned (prevents search-path hijacking since it runs with definer privileges). `EXECUTE` is granted to all 17 agent database roles, so any agent can append a note to any run — the function only writes the single `notes` column via its own `UPDATE`, it does not expose broader `workflow_runs` write access.
  - **Timestamp format:** Each call prepends a UTC stamp of the form `YYYY-MM-DD HH24:MI UTC — ` ahead of the note text, computed server-side via `now() AT TIME ZONE 'UTC'` (not the caller's session timezone), then appends the stamped line to the existing value with a newline separator — the very first note on a run gets no leading newline.
  - **NULL vs. empty-string handling:** `p_note IS NULL` raises `append_run_note: p_note cannot be NULL`. An empty string (`''`) is accepted and produces a stamped line with nothing after the `— ` separator — this is intentional (e.g. a bookend marker with no free-text content) and documented in the function's `COMMENT ON FUNCTION`.
  - **Missing run_id:** Raises `append_run_note: run_id % not found` when no row matches `p_run_id` (checked via `FOUND` after the `UPDATE`).
  - **Usage:** `SELECT append_run_note(<run_id>, 'note text');`
  - Defined in `database/schema.sql` (~lines 3804-3843), applied via the standard `pgschema` declarative flow — no new migration file needed since `workflow_runs.notes` already existed as a column, only the write-path function is new.

#### Tests
- `tests/issue-557/test-append-run-note.sh` + `tests/issue-557/README.md` (nova-mind#557) — TC-1 through TC-16 automated (concatenation/newline behavior, NULL vs. empty-string notes, nonexistent run_id, NULL run_id, `SECURITY DEFINER`/`search_path` catalog verification, per-role `EXECUTE` privilege checks across all 17 agent roles, unicode/long-note/special-character payloads, concurrent-append ordering) plus TC-17/TC-18 documented as manual staging steps for `pgschema apply`/re-apply idempotency (full schema apply against a staging database mirroring production roles is required for these two; not automatable in the same script). Staging run: all cases PASS; QA verdict PASS-WITH-CONDITIONS (conditions are follow-up items, not blockers — see nova-mind#559).

#### Issues Closed
- #557 — Promote lesson 757 (append-only workflow run notes) to a database-enforced `append_run_note()` function

### Batch: memory-extraction-reliability-497 (Issue #497)

#### Fixed
- **Config-driven, hot-reloadable extraction timeout** (nova-mind#497) — The `memory-extract` hook (`memory/hooks/memory-extract/handler.ts`) previously used a fixed 30-second `EXTRACTION_TIMEOUT_MS` constant (#485). Post-deploy monitoring (issue #497, discovered via SE run #448 step 12 introspection) found deepseek-v4-flash's p95 extraction latency regularly exceeded 30s, producing a ~15% first-attempt timeout rate (9 of 13 dead-letter rows in a 3.5h window) — all of which succeeded on replay, confirming the constant was too tight rather than indicating a genuine hang. `loadExtractionTimeoutMs()` now reads `extraction_timeout_ms` from `~/.openclaw/scripts/memory-extraction-config.json` on every hook invocation (no caching, so edits hot-reload with no gateway/hook restart), defaulting to **90000ms (90s)** when the field is absent, non-numeric, or `<= 0`. Precedence: `EXTRACTION_TIMEOUT_MS_OVERRIDE` env var (test-only) > config file > hardcoded default. The 90s default is not arbitrary: `extract_memories.py`'s inner `requests.post(..., timeout=60)` call is 60s, and the outer hook timeout must exceed it so a slow LLM call fails cleanly inside the Python child (normal `RuntimeError`, exit 1) rather than being `SIGTERM`'d by the hook mid-request.
- **One-shot JSON repair pass + `json_parse_failure` exit-code taxonomy** (nova-mind#497) — `extract_memories.py`'s `call_llm()` previously raised a bare `RuntimeError` (indistinguishable from a network/HTTP failure) on any non-JSON LLM response, with no recovery attempt for near-miss malformed output. `call_llm()` now makes exactly one repair attempt via the new `json_repair` dependency when `json.loads()` fails (no retry loop, no re-prompt). A bare top-level JSON array is handled explicitly: a list of fact-shaped dicts (each with `key` or `value`) wraps to `{"facts": [...]}`; an empty list is a no-op (`{}`); anything else (bare scalars, non-fact-shaped dicts, or a non-dict/non-list top-level type) raises the new `JsonParseFailure` exception (a dedicated `RuntimeError` subclass so `main()`'s exit-code dispatch is unambiguous). `main()` maps `JsonParseFailure` to **exit code 2** (distinct from the existing generic-error exit code 1); `handler.ts` maps exit code 2 to `failure_reason='json_parse_failure'` in the `extraction_failures` dead-letter table, with timeout detection still taking precedence over exit-code inspection when both could apply.
- **Type-generic fact-value coercion** (nova-mind#497) — `coerce_fact_value()` normalizes any LLM-emitted value type before persistence instead of only handling strings: `bool` → `"true"`/`"false"` (JSON-lowercase literal; `False` now survives falsy guards instead of being silently dropped), `int`/`float` → `str()`, `dict`/`list` → `json.dumps()`, `None` → skipped with a logged stderr notice (dropped, not stored as the literal string `"None"`), `str` → stripped as before.
- **Interpreter resolution chain + graceful `json_repair` degradation** (nova-mind#554, #555, amending the above) — Both spawn paths for `extract_memories.py` (`handler.ts` and the standalone `extraction-replay.sh`) now resolve the Python interpreter via the same first-match-wins order: `EXTRACTION_PYTHON_CMD_OVERRIDE` env var → `python_cmd` key in `memory-extraction-config.json` → agent venv python (`~/.local/share/<user>/venv/bin/python3`) if present → bare `python3`. `handler.ts` logs the result once per invocation as `[memory-extract] Resolved extraction interpreter { pythonCmd: ... }` for deploy verification. `extraction-replay.sh` mirrors the same order and uses `$(id -un)` rather than `$USER` for the venv path lookup — `$USER` is unset in cron environments, which previously collapsed the venv path and silently fell through to bare `python3` under cron, reintroducing the system-python failure class this work closes (#555). Separately, `extract_memories.py`'s `json_repair` import is now lazy and guarded rather than a top-level unconditional import (#554): if the resolved interpreter's environment lacks `json_repair`, extraction still completes end-to-end — one stderr warning is logged, no repair attempt is made, and malformed JSON goes straight to exit code 2 / `failure_reason='json_parse_failure'`. Full docs: `memory/docs/memory-extraction-pipeline.md` ("Interpreter resolution" note in §1) and `memory/hooks/memory-extract/HOOK.md`.

#### Migrations
- `memory/migrations/086_extraction_failures_json_parse_failure.sql` (nova-mind#497) — Extends the `extraction_failures.failure_reason` CHECK constraint to add `json_parse_failure` alongside the existing `nonzero_exit`/`timeout`/`spawn_error`/`unreplayable` values. Forward-only migration; header documents the accepted irreversible state for any `json_parse_failure` rows written before a hypothetical future revert (PostgreSQL does not retroactively re-validate existing rows against a loosened/dropped CHECK constraint).

#### Changed
- **`json_repair` added to `REQUIRED_PACKAGES`** (nova-mind#497) — Repo-root `agent-install.sh`'s Python venv setup now installs `json_repair` alongside `openai`/`tiktoken`/`psycopg2-binary`/`pillow`. Importable as `json_repair` directly, so no `PACKAGE_MODULE_MAP` entry was needed.

#### Tests
- `tests/issue-497/test_extract_memories.py` — pytest coverage for `call_llm()`'s JSON repair paths (valid JSON, repairable/unrepairable malformed JSON, bare-array wrap contract including empty-list no-op and non-fact-shaped rejection, markdown-fence stripping, unexpected top-level type), `coerce_fact_value()`'s type coercion matrix, and `main()`'s exit-code-2 mapping for all three `JsonParseFailure` raise sites.
- `tests/issue-497/test-handler.js` — Node.js tests for `handler.ts`'s config-driven timeout (env override precedence, hot reload, malformed/missing/unreadable config fallback to default), the `json_parse_failure` exit-code-2 taxonomy mapping, timeout-takes-precedence-over-exit-code behavior, and the non-blocking invariant (hook never throws).
- `tests/issue-497/validate-migration.sh` — Migration 086 idempotency (two consecutive applies succeed), CHECK constraint extension verification, and existing-row safety (pre-migration `nonzero_exit` rows remain valid and unchanged after the constraint is extended).

#### Issues Closed
- #497 — memory-extract: ~15% extraction timeout rate at fixed 30s `EXTRACTION_TIMEOUT_MS` with deepseek-v4-flash (surfaced by #485 dead-letter table)

See `memory/CHANGELOG.md` for the memory-subsystem-side changelog entry.

### Batch: entity-resolver-relationship-stats-543 (Issue #543)

#### Added
- **Pronouns + relationship stats in turn-context entity injection** (nova-mind#543) — the turn-context entity injection (`memory/plugins/turn-context/src/entity-resolver.ts`'s `formatEntityContext()`) previously showed only a 7-key allowlist of facts. It now also renders:
  - `entities.pronouns` in the `👤 **Talking with:**` header, e.g. `👤 **Talking with:** Tabatha Janell Wilson (she/her)`.
  - An optional trust suffix from `entities.trust_level` (free-text, e.g. `— trust: friend`) — suppressed when the value is `'unknown'` (the column default) or NULL, since that conveys no information.
  - A new `📊 Known contact:` stats line with unfiltered fact count, first-seen date (`entities.created_at`), and last message timestamp + `provider:external_chat_id` ref (from `channel_transcripts`/`channel_sessions`) — falling back to `entities.last_seen` when no transcript row exists.
  - `relationships/lib/entity-resolver/resolver.ts`'s `getEntityProfile()` return type changed from a bare `EntityFacts` map to `EntityProfile` (`{ facts, stats }`) — a breaking signature change for any direct consumer. `resolver.ts` also gains a shared `mapDbEntity()` helper so `pronouns`/`trust_level`/`last_seen`/`created_at` ride on the existing cheap identifier-resolution query (`resolveEntity()`/`resolveEntityByIdentifiers()`) rather than a second round trip — this means pronouns/trust/last-seen survive a `getEntityProfile()` stats-query timeout, since they're already on the resolved `Entity` before the stats race even begins.
  - The stats query itself (unfiltered fact count + most recent transcript, via a single aggregate query with two `LEFT JOIN LATERAL`s) stays inside the existing 1s `Promise.race` timeout in `resolveEntityContext()`; on timeout or error it degrades to `{ facts: {}, stats: { factCount: 0, lastMessage: null } }`, matching the library's existing fail-closed contract.
  - Honorific guard path (`resolveEntityForGuard()`) is unchanged — it never triggers the stats query.
  - `database/schema.sql`'s `entities.trust_level` column comment updated from an enum-style description to reflect that it is free-text, not enforced by a CHECK constraint.

#### Fixed
- **`entities.last_seen` timezone-shift bug** (nova-mind#543) — `resolveEntity()`/`resolveEntityByIdentifiers()` originally rendered the naive (no-tz) `entities.last_seen` timestamp with `AT TIME ZONE 'UTC'`, which Postgres interprets as "convert from the session's timezone to UTC" — silently shifting the displayed value under any non-UTC session (e.g. `America/Chicago`). Fixed to render directly via `to_char(e.last_seen, 'YYYY-MM-DD HH24:MI "UTC"')` with no timezone conversion, matching how `created_at` is already rendered. See the RS-062 regression test in `relationships/lib/entity-resolver/test.ts` (run under `SET timezone='America/Chicago'`).

#### Tests
- `memory/plugins/turn-context/src/entity-resolver.test.ts` (nova-mind#543) — RS-001 through RS-062: full formatting matrix for `formatEntityContext()` (pronouns, trust suffix incl. `'unknown'`/NULL suppression, stats-line permutations, zero-fact/new-contact rendering, group-channel cache non-contamination), plus stats-query timeout/error-degradation behavior.
- `relationships/lib/entity-resolver/test.ts` (nova-mind#543) — integration scaffold plus RS-062 (timezone regression under `SET timezone='America/Chicago'`).

#### Issues Closed
- #543 — Pronouns + relationship stats in turn-context entity injection

See `relationships/CHANGELOG.md` for the entity-resolver library's own changelog entry.

### Batch: pg-notify-alert-sender-508 (Issue #508)

#### Fixed
- **`pg-notify-listener.py` alerts use connecting PGUSER as sender and self-safe recipients** (nova-mind#508) — Alert notifications (`_send_push_alert` and `_send_branch_alert`) in the schema-sync listener previously hardcoded the sender as `'schema-sync'`. Because `send_agent_message()` enforces `LOWER(p_sender) == session_user` and no `'schema-sync'` DB user exists, these alerts silently failed to deliver in production since 2026-07-12. The listener now dynamically binds the sender to the connecting `PGUSER` from `_agent_chat_env` (and uses that user to connect to the `agent_chat` database), prefixes the body with `[schema-sync]` for attribution, and applies a smart self-safe recipient resolution strategy (`_alert_recipients()`):
  - Excludes the sending user from the recipient list to satisfy the self-address guard in `send_agent_message()` (which throws if the sender is in the recipients list).
  - Routes primarily to `nova`. If the sender is `nova` (e.g. running as the primary nova agent), it falls back to `graybeard`. If both match the sender, it falls back to broadcast (`*`).
  - Alert helpers remain strictly non-raising; any error along the alert path (missing PGUSER, connection failure, or database error) is logged and swallowed, preventing alert failures from disrupting the schema-sync NOTIFY loop or hiding true sync success/failure outcomes.

#### Tests
- `cognition/tests/test_pg_notify_listener_issue_508.py` (nova-mind#508) — 23 new tests covering sender binding, message prefixing, recipient self-avoidance (nova → graybeard, graybeard → nova, and fallback broadcast), connection kwarg sourcing, failure swallow/non-raising behavior, raw bound SQL parameter verification, and end-to-end regression paths mirroring #399 and #506 failure states.
- `cognition/tests/test_pg_notify_listener_issue_399.py` and `cognition/tests/test_pg_notify_listener_issue_506.py` (nova-mind#508) — updated pre-existing assertions to align with the new PGUSER sender, message prefix, and self-safe recipient resolver.

#### Issues Closed
- #508 — pg-notify-listener.py agent_chat alerts are latently broken (hardcoded 'schema-sync' sender rejects)

### Batch: irc-entity-resolver-522 (Issue #522)

#### Added
- **IRC entity resolution** (nova-mind#522, PR #525) — `extractIdentifiers()` in `memory/plugins/turn-context/src/entity-resolver.ts` gains an `"irc"` case, producing a composite `ircUsername` identifier of the form `<network>/<nick>` (e.g. `late.sh/druidian`, always lowercased per IRC's `CASEMAPPING=ascii` semantics):
  - **Network** derivation (`deriveIrcNetwork()`): lowercases the server host, then strips a leading `irc.` or `irc-` prefix if present (falls back to the full lowercased host when no prefix matches, e.g. `chat.freenode.net` stays as-is). Host source priority: `event.metadata.host`/`senderHost` (when the channel adapter supplies it) → resolved from OpenClaw config via the new `resolveIrcHostFromConfig(accountId, config)`, which checks `channels.irc.accounts[accountId].host` first, then falls back to top-level `channels.irc.host`.
  - **Nick** parsing (`parseIrcNick()`): handles both a bare nick and a `nick!user@host` mask, taking everything before the first `!`.
  - `memory/plugins/turn-context/src/index.ts`'s `message_received` handler now caches `accountId` and `host` per sender (`SenderCache` interface) alongside existing fields, and passes the plugin's `config` object through the `before_prompt_build` context so `resolveIrcHostFromConfig()` can use the already-loaded config without re-reading `openclaw.json` from disk on every call.
  - If network derivation fails (no host resolvable from any source, or the stripped result is empty — e.g. a bare `irc.` host), IRC entity resolution gracefully skips (logs `IRC network derivation failed for sender ...` and returns `null`) rather than resolving with a garbage identifier.
  - Companion resolver-lib change: `relationships/lib/entity-resolver` gains `ircUsername` → `irc_username` in the `IDENTIFIER_TO_DB_KEY` constant (`resolver.ts`) and the `EntityIdentifiers` interface (`types.ts`). The library only stores/matches the already-composed value — it does not parse hosts or nicks itself.
  - Full identifier-mapping documentation: `relationships/ARCHITECTURE-entity-resolver.md`, `memory/docs/semantic-recall.md` (Entity Resolution section).

#### Fixed
- **`resolveIrcHostFromConfig()` hardened against malformed IRC config** (nova-mind#522) — Desk review during initial #522 testing found the original implementation called `.trim()` on `irc.accounts?.[accountId]?.host` and `irc.host` without a `typeof === "string"` guard, so a config value of the wrong type (e.g. `host: 12345`, from a hand-edited or corrupted `openclaw.json`) would throw synchronously into the shared `before_prompt_build` hook path for every message, not just IRC messages. The function now validates the IRC config shape (`irc && typeof irc === "object" && !Array.isArray(irc)`), checks `typeof === "string"` before every `.trim()` call, and wraps the entire body in try/catch returning `undefined` with a `console.warn` — matching the graceful-skip contract already used elsewhere in this file (`readOpenClawConfig()`'s own catch handles missing-file/invalid-JSON; this fix covers the additional unexpected-shape cases inside the already-parsed config object).

#### Migrations
- `database/pre-migrations/006-lowercase-irc-username-values.sql` (nova-mind#522) — One-time idempotent data cleanup: `UPDATE entity_facts SET value = lower(value) WHERE key = 'irc_username' AND value != lower(value)`. Normalizes pre-existing mixed-case `irc_username` fact values (e.g. `entity_facts` id=26989, `late.sh/Druidian`) to lowercase so exact-match resolution against the new lowercased composite values works immediately post-deploy. Must run atomically with (before or alongside) the code deploy above — read via `database/pre-migrations/` per the standard installer pre-migration path (see `memory/INSTALLATION.md`).

#### Tests
- `memory/plugins/turn-context/src/index.test.ts` (nova-mind#522) — TC-522-014–024, TC-522-032–036: new IRC identifier-extraction tests (bare nick, `nick!user@host` mask, missing host, empty/whitespace nick, IRC-legal special chars in nick, network-derivation case-folding and prefix handling, prefix-only-host empty-network skip) plus regression coverage confirming discord/telegram/slack/signal/unknown-provider/device-provider extraction paths are unchanged by the new `irc` case. TC-522-036 covers config-driven host resolution via `accountId` (default account → top-level host, named account → account-specific host).
- `memory/plugins/turn-context/src/index.test.ts` (nova-mind#522) — TC-522-028 (4 sub-cases): config-read/parse resilience for the IRC path — missing config file, invalid JSON, non-string `host`, non-string per-account `host`, all asserting graceful-skip (`{}`) with no throw. Only the two non-string-host sub-cases exercise the new `resolveIrcHostFromConfig` hardening fix above; the missing-file and invalid-JSON sub-cases exercise pre-existing `readOpenClawConfig()` resilience (its own try/catch predates #522). See `tests/TEST-CASES-ISSUE-522.md` for the execution-status tracker.
- `relationships/lib/entity-resolver/test.ts` (nova-mind#522) — TC-522-013: regression test confirming combined non-IRC identifier conflict detection (`resolveEntityByIdentifiers()`) is unaffected by the new `ircUsername` mapping.

#### Known follow-ups (not part of this fix)
- The `deviceId` identifier field exists in `EntityIdentifiers`/`IDENTIFIER_TO_DB_KEY` but has no corresponding `extractIdentifiers()` case in `memory/plugins/turn-context` today (TC-522-024 documents this gap as a regression guard — #522 must not, and does not, widen the default provider match to cover it). Out of scope for this issue.

#### Issues Closed
- #522 — IRC entity resolver support (composite `<network>/<nick>` identifier, config-driven host resolution, lowercase-normalization migration)

### Batch: schema-sync-branch-safety-506 (Issue #506)

#### Fixed
- **`sync_schema_to_github()` now asserts branch safety before every schema dump/commit/push** (nova-mind#506) — Every sync attempt since 2026-07-17 had silently committed and pushed schema dumps onto whatever branch the listener's working clone (`~/.openclaw/workspace/nova-mind`) happened to have checked out, because the function never verified `HEAD`. The clone was left on a stale feature branch after prior work concluded, causing pushes to fail (branch diverged from its remote) while `database/schema.sql` on `main` silently drifted from the live database — masked because failures only wrote a `False` event, with no alert. A new `_ensure_on_main()` check now runs first thing inside the existing git-lock critical section (after lock acquisition, before the `pgschema dump` step) on **every** call — there is no process-lifetime cache, so branch state is re-verified even between long-lived daemon invocations:
  - **Already on `main`:** fetch `origin` and fast-forward if origin is ahead; proceeds normally.
  - **Wrong branch or detached `HEAD`:** checkout `main`, fetch `origin`, fast-forward — proceeds normally once remediated. The previously-checked-out branch/commit is left untouched (no commits are ever created on it, before or during the switch).
  - **`main` has diverged from `origin/main` (ff-only merge fails):** abort loudly — no commit is created, nothing is pushed, local divergent commits are preserved unchanged. Returns `(False, None)` and sends an `agent_chat` alert (`_send_branch_alert()`, sender `schema-sync` → `nova`) naming the expected/found branch and the exact manual reconciliation commands (`git fetch origin && git rebase origin/main && git push origin main`).
  - **Checkout or fetch fails outright** (e.g., dirty working tree blocking `git checkout main`, or the remote is unreachable): abort loudly the same way — `(False, None)` plus an alert with failure-specific remediation commands. Uncommitted edits are never discarded (git itself refuses the checkout/merge when a dirty file would be clobbered, and the code treats that refusal as an abort signal rather than forcing through with `--force`).
  - The git lock (`_git_lock_path` flock) is acquired before the branch check runs and released unconditionally in the function's single `finally` block on every exit path, including the new early-return-on-abort paths — lock discipline is unchanged from the #399-era contract.
  - No behavior change to the existing push retry/backoff/failure-classification logic (`_classify_push_failure()`, `_send_push_alert()`) — those paths are untouched and only run after branch safety is confirmed.
  - Full detail (invariants, remediation matrix, alert semantics): `cognition/CHANGELOG.md` (`schema-sync-branch-safety-506` batch) and `cognition/scripts/pg-notify-listener.py` (`_ensure_on_main`, `_send_branch_alert`).

#### Tests
- `cognition/tests/test_pg_notify_listener_issue_506.py` — 11 new tests (14–23, continuing the #399 suite's numbering) covering: happy path (already on main, in sync, no extra alert/commit churn), wrong-branch remediation (feature branch tip byte-identical before/after — the core #506 regression check), detached-`HEAD` remediation, behind-origin fast-forward (commit correctly parented on the fetched tip, no alert on routine catch-up), diverged-main abort (local commits preserved, nothing pushed), dirty-worktree preservation on both `main` and a wrong branch, push-failure-after-remediation return-contract parity (`(False, commit_hash)`), lock release on abort-before-dump and on remediation failure, re-entry re-detection (no one-shot cache), and concurrent same-clone calls (no wrong-branch commit under a forced interleaving race). Existing #399 fixtures were refactored into a shared `cognition/tests/conftest.py`; two #399 assertions (Tests 5/10) were intentionally updated because their "clone behind origin" scenario is now correctly reclassified from a push-time non-fast-forward failure to an auto-remediated fast-forward success — no other #399 assertion changed, and the full 27-test suite (16 #399 + 11 #506) passes. See `cognition/CHANGELOG.md` for QA sign-off detail.

#### Known follow-ups (not part of this fix)
- **nova-mind#507** — no automated test drives the `_send_push_alert()` non-fast-forward branch post-#506 (only reachable now via a narrow same-call TOCTOU race between the fast-forward and the subsequent push, both inside the held lock); code is untouched and correct by inspection, test coverage only.
- **nova-mind#508** — `pg-notify-listener.py` `agent_chat` alerts (`_send_push_alert` and the new `_send_branch_alert`) are latently broken in production: both hardcode sender `'schema-sync'`, and `send_agent_message()` now enforces `sender == session_user`, so every listener alert has silently failed to deliver since 2026-07-12. Pre-existing pattern inherited from #399-era code, not introduced by #506; this fix's error handling degrades correctly (alert-send failure is logged, never turns an abort into a false success).

#### Issues Closed
- #506 — schema-sync listener commits dumps onto whatever branch is checked out — silent total sync failure since Jul 17

### Batch: extraction-dead-letter-485 (Issue #485)

#### Added
- **`extraction_failures` dead-letter table + replay path** (nova-mind#485) — The
  `memory-extract` hook (`memory/hooks/memory-extract/handler.ts`) previously spawned
  `extract_memories.py` fire-and-forget with no stderr/stdout capture, no retry, and no
  persistence on failure — a System Diagnostic run (nova-mind#447) found ~10% of
  extractions failing silently (10/112 messages in a 33-hour window), permanently losing
  the source message body since it only existed at hook time. The hook now captures
  16384-byte tail buffers of the child's stderr/stdout (continuous-drain, so an unread
  pipe never stalls the child), enforces a 30-second timeout (SIGTERM, then SIGKILL after
  a 5-second grace period), and writes a row to the new `extraction_failures` table on
  nonzero exit, timeout, or spawn error, tagged with a `failure_reason` taxonomy
  (`nonzero_exit`, `timeout`, `spawn_error`, `unreplayable`). Migration
  `085_extraction_failures.sql` adds the table (FK to `channel_transcripts` with
  `ON DELETE SET NULL`, raw-body fallback column when no FK is available, CHECK
  constraints on `status`/`failure_reason`/`retry_count`, four named indexes including a
  composite replay-order index). New script `memory/scripts/extraction-replay.sh`
  (flock-guarded, batch/retry-limit configurable via env, `row_to_json`+`jq` body
  reconstruction to avoid a pipe/newline parsing bug caught in QA) replays pending rows
  via the same stdin-feed contract as the hook, following the `memory-catchup.sh`
  cron-script pattern and `GLOBAL/CRON_DESIGN` (script is the system of record for DB
  writes, not an agent-turn prompt). Full detail:
  `memory/docs/memory-extraction-pipeline.md#1a-failure-handling-extraction_failures-dead-letter-table--replay-485`.
  **Known debt (not addressed by this change):** both the hook and the replay script
  default `PGDATABASE` to a hardcoded `nova_memory` rather than deriving it from the OS
  user, tracked separately under nova-mind#487 (umbrella) / nova-mind#481.

#### Tests
- `tests/issue-485/validate-migration.sh`, `tests/issue-485/test-handler.js`,
  `tests/issue-485/test-replay.sh`, `tests/issue-485/test-replay-d6b.py` — 92/92 PASS on
  nova-staging across migration validation (17), handler behavior (52), and replay-script
  behavior (23, including the row_to_json/jq regression case). See
  `tests/issue-485/TEST-RESULTS-integrated.log` for the full run and contamination check
  (zero residual test rows on staging and production).

### Batch: comms-items-unified-lifecycle-474 (Issue #474)

#### Added
- **`comms_items` table** (#474) — unified lifecycle for asynchronous inbound
  communications (Gmail, X mentions/DMs, Nostr DMs; GitHub notifications deferred to a
  follow-up issue). Dedupe key is `UNIQUE (platform, item_id)` using immutable source
  identifiers (Gmail message id, tweet id, Nostr event id). Lifecycle:
  `inbound → reported → tracked → resolved | dismissed`. Columns: `platform`, `item_id`,
  `thread_id`, `entity_id` (FK → `entities`, nullable), `status` (CHECK-constrained),
  `disposition` (`fyi|actionable|escalation|receipt|injection_suspect`, CHECK-constrained),
  `summary` (poller-voice text, never raw relayed prose), `artifact_ref`, `first_seen_at`,
  `reported_at`, `resolved_at`. Replaces the inbound-lifecycle role of `social_interactions`,
  which is dropped by the fold migration below. Owner: Communications domain (hermes).
- **`comms_responses` table** (#474) — approval-gate sub-lifecycle for outbound responses
  to inbound X/Nostr mentions and DMs, 1:1 linked to `comms_items` via `comms_item_id`
  (`ON DELETE CASCADE`). Carries `draft_response`, `approved_by`, `approved_at`,
  `response_id`, `responded_at`, `notes`. Preserves the `social_interactions`
  drafted/approved/posted workflow that would otherwise have been orphaned by the fold.
- **`resolve_entity_by_identifier(key text, value text) RETURNS bigint`** (#474) — shared
  SQL entity-resolution helper mirroring `resolver.ts` logic: looks up `entity_facts` by
  key/value (case-insensitive), preferring highest confidence then most recently
  confirmed. Used by both the fold migration and the ingest script so schema-side and
  script-side resolution stay in sync. Tolerates no match (returns `NULL`); callers are
  responsible for normalizing identifier formats (e.g., Nostr npub vs. hex) before calling
  — full normalization convention tracked as a follow-up (#227).
- **Migration `164-fold-social-interactions-to-comms-items.sql`** (#474) — post-pgschema,
  idempotent fold of legacy `social_interactions` into `comms_items`/`comms_responses`.
  No-ops on fresh installs (guards on `social_interactions` existing). Maps
  `seen→inbound`, `needs_response|drafted|approved→tracked`, `posted→resolved`,
  `dismissed→dismissed`; preserves `dismissed_reason`/`notes` content by folding it into
  `summary` rather than discarding it; preserves `created_at` as `first_seen_at`. Excludes
  NOVA's own outbound X rows (`author_handle = 'NOVA_Openclaw'`) — inbound-only per the
  #474 scope decision (2026-07-14: general social-interaction/outbound-activity tracking
  is out of scope for this table). Drops `social_interactions` after a successful fold.
- **Deterministic comms ingest pipeline** (#474, `scripts/comms/ingest.py`) — per
  GLOBAL/CRON_DESIGN, all `comms_items` writes are script-side, never agent-turn prose.
  Flow: fetch (per-platform adapter) → dedupe on `(platform, item_id)` **before any LLM
  reasoning** → resolve entity → classify (rule-based, no LLM) → upsert → archive-on-
  resolution. Platform adapters: `scripts/comms/adapters/gmail.py`,
  `scripts/comms/adapters/x.py`, `scripts/comms/adapters/nostr.py` (with
  `scripts/comms/adapters/bech32.py` for Nostr npub/hex conversion). A platform fetch
  failure is isolated (logged as a per-platform error) and does not abort ingest for the
  remaining platforms.
- **`scripts/comms/classifier.py`** (#474) — pure rule-based (no LLM) disposition
  classifier. Detects direct-address imperatives ("NOVA, please run..."),
  ignore-instructions phrasing, authority-spoofing ("as I)ruid, I'm asking you to..."),
  and system/tool-markup injection attempts, tagging them `disposition=injection_suspect`
  regardless of claimed sender identity — authorization derives from the delivery
  mechanism and resolved `entity_id`, never from payload claims. Also classifies
  `fyi`/`receipt`/`escalation` via marker-word matching, defaulting to `actionable`.
  Summaries are capped previews in the poller's own voice, never the full raw body, so an
  injection payload cannot ride the summary through to the Hermes→NOVA report hop.
- **Consolidated `hermes-comms-check` cron job** (#474, `scripts/comms/hermes-comms-check.sh`)
  — replaces the previous two enabled comms-check cron entries (agent=hermes short brief +
  agent=nova interim-mitigation brief) with exactly one job, every 4 hours, running as the
  `hermes` DB user (re-execs via `sudo -u hermes` if invoked as another user). Installed and
  drift-checked by `agent-install.sh` (`_install_hermes_comms_check_cron`); `--verify-only`
  reports missing/drifted/installed status alongside the existing D100-announcer cron
  check. Logs to `~/.openclaw/logs/hermes-comms-check.log`.
- **`comms_checks` audit logging retained** (#474) — `log_comms_check()` continues writing
  one audit row per deterministic ingest run (summary, per-platform new/existing/skipped
  counts, injection candidates, actionable items) even as the underlying lifecycle model
  changes from `social_interactions`/ad hoc state to `comms_items`.
- **Grants** (#474) — `comms_items`/`comms_responses` follow the `comms_state` grant
  pattern: `hermes` retains INSERT/UPDATE (writer of record per CRON_DESIGN), DELETE
  revoked from `hermes`; all other non-owning agents have DELETE/INSERT/UPDATE revoked
  (SELECT retained); `nova` additionally has DELETE/INSERT revoked on `comms_responses`
  (approval actions happen through the workflow, not direct row creation).

#### Changed
- **`social_interactions` table removed** (#474) — dropped by migration 164 after its
  inbound rows are folded into `comms_items`/`comms_responses`. Outbound-only
  social-activity tracking (NOVA's own posts/likes/replies) was explicitly scoped out of
  `comms_items` (2026-07-14 scope decision) and has no replacement table in this change;
  see the #474 issue thread if that tracking need resurfaces.
- **`agent-install.sh`** (#474) — installs `scripts/comms/*.py` and `*.sh` to
  `~/.openclaw/scripts/comms/` (hash-compared, `--force` to overwrite), runs the 164 fold
  migration during schema apply, and installs/verifies the consolidated
  `hermes-comms-check` cron entry.

#### Tests
- `tests/TEST-CASES-ISSUE-474.md` — 50 test cases across 8 areas (schema structure,
  approval-gate sub-lifecycle, migration/fold, deterministic ingest, trust boundary/
  injection quarantine, entity resolution, boundary/adversarial sweep, cross-cutting
  concerns). See `tests/TEST-474-coverage-map.md` for the case→test-file mapping — 50/50
  passing.
- `tests/TEST-474-schema.sql`, `tests/TEST-474-migration.sql`,
  `tests/TEST-474-chunk1-schema.sql`, `tests/TEST-474-chunk2-migration.sql` — pgTAP schema
  and migration coverage.
- `tests/test_comms_ingest.py` — unit coverage for dedupe, classification, entity
  resolution, and archive-on-resolution behavior.
- `tests/test_comms_integration.sh` — end-to-end ingest→report integration coverage.
- `tests/install/test_hermes_comms_check_cron.bats` — cron installation/drift-detection
  coverage for the consolidated cron entry.
- Staging validation: 84/84 checks passing. QA validation: PASS.

#### Issues Closed
- #474 — `comms_items`: unified lifecycle + trust boundary for other-comms (email,
  mentions, DMs)

### Batch: d100-motivation-refinements-444 (Issue #444)

#### Added
- **Generative empty slots for `motivation_d100`** (#444) — `roll_d100()`'s return contract
  gains an additive `is_populate_me boolean` column (15-column shape; no sentinel strings).
  A roll landing on a non-reserved empty slot (`task_name IS NULL`, `reserved = false`,
  `enabled = true`) now returns `is_populate_me = true` instead of silently re-rolling:
  NOVA is expected to invent `task_name`/`task_description` for the slot on the spot, do
  the work, then call `complete_d100(roll)`. Populate-me rolls still increment
  `times_rolled`/set `last_rolled` (DQ-1) so the existing `d100_roll_log` trigger and the
  forced-D100 staleness gate (#358) keep working unmodified.
- **`reserved boolean` column on `motivation_d100`** (#444, default `false`) — lets specific
  empty slots opt out of the generative populate-me path (re-roll instead). Migration 084
  reserves 22 of the pre-#444 empty slots.
- **`populated_at timestamptz` column + `trg_set_populated_at` trigger** (#444) —
  auto-stamped by `_trg_set_populated_at()` the first time a slot transitions from
  `task_name IS NULL` to `task_name IS NOT NULL` (INSERT or UPDATE). Not directly writable
  by NOVA (tracking-column protection extends to it). Existing 56 populated slots were
  backfilled to `populated_at = created_at` (NOT NULL — GAP-3 resolution; backfilling NULL
  would have silently defanged completion-rate flagging for all legacy slots).
- **7-day anti-repeat window with dynamic 50%-floor cap for populated-slot rolls** (#444) —
  a populated+enabled roll is accepted if `last_rolled IS NULL`, more than 7 days old, or
  re-admitted by the cap. The cap recomputes every roll: it allows up to
  `floor(total_populated * 0.5)` recently-rolled (≤7d) slots to stay excluded; any excess is
  re-admitted oldest-`last_rolled`-first, statelessly per invocation (DQ-6, cap rounding
  floor per DQ-5). Does not apply to empty-slot draws (DQ-4).
- **`flag_d100_low_completion()`** (#444) — monthly completion-rate audit function. Flags
  populated slots with ≥10 rolls since `populated_at` (time-windowed via `d100_roll_log`
  where `rolled_at >= populated_at`, so pre-population populate-me rolls never inflate the
  denominator — DQ-2) and a completion rate below 60%. The completion side needs no
  `populated_at` filter by construction: `complete_d100()` requires `task_name IS NOT NULL`,
  so every recorded completion is inherently post-population (GAP-1). Disabled populated
  slots remain flag-eligible (DQ-7 — useful retirement signal).
- **Three new populated content slots** (#444, rolls 62–64): Bootstrap token audit,
  Subsystem capability-loss review, Lesson re-validation.
- **Workflow 27 step 11 text updated** (#444) — the D100 step now documents both the
  `is_populate_me = true` (populate-and-execute) and `is_populate_me = false` (normal
  execute) branches with exact SQL for each.
- **`announce-d100-rolls.py` populate-me rendering** (#444) — a roll with `task_name IS
  NULL` now renders as `[ORIGINATION SLOT — populate & execute]` when `reserved = false`
  (a genuine generative-slot roll), distinct from the `task unknown (slot N)` fallback,
  which remains reserved for actual data-integrity errors.

#### Fixed
- **Column-level UPDATE grants for `nova` on `motivation_d100`** (#444) — `reserved`,
  `populated_at`, and the pre-existing tracking columns require explicit column-level
  `GRANT UPDATE` since `nova` operates under column-level privileges, not table-level.
- **`d100_roll_log` privilege correction** (#444, closes remaining gaps from #432) —
  `REVOKE DELETE, INSERT ON TABLE d100_roll_log FROM nova` followed by
  `GRANT SELECT, UPDATE ON TABLE d100_roll_log TO nova` (no `INSERT`: the roll-log trigger
  writes under `roll_d100()`'s own `SECURITY DEFINER` context, not nova's session).
- **Ambiguous `last_rolled`/anti-repeat CTE alias fix** (#444, #453) — the anti-repeat
  eligibility CTE's `roll` output column collided with the outer function's `roll`
  parameter/table-column name inside `roll_d100()`, causing an ambiguous-reference error
  under live PL/pgSQL execution (not caught by mock-based pytest coverage). Aliased the CTE
  column and added a direct-migration-load regression test
  (`motivation/tests/test_roll_d100_migration.py`) that executes `roll_d100()` end-to-end
  against a real database connection (transaction always rolled back) specifically because
  this class of bug is invisible to mocked tests.
- **`agent-install.sh` post-`pgschema`-apply grant reconciliation** (#452) — `pgschema`
  deliberately ignores privilege (GRANT/REVOKE) statements when diffing/applying
  `schema.sql`, so the explicit grants above (and the #448/#449 predecessors) were silently
  lost on fresh installs. The schema-apply step now extracts `GRANT`/`REVOKE` lines from the
  staged schema file after a successful `pgschema apply` and re-applies them via
  `_superuser_psql`, non-fatally logging failure rather than aborting the install.

#### Tests
- `tests/TEST-CASES-ISSUE-444.md` — 74 finalized test cases across 9 sections (schema/
  migration, generative empty slot/reserved semantics, anti-repeat window + dynamic cap,
  `max_attempts` interaction, populate-me interface/contract, `complete_d100()` lifecycle/
  backward-compat, completion-rate flagging, new content slots, adversarial/degenerate
  sweep). Local to `feature/444-d100-refinements`, no PR yet.
- `motivation/tests/test_roll_d100_migration.py` — direct end-to-end `roll_d100()` load-
  and-execute regression test against a real DB connection (the ambiguous-CTE-alias class
  of bug is invisible to mock-based coverage).
- `motivation/tests/test_announce_d100_rolls.py` — extended for populate-me rendering
  (`[ORIGINATION SLOT — populate & execute]` vs. `task unknown (slot N)` fallback) and the
  `reserved` column join.

#### Issues Closed
- #444 — D100 motivation system refinements (generative empty slots, anti-repeat window,
  completion-rate flagging)
- #452 — `agent-install.sh` grant reconciliation after `pgschema apply`
- #453 — Anti-repeat CTE alias / ambiguous `roll` reference in `roll_d100()`

### Batch: turn-context-placement-cache-439 (Issue #439)

#### Added
- **`placement` config option for the turn-context plugin's dynamic context block** (#439) — `memory/plugins/turn-context/openclaw.plugin.json` gains a `configSchema.placement` enum (`system-prepend` default | `turn-prepend`). `system-prepend` preserves the pre-existing behavior (dynamic entity/domain/recall block returned as `prependSystemContext`, ahead of the base system prompt — no behavior change for instances that don't set this option). `turn-prepend` instead returns the same block as `prependContext`, adjacent to the current user turn, so the (comparatively static) base system prompt is no longer preceded by a per-turn-varying block — preserving prompt-cache hits on the system-prompt prefix across turns. Turn reminders and the honorific guard are unaffected by this setting and always land in `appendSystemContext`. New pure helpers `resolvePlacement()` (defaults unknown/malformed values to `system-prepend` rather than throwing) and `buildPromptResult()` in `memory/plugins/turn-context/src/index.ts`, covered by 12 new unit tests in `src/index.test.ts` (TC-439-001–012). Full option documentation: `memory/plugins/turn-context/README.md#placement`.
- **`scripts/measure-turn-cache-impact.py`** (#439) — Compares prompt-cache metrics (cache-read/write token counts, cache-hit ratio, steady-state cacheWrite/turn) between a baseline and an experiment OpenClaw session JSONL log, to quantify the effect of switching `placement` above. Supports a single-session mode (`python3 scripts/measure-turn-cache-impact.py <session.jsonl>`) and a before/after comparison mode (`--before baseline.jsonl --after experiment.jsonl`, optionally with `--turn-context-log <log>` to parse the plugin's own `prepend=<N>chars` log lines). Checks three acceptance criteria: AC-1 (steady-state cacheWrite/turn drops ≥80%), AC-2 (cache-hit ratio improves ≥15 percentage points, or reaches ≥90% from turn 3 on), and AC-3 (the measured cacheWrite/turn drop, in tokens, is within ±10% of the dynamic prepend block's char count converted to an estimated token count via a `chars ÷ 4` English-text heuristic — `CHARS_PER_TOKEN_ESTIMATE = 4`). This AC-3 check is a coarse sanity check, not an exact token count: actual tokenization varies by model and language mix, so use it to catch gross mismatches (e.g. cacheWrite dropping because the block was shrunk rather than moved), not as a precise token accounting tool. Installer wiring for this script is tracked separately and out of scope here — see #445. Usage documentation: `memory/plugins/turn-context/README.md#placement`.

#### Tests
- `memory/plugins/turn-context/src/index.test.ts` (#439) — 12 new unit tests (TC-439-001–012) covering `buildPromptResult()` placement routing (dynamic block to `prependSystemContext` vs `prependContext`, append segments unaffected, empty-segment omission) and `resolvePlacement()` fallback behavior (undefined config, empty object, unknown string, non-string value, both valid values).
- `tests/test_measure_turn_cache_impact.py` (#439) — New suite covering `estimate_tokens_from_chars()` (rounding, zero, heuristic-constant guard), `compare_metrics()` AC-3 behavior (matched/mismatched/missing-log/zero-size), `parse_prepend_block_size()` (plain-log parsing, missing file, non-matching log), and CLI smoke tests against fixture files in `tests/fixtures/measure_turn_cache/` (`baseline.jsonl`, `experiment.jsonl`, `turn-context-matched.log`, `turn-context-mismatched.log`).

#### Issues Closed
- #439 — Turn-context prompt-cache optimization: configurable placement for the dynamic context block + measurement script
