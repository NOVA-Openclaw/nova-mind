#!/usr/bin/env python3
"""
Generate or update the daily memory log markdown file.

Creates/updates $OPENCLAW_WORKSPACE/memory/<YYYY-MM-DD>.md with an auto-generated
block delimited by HTML comments. Preserves agent narrative outside the markers.

Usage:
    generate-daily-log.py [--date YYYY-MM-DD] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterable

import psycopg2


BEGIN_MARKER_PREFIX = "<!-- BEGIN GENERATED DAILY LOG"
END_MARKER = "<!-- END GENERATED DAILY LOG -->"
CRON_PLACEHOLDER = "Cron results: not yet tracked — see nova-mind#397"


class DailyLogError(Exception):
    """Recoverable error that should produce a clean cron-parseable message."""

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
    raise DailyLogError(f"No workspace directory found. Tried: {tried}")


def load_postgres_config() -> dict[str, str | int]:
    """Read host/port/database from postgres.json; never consume password fields."""
    config_path = Path.home() / ".openclaw" / "postgres.json"
    if not config_path.is_file():
        raise DailyLogError(f"PostgreSQL config not found: {config_path}")
    try:
        with config_path.open("r", encoding="utf-8") as f:
            raw = json.load(f)
    except json.JSONDecodeError as exc:
        raise DailyLogError(f"Invalid JSON in {config_path}: {exc}") from exc

    if not isinstance(raw, dict):
        raise DailyLogError(f"Unexpected config shape in {config_path}")

    try:
        return {
            "host": str(raw["host"]),
            "port": int(raw["port"]),
            "database": str(raw["database"]),
        }
    except (KeyError, TypeError, ValueError) as exc:
        raise DailyLogError(
            f"postgres.json missing required host/port/database key: {exc}"
        ) from exc


def connect(dbname: str, pg_config: dict[str, str | int]) -> psycopg2.extensions.connection:
    """Connect to a PostgreSQL database honoring .pgpass and dropping PGPASSWORD."""
    # Prevent gateway-inherited PGPASSWORD from overriding .pgpass (Hermes incident).
    os.environ.pop("PGPASSWORD", None)

    env = os.environ.copy()
    env["PGHOST"] = str(pg_config["host"])
    env["PGPORT"] = str(pg_config["port"])
    env["PGDATABASE"] = dbname
    env["PGUSER"] = env.get("PGUSER", os.environ.get("USER", str(os.getuid())))
    # Ensure PGPASSWORD is absent from the connection environment as well.
    env.pop("PGPASSWORD", None)

    try:
        return psycopg2.connect(
            host=env["PGHOST"],
            port=env["PGPORT"],
            database=env["PGDATABASE"],
            user=env["PGUSER"],
        )
    except psycopg2.Error as exc:
        raise DailyLogError(
            f"Database connection failed for '{dbname}': {exc}"
        ) from exc


_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def validate_date(value: str) -> date:
    """Parse and validate an exact YYYY-MM-DD date string; reject future dates."""
    if not _DATE_RE.match(value):
        raise argparse.ArgumentTypeError(
            f"Invalid date '{value}'. Expected YYYY-MM-DD."
        )
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"Invalid date '{value}'. Expected YYYY-MM-DD."
        ) from exc

    if parsed > datetime.now(timezone.utc).date():
        raise argparse.ArgumentTypeError(
            f"Future date '{value}' is not allowed."
        )
    return parsed


def day_window_aware(target_date: date) -> tuple[datetime, datetime]:
    """Return UTC-aware start/end datetimes for timestamp-with-time-zone columns."""
    start = datetime(target_date.year, target_date.month, target_date.day, tzinfo=timezone.utc)
    end = datetime.fromtimestamp(start.timestamp() + 86400, tz=timezone.utc)
    return start, end


def day_window_naive(target_date: date) -> tuple[datetime, datetime]:
    """Return naive UTC start/end datetimes for timestamp-without-time-zone columns."""
    start = datetime(target_date.year, target_date.month, target_date.day)
    end = datetime.fromtimestamp(
        datetime(target_date.year, target_date.month, target_date.day, tzinfo=timezone.utc).timestamp() + 86400
    )
    return start, end


def query_agent_chat(target_date: date, conn: psycopg2.extensions.connection) -> dict:
    """Top-5 senders by message count + total messages for the day."""
    start, end = day_window_aware(target_date)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COUNT(*) AS total
            FROM agent_chat
            WHERE timestamp >= %s AND timestamp < %s
            """,
            (start, end),
        )
        total = cur.fetchone()[0]

        cur.execute(
            """
            SELECT sender, COUNT(*) AS cnt
            FROM agent_chat
            WHERE timestamp >= %s AND timestamp < %s
            GROUP BY sender
            ORDER BY cnt DESC, sender ASC
            LIMIT 5
            """,
            (start, end),
        )
        top_senders = cur.fetchall()

    return {"total": total, "top_senders": top_senders}


def query_workflow_runs(target_date: date, conn: psycopg2.extensions.connection) -> dict:
    start, end = day_window_aware(target_date)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, workflow_id, status, started_at
            FROM workflow_runs
            WHERE started_at >= %s AND started_at < %s
            ORDER BY started_at DESC
            LIMIT 10
            """,
            (start, end),
        )
        rows = cur.fetchall()

        cur.execute(
            """
            SELECT COUNT(*)
            FROM workflow_runs
            WHERE started_at >= %s AND started_at < %s
            """,
            (start, end),
        )
        total = cur.fetchone()[0]

    return {"total": total, "rows": rows}


def query_lessons(target_date: date, conn: psycopg2.extensions.connection) -> dict:
    start, end = day_window_naive(target_date)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, source, lesson
            FROM lessons
            WHERE learned_at >= %s AND learned_at < %s
            ORDER BY learned_at DESC
            LIMIT 10
            """,
            (start, end),
        )
        rows = cur.fetchall()

        cur.execute(
            """
            SELECT COUNT(*)
            FROM lessons
            WHERE learned_at >= %s AND learned_at < %s
            """,
            (start, end),
        )
        total = cur.fetchone()[0]

    return {"total": total, "rows": rows}


def query_events(target_date: date, conn: psycopg2.extensions.connection) -> dict:
    start, end = day_window_naive(target_date)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, title, event_date
            FROM events
            WHERE event_date >= %s AND event_date < %s
            ORDER BY event_date DESC
            LIMIT 10
            """,
            (start, end),
        )
        rows = cur.fetchall()

        cur.execute(
            """
            SELECT COUNT(*)
            FROM events
            WHERE event_date >= %s AND event_date < %s
            """,
            (start, end),
        )
        total = cur.fetchone()[0]

    return {"total": total, "rows": rows}


def query_tasks(target_date: date, conn: psycopg2.extensions.connection) -> dict:
    start, end = day_window_naive(target_date)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COUNT(*) FROM tasks WHERE created_at >= %s AND created_at < %s
            """,
            (start, end),
        )
        created = cur.fetchone()[0]

        cur.execute(
            """
            SELECT COUNT(*) FROM tasks WHERE completed_at >= %s AND completed_at < %s
            """,
            (start, end),
        )
        completed = cur.fetchone()[0]

        cur.execute(
            """
            SELECT COUNT(*) FROM tasks
            WHERE blocked = true
              AND updated_at >= %s AND updated_at < %s
            """,
            (start, end),
        )
        blocked = cur.fetchone()[0]

        cur.execute(
            """
            SELECT id, title, status
            FROM tasks
            WHERE created_at >= %s AND created_at < %s
            ORDER BY created_at DESC
            LIMIT 10
            """,
            (start, end),
        )
        recent_rows = cur.fetchall()

    return {
        "created": created,
        "completed": completed,
        "blocked": blocked,
        "recent_rows": recent_rows,
    }


def format_section(name: str, lines: Iterable[str]) -> list[str]:
    section = [f"### {name}", ""]
    section.extend(lines)
    section.append("")
    return section


def format_agent_chat(data: dict) -> list[str]:
    lines: list[str] = []
    lines.append(f"- Total messages: {data['total']}")
    if data["top_senders"]:
        lines.append("- Top senders:")
        for sender, count in data["top_senders"]:
            lines.append(f"  - {sender}: {count}")
    else:
        lines.append("- No agent chat activity recorded.")
    return format_section("Agent chat activity", lines)


def format_workflow_runs(data: dict) -> list[str]:
    lines: list[str] = []
    lines.append(f"- Total workflow runs: {data['total']}")
    if data["rows"]:
        lines.append("- Recent runs:")
        for run_id, workflow_id, status, started_at in data["rows"]:
            started = started_at.isoformat() if started_at else "N/A"
            lines.append(
                f"  - run {run_id} (workflow {workflow_id}): {status or 'unknown'} @ {started}"
            )
    else:
        lines.append("- No workflow runs recorded.")
    return format_section("Workflow runs", lines)


def format_lessons(data: dict) -> list[str]:
    lines: list[str] = []
    lines.append(f"- Total lessons learned: {data['total']}")
    if data["rows"]:
        lines.append("- Recent lessons:")
        for lesson_id, source, lesson in data["rows"]:
            snippet = (lesson or "").replace("\n", " ")
            if len(snippet) > 100:
                snippet = snippet[:97] + "..."
            lines.append(f"  - [{lesson_id}] {source or 'unknown'}: {snippet or '(no text)'}")
    else:
        lines.append("- No lessons recorded.")
    return format_section("Lessons learned", lines)


def format_events(data: dict) -> list[str]:
    lines: list[str] = []
    lines.append(f"- Total events: {data['total']}")
    if data["rows"]:
        lines.append("- Recent events:")
        for event_id, title, event_date in data["rows"]:
            lines.append(f"  - [{event_id}] {title or 'unknown'} @ {event_date.isoformat() if event_date else 'N/A'}")
    else:
        lines.append("- No events recorded.")
    return format_section("Events logged", lines)


def format_tasks(data: dict) -> list[str]:
    lines: list[str] = [
        f"- Created: {data['created']}",
        f"- Completed: {data['completed']}",
        f"- Blocked updates: {data['blocked']}",
    ]
    if data["recent_rows"]:
        lines.append("- Recent tasks:")
        for task_id, title, status in data["recent_rows"]:
            lines.append(f"  - [{task_id}] {status or 'unknown'}: {title or '(untitled)'}")
    else:
        lines.append("- No tasks created today.")
    return format_section("Tasks", lines)


def format_cron_results() -> list[str]:
    return format_section("Key cron results", [f"- {CRON_PLACEHOLDER}"])


def generate_block(target_date: date, pg_config: dict[str, str | int]) -> str:
    """Query both databases and render the generated markdown block."""
    try:
        conn_memory = connect(pg_config["database"], pg_config)
    except DailyLogError:
        raise

    agent_chat_db = "agent_chat"
    conn_chat = None
    try:
        conn_chat = connect(agent_chat_db, pg_config)
    except DailyLogError:
        conn_memory.close()
        raise

    try:
        chat_data = query_agent_chat(target_date, conn_chat)
        workflow_data = query_workflow_runs(target_date, conn_memory)
        lessons_data = query_lessons(target_date, conn_memory)
        events_data = query_events(target_date, conn_memory)
        tasks_data = query_tasks(target_date, conn_memory)
    finally:
        conn_memory.close()
        conn_chat.close()

    generated_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    lines: list[str] = [
        f"{BEGIN_MARKER_PREFIX} — source: generate-daily-log.py — generated_at: {generated_at} -->",
        "<!-- Do not edit between these markers; content is regenerated automatically. -->",
        "",
        "## System summary (auto-generated)",
        "",
    ]
    lines.extend(format_agent_chat(chat_data))
    lines.extend(format_workflow_runs(workflow_data))
    lines.extend(format_lessons(lessons_data))
    lines.extend(format_events(events_data))
    lines.extend(format_tasks(tasks_data))
    lines.extend(format_cron_results())
    lines.append(END_MARKER)

    return "\n".join(lines) + "\n"


def strip_generated_at(line: str) -> str:
    """Return a stable representation of a BEGIN marker for no-op comparison."""
    if line.startswith(BEGIN_MARKER_PREFIX):
        return BEGIN_MARKER_PREFIX
    return line


def blocks_equal(new_block: str, existing_block: str) -> bool:
    """Compare generated blocks ignoring the generated_at timestamp line."""
    new_lines = new_block.splitlines()
    existing_lines = existing_block.splitlines()
    if len(new_lines) != len(existing_lines):
        return False
    for a, b in zip(new_lines, existing_lines):
        if strip_generated_at(a) != strip_generated_at(b):
            return False
    return True


def find_markers(content: str) -> tuple[int, int]:
    """Return (begin_index, end_index) for a single valid marker pair, or raise."""
    begin_indices = [
        i for i, line in enumerate(content.splitlines())
        if line.startswith(BEGIN_MARKER_PREFIX)
    ]
    end_indices = [
        i for i, line in enumerate(content.splitlines())
        if line == END_MARKER
    ]

    if len(begin_indices) == 0 and len(end_indices) == 0:
        return -1, -1

    if len(begin_indices) != 1 or len(end_indices) != 1:
        raise DailyLogError(
            f"Malformed generated-block markers: "
            f"found {len(begin_indices)} BEGIN and {len(end_indices)} END markers. "
            f"BEGIN lines: {[i + 1 for i in begin_indices]}, "
            f"END lines: {[i + 1 for i in end_indices]}. "
            f"Fix manually and re-run."
        )

    begin_idx, end_idx = begin_indices[0], end_indices[0]
    if begin_idx >= end_idx:
        raise DailyLogError(
            f"Malformed generated-block markers: BEGIN marker (line {begin_idx + 1}) "
            f"appears after END marker (line {end_idx + 1}). Fix manually and re-run."
        )

    return begin_idx, end_idx


def update_file(file_path: Path, new_block: str) -> bool:
    """Atomically update the daily log file. Returns True if a write occurred."""
    file_path.parent.mkdir(parents=True, exist_ok=True)

    if not file_path.exists():
        content = f"# {file_path.stem}\n\n"
        content += new_block
        _atomic_write(file_path, content)
        return True

    original_bytes = file_path.read_bytes()
    original_text = original_bytes.decode("utf-8")

    begin_idx, end_idx = find_markers(original_text)

    if begin_idx == -1:
        # No markers: append block preserving existing content.
        if original_text.endswith("\n"):
            new_content = original_text + "\n" + new_block
        else:
            new_content = original_text + "\n\n" + new_block
    else:
        lines = original_text.splitlines()
        before = "\n".join(lines[:begin_idx])
        after = "\n".join(lines[end_idx + 1 :])

        parts = []
        if before:
            parts.append(before)
        parts.append(new_block.rstrip("\n"))
        if after:
            parts.append(after)

        # Preserve the original trailing newline convention if possible.
        ended_with_newline = original_text.endswith("\n")
        new_content = "\n\n".join(parts)
        if ended_with_newline and not new_content.endswith("\n"):
            new_content += "\n"

    # Idempotency: skip write if the generated block (sans generated_at) is unchanged.
    if begin_idx != -1:
        lines = original_text.splitlines()
        existing_block = "\n".join(lines[begin_idx : end_idx + 1]) + "\n"
        if blocks_equal(new_block, existing_block):
            return False

    _atomic_write(file_path, new_content)
    return True


def _atomic_write(file_path: Path, content: str) -> None:
    """Write content to a temp file in the same directory, fsync, then rename."""
    temp_fd, temp_path = tempfile.mkstemp(
        prefix=f".{file_path.name}.", suffix=".tmp", dir=str(file_path.parent)
    )
    temp_file = Path(temp_path)
    try:
        with os.fdopen(temp_fd, "w", encoding="utf-8") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, file_path)
    except Exception:
        try:
            os.close(temp_fd)
        except OSError:
            pass
        if temp_file.exists():
            temp_file.unlink()
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate or update the daily memory log markdown file."
    )
    parser.add_argument(
        "--date",
        type=validate_date,
        default=datetime.now(timezone.utc).date(),
        help="Target date in YYYY-MM-DD format (past dates only; default: today UTC).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the generated block without writing to disk.",
    )

    args = parser.parse_args(argv)
    target_date: date = args.date

    try:
        workspace = resolve_workspace()
        pg_config = load_postgres_config()
        new_block = generate_block(target_date, pg_config)
    except DailyLogError as exc:
        print(f"[generate-daily-log] ERROR: {exc.message}", file=sys.stderr)
        return exc.exit_code

    if args.dry_run:
        print(new_block, end="")
        return 0

    memory_dir = workspace / "memory"
    file_path = memory_dir / f"{target_date.isoformat()}.md"

    try:
        written = update_file(file_path, new_block)
    except DailyLogError as exc:
        print(f"[generate-daily-log] ERROR: {exc.message}", file=sys.stderr)
        return exc.exit_code
    except OSError as exc:
        print(
            f"[generate-daily-log] ERROR: failed to write {file_path}: {exc}",
            file=sys.stderr,
        )
        return 1

    if written:
        print(f"[generate-daily-log] Updated {file_path}")
    else:
        print(f"[generate-daily-log] No changes needed for {file_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
