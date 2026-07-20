"""Shared fixtures and helpers for pg-notify-listener tests.

This conftest supports both test_pg_notify_listener_issue_399.py and
test_pg_notify_listener_issue_506.py. Fixtures and helpers that were originally
in the issue #399 module have been moved here so they can be reused without
duplication.
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
    """Create a directory containing a fake `git` wrapper for push/fetch tests."""
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
    elif behavior == "fetch_failure":
        body = """echo "fatal: unable to access 'origin': Could not resolve host example.com" >&2
exit 128
"""
    elif behavior == "slow_checkout":
        sleep_seconds = kwargs.get("sleep_seconds", 1)
        body = f"""sleep {sleep_seconds}
exec "$REAL_GIT" "$@"
"""
    else:
        raise ValueError(f"Unknown fake-git behavior: {behavior}")

    script = f"""#!/usr/bin/env bash
set -euo pipefail
REAL_GIT={real_git!r}
IS_PUSH=0
IS_FETCH=0
IS_CHECKOUT=0
for arg in "$@"; do
    if [[ "$arg" == "push" ]]; then
        IS_PUSH=1
    elif [[ "$arg" == "fetch" ]]; then
        IS_FETCH=1
    elif [[ "$arg" == "checkout" ]]; then
        IS_CHECKOUT=1
    fi
done
"""
    if behavior == "transient_then_success":
        script += """if [[ $IS_PUSH -eq 1 ]]; then
"""
    elif behavior == "permanent_failure":
        script += """if [[ $IS_PUSH -eq 1 ]]; then
"""
    elif behavior == "auth_failure":
        script += """if [[ $IS_PUSH -eq 1 ]]; then
"""
    elif behavior == "timeout":
        script += """if [[ $IS_PUSH -eq 1 ]]; then
"""
    elif behavior == "fetch_failure":
        script += """if [[ $IS_FETCH -eq 1 ]]; then
"""
    elif behavior == "slow_checkout":
        script += """if [[ $IS_CHECKOUT -eq 1 ]]; then
"""
    else:
        raise ValueError(f"Unhandled fake-git behavior: {behavior}")

    script += body
    script += """fi
exec "$REAL_GIT" "$@"
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


def _checkout_branch(clone_dir, branch, create=False):
    """Checkout an existing branch, or create and checkout a new one."""
    args = ["git", "-C", str(clone_dir), "checkout"]
    if create:
        args.append("-b")
    args.append(branch)
    subprocess.run(args, check=True, capture_output=True)


def _detach_head(clone_dir):
    """Put the clone into detached HEAD state at the current HEAD."""
    head = subprocess.run(
        ["git", "-C", str(clone_dir), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    subprocess.run(
        ["git", "-C", str(clone_dir), "checkout", "--detach", head],
        check=True,
        capture_output=True,
    )


def _make_clone_behind(origin_dir, clone_dir, n=1):
    """Push n new commits to origin/main so clone's main is behind."""
    side_dir = Path(clone_dir).parent / "side-behind"
    if side_dir.exists():
        shutil.rmtree(side_dir)
    subprocess.run(["git", "clone", str(origin_dir), str(side_dir)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(side_dir), "config", "user.email", "side@example.com"], check=True)
    subprocess.run(["git", "-C", str(side_dir), "config", "user.name", "Side"], check=True)
    subprocess.run(["git", "-C", str(side_dir), "config", "core.hooksPath", ""], check=True)
    for i in range(n):
        (side_dir / f"behind-{i}.txt").write_text(f"behind {i}\n")
        subprocess.run(["git", "-C", str(side_dir), "add", f"behind-{i}.txt"], check=True)
        subprocess.run(["git", "-C", str(side_dir), "commit", "-m", f"behind commit {i}"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(side_dir), "push", "origin", "main"], check=True, capture_output=True)
    shutil.rmtree(side_dir)


def _make_clone_diverged(origin_dir, clone_dir):
    """Create true divergence: local main has a commit not on origin, and origin/main has a different commit not in local."""
    clone_path = Path(clone_dir)

    # Commit A: local-only commit on main in clone.
    (clone_path / "local-diverge.txt").write_text("local\n")
    subprocess.run(["git", "-C", str(clone_path), "add", "local-diverge.txt"], check=True)
    subprocess.run(["git", "-C", str(clone_path), "commit", "-m", "local diverged commit"], check=True, capture_output=True)

    # Commit B: origin-only commit pushed from a side clone.
    side_dir = clone_path.parent / "side-diverge"
    if side_dir.exists():
        shutil.rmtree(side_dir)
    subprocess.run(["git", "clone", str(origin_dir), str(side_dir)], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(side_dir), "config", "user.email", "side@example.com"], check=True)
    subprocess.run(["git", "-C", str(side_dir), "config", "user.name", "Side"], check=True)
    subprocess.run(["git", "-C", str(side_dir), "config", "core.hooksPath", ""], check=True)
    (side_dir / "origin-diverge.txt").write_text("origin\n")
    subprocess.run(["git", "-C", str(side_dir), "add", "origin-diverge.txt"], check=True)
    subprocess.run(["git", "-C", str(side_dir), "commit", "-m", "origin diverged commit"], check=True, capture_output=True)
    subprocess.run(["git", "-C", str(side_dir), "push", "origin", "main"], check=True, capture_output=True)
    shutil.rmtree(side_dir)


def _dirty_worktree(clone_dir, path="README.md"):
    """Write an uncommitted change to a tracked file, returning the new content."""
    content = f"# README dirty {time.monotonic()}\n"
    Path(clone_dir, path).write_text(content)
    return content


def _all_commits(clone_dir):
    """Return set of short commit hashes reachable from any ref."""
    result = subprocess.run(
        ["git", "-C", str(clone_dir), "log", "--all", "--oneline", "--format=%h"],
        capture_output=True,
        text=True,
        check=True,
    )
    return set(result.stdout.strip().splitlines())


def _current_branch(clone_dir):
    """Return current branch name, or None if detached HEAD."""
    result = subprocess.run(
        ["git", "-C", str(clone_dir), "symbolic-ref", "-q", "HEAD"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip().replace("refs/heads/", "")
