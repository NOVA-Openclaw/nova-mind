#!/usr/bin/env python3
"""
Integration tests for nova-mind#611 events INSERT path.

These tests use a real psycopg2 connection to nova_memory (peer auth) and a
scratch-schema copy of the events table. They are skipped when PostgreSQL is
unavailable so CI without a database does not break.

Because another test file in this directory mocks psycopg2 globally, the
actual DB exercise runs in a fresh subprocess so it sees the real driver.
"""

import os
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPT = REPO_ROOT / "memory" / "scripts" / "extract_memories.py"


def _db_available() -> bool:
    """Return True if we can connect to nova_memory as the current user."""
    try:
        import psycopg2

        conn = psycopg2.connect(
            user=os.environ.get("PGUSER") or os.getlogin(),
            host=os.environ.get("PGHOST", "localhost"),
            dbname="nova_memory",
        )
        conn.close()
        return True
    except Exception:
        return False


RUNNER = r'''
import os
import sys

import psycopg2

sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
sys.path.insert(0, os.path.dirname("SCRIPT_PLACEHOLDER"))

import extract_memories as em

schema = "test_611_events_insert"
conn = psycopg2.connect(
    user=os.environ.get("PGUSER") or os.getlogin(),
    host=os.environ.get("PGHOST", "localhost"),
    dbname="nova_memory",
)
with conn.cursor() as cur:
    cur.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")
    cur.execute(f"DROP TABLE IF EXISTS {schema}.events")
    cur.execute(f"CREATE TABLE {schema}.events (LIKE public.events INCLUDING ALL)")
    cur.execute(f"SET search_path TO {schema}, public")
conn.commit()

title = sys.argv[1]
environment = sys.argv[2] if len(sys.argv) > 2 else None

event = {"description": title}
if environment:
    event["environment"] = environment

em.store_extracted(
    data={"events": [event]},
    sender_name="QA",
    sender_id="",
    sender_provider="discord",
    src_timestamp="",
    src_channel_transcript_id="",
    src_channel_session_id="",
    conn=conn,
)

with conn.cursor() as cur:
    cur.execute(
        "SELECT title, description, event_date, source, environment FROM events WHERE title = %s",
        (title,),
    )
    row = cur.fetchone()
    cur.execute(f"DROP SCHEMA IF EXISTS {schema} CASCADE")
conn.commit()
conn.close()

if row is None:
    print("ROW_NOT_FOUND")
    sys.exit(1)

print("|".join("" if c is None else str(c) for c in row))
'''


def _run_subprocess_case(title: str, environment: str | None = None) -> str:
    """Run the DB exercise in a subprocess and return the pipe-delimited row."""
    runner = RUNNER.replace("SCRIPT_PLACEHOLDER", str(SCRIPT))
    args = [sys.executable, "-c", runner, title]
    if environment:
        args.append(environment)
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        check=False,
        cwd=str(REPO_ROOT),
    )
    if result.returncode != 0:
        raise AssertionError(
            f"Integration subprocess failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout.strip()


@unittest.skipUnless(_db_available(), "nova_memory not available")
class TestEventsInsertIntegration(unittest.TestCase):
    """Real-DB tests for the events INSERT placeholder/value symmetry."""

    def test_event_insert_without_date_or_timestamp(self):
        """BLOCKER regression: date omitted + empty src_timestamp must INSERT."""
        title = f"QA integration no-date {os.urandom(4).hex()}"
        row = _run_subprocess_case(title)
        parts = row.split("|")
        self.assertEqual(parts[0], title)
        self.assertEqual(parts[1], title)
        self.assertTrue(parts[2])  # event_date filled by COALESCE(..., NOW())
        self.assertEqual(parts[3], "QA")
        self.assertEqual(parts[4], "")

    def test_event_insert_without_date_but_with_environment(self):
        """Same path with environment populated must keep placeholder/value symmetry."""
        title = f"QA integration env {os.urandom(4).hex()}"
        row = _run_subprocess_case(title, "nova-local")
        parts = row.split("|")
        self.assertEqual(parts[0], title)
        self.assertEqual(parts[1], title)
        self.assertTrue(parts[2])
        self.assertEqual(parts[3], "QA")
        self.assertEqual(parts[4], "nova-local")


if __name__ == "__main__":
    unittest.main()
