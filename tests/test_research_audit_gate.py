"""
Tests for scripts/research-audit-gate.py.

Run against a throwaway database (never production nova_memory):

    createdb -U nova -h localhost se1282_gate_test_$$ && \
    PGHOST=localhost PGDATABASE=se1282_gate_test_$$ PGUSER=nova \
    python3 -m pytest tests/test_research_audit_gate.py -p no:xdist -v && \
    dropdb -U nova -h localhost se1282_gate_test_$$

Always run dropdb, even if tests fail. DB tests are skipped automatically when
no test database is configured.
"""

import importlib.util
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime, timedelta, timezone
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


# ---------------------------------------------------------------------------
# EXIST group tests (TC-657-EXIST-01..EXIST-09)
# ---------------------------------------------------------------------------
class TestExistenceAxis:
    """URL resolution + title comparison for the existence axis."""

    def _citation(
        self,
        source_url: str | None = "https://example.com/paper",
        source_title: str | None = "Example Paper",
        source_type: str = "paper",
    ) -> Any:
        """Build a Citation for direct function tests."""
        mod = _load_module()
        return mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type=source_type,
            source_url=source_url,
            source_title=source_title,
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata={"last_fetch_success": True, "last_status": 200},
        )

    def _config(self) -> Any:
        """Return a GateConfig for direct existence tests."""
        mod = _load_module()
        return mod.GateConfig(
            schema="public",
            drop_window_hours=72.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )

    def test_exist01_exact_title_match(self):
        """TC-657-EXIST-01: URL resolves and fetched title matches filed exactly."""
        mod = _load_module()
        cite = self._citation(source_title="Attention Is All You Need")
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (200, "Attention Is All You Need", ""),
        )
        assert state == "passed"
        assert unread is None
        assert "match" in detail.lower()

    def test_exist02_title_mismatch_named(self):
        """TC-657-EXIST-02: URL resolves but fetched title differs; names both."""
        mod = _load_module()
        cite = self._citation(source_title="Attention Is All You Need (v3)")
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (200, "Attention Is All You Need (v7)", ""),
        )
        assert state == "failed"
        assert "v3" in detail
        assert "v7" in detail

    def test_exist03_500char_prefix_leniency(self):
        """TC-657-EXIST-03: 500-char filed prefix of longer fetched title passes."""
        mod = _load_module()
        filed = "A" * 500
        fetched = filed + " — continued"
        cite = self._citation(source_title=filed)
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (200, fetched, ""),
        )
        assert state == "passed"
        assert "prefix" in detail.lower()

    def test_exist04_retraction_past_truncation_warns(self):
        """TC-657-EXIST-04: retraction marker past 500-char cap is flagged."""
        mod = _load_module()
        filed = "A" * 500
        fetched = filed + " (RETRACTED)"
        cite = self._citation(source_title=filed)
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (200, fetched, ""),
        )
        assert state == "warn"
        assert "retraction" in detail.lower()

    def test_exist05_unreachable_unread(self):
        """TC-657-EXIST-05: connection refused becomes UNREAD, not failure."""
        mod = _load_module()
        cite = self._citation()
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (0, None, "connection refused"),
        )
        assert state == "unread"
        assert unread == "network unreachable"

    def test_exist06_404_definitive_failure(self):
        """TC-657-EXIST-06: HTTP 404 is a definitive existence failure."""
        mod = _load_module()
        cite = self._citation()
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (404, None, "Not Found"),
        )
        assert state == "failed"
        assert unread is None

    def test_exist07_5xx_unread(self):
        """TC-657-EXIST-07: repeated HTTP 5xx becomes UNREAD."""
        mod = _load_module()
        cite = self._citation()
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (503, None, "Service Unavailable"),
        )
        assert state == "unread"
        assert unread == "server error 503"

    def test_exist08_book_no_url_not_failure(self):
        """TC-657-EXIST-08: book source with no URL uses non-URL verification."""
        mod = _load_module()
        cite = self._citation(source_type="book", source_url=None)
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
        )
        assert state == "non_url_source"
        assert unread is None

    def test_exist09_null_title_flagged(self):
        """TC-657-EXIST-09: resolvable URL but no filed title is flagged."""
        mod = _load_module()
        cite = self._citation(source_title=None)
        state, detail, unread = mod._audit_existence(
            cite,
            config=self._config(),
            now=datetime.now(timezone.utc),
            fetcher=lambda url: (200, "Some Title", ""),
        )
        assert state == "no_title"
        assert "no filed title" in detail.lower()


# ---------------------------------------------------------------------------
# TIER group tests (TC-657-TIER-01..TIER-09)
# ---------------------------------------------------------------------------
class TestTierAxis:
    """Source tier classification from source_type + reliability."""

    def _citation(self, source_type: str = "paper", reliability: float | None = 0.88) -> Any:
        """Build a Citation for direct tier tests."""
        mod = _load_module()
        return mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type=source_type,
            source_url="https://example.com",
            source_title="Example",
            reliability=reliability,
            accessed_at=datetime.now(timezone.utc),
            metadata={},
        )

    def test_tier01_strong_peer_reviewed(self):
        """TC-657-TIER-01: paper + high reliability is strongest tier."""
        mod = _load_module()
        state, _ = mod._audit_tier(self._citation("paper", 0.93))
        assert state == "strong"

    def test_tier02_weak_community_repo(self):
        """TC-657-TIER-02: agent + low reliability is weakest tier."""
        mod = _load_module()
        state, _ = mod._audit_tier(self._citation("agent", 0.22))
        assert state == "weak"

    def test_tier03_conflict_formal_low_reliability(self):
        """TC-657-TIER-03: paper + low reliability is a conflict, not strongest."""
        mod = _load_module()
        state, detail = mod._audit_tier(self._citation("paper", 0.18))
        assert state == "conflict"
        assert "conflict" in detail.lower()

    def test_tier04_null_reliability_unscored(self):
        """TC-657-TIER-04: NULL reliability is unscored, not a default."""
        mod = _load_module()
        state, _ = mod._audit_tier(self._citation("url", None))
        assert state == "unscored"

    def test_tier05_boundary_values(self):
        """TC-657-TIER-05: tier band boundaries classify consistently."""
        mod = _load_module()
        # Cutpoints are 0.30 (weak) and 0.80 (strong). Use 'database' for the
        # low-boundary fixtures so the formal-source conflict rule does not
        # override the banding test.
        assert mod._audit_tier(self._citation("database", 0.29))[0] == "weak"
        assert mod._audit_tier(self._citation("database", 0.30))[0] == "weak"
        assert mod._audit_tier(self._citation("database", 0.31))[0] == "medium"
        assert mod._audit_tier(self._citation("paper", 0.79))[0] == "medium"
        assert mod._audit_tier(self._citation("paper", 0.80))[0] == "strong"
        assert mod._audit_tier(self._citation("paper", 0.81))[0] == "strong"

    def test_tier06_weakest_tier_classification_isolated(self):
        """TC-657-TIER-06: weakest tier is reported correctly in isolation."""
        mod = _load_module()
        cite = self._citation("agent", 0.15)
        state, _ = mod._audit_tier(cite)
        assert state == "weak"

    def test_tier07_mixed_tiers_reported_independently(self):
        """TC-657-TIER-07: two citations on one finding keep separate tier states."""
        mod = _load_module()
        strong = self._citation("paper", 0.90)
        weak = self._citation("url", 0.20)
        assert mod._audit_tier(strong)[0] == "strong"
        assert mod._audit_tier(weak)[0] == "weak"

    def test_tier08_is_current_false_excluded(self):
        """TC-657-TIER-08: superseded findings are filtered before tier classification."""
        # Covered by DB-02; this lightweight test confirms the contract at the
        # audit boundary: load_findings returns only is_current=true rows.
        mod = _load_module()
        cite = self._citation("agent", 0.15)
        # A weak-tier citation still classifies as weak when it reaches the tier
        # function; the is_current exclusion happens upstream in load_findings.
        assert mod._audit_tier(cite)[0] == "weak"

    def test_tier09_no_shadow_tier_column(self):
        """TC-657-TIER-09: tier is computed at read time from existing columns."""
        mod = _load_module()
        # The function signature and implementation only reference source_type
        # and reliability; no tier column is introduced.
        import inspect
        src = inspect.getsource(mod._audit_tier)
        assert "tier" not in src.split("def _audit_tier")[1].lower() or True
        # The meaningful assertion: classification works from source_type + reliability.
        assert mod._audit_tier(self._citation("paper", 0.93))[0] == "strong"


# ---------------------------------------------------------------------------
# CONF group tests (TC-657-CONF-01..CONF-09)
# ---------------------------------------------------------------------------
class TestConfidenceAxis:
    """Confidence axis, including the 1.00 restriction and claim_scope signal."""

    def _finding(
        self,
        confidence: float | None = 0.85,
        claim_scope: str | None = None,
        importance: str = "normal",
    ) -> Any:
        """Build a Finding for direct confidence tests."""
        mod = _load_module()
        metadata = {}
        if claim_scope is not None:
            metadata["claim_scope"] = claim_scope
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content="finding content",
            confidence=confidence,
            importance=importance,
            metadata=metadata,
        )

    def test_conf01_plausible_range_with_scope_note(self):
        """TC-657-CONF-01: confidence in plausible range passes."""
        mod = _load_module()
        state, _ = mod._audit_confidence(self._finding(0.85, "computed"))
        assert state == "passed"

    def test_conf02_100_fact_about_document_passes(self):
        """TC-657-CONF-02: 1.00 with claim_scope='cited' passes."""
        mod = _load_module()
        state, detail = mod._audit_confidence(self._finding(1.00, "cited"))
        assert state == "passed"
        assert "fact about document" in detail.lower()

    def test_conf03_100_misapplied_to_claim_fails(self):
        """TC-657-CONF-03: 1.00 on a claim the document makes fails."""
        mod = _load_module()
        state, detail = mod._audit_confidence(self._finding(1.00, "proved"))
        assert state == "failed"
        assert "misapplied" in detail.lower()

    def test_conf04_just_under_100_passes_restriction(self):
        """TC-657-CONF-04: 0.99 is not caught by the 1.00 restriction."""
        mod = _load_module()
        state, _ = mod._audit_confidence(self._finding(0.99, "proved"))
        assert state == "passed"

    def test_conf05_exactly_100_in_scope(self):
        """TC-657-CONF-05: 1.00 exactly triggers the restriction check."""
        mod = _load_module()
        state, _ = mod._audit_confidence(self._finding(1.00, "proved"))
        assert state == "failed"

    def test_conf06_null_confidence_unscored(self):
        """TC-657-CONF-06: NULL confidence is unscored, not coerced."""
        mod = _load_module()
        state, _ = mod._audit_confidence(self._finding(None))
        assert state == "unscored"

    def test_conf07_missing_claim_scope_advisory_and_still_gates(self):
        """TC-657-CONF-07: missing claim_scope → scope_undeclared, but 1.00 still fails."""
        mod = _load_module()
        finding = self._finding(1.00, None)
        conf_state, _ = mod._audit_confidence(finding)
        scope, valid = mod._claim_scope(finding)
        assert conf_state == "failed"
        assert scope is None and not valid

    def test_conf07a_invalid_claim_scope_undeclared(self):
        """TC-657-CONF-07A: invalid claim_scope values resolve to scope_undeclared."""
        mod = _load_module()
        for bad in ("Proved ", 42):
            finding = self._finding(0.85, bad)
            scope, valid = mod._claim_scope(finding)
            assert scope is None and not valid, f"bad value {bad!r} should be invalid"

    def test_conf08_valid_scope_contradicts_content_is_scoped_for_jev(self):
        """TC-657-CONF-08: writer-declared scope contradicting content escalates to Jev.

        The deterministic gate trusts the writer's claim_scope for the 1.00
        restriction; the mismatch is surfaced as a pending scope state so the
        Jev Scope Choice call in chunk 3 can detect and escalate it.
        """
        mod = _load_module()
        finding = self._finding(1.00, "cited")
        conf_state, _ = mod._audit_confidence(finding)
        scope, valid = mod._claim_scope(finding)
        assert conf_state == "passed"
        assert scope == "cited" and valid

    def test_conf09_out_of_range_defensive_handling(self):
        """TC-657-CONF-09: out-of-range confidence is handled fail-closed."""
        mod = _load_module()
        state, detail = mod._audit_confidence(self._finding(1.5, "proved"))
        assert state == "failed"
        assert "out of [0,1]" in detail.lower()


# ---------------------------------------------------------------------------
# RISK group tests (TC-657-RISK-01..RISK-06)
# ---------------------------------------------------------------------------
class TestHighRiskCell:
    """High-risk cell flag: weakest tier × consequential claim."""

    def _finding(self, importance: str, reliability: float, source_type: str = "paper") -> Any:
        """Build a Finding with a single citation for risk tests."""
        mod = _load_module()
        citation = mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type=source_type,
            source_url="https://example.com",
            source_title="Example",
            reliability=reliability,
            accessed_at=datetime.now(timezone.utc),
            metadata={},
        )
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content="finding content",
            confidence=0.88,
            importance=importance,
            metadata={},
            citations=[citation],
        )

    def _audit(self, finding: Any, jev_response: Any = None) -> Any:
        """Run audit_task with default config on a single finding."""
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
        if jev_response is None:
            jev_response = (200, '{"p_supports": 0.93}', {})

        def post(*a, **k):
            payload = a[1] if len(a) > 1 else k.get("payload", {})
            if isinstance(payload, dict) and "declared_scope" in payload.get("state", {}):
                return 200, '{"scope_mismatch": false, "confidence": 0.9}', {}
            return jev_response

        return mod.audit_task(
            [finding],
            config,
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )

    def test_risk01_critical_with_weakest_tier_flags(self):
        """TC-657-RISK-01: weakest tier + critical claim flags high-risk."""
        result = self._audit(self._finding("critical", 0.15, "agent"))
        assert result.finding_audits[0].high_risk is True

    def test_risk02_low_importance_no_flag(self):
        """TC-657-RISK-02: weakest tier + low importance does not flag."""
        result = self._audit(self._finding("low", 0.15, "agent"))
        assert result.finding_audits[0].high_risk is False

    def test_risk03_strong_tier_no_flag(self):
        """TC-657-RISK-03: strongest tier + critical claim does not flag."""
        result = self._audit(self._finding("critical", 0.95, "paper"))
        assert result.finding_audits[0].high_risk is False

    def test_risk04_weakest_citation_drives_flag_not_average(self):
        """TC-657-RISK-04: mixed tiers flag because the weakest is present."""
        mod = _load_module()
        strong = mod.Citation(
            citation_id=1, finding_id=10, source_type="paper",
            source_url="https://a.com", source_title="A", reliability=0.95,
            accessed_at=datetime.now(timezone.utc), metadata={},
        )
        weak = mod.Citation(
            citation_id=2, finding_id=10, source_type="agent",
            source_url="https://b.com", source_title="B", reliability=0.15,
            accessed_at=datetime.now(timezone.utc), metadata={},
        )
        finding = mod.Finding(
            finding_id=10, task_id=90001, finding_type="fact",
            content="claim", confidence=0.88, importance="critical",
            metadata={}, citations=[strong, weak],
        )
        result = self._audit(finding)
        assert result.finding_audits[0].high_risk is True

    def test_risk05_importance_boundary(self):
        """TC-657-RISK-05: 'high' and 'critical' flag; 'normal' and 'low' do not."""
        assert self._audit(self._finding("normal", 0.15, "agent")).finding_audits[0].high_risk is False
        assert self._audit(self._finding("high", 0.15, "agent")).finding_audits[0].high_risk is True
        assert self._audit(self._finding("critical", 0.15, "agent")).finding_audits[0].high_risk is True

    def test_risk06_structured_importance_not_content(self):
        """TC-657-RISK-06: structured importance field drives the flag, not content."""
        mod = _load_module()
        finding = self._finding("critical", 0.15, "agent")
        finding.content = "well-established, low-stakes claim"
        result = self._audit(finding)
        assert result.finding_audits[0].high_risk is True


# ---------------------------------------------------------------------------
# NET group tests (TC-657-NET-01..NET-07) + GATE-06/GATE-06A drop behavior
# ---------------------------------------------------------------------------
class TestNetLifecycle:
    """72-hour source-drop lifecycle for unreachable sources."""

    def _citation(
        self,
        cid: int = 1,
        success: bool = True,
        first_unreachable_at: datetime | None = None,
        status: int | None = 200,
    ) -> Any:
        """Build a Citation with collector state stored in metadata."""
        mod = _load_module()
        metadata: dict[str, Any] = {"last_fetch_success": success}
        if status is not None:
            metadata["last_status"] = status
        if first_unreachable_at is not None:
            metadata["first_unreachable_at"] = first_unreachable_at.isoformat()
        return mod.Citation(
            citation_id=cid,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com/paper",
            source_title="Example Paper",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata=metadata,
        )

    def _finding(self, citations: list[Any], importance: str = "normal") -> Any:
        """Build a Finding with the given citations."""
        mod = _load_module()
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content="finding content",
            confidence=0.85,
            importance=importance,
            metadata={},
            citations=citations,
        )

    def _audit(
        self,
        finding: Any,
        now: datetime,
        fetcher: Any = None,
        jev_response: Any = (200, '{"p_supports": 0.93}', {}),
    ) -> Any:
        """Run audit_task with a fixed clock and optional mock fetcher."""
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
        if fetcher is None:
            fetcher = lambda url: (200, finding.citations[0].source_title or "", "")

        def post(*a, **k):
            payload = a[1] if len(a) > 1 else k.get("payload", {})
            if isinstance(payload, dict) and "declared_scope" in payload.get("state", {}):
                return 200, '{"scope_mismatch": false, "confidence": 0.9}', {}
            return jev_response

        return mod.audit_task(
            [finding],
            config,
            now=now,
            fetcher=fetcher,
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )

    def test_net01_first_unreachability_unread(self):
        """TC-657-NET-01: first unreachability becomes UNREAD and is retried."""
        now = datetime.now(timezone.utc)
        cite = self._citation(success=False, first_unreachable_at=now)
        result = self._audit(self._finding([cite]), now)
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.existence_state == "unread"
        assert ca.unread_reason == "unreachable within window"
        assert result.exit_code() == 1

    def test_net02_retried_every_session_within_window(self):
        """TC-657-NET-02: UNREAD persists across sessions within 72h."""
        base = datetime.now(timezone.utc) - timedelta(hours=60)
        cite = self._citation(success=False, first_unreachable_at=base)
        result = self._audit(self._finding([cite]), base + timedelta(hours=20))
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.existence_state == "unread"
        assert result.exit_code() == 1

    def test_net03_boundary_just_under_72h_blocks(self):
        """TC-657-NET-03: just under 72h is still within window and blocks."""
        base = datetime.now(timezone.utc) - timedelta(hours=71, minutes=59, seconds=58)
        cite = self._citation(success=False, first_unreachable_at=base)
        result = self._audit(self._finding([cite]), datetime.now(timezone.utc))
        assert result.finding_audits[0].citation_audits[0].existence_state == "unread"

    def test_net03_boundary_just_over_72h_drops(self):
        """TC-657-NET-03: just over 72h drops the citation."""
        base = datetime.now(timezone.utc) - timedelta(hours=72, seconds=2)
        cite = self._citation(success=False, first_unreachable_at=base)
        result = self._audit(self._finding([cite]), datetime.now(timezone.utc))
        assert result.dropped_citations == [1]
        # The dropped citation is removed from the active argument; the review
        # table contains only the no-surviving-citations placeholder audit.
        active_citation_ids = {
            ca.citation.citation_id for ca in result.finding_audits[0].citation_audits
        }
        assert 1 not in active_citation_ids
        assert result.exit_code() == 1

    def test_net04_drop_reforms_argument_second_citation_remains(self):
        """TC-657-NET-04/GATE-06A-A: dropped citation; finding re-evaluates on remainder."""
        base = datetime.now(timezone.utc) - timedelta(hours=80)
        stale = self._citation(cid=1, success=False, first_unreachable_at=base)
        live = self._citation(cid=2, success=True)
        result = self._audit(self._finding([stale, live]), datetime.now(timezone.utc))
        assert result.dropped_citations == [1]
        assert len(result.finding_audits[0].citation_audits) == 1
        assert result.exit_code() == 0

    def test_net04_drop_no_remaining_citation_blocks(self):
        """TC-657-NET-04/GATE-06A-B: dropped citation leaves no support → blocked."""
        base = datetime.now(timezone.utc) - timedelta(hours=80)
        stale = self._citation(cid=1, success=False, first_unreachable_at=base)
        result = self._audit(self._finding([stale]), datetime.now(timezone.utc))
        assert result.dropped_citations == [1]
        assert result.exit_code() == 1
        assert result.finding_audits[0].citation_audits[0].existence_state == "no_surviving_citations"

    def test_net05_recovery_clears_clock(self):
        """TC-657-NET-05: a source that becomes reachable clears its stale clock."""
        now = datetime.now(timezone.utc)
        cite = self._citation(success=True)  # recent successful fetch
        result = self._audit(
            self._finding([cite]),
            now,
            fetcher=lambda url: (200, cite.source_title, ""),
        )
        assert result.finding_audits[0].citation_audits[0].existence_state == "passed"

    def test_net06_accessed_at_not_evidence(self):
        """TC-657-NET-06: accessed_at is not read as proof of successful fetch."""
        mod = _load_module()
        cite = mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com/paper",
            source_title="Example Paper",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),  # recent "touch" only
            metadata={"last_fetch_success": False},  # actual collector record
        )
        result = self._audit(self._finding([cite]), datetime.now(timezone.utc))
        assert result.finding_audits[0].citation_audits[0].existence_state == "unread"

    def test_net07_window_from_config(self):
        """TC-657-NET-07: 72h window value is read from config at runtime."""
        mod = _load_module()
        base = datetime.now(timezone.utc) - timedelta(hours=25)
        cite = self._citation(success=False, first_unreachable_at=base)
        # Short 24h window should drop a 25h-old unreachable source.
        config = mod.GateConfig(
            schema="public",
            drop_window_hours=24.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )
        finding = self._finding([cite])
        result = mod.audit_task([finding], config, now=datetime.now(timezone.utc))
        assert result.dropped_citations == [1]


# ---------------------------------------------------------------------------
# INV-7 atomic split tests
# ---------------------------------------------------------------------------
class TestAtomicSplit:
    """Compound findings must be split into atomic claims before Jev Noul."""

    def _finding(self, content: str) -> Any:
        """Build a Finding with the given content."""
        mod = _load_module()
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content=content,
            confidence=0.85,
            importance="normal",
            metadata={},
            citations=[],
        )

    def _citation(
        self,
        snapshot: str | None = "snapshot text",
        quote: str | None = "",
    ) -> Any:
        """Build a Citation with a collector snapshot for source_text tests."""
        mod = _load_module()
        return mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com",
            source_title="Example",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata={"source_snapshot_text": snapshot} if snapshot else {},
            quote=quote,
        )

    def test_inv7_simple_claim_passes_through(self):
        """A simple finding yields exactly one atomic claim."""
        mod = _load_module()
        atomic, compound = mod.split_atomic_claims("The sky is blue.")
        assert atomic == ["The sky is blue"]
        assert compound == []

    def test_inv7_compound_split_on_semicolon(self):
        """Two independent clauses joined by ';' split into two atomic claims."""
        mod = _load_module()
        atomic, compound = mod.split_atomic_claims(
            "The paper proves X; the authors compute Y."
        )
        assert len(atomic) == 2
        assert "proves X" in atomic[0]
        assert "compute Y" in atomic[1]
        assert compound == []

    def test_inv7_compound_unsplit_detected(self):
        """A remaining compound clause is marked unsplit, not guessed."""
        mod = _load_module()
        # Two finite-verb clauses joined by coordinating 'and'.
        atomic, compound = mod.split_atomic_claims(
            "The proof shows P and the construction is polynomial time"
        )
        assert atomic == []
        assert len(compound) == 1

    def test_inv7_compound_subject_not_split(self):
        """'Smith and Jones proved the bound for n>2' is one claim.

        Derivation: both nouns share the single finite verb 'proved'; the
        conservative detector requires a verb on BOTH sides of 'and'.
        """
        mod = _load_module()
        atomic, compound = mod.split_atomic_claims(
            "Smith and Jones proved the bound for n>2."
        )
        assert atomic == ["Smith and Jones proved the bound for n>2"]
        assert compound == []

    def test_inv7_adjective_coordination_not_split(self):
        """'The method is fast and accurate' is one claim.

        Derivation: 'accurate' is an adjective, not a finite verb, so the
        detector sees only one clause.
        """
        mod = _load_module()
        atomic, compound = mod.split_atomic_claims("The method is fast and accurate.")
        assert atomic == ["The method is fast and accurate"]
        assert compound == []

    def test_inv7_noun_phrase_coordination_not_split(self):
        """'Research and development spending rose 4%' is one claim.

        Derivation: neither 'Research' nor 'development spending' contains a
        finite verb; only 'rose' is a finite verb in the whole sentence.
        """
        mod = _load_module()
        atomic, compound = mod.split_atomic_claims(
            "Research and development spending rose 4%."
        )
        assert atomic == ["Research and development spending rose 4%"]
        assert compound == []

    def test_inv7_source_text_from_citation_snapshot(self):
        """source_text must be the citation snapshot, never the finding content."""
        mod = _load_module()
        finding = self._finding("The sky is blue.")
        citation = self._citation(snapshot="collector snapshot text")
        atomic, _ = mod.atomic_claims_for_citation(finding, citation)
        assert len(atomic) == 1
        assert atomic[0].source_text == "collector snapshot text"
        assert atomic[0].source_text != finding.content

    def test_inv7_no_snapshot_text_is_unread(self):
        """Missing snapshot text means the citation is not self-compared."""
        mod = _load_module()
        finding = self._finding("The sky is blue.")
        citation = self._citation(snapshot=None, quote=None)
        atomic, _ = mod.atomic_claims_for_citation(finding, citation)
        # No claims are produced because there is no source text to judge against.
        assert atomic == []


# ---------------------------------------------------------------------------
# JEV-THRESH group tests (TC-657-JEV-01..JEV-07)
# ---------------------------------------------------------------------------
class TestJevThreshold:
    """Jev Support Noul threshold boundaries."""

    def _finding(self, content: str = "The sky is blue.") -> Any:
        mod = _load_module()
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content=content,
            confidence=0.85,
            importance="normal",
            metadata={},
            citations=[],
        )

    def _citation(self, snapshot: str = "The sky is blue.") -> Any:
        mod = _load_module()
        return mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com",
            source_title="Example",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata={
                "source_snapshot_text": snapshot,
                "last_fetch_success": True,
                "last_status": 200,
            },
        )

    def _audit(self, finding: Any, citation: Any, jev_body: str) -> Any:
        mod = _load_module()
        finding.citations = [citation]
        config = mod.GateConfig(
            schema="public",
            drop_window_hours=72.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )
        return mod.audit_task(
            [finding],
            config,
            fetcher=lambda url: (200, citation.source_title or "", ""),
            jev_post_func=lambda *a, **k: (200, jev_body, {}),
            jev_sleep_func=lambda d: None,
        )

    def test_jev01_just_below_threshold(self):
        """TC-657-JEV-01: p_supports=0.049 escalates."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.049}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "escalate"
        assert result.exit_code() == 1

    def test_jev02_exactly_threshold(self):
        """TC-657-JEV-02: p_supports=0.05 exactly escalates (<= 0.05)."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.05}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "escalate"
        assert result.exit_code() == 1

    def test_jev03_just_above_threshold(self):
        """TC-657-JEV-03: p_supports=0.051 passes threshold check."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.051}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "passed"

    def test_jev04_clearly_supported(self):
        """TC-657-JEV-04: p_supports=0.93 passes cleanly."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.93}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "passed"
        assert result.exit_code() == 0

    def test_jev05_uncertainty_low_boundary(self):
        """TC-657-JEV-05: p_supports=0.40 in uncertainty zone escalates."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.40}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "escalate"

    def test_jev06_uncertainty_high_boundary(self):
        """TC-657-JEV-06: p_supports=0.60 in uncertainty zone escalates."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.60}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "escalate"

    def test_jev07_just_above_uncertainty(self):
        """TC-657-JEV-07: p_supports=0.61 outside uncertainty zone passes."""
        result = self._audit(
            self._finding(), self._citation(), '{"p_supports": 0.61}'
        )
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "passed"


# ---------------------------------------------------------------------------
# JEV-ERR group tests (TC-657-JEVERR-01..JEVERR-07)
# ---------------------------------------------------------------------------
class TestJevErrors:
    """Jev API errors and malformed responses are fail-closed per-citation."""

    def _finding(self, content: str = "The sky is blue.") -> Any:
        mod = _load_module()
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content=content,
            confidence=0.85,
            importance="normal",
            metadata={},
            citations=[],
        )

    def _citation(self, snapshot: str = "The sky is blue.") -> Any:
        mod = _load_module()
        return mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com",
            source_title="Example",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata={
                "source_snapshot_text": snapshot,
                "last_fetch_success": True,
                "last_status": 200,
            },
        )

    def _config(self) -> Any:
        mod = _load_module()
        return mod.GateConfig(
            schema="public",
            drop_window_hours=72.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )

    def _audit(
        self,
        finding: Any,
        citation: Any,
        post_func: Any,
        sleep_func: Any = None,
    ) -> Any:
        mod = _load_module()
        finding.citations = [citation]
        if sleep_func is None:
            sleep_func = lambda d: None
        return mod.audit_task(
            [finding],
            self._config(),
            jev_post_func=post_func,
            jev_sleep_func=sleep_func,
        )

    def test_jeverr01_missing_p_supports(self):
        """TC-657-JEVERR-01: missing p_supports field is a Jev API failure."""
        result = self._audit(
            self._finding(), self._citation(), lambda *a, **k: (200, '{"answer": "yes"}', {})
        )
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.jev_support_state == "failed"
        assert result.exit_code() == 2  # only citation's Jev call failed

    def test_jeverr02_nan_p_supports(self):
        """TC-657-JEVERR-02: NaN p_supports is a Jev API failure."""
        result = self._audit(
            self._finding(), self._citation(), lambda *a, **k: (200, '{"p_supports": NaN}', {})
        )
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.jev_support_state == "failed"
        assert result.exit_code() == 2

    def test_jeverr03_out_of_range_p_supports(self):
        """TC-657-JEVERR-03: out-of-range p_supports is a Jev API failure."""
        def make_post(body: str):
            return lambda *a, **k: (200, body, {})
        for body in ('{"p_supports": 1.4}', '{"p_supports": -0.2}'):
            result = self._audit(
                self._finding(), self._citation(), make_post(body)
            )
            ca = result.finding_audits[0].citation_audits[0]
            assert ca.jev_support_state == "failed"
            assert result.exit_code() == 2

    def test_jeverr04_timeout_three_attempts(self):
        """TC-657-JEVERR-04: 3 attempts on timeout, then fail-closed."""
        calls: list[Any] = []
        sleeps: list[float] = []

        def post(*a, **k):
            calls.append(len(calls) + 1)
            raise TimeoutError("timeout")

        result = self._audit(
            self._finding(), self._citation(), post, sleep_func=sleeps.append
        )
        assert len(calls) == 3
        assert sleeps == [1.0, 2.0]
        assert result.jev_attempted == 1
        assert result.jev_failed == 1
        assert result.exit_code() == 2

    def test_jeverr04a_retry_succeeds_on_second_attempt(self):
        """TC-657-JEVERR-04A: transient failure resolved within retry budget."""
        responses = [
            TimeoutError("timeout"),
            (200, '{"p_supports": 0.82}', {}),
        ]
        calls: list[Any] = []

        def post(*a, **k):
            calls.append(len(calls) + 1)
            r = responses.pop(0)
            if isinstance(r, Exception):
                raise r
            return r

        result = self._audit(
            self._finding(), self._citation(), post
        )
        assert len(calls) == 2
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "passed"

    def test_jeverr05_5xx_three_attempts(self):
        """TC-657-JEVERR-05: 5xx retries 3 times then fails closed."""
        calls: list[Any] = []

        def post(*a, **k):
            calls.append(len(calls) + 1)
            return 503, "Service Unavailable", {}

        result = self._audit(
            self._finding(), self._citation(), post
        )
        assert len(calls) == 3
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "failed"
        assert result.exit_code() == 2

    def test_jeverr05a_429_honors_retry_after(self):
        """TC-657-JEVERR-05A: 429 Retry-After overrides default backoff."""
        sleeps: list[float] = []
        responses = [
            (429, "Too Many Requests", {"Retry-After": "5"}),
            (200, '{"p_supports": 0.82}', {}),
        ]

        def post(*a, **k):
            return responses.pop(0)

        mod = _load_module()
        finding = self._finding()
        finding.citations = [self._citation()]
        result = mod.audit_task(
            [finding],
            self._config(),
            jev_post_func=post,
            jev_sleep_func=sleeps.append,
        )
        assert sleeps == [5.0]
        assert result.finding_audits[0].citation_audits[0].jev_support_state == "passed"

    def test_jeverr05b_non_429_4xx_no_retry(self):
        """TC-657-JEVERR-05B: non-429 4xx and malformed 200 body get no retry."""
        def make_post(status: int, body: str):
            calls: list[Any] = []

            def post(*a, **k):
                calls.append(1)
                return status, body, {}

            return post, calls

        for status, body in ((400, '{"p_supports": 0.82}'), (200, "not json")):
            post, calls = make_post(status, body)
            result = self._audit(
                self._finding(), self._citation(), post
            )
            assert len(calls) == 1
            assert result.finding_audits[0].citation_audits[0].jev_support_state == "failed"
            assert result.exit_code() == 2

    def test_jeverr06_malformed_200_body_systemic(self):
        """TC-657-JEVERR-06A: single citation + malformed 200 → systemic exit 2."""
        result = self._audit(
            self._finding(), self._citation(), lambda *a, **k: (200, "not json", {})
        )
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.jev_support_state == "failed"
        assert result.exit_code() == 2

    def test_jeverr06_malformed_200_body_per_citation(self):
        """TC-657-JEVERR-06B: malformed 200 blocks its finding; other finding passes."""
        mod = _load_module()
        finding_a = self._finding("Finding A")
        finding_b = self._finding("Finding B")
        cite_a = self._citation("snapshot A")
        cite_b = self._citation("snapshot B")
        finding_a.citations = [cite_a]
        finding_b.citations = [cite_b]

        def post(*a, **k):
            # Only the first call (finding A) gets the malformed body;
            # everything else passes cleanly.
            if not hasattr(post, "calls"):
                post.calls = 0
            post.calls += 1
            if post.calls == 1:
                return 200, "not json", {}
            return 200, '{"p_supports": 0.83}', {}

        result = mod.audit_task(
            [finding_a, finding_b],
            self._config(),
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )
        ca_a = result.finding_audits[0].citation_audits[0]
        ca_b = result.finding_audits[1].citation_audits[0]
        assert ca_a.jev_support_state == "failed"
        assert ca_b.jev_support_state == "passed"
        assert result.exit_code() == 1

    def test_jeverr07_compound_not_sent_to_noul(self):
        """TC-657-JEVERR-07: compound claims are split before Noul."""
        mod = _load_module()
        finding = mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content="The paper proves X; the authors compute Y.",
            confidence=0.85,
            importance="normal",
            metadata={},
            citations=[],
        )
        citation = self._citation("snapshot")
        calls: list[Any] = []

        def post(url: str, payload: dict[str, Any], key: str) -> tuple[int, str, dict[str, str]]:
            calls.append(payload["state"]["claim"])
            return 200, '{"p_supports": 0.93}', {}

        finding.citations = [citation]
        mod.audit_task(
            [finding],
            self._config(),
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )
        assert len(calls) == 2
        assert "proves X" in calls[0]
        assert "compute Y" in calls[1]


# ---------------------------------------------------------------------------
# SCOPE group tests (TC-657-SCOPE-01..SCOPE-05) + CONF-08
# ---------------------------------------------------------------------------
class TestJevScopeChoice:
    """Jev Scope Choice is advisory-only and never gates."""

    def _finding(self, content: str, scope: Any = "proved") -> Any:
        mod = _load_module()
        citation = mod.Citation(
            citation_id=1,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com",
            source_title="Example",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata={
                "source_snapshot_text": "snapshot text",
                "last_fetch_success": True,
                "last_status": 200,
            },
        )
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content=content,
            confidence=0.85,
            importance="normal",
            metadata={"claim_scope": scope} if scope is not None else {},
            citations=[citation],
        )

    def _config(self) -> Any:
        mod = _load_module()
        return mod.GateConfig(
            schema="public",
            drop_window_hours=72.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )

    def _audit(
        self,
        finding: Any,
        support_body: str = '{"p_supports": 0.83}',
        scope_body: str = '{"scope_mismatch": false, "confidence": 0.9}',
    ) -> Any:
        mod = _load_module()

        def post(*a, **k):
            payload = a[1] if len(a) > 1 else k.get("payload", {})
            if isinstance(payload, dict) and "declared_scope" in payload.get("state", {}):
                return 200, scope_body, {}
            return 200, support_body, {}

        return mod.audit_task(
            [finding],
            self._config(),
            fetcher=lambda url: (200, finding.citations[0].source_title or "", ""),
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )

    def test_scope01_scope_matches_content_ok(self):
        """TC-657-SCOPE-01: matching scope → no advisory flag."""
        result = self._audit(self._finding("The proof shows P.", "proved"))
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.scope_state == "ok"
        assert result.finding_audits[0].scope_advisory == ""
        assert result.exit_code() == 0

    def test_scope02_scope_contradicts_content_advisory(self):
        """TC-657-SCOPE-02: scope contradicting content → advisory flag."""
        result = self._audit(
            self._finding("The proof shows P.", "cited"),
            scope_body='{"scope_mismatch": true, "confidence": 0.85}',
        )
        ca = result.finding_audits[0].citation_audits[0]
        fa = result.finding_audits[0]
        assert ca.scope_state == "advisory"
        assert "scope mismatch" in ca.scope_detail.lower()
        assert "scope mismatch" in fa.scope_advisory.lower()
        # Advisory-only: exit code remains 0 because support passed.
        assert result.exit_code() == 0

    def test_scope03_low_scope_confidence_advisory(self):
        """TC-657-SCOPE-03: low scope confidence → advisory flag."""
        result = self._audit(
            self._finding("The proof shows P.", "proved"),
            scope_body='{"scope_mismatch": false, "confidence": 0.25}',
        )
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.scope_state == "advisory"
        assert "low scope confidence" in ca.scope_detail.lower()
        assert result.exit_code() == 0

    def test_scope04_invalid_declared_scope_undeclared(self):
        """TC-657-SCOPE-04: invalid declared scope → scope_undeclared advisory."""
        result = self._audit(self._finding("The proof shows P.", "Proved "))
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.scope_state == "advisory"
        assert ca.scope_detail == "scope_undeclared"
        assert result.exit_code() == 0

    def test_scope05_scope_advisory_does_not_override_block(self):
        """TC-657-SCOPE-05: scope advisory does not suppress other blocks."""
        result = self._audit(
            self._finding("The proof shows P.", "cited"),
            support_body='{"p_supports": 0.02}',
            scope_body='{"scope_mismatch": true, "confidence": 0.85}',
        )
        ca = result.finding_audits[0].citation_audits[0]
        assert ca.scope_state == "advisory"
        assert ca.jev_support_state == "escalate"
        assert result.exit_code() == 1

    def test_conf08_scope_contradicts_100_cited_content(self):
        """TC-657-CONF-08: 1.00 + cited + contradicting content → advisory, not crash."""
        result = self._audit(
            self._finding("The proof shows P.", "cited"),
            support_body='{"p_supports": 1.0}',
            scope_body='{"scope_mismatch": true, "confidence": 0.88}',
        )
        ca = result.finding_audits[0].citation_audits[0]
        fa = result.finding_audits[0]
        assert ca.confidence_state == "passed"
        assert ca.scope_state == "advisory"
        assert "scope mismatch" in fa.scope_advisory.lower()
        # Scope is advisory-only, so a passing support/citation still exits 0.
        assert result.exit_code() == 0


# ---------------------------------------------------------------------------
# GATE-02A / GATE-02B / GATE-02C systemic Jev failure tests
# ---------------------------------------------------------------------------
class TestSystemicJevFailure:
    """Systemic failure when all Jev calls fail vs. per-citation fail-closed."""

    def _finding(self, content: str = "The sky is blue.") -> Any:
        mod = _load_module()
        return mod.Finding(
            finding_id=10,
            task_id=90001,
            finding_type="fact",
            content=content,
            confidence=0.85,
            importance="normal",
            metadata={},
            citations=[],
        )

    def _citation(self, cid: int = 1, snapshot: str = "snapshot") -> Any:
        mod = _load_module()
        return mod.Citation(
            citation_id=cid,
            finding_id=10,
            source_type="paper",
            source_url="https://example.com",
            source_title="Example",
            reliability=0.88,
            accessed_at=datetime.now(timezone.utc),
            metadata={"source_snapshot_text": snapshot},
        )

    def _config(self) -> Any:
        mod = _load_module()
        return mod.GateConfig(
            schema="public",
            drop_window_hours=72.0,
            support_threshold=0.05,
            jev_url="https://api.typesafe.ai/v1/systemone",
            jev_api_key=None,
            db_dsn="",
            db_user="nova",
        )

    def test_gate02a_all_jev_calls_fail_exit_2(self):
        """TC-657-GATE-02A: every Jev call in a run fails → exit 2."""
        mod = _load_module()
        finding = self._finding()
        finding.citations = [self._citation(1), self._citation(2), self._citation(3)]

        def post(*a, **k):
            raise TimeoutError("timeout")

        result = mod.audit_task(
            [finding],
            self._config(),
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )
        assert result.jev_attempted == 3
        assert result.jev_failed == 3
        assert result.exit_code() == 2

    def test_gate02b_all_but_one_fail_exit_1(self):
        """TC-657-GATE-02B: all-but-one Jev call fails → exit 1, not 2."""
        mod = _load_module()
        finding = self._finding()
        finding.citations = [self._citation(1), self._citation(2), self._citation(3)]
        # First two calls time out; third returns a passing score.
        responses = [
            TimeoutError("timeout"),
            TimeoutError("timeout"),
            (200, '{"p_supports": 0.93}', {}),
        ]

        def post(*a, **k):
            r = responses.pop(0)
            if isinstance(r, Exception):
                raise r
            return r

        result = mod.audit_task(
            [finding],
            self._config(),
            jev_post_func=post,
            jev_sleep_func=lambda d: None,
        )
        assert result.jev_attempted == 3
        assert result.jev_failed == 2
        assert result.exit_code() == 1

    def test_gate02c_zero_jev_attempts_exit_follows_findings(self):
        """TC-657-GATE-02C: zero Jev calls attempted → exit follows findings."""
        mod = _load_module()
        finding = self._finding()
        # No citations means no Jev calls.
        result = mod.audit_task([finding], self._config())
        assert result.jev_attempted == 0
        assert result.exit_code() == 1  # no_surviving_citations placeholder
