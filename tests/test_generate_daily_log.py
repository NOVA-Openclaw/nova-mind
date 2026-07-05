"""
Tests for memory/scripts/generate-daily-log.py.

Covers marker handling, file preservation, idempotency, date validation,
multi-tenant paths, PGPASSWORD hygiene, and integration with live DBs.
"""

from __future__ import annotations

import argparse
import datetime
import importlib.util
import io
import os
import sys
import tempfile
import time
from pathlib import Path
from unittest import mock

import psycopg2
import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "memory" / "scripts" / "generate-daily-log.py"
spec = importlib.util.spec_from_file_location("generate_daily_log", SCRIPT_PATH)
generate_daily_log = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generate_daily_log)

DailyLogError = generate_daily_log.DailyLogError
BEGIN_MARKER_PREFIX = generate_daily_log.BEGIN_MARKER_PREFIX
END_MARKER = generate_daily_log.END_MARKER


class TestValidateDate:
    def test_accepts_valid_past_date(self):
        assert generate_daily_log.validate_date("2026-05-15") == datetime.date(2026, 5, 15)

    def test_accepts_today(self):
        today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        assert generate_daily_log.validate_date(today) == datetime.date.fromisoformat(today)

    def test_rejects_future_date(self):
        future = (datetime.datetime.now(datetime.timezone.utc).date() + datetime.timedelta(days=7)).isoformat()
        with pytest.raises(SystemExit):
            # argparse exits via SystemExit, not ArgumentTypeError directly in some paths
            try:
                generate_daily_log.validate_date(future)
            except argparse.ArgumentTypeError:
                raise SystemExit

    def test_rejects_malformed_date(self):
        for bad in ["07/05/2026", "2026-13-45", "today", "", "2026-7-5"]:
            with pytest.raises((SystemExit, argparse.ArgumentTypeError)):
                generate_daily_log.validate_date(bad)


class TestResolveWorkspace:
    def test_env_var_takes_precedence(self, tmp_path, monkeypatch):
        monkeypatch.setenv("OPENCLAW_WORKSPACE", str(tmp_path))
        assert generate_daily_log.resolve_workspace() == tmp_path.resolve()

    def test_openclaw_agent_id_resolves_workspace_xyz(self, tmp_path, monkeypatch):
        monkeypatch.delenv("OPENCLAW_WORKSPACE", raising=False)
        monkeypatch.setenv("OPENCLAW_AGENT_ID", "xyz")
        home = tmp_path / "home"
        workspace = home / ".openclaw" / "workspace-xyz"
        workspace.mkdir(parents=True)
        monkeypatch.setenv("HOME", str(home))
        assert generate_daily_log.resolve_workspace() == workspace.resolve()

    def test_stray_workspace_coder_is_ignored_without_agent_id(self, tmp_path, monkeypatch):
        monkeypatch.delenv("OPENCLAW_WORKSPACE", raising=False)
        monkeypatch.delenv("OPENCLAW_AGENT_ID", raising=False)
        home = tmp_path / "home"
        stray = home / ".openclaw" / "workspace-coder"
        stray.mkdir(parents=True)
        fallback = home / ".openclaw" / "workspace"
        fallback.mkdir(parents=True)
        monkeypatch.setenv("HOME", str(home))
        assert generate_daily_log.resolve_workspace() == fallback.resolve()

    def test_falls_back_to_workspace(self, tmp_path, monkeypatch):
        monkeypatch.delenv("OPENCLAW_WORKSPACE", raising=False)
        home = tmp_path / "home"
        workspace = home / ".openclaw" / "workspace"
        workspace.mkdir(parents=True)
        monkeypatch.setenv("HOME", str(home))
        assert generate_daily_log.resolve_workspace() == workspace.resolve()

    def test_error_when_no_workspace_found(self, tmp_path, monkeypatch):
        monkeypatch.delenv("OPENCLAW_WORKSPACE", raising=False)
        home = tmp_path / "home"
        home.mkdir(parents=True)
        monkeypatch.setenv("HOME", str(home))
        with pytest.raises(DailyLogError):
            generate_daily_log.resolve_workspace()


class TestLoadPostgresConfig:
    def test_reads_host_port_database_only(self, tmp_path, monkeypatch):
        home = tmp_path / "home"
        config_path = home / ".openclaw" / "postgres.json"
        config_path.parent.mkdir(parents=True)
        config_path.write_text(
            '{"host": "db.example.com", "port": 5433, "database": "testdb", "user": "testuser", "password": "SECRET"}'
        )
        monkeypatch.setenv("HOME", str(home))
        cfg = generate_daily_log.load_postgres_config()
        assert cfg == {"host": "db.example.com", "port": 5433, "database": "testdb"}

    def test_error_on_missing_key(self, tmp_path, monkeypatch):
        home = tmp_path / "home"
        config_path = home / ".openclaw" / "postgres.json"
        config_path.parent.mkdir(parents=True)
        config_path.write_text('{"host": "localhost", "port": 5432}')
        monkeypatch.setenv("HOME", str(home))
        with pytest.raises(DailyLogError):
            generate_daily_log.load_postgres_config()


class TestConnectPGPASSWORD:
    def test_drops_pgpassword_before_connect(self, monkeypatch):
        monkeypatch.setenv("PGPASSWORD", "wrong-password")
        captured: dict = {}

        def fake_connect(*, host, port, database, user):
            captured["pgpassword_in_os"] = "PGPASSWORD" in os.environ
            captured["pgpassword_value"] = os.environ.get("PGPASSWORD")
            raise psycopg2.OperationalError("simulated failure")

        monkeypatch.setattr(psycopg2, "connect", fake_connect)
        with pytest.raises(DailyLogError):
            generate_daily_log.connect("testdb", {"host": "localhost", "port": 5432, "database": "testdb"})
        assert captured["pgpassword_in_os"] is False
        assert captured["pgpassword_value"] is None


class TestFindMarkers:
    def test_no_markers(self):
        assert generate_daily_log.find_markers("# 2026-07-05\n\nSome narrative\n") == (-1, -1)

    def test_valid_marker_pair(self):
        content = f"# Day\n{BEGIN_MARKER_PREFIX} -- generated_at: X -->\ntext\n{END_MARKER}\nmore\n"
        assert generate_daily_log.find_markers(content) == (1, 3)

    def test_begin_without_end(self):
        content = f"# Day\n{BEGIN_MARKER_PREFIX} -->\ntext\n"
        with pytest.raises(DailyLogError):
            generate_daily_log.find_markers(content)

    def test_end_without_begin(self):
        content = f"# Day\ntext\n{END_MARKER}\n"
        with pytest.raises(DailyLogError):
            generate_daily_log.find_markers(content)

    def test_duplicate_markers(self):
        content = f"{BEGIN_MARKER_PREFIX} -->\na\n{END_MARKER}\n{BEGIN_MARKER_PREFIX} -->\nb\n{END_MARKER}\n"
        with pytest.raises(DailyLogError):
            generate_daily_log.find_markers(content)

    def test_begin_after_end(self):
        content = f"{END_MARKER}\n{BEGIN_MARKER_PREFIX} -->\n"
        with pytest.raises(DailyLogError):
            generate_daily_log.find_markers(content)


class TestBlocksEqual:
    def test_equal_ignoring_generated_at(self):
        a = f"{BEGIN_MARKER_PREFIX} — generated_at: 2026-07-05T10:00:00Z -->\ntext\n{END_MARKER}\n"
        b = f"{BEGIN_MARKER_PREFIX} — generated_at: 2026-07-05T11:00:00Z -->\ntext\n{END_MARKER}\n"
        assert generate_daily_log.blocks_equal(a, b) is True

    def test_different_content_not_equal(self):
        a = f"{BEGIN_MARKER_PREFIX} — generated_at: X -->\ntext\n{END_MARKER}\n"
        b = f"{BEGIN_MARKER_PREFIX} — generated_at: X -->\nother\n{END_MARKER}\n"
        assert generate_daily_log.blocks_equal(a, b) is False

    def test_different_lengths_not_equal(self):
        a = f"{BEGIN_MARKER_PREFIX} -->\ntext\n{END_MARKER}\n"
        b = f"{BEGIN_MARKER_PREFIX} -->\ntext\nmore\n{END_MARKER}\n"
        assert generate_daily_log.blocks_equal(a, b) is False


class TestUpdateFile:
    def test_creates_new_file(self, tmp_path):
        target = tmp_path / "2026-07-05.md"
        block = f"{BEGIN_MARKER_PREFIX} -->\ncontent\n{END_MARKER}\n"
        assert generate_daily_log.update_file(target, block) is True
        assert target.exists()
        assert target.read_text().startswith("# 2026-07-05\n")
        assert block in target.read_text()

    def test_replaces_existing_block(self, tmp_path):
        target = tmp_path / "2026-07-05.md"
        original = f"# 2026-07-05\n\n{BEGIN_MARKER_PREFIX} -->\nold\n{END_MARKER}\n\nNarrative after\n"
        target.write_text(original)
        new_block = f"{BEGIN_MARKER_PREFIX} -->\nnew\n{END_MARKER}\n"
        assert generate_daily_log.update_file(target, new_block) is True
        text = target.read_text()
        assert "new" in text
        assert "old" not in text
        assert "Narrative after" in text

    def test_appends_when_no_markers(self, tmp_path):
        target = tmp_path / "2026-07-05.md"
        original = "# 2026-07-05\n\nHand-written narrative\n"
        target.write_text(original)
        block = f"{BEGIN_MARKER_PREFIX} -->\ncontent\n{END_MARKER}\n"
        assert generate_daily_log.update_file(target, block) is True
        text = target.read_text()
        assert text.startswith("# 2026-07-05\n")
        assert "Hand-written narrative" in text
        assert block in text

    def test_preserves_narrative_above_and_below(self, tmp_path):
        target = tmp_path / "2026-07-05.md"
        original = f"# 2026-07-05\nAbove\n\n{BEGIN_MARKER_PREFIX} -->\nold\n{END_MARKER}\n\nBelow\n"
        target.write_text(original)
        new_block = f"{BEGIN_MARKER_PREFIX} -->\nnew\n{END_MARKER}\n"
        assert generate_daily_log.update_file(target, new_block) is True
        text = target.read_text()
        assert "Above" in text
        assert "Below" in text
        assert "old" not in text
        assert "new" in text

    def test_idempotent_noop(self, tmp_path):
        target = tmp_path / "2026-07-05.md"
        block_a = f"{BEGIN_MARKER_PREFIX} — generated_at: 2026-07-05T10:00:00Z -->\ncontent\n{END_MARKER}\n"
        generate_daily_log.update_file(target, block_a)
        mtime_before = target.stat().st_mtime
        time.sleep(0.05)
        block_b = f"{BEGIN_MARKER_PREFIX} — generated_at: 2026-07-05T11:00:00Z -->\ncontent\n{END_MARKER}\n"
        assert generate_daily_log.update_file(target, block_b) is False
        mtime_after = target.stat().st_mtime
        assert mtime_after == mtime_before

    def test_preserves_non_ascii_and_whitespace(self, tmp_path):
        target = tmp_path / "2026-07-05.md"
        narrative = "# 2026-07-05\n✅ keep trailing   \n→ em-dash\n"
        target.write_text(narrative)
        block = f"{BEGIN_MARKER_PREFIX} -->\ncontent\n{END_MARKER}\n"
        generate_daily_log.update_file(target, block)
        preserved = target.read_text()
        assert "✅ keep trailing   \n" in preserved
        assert "→ em-dash" in preserved

    def test_atomic_write_does_not_corrupt_on_rename_fault(self, tmp_path, monkeypatch):
        target = tmp_path / "2026-07-05.md"
        original = "# 2026-07-05\nNarrative\n"
        target.write_text(original)

        calls = []

        def failing_replace(src, dst):
            calls.append((src, dst))
            raise OSError("rename fault")

        monkeypatch.setattr(os, "replace", failing_replace)
        block = f"{BEGIN_MARKER_PREFIX} -->\ncontent\n{END_MARKER}\n"
        with pytest.raises(OSError):
            generate_daily_log.update_file(target, block)

        assert target.read_text() == original
        # Temp file should have been cleaned up.
        assert len(list(tmp_path.glob(".*.tmp*"))) == 0


@pytest.mark.integration
class TestIntegration:
    """Tests requiring live nova_memory and agent_chat databases."""

    @pytest.fixture(scope="class")
    def pg_config(self):
        cfg = generate_daily_log.load_postgres_config()
        # Verify connections work and PGPASSWORD is not required.
        os.environ.pop("PGPASSWORD", None)
        for db in [cfg["database"], "agent_chat"]:
            conn = generate_daily_log.connect(db, cfg)
            conn.close()
        return cfg

    def test_dry_run_does_not_write(self, tmp_path, monkeypatch, pg_config):
        monkeypatch.setenv("OPENCLAW_WORKSPACE", str(tmp_path))
        target = tmp_path / "memory" / "2026-01-01.md"
        with mock.patch("sys.stdout", new_callable=io.StringIO):
            rc = generate_daily_log.main(["--dry-run", "--date", "2026-01-01"])
        assert rc == 0
        assert not target.exists()

    def test_happy_path_creates_file(self, tmp_path, monkeypatch, pg_config):
        monkeypatch.setenv("OPENCLAW_WORKSPACE", str(tmp_path))
        target = tmp_path / "memory" / "2026-07-05.md"
        rc = generate_daily_log.main(["--date", "2026-07-05"])
        assert rc == 0
        assert target.exists()
        text = target.read_text()
        assert text.startswith("# 2026-07-05\n")
        assert BEGIN_MARKER_PREFIX in text
        assert END_MARKER in text
        assert "Agent chat activity" in text
        assert "Workflow runs" in text
        assert "Lessons learned" in text
        assert "Events logged" in text
        assert "Tasks" in text
        assert "Cron results: not yet tracked" in text

    def test_idempotent_rerun(self, tmp_path, monkeypatch, pg_config):
        monkeypatch.setenv("OPENCLAW_WORKSPACE", str(tmp_path))
        target = tmp_path / "memory" / "2026-07-05.md"
        rc1 = generate_daily_log.main(["--date", "2026-07-05"])
        assert rc1 == 0
        text1 = target.read_text()
        rc2 = generate_daily_log.main(["--date", "2026-07-05"])
        assert rc2 == 0
        text2 = target.read_text()
        assert text1 == text2


@pytest.mark.integration
class TestPGPASSWORDRegression:
    """Dedicated regression test for the Hermes PGPASSWORD incident."""

    def test_wrong_pgpassword_in_environment_still_connects(self, monkeypatch):
        """Script must drop PGPASSWORD so .pgpass is honored."""
        monkeypatch.setenv("PGPASSWORD", "intentionally-wrong-password")
        cfg = generate_daily_log.load_postgres_config()
        # Should succeed because .pgpass provides the real password and script drops PGPASSWORD.
        conn = generate_daily_log.connect(cfg["database"], cfg)
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                assert cur.fetchone()[0] == 1
        finally:
            conn.close()


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
