"""
Tests for scripts/research-audit-gate.py — chunk 1: Foundation & DB contract.

Covers the DB test-case group (TC-657-DB-01..DB-07). All DB interaction uses a
throwaway schema created from tests/fixtures/research_audit_gate.sql; no test
writes into the live public.research_* tables.
"""

import importlib.util
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path
from types import ModuleType
from typing import Any, Iterator

import pytest

# ---------------------------------------------------------------------------
# Module import
# ---------------------------------------------------------------------------
_SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "research-audit-gate.py"


def _load_module() -> ModuleType:
    """Load the gate script as an importable module.

    Registers the module in sys.modules before execution so that
    ``from __future__ import annotations`` string annotations can be resolved
    by the stdlib dataclasses machinery (Python 3.10-3.12).
    """
    spec = importlib.util.spec_from_file_location(
        "research_audit_gate", _SCRIPT_PATH
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["research_audit_gate"] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


@pytest.fixture(scope="module")
def gate() -> ModuleType:
    """Loaded gate module, shared across the test module."""
    return _load_module()


# ---------------------------------------------------------------------------
# PostgreSQL helpers
# ---------------------------------------------------------------------------
# Test DB resolution order:
#   1. RESEARCH_AUDIT_GATE_TEST_DSN (a full libpq DSN string)
#   2. PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD env vars
# If neither resolves to a database, DB tests are skipped so the suite can run
# in environments without a configured test database.
TEST_DSN = os.environ.get("RESEARCH_AUDIT_GATE_TEST_DSN", "")


def _test_dsn() -> str:
    """Return the DSN to use for tests, or '' if none is configured.

    Only explicit environment values are used; the live ~/.openclaw/postgres.json
    is intentionally NOT consulted so tests cannot accidentally run against
    production nova_memory.
    """
    if TEST_DSN:
        return TEST_DSN
    # Require PGDATABASE to be explicitly set; without it we cannot know which
    # database is the intended test target.
    if not os.environ.get("PGDATABASE"):
        return ""
    parts: list[str] = []
    if os.environ.get("PGHOST"):
        parts.append(f"host={os.environ['PGHOST']}")
    if os.environ.get("PGPORT"):
        parts.append(f"port={os.environ['PGPORT']}")
    parts.append(f"dbname={os.environ['PGDATABASE']}")
    if os.environ.get("PGUSER"):
        parts.append(f"user={os.environ['PGUSER']}")
    return " ".join(parts)


def _require_test_db() -> str:
    """Return the test DSN or skip the current test."""
    dsn = _test_dsn()
    if not dsn:
        pytest.skip(
            "No test database configured. Set RESEARCH_AUDIT_GATE_TEST_DSN "
            "or PGHOST/PGDATABASE/PGUSER to run DB tests."
        )
    return dsn


@pytest.fixture(scope="module")
def db_conn():
    """Module-scoped DB connection for schema setup and teardown."""
    dsn = _require_test_db()
    import psycopg2

    conn = psycopg2.connect(dsn)
    yield conn
    conn.close()


def _read_fixture_sql(schema_name: str) -> str:
    """Return the fixture SQL with the schema placeholder substituted."""
    sql_path = Path(__file__).parent / "fixtures" / "research_audit_gate.sql"
    sql = sql_path.read_text()
    return sql.replace("{{schema}}", schema_name)


@pytest.fixture
def schema(db_conn: Any) -> Iterator[str]:
    """Create a fresh throwaway schema, yield its name, then drop it."""
    schema_name = f"test_gate_{uuid.uuid4().hex[:16]}"
    with db_conn.cursor() as cur:
        cur.execute(f"CREATE SCHEMA {schema_name}")
        cur.execute(_read_fixture_sql(schema_name))
        # Minimal research_tasks mirror so the gate's task-existence check works
        # without touching the public schema.
        cur.execute(
            f"""
            CREATE TABLE {schema_name}.research_tasks (
                id integer PRIMARY KEY,
                title character varying(500) NOT NULL,
                query text NOT NULL,
                importance character varying(20) NOT NULL DEFAULT 'normal',
                status character varying(50) NOT NULL DEFAULT 'pending',
                priority integer NOT NULL DEFAULT 5,
                assigned_to character varying(100) NOT NULL DEFAULT CURRENT_USER,
                metadata jsonb NOT NULL DEFAULT '{{}}'::jsonb
            )
            """
        )
    db_conn.commit()
    try:
        yield schema_name
    finally:
        with db_conn.cursor() as cur:
            cur.execute(f"DROP SCHEMA {schema_name} CASCADE")
        db_conn.commit()


def _insert_task(cur: Any, schema: str, task_id: int) -> None:
    """Insert a minimal research_tasks row."""
    cur.execute(
        f"""
        INSERT INTO {schema}.research_tasks (id, title, query)
        VALUES (%s, %s, %s)
        """,
        (task_id, f"task {task_id}", f"query {task_id}"),
    )


def _insert_finding(
    cur: Any,
    schema: str,
    finding_id: int,
    task_id: int,
    content: str = "finding content",
    confidence: float | None = 0.78,
    importance: str = "normal",
    is_current: bool = True,
    metadata: dict[str, Any] | None = None,
) -> None:
    """Insert a research_findings row."""
    cur.execute(
        f"""
        INSERT INTO {schema}.research_findings
            (id, task_id, finding_type, content, confidence, importance, is_current, metadata)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            finding_id,
            task_id,
            "fact",
            content,
            confidence,
            importance,
            is_current,
            json.dumps(metadata or {}),
        ),
    )


def _insert_citation(
    cur: Any,
    schema: str,
    citation_id: int,
    finding_id: int,
    source_type: str = "paper",
    source_url: str | None = "https://example.com/paper",
    source_title: str | None = "Example Paper",
    reliability: float | None = 0.88,
) -> None:
    """Insert a research_citations row."""
    cur.execute(
        f"""
        INSERT INTO {schema}.research_citations
            (id, finding_id, source_type, source_url, source_title, reliability)
        VALUES (%s, %s, %s, %s, %s, %s)
        """,
        (
            citation_id,
            finding_id,
            source_type,
            source_url,
            source_title,
            reliability,
        ),
    )


def _make_config(schema: str) -> Any:
    """Return a GateConfig-like object for tests."""
    # We use the gate module's dataclass directly once loaded; this helper keeps
    # test boilerplate small and pins non-DB config values.
    mod = _load_module()
    return mod.GateConfig(
        schema=schema,
        drop_window_hours=72.0,
        support_threshold=0.05,
        jev_url="https://api.typesafe.ai/v1/systemone",
        jev_api_key=None,
        db_dsn="",
        db_user="nova",
    )


# ---------------------------------------------------------------------------
# DB group tests
# ---------------------------------------------------------------------------
class TestDbJoinAndReadOnly:
    """TC-657-DB-* — join correctness, is_current filtering, read-only contract."""

    def test_db01_correct_join_path(self, db_conn, schema):
        """TC-657-DB-01: citations are joined via finding_id and filtered by task_id."""
        mod = _load_module()
        with db_conn.cursor() as cur:
            _insert_task(cur, schema, 90001)
            _insert_task(cur, schema, 90002)
            _insert_finding(cur, schema, 3310, 90001)
            _insert_finding(cur, schema, 3311, 90001)
            _insert_finding(cur, schema, 3320, 90002)
            _insert_citation(cur, schema, 4010, 3310)
            _insert_citation(cur, schema, 4011, 3310)
            _insert_citation(cur, schema, 4012, 3311)
            _insert_citation(cur, schema, 4020, 3320)
        db_conn.commit()

        findings = mod.load_findings(db_conn, schema, 90001)
        assert len(findings) == 2
        finding_ids = {f.finding_id for f in findings}
        assert finding_ids == {3310, 3311}
        citation_ids = {
            c.citation_id for f in findings for c in f.citations
        }
        assert citation_ids == {4010, 4011, 4012}
        # Sibling task's citation must not leak in.
        assert 4020 not in citation_ids

    def test_db02_is_current_false_excluded(self, db_conn, schema):
        """TC-657-DB-02: superseded findings are excluded from the audit."""
        mod = _load_module()
        with db_conn.cursor() as cur:
            _insert_task(cur, schema, 90001)
            _insert_finding(cur, schema, 3310, 90001, is_current=True)
            _insert_finding(cur, schema, 3311, 90001, is_current=False)
            _insert_citation(cur, schema, 4010, 3310, reliability=0.88)
            _insert_citation(cur, schema, 4011, 3311, reliability=0.15)
        db_conn.commit()

        findings = mod.load_findings(db_conn, schema, 90001)
        assert len(findings) == 1
        assert findings[0].finding_id == 3310
        assert len(findings[0].citations) == 1
        assert findings[0].citations[0].citation_id == 4010

    def test_db03_finding_with_zero_citations(self, db_conn, schema):
        """TC-657-DB-03: LEFT JOIN keeps findings that have no citations."""
        mod = _load_module()
        with db_conn.cursor() as cur:
            _insert_task(cur, schema, 90001)
            _insert_finding(cur, schema, 3310, 90001)
            _insert_finding(cur, schema, 3311, 90001)
            _insert_citation(cur, schema, 4010, 3310)
        db_conn.commit()

        findings = mod.load_findings(db_conn, schema, 90001)
        assert len(findings) == 2
        uncited = next(f for f in findings if f.finding_id == 3311)
        assert uncited.citations == []

        # The audit result surfaces an explicit no-citations state.
        config = _make_config(schema)
        result = mod.audit_task(findings, config)
        uncited_audit = next(
            fa for fa in result.finding_audits if fa.finding.finding_id == 3311
        )
        assert len(uncited_audit.citation_audits) == 1
        assert uncited_audit.citation_audits[0].existence_state == "no_citations"

    def test_db04_citation_from_other_task_not_joined(self, db_conn, schema):
        """TC-657-DB-04: a citation belonging to a sibling task never appears."""
        mod = _load_module()
        with db_conn.cursor() as cur:
            _insert_task(cur, schema, 90001)
            _insert_task(cur, schema, 90002)
            _insert_finding(cur, schema, 3310, 90001)
            _insert_finding(cur, schema, 3320, 90002)
            _insert_citation(cur, schema, 4020, 3320)
        db_conn.commit()

        findings = mod.load_findings(db_conn, schema, 90001)
        assert len(findings) == 1
        assert findings[0].finding_id == 3310
        assert findings[0].citations == []

    def test_db06_row_count_unchanged(self, db_conn, schema):
        """TC-657-DB-06: gate invocation leaves research_* row counts unchanged."""
        mod = _load_module()
        with db_conn.cursor() as cur:
            _insert_task(cur, schema, 90001)
            _insert_finding(cur, schema, 3310, 90001)
            _insert_finding(cur, schema, 3311, 90001)
            _insert_citation(cur, schema, 4010, 3310)
            _insert_citation(cur, schema, 4011, 3311, reliability=0.15)
        db_conn.commit()

        before = mod.get_table_counts(db_conn, schema)
        config = _make_config(schema)
        findings = mod.load_findings(db_conn, schema, 90001)
        mod.audit_task(findings, config)
        after = mod.get_table_counts(db_conn, schema)

        assert before == after


class TestDbExitAndRole:
    """TC-657-DB-05, DB-07 — task existence and read-only role checks."""

    def test_db05_nonexistent_task_returns_exit_2(self, db_conn, schema, tmp_path):
        """TC-657-DB-05: a missing task_id is a usage/DB error, exit 2."""
        # The schema exists but contains no tasks.
        _require_test_db()  # skipped early if no test DB is configured
        env = os.environ.copy()
        env["RESEARCH_AUDIT_GATE_SCHEMA"] = schema
        proc = subprocess.run(
            [sys.executable, str(_SCRIPT_PATH), "--task-id", "999999", "--json"],
            cwd=str(_SCRIPT_PATH.parent.parent),
            env=env,
            capture_output=True,
            text=True,
        )
        assert proc.returncode == 2, f"stdout={proc.stdout!r} stderr={proc.stderr!r}"
        assert "not found" in proc.stderr.lower()

    def test_db07_readonly_sufficient_role(self):
        """TC-657-DB-07: the gate connects as a non-scout, non-superuser role."""
        mod = _load_module()
        config = mod.GateConfig(
            schema="public",
            drop_window_hours=72.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )
        assert config.is_readonly_sufficient()
        # Scout and postgres roles must be rejected by the self-check.
        for bad_user in ("scout", "postgres"):
            bad = mod.GateConfig(
                schema="public",
                drop_window_hours=72.0,
                support_threshold=0.05,
                jev_url="https://api.typesafe.ai/v1/systemone",
                jev_api_key=None,
                db_dsn="",
                db_user=bad_user,
            )
            assert not bad.is_readonly_sufficient()
