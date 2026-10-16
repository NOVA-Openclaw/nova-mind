"""Read-only schema cross-check for SOURCE_SPECS (#706 QA round 4).

This test connects to the live Postgres database defined by PGDATABASE or
~/.openclaw/postgres.json (the same resolution path used by #703).  It only
runs SELECTs against information_schema.columns; it never writes, deletes, or
migrates data.  It is marked ``integration`` and is skipped when no DB is
reachable.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# Add memory/lib to the path so we can import the module under test.
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

import source_anchor as sa


def _resolve_db_connection(db_name: str):
    """Connect to a Postgres database, or skip if unavailable."""
    try:
        import psycopg2
    except ImportError:
        pytest.skip("psycopg2 not installed")

    config_path = os.path.expanduser("~/.openclaw/postgres.json")
    cfg: dict = {}
    try:
        import json

        with open(config_path) as f:
            cfg = json.load(f)
        if not isinstance(cfg, dict):
            cfg = {}
    except FileNotFoundError:
        pass

    kwargs = {"dbname": db_name}
    for json_key, env_var in (
        ("host", "PGHOST"),
        ("port", "PGPORT"),
        ("user", "PGUSER"),
        ("password", "PGPASSWORD"),
    ):
        value = os.environ.get(env_var, "").strip() or cfg.get(json_key)
        if value:
            kwargs[json_key] = value

    try:
        return psycopg2.connect(**kwargs)
    except psycopg2.OperationalError as exc:
        pytest.skip(f"could not connect to {db_name}: {exc}")


@pytest.fixture
def nova_conn():
    """Yield a real nova_memory connection, or skip if unavailable."""
    db_name = os.environ.get("PGDATABASE", "").strip()
    if not db_name:
        config_path = os.path.expanduser("~/.openclaw/postgres.json")
        try:
            import json

            with open(config_path) as f:
                cfg = json.load(f)
            db_name = cfg.get("database", "")
            if isinstance(db_name, str):
                db_name = db_name.strip()
        except FileNotFoundError:
            pass

    if not db_name or not db_name.endswith("_memory"):
        pytest.skip(f"no memory database resolved (got {db_name!r})")

    conn = _resolve_db_connection(db_name)
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture
def agent_chat_conn():
    """Yield a real agent_chat connection, or skip if unavailable."""
    conn = _resolve_db_connection("agent_chat")
    try:
        yield conn
    finally:
        conn.close()


@pytest.mark.integration
def test_source_specs_match_information_schema(nova_conn, agent_chat_conn):
    """Every SOURCE_SPECS table/key/provenance column must exist in the DB."""
    resolver = sa.SourceAnchorResolver(nova_conn, agent_chat_conn)
    report = resolver.validate_specs_against_schema()

    if not report["ok"]:
        for m in report["mismatches"]:
            print(m)

    assert report["ok"], (
        f"{report['mismatch_count']} SOURCE_SPECS mismatch(es) found: "
        f"{report['mismatches']}"
    )
