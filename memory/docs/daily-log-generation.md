# Daily Log Generation

## Overview

Two LLM-free, cron-driven scripts cooperate to keep the daily memory log
(`memory/YYYY-MM-DD.md`) current, both installed by `agent-install.sh`:

- **`memory/scripts/generate-daily-log.py`** generates and updates the
  current day's log from live database state. It writes into a delimited
  **generated block** at the top of the file, marked by HTML comments, and
  never touches any agent-written narrative outside that block.
- **`memory/scripts/completion-log-reconcile.py`** (nova-mind#561) appends
  one-line completion entries for closed `work_queue` rows and completed
  `workflow_runs` rows, dated to the day the row actually completed. See
  [Completion Log Reconcile](#completion-log-reconcile-nova-mind561) below.

Both scripts write to the same file and share an advisory `flock` to avoid
clobbering each other's writes (see
[Shared Lock With completion-log-reconcile.py](#shared-lock-with-completion-log-reconcilepy)).

Before `generate-daily-log.py` existed (see nova-mind#397), daily logs were purely
hand-written scratch notes (see `memory/ARCHITECTURE.md` — "Daily Notes"). As
of #397, each day's file additionally carries an auto-generated system
summary — agents (and humans) still write freeform narrative in the same
file, above or below the generated block.

## Usage

```bash
# Generate/update today's log (UTC date)
python3 memory/scripts/generate-daily-log.py

# Backfill a past date
python3 memory/scripts/generate-daily-log.py --date 2026-07-01

# Preview without writing to disk
python3 memory/scripts/generate-daily-log.py --dry-run

# Preview a specific past date without writing
python3 memory/scripts/generate-daily-log.py --date 2026-07-01 --dry-run
```

Once installed via `agent-install.sh`, the script also runs unattended from
cron (see [Cron Schedule](#cron-schedule-and-management) below) writing to
`~/.openclaw/logs/generate-daily-log.log`.

### Flags

| Flag | Description |
|------|--------------|
| `--date YYYY-MM-DD` | Target date to generate/update. Must be today or a past date (UTC) — **future dates are rejected** with exit code 2. Defaults to today (UTC) if omitted. Use this for backfilling gap days (see [Backfill Runbook](#backfill-runbook-for-gap-days)). |
| `--dry-run` | Print the generated block to stdout without writing to disk. No file is created or modified, even if the target file doesn't exist yet. |

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success. Either the file was written/updated, or no changes were needed (true no-op — see [Idempotency](#idempotency)). |
| `1` | Hard failure — database connection error, missing/malformed `~/.openclaw/postgres.json`, or corrupted generated-block markers in the target file (see [Marker Contract](#marker-contract)). **No partial writes occur on failure** — the target file is left exactly as it was found. |
| `2` | Usage error — invalid `--date` value (malformed format, or a future date). |

## Marker Contract

The generated block is delimited by two HTML comment markers:

```markdown
<!-- BEGIN GENERATED DAILY LOG — source: generate-daily-log.py — generated_at: 2026-07-05T05:00:12Z -->
<!-- Do not edit between these markers; content is regenerated automatically. -->

## System summary (auto-generated)

### Agent chat activity
...

<!-- END GENERATED DAILY LOG -->
```

**What agents (and humans) may do:**
- Write freeform narrative anywhere **above** the BEGIN marker or **below** the END marker in the same file. This content is preserved byte-for-byte across every regeneration, including exact whitespace, non-ASCII characters, and trailing newline conventions.
- Leave the file with no markers at all (e.g., a brand-new hand-written daily note). The next script run will **append** the generated block after existing content rather than overwriting it.

**What agents (and humans) must NOT do:**
- Edit content **between** the BEGIN and END markers. It is regenerated wholesale on every run and any manual edits there will be silently discarded on the next run.
- Manually duplicate, remove just one of, or reorder the marker pair. The script requires **exactly one** BEGIN and **exactly one** END marker, with BEGIN appearing before END. Any other arrangement (zero of one but not the other, more than one pair, or END before BEGIN) is treated as **marker corruption** — the script exits 1 with a diagnostic message identifying the offending line numbers, and makes no write. Fix the file by hand before re-running.

## Generated Sections

The block currently renders these sections, each queried fresh from the database for the target date (UTC day window):

- **Agent chat activity** — total message count + top-5 senders by message count, from the `agent_chat` database.
- **Workflow runs** — total count + up to 10 most recent `workflow_runs` rows (id, workflow, status, started_at).
- **Lessons learned** — total count + up to 10 most recent `lessons` rows.
- **Events logged** — total count + up to 10 most recent `events` rows.
- **Tasks** — created/completed/blocked-update counts + up to 10 most recently created `tasks` rows.
- **Key cron results** — static placeholder for v1: *"Cron results: not yet tracked — see nova-mind#397"*. Actual cron-run outcome tracking was descoped from v1 scope; do not treat this line as real data.

## Workspace Resolution

The script resolves the target workspace directory (where `memory/YYYY-MM-DD.md` lives) using this fallback chain, first match wins:

1. **`$OPENCLAW_WORKSPACE`** — if set, used as-is (must be an existing directory).
2. **`~/.openclaw/workspace-$OPENCLAW_AGENT_ID`** — only checked when `OPENCLAW_AGENT_ID` is set in the environment. This supports multi-agent hosts where each agent has its own workspace directory.
3. **`~/.openclaw/workspace`** — the default single-agent workspace path.

If none of the applicable candidates exist as a directory, the script exits 1 listing every path it tried.

## Idempotency

Re-running the script for a date where nothing in the database has changed since the last run produces **no write at all** — not just "same content written again." The script compares the newly generated block against the existing block (ignoring only the `generated_at` timestamp line) before deciding whether to touch the file. If they match, the file's `mtime` is left untouched and no disk I/O occurs.

This matters for the cron schedule: the intraday runs (see below) are expected to be no-ops most of the time, only producing a real write when something changed since the last run (new agent_chat messages, workflow runs, lessons, events, or tasks that day).

## Credential Model

- The script never reads a database password from anywhere in its own config or environment handling — it reads only `host`, `port`, and `database` from `~/.openclaw/postgres.json`.
- Authentication happens exclusively via `.pgpass` (standard PostgreSQL client behavior), consistent with the rest of nova-mind's per-agent credential model (see `GLOBAL/DATABASE_ACCESS`).
- Before connecting, the script explicitly pops `PGPASSWORD` from its own environment (`os.environ.pop("PGPASSWORD", None)`) so a gateway-inherited `PGPASSWORD` cannot silently override `.pgpass` and cause an auth mismatch. This is the same class of fix as the Hermes `PGPASSWORD` incident (see `GLOBAL/DATABASE_ACCESS`) and is covered by a dedicated regression test (`TestPGPASSWORDRegression` in `tests/test_generate_daily_log.py`).
- The script connects to **two** databases per run: the memory database named in `postgres.json` (`database` field) for workflow_runs/lessons/events/tasks, and the separate `agent_chat` database (hardcoded name, per the #320 dedicated-database migration) for agent chat activity. Both connections share the same host/port and rely on `.pgpass` for their respective credentials.
- **PGUSER resolution under cron** (nova-mind#564): `connect()` resolves the connecting user with `env.get("PGUSER", getpass.getuser())` — i.e. an explicitly-set `PGUSER` wins, otherwise fall back to `getpass.getuser()`. `getpass.getuser()` checks `LOGNAME`, `USER`, `LNAME`, `USERNAME` (in that order, first non-empty wins) before falling back to `pwd.getpwuid(os.getuid())`. This matters because **Debian cron does not set `USER`** (only `HOME`/`LOGNAME`/`SHELL`/`PATH`) — an earlier version of this fallback used `os.environ.get("USER", str(os.getuid()))`, which under cron resolved to the literal numeric UID string (e.g. `"1005"`), matched no database role or `.pgpass` entry, and failed every cron invocation with `fe_sendauth: no password supplied`. `generate-daily-log.py`'s `connect()` uses the identical fallback. Regression coverage: `TestConnectUserResolution` in `tests/test_completion_log_reconcile.py` unsets all four identity env vars and asserts the resolved user is a username string, not a numeric UID, for both scripts' `connect()` functions.

## Completion Log Reconcile (nova-mind#561)

`memory/scripts/completion-log-reconcile.py` is a separate, LLM-free script that appends completion-side entries to the daily log for rows that reached a terminal status in `work_queue` or `workflow_runs`. It exists because `generate-daily-log.py`'s periodic snapshot queries can miss short-lived rows that opened and closed between two cron runs — reconcile guarantees every closed row eventually produces exactly one line, regardless of timing.

### What it does

On each run, the script:

1. Queries `work_queue` for rows with `status IN ('done', 'failed', 'stale', 'cancelled')` and `completion_logged_at IS NULL`.
2. Queries `workflow_runs` for rows with `status IN ('completed', 'failed', 'cancelled')` and `completion_logged_at IS NULL`.
3. For each eligible row, resolves an effective completion timestamp (see **Watermark fallback** below), sorts all rows chronologically across both tables, and appends one line per row to the `memory/YYYY-MM-DD.md` file matching that row's completion date (UTC) — not the date the reconcile script happened to run.
4. Sets `completion_logged_at = now()` on the row immediately after a successful append, so the row is never logged twice.

### Line formats

- `work_queue`: `- HH:MM wq#<id> closed (<kind>): <description> — <status>`
- `workflow_runs`: `- HH:MM workflow run #<id> <status> (workflow <workflow_id>): <trigger_context>`

Descriptions and trigger_context have all whitespace runs (including newlines) collapsed to single spaces; `description` is truncated to 120 chars and `trigger_context` to ~80 chars, each with a trailing `…` when truncated. No Markdown escaping is applied.

### Watermark fallback

- `work_queue`: `COALESCE(completed_at, last_checked_at, created_at)`. If all three are NULL (structurally unreachable via normal inserts, since `created_at` is `NOT NULL DEFAULT now()`), the row is skipped with a stderr warning rather than crashing.
- `workflow_runs`: `COALESCE(completed_at, started_at)`. `started_at` is `NOT NULL`, so this is always usable.

### Idempotency and crash recovery

The script uses a two-phase append: (1) a file-grep pre-check across the target day's file plus the adjacent day's files (guards against timestamp-driven off-by-one dating at midnight boundaries) for a marker matching `wq#<id> closed` or `workflow run #<id>`, with a word-boundary anchor immediately after the numeric id so a shorter id cannot false-match inside a longer one (e.g. `#1` does not match inside `#10`); (2) if no marker is found, append the line; (3) set `completion_logged_at` only **after** a successful append. If the script crashes between steps (2) and (3), the next run's pre-check in step (1) finds the already-appended line and skips straight to watermarking — the residual cost is at most one redundant grep, never a duplicate line.

### Invocation

```bash
# Reconcile pass against the default database (from postgres.json)
python3 memory/scripts/completion-log-reconcile.py

# Preview without writing files or updating the DB
python3 memory/scripts/completion-log-reconcile.py --dry-run

# Override the target database name
python3 memory/scripts/completion-log-reconcile.py --database nova_staging_memory
```

Installed via `agent-install.sh` to `~/.openclaw/scripts/completion-log-reconcile.py`, run from cron every 5 minutes (see [Cron Schedule and Management](#cron-schedule-and-management)), output appended to `~/.openclaw/logs/completion-log-reconcile.log`.

### Migration

`memory/migrations/087_completion_log_watermark.sql` adds `completion_logged_at timestamptz` to both `work_queue` and `workflow_runs`, and seeds the column for all already-closed rows at deploy time via `COALESCE(completed_at, now())` guarded by `WHERE completion_logged_at IS NULL`. Because the seed guard only checks for NULL (not a deploy-time snapshot), **re-applying this migration against a live system will also seed any row that became terminal between the two applies**, permanently excluding it from reconcile's scan. Drain pending closures with `completion-log-reconcile.py` before re-applying migration 087 against a live system.

### Shared lock with generate-daily-log.py

`completion-log-reconcile.py` and `generate-daily-log.py` both acquire an exclusive advisory `flock` (`fcntl.flock`, `LOCK_EX`) on `memory/.daily-log.lock` around their respective read/write/rename critical sections before touching a `YYYY-MM-DD.md` file. This prevents one script's write from clobbering the other's if a 5-minute reconcile tick and a nightly/intraday `generate-daily-log.py` run land close together. Neither script depends on the other's presence — the lock file is created on first use by whichever script runs first. Verified by `TestFlockMutualExclusion` in `tests/test_completion_log_reconcile.py` (both `test_reconcile_blocks_when_lock_held` and `test_generate_daily_log_takes_same_lock`).

## Cron Schedule and Management

`agent-install.sh` installs cron entries for both scripts by default:

| Script | Schedule | Cron expression | Purpose |
|--------|----------|------------------|---------|
| `generate-daily-log.py` | Nightly | `5 0 * * *` | Generates the previous/current day's log shortly after midnight UTC. |
| `generate-daily-log.py` | Intraday | `0 6,12,18 * * *` | Refreshes the current day's log three times during the day so it stays reasonably current before the nightly run. |
| `completion-log-reconcile.py` | Every 5 minutes | `*/5 * * * *` | Appends completion lines for closed `work_queue`/`workflow_runs` rows shortly after they close, independent of the snapshot-driven `generate-daily-log.py` schedule. |

All entries invoke the installed script under `~/.openclaw/scripts/` and redirect output to a dedicated log under `~/.openclaw/logs/` (`generate-daily-log.log` and `completion-log-reconcile.log` respectively).

### Opting out: `--no-cron`

```bash
./agent-install.sh --no-cron
```

Skips cron installation entirely for this run, for **all** cron-installed scripts including both `generate-daily-log.py` and `completion-log-reconcile.py`. Use this if you manage the schedule yourself (e.g., a different scheduler, or you don't want scripts running automatically on this host).

### Drift detection

If a crontab entry already references a script path but with a **different** schedule than expected, the installer treats this as **drift**: it prints a warning and leaves the crontab untouched. The installer never overwrites or "fixes" a drifted entry automatically — resolve drift by hand (edit `crontab -e` to match the expected schedule, or remove the conflicting line and re-run the installer). This applies identically to `generate-daily-log.py` and `completion-log-reconcile.py`.

### Checking installation status: `--verify-only`

```bash
./agent-install.sh --verify-only
```

Reports cron status for both scripts without modifying the crontab in any way:

- **installed** — the expected entry (or entries) are present.
- **missing** — no entry referencing the script path exists.
- **drift detected (review required)** — an entry references the script path but doesn't match the expected schedule.

### Deduplication

Re-running `agent-install.sh` (without `--verify-only`) is safe: the installer checks for each script's path in the existing crontab before appending, so re-installs do not create duplicate cron lines.

## Backfill Runbook for Gap Days

If daily logs are missing for one or more past dates (e.g., cron was down, the host was offline, or the feature was installed after those dates already passed), backfill them one date at a time:

```bash
# 1. Identify the gap — list existing daily logs and spot missing dates
ls memory/ | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' | sort

# 2. For each missing date, dry-run first to confirm the query results look sane
python3 memory/scripts/generate-daily-log.py --date 2026-07-01 --dry-run

# 3. Run for real once the dry-run output looks correct
python3 memory/scripts/generate-daily-log.py --date 2026-07-01

# 4. Repeat for each additional gap date
python3 memory/scripts/generate-daily-log.py --date 2026-07-02
```

Notes:
- `--date` only accepts **past** dates (or today) — you cannot pre-generate a future day's log.
- If a gap date's file already exists with hand-written narrative and no markers, the generated block is **appended** after existing content, not merged into it — the existing narrative is fully preserved.
- If a gap date's file already has a (possibly stale) generated block from a partial/earlier run, re-running replaces just that block; narrative outside it is untouched.
- Backfilling is safe to re-run — the same idempotency guarantee applies to `--date` runs as to default (today) runs.

## Tests

- `tests/test_generate_daily_log.py` — 32 unit/integration tests covering date validation, workspace resolution, postgres.json loading, PGPASSWORD hygiene, marker parsing, block comparison, file update (create/append/replace/preserve), atomic-write failure handling, and live-DB integration paths (dry-run, happy path, idempotent re-run).
- `tests/test_completion_log_reconcile.py` — 64 tests covering line formatting, sanitization, watermark fallback, idempotency, crash recovery, midnight-boundary dating, status decision tables, migration idempotency, failure modes (permission errors, unreachable DB, DB permission-denied), the numeric-prefix marker-collision regression for both tables, `TestConnectUserResolution` (cron-env PGUSER regression for both scripts' `connect()`), and `TestFlockMutualExclusion` (shared-lock contention with `generate-daily-log.py`).
- `tests/install/test_generate_daily_log_cron.bats` — cron installation/verification/drift/opt-out coverage for `agent-install.sh`'s `_install_daily_log_cron()` helper. There is no equivalent `.bats` suite yet for `_install_completion_log_reconcile_cron()` (nova-mind#562's crontab wiring); that installer helper was verified manually on staging (crontab exact-match, artifact present/executable, idempotency, `--no-cron` guard — see nova-mind#562/#564 issue comments) rather than by an automated bats suite.
- `pytest.ini` — new at repo root; configures the `integration` marker used by the live-DB test classes above.
