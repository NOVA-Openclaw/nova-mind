#!/usr/bin/env python3
"""
Deterministic completion-side daily-log reconcile.

Scans work_queue and workflow_runs for rows that have reached a terminal status
but have not yet had their completion line appended to the daily log, appends
exactly one line per row, and watermarks the row.

The script is LLM-free and is intended to run from cron every few minutes.
"""

from __future__ import annotations

import argparse
import fcntl
import getpass
import json
import os
import re
import sys
import tempfile
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import psycopg2

WORK_QUEUE_TERMINAL_STATUSES = ("done", "failed", "stale", "cancelled")
WORKFLOW_RUNS_TERMINAL_STATUSES = ("completed", "failed", "cancelled")

DESCRIPTION_MAX_LEN = 120
TRIGGER_CONTEXT_MAX_LEN = 80

# Marker templates used for the two-phase grep pre-check.  A word boundary is
# required after the numeric id so that "#1" cannot match inside "#10".
WORK_QUEUE_MARKER = "wq#{id} closed"
WORKFLOW_RUNS_MARKER = "workflow run #{id}"


def _marker_pattern(marker_template: str, row_id: int) -> str:
    """Return a regex pattern that matches the marker for a specific id.

    A \\b word boundary is inserted immediately after the formatted digits so
    that a shorter id cannot match as a prefix of a longer id (e.g. #1 inside
    #10).
    """
    return marker_template.format(id=f"{row_id}\\b")


class ReconcileError(Exception):
    """Recoverable error that should produce a clean, cron-parseable message."""

    def __init__(self, message: str, exit_code: int = 1) -> None:
        super().__init__(message)
        self.message = message
        self.exit_code = exit_code


def resolve_workspace() -> Path:
    """Resolve workspace directory per multi-tenant fallback chain.

    Resolution order:
      1. $OPENCLAW_WORKSPACE
      2. ~/.openclaw/workspace-$OPENCLAW_AGENT_ID (only when OPENCLAW_AGENT_ID is set)
      3. ~/.openclaw/workspace
    """
    candidates: list[str] = []
    if "OPENCLAW_WORKSPACE" in os.environ:
        candidates.append(os.environ["OPENCLAW_WORKSPACE"])
    home = os.path.expanduser("~")
    agent_id = os.environ.get("OPENCLAW_AGENT_ID")
    if agent_id:
        candidates.append(os.path.join(home, ".openclaw", f"workspace-{agent_id}"))
    candidates.append(os.path.join(home, ".openclaw", "workspace"))

    for candidate in candidates:
        path = Path(candidate).resolve()
        if path.is_dir():
            return path

    tried = ", ".join(f"'{c}'" for c in candidates)
    raise ReconcileError(f"No workspace directory found. Tried: {tried}")


def load_postgres_config() -> dict[str, str | int]:
    """Read host/port/database from postgres.json; never consume password fields."""
    config_path = Path.home() / ".openclaw" / "postgres.json"
    if not config_path.is_file():
        raise ReconcileError(f"PostgreSQL config not found: {config_path}")
    try:
        with config_path.open("r", encoding="utf-8") as f:
            raw = json.load(f)
    except json.JSONDecodeError as exc:
        raise ReconcileError(f"Invalid JSON in {config_path}: {exc}") from exc

    if not isinstance(raw, dict):
        raise ReconcileError(f"Unexpected config shape in {config_path}")

    try:
        return {
            "host": str(raw["host"]),
            "port": int(raw["port"]),
            "database": str(raw["database"]),
        }
    except (KeyError, TypeError, ValueError) as exc:
        raise ReconcileError(
            f"postgres.json missing required host/port/database key: {exc}"
        ) from exc


def connect(dbname: str, pg_config: dict[str, str | int]) -> psycopg2.extensions.connection:
    """Connect to a PostgreSQL database honoring .pgpass and dropping PGPASSWORD."""
    os.environ.pop("PGPASSWORD", None)

    env = os.environ.copy()
    env["PGHOST"] = str(pg_config["host"])
    env["PGPORT"] = str(pg_config["port"])
    env["PGDATABASE"] = dbname
    env["PGUSER"] = env.get("PGUSER", getpass.getuser())
    env.pop("PGPASSWORD", None)

    try:
        return psycopg2.connect(
            host=env["PGHOST"],
            port=env["PGPORT"],
            database=env["PGDATABASE"],
            user=env["PGUSER"],
        )
    except psycopg2.Error as exc:
        raise ReconcileError(
            f"Database connection failed for '{dbname}': {exc}"
        ) from exc


def sanitize(text: str | None, max_len: int | None = None) -> str:
    """Collapse whitespace runs and optionally truncate with an ellipsis."""
    if text is None:
        text = ""
    # Collapse all whitespace runs (incl. newlines/tabs) to a single space.
    cleaned = re.sub(r"\s+", " ", text).strip()
    if max_len is not None and len(cleaned) > max_len:
        cleaned = cleaned[:max_len] + "…"
    return cleaned


def effective_watermark(
    row: dict[str, Any], table: str
) -> tuple[datetime, bool]:
    """Return the effective completion timestamp for a row and whether it is usable.

    work_queue: COALESCE(completed_at, last_checked_at, created_at)
    workflow_runs: COALESCE(completed_at, started_at)

    Returns (timestamp, usable). If unusable, a warning has been emitted to stderr.
    """
    if table == "work_queue":
        ts = row.get("completed_at") or row.get("last_checked_at") or row.get("created_at")
        if ts is None:
            print(
                f"[completion-log-reconcile] WARNING: skipping {table} id={row['id']} "
                "(completed_at, last_checked_at, and created_at are all NULL)",
                file=sys.stderr,
            )
            return datetime.now(timezone.utc), False
    elif table == "workflow_runs":
        # started_at is NOT NULL on this table, so this is always usable.
        ts = row.get("completed_at") or row.get("started_at")
        if ts is None:
            print(
                f"[completion-log-reconcile] WARNING: skipping {table} id={row['id']} "
                "(completed_at and started_at are both NULL)",
                file=sys.stderr,
            )
            return datetime.now(timezone.utc), False
    else:
        raise ReconcileError(f"Unknown table: {table}")

    if isinstance(ts, str):
        ts = datetime.fromisoformat(ts)
    return ts, True


def format_work_queue_line(row: dict[str, Any], ts: datetime) -> str:
    """Render a work_queue completion line."""
    time_str = ts.strftime("%H:%M")
    kind = sanitize(row.get("kind"), max_len=None) or "unknown"
    description = sanitize(row.get("description"), DESCRIPTION_MAX_LEN) or "(no description)"
    status = sanitize(row.get("status"), max_len=None) or "unknown"
    return f"- {time_str} wq#{row['id']} closed ({kind}): {description} — {status}"


def format_workflow_runs_line(row: dict[str, Any], ts: datetime) -> str:
    """Render a workflow_runs completion line."""
    time_str = ts.strftime("%H:%M")
    workflow_id = row.get("workflow_id") or "unknown"
    status = sanitize(row.get("status"), max_len=None) or "unknown"
    trigger_context = sanitize(row.get("trigger_context"), TRIGGER_CONTEXT_MAX_LEN) or "(no context)"
    return (
        f"- {time_str} workflow run #{row['id']} {status} "
        f"(workflow {workflow_id}): {trigger_context}"
    )


def daily_log_path(workspace: Path, ts: datetime) -> Path:
    """Return the YYYY-MM-DD.md path for a UTC timestamp."""
    memory_dir = workspace / "memory"
    return memory_dir / f"{ts.date().isoformat()}.md"


def adjacent_log_paths(workspace: Path, ts: datetime) -> list[Path]:
    """Return the target date file plus the previous and next day's files."""
    memory_dir = workspace / "memory"
    base = ts.date()
    return [
        memory_dir / f"{(base - timedelta(days=1)).isoformat()}.md",
        memory_dir / f"{base.isoformat()}.md",
        memory_dir / f"{(base + timedelta(days=1)).isoformat()}.md",
    ]


def marker_present(marker_pattern: str, paths: list[Path]) -> bool:
    """Grep the candidate files for a marker regex pattern."""
    compiled = re.compile(marker_pattern)
    for path in paths:
        if not path.is_file():
            continue
        try:
            with path.open("r", encoding="utf-8") as f:
                for line in f:
                    if compiled.search(line):
                        return True
        except OSError:
            continue
    return False


def append_line(path: Path, line: str) -> None:
    """Atomically append a single line to a daily log file.

    Creates the file (with a title line) and parent directories if needed.
    """
    path.parent.mkdir(parents=True, exist_ok=True)

    needs_title = not path.exists() or path.stat().st_size == 0
    temp_fd, temp_path = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    temp_file = Path(temp_path)
    try:
        if needs_title:
            content = f"# {path.stem}\n\n{line}\n"
        else:
            original = path.read_text(encoding="utf-8")
            if original.endswith("\n"):
                content = original + line + "\n"
            else:
                content = original + "\n" + line + "\n"

        with os.fdopen(temp_fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, path)
    except Exception:
        try:
            os.close(temp_fd)
        except OSError:
            pass
        if temp_file.exists():
            temp_file.unlink()
        raise


@contextmanager
def daily_log_lock(workspace: Path):
    """Acquire an exclusive advisory flock on the shared daily-log lock file."""
    lock_file = workspace / "memory" / ".daily-log.lock"
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock_file), os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def fetch_eligible_rows(
    conn: psycopg2.extensions.connection,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Return terminal-status rows from both tables that need logging."""
    work_queue_rows: list[dict[str, Any]] = []
    workflow_runs_rows: list[dict[str, Any]] = []

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, kind, description, status,
                   completed_at, last_checked_at, created_at
              FROM work_queue
             WHERE status IN %s
               AND completion_logged_at IS NULL
             ORDER BY COALESCE(completed_at, last_checked_at, created_at)
            """,
            (WORK_QUEUE_TERMINAL_STATUSES,),
        )
        columns = [desc[0] for desc in cur.description]
        work_queue_rows = [dict(zip(columns, row)) for row in cur.fetchall()]

        cur.execute(
            """
            SELECT id, workflow_id, trigger_context, status,
                   completed_at, started_at
              FROM workflow_runs
             WHERE status IN %s
               AND completion_logged_at IS NULL
             ORDER BY COALESCE(completed_at, started_at)
            """,
            (WORKFLOW_RUNS_TERMINAL_STATUSES,),
        )
        columns = [desc[0] for desc in cur.description]
        workflow_runs_rows = [dict(zip(columns, row)) for row in cur.fetchall()]

    return work_queue_rows, workflow_runs_rows


def _prepare_items(
    work_queue_rows: list[dict[str, Any]],
    workflow_runs_rows: list[dict[str, Any]],
) -> list[tuple[datetime, str, dict[str, Any]]]:
    """Tag rows with their table, resolve watermarks, and sort chronologically."""
    items: list[tuple[datetime, str, dict[str, Any]]] = []
    for row in work_queue_rows:
        ts, usable = effective_watermark(row, "work_queue")
        if usable:
            items.append((ts, "work_queue", row))
    for row in workflow_runs_rows:
        ts, usable = effective_watermark(row, "workflow_runs")
        if usable:
            items.append((ts, "workflow_runs", row))
    items.sort(key=lambda item: item[0])
    return items


def reconcile(
    pg_config: dict[str, str | int],
    database_name: str | None,
    workspace: Path,
    dry_run: bool,
) -> int:
    """Run the reconcile pass. Returns the number of lines appended."""
    dbname = database_name or str(pg_config["database"])
    conn = connect(dbname, pg_config)
    conn.autocommit = True

    try:
        with daily_log_lock(workspace):
            work_queue_rows, workflow_runs_rows = fetch_eligible_rows(conn)
            items = _prepare_items(work_queue_rows, workflow_runs_rows)

            if not items:
                return 0

            appended = 0
            for ts, table, row in items:
                if table == "work_queue":
                    marker_template = WORK_QUEUE_MARKER
                    format_line = format_work_queue_line
                    update_sql = "UPDATE work_queue SET completion_logged_at = now() WHERE id = %s"
                else:
                    marker_template = WORKFLOW_RUNS_MARKER
                    format_line = format_workflow_runs_line
                    update_sql = "UPDATE workflow_runs SET completion_logged_at = now() WHERE id = %s"

                candidate_paths = adjacent_log_paths(workspace, ts)
                marker = _marker_pattern(marker_template, row["id"])

                if marker_present(marker, candidate_paths):
                    # Line already exists; just watermark.
                    if not dry_run:
                        with conn.cursor() as cur:
                            cur.execute(update_sql, (row["id"],))
                    continue

                line = format_line(row, ts)
                if not dry_run:
                    append_line(daily_log_path(workspace, ts), line)
                    with conn.cursor() as cur:
                        cur.execute(update_sql, (row["id"],))
                appended += 1

            return appended
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Reconcile closed work_queue and workflow_runs rows into the daily log."
    )
    parser.add_argument(
        "--database",
        type=str,
        default=None,
        help="Override the database name (default from postgres.json).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be appended without writing files or updating the DB.",
    )

    args = parser.parse_args(argv)

    try:
        workspace = resolve_workspace()
        pg_config = load_postgres_config()
        appended = reconcile(pg_config, args.database, workspace, args.dry_run)
    except ReconcileError as exc:
        print(f"[completion-log-reconcile] ERROR: {exc.message}", file=sys.stderr)
        return exc.exit_code
    except OSError as exc:
        print(
            f"[completion-log-reconcile] ERROR: failed to write daily log: {exc}",
            file=sys.stderr,
        )
        return 1
    except psycopg2.Error as exc:
        print(
            f"[completion-log-reconcile] ERROR: database operation failed: {exc}",
            file=sys.stderr,
        )
        return 1

    print(
        f"[completion-log-reconcile] Appended {appended} line(s)"
        + (" (dry run)" if args.dry_run else "")
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
