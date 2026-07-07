#!/usr/bin/env python3
"""
announce-d100-rolls.py — deterministic D100 roll announcer for #proactive-mode.

Claims unannounced rows from d100_roll_log, joins motivation_d100 for task
detail, and posts to Discord via the openclaw CLI. Idempotent: re-running
only processes rows where announced_at IS NULL.

See: nova-mind#432
"""

import argparse
import getpass
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from typing import Any

# ---------------------------------------------------------------------------
# Venv bootstrap — add nova venv site-packages so psycopg2 is importable
# even when running outside the venv.
# ---------------------------------------------------------------------------
_PY_VER = f"python{sys.version_info.major}.{sys.version_info.minor}"
_VENV_USER = os.environ.get("USER") or os.environ.get("LOGNAME") or getpass.getuser()
_VENV_SITE = os.path.expanduser(
    f"~/.local/share/{_VENV_USER}/venv/lib/{_PY_VER}/site-packages"
)
if os.path.isdir(_VENV_SITE) and _VENV_SITE not in sys.path:
    sys.path.insert(0, _VENV_SITE)

import psycopg2  # noqa: E402

# Load centralized PG config loader. Try the installed location first
# (~/.openclaw/lib), then fall back to the repo-relative path so tests and
# repo-based runs continue to work. See nova-mind#437.
_installed_pg_env_dir = os.path.expanduser("~/.openclaw/lib")
_repo_pg_env_dir = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"
)
_PG_ENV_AVAILABLE = False
for _pg_env_dir in (_installed_pg_env_dir, _repo_pg_env_dir):
    if _pg_env_dir not in sys.path:
        sys.path.insert(0, _pg_env_dir)
    try:
        from pg_env import load_pg_env  # type: ignore
        _PG_ENV_AVAILABLE = True
        break
    except ImportError:
        # Remove the failed path so the next candidate is tried cleanly.
        if _pg_env_dir in sys.path:
            sys.path.remove(_pg_env_dir)

# Keep a stable name for backwards compatibility in case anything references
# _PG_ENV_DIR directly (tests, wrappers, etc.).
_PG_ENV_DIR = _installed_pg_env_dir if _PG_ENV_AVAILABLE else _repo_pg_env_dir

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DISCORD_CHANNEL = "1504054635231445112"
MAX_INDIVIDUAL_MESSAGES = 3


def _dsn() -> str:
    """Build a psycopg2 DSN from pg_env. Password is omitted; libpq reads
    PGPASSWORD from the environment set by load_pg_env and/or .pgpass.

    Mirrors the explicit per-key mapping used by proactive-gate-check.py so
    that PGPORT -> port=, PGDATABASE -> dbname=, PGUSER -> user=.
    """
    if not _PG_ENV_AVAILABLE:
        raise RuntimeError("pg_env loader not importable")
    env = load_pg_env()
    parts: list[str] = []
    host = env.get("PGHOST")
    if host:
        parts.append(f"host={host}")
    else:
        parts.append("host=/var/run/postgresql")
    if env.get("PGPORT"):
        parts.append(f"port={env['PGPORT']}")
    if env.get("PGDATABASE"):
        parts.append(f"dbname={env['PGDATABASE']}")
    if env.get("PGUSER"):
        parts.append(f"user={env['PGUSER']}")
    return " ".join(parts)


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _format_roll(row: dict[str, Any]) -> str:
    """Format a single roll announcement."""
    roll = row["roll"]
    task_name = row["task_name"] or ""
    estimated = row["estimated_minutes"]
    difficulty = row["difficulty"] or ""
    last_rolled = row["last_rolled"]
    last_completed = row["last_completed"]

    task_display = task_name.strip() if task_name and task_name.strip() else f"task unknown (slot {roll})"

    if estimated and difficulty:
        status = f"rolled ({estimated}m, difficulty {difficulty})"
    else:
        status = "rolled"

    lines = [f'🎲 D100 roll {roll}: "{task_display}" — {status}']

    if last_completed is not None and last_rolled is not None and last_completed >= last_rolled:
        lines.append("✅ Completed")

    return "\n".join(lines)


def _send_message(text: str, dry_run: bool) -> bool:
    """Post one message via openclaw. Returns True on success."""
    if dry_run:
        print(f"[DRY-RUN] would send: {text[:200]}...")
        return True

    openclaw_bin = shutil.which("openclaw")
    if not openclaw_bin:
        print(
            "openclaw CLI not found in PATH; ensure the cron wrapper exports a PATH "
            "containing the openclaw binary (e.g. ~/.npm-global/bin).",
            file=sys.stderr,
        )
        return False

    cmd = [
        openclaw_bin, "message", "send",
        "--channel", "discord",
        "--target", f"channel:{DISCORD_CHANNEL}",
        "-m", text,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            print(
                f"openclaw message send failed (rc={result.returncode}): {result.stderr.strip()}",
                file=sys.stderr,
            )
            return False
        return True
    except Exception as exc:
        print(f"openclaw message send exception: {exc}", file=sys.stderr)
        return False


def _select_unannounced(conn) -> list[tuple[Any, ...]]:
    """Dry-run helper: read unannounced rows without claiming them."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT id, roll, rolled_at
            FROM d100_roll_log
            WHERE announced_at IS NULL
            ORDER BY rolled_at ASC
        """)
        return cur.fetchall()


def _claim_rows(conn) -> list[tuple[Any, ...]]:
    """Atomically claim all unannounced rows."""
    with conn.cursor() as cur:
        cur.execute("""
            UPDATE d100_roll_log
            SET announced_at = now()
            WHERE announced_at IS NULL
            RETURNING id, roll, rolled_at
        """)
        return cur.fetchall()


def _fetch_task_details(conn, rolls: list[int]) -> dict[int, dict[str, Any]]:
    """LEFT JOIN stand-in: fetch motivation_d100 details by roll value."""
    if not rolls:
        return {}
    with conn.cursor() as cur:
        cur.execute("""
            SELECT roll, task_name, estimated_minutes, difficulty, last_rolled, last_completed
            FROM motivation_d100
            WHERE roll = ANY(%s)
        """, (rolls,))
        return {
            row[0]: {
                "task_name": row[1],
                "estimated_minutes": row[2],
                "difficulty": row[3],
                "last_rolled": row[4],
                "last_completed": row[5],
            }
            for row in cur.fetchall()
        }


def _unstamp_rows(conn, ids: list[int]) -> None:
    """Compensating rollback: clear announced_at for failed rows."""
    if not ids:
        return
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE d100_roll_log SET announced_at = NULL WHERE id = ANY(%s)",
            (ids,),
        )


def _build_rows(claimed: list[tuple[Any, ...]], task_map: dict[int, dict[str, Any]]) -> list[dict[str, Any]]:
    """Merge claimed roll log rows with motivation details."""
    rows: list[dict[str, Any]] = []
    for rid, roll, rolled_at in claimed:
        details = task_map.get(roll, {})
        rows.append({
            "id": rid,
            "roll": roll,
            "rolled_at": rolled_at,
            "task_name": details.get("task_name"),
            "estimated_minutes": details.get("estimated_minutes"),
            "difficulty": details.get("difficulty"),
            "last_rolled": details.get("last_rolled"),
            "last_completed": details.get("last_completed"),
        })
    return rows


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Announce unannounced D100 rolls to Discord #proactive-mode."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Read rows and print what would be sent without sending or stamping.",
    )
    args = parser.parse_args(argv)

    try:
        conn = psycopg2.connect(_dsn())
    except Exception as exc:
        print(f"Database connection failed: {exc}", file=sys.stderr)
        return 1

    with conn:
        if args.dry_run:
            claimed = _select_unannounced(conn)
        else:
            claimed = _claim_rows(conn)

        if not claimed:
            print("0 rolls to announce")
            return 0

        # Chronological order per D4.
        claimed = sorted(claimed, key=lambda r: r[2])

        rolls = [r[1] for r in claimed]
        task_map = _fetch_task_details(conn, rolls)
        rows = _build_rows(claimed, task_map)

    failed_ids: list[int] = []

    if len(rows) > MAX_INDIVIDUAL_MESSAGES:
        text = "\n\n".join(_format_roll(r) for r in rows)
        if _send_message(text, args.dry_run):
            print(f"Sent digest for {len(rows)} rolls")
        else:
            failed_ids = [r["id"] for r in rows]
    else:
        for row in rows:
            text = _format_roll(row)
            if _send_message(text, args.dry_run):
                print(f"Sent announcement for roll {row['roll']}")
            else:
                failed_ids.append(row["id"])

    if failed_ids and not args.dry_run:
        try:
            with conn:
                _unstamp_rows(conn, failed_ids)
            print(f"Un-stamped {len(failed_ids)} failed roll(s) for retry", file=sys.stderr)
        except Exception as exc:
            print(f"Failed to un-stamp rows {failed_ids}: {exc}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
