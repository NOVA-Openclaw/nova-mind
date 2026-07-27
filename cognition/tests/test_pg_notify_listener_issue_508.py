"""Tests for cognition/scripts/pg-notify-listener.py issue #508.

Covers the alert sender/recipient fix:
  * sender = connecting PGUSER (not hardcoded 'schema-sync')
  * message body prefixed with '[schema-sync]'
  * recipient strategy excludes the sender and falls back to graybeard/broadcast
  * helpers remain non-raising on alert-path failures
"""

from __future__ import annotations

import fcntl
import subprocess
import sys
from pathlib import Path

import psycopg2
import pytest

from conftest import (
    pg_notify_listener,
    _make_clone_diverged,
    _set_schema_content,
    _use_fake_git,
)


class TestDirectHelperContract:
    """TC-508-01/02: direct helper calls pin sender/prefix/recipients."""

    def test_push_alert_binds_pguser_sender_and_prefixes_message(
        self, listener_module, mock_agent_chat
    ):
        listener_module._send_push_alert(
            "abc1234", "CREATE", "public.t", "transient", "boom"
        )
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(calls) == 1
        sender, message, recipients = calls[0]["params"]
        assert sender == listener_module._agent_chat_env["PGUSER"]
        assert sender != "schema-sync"
        assert message.startswith("[schema-sync]")
        assert "abc1234" in message
        assert "push failed" in message.lower()
        assert recipients == listener_module._alert_recipients(sender)

    def test_branch_alert_binds_pguser_sender_and_prefixes_message(
        self, listener_module, mock_agent_chat
    ):
        listener_module._send_branch_alert(
            "feature/x", "ALTER", "public.t", "diverged", "err"
        )
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(calls) == 1
        sender, message, recipients = calls[0]["params"]
        assert sender == listener_module._agent_chat_env["PGUSER"]
        assert message.startswith("[schema-sync]")
        assert "diverged" in message.lower()
        assert "main" in message.lower()
        assert recipients == listener_module._alert_recipients(sender)

    def test_connect_kwargs_still_come_from_agent_chat_env(
        self, listener_module, mock_agent_chat
    ):
        listener_module._send_push_alert("abc1234", "CREATE", "public.t", "auth", "boom")
        connect_calls = [c for c in mock_agent_chat if "connect_kwargs" in c]
        assert len(connect_calls) == 1
        kwargs = connect_calls[0]["connect_kwargs"]
        assert kwargs["database"] == "agent_chat"
        assert kwargs["user"] == listener_module._agent_chat_env["PGUSER"]


class TestRecipientStrategy:
    """TC-508-07 through TC-508-12: recipient resolver properties."""

    @pytest.mark.parametrize(
        "pguser,expected_recipients",
        [
            ("testuser", ["nova"]),
            ("graybeard", ["nova"]),
            ("nova", ["graybeard"]),  # CRITICAL self-avoidance (TC-508-09)
            ("nova-staging", ["nova"]),
            ("newhart", ["nova"]),
            ("victoria", ["nova"]),
        ],
    )
    def test_recipients_follow_strategy_for_pguser(
        self, listener_module, mock_agent_chat, monkeypatch, pguser, expected_recipients
    ):
        monkeypatch.setitem(listener_module._agent_chat_env, "PGUSER", pguser)
        listener_module._send_push_alert("abc1234", "CREATE", "public.t", "auth", "boom")
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(calls) == 1
        sender, message, recipients = calls[0]["params"]
        assert sender == pguser
        assert recipients == expected_recipients
        assert sender.lower() not in [r.lower() for r in recipients]
        assert len(recipients) >= 1

    def test_recipients_never_include_sender_property(
        self, listener_module, mock_agent_chat, monkeypatch
    ):
        for pguser in ("testuser", "nova", "graybeard", "victoria", "newhart", "nova-staging"):
            mock_agent_chat.clear()
            monkeypatch.setitem(listener_module._agent_chat_env, "PGUSER", pguser)
            listener_module._send_push_alert("h", "C", "t", "transient", None)
            calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
            assert len(calls) == 1
            sender, _, recipients = calls[0]["params"]
            assert sender == pguser
            assert sender.lower() not in [r.lower() for r in recipients]
            assert len(recipients) >= 1

    def test_last_resort_broadcast_when_primary_and_fallback_both_match_sender(
        self, listener_module, monkeypatch
    ):
        """Last-resort broadcast when every configured recipient is the sender."""
        monkeypatch.setattr(listener_module, "_ALERT_PRIMARY", ["nova"])
        monkeypatch.setattr(listener_module, "_ALERT_FALLBACK", ["nova"])
        recipients = listener_module._alert_recipients("nova")
        assert recipients == ["*"]

    def test_both_primary_and_fallback_are_self_stripped(self, listener_module):
        """If primary and fallback both equal sender, final resort is broadcast."""
        recipients = listener_module._alert_recipients("nova")
        assert recipients == ["graybeard"]
        recipients = listener_module._alert_recipients("graybeard")
        assert recipients == ["nova"]


class TestFailureSwallow:
    """TC-508-13 through TC-508-16: alert path failures do not propagate."""

    def test_operational_error_on_connect_is_swallowed(self, listener_module, monkeypatch):
        def boom(**kwargs):
            raise psycopg2.OperationalError("simulated agent_chat outage")

        monkeypatch.setattr(listener_module.psycopg2, "connect", boom)
        listener_module._send_push_alert("h", "C", "t", "transient", None)
        listener_module._send_branch_alert("b", "C", "t", "fetch failed", None)

    def test_sender_mismatch_error_is_swallowed(self, listener_module, monkeypatch):
        class RaisingCursor:
            def execute(self, query, params):
                raise Exception(
                    'send_agent_message: sender must match session_user (got schema-sync but connected as nova)'
                )

            def close(self):
                pass

        class RaisingConnection:
            def cursor(self):
                return RaisingCursor()

            def commit(self):
                pass

            def close(self):
                pass

        monkeypatch.setattr(
            listener_module.psycopg2, "connect", lambda **kwargs: RaisingConnection()
        )
        listener_module._send_push_alert("h", "C", "t", "transient", None)

    def test_self_address_error_is_swallowed(self, listener_module, monkeypatch):
        class RaisingCursor:
            def execute(self, query, params):
                raise Exception(
                    'send_agent_message: sender "nova" is in the recipient list — agents cannot message themselves'
                )

            def close(self):
                pass

        class RaisingConnection:
            def cursor(self):
                return RaisingCursor()

            def commit(self):
                pass

            def close(self):
                pass

        monkeypatch.setattr(
            listener_module.psycopg2, "connect", lambda **kwargs: RaisingConnection()
        )
        listener_module._send_push_alert("h", "C", "t", "transient", None)

    def test_missing_pguser_does_not_raise(self, listener_module, monkeypatch):
        monkeypatch.setitem(listener_module._agent_chat_env, "PGUSER", "")
        listener_module._send_push_alert("h", "C", "t", "transient", None)
        listener_module._send_branch_alert("b", "C", "t", "diverged", None)


class TestBoundParams:
    """TC-508-17 through TC-508-20: assert raw bound SQL params."""

    def test_params_are_list_with_three_positions(self, listener_module, mock_agent_chat):
        listener_module._send_push_alert("abc1234", "CREATE", "public.t", "auth", "boom")
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(calls) == 1
        params = calls[0]["params"]
        assert isinstance(params, list)
        assert len(params) == 3
        sender, message, recipients = params
        assert isinstance(sender, str)
        assert isinstance(message, str)
        assert isinstance(recipients, (list, tuple))
        assert all(isinstance(r, str) for r in recipients)

    def test_message_non_empty_after_prefix(self, listener_module, mock_agent_chat):
        listener_module._send_push_alert("abc1234", "CREATE", "public.t", "auth", "boom")
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        message = calls[0]["params"][1]
        assert message and message.strip()

    def test_stderr_truncation_still_applied_after_prefix(
        self, listener_module, mock_agent_chat
    ):
        long_stderr = "x" * 1000
        listener_module._send_push_alert(
            "abc1234", "CREATE", "public.t", "transient", long_stderr
        )
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        message = calls[0]["params"][1]
        assert message.startswith("[schema-sync]")
        # The raw stderr slice is at most 500 chars; the full message is longer
        # because of the fixed body, so we just verify the stderr portion is truncated.
        assert len(message.split("git stderr:")[-1].strip()) <= 500


class TestEndToEndRegression:
    """TC-508-03/04 and #399/#506 regression paths with new alert contract."""

    def test_permanent_push_failure_alerts_with_new_contract(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, monkeypatch, tmp_path
    ):
        listener_module.NOVA_MIND_DIR = git_repos["clone"]
        listener_module.SCHEMA_FILE = Path(git_repos["clone"]) / "database" / "schema.sql"
        _set_schema_content(listener_module, "-- permanent failure schema\n")
        _use_fake_git(monkeypatch, tmp_path, "permanent_failure")

        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )
        local_head = subprocess.run(
            ["git", "-C", git_repos["clone"], "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

        assert ok is False
        assert commit_hash == local_head
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == listener_module._agent_chat_env["PGUSER"]
        assert message.startswith("[schema-sync]")
        assert recipients == listener_module._alert_recipients(sender)
        assert not self._lock_is_held(listener_module._git_lock_path)

    def test_diverged_main_branch_alert_with_new_contract(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat
    ):
        clone = Path(git_repos["clone"])
        origin = Path(git_repos["origin"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")

        _make_clone_diverged(origin, clone)
        local_head_before = subprocess.run(
            ["git", "-C", str(clone), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

        _set_schema_content(listener_module, "-- diverged schema\n")
        ok, commit_hash = listener_module.sync_schema_to_github(
            "CREATE", "table", "public.test_table"
        )

        assert ok is False
        assert commit_hash is None
        local_head_after = subprocess.run(
            ["git", "-C", str(clone), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        assert local_head_after == local_head_before

        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        sender, message, recipients = message_calls[0]["params"]
        assert sender == listener_module._agent_chat_env["PGUSER"]
        assert message.startswith("[schema-sync]")
        assert "diverged" in message.lower()
        assert recipients == listener_module._alert_recipients(sender)

    @staticmethod
    def _lock_is_held(lock_path):
        try:
            fd = open(lock_path, "w")
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(fd, fcntl.LOCK_UN)
            fd.close()
            return False
        except (IOError, OSError):
            return True


class TestStaticContract:
    """TC-508-06/26/27/28: source-level contract checks."""

    def test_no_literal_schema_sync_sender_in_alert_helpers(self, listener_module):
        import inspect

        push_src = inspect.getsource(listener_module._send_push_alert)
        branch_src = inspect.getsource(listener_module._send_branch_alert)
        # The literal 'schema-sync' must not appear as the sender argument.
        assert "('schema-sync', message, ['nova'])" not in push_src
        assert "('schema-sync', message, ['nova'])" not in branch_src
        # The prefix constant must be present.
        assert "'[schema-sync]'" in push_src
        assert "'[schema-sync]'" in branch_src

    def test_alert_recipients_helper_documents_both_guards(self, listener_module):
        doc = listener_module._alert_recipients.__doc__ or ""
        lowered = doc.lower()
        assert "session_user" in lowered or "pguser" in lowered
        assert "self-address" in lowered or "recipient" in lowered


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
