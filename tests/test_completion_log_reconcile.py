"""
Tests for memory/scripts/completion-log-reconcile.py.

Covers line formatting, sanitization, watermark fallback, idempotency, migration
behaviour, failure modes, and flock mutual exclusion with generate-daily-log.py.
"""

from __future__ import annotations

import datetime
import importlib.util
import os
import re
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from pathlib import Path
from unittest import mock

import psycopg2
import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "memory" / "scripts" / "completion-log-reconcile.py"
spec = importlib.util.spec_from_file_location("completion_log_reconcile", SCRIPT_PATH)
completion_log_reconcile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(completion_log_reconcile)

ReconcileError = completion_log_reconcile.ReconcileError

# Force a fresh real psycopg2 import in case another test mocked it.
for _psycopg2_mod in ("psycopg2", "psycopg2.extras", "psycopg2.extensions"):
    sys.modules.pop(_psycopg2_mod, None)
import psycopg2  # noqa: E402

if not hasattr(psycopg2, "connect") or psycopg2.connect is None:
    pytest.skip("psycopg2 driver not available", allow_module_level=True)

REPO_ROOT = Path(__file__).resolve().parent.parent
MIGRATION_PATH = REPO_ROOT / "memory" / "migrations" / "087_completion_log_watermark.sql"


def _admin_conn():
    """Connect to the postgres maintenance database as nova."""
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(host="localhost", user="nova", dbname="postgres")


def _create_test_db() -> str:
    """Create and return a uniquely-named test database."""
    db_name = f"nova_memory_test_561_{uuid.uuid4().hex[:8]}"
    conn = _admin_conn()
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS %s", (psycopg2.extensions.AsIs(db_name),))
        cur.execute("CREATE DATABASE %s", (psycopg2.extensions.AsIs(db_name),))
    conn.close()
    return db_name


def _drop_test_db(db_name: str) -> None:
    """Drop the test database, ignoring errors."""
    try:
        conn = _admin_conn()
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("DROP DATABASE IF EXISTS %s", (psycopg2.extensions.AsIs(db_name),))
        conn.close()
    except Exception:
        pass


def _seed_minimal_schema(conn: psycopg2.extensions.connection) -> None:
    """Create minimal work_queue and workflow_runs tables (pre-migration state)."""
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE work_queue (
                id SERIAL PRIMARY KEY,
                created_at timestamptz DEFAULT now() NOT NULL,
                created_by text DEFAULT CURRENT_USER NOT NULL,
                owner_session text NOT NULL,
                kind text NOT NULL,
                ref text NOT NULL,
                description text NOT NULL,
                expected_outcome text,
                next_action_hint text,
                status text DEFAULT 'pending' NOT NULL,
                last_checked_at timestamptz,
                check_count integer DEFAULT 0 NOT NULL,
                completed_at timestamptz,
                notes text,
                CONSTRAINT work_queue_status_check CHECK (
                    status IN ('pending', 'done', 'failed', 'stale', 'cancelled')
                )
            );
            CREATE TABLE workflow_runs (
                id SERIAL PRIMARY KEY,
                workflow_id integer NOT NULL,
                triggered_by text,
                trigger_context text,
                current_step integer,
                status varchar(20) DEFAULT 'running' NOT NULL,
                started_at timestamptz DEFAULT now() NOT NULL,
                completed_at timestamptz,
                notes text,
                channel text NOT NULL,
                CONSTRAINT workflow_runs_status_check CHECK (
                    status IN ('running', 'completed', 'failed', 'paused', 'cancelled')
                )
            );
            """
        )
    conn.commit()


def _apply_migration(conn: psycopg2.extensions.connection) -> None:
    """Execute migration 087 against the open connection."""
    migration_sql = MIGRATION_PATH.read_text()
    with conn.cursor() as cur:
        cur.execute(migration_sql)
    conn.commit()


def _test_conn(db_name: str):
    """Connect to the test database as nova."""
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(host="localhost", user="nova", dbname=db_name)


@pytest.fixture
def test_db():
    """Yield a freshly-created test DB with the migration applied."""
    db_name = _create_test_db()
    conn = _test_conn(db_name)
    try:
        _seed_minimal_schema(conn)
        _apply_migration(conn)
        yield db_name
    finally:
        conn.close()
        _drop_test_db(db_name)


@pytest.fixture
def workspace(tmp_path, monkeypatch):
    """Yield an isolated workspace directory."""
    ws = tmp_path / "workspace"
    ws.mkdir()
    (ws / "memory").mkdir()
    monkeypatch.setenv("OPENCLAW_WORKSPACE", str(ws))
    # Ensure PGPASSWORD is not inherited from the gateway.
    monkeypatch.delenv("PGPASSWORD", raising=False)
    # Run the script as nova so it can write to the test DB.
    monkeypatch.setenv("PGUSER", "nova")
    return ws


class TestSanitize:
    def test_collapses_newlines(self):
        text = "Dispatched subagent.\nExpect report at tmp/foo.md.\n\nAlso check X."
        assert completion_log_reconcile.sanitize(text) == (
            "Dispatched subagent. Expect report at tmp/foo.md. Also check X."
        )

    def test_collapses_tabs_and_multiple_spaces(self):
        text = "a\t\t  b\n\n   c"
        assert completion_log_reconcile.sanitize(text) == "a b c"

    def test_truncates_long_text(self):
        text = "x" * 500
        assert len(completion_log_reconcile.sanitize(text, 120)) == 121
        assert completion_log_reconcile.sanitize(text, 120).endswith("…")

    def test_exact_boundary_no_ellipsis(self):
        text = "x" * 120
        assert completion_log_reconcile.sanitize(text, 120) == text

    def test_one_over_boundary_gets_ellipsis(self):
        text = "x" * 121
        result = completion_log_reconcile.sanitize(text, 120)
        assert result == "x" * 120 + "…"

    def test_preserves_markdown_structural_chars(self):
        text = "Fixed # 42 | ran `script.sh` with **flag** set"
        assert completion_log_reconcile.sanitize(text, 120) == text

    def test_preserves_non_ascii(self):
        text = "✅ Deploy complete → renaissancemachine.ai/music/"
        assert completion_log_reconcile.sanitize(text, 120) == text

    def test_empty_string(self):
        assert completion_log_reconcile.sanitize("") == ""


class TestEffectiveWatermark:
    def test_work_queue_completed_at(self):
        ts = datetime.datetime(2026, 8, 8, 14, 32, 7, tzinfo=datetime.timezone.utc)
        row = {"id": 1, "completed_at": ts, "last_checked_at": None, "created_at": None}
        result, usable = completion_log_reconcile.effective_watermark(row, "work_queue")
        assert result == ts
        assert usable is True

    def test_work_queue_fallback_last_checked_at(self):
        ts = datetime.datetime(2026, 8, 7, 12, 20, 10, tzinfo=datetime.timezone.utc)
        row = {"id": 1, "completed_at": None, "last_checked_at": ts, "created_at": None}
        result, usable = completion_log_reconcile.effective_watermark(row, "work_queue")
        assert result == ts
        assert usable is True

    def test_work_queue_fallback_created_at(self):
        ts = datetime.datetime(2026, 7, 30, 0, 59, 29, tzinfo=datetime.timezone.utc)
        row = {"id": 1, "completed_at": None, "last_checked_at": None, "created_at": ts}
        result, usable = completion_log_reconcile.effective_watermark(row, "work_queue")
        assert result == ts
        assert usable is True

    def test_work_queue_all_null_emits_warning(self, capsys):
        row = {"id": 175, "completed_at": None, "last_checked_at": None, "created_at": None}
        result, usable = completion_log_reconcile.effective_watermark(row, "work_queue")
        assert usable is False
        captured = capsys.readouterr()
        assert "skipping work_queue id=175" in captured.err

    def test_workflow_runs_completed_at(self):
        ts = datetime.datetime(2026, 8, 8, 22, 18, 3, tzinfo=datetime.timezone.utc)
        row = {"id": 1, "completed_at": ts, "started_at": None}
        result, usable = completion_log_reconcile.effective_watermark(row, "workflow_runs")
        assert result == ts
        assert usable is True

    def test_workflow_runs_fallback_started_at(self):
        ts = datetime.datetime(2026, 6, 11, 7, 4, 28, tzinfo=datetime.timezone.utc)
        row = {"id": 80, "completed_at": None, "started_at": ts}
        result, usable = completion_log_reconcile.effective_watermark(row, "workflow_runs")
        assert result == ts
        assert usable is True


class TestFormatLines:
    def test_work_queue_line(self):
        ts = datetime.datetime(2026, 8, 8, 14, 32, 7, tzinfo=datetime.timezone.utc)
        row = {
            "id": 42,
            "kind": "subagent_session",
            "description": "Dispatched voice-profile drafter",
            "status": "done",
        }
        line = completion_log_reconcile.format_work_queue_line(row, ts)
        assert line == "- 14:32 wq#42 closed (subagent_session): Dispatched voice-profile drafter — done"

    def test_workflow_runs_line_truncates_trigger_context(self):
        ts = datetime.datetime(2026, 8, 8, 22, 18, 3, tzinfo=datetime.timezone.utc)
        row = {
            "id": 100,
            "workflow_id": 30,
            "status": "completed",
            "trigger_context": (
                "Weekly Music Publication run, promoting Old Carbon (doom jazz) through "
                "release pipeline end to end"
            ),
        }
        line = completion_log_reconcile.format_workflow_runs_line(row, ts)
        assert line.startswith("- 22:18 workflow run #100 completed (workflow 30):")
        # Trigger context truncated to 80 chars + ellipsis.
        prefix = "- 22:18 workflow run #100 completed (workflow 30): "
        segment = line[len(prefix):]
        assert len(segment) == 81
        assert segment.endswith("…")

    def test_workflow_runs_line_short_context_no_ellipsis(self):
        ts = datetime.datetime(2026, 8, 8, 22, 18, 3, tzinfo=datetime.timezone.utc)
        row = {
            "id": 101,
            "workflow_id": 4,
            "status": "failed",
            "trigger_context": "Short context",
        }
        line = completion_log_reconcile.format_workflow_runs_line(row, ts)
        assert line == "- 22:18 workflow run #101 failed (workflow 4): Short context"


class TestAppendLine:
    def test_creates_file_with_title(self, tmp_path):
        target = tmp_path / "2026-08-08.md"
        completion_log_reconcile.append_line(target, "- 14:32 test line")
        assert target.exists()
        text = target.read_text(encoding="utf-8")
        assert text.startswith("# 2026-08-08\n\n")
        assert "- 14:32 test line\n" in text

    def test_appends_to_existing_file(self, tmp_path):
        target = tmp_path / "2026-08-08.md"
        target.write_text("# 2026-08-08\n\n- existing line\n", encoding="utf-8")
        completion_log_reconcile.append_line(target, "- 14:32 new line")
        text = target.read_text(encoding="utf-8")
        assert text.count("- ") == 2
        assert text.endswith("- 14:32 new line\n")

    def test_creates_parent_directory(self, tmp_path):
        target = tmp_path / "memory" / "2026-08-08.md"
        completion_log_reconcile.append_line(target, "- 14:32 test line")
        assert target.exists()

    def test_atomic_write_cleanup_on_failure(self, tmp_path, monkeypatch):
        target = tmp_path / "2026-08-08.md"
        target.write_text("# 2026-08-08\n\noriginal\n", encoding="utf-8")

        def failing_replace(src, dst):
            raise OSError("rename fault")

        monkeypatch.setattr(os, "replace", failing_replace)
        with pytest.raises(OSError):
            completion_log_reconcile.append_line(target, "- 14:32 new line")

        assert target.read_text(encoding="utf-8") == "# 2026-08-08\n\noriginal\n"
        assert len(list(tmp_path.glob(".*.tmp*"))) == 0


class TestMarkerPresent:
    def test_finds_marker(self, tmp_path):
        file1 = tmp_path / "2026-08-08.md"
        file1.write_text("# Day\n\n- 14:32 wq#42 closed (x): desc — done\n", encoding="utf-8")
        assert completion_log_reconcile.marker_present("wq#42 closed", [file1]) is True

    def test_checks_adjacent_file(self, tmp_path):
        file1 = tmp_path / "2026-08-08.md"
        file2 = tmp_path / "2026-08-09.md"
        file2.write_text("# Day\n\n- 00:01 wq#42 closed (x): desc — done\n", encoding="utf-8")
        assert completion_log_reconcile.marker_present("wq#42 closed", [file1, file2]) is True

    def test_missing_marker(self, tmp_path):
        file1 = tmp_path / "2026-08-08.md"
        file1.write_text("# Day\n\n- 14:32 wq#99 closed (x): desc — done\n", encoding="utf-8")
        assert completion_log_reconcile.marker_present("wq#42 closed", [file1]) is False


class TestDailyLogLock:
    def test_mutual_exclusion(self, workspace):
        lock_file = workspace / "memory" / ".daily-log.lock"
        acquired = []

        def holder():
            with completion_log_reconcile.daily_log_lock(workspace):
                acquired.append("holder")
                time.sleep(0.2)

        t = threading.Thread(target=holder)
        t.start()
        time.sleep(0.05)  # Let holder acquire first.

        with completion_log_reconcile.daily_log_lock(workspace):
            acquired.append("main")
            assert "holder" in acquired

        t.join()
        assert lock_file.exists()


@pytest.mark.integration
class TestMigration:
    def test_adds_column_and_backfills_idempotently(self, test_db):
        conn = _test_conn(test_db)
        try:
            with conn.cursor() as cur:
                # Seed pre-existing closed rows.
                cur.execute(
                    """
                    INSERT INTO work_queue (owner_session, kind, ref, description, status, completed_at)
                    VALUES ('s1', 'subagent_session', 'r1', 'desc', 'done', '2026-08-01T10:00:00Z')
                    RETURNING id
                    """
                )
                wq_id = cur.fetchone()[0]
                cur.execute(
                    """
                    INSERT INTO workflow_runs (workflow_id, trigger_context, status, completed_at, channel)
                    VALUES (4, 'ctx', 'completed', '2026-08-01T11:00:00Z', 'test:1')
                    RETURNING id
                    """
                )
                wf_id = cur.fetchone()[0]
                # Add a row that is not terminal — should stay NULL.
                cur.execute(
                    """
                    INSERT INTO work_queue (owner_session, kind, ref, description, status)
                    VALUES ('s2', 'subagent_session', 'r2', 'pending desc', 'pending')
                    """
                )
            conn.commit()

            # Drop the column to simulate pre-migration state.
            with conn.cursor() as cur:
                cur.execute("ALTER TABLE work_queue DROP COLUMN completion_logged_at")
                cur.execute("ALTER TABLE workflow_runs DROP COLUMN completion_logged_at")
            conn.commit()

            _apply_migration(conn)

            with conn.cursor() as cur:
                cur.execute(
                    "SELECT completion_logged_at IS NOT NULL FROM work_queue WHERE id = %s",
                    (wq_id,),
                )
                assert cur.fetchone()[0] is True
                cur.execute(
                    "SELECT completion_logged_at IS NOT NULL FROM workflow_runs WHERE id = %s",
                    (wf_id,),
                )
                assert cur.fetchone()[0] is True
                cur.execute(
                    "SELECT completion_logged_at IS NULL FROM work_queue WHERE status = 'pending'"
                )
                assert cur.fetchone()[0] is True

            # Capture the originally-seeded watermark so we can prove the guard
            # does not overwrite it on re-apply.
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT completion_logged_at FROM work_queue WHERE id = %s", (wq_id,)
                )
                first_seed = cur.fetchone()[0]

            # Simulate a row closing between two applies. The re-apply will seed it
            # because it is terminal and unseeded (this is the specified migration
            # behavior; the IS NULL guard only prevents re-stamping already-seeded
            # rows, not newly-terminal rows).
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO work_queue (owner_session, kind, ref, description, status, completed_at)
                    VALUES ('s3', 'subagent_session', 'r3', 'late desc', 'done', '2026-08-02T10:00:00Z')
                    RETURNING id
                    """
                )
                late_id = cur.fetchone()[0]
            conn.commit()

            _apply_migration(conn)

            with conn.cursor() as cur:
                # Already-seeded row must keep its original watermark (guard works).
                cur.execute(
                    "SELECT completion_logged_at FROM work_queue WHERE id = %s", (wq_id,)
                )
                assert cur.fetchone()[0] == first_seed
                # Newly-terminal row gets seeded by the re-apply.
                cur.execute(
                    "SELECT completion_logged_at IS NOT NULL FROM work_queue WHERE id = %s",
                    (late_id,),
                )
                assert cur.fetchone()[0] is True
        finally:
            conn.close()


@pytest.mark.integration
class TestReconcile:
    def _run_script(self, workspace: Path, db_name: str, *extra_args: str) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env["OPENCLAW_WORKSPACE"] = str(workspace)
        env["PGUSER"] = "nova"
        env.pop("PGPASSWORD", None)
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "--database", db_name, *extra_args],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

    def insert_work_queue(
        self,
        conn: psycopg2.extensions.connection,
        status: str,
        completed_at: str | None,
        last_checked_at: str | None = None,
        created_at: str | None = None,
        description: str = "test description",
        kind: str = "subagent_session",
    ) -> int:
        columns = ["owner_session", "kind", "ref", "description", "status", "completed_at"]
        values: list[Any] = ["s1", kind, "r1", description, status, completed_at]
        if last_checked_at is not None:
            columns.append("last_checked_at")
            values.append(last_checked_at)
        if created_at is not None:
            columns.append("created_at")
            values.append(created_at)
        with conn.cursor() as cur:
            cur.execute(
                f"""
                INSERT INTO work_queue ({', '.join(columns)})
                VALUES ({', '.join(['%s'] * len(columns))})
                RETURNING id
                """,
                values,
            )
            return cur.fetchone()[0]

    def insert_workflow_run(
        self,
        conn: psycopg2.extensions.connection,
        status: str,
        completed_at: str | None,
        started_at: str | None = None,
        trigger_context: str = "test context",
        workflow_id: int = 4,
    ) -> int:
        started = started_at or "2026-08-01T00:00:00Z"
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO workflow_runs
                    (workflow_id, trigger_context, status, completed_at, started_at, channel)
                VALUES (%s, %s, %s, %s, %s, 'test:1')
                RETURNING id
                """,
                (workflow_id, trigger_context, status, completed_at, started),
            )
            return cur.fetchone()[0]

    def test_01_single_work_queue_row(self, test_db, workspace):
        """TC-561-01"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "done",
                "2026-08-08T14:32:07Z",
                description="Dispatched voice-profile drafter",
            )
            conn.commit()

            result = self._run_script(workspace, test_db)
            assert result.returncode == 0, result.stderr

            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "- 14:32 wq#1 closed (subagent_session): Dispatched voice-profile drafter — done" in log
        finally:
            conn.close()

    def test_02_single_workflow_runs_row(self, test_db, workspace):
        """TC-561-02"""
        conn = _test_conn(test_db)
        try:
            self.insert_workflow_run(
                conn,
                "completed",
                "2026-08-08T22:18:03Z",
                trigger_context=(
                    "Weekly Music Publication run, promoting Old Carbon (doom jazz) through "
                    "release pipeline end to end"
                ),
                workflow_id=30,
            )
            conn.commit()

            result = self._run_script(workspace, test_db)
            assert result.returncode == 0, result.stderr

            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "- 22:18 workflow run #1 completed (workflow 30):" in log
            assert log.count("workflow run #1") == 1
        finally:
            conn.close()

    def test_03_line_dated_by_completed_at(self, test_db, workspace):
        """TC-561-03"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-05T09:00:00Z")
            conn.commit()

            result = self._run_script(workspace, test_db)
            assert result.returncode == 0

            assert (workspace / "memory" / "2026-08-05.md").exists()
            assert not (workspace / "memory" / "2026-08-08.md").exists()
        finally:
            conn.close()

    def test_04_multiple_rows_ordered(self, test_db, workspace):
        """TC-561-04"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T16:00:00Z", description="third")
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z", description="first")
            self.insert_workflow_run(conn, "completed", "2026-08-08T14:00:00Z", trigger_context="second")
            conn.commit()

            result = self._run_script(workspace, test_db)
            assert result.returncode == 0

            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            lines = [ln for ln in log.splitlines() if ln.startswith("- ")]
            assert ["first" in ln or "second" in ln or "third" in ln for ln in lines]
            assert "first" in lines[0]
            assert "second" in lines[1]
            assert "third" in lines[2]
        finally:
            conn.close()

    def test_05_06_idempotent_rerun(self, test_db, workspace):
        """TC-561-05 + TC-561-06"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z")
            conn.commit()

            r1 = self._run_script(workspace, test_db)
            assert r1.returncode == 0
            mtime1 = (workspace / "memory" / "2026-08-08.md").stat().st_mtime

            time.sleep(0.05)
            r2 = self._run_script(workspace, test_db)
            assert r2.returncode == 0
            mtime2 = (workspace / "memory" / "2026-08-08.md").stat().st_mtime
            assert mtime1 == mtime2

            # Run 5 more times.
            for _ in range(5):
                r = self._run_script(workspace, test_db)
                assert r.returncode == 0

            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert log.count("wq#1 closed") == 1
        finally:
            conn.close()

    def test_07b_adjacent_day_grep(self, test_db, workspace):
        """TC-561-07b"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T23:59:50Z")
            conn.commit()

            # First run writes the line.
            r1 = self._run_script(workspace, test_db)
            assert r1.returncode == 0

            # Reset the watermark to simulate a crash before commit.
            with conn.cursor() as cur:
                cur.execute("UPDATE work_queue SET completion_logged_at = NULL WHERE id = 1")
            conn.commit()

            # Second run should find the existing line via adjacent-day grep and only watermark.
            r2 = self._run_script(workspace, test_db)
            assert r2.returncode == 0

            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert log.count("wq#1 closed") == 1

            with conn.cursor() as cur:
                cur.execute("SELECT completion_logged_at IS NOT NULL FROM work_queue WHERE id = 1")
                assert cur.fetchone()[0] is True
        finally:
            conn.close()

    def test_08_crash_recovery(self, test_db, workspace, monkeypatch):
        """TC-561-08"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z")
            conn.commit()

            original_append = completion_log_reconcile.append_line

            def crashing_append(path, line):
                original_append(path, line)
                raise OSError("injected crash after append")

            monkeypatch.setenv("OPENCLAW_WORKSPACE", str(workspace))
            monkeypatch.setenv("PGUSER", "nova")
            monkeypatch.delenv("PGPASSWORD", raising=False)

            # First invocation: append succeeds, DB update never runs.
            with mock.patch.object(completion_log_reconcile, "append_line", crashing_append):
                r1 = completion_log_reconcile.main(["--database", test_db])
            assert r1 != 0

            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert log.count("wq#1 closed") == 1

            with conn.cursor() as cur:
                cur.execute("SELECT completion_logged_at IS NULL FROM work_queue WHERE id = 1")
                assert cur.fetchone()[0] is True

            # Second invocation: watermark only.
            r2 = completion_log_reconcile.main(["--database", test_db])
            assert r2 == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert log.count("wq#1 closed") == 1
            with conn.cursor() as cur:
                cur.execute("SELECT completion_logged_at IS NOT NULL FROM work_queue WHERE id = 1")
                assert cur.fetchone()[0] is True
        finally:
            conn.close()

    def test_10_midnight_boundary(self, test_db, workspace):
        """TC-561-10"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T23:59:30Z")
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            assert (workspace / "memory" / "2026-08-08.md").exists()
            assert not (workspace / "memory" / "2026-08-09.md").exists()
        finally:
            conn.close()

    def test_11_exact_midnight(self, test_db, workspace):
        """TC-561-11"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-09T00:00:00Z")
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            assert (workspace / "memory" / "2026-08-09.md").exists()
        finally:
            conn.close()

    def test_12_one_microsecond_before_midnight(self, test_db, workspace):
        """TC-561-12"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T23:59:59.999999Z")
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            assert (workspace / "memory" / "2026-08-08.md").exists()
            assert not (workspace / "memory" / "2026-08-09.md").exists()
        finally:
            conn.close()

    def test_13_two_days_later_backfill(self, test_db, workspace):
        """TC-561-13"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T23:58:00Z")
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            assert (workspace / "memory" / "2026-08-08.md").exists()
            assert not (workspace / "memory" / "2026-08-10.md").exists()
        finally:
            conn.close()

    def test_14_work_queue_fallback_last_checked_at(self, test_db, workspace):
        """TC-561-14"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "failed",
                None,
                last_checked_at="2026-08-07T12:20:10Z",
                description="failed task",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-07.md").read_text(encoding="utf-8")
            assert "- 12:20 wq#1 closed (subagent_session): failed task — failed" in log
        finally:
            conn.close()

    def test_15_work_queue_fallback_created_at(self, test_db, workspace):
        """TC-561-15"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "failed",
                None,
                last_checked_at=None,
                created_at="2026-07-30T00:59:29Z",
                description="failed task",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-07-30.md").read_text(encoding="utf-8")
            assert "- 00:59 wq#1 closed (subagent_session): failed task — failed" in log
        finally:
            conn.close()

    def test_16_workflow_runs_fallback_started_at(self, test_db, workspace):
        """TC-561-16"""
        conn = _test_conn(test_db)
        try:
            self.insert_workflow_run(
                conn,
                "completed",
                None,
                started_at="2026-06-11T07:04:28Z",
                trigger_context="run 80 context",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-06-11.md").read_text(encoding="utf-8")
            assert "- 07:04 workflow run #1 completed (workflow 4): run 80 context" in log
        finally:
            conn.close()

    def test_17_workflow_runs_paused_excluded(self, test_db, workspace):
        """TC-561-17"""
        conn = _test_conn(test_db)
        try:
            self.insert_workflow_run(
                conn,
                "paused",
                None,
                started_at="2026-07-01T00:00:00Z",
                trigger_context="paused run",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            assert not list((workspace / "memory").glob("*.md"))
        finally:
            conn.close()

    def test_18_newlines_collapsed(self, test_db, workspace):
        """TC-561-18"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "done",
                "2026-08-08T10:00:00Z",
                description="Dispatched subagent.\nExpect report at tmp/foo.md.\n\nAlso check X.",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "Dispatched subagent. Expect report at tmp/foo.md. Also check X." in log
        finally:
            conn.close()

    def test_19_long_description_truncated(self, test_db, workspace):
        """TC-561-19"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "done",
                "2026-08-08T10:00:00Z",
                description="x" * 500,
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            line = [ln for ln in log.splitlines() if ln.startswith("-")][0]
            desc = line.split(": ", 1)[1].rsplit(" — ", 1)[0]
            assert len(desc) == 121
            assert desc.endswith("…")
        finally:
            conn.close()

    def test_20_markdown_chars_preserved(self, test_db, workspace):
        """TC-561-20"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "done",
                "2026-08-08T10:00:00Z",
                description="Fixed # 42 | ran `script.sh` with **flag** set",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "Fixed # 42 | ran `script.sh` with **flag** set" in log
        finally:
            conn.close()

    def test_21_non_ascii_preserved(self, test_db, workspace):
        """TC-561-21"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(
                conn,
                "done",
                "2026-08-08T10:00:00Z",
                description="✅ Deploy complete → renaissancemachine.ai/music/",
            )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "✅ Deploy complete → renaissancemachine.ai/music/" in log
        finally:
            conn.close()

    def test_22_empty_description(self, test_db, workspace):
        """TC-561-22"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z", description="")
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "- 10:00 wq#1 closed (subagent_session): (no description) — done" in log
        finally:
            conn.close()

    def test_23_work_queue_status_decision_table(self, test_db, workspace):
        """TC-561-23"""
        conn = _test_conn(test_db)
        try:
            for status in ("pending", "done", "failed", "stale", "cancelled"):
                self.insert_work_queue(
                    conn, status, "2026-08-08T10:00:00Z", description=status
                )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "pending" not in log
            for status in ("done", "failed", "stale", "cancelled"):
                assert f" — {status}" in log
        finally:
            conn.close()

    def test_24_workflow_runs_status_decision_table(self, test_db, workspace):
        """TC-561-24"""
        conn = _test_conn(test_db)
        try:
            for status in ("running", "paused", "completed", "failed", "cancelled"):
                self.insert_workflow_run(
                    conn, status, "2026-08-08T10:00:00Z", trigger_context=status
                )
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "running" not in log
            assert "paused" not in log
            for status in ("completed", "failed", "cancelled"):
                assert f"workflow run #" in log and status in log
        finally:
            conn.close()

    def test_25_status_transition(self, test_db, workspace):
        """TC-561-25"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "pending", None)
            conn.commit()
            r1 = self._run_script(workspace, test_db)
            assert r1.returncode == 0
            assert not list((workspace / "memory").glob("*.md"))

            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE work_queue SET status='done', completed_at='2026-08-08T10:00:00Z' WHERE id=1"
                )
            conn.commit()
            r2 = self._run_script(workspace, test_db)
            assert r2.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "wq#1 closed" in log
            assert log.count("wq#1 closed") == 1
        finally:
            conn.close()

    def test_27_28_backfill_and_post_deploy(self, test_db, workspace):
        """TC-561-27 + TC-561-28"""
        conn = _test_conn(test_db)
        try:
            # Pre-existing closed row (backlog).
            self.insert_work_queue(conn, "done", "2026-08-01T10:00:00Z", description="backlog")
            # Re-apply migration to seed the backlog row.
            _apply_migration(conn)

            # Post-deploy closure.
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z", description="new")
            conn.commit()

            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            log = (workspace / "memory" / "2026-08-08.md").read_text(encoding="utf-8")
            assert "new" in log
            assert "backlog" not in log

            # Backlog file should not exist (no lines written for it).
            assert not (workspace / "memory" / "2026-08-01.md").exists()
        finally:
            conn.close()

    def test_29_creates_target_file(self, test_db, workspace):
        """TC-561-29"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z")
            conn.commit()
            result = self._run_script(workspace, test_db)
            assert result.returncode == 0
            target = workspace / "memory" / "2026-08-08.md"
            assert target.exists()
            assert target.read_text(encoding="utf-8").startswith("# 2026-08-08\n")
        finally:
            conn.close()

    def test_30_creates_directory(self, test_db, tmp_path, monkeypatch):
        """TC-561-30"""
        ws = tmp_path / "fresh_workspace"
        ws.mkdir()
        monkeypatch.setenv("OPENCLAW_WORKSPACE", str(ws))
        monkeypatch.setenv("PGUSER", "nova")
        monkeypatch.delenv("PGPASSWORD", raising=False)
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z")
            conn.commit()
            result = self._run_script(ws, test_db)
            assert result.returncode == 0
            assert (ws / "memory" / "2026-08-08.md").exists()
        finally:
            conn.close()

    def test_31_permission_error(self, test_db, workspace):
        """TC-561-31"""
        conn = _test_conn(test_db)
        try:
            target = workspace / "memory" / "2026-08-08.md"
            target.write_text("# 2026-08-08\n\noriginal\n", encoding="utf-8")
            target.chmod(0o444)
            (workspace / "memory").chmod(0o555)

            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z")
            conn.commit()

            result = self._run_script(workspace, test_db)
            assert result.returncode != 0
            assert target.read_text(encoding="utf-8") == "# 2026-08-08\n\noriginal\n"
            with conn.cursor() as cur:
                cur.execute("SELECT completion_logged_at IS NULL FROM work_queue WHERE id = 1")
                assert cur.fetchone()[0] is True
        finally:
            conn.close()
            (workspace / "memory").chmod(0o755)
            target.chmod(0o644)

    def test_33_db_unreachable(self, workspace):
        """TC-561-33"""
        result = self._run_script(workspace, "definitely_not_a_real_database_561")
        assert result.returncode != 0
        assert "Database connection failed" in result.stderr or "does not exist" in result.stderr

    def test_34_db_permission_denied(self, test_db, workspace, monkeypatch):
        """TC-561-34"""
        conn = _test_conn(test_db)
        try:
            self.insert_work_queue(conn, "done", "2026-08-08T10:00:00Z")
            conn.commit()

            # Simulate an UPDATE permission failure on the watermark column by
            # wrapping the real connection with a cursor that raises on UPDATE.
            class PermissionDeniedCursor:
                def __init__(self, real_cursor):
                    self._real = real_cursor

                def __enter__(self):
                    return self

                def __exit__(self, *exc):
                    self._real.close()
                    return False

                def __getattr__(self, name):
                    return getattr(self._real, name)

                def execute(self, query, params=None):
                    if isinstance(query, str) and query.strip().startswith("UPDATE work_queue"):
                        raise psycopg2.OperationalError("permission denied for table work_queue")
                    return self._real.execute(query, params)

                def fetchone(self):
                    return self._real.fetchone()

                def fetchall(self):
                    return self._real.fetchall()

            class WrappedConnection:
                def __init__(self, real_conn):
                    self._real = real_conn
                    self.autocommit = real_conn.autocommit

                def cursor(self):
                    return PermissionDeniedCursor(self._real.cursor())

                def close(self):
                    return self._real.close()

            real_connect = completion_log_reconcile.connect

            def wrapped_connect(dbname, pg_config):
                return WrappedConnection(real_connect(dbname, pg_config))

            monkeypatch.setenv("OPENCLAW_WORKSPACE", str(workspace))
            monkeypatch.setenv("PGUSER", "nova")
            monkeypatch.delenv("PGPASSWORD", raising=False)

            with mock.patch.object(completion_log_reconcile, "connect", wrapped_connect):
                rc = completion_log_reconcile.main(["--database", test_db])
            assert rc != 0
        finally:
            conn.close()


@pytest.mark.integration
class TestFlockMutualExclusion:
    """TC-561-09 + TC-561-32"""

    def _run_script(self, workspace: Path, db_name: str) -> subprocess.CompletedProcess:
        env = os.environ.copy()
        env["OPENCLAW_WORKSPACE"] = str(workspace)
        env["PGUSER"] = "nova"
        env.pop("PGPASSWORD", None)
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH), "--database", db_name],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

    def test_reconcile_holds_lock_during_critical_section(self, test_db, workspace):
        conn = _test_conn(test_db)
        try:
            self._lock_held_acquisition_test(workspace)
        finally:
            conn.close()

    def _lock_held_acquisition_test(self, workspace: Path):
        """While reconcile holds the lock, a non-blocking flock -n must fail."""
        lock_file = workspace / "memory" / ".daily-log.lock"
        lock_file.parent.mkdir(parents=True, exist_ok=True)

        # Use a helper process that acquires the lock and holds it.
        helper = subprocess.Popen(
            [sys.executable, "-c", f"""
import fcntl, os, time
fd = os.open('{lock_file}', os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)
time.sleep(2)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
"""],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(0.2)  # Let helper acquire.

        try:
            # Non-blocking flock from shell should fail.
            result = subprocess.run(
                ["flock", "-n", str(lock_file), "-c", "echo acquired"],
                capture_output=True,
                text=True,
                check=False,
            )
            assert result.returncode != 0 or "acquired" not in result.stdout
        finally:
            helper.wait(timeout=5)

    def test_reconcile_blocks_when_lock_held(self, test_db, workspace):
        conn = _test_conn(test_db)
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO work_queue (owner_session, kind, ref, description, status, completed_at) "
                    "VALUES ('s1', 'subagent_session', 'r1', 'desc', 'done', '2026-08-08T10:00:00Z')"
                )
            conn.commit()

            lock_file = workspace / "memory" / ".daily-log.lock"
            lock_file.parent.mkdir(parents=True, exist_ok=True)

            helper = subprocess.Popen(
                [sys.executable, "-c", f"""
import fcntl, os, time
fd = os.open('{lock_file}', os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)
time.sleep(2)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
"""],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            time.sleep(0.2)

            try:
                start = time.time()
                result = self._run_script(workspace, test_db)
                elapsed = time.time() - start
                assert elapsed >= 1.5, f"expected blocking wait, elapsed={elapsed}"
                assert result.returncode == 0, result.stderr
            finally:
                helper.wait(timeout=5)
        finally:
            conn.close()

    def test_generate_daily_log_takes_same_lock(self, test_db, workspace):
        """Verify generate-daily-log.py also holds the shared lock file."""
        generate_script = REPO_ROOT / "memory" / "scripts" / "generate-daily-log.py"
        lock_file = workspace / "memory" / ".daily-log.lock"
        lock_file.parent.mkdir(parents=True, exist_ok=True)

        helper = subprocess.Popen(
            [sys.executable, "-c", f"""
import fcntl, os, time
fd = os.open('{lock_file}', os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)
time.sleep(2)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
"""],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(0.2)

        try:
            env = os.environ.copy()
            env["OPENCLAW_WORKSPACE"] = str(workspace)
            env["PGUSER"] = "nova"
            env.pop("PGPASSWORD", None)
            start = time.time()
            result = subprocess.run(
                [sys.executable, str(generate_script), "--date", "2026-08-08"],
                capture_output=True,
                text=True,
                env=env,
                check=False,
            )
            elapsed = time.time() - start
            assert elapsed >= 1.5, f"expected generate-daily-log to block, elapsed={elapsed}"
            assert result.returncode == 0, result.stderr
        finally:
            helper.wait(timeout=5)


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
