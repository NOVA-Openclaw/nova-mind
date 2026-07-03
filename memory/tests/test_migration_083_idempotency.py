#!/usr/bin/env python3
"""
test_migration_083_idempotency.py — Verify migration 083 is idempotent.

Migration 083 rewrites workflow 27 (Proactive Mode) in place: it renumbers
steps 8/9/10 to 9/10/11, updates steps 6 and 7 with blocker-curation
semantics, and inserts the new "Blocker Outreach" step at step_order 8.

This test creates a fresh PostgreSQL database with only the tables required
for the migration, seeds workflow 27 with the pre-migration 10-step layout,
applies migration 083 twice, and asserts that the second run is a safe no-op
leaving exactly the expected 11-step layout with no duplicate rows.
"""

import os
import sys
import uuid
from pathlib import Path

import pytest

# test_proactive_gate_check.py replaces sys.modules['psycopg2'] with a MagicMock,
# which pollutes the import namespace for every later test in the same process.
# Force a fresh import of the real psycopg2 driver before anything else can mock it.
for _psycopg2_mod in ("psycopg2", "psycopg2.extras", "psycopg2.extensions"):
    sys.modules.pop(_psycopg2_mod, None)
import psycopg2  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MIGRATION_PATH = REPO_ROOT / "memory" / "migrations" / "083_blocker_outreach_workflow_27.sql"

if not hasattr(psycopg2, "connect") or psycopg2.connect is None:
    pytest.skip("psycopg2 driver not available", allow_module_level=True)


def _admin_conn():
    """Connect to the postgres maintenance database as the nova user."""
    # Unset any inherited PGPASSWORD so libpq falls back to .pgpass.
    env = os.environ.copy()
    env.pop("PGPASSWORD", None)
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(host="localhost", user="nova", dbname="postgres")


def _test_conn(db_name):
    """Connect to the freshly-created test database as the nova user."""
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(host="localhost", user="nova", dbname=db_name)


def _create_test_db():
    """Create and return the name of a uniquely-named test database."""
    db_name = f"nova_memory_test_083_{uuid.uuid4().hex[:8]}"
    conn = _admin_conn()
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS %s", (psycopg2.extensions.AsIs(db_name),))
        cur.execute("CREATE DATABASE %s", (psycopg2.extensions.AsIs(db_name),))
    conn.close()
    return db_name


def _drop_test_db(db_name):
    """Drop the test database, ignoring errors."""
    try:
        conn = _admin_conn()
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                "DROP DATABASE IF EXISTS %s",
                (psycopg2.extensions.AsIs(db_name),),
            )
        conn.close()
    except Exception:
        pass


def _seed_workflow_27(conn):
    """Create the minimal schema and seed workflow 27 with 10 steps."""
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE workflows (
                id SERIAL PRIMARY KEY,
                name text NOT NULL,
                description text NOT NULL DEFAULT '',
                created_at timestamptz DEFAULT now(),
                updated_at timestamptz DEFAULT now(),
                created_by text DEFAULT CURRENT_USER,
                status text DEFAULT 'active',
                tags text[] DEFAULT '{}',
                department text,
                orchestrator_domain text
            );
            CREATE TABLE workflow_steps (
                id SERIAL PRIMARY KEY,
                workflow_id integer NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
                step_order integer NOT NULL,
                description text NOT NULL,
                produces_deliverable boolean DEFAULT false,
                deliverable_type text,
                deliverable_description text,
                handoff_to_step integer REFERENCES workflow_steps(id),
                required boolean DEFAULT true,
                estimated_duration_minutes integer,
                requires_authorization boolean DEFAULT false,
                requires_discussion boolean DEFAULT false,
                domain text,
                domains text[],
                CONSTRAINT workflow_steps_workflow_id_step_order_key
                    UNIQUE (workflow_id, step_order)
            );
            INSERT INTO workflows (id, name, description)
            VALUES (27, 'Proactive Mode', 'Test workflow for migration 083');
            INSERT INTO workflow_steps (workflow_id, step_order, description)
            SELECT 27, i, 'Step ' || i FROM generate_series(1, 10) AS i;
            """
        )
    conn.commit()


def _apply_migration(conn):
    """Execute migration 083 against the open connection."""
    migration_sql = MIGRATION_PATH.read_text()
    with conn.cursor() as cur:
        cur.execute(migration_sql)
    conn.commit()


def _fetch_workflow_27(conn):
    """Return workflow 27 rows as (step_order, description) tuples."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT step_order, description
            FROM workflow_steps
            WHERE workflow_id = 27
            ORDER BY step_order
            """
        )
        return cur.fetchall()


@pytest.fixture
def test_db():
    """Yield a freshly-created test DB name and clean it up afterward."""
    db_name = _create_test_db()
    try:
        yield db_name
    finally:
        _drop_test_db(db_name)


def test_migration_083_idempotent(test_db):
    """Applying migration 083 twice must be a no-op and leave a clean layout."""
    conn = _test_conn(test_db)
    try:
        _seed_workflow_27(conn)

        # First application: should produce the 11-step layout.
        _apply_migration(conn)
        first = _fetch_workflow_27(conn)
        assert len(first) == 11, f"Expected 11 steps after first run, got {len(first)}"
        assert [r[0] for r in first] == list(range(1, 12))
        assert first[7][1].startswith("## Blocker Outreach")

        # Second application: must succeed and leave the layout unchanged.
        _apply_migration(conn)
        second = _fetch_workflow_27(conn)
        assert len(second) == 11, f"Expected 11 steps after second run, got {len(second)}"
        assert [r[0] for r in second] == list(range(1, 12))
        assert second[7][1].startswith("## Blocker Outreach")
        assert first == second, "Second run changed the workflow layout"

        # No duplicate "Blocker Outreach" rows may exist.
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*)
                FROM workflow_steps
                WHERE workflow_id = 27 AND description LIKE '## Blocker Outreach%'
                """
            )
            blocker_count = cur.fetchone()[0]
        assert blocker_count == 1, f"Expected 1 Blocker Outreach row, got {blocker_count}"
    finally:
        conn.close()
