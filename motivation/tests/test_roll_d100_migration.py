"""
Regression test for nova-mind#444.

Pytest's mock-based coverage of announce-d100-rolls.py cannot catch SQL-level
errors inside the SECURITY DEFINER roll_d100() function (e.g., ambiguous column
references caused by PL/pgSQL output-parameter names colliding with table
columns). This test loads roll_d100() directly from migration 084 — the source
of truth — into the configured database and calls it end-to-end.

The transaction is always rolled back, so no permanent writes are made.
"""

import os
from pathlib import Path

import pytest

MIGRATION_PATH = Path(__file__).parent.parent.parent / "memory" / "migrations" / "084_d100_motivation_refinements.sql"
# Use a valid, currently empty non-reserved roll for deterministic seeding.
TEST_ROLL = 65


def _load_pg_env() -> None:
    """Bring pg_env values into os.environ if the loader is available."""
    try:
        from pg_env import load_pg_env  # type: ignore

        env = load_pg_env()
        if env is not None:
            for key, value in env.items():
                if value is not None:
                    os.environ[key] = str(value)
    except ImportError:
        pass


def _extract_roll_d100_block(sql: str) -> str:
    """Extract DROP + CREATE OR REPLACE FUNCTION roll_d100() ... $$; block."""
    start = sql.find("DROP FUNCTION IF EXISTS roll_d100();")
    if start == -1:
        raise ValueError("DROP FUNCTION IF EXISTS roll_d100() not found in migration 084")

    marker = "$$;\n\n-- Restore nova EXECUTE grant after drop/create."
    end = sql.find(marker, start)
    if end == -1:
        raise ValueError("End of roll_d100() function body not found in migration 084")

    return sql[start:end + 4]


def _connect():
    _load_pg_env()
    import psycopg2

    return psycopg2.connect(
        host=os.environ.get("PGHOST", "/var/run/postgresql"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "nova_memory"),
        user=os.environ.get("PGUSER", "nova"),
    )


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_deployed_roll_d100_runs_without_privilege_errors():
    """
    TC-444-PRIV-01: the live, deployed roll_d100() function can be called by
    the nova role and returns a row. This catches column-grant regressions
    (e.g. missing UPDATE on tracking columns) that migration-only tests miss
    because they recreate the function as the table owner.
    """
    conn = _connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            row = cur.fetchone()

            assert row is not None, "deployed roll_d100() returned no row"
            assert isinstance(row[0], int), f"expected integer roll, got {row[0]!r}"
            assert 1 <= row[0] <= 100, f"roll {row[0]} out of 1-100 range"
    finally:
        conn.rollback()
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_d100_from_migration_returns_row():
    """
    TC-444-ADV-09: source-of-truth migration function executes without
    ambiguity errors and returns a populated row.
    """
    migration_sql = MIGRATION_PATH.read_text()
    function_sql = _extract_roll_d100_block(migration_sql)

    conn = _connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            # Install the migration-084 roll_d100() in this transaction.
            cur.execute(function_sql)

            # Seed a single populated+enabled row and disable all empty slots so
            # the function is guaranteed to take the populated-task path.
            cur.execute(
                """
                INSERT INTO motivation_d100 (
                    roll, task_name, task_description, enabled, populated_at
                ) VALUES (
                    %s, 'Migration regression smoke test task',
                    'Temporary row for roll_d100 smoke test', true, now()
                )
                ON CONFLICT (roll) DO UPDATE SET
                    task_name = EXCLUDED.task_name,
                    task_description = EXCLUDED.task_description,
                    enabled = true,
                    populated_at = COALESCE(motivation_d100.populated_at, now());
                """,
                (TEST_ROLL,),
            )
            cur.execute("UPDATE motivation_d100 SET enabled = false WHERE task_name IS NULL;")

            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            row = cur.fetchone()

            assert row is not None, "roll_d100() returned no row"
            assert row[-1] is False, f"Expected is_populate_me=False for populated row, got {row[-1]}"
            assert 1 <= row[0] <= 100, f"roll {row[0]} out of 1-100 range"
    finally:
        conn.rollback()
        conn.close()
