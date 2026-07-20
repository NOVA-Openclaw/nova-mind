"""Tests for cognition/scripts/pg-notify-listener.py issue #399.

Covers the direct git push fix, retry/backoff, failure classification,
lock hygiene, alert path, and stale gidget instruction removal.

Fixtures and helpers have been moved to conftest.py so they can be reused
by the issue #506 test module without duplication.
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

from conftest import (
    pg_notify_listener,
    _create_fake_git_dir,
    _use_fake_git,
    _set_schema_content,
    _clone_head,
    _remote_head,
    _lock_is_held,
)


class TestHappyPath:
    def test_commit_exists_push_succeeds(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 1: commit is created and pushed; no agent_chat alert sent."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- changed schema\n")

        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert ok is True
        assert commit_hash == _clone_head(git_repos["clone"])
        assert _remote_head(git_repos["origin"]) == _clone_head(git_repos["clone"])
        assert len(mock_agent_chat) == 0


class TestNoChangesPath:
    def test_no_diff_no_commit_no_push_no_alert(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 2: unchanged schema returns (True, None) with no git ops."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        # pgschema reproduces the already-committed content.
        _set_schema_content(listener_module, "-- initial\n")
        head_before = _clone_head(git_repos["clone"])

        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert ok is True
        assert commit_hash is None
        assert _clone_head(git_repos["clone"]) == head_before
        assert len(mock_agent_chat) == 0


class TestRetryBackoff:
    def test_transient_failure_then_success(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 3: transient failure is retried with backoff, then succeeds."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- retry schema\n")
        _use_fake_git(monkeypatch, tmp_path, "transient_then_success", fail_count=2)

        start = time.monotonic()
        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")
        elapsed = time.monotonic() - start

        assert ok is True
        assert commit_hash == _clone_head(git_repos["clone"])
        assert _remote_head(git_repos["origin"]) == _clone_head(git_repos["clone"])
        assert len(mock_agent_chat) == 0
        # Two failures then success: backoff delays 2s + 4s = 6s minimum.
        assert elapsed >= 5.5, f"expected backoff delay, elapsed={elapsed:.2f}s"


class TestPermanentFailure:
    def test_alert_to_nova_and_return_semantics(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 4: permanent push failure alerts nova and returns (False, commit_hash)."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- permanent failure schema\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure")

        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")
        local_head = _clone_head(git_repos["clone"])

        assert ok is False
        assert commit_hash == local_head
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        call = message_calls[0]
        assert call["query"] == "SELECT send_agent_message(%s, %s, %s)"
        sender, message, recipients = call["params"]
        assert sender == "schema-sync"
        assert recipients == ["nova"]
        assert "schema sync push failed" in message.lower()
        assert commit_hash in message
        assert "Permission denied" not in message


class TestNonFastForward:
    def test_behind_origin_fast_forwards_and_succeeds(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 5: behind origin/main is now fast-forwarded before commit (issue #506)."""
        clone = Path(git_repos["clone"])
        origin = Path(git_repos["origin"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        # Push a commit directly to origin that is not in the clone.
        side_dir = clone.parent / "side"
        subprocess.run(["git", "clone", str(origin), str(side_dir)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(side_dir), "config", "user.email", "side@example.com"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "config", "user.name", "Side"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "config", "core.hooksPath", ""], check=True)
        (side_dir / "side.txt").write_text("side\n")
        subprocess.run(["git", "-C", str(side_dir), "add", "side.txt"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "commit", "-m", "side commit"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(side_dir), "push", "origin", "main"], check=True, capture_output=True)

        # The branch-safety fix fast-forwards the clone before creating the schema commit.
        _set_schema_content(listener_module, "-- local diverged schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _remote_head(git_repos["origin"]) == _clone_head(clone)
        assert len(mock_agent_chat) == 0
        # Lock released.
        assert not _lock_is_held(listener_module._git_lock_path)


class TestMultipleCommitsAhead:
    def test_push_carries_full_backlog(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 6: a single push transfers all locally-ahead commits."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        # Create 5 unpushed commits.
        local_hashes = []
        for i in range(5):
            schema_file = clone / "database" / "schema.sql"
            schema_file.write_text(f"-- backlog commit {i}\n")
            subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
            subprocess.run(["git", "-C", str(clone), "commit", "-m", f"backlog {i}"], check=True, capture_output=True)
            local_hashes.append(_clone_head(clone))

        # Now trigger one schema sync; the mocked pgschema writes a new diff.
        _set_schema_content(listener_module, "-- backlog head schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _remote_head(git_repos["origin"]) == _clone_head(clone)
        # All backlog commits are present on origin.
        for h in local_hashes:
            result = subprocess.run(
                ["git", "--git-dir", str(git_repos["origin"]), "merge-base", "--is-ancestor", h, "main"],
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, f"commit {h} not on origin"
        assert len(mock_agent_chat) == 0


class TestLockHygiene:
    def test_lock_released_after_success(
        self, listener_module, git_repos, mock_pgschema_dump
    ):
        """Test 7a: lock released after success."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- lock success schema\n")

        listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert not _lock_is_held(listener_module._git_lock_path)

    def test_lock_released_after_failure(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 7b: lock released after permanent push failure."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- lock failure schema\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure")

        listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert not _lock_is_held(listener_module._git_lock_path)

    def test_lock_held_during_execution(
        self, listener_module, git_repos, mock_pgschema_dump, monkeypatch, tmp_path
    ):
        """Test 7c: lock is held while sync_schema_to_github is running."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        _set_schema_content(listener_module, "-- lock held schema\n")
        _use_fake_git(monkeypatch, tmp_path, "timeout", sleep_seconds=2)

        lock_path = listener_module._git_lock_path
        probe_script = tmp_path / "probe.py"
        probe_script.write_text(
            f"""import fcntl, sys, time
lock_path = {repr(lock_path)}
for _ in range(100):
    try:
        fd = open(lock_path, 'w')
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
        fd.close()
        sys.exit(0)
    except (IOError, OSError):
        time.sleep(0.05)
sys.exit(1)
"""
        )

        start = time.monotonic()
        proc = subprocess.Popen([sys.executable, str(probe_script)])
        listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")
        elapsed = time.monotonic() - start
        proc.wait(timeout=10)

        assert proc.returncode == 0, "concurrent lock probe succeeded while sync held the lock"
        assert elapsed >= 1.5, f"expected delay from fake timeout, elapsed={elapsed:.2f}s"
        assert not _lock_is_held(lock_path)


class TestAuthFailure:
    def test_auth_fails_fast_with_distinct_message(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 8: auth failure fails fast and produces a class-specific alert."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- auth failure schema\n")
        _use_fake_git(monkeypatch, tmp_path, "auth_failure")
        start = time.monotonic()

        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")
        elapsed = time.monotonic() - start

        assert ok is False
        assert commit_hash == _clone_head(git_repos["clone"])
        # Auth is fail-fast: only one attempt, no backoff delays.
        assert elapsed < 3.0, f"auth failure should not wait, elapsed={elapsed:.2f}s"
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert recipients == ["nova"]
        assert "auth" in message.lower()


class TestTimeoutBehavior:
    def test_push_timeout_enforced_no_zombie(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 9: push timeout is enforced and no zombie process remains."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- timeout schema\n")
        # Patch the per-attempt timeout down for a fast, deterministic test.
        monkeypatch.setattr(pg_notify_listener, "PUSH_TIMEOUT", 1)
        _use_fake_git(monkeypatch, tmp_path, "timeout", sleep_seconds=3)
        start = time.monotonic()

        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")
        elapsed = time.monotonic() - start

        assert ok is False
        assert commit_hash == _clone_head(git_repos["clone"])
        # 3 attempts × 1s timeout + 2s + 4s backoff = 9s; cap high to avoid flaky CI.
        assert elapsed < 30, f"timeout retry loop took too long: {elapsed:.2f}s"
        assert elapsed >= 2.5, f"expected timeout delays, elapsed={elapsed:.2f}s"
        # No orphaned git push process.
        procs = subprocess.run(
            ["pgrep", "-af", "git.*push.*origin.*main"],
            capture_output=True,
            text=True,
        )
        assert procs.returncode != 0 or not procs.stdout.strip(), "zombie git push found"


class TestNoGidgetMessages:
    def test_no_schema_sync_messages_addressed_to_gidget(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 10: no agent_chat message from schema-sync is addressed to gidget."""
        clone = git_repos["clone"]
        listener_module.NOVA_MIND_DIR = clone
        listener_module.SCHEMA_FILE = os.path.join(clone, "database", "schema.sql")
        original_path = os.environ["PATH"]

        # Set up the non-fast-forward scenario first, while PATH still has the real git.
        origin = Path(git_repos["origin"])
        side_dir = Path(clone).parent / "side-10"
        subprocess.run(["git", "clone", str(origin), str(side_dir)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(side_dir), "config", "user.email", "side@example.com"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "config", "user.name", "Side"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "config", "core.hooksPath", ""], check=True)
        (side_dir / "side.txt").write_text("side\n")
        subprocess.run(["git", "-C", str(side_dir), "add", "side.txt"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "commit", "-m", "side"], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(side_dir), "push", "origin", "main"], check=True, capture_output=True)

        # Permanent failure scenario.
        _set_schema_content(listener_module, "-- gidget regression schema\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure", name="fake-git-1")
        listener_module.sync_schema_to_github("CREATE", "table", "public.t1")

        # Auth failure scenario.
        _set_schema_content(listener_module, "-- gidget regression schema 2\n")
        _use_fake_git(monkeypatch, tmp_path, "auth_failure", name="fake-git-2")
        listener_module.sync_schema_to_github("CREATE", "table", "public.t2")

        # Non-fast-forward scenario: restore real git on PATH first.
        monkeypatch.setenv("PATH", original_path)
        _set_schema_content(listener_module, "-- gidget regression schema 3\n")
        listener_module.sync_schema_to_github("CREATE", "table", "public.t3")

        schema_sync_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        # The non-fast-forward scenario now fast-forwards and succeeds (issue #506),
        # so only the permanent-failure and auth-failure cases produce alerts.
        assert len(schema_sync_calls) == 2
        for call in schema_sync_calls:
            recipients = call["params"][2]
            assert recipients == ["nova"]
            assert "gidget" not in [r.lower() for r in recipients]


class TestAlertPathFailure:
    def test_alert_db_down_does_not_crash_listener(
        self, listener_module, git_repos, mock_pgschema_dump, monkeypatch, tmp_path
    ):
        """Test 11: agent_chat DB failure is caught; lock released; listener survives."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- alert failure schema\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure")

        def exploding_connect(**kwargs):
            raise psycopg2.OperationalError("simulated agent_chat outage")

        monkeypatch.setattr(pg_notify_listener.psycopg2, "connect", exploding_connect)

        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert ok is False
        assert commit_hash == _clone_head(git_repos["clone"])
        assert not _lock_is_held(listener_module._git_lock_path)

    def test_handle_schema_change_survives_push_and_alert_failure(
        self, listener_module, monkeypatch
    ):
        """Test 11b: handle_schema_change outer wrapper survives internal failures."""
        monkeypatch.setattr(
            pg_notify_listener,
            "sync_schema_to_github",
            lambda _c, _t, _n: (False, "abc1234"),
        )
        monkeypatch.setattr(pg_notify_listener, "generate_schema_reference", lambda: True)
        monkeypatch.setattr(pg_notify_listener, "log_schema_event", lambda *args, **kwargs: None)
        captured = []
        monkeypatch.setattr(pg_notify_listener, "notify_clawdbot", lambda msg: captured.append(msg))

        listener_module.handle_schema_change(
            '{"command_tag": "CREATE", "object_type": "table", "object_identity": "public.test_table"}'
        )

        assert any("schema sync failed" in m.lower() for m in captured)


class TestSendAgentMessageCompliance:
    def test_uses_agent_chat_env_and_valid_signature(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 12: send_agent_message uses _agent_chat_env and valid signature."""
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = os.path.join(git_repos["clone"], "database", "schema.sql")
        _set_schema_content(listener_module, "-- signature schema\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure")

        listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        connect_calls = [c for c in mock_agent_chat if "connect_kwargs" in c]
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(connect_calls) == 1
        assert connect_calls[0]["connect_kwargs"]["database"] == "agent_chat"
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == "schema-sync"
        assert len(sender) <= 50
        assert message
        assert recipients == ["nova"]


class TestStaleGidgetInstruction:
    def test_failure_template_contains_no_gidget(
        self, listener_module, monkeypatch
    ):
        """Test 13: handle_schema_change failure template contains no gidget instruction."""
        monkeypatch.setattr(
            pg_notify_listener,
            "sync_schema_to_github",
            lambda _c, _t, _n: (False, "abc1234"),
        )
        monkeypatch.setattr(pg_notify_listener, "generate_schema_reference", lambda: True)
        monkeypatch.setattr(pg_notify_listener, "log_schema_event", lambda *args, **kwargs: None)
        captured = []
        monkeypatch.setattr(pg_notify_listener, "notify_clawdbot", lambda msg: captured.append(msg))

        listener_module.handle_schema_change(
            '{"command_tag": "CREATE", "object_type": "table", "object_identity": "public.test_table"}'
        )

        assert len(captured) == 1
        message = captured[0]
        assert "gidget" not in message.lower()
        assert "git push origin main" in message.lower()


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
