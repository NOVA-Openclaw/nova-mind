"""Tests for cognition/scripts/pg-notify-listener.py issue #506.

Covers the branch-safety fix: sync_schema_to_github() must never commit or push
while HEAD is not on a clean, fast-forwarded main, and must fail loudly when it
cannot reach that state.
"""

from __future__ import annotations

import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

from conftest import (
    pg_notify_listener,
    _checkout_branch,
    _clone_head,
    _current_branch,
    _detach_head,
    _dirty_worktree,
    _lock_is_held,
    _make_clone_behind,
    _make_clone_diverged,
    _remote_head,
    _set_schema_content,
    _use_fake_git,
)


class TestHappyPath:
    def test_on_main_clean_in_sync_proceeds_normally(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 14: on main, clean, in sync behaves like pre-fix happy path."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        _set_schema_content(listener_module, "-- changed schema\n")

        assert _current_branch(clone) == "main"
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _remote_head(git_repos["origin"]) == _clone_head(clone)
        assert _current_branch(clone) == "main"
        assert len(mock_agent_chat) == 0


class TestWrongBranch:
    def test_feature_branch_checked_out_no_commit_on_wrong_branch(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 15: wrong branch is remediated to main; feature branch untouched."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _checkout_branch(clone, "feature/some-work", create=True)
        feature_tip_before = subprocess.run(
            ["git", "-C", str(clone), "rev-parse", "feature/some-work"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

        _set_schema_content(listener_module, "-- feature branch schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _current_branch(clone) == "main"
        assert _remote_head(git_repos["origin"]) == _clone_head(clone)

        feature_tip_after = subprocess.run(
            ["git", "-C", str(clone), "rev-parse", "feature/some-work"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        assert feature_tip_after == feature_tip_before
        assert len(mock_agent_chat) == 0


class TestDetachedHead:
    def test_detached_head_no_commit_on_detached_state(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 16: detached HEAD is remediated to main; no orphaned commit."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _detach_head(clone)
        assert _current_branch(clone) is None

        _set_schema_content(listener_module, "-- detached head schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _current_branch(clone) == "main"
        assert _remote_head(git_repos["origin"]) == _clone_head(clone)
        # The commit we created is reachable from main (not orphaned).
        result = subprocess.run(
            ["git", "-C", str(clone), "merge-base", "--is-ancestor", commit_hash, "main"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert len(mock_agent_chat) == 0


class TestMainBehindOrigin:
    def test_main_behind_origin_fast_forwards_before_sync(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 17: main behind origin is fast-forwarded before schema commit."""
        clone = Path(git_repos["clone"])
        origin = Path(git_repos["origin"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        old_remote_head = _remote_head(origin)
        _make_clone_behind(origin, clone, n=1)
        new_remote_head = _remote_head(origin)
        assert old_remote_head != new_remote_head

        _set_schema_content(listener_module, "-- behind origin schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _remote_head(origin) == _clone_head(clone)
        assert _current_branch(clone) == "main"
        # New commit is a descendant of the previous origin/main tip.
        result = subprocess.run(
            ["git", "-C", str(clone), "merge-base", "--is-ancestor", new_remote_head, commit_hash],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        assert len(mock_agent_chat) == 0


class TestMainDiverged:
    def test_main_diverged_from_origin_aborts_loudly(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 18 (variant b): diverged main aborts loudly; local history preserved."""
        clone = Path(git_repos["clone"])
        origin = Path(git_repos["origin"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _make_clone_diverged(origin, clone)
        local_head_before = _clone_head(clone)

        # Verify true divergence.
        result = subprocess.run(
            ["git", "-C", str(clone), "merge-base", "--is-ancestor", "main", "origin/main"],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0, "main should not be a fast-forward of origin/main"

        _set_schema_content(listener_module, "-- diverged schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is False
        assert commit_hash is None
        assert _clone_head(clone) == local_head_before
        assert _current_branch(clone) == "main"

        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == "schema-sync"
        assert recipients == ["nova"]
        assert "main" in message.lower()
        assert "diverged" in message.lower()
        assert "reconcile manually" in message.lower()


class TestDirtyWorktree:
    def test_dirty_worktree_readme_on_main_committed_normally(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 19a: dirty README.md on main is preserved in the schema commit."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        dirty_content = _dirty_worktree(clone, "README.md")
        _set_schema_content(listener_module, "-- dirty main schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _current_branch(clone) == "main"
        # README.md edit survived (committed).
        readme_in_head = subprocess.run(
            ["git", "-C", str(clone), "show", f"{commit_hash}:README.md"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        assert readme_in_head == dirty_content.strip()
        assert len(mock_agent_chat) == 0

    def test_dirty_worktree_on_wrong_branch_does_not_lose_edits(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        """Test 19b: dirty tracked file on wrong branch is not destroyed."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _checkout_branch(clone, "feature/dirty", create=True)
        # Make feature branch's README differ from main so checkout main fails.
        (clone / "README.md").write_text("# Feature README\n")
        subprocess.run(["git", "-C", str(clone), "add", "README.md"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "feature readme"],
            check=True,
            capture_output=True,
        )
        dirty_content = _dirty_worktree(clone, "README.md")

        _set_schema_content(listener_module, "-- dirty wrong branch schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        # Edit must survive somewhere in the working tree (feature branch still checked out or not).
        working_readme = (clone / "README.md").read_text().strip()
        assert working_readme == dirty_content.strip()

        # Since checkout fails, we abort loudly.
        assert ok is False
        assert commit_hash is None
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) >= 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == "schema-sync"
        assert recipients == ["nova"]
        assert "branch" in message.lower()
        assert "main" in message.lower()


class TestPushFailureAfterRemediation:
    def test_wrong_branch_remediated_then_push_fails_returns_commit_hash(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 20: remediation succeeds, commit is created, push fails -> (False, hash)."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _checkout_branch(clone, "feature/y", create=True)
        _set_schema_content(listener_module, "-- remediated then push fail\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure")

        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )
        local_head = _clone_head(clone)

        assert ok is False
        assert commit_hash == local_head
        assert _current_branch(clone) == "main"

        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == "schema-sync"
        assert recipients == ["nova"]
        assert "schema sync push failed" in message.lower()
        assert commit_hash in message


class TestLockHygiene:
    def test_lock_released_when_branch_check_aborts_before_dump(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 21: lock released when branch remediation aborts before dump."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _checkout_branch(clone, "feature/z", create=True)
        _set_schema_content(listener_module, "-- branch check abort\n")
        _use_fake_git(monkeypatch, tmp_path, "fetch_failure")

        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is False
        assert commit_hash is None
        assert not _lock_is_held(listener_module._git_lock_path)

    def test_lock_released_when_remediation_itself_fails_and_reentry_detects_problem(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        """Test 22: lock released on remediation failure; second call re-detects."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _checkout_branch(clone, "feature/reentry", create=True)
        _use_fake_git(monkeypatch, tmp_path, "fetch_failure")

        _set_schema_content(listener_module, "-- first remediation attempt\n")
        ok1, hash1 = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.t1"
        )
        assert ok1 is False
        assert hash1 is None
        assert not _lock_is_held(listener_module._git_lock_path)

        # Re-entry must detect the same problem (no one-shot cache).
        _set_schema_content(listener_module, "-- second remediation attempt\n")
        ok2, hash2 = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.t2"
        )
        assert ok2 is False
        assert hash2 is None
        assert not _lock_is_held(listener_module._git_lock_path)

        # No partial commit was created on any branch.
        log_result = subprocess.run(
            ["git", "-C", str(clone), "log", "--all", "--oneline"],
            capture_output=True,
            text=True,
            check=True,
        )
        assert "public.t1" not in log_result.stdout
        assert "public.t2" not in log_result.stdout


class TestConcurrency:
    def test_concurrent_calls_same_notify_never_produce_wrong_branch_commit(
        self, listener_module, git_repos, mock_pgschema_dump, monkeypatch, tmp_path
    ):
        """Test 23: concurrent calls serialize; no commit lands on a non-main branch."""
        clone = Path(git_repos["clone"])
        origin = Path(git_repos["origin"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _checkout_branch(clone, "feature/race", create=True)
        feature_tip_before = subprocess.run(
            ["git", "-C", str(clone), "rev-parse", "feature/race"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

        # Slow checkout forces the second caller to block while the first remediates.
        _use_fake_git(monkeypatch, tmp_path, "slow_checkout", sleep_seconds=1)
        _set_schema_content(listener_module, "-- concurrent schema\n")

        def call_sync():
            return listener_module.sync_schema_to_github(
                "CREATE", "table", "public.test_table"
            )

        with ThreadPoolExecutor(max_workers=2) as executor:
            future_a = executor.submit(call_sync)
            # Tiny delay so A is first to the lock.
            time.sleep(0.05)
            future_b = executor.submit(call_sync)

            result_a = future_a.result(timeout=30)
            result_b = future_b.result(timeout=30)

        # At least one call should create a real commit (the first to acquire the lock).
        commits_created = sum(1 for r in (result_a, result_b) if r[1] is not None)
        assert commits_created >= 1

        # Both calls complete without unhandled exceptions.
        assert result_a[0] in (True, False)
        assert result_b[0] in (True, False)

        # No commit landed on the feature branch.
        feature_tip_after = subprocess.run(
            ["git", "-C", str(clone), "rev-parse", "feature/race"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        assert feature_tip_after == feature_tip_before

        # Final state is on main.
        assert _current_branch(clone) == "main"

        # The commit that was created is on main at origin.
        pushed_commit = result_a[1] if result_a[1] else result_b[1]
        assert pushed_commit is not None
        result = subprocess.run(
            ["git", "--git-dir", str(origin), "merge-base", "--is-ancestor", pushed_commit, "main"],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

        # No wrong-branch/orphaned commits.
        all_refs = subprocess.run(
            ["git", "-C", str(clone), "branch", "-a"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        assert "feature/race" in all_refs


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
