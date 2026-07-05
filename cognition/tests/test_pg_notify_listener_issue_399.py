"""Tests for cognition/scripts/pg-notify-listener.py issue #399.

Covers the direct git push fix, retry/backoff, failure classification,
lock hygiene, alert path, and stale gidget instruction removal.
"""

from __future__ import annotations

import fcntl
import importlib.util
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from unittest import mock

import psycopg2
import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "pg-notify-listener.py"
spec = importlib.util.spec_from_file_location("pg_notify_listener", SCRIPT_PATH)
pg_notify_listener = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pg_notify_listener)


@pytest.fixture
def listener_module(monkeypatch, tmp_path):
    """Return the listener module configured for a disposable repo."""
    repo = tmp_path / "nova-mind-clone"
    repo.mkdir()
    (repo / "database").mkdir()
    schema_file = repo / "database" / "schema.sql"
    schema_file.write_text("-- baseline schema\n")
    lock_path = tmp_path / "git.lock"

    monkeypatch.setattr(pg_notify_listener, "NOVA_MIND_DIR", str(repo))
    monkeypatch.setattr(pg_notify_listener, "SCHEMA_FILE", str(schema_file))
    monkeypatch.setattr(pg_notify_listener, "_git_lock_path", str(lock_path))
    monkeypatch.setattr(
        pg_notify_listener,
        "_agent_chat_env",
        {
            "PGHOST": "localhost",
            "PGDATABASE": "agent_chat",
            "PGUSER": "testuser",
            "PGPASSWORD": "testpass",
        },
    )
    # Ensure a clean lock fd state for every test.
    pg_notify_listener._git_lock_fd = None

    yield pg_notify_listener

    # Cleanup: release lock if a test left it held.
    if pg_notify_listener._git_lock_fd:
        try:
            fcntl.flock(pg_notify_listener._git_lock_fd, fcntl.LOCK_UN)
        except Exception:
            pass
        try:
            pg_notify_listener._git_lock_fd.close()
        except Exception:
            pass
        pg_notify_listener._git_lock_fd = None


@pytest.fixture
def git_repos(tmp_path):
    """Create a bare origin and a clone with an initial commit pushed."""
    origin = tmp_path / "origin.git"
    clone = tmp_path / "clone"
    origin.mkdir(mode=0o700)
    subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
    subprocess.run(["git", "clone", str(origin), str(clone)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(clone), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(clone), "config", "user.name", "Test"], check=True)
    # Disable global hooks so test pushes to disposable repos are not blocked.
    subprocess.run(["git", "-C", str(clone), "config", "core.hooksPath", ""], check=True)
    subprocess.run(["git", "-C", str(origin), "config", "core.hooksPath", ""], check=True)
    (clone / "database").mkdir(exist_ok=True)
    (clone / "database" / "schema.sql").write_text("-- initial\n")
    (clone / "README.md").write_text("# README\n")
    subprocess.run(["git", "-C", str(clone), "add", "."], check=True)
    subprocess.run(["git", "-C", str(clone), "commit", "-m", "initial"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)
    return {"origin": str(origin), "clone": str(clone)}


@pytest.fixture
def mock_pgschema_dump(monkeypatch, listener_module):
    """Mock pgschema dump to write deterministic schema content."""
    real_subprocess_run = subprocess.run

    def fake_run(*args, **kwargs):
        cmd = args[0] if args else kwargs.get("args", [])
        if len(cmd) > 0 and cmd[0] == "pgschema":
            stdout = kwargs.get("stdout")
            new_content = getattr(
                listener_module, "_test_schema_content", "-- schema from pgschema\n"
            )
            if stdout is not None:
                stdout.write(new_content)
                stdout.flush()
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout="", stderr="")
        return real_subprocess_run(*args, **kwargs)

    monkeypatch.setattr(pg_notify_listener.subprocess, "run", fake_run)
    return fake_run


@pytest.fixture
def mock_agent_chat(monkeypatch, listener_module):
    """Capture send_agent_message calls made via psycopg2."""
    calls = []

    class FakeCursor:
        def execute(self, query, params):
            calls.append({"query": query, "params": list(params)})

        def close(self):
            pass

    class FakeConnection:
        def cursor(self):
            return FakeCursor()

        def commit(self):
            pass

        def close(self):
            pass

    def fake_connect(**kwargs):
        calls.append({"connect_kwargs": kwargs})
        return FakeConnection()

    monkeypatch.setattr(pg_notify_listener.psycopg2, "connect", fake_connect)
    return calls


def _create_fake_git_dir(tmp_path, behavior, name="fake-git", **kwargs):
    """Create a directory containing a fake `git` wrapper for push tests."""
    # Resolve the real git binary before we shadow it on PATH.
    real_git = shutil.which("git")
    if not real_git:
        real_git = "/usr/bin/git"

    fake_dir = tmp_path / name
    fake_dir.mkdir(mode=0o700)
    counter_file = fake_dir / "counter"
    counter_file.write_text("0")

    if behavior == "transient_then_success":
        fail_count = kwargs.get("fail_count", 2)
        body = f"""COUNTER=$(cat {counter_file} 2>/dev/null || echo 0)
echo $((COUNTER + 1)) > {counter_file}
if [[ $COUNTER -lt {fail_count} ]]; then
    echo "fatal: unable to access 'origin': Could not resolve host example.com" >&2
    exit 128
fi
exec "$REAL_GIT" "$@"
"""
    elif behavior == "permanent_failure":
        body = """echo "fatal: unable to access 'origin': Could not resolve host example.com" >&2
exit 128
"""
    elif behavior == "auth_failure":
        body = """echo "Permission denied (publickey)." >&2
echo "fatal: Could not read from remote repository." >&2
exit 128
"""
    elif behavior == "timeout":
        sleep_seconds = kwargs.get("sleep_seconds", 70)
        body = f"""sleep {sleep_seconds}
exit 0
"""
    else:
        raise ValueError(f"Unknown fake-git behavior: {behavior}")

    script = f"""#!/usr/bin/env bash
set -euo pipefail
REAL_GIT={real_git!r}
IS_PUSH=0
for arg in "$@"; do
    if [[ "$arg" == "push" ]]; then
        IS_PUSH=1
        break
    fi
done
if [[ $IS_PUSH -eq 0 ]]; then
    exec "$REAL_GIT" "$@"
fi
{body}
"""
    git_path = fake_dir / "git"
    git_path.write_text(script)
    git_path.chmod(0o755)
    return str(fake_dir)


def _use_fake_git(monkeypatch, tmp_path, behavior, name="fake-git", **kwargs):
    """Prepend a fake git directory to PATH."""
    fake_dir = _create_fake_git_dir(tmp_path, behavior, name=name, **kwargs)
    monkeypatch.setenv("PATH", f"{fake_dir}{os.pathsep}{os.environ['PATH']}")
    return fake_dir


def _set_schema_content(listener_module, content):
    """Set the content the mocked pgschema will write."""
    listener_module._test_schema_content = content


def _clone_head(clone_dir):
    """Return short HEAD hash of clone."""
    result = subprocess.run(
        ["git", "-C", str(clone_dir), "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def _remote_head(origin_dir):
    """Return short hash of origin/main."""
    result = subprocess.run(
        ["git", "--git-dir", str(origin_dir), "rev-parse", "--short", "main"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def _lock_is_held(lock_path):
    """Return True if an exclusive non-blocking lock cannot be acquired."""
    try:
        fd = open(lock_path, "w")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
        fd.close()
        return False
    except (IOError, OSError):
        return True


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
    def test_behind_origin_rejection_fail_fast(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 5: non-fast-forward rejection fails fast and alerts nova."""
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

        # Now make a diverging commit in the clone.
        _set_schema_content(listener_module, "-- local diverged schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github("CREATE", "table", "public.test_table")

        assert ok is False
        assert commit_hash == _clone_head(clone)
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == "schema-sync"
        assert recipients == ["nova"]
        assert "non-fast-forward" in message.lower()
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
        assert len(schema_sync_calls) == 3
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
