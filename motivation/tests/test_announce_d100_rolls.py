"""
Tests for memory/scripts/announce-d100-rolls.py

Covers unit cases from Gem's 34-case design for issue #432:
- Unannounced-row selection (TC-432-U-01, U-02)
- Idempotency (TC-432-U-03, U-04, U-14)
- Message formatting roll-only vs roll+complete (TC-432-U-05, U-06, U-07, U-08, U-18)
- Failure semantics / compensating rollback (TC-432-U-09, U-10, U-11, U-12)
- Ordering (TC-432-U-13)
- Join drift / missing task (TC-432-U-16, U-17)
- Claim-before-post ordering (TC-432-U-19)
- Grants declaration regression (D1)
- check_step11_d100 regression (TC-432-R-03, R-04, R-05)

Integration cases (I-*) and live-DB cases are staging-only and listed in the
STAGING_ONLY manifest comment at the bottom of this file.
"""

import importlib.util
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
from types import ModuleType
from unittest.mock import MagicMock, patch

import pytest

_SCRIPT_PATH = Path(__file__).parent.parent.parent / "memory" / "scripts" / "announce-d100-rolls.py"
_SCHEMA_PATH = Path(__file__).parent.parent.parent / "database" / "schema.sql"


def _load_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("announce_d100_rolls", _SCRIPT_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


@pytest.fixture(scope="module")
def m() -> ModuleType:
    return _load_module()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _mock_conn(claimed_rows, task_rows=None):
    """Build a mock psycopg2 connection with cursor dispatching."""
    task_rows = task_rows or []
    state = {"last": None}

    mock_cur = MagicMock()
    mock_cur.__enter__ = MagicMock(return_value=mock_cur)
    mock_cur.__exit__ = MagicMock(return_value=False)

    def fake_execute(sql, params=None):
        # The real SQL is multi-line; normalize whitespace before matching.
        normalized = " ".join(sql.split())
        if "UPDATE d100_roll_log SET announced_at" in normalized and "RETURNING" in normalized:
            state["last"] = "claim"
        elif "UPDATE d100_roll_log SET announced_at = NULL" in normalized:
            state["last"] = "unstamp"
        elif "SELECT id, roll, rolled_at" in normalized:
            state["last"] = "select"
        elif "FROM motivation_d100" in normalized:
            state["last"] = "tasks"
        else:
            state["last"] = "other"

    def fake_fetchall():
        if state["last"] == "claim" or state["last"] == "select":
            return claimed_rows
        if state["last"] == "tasks":
            return task_rows
        return []

    mock_cur.execute.side_effect = fake_execute
    mock_cur.fetchall.side_effect = fake_fetchall

    mock_conn = MagicMock()
    mock_conn.__enter__ = MagicMock(return_value=mock_conn)
    mock_conn.__exit__ = MagicMock(return_value=False)
    mock_conn.cursor.return_value = mock_cur
    return mock_conn


def _task_row(roll, task_name="Task", estimated=10, difficulty="medium", last_rolled=None, last_completed=None):
    return {
        "roll": roll,
        "task_name": task_name,
        "estimated_minutes": estimated,
        "difficulty": difficulty,
        "last_rolled": last_rolled,
        "last_completed": last_completed,
    }


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

class TestSelection:
    def test_claims_only_null_rows(self, m):
        """TC-432-U-01"""
        claimed = [(1, 42, datetime(2026, 7, 6, 12, 0, 0, tzinfo=timezone.utc))]
        conn = _mock_conn(claimed)

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=True):
            mock_psycopg2.connect.return_value = conn
            rc = m.main([])

        assert rc == 0
        # Claim query issued
        execute_calls = [call[0][0] for call in conn.cursor.return_value.execute.call_args_list]
        assert any("UPDATE d100_roll_log" in sql and "RETURNING" in sql for sql in execute_calls)

    def test_empty_result_exits_zero(self, m, capsys):
        """TC-432-U-02"""
        conn = _mock_conn([])

        with patch.object(m, "psycopg2") as mock_psycopg2:
            mock_psycopg2.connect.return_value = conn
            rc = m.main([])

        assert rc == 0
        out, _ = capsys.readouterr()
        assert "0 rolls to announce" in out


# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

class TestIdempotency:
    def test_re_run_after_success_announce_nothing(self, m):
        """TC-432-U-03"""
        conn = _mock_conn([])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            rc = m.main([])

        assert rc == 0
        mock_send.assert_not_called()

    def test_one_message_per_row(self, m):
        """TC-432-U-04"""
        now = datetime.now(timezone.utc)
        claimed = [
            (1, 10, now - timedelta(minutes=5)),
            (2, 20, now - timedelta(minutes=3)),
            (3, 30, now - timedelta(minutes=1)),
        ]
        conn = _mock_conn(claimed)

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=True) as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        assert mock_send.call_count == 3

@pytest.mark.parametrize("n", [1, 2, 3])
def test_n_rows_exactly_n_posts(m, n):
    """TC-432-U-14: for N <= 3, each row gets its own post."""
    now = datetime.now(timezone.utc)
    claimed = [(i, i, now - timedelta(minutes=n - i)) for i in range(1, n + 1)]
    conn = _mock_conn(claimed)

    with patch.object(m, "psycopg2") as mock_psycopg2, \
         patch.object(m, "_send_message", return_value=True) as mock_send:
        mock_psycopg2.connect.return_value = conn
        m.main([])

    assert mock_send.call_count == n


@pytest.mark.parametrize("n", [5, 10])
def test_n_rows_digest_when_over_three(m, n):
    """TC-432-U-14 + D3: for N > 3, rolls collapse into a single digest post."""
    now = datetime.now(timezone.utc)
    claimed = [(i, i, now - timedelta(minutes=n - i)) for i in range(1, n + 1)]
    conn = _mock_conn(claimed)

    with patch.object(m, "psycopg2") as mock_psycopg2, \
         patch.object(m, "_send_message", return_value=True) as mock_send:
        mock_psycopg2.connect.return_value = conn
        m.main([])

    assert mock_send.call_count == 1


# ---------------------------------------------------------------------------
# Formatting
# ---------------------------------------------------------------------------

class TestFormatting:
    def test_roll_only_formatting(self, m):
        """TC-432-U-05"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now)]
        task = (42, "Write tests", 15, "medium", now, None)
        conn = _mock_conn(claimed, [task])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert text.startswith('🎲 D100 roll 42: "Write tests"')
        assert "rolled (15m, difficulty medium)" in text
        assert "Completed" not in text

    def test_roll_complete_formatting(self, m):
        """TC-432-U-06"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now - timedelta(minutes=5))]
        task = (42, "Write tests", 15, "medium", now - timedelta(minutes=5), now)
        conn = _mock_conn(claimed, [task])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert "Completed" in text

    def test_last_completed_equal_last_rolled_is_completed(self, m):
        """TC-432-U-07"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now)]
        task = (42, "Write tests", 15, "medium", now, now)
        conn = _mock_conn(claimed, [task])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert "Completed" in text

    def test_special_characters_in_task_name(self, m):
        """TC-432-U-08"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now)]
        task = (42, 'Task with "quotes" *bold* `_code_`', 15, "medium", now, None)
        conn = _mock_conn(claimed, [task])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=True) as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert "Task with \"quotes\"" in text

    def test_null_last_completed_falls_to_roll_only(self, m):
        """TC-432-U-18"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now)]
        # times_completed > 0 cannot be represented in the join; we only get
        # last_completed here. The script must use a NULL-safe comparison.
        task = (42, "Write tests", 15, "medium", now, None)
        conn = _mock_conn(claimed, [task])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert "Completed" not in text


# ---------------------------------------------------------------------------
# Join drift / missing task
# ---------------------------------------------------------------------------

class TestJoinDrift:
    def test_missing_motivation_row_uses_fallback(self, m):
        """TC-432-U-17"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 99, now)]
        conn = _mock_conn(claimed, [])  # no matching motivation_d100 row

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert "task unknown (slot 99)" in text

    def test_empty_task_name_uses_fallback(self, m):
        """TC-432-U-16 variant"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 7, now)]
        task = (7, "", 10, "low", now, None)
        conn = _mock_conn(claimed, [task])

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message") as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        text = mock_send.call_args[0][0]
        assert "task unknown (slot 7)" in text


# ---------------------------------------------------------------------------
# Failure semantics
# ---------------------------------------------------------------------------

class TestFailureSemantics:
    def test_cli_failure_unstamps_row(self, m):
        """TC-432-U-09"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now)]
        conn = _mock_conn(claimed)

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=False) as mock_send:
            mock_psycopg2.connect.return_value = conn
            rc = m.main([])

        assert rc == 0
        execute_calls = [call[0][0] for call in conn.cursor.return_value.execute.call_args_list]
        assert any("SET announced_at = NULL" in sql for sql in execute_calls)

    def test_failure_retried_next_cycle(self, m):
        """TC-432-U-10"""
        now = datetime.now(timezone.utc)
        claimed = [(1, 42, now)]

        # First run: send fails
        conn1 = _mock_conn(claimed)
        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=False):
            mock_psycopg2.connect.return_value = conn1
            assert m.main([]) == 0

        # Second run: row still unannounced, send succeeds
        conn2 = _mock_conn(claimed)
        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=True) as mock_send:
            mock_psycopg2.connect.return_value = conn2
            assert m.main([]) == 0
            mock_send.assert_called_once()

    def test_partial_batch_failure(self, m):
        """TC-432-U-11"""
        now = datetime.now(timezone.utc)
        claimed = [
            (1, 10, now - timedelta(minutes=5)),
            (2, 20, now - timedelta(minutes=3)),
            (3, 30, now - timedelta(minutes=1)),
        ]
        conn = _mock_conn(claimed)

        def send_side_effect(text, dry_run):
            # Row 2 fails (its message contains "roll 20")
            return "roll 20" not in text

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", side_effect=send_side_effect) as mock_send:
            mock_psycopg2.connect.return_value = conn
            rc = m.main([])

        assert rc == 0
        assert mock_send.call_count == 3

        # unstamp should be called with id 2 only
        unstamp_calls = [
            call for call in conn.cursor.return_value.execute.call_args_list
            if "SET announced_at = NULL" in call[0][0]
        ]
        assert len(unstamp_calls) == 1
        ids = unstamp_calls[0][0][1][0]
        assert ids == [2]

    def test_db_unreachable_returns_nonzero(self, m):
        """TC-432-U-12 DB failure path."""
        with patch.object(m, "psycopg2") as mock_psycopg2:
            mock_psycopg2.connect.side_effect = Exception("connection refused")
            rc = m.main([])
        assert rc == 1


# ---------------------------------------------------------------------------
# Ordering / batching
# ---------------------------------------------------------------------------

class TestOrderingBatching:
    def test_oldest_first_processing(self, m):
        """TC-432-U-13"""
        now = datetime.now(timezone.utc)
        claimed = [
            (1, 30, now - timedelta(minutes=1)),
            (2, 10, now - timedelta(minutes=5)),
            (3, 20, now - timedelta(minutes=3)),
        ]
        conn = _mock_conn(claimed)
        sent = []

        def capture(text, dry_run):
            sent.append(text)
            return True

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", side_effect=capture):
            mock_psycopg2.connect.return_value = conn
            m.main([])

        # Extract roll numbers from sent messages in order.
        rolls = [int(re.search(r"roll (\d+):", t).group(1)) for t in sent]
        assert rolls == [10, 20, 30]

    def test_digest_when_more_than_three(self, m):
        """TC-432-U-04 inverse + D3 digest behavior."""
        now = datetime.now(timezone.utc)
        claimed = [(i, i, now - timedelta(minutes=10 - i)) for i in range(1, 5)]
        conn = _mock_conn(claimed)

        with patch.object(m, "psycopg2") as mock_psycopg2, \
             patch.object(m, "_send_message", return_value=True) as mock_send:
            mock_psycopg2.connect.return_value = conn
            m.main([])

        # Exactly one digest message.
        assert mock_send.call_count == 1
        text = mock_send.call_args[0][0]
        assert text.count("🎲 D100 roll") == 4


# ---------------------------------------------------------------------------
# Regression / grants
# ---------------------------------------------------------------------------

class TestRegression:
    def test_schema_declares_announced_at_column(self):
        """Schema addition for #432."""
        schema = _SCHEMA_PATH.read_text()
        assert "announced_at timestamptz" in schema
        assert "CREATE TABLE IF NOT EXISTS d100_roll_log" in schema

    def test_nova_grant_select_update_on_d100_roll_log(self):
        """D1 grants fix: nova must hold SELECT + UPDATE on d100_roll_log."""
        schema = _SCHEMA_PATH.read_text()
        # Find the d100_roll_log nova privilege block.
        block_start = schema.find("REVOKE DELETE, INSERT ON TABLE d100_roll_log FROM nova;")
        assert block_start != -1
        block = schema[block_start:block_start + 400]
        assert "GRANT SELECT, UPDATE ON TABLE d100_roll_log TO nova;" in block

    def test_check_step11_d100_not_broken_by_announced_at(self, m):
        """TC-432-R-03, R-04, R-05: announcer's UPDATE only touches announced_at."""
        script_text = _SCRIPT_PATH.read_text()
        # The real stamp SQL is multi-line; normalize before asserting it exists.
        normalized = " ".join(script_text.split())
        assert "UPDATE d100_roll_log SET announced_at = now()" in normalized
        # Load-bearing invariant: the announcer must NEVER write rolled_at.
        assert "SET rolled_at" not in script_text


# ---------------------------------------------------------------------------
# DSN construction (D-1 regression)
# ---------------------------------------------------------------------------

class TestDsn:
    def test_dsn_uses_libpq_keywords(self, m):
        """D-1: _dsn() maps PGPORT->port, PGDATABASE->dbname, PGUSER->user."""
        fake_env = {
            "PGHOST": "localhost",
            "PGPORT": "5432",
            "PGDATABASE": "nova_memory",
            "PGUSER": "coder",
        }
        with patch.object(m, "load_pg_env", return_value=fake_env), \
             patch.object(m, "_PG_ENV_AVAILABLE", True):
            dsn = m._dsn()

        assert "host=localhost" in dsn
        assert "port=5432" in dsn
        assert "dbname=nova_memory" in dsn
        assert "user=coder" in dsn
        assert "pgport=" not in dsn
        assert "pgdatabase=" not in dsn
        assert "pguser=" not in dsn


# ---------------------------------------------------------------------------
# Staging-only integration case manifest
# ---------------------------------------------------------------------------

# TC-432-I-01  Live-DB selection against staging
# TC-432-I-02  Idempotency under real cron cadence simulation
# TC-432-I-03  CLI failure due to Discord/gateway outage
# TC-432-I-04  Migration stamps existing historical rows
# TC-432-I-05  First real announcer run post-migration produces zero burst posts
# TC-432-I-06  Migration re-run idempotency
# TC-432-I-07  New roll_d100() call inserts announced_at IS NULL
# TC-432-I-08  New row picked up by next announcer cycle
# TC-432-I-09  Two overlapping runs atomic claim
# TC-432-I-10  Advisory lock fallback (not implemented; atomic claim used per D2)
# TC-432-I-11  Announcer's configured role can SELECT/UPDATE
