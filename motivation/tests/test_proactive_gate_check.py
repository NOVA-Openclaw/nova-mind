"""
Tests for motivation/scripts/proactive-gate-check.py

Covers:
- Idle detection (active, idle, boundary, missing file, malformed, bot-only, custom threshold)
- All 11 gate check steps (actionable / not-actionable paths)
- D100 logic (mandatory vs optional vs forced by roll staleness)
- Error handling (DB failure, missing state files, gh unavailable)
- Output format validation (required fields, correct types)
"""

import importlib
import importlib.util
import json
import os
import sys
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import MagicMock, patch, mock_open

import pytest

# ---------------------------------------------------------------------------
# Import the module under test from its non-standard location
# ---------------------------------------------------------------------------

_SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "proactive-gate-check.py"


def _load_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location("proactive_gate_check", _SCRIPT_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


@pytest.fixture(scope="module")
def m() -> ModuleType:
    """Loaded module, shared across the test session."""
    return _load_module()


@pytest.fixture(autouse=True)
def _isolate_heartbeat_alt(m, tmp_path):
    """Prevent the real alt heartbeat file from leaking into tests."""
    alt_path = str(tmp_path / "alt-heartbeat.json")
    with patch.object(m, "HEARTBEAT_STATE_JSON_ALT", alt_path):
        yield


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ms(minutes_ago: float = 0.0) -> int:
    """Return epoch-ms for `minutes_ago` minutes in the past."""
    return int((time.time() - minutes_ago * 60) * 1000)


def _iso(hours_ago: float = 0.0) -> str:
    dt = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _make_sessions(entries: dict[str, int]) -> str:
    """Build a minimal sessions.json payload from {key: lastInteractionAt_ms}."""
    data = {k: {"lastInteractionAt": v, "chatType": "channel"} for k, v in entries.items()}
    return json.dumps(data)


# ---------------------------------------------------------------------------
# Idle detection tests
# ---------------------------------------------------------------------------

class TestIdleDetection:
    def test_active_under_threshold(self, m, tmp_path):
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({"agent:nova:discord:channel:123": _ms(30)})
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert result["idle"] is False
        assert result["idle_minutes"] < 60

    def test_idle_over_threshold(self, m, tmp_path):
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({"agent:nova:discord:channel:123": _ms(90)})
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert result["idle"] is True
        assert result["idle_minutes"] >= 60

    def test_boundary_exactly_at_threshold(self, m, tmp_path):
        """elapsed >= threshold → idle (inclusive boundary)."""
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({"agent:nova:discord:channel:123": _ms(60)})
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert result["idle"] is True

    def test_missing_sessions_file_defaults_to_idle(self, m, tmp_path):
        missing = str(tmp_path / "nonexistent.json")
        with patch.object(m, "SESSIONS_JSON", missing):
            result = m.check_idle()
        assert result["idle"] is True
        assert "reason" in result

    def test_malformed_sessions_file_defaults_to_idle(self, m, tmp_path):
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text("{this is not valid json{{")
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)):
            result = m.check_idle()
        assert result["idle"] is True
        assert "reason" in result

    def test_bot_only_sessions_default_to_idle(self, m, tmp_path):
        """Sessions that are all heartbeat/cron/subagent should default to idle."""
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({
                "agent:nova:main:heartbeat": _ms(1),
                "agent:nova:cron:abc123": _ms(1),
                "agent:nova:subagent:xyz": _ms(1),
            })
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert result["idle"] is True
        assert "reason" in result

    def test_excludes_user_facing_bot_session(self, m, tmp_path):
        """
        A key that matches a user-facing pattern (discord:channel) AND an
        exclude pattern (heartbeat) must be dropped by the exclude filter,
        leaving no qualifying sessions → defaults to idle.

        This exercises EXCLUDE_PATTERNS on keys that would otherwise pass the
        USER_SESSION_PATTERNS guard — the vacuous-exclude bug reproduced with
        keys like agent:nova:main:heartbeat which never reach the exclude check.
        """
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({
                # Matches discord:channel (user-facing) AND heartbeat (exclude) —
                # should be dropped by EXCLUDE_PATTERNS, not counted.
                "agent:nova:discord:channel:123:heartbeat": _ms(1),
            })
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert result["idle"] is True
        assert "reason" in result

    def test_custom_threshold_via_env(self, m, tmp_path):
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({"agent:nova:discord:channel:123": _ms(10)})
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 5):
            result = m.check_idle()
        assert result["idle"] is True
        assert result["idle_threshold_minutes"] == 5

    def test_multiple_sessions_picks_most_recent(self, m, tmp_path):
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({
                "agent:nova:discord:channel:111": _ms(120),  # old
                "agent:nova:discord:channel:222": _ms(10),   # recent
            })
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert result["idle"] is False  # most recent was 10 min ago

    def test_result_contains_required_fields(self, m, tmp_path):
        sessions_file = tmp_path / "sessions.json"
        sessions_file.write_text(
            _make_sessions({"agent:nova:signal:user:abc": _ms(30)})
        )
        with patch.object(m, "SESSIONS_JSON", str(sessions_file)), \
             patch.object(m, "IDLE_THRESHOLD_MINUTES", 60):
            result = m.check_idle()
        assert "idle" in result
        assert "idle_minutes" in result
        assert "idle_threshold_minutes" in result


# ---------------------------------------------------------------------------
# Step 1 — agent_chat
# ---------------------------------------------------------------------------

class TestStep1AgentChat:
    def test_no_unacknowledged_messages(self, m):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        mock_cur.fetchone.return_value = (0,)
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur

        with patch.object(m, "_db_connect", return_value=mock_conn):
            result = m.check_step1_agent_chat()
        assert result["actionable"] is False

    def test_unacknowledged_messages_present(self, m):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        mock_cur.fetchone.return_value = (3,)
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur

        with patch.object(m, "_db_connect", return_value=mock_conn):
            result = m.check_step1_agent_chat()
        assert result["actionable"] is True
        assert result["data"]["count"] == 3

    def test_db_failure_returns_error(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("connection refused")):
            result = m.check_step1_agent_chat()
        assert result["actionable"] is False
        assert "error" in result


# ---------------------------------------------------------------------------
# Step 2 — unanswered sessions
# ---------------------------------------------------------------------------

class TestStep2UnansweredSessions:
    """check_step2_unanswered_sessions() reads SESSIONS_JSON directly and, for
    each recent user-facing session, inspects the last conversational role in
    its JSONL session file via _last_conversational_role()."""

    def _write_sessions_json(self, tmp_path, entries: dict[str, dict]) -> str:
        path = tmp_path / "sessions.json"
        path.write_text(json.dumps(entries))
        return str(path)

    def _write_session_file(self, tmp_path, name: str, roles: list[str]) -> str:
        """Write a minimal JSONL session file; last entry in `roles` is the
        last conversational message role."""
        path = tmp_path / name
        lines = [json.dumps({"message": {"role": role}}) for role in roles]
        path.write_text("\n".join(lines) + "\n")
        return str(path)

    def test_recent_user_sessions_found(self, m, tmp_path):
        now_ms = int(time.time() * 1000)
        sf1 = self._write_session_file(tmp_path, "s1.jsonl", ["assistant", "user"])
        sf2 = self._write_session_file(tmp_path, "s2.jsonl", ["assistant", "user"])
        sessions_json = self._write_sessions_json(tmp_path, {
            "agent:nova:discord:channel:123": {"updatedAt": now_ms - 1000, "sessionFile": sf1},
            "agent:nova:discord:channel:456": {"updatedAt": now_ms - 2000, "sessionFile": sf2},
        })
        with patch.object(m, "SESSIONS_JSON", sessions_json):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is True
        assert result["data"]["count"] == 2

    def test_no_recent_user_sessions(self, m, tmp_path):
        now_ms = int(time.time() * 1000)
        sf1 = self._write_session_file(tmp_path, "s1.jsonl", ["user", "assistant"])
        sessions_json = self._write_sessions_json(tmp_path, {
            "agent:nova:discord:channel:123": {"updatedAt": now_ms - 90_000_000, "sessionFile": sf1},
        })
        with patch.object(m, "SESSIONS_JSON", sessions_json):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False

    def test_answered_session_not_actionable(self, m, tmp_path):
        """Last conversational message is from the assistant -> not unanswered."""
        now_ms = int(time.time() * 1000)
        sf1 = self._write_session_file(tmp_path, "s1.jsonl", ["user", "assistant"])
        sessions_json = self._write_sessions_json(tmp_path, {
            "agent:nova:discord:channel:123": {"updatedAt": now_ms - 1000, "sessionFile": sf1},
        })
        with patch.object(m, "SESSIONS_JSON", sessions_json):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False

    def test_excludes_bot_sessions(self, m, tmp_path):
        now_ms = int(time.time() * 1000)
        sf1 = self._write_session_file(tmp_path, "s1.jsonl", ["assistant", "user"])
        sf2 = self._write_session_file(tmp_path, "s2.jsonl", ["assistant", "user"])
        sf3 = self._write_session_file(tmp_path, "s3.jsonl", ["assistant", "user"])
        sessions_json = self._write_sessions_json(tmp_path, {
            "agent:nova:discord:channel:123": {"updatedAt": now_ms - 1000, "sessionFile": sf1},
            "agent:nova:main:heartbeat": {"updatedAt": now_ms - 500, "sessionFile": sf2},
            "agent:nova:cron:abc": {"updatedAt": now_ms - 300, "sessionFile": sf3},
        })
        with patch.object(m, "SESSIONS_JSON", sessions_json):
            result = m.check_step2_unanswered_sessions()
        # Only the discord channel should count
        assert result["data"]["count"] == 1

    def test_sessions_json_missing(self, m, tmp_path):
        missing = str(tmp_path / "no-such-sessions.json")
        with patch.object(m, "SESSIONS_JSON", missing):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False
        assert "error" in result

    def test_sessions_json_malformed(self, m, tmp_path):
        path = tmp_path / "sessions.json"
        path.write_text("not json")
        with patch.object(m, "SESSIONS_JSON", str(path)):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False
        assert "error" in result

    def test_missing_session_file_skipped(self, m, tmp_path):
        """A session entry with no sessionFile on disk should be skipped, not error."""
        now_ms = int(time.time() * 1000)
        missing_file = str(tmp_path / "does-not-exist.jsonl")
        sessions_json = self._write_sessions_json(tmp_path, {
            "agent:nova:discord:channel:123": {"updatedAt": now_ms - 1000, "sessionFile": missing_file},
        })
        with patch.object(m, "SESSIONS_JSON", sessions_json):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False


# ---------------------------------------------------------------------------
# Step 3 — introspection
# ---------------------------------------------------------------------------

class TestStep3Introspection:
    def _make_heartbeat_state(self, lines: int, bytez: int, hours_ago: float) -> str:
        return json.dumps({
            "lastIntrospection": {
                "dailyLogLines": lines,
                "sessionTranscriptBytes": bytez,
                "timestamp": _iso(hours_ago),
            }
        })

    def test_no_thresholds_exceeded(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 2.0))

        mock_wc = MagicMock()
        mock_wc.returncode = 0
        mock_wc.stdout = "102 /path/to/log"  # only 2 lines growth

        mock_du = MagicMock()
        mock_du.returncode = 0
        mock_du.stdout = "1050000"  # 50KB growth (< 100KB threshold)

        def fake_run(cmd, **kwargs):
            if "wc" in cmd[0] if isinstance(cmd, list) else cmd:
                return mock_wc
            return mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_time_threshold_exceeded(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 10.0))  # 10h ago

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1001000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "10.0h" in result["reason"]

    def test_line_growth_threshold_exceeded(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 2.0))

        mock_wc = MagicMock(); mock_wc.returncode = 0
        mock_wc.stdout = "160 /path"   # 60 lines growth (> 50 threshold)
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1001000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "60 new daily log lines" in result["reason"]

    def test_byte_growth_threshold_exceeded(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 2.0))

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0
        mock_du.stdout = "1200000"  # 200KB growth (> 100KB threshold)

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "bytes" in result["reason"]

    def test_missing_state_file_is_actionable(self, m, tmp_path):
        missing = str(tmp_path / "nonexistent.json")
        with patch.object(m, "HEARTBEAT_STATE_JSON", missing):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "missing" in result["reason"].lower() or "first run" in result["reason"].lower()

    def test_malformed_state_file_is_actionable(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text("{bad json{{")
        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)):
            result = m.check_step3_introspection()
        assert result["actionable"] is True

    def test_cooldown_active_blocks_introspection(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 0.5))

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        assert "Cooldown active" in result["reason"]
        assert abs(result["data"]["remaining_hours"] - 1.5) < 0.1

    def test_cooldown_expired_proceeds_to_thresholds(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 2.5))

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1050000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        assert "Cooldown active" not in result["reason"]
        assert result["reason"] == "No introspection threshold exceeded"

    def test_cooldown_boundary_exactly_2h_not_blocked(self, m, tmp_path):
        fixed_now = datetime(2026, 6, 15, 12, 0, 0, tzinfo=timezone.utc)
        timestamp = (fixed_now - timedelta(hours=2.0)).strftime("%Y-%m-%dT%H:%M:%SZ")
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(json.dumps({
            "lastIntrospection": {
                "dailyLogLines": 100,
                "sessionTranscriptBytes": 1_000_000,
                "timestamp": timestamp,
            }
        }))

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1050000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch.object(m, "_now_utc", return_value=fixed_now), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        assert "Cooldown active" not in result["reason"]
        assert result["reason"] == "No introspection threshold exceeded"

    def test_cooldown_expired_force_trigger_9h(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 9.0))

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1001000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "h since last introspection" in result["reason"]
        assert "Cooldown active" not in result["reason"]

    def test_cooldown_no_timestamp_falls_through_to_thresholds(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(json.dumps({
            "lastIntrospection": {
                "dailyLogLines": 100,
                "sessionTranscriptBytes": 1_000_000,
            }
        }))

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1050000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        assert result["reason"] == "No introspection threshold exceeded"

    def test_cooldown_malformed_timestamp_falls_through(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(json.dumps({
            "lastIntrospection": {
                "dailyLogLines": 100,
                "sessionTranscriptBytes": 1_000_000,
                "timestamp": "not-a-valid-date",
            }
        }))

        mock_wc = MagicMock(); mock_wc.returncode = 0; mock_wc.stdout = "102 /path"
        mock_du = MagicMock(); mock_du.returncode = 0; mock_du.stdout = "1050000"

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        assert "elapsed_error" in result["data"]
        assert result["reason"] == "No introspection threshold exceeded"

    def test_cooldown_response_format(self, m, tmp_path):
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._make_heartbeat_state(100, 1_000_000, 0.5))

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)):
            result = m.check_step3_introspection()
        assert set(result.keys()) == {"actionable", "reason", "data"}
        assert set(result["data"].keys()) == {"elapsed_hours", "remaining_hours"}
        assert isinstance(result["data"]["elapsed_hours"], float)
        assert isinstance(result["data"]["remaining_hours"], float)
        assert 0.0 <= result["data"]["elapsed_hours"] < 2.0
        assert 0.0 < result["data"]["remaining_hours"] <= 2.0


# ---------------------------------------------------------------------------
# Step 3 — introspection dual-mirror heartbeat state
# ---------------------------------------------------------------------------

class TestStep3IntrospectionDualMirror:
    def _make_heartbeat_state(self, lines: int, bytez: int, hours_ago: float) -> str:
        return json.dumps({
            "lastIntrospection": {
                "dailyLogLines": lines,
                "sessionTranscriptBytes": bytez,
                "timestamp": _iso(hours_ago),
            }
        })

    def _fake_run(self, mock_wc, mock_du):
        def fake_run(cmd, **kwargs):
            if isinstance(cmd, list) and cmd[0] == "wc":
                return mock_wc
            return mock_du
        return fake_run

    def _no_threshold_mocks(self):
        mock_wc = MagicMock()
        mock_wc.returncode = 0
        mock_wc.stdout = "102 /path"  # 2-line growth
        mock_du = MagicMock()
        mock_du.returncode = 0
        mock_du.stdout = "1050000"  # 50KB growth
        return mock_wc, mock_du

    def test_both_exist_primary_newer_uses_primary(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        primary_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))
        alt_file.write_text(self._make_heartbeat_state(100, 1_000_000, 8.0))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_both_exist_alt_newer_uses_alt(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        primary_file.write_text(self._make_heartbeat_state(100, 1_000_000, 9.0))
        alt_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_only_primary_exists_uses_primary(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        primary_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))
        # alt_file intentionally does not exist

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_only_alt_exists_uses_alt(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        # primary_file intentionally does not exist
        alt_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_neither_exists_triggers_introspection(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        # Neither file exists

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "missing" in result["reason"].lower()

    def test_primary_malformed_alt_valid_uses_alt(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        primary_file.write_text("{bad json{{")
        alt_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_alt_malformed_primary_valid_uses_primary(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        primary_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))
        alt_file.write_text("{bad json{{")

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False

    def test_same_timestamp_uses_primary(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        # Relative (3h ago) rather than a hardcoded absolute date so this test
        # doesn't bit-rot as real time passes and eventually cross the
        # INTROSPECT_TIME_THRESHOLD_H threshold regardless of tie-break winner.
        fixed_ts = _iso(3.0)
        primary_file.write_text(json.dumps({
            "lastIntrospection": {
                "dailyLogLines": 100,
                "sessionTranscriptBytes": 1_000_000,
                "timestamp": fixed_ts,
            }
        }))
        alt_file.write_text(json.dumps({
            "lastIntrospection": {
                "dailyLogLines": 999,
                "sessionTranscriptBytes": 9_000_000,
                "timestamp": fixed_ts,
            }
        }))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        # Primary wins tie, so it uses baseline 100/1M → no thresholds exceeded.
        assert result["actionable"] is False

    def test_both_malformed_triggers_introspection(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        primary_file.write_text("{bad json{{")
        alt_file.write_text("{also bad{{")

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)):
            result = m.check_step3_introspection()
        assert result["actionable"] is True

    def test_sync_writes_stale_copy(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        # Primary is stale; alt is fresher and has different values.
        primary_file.write_text(self._make_heartbeat_state(100, 1_000_000, 9.0))
        alt_state = {
            "lastIntrospection": {
                "dailyLogLines": 200,
                "sessionTranscriptBytes": 2_000_000,
                "timestamp": _iso(3.0),
            }
        }
        alt_file.write_text(json.dumps(alt_state))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        synced = json.loads(primary_file.read_text())
        assert synced["lastIntrospection"]["dailyLogLines"] == 200
        assert synced["lastIntrospection"]["sessionTranscriptBytes"] == 2_000_000

    def test_sync_does_not_create_nonexistent_file(self, m, tmp_path):
        primary_file = tmp_path / "primary.json"
        alt_file = tmp_path / "alt.json"
        # Only alt exists; primary is missing.
        alt_file.write_text(self._make_heartbeat_state(100, 1_000_000, 3.0))

        mock_wc, mock_du = self._no_threshold_mocks()

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(primary_file)), \
             patch.object(m, "HEARTBEAT_STATE_JSON_ALT", str(alt_file)), \
             patch("subprocess.run", side_effect=self._fake_run(mock_wc, mock_du)):
            result = m.check_step3_introspection()
        assert result["actionable"] is False
        assert not primary_file.exists()


# ---------------------------------------------------------------------------
# Step 4 — memory maintenance
# ---------------------------------------------------------------------------

class TestStep4MemoryMaintenance:
    def test_within_cooldown(self, m, tmp_path):
        state_file = tmp_path / "memory-maintenance.json"
        state_file.write_text(json.dumps({"last_run": _iso(1.0)}))  # 1h ago, threshold 4h
        with patch.object(m, "MEMORY_MAINTENANCE_JSON", str(state_file)):
            result = m.check_step4_memory_maintenance()
        assert result["actionable"] is False
        assert "remaining" in result["reason"].lower()

    def test_beyond_cooldown(self, m, tmp_path):
        state_file = tmp_path / "memory-maintenance.json"
        state_file.write_text(json.dumps({"last_run": _iso(5.0)}))  # 5h ago, threshold 4h
        with patch.object(m, "MEMORY_MAINTENANCE_JSON", str(state_file)):
            result = m.check_step4_memory_maintenance()
        assert result["actionable"] is True

    def test_missing_file_is_actionable(self, m, tmp_path):
        missing = str(tmp_path / "nonexistent.json")
        with patch.object(m, "MEMORY_MAINTENANCE_JSON", missing):
            result = m.check_step4_memory_maintenance()
        assert result["actionable"] is True

    def test_malformed_file_is_actionable(self, m, tmp_path):
        state_file = tmp_path / "memory-maintenance.json"
        state_file.write_text("{invalid}")
        with patch.object(m, "MEMORY_MAINTENANCE_JSON", str(state_file)):
            result = m.check_step4_memory_maintenance()
        assert result["actionable"] is True

    def test_missing_last_run_key(self, m, tmp_path):
        state_file = tmp_path / "memory-maintenance.json"
        state_file.write_text(json.dumps({"other_key": "value"}))
        with patch.object(m, "MEMORY_MAINTENANCE_JSON", str(state_file)):
            result = m.check_step4_memory_maintenance()
        assert result["actionable"] is True


# ---------------------------------------------------------------------------
# Step 5 — entity dedup
# ---------------------------------------------------------------------------

class TestStep5EntityDedup:
    def _mock_conn(self, count: int) -> MagicMock:
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        mock_cur.fetchone.return_value = (count,)
        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        return mock_conn

    def test_no_duplicates(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(0)):
            result = m.check_step5_entity_dedup()
        assert result["actionable"] is False

    def test_duplicates_found(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(1)):
            result = m.check_step5_entity_dedup()
        assert result["actionable"] is True

    def test_db_failure_not_actionable(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("connection failed")):
            result = m.check_step5_entity_dedup()
        assert result["actionable"] is False
        assert "error" in result

    def test_pg_trgm_missing_reports_error(self, m):
        err = Exception("function similarity(character varying, character varying) does not exist")
        with patch.object(m, "_db_connect", side_effect=err):
            result = m.check_step5_entity_dedup()
        assert "error" in result
        assert result["actionable"] is False


# ---------------------------------------------------------------------------
# Step 6 — pending tasks
# ---------------------------------------------------------------------------

class TestStep6PendingTasks:
    def _mock_conn(self, count: int) -> MagicMock:
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        mock_cur.fetchone.return_value = (count,)
        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        return mock_conn

    def test_no_pending_tasks(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(0)):
            result = m.check_step6_pending_tasks()
        assert result["actionable"] is False

    def test_pending_tasks_present(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(5)):
            result = m.check_step6_pending_tasks()
        assert result["actionable"] is True
        assert result["data"]["count"] == 5

    def test_db_failure(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("db error")):
            result = m.check_step6_pending_tasks()
        assert result["actionable"] is False
        assert "error" in result


# ---------------------------------------------------------------------------
# Step 7 — GitHub issues
# ---------------------------------------------------------------------------

class TestStep7GithubIssues:
    def test_issues_found(self, m):
        calls = []
        def fake_run(cmd, **kwargs):
            result = MagicMock()
            result.returncode = 0
            if "repo" in cmd and "list" in cmd:
                result.stdout = "nova-mind\nnova-openclaw\n"
            else:
                result.stdout = "3"
                calls.append(cmd)
            return result

        with patch("subprocess.run", side_effect=fake_run):
            result = m.check_step7_github_issues()
        assert result["actionable"] is True
        assert result["data"]["total"] == 6  # 2 repos × 3

    def test_no_issues(self, m):
        def fake_run(cmd, **kwargs):
            r = MagicMock(); r.returncode = 0
            r.stdout = "nova-mind\n" if "repo" in cmd and "list" in cmd else "0"
            return r

        with patch("subprocess.run", side_effect=fake_run):
            result = m.check_step7_github_issues()
        assert result["actionable"] is False

    def test_gh_not_found(self, m):
        with patch("subprocess.run", side_effect=FileNotFoundError):
            result = m.check_step7_github_issues()
        assert result["actionable"] is False
        assert "error" in result

    def test_gh_repo_list_failure(self, m):
        r = MagicMock(); r.returncode = 1; r.stderr = "auth error"
        with patch("subprocess.run", return_value=r):
            result = m.check_step7_github_issues()
        assert result["actionable"] is False
        assert "error" in result

    def test_no_repos_found(self, m):
        r = MagicMock(); r.returncode = 0; r.stdout = ""
        with patch("subprocess.run", return_value=r):
            result = m.check_step7_github_issues()
        assert result["actionable"] is False

    def test_partial_repo_failure_still_counts(self, m):
        call_count = [0]

        def fake_run(cmd, **kwargs):
            r = MagicMock(); r.returncode = 0
            if "repo" in cmd and "list" in cmd:
                r.stdout = "good-repo\nbad-repo\n"
                return r
            call_count[0] += 1
            repo_slug = next((a for a in cmd if "/" in a), "")
            if "bad-repo" in repo_slug:
                r.returncode = 1; r.stderr = "not found"
            else:
                r.stdout = "4"
            return r

        with patch("subprocess.run", side_effect=fake_run):
            result = m.check_step7_github_issues()
        assert result["actionable"] is True
        assert result["data"]["total"] == 4
        assert len(result["data"]["errors"]) == 1


# ---------------------------------------------------------------------------
# Step 8 — unsolved problems
# ---------------------------------------------------------------------------

class TestStep9UnsolvedProblems:
    def _mock_conn(self, count: int) -> MagicMock:
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        mock_cur.fetchone.return_value = (count,)
        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        return mock_conn

    def test_no_unsolved_problems(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(0)):
            result = m.check_step9_unsolved_problems()
        assert result["actionable"] is False
        # D-2 revert: no last_worked_at/3-day-cooldown predicate in this PR;
        # reason string restored to the pre-PR count-only form.
        assert result["reason"] == "0 unsolved problems"

    def test_unsolved_problems_present(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(3)):
            result = m.check_step9_unsolved_problems()
        assert result["actionable"] is True
        assert result["data"]["count"] == 3
        assert result["reason"] == "3 unsolved problem(s) awaiting research"

    def test_db_failure(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("db error")):
            result = m.check_step9_unsolved_problems()
        assert result["actionable"] is False
        assert "error" in result


# ---------------------------------------------------------------------------
# Step 8 — blocker outreach
# ---------------------------------------------------------------------------

class TestStep8BlockerOutreach:
    """Tests for check_step8_blocker_outreach().

    The function issues three DB round-trips via a single connection:
      1. main SELECT joining blockers + entities + LATERAL proactive_outreach
         (per-blocker attempt_count / latest_attempt)
      2. entity master-cooldown SELECT (MAX(attempted_at) GROUP BY entity_id)
      3. (helpers) _entity_channel_facts / _entity_is_agent, one query each,
         called per-entity outside the main connection block.

    We mock _db_connect to return a context-manager connection whose
    cursor.execute/fetchall are driven by a small dispatcher keyed on the
    SQL text, and separately patch _entity_channel_facts / _entity_is_agent
    since those open their own connections.
    """

    def _row(
        self,
        bid: int,
        entity_id: int,
        entity_name: str = "entity",
        priority: int = 5,
        first_seen_hours_ago: float = 1.0,
        attempt_count: int = 0,
        latest_attempt_hours_ago: float | None = None,
        source_type: str = "task",
        source_ref: str = "ref-1",
    ):
        latest_attempt = (
            "epoch"
            if latest_attempt_hours_ago is None
            else datetime.now(timezone.utc) - timedelta(hours=latest_attempt_hours_ago)
        )
        if latest_attempt == "epoch":
            latest_attempt = datetime(1970, 1, 1, tzinfo=timezone.utc)
        return (
            bid,
            source_type,
            source_ref,
            f"desc-{bid}",
            f"needs-{bid}",
            entity_id,
            entity_name,
            priority,
            datetime.now(timezone.utc) - timedelta(hours=first_seen_hours_ago),
            attempt_count,
            latest_attempt,
        )

    def _mock_conn(self, rows: list, entity_master: dict[int, Any]):
        """Build a mock connection whose cursor dispatches on query text."""
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)

        state = {"last": None}

        def fake_execute(sql, params=None):
            if "FROM blockers b" in sql:
                state["last"] = "main"
            elif "GROUP BY entity_id" in sql:
                state["last"] = "master"
            else:
                state["last"] = "other"

        def fake_fetchall():
            if state["last"] == "main":
                return rows
            if state["last"] == "master":
                return list(entity_master.items())
            return []

        mock_cur.execute.side_effect = fake_execute
        mock_cur.fetchall.side_effect = fake_fetchall

        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        mock_conn.close = MagicMock()
        return mock_conn

    def _patched(self, m, rows, entity_master=None, channels=None, is_agent=None):
        """Context manager patching _db_connect + the per-entity helpers."""
        entity_master = entity_master or {}
        channels = channels if channels is not None else {}
        is_agent = is_agent if is_agent is not None else False
        conn = self._mock_conn(rows, entity_master)
        return (
            patch.object(m, "_db_connect", return_value=conn),
            patch.object(m, "_entity_channel_facts", return_value=channels),
            patch.object(m, "_entity_is_agent", return_value=is_agent),
        )

    # ---- cooldown boundaries ----

    def test_entity_master_cooldown_exactly_24h_is_blocked(self, m):
        """Master cooldown is strict >24h: exactly 24h elapsed must still be blocked.

        A 100ms safety margin is added so the row's timestamp is captured
        very slightly *after* the true 24h mark, absorbing the microseconds
        that elapse before the function's internal _now_utc() call runs —
        otherwise this boundary test is flaky (real elapsed drifts just past
        24h and is treated as eligible).
        """
        rows = [self._row(1, entity_id=10, attempt_count=0)]
        master = {10: datetime.now(timezone.utc) - timedelta(hours=24.0) + timedelta(milliseconds=100)}
        p1, p2, p3 = self._patched(m, rows, entity_master=master)
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is False

    def test_entity_master_cooldown_24h_plus_1s_is_eligible(self, m):
        rows = [self._row(1, entity_id=10, attempt_count=0)]
        master = {10: datetime.now(timezone.utc) - timedelta(hours=24.0, seconds=1)}
        p1, p2, p3 = self._patched(m, rows, entity_master=master)
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is True

    def test_per_blocker_cooldown_exactly_72h_is_blocked(self, m):
        """Per-blocker cooldown is strict >72h: exactly 72h elapsed must still be blocked.

        Uses a 100ms-under-72h delta (see note on the 24h master-cooldown
        boundary test above) to avoid boundary flakiness.
        """
        rows = [self._row(
            1, entity_id=10, attempt_count=1,
            latest_attempt_hours_ago=72.0 - (0.1 / 3600),
        )]
        p1, p2, p3 = self._patched(m, rows, entity_master={})
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is False

    def test_per_blocker_cooldown_72h_plus_1s_is_eligible(self, m):
        rows = [self._row(
            1, entity_id=10, attempt_count=1,
            latest_attempt_hours_ago=72.0 + (1 / 3600),
        )]
        p1, p2, p3 = self._patched(m, rows, entity_master={})
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is True

    # ---- never-contacted entity ----

    def test_never_contacted_entity_is_eligible(self, m):
        """No proactive_outreach rows at all (empty master dict, epoch latest_attempt)."""
        rows = [self._row(1, entity_id=10, attempt_count=0, latest_attempt_hours_ago=None)]
        p1, p2, p3 = self._patched(m, rows, entity_master={})
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is True
        assert result["data"]["eligible_entities"][0]["selected_blockers"][0]["cascade_level"] == 1

    # ---- non-blocker outreach triggers master but not per-blocker cooldown ----

    def test_non_blocker_outreach_triggers_master_not_per_blocker(self, m):
        """A proactive_outreach row for a *different* blocker_type/id still counts
        toward the entity master cooldown (any row for the entity), but the
        per-blocker cooldown for THIS blocker is independent — attempt_count
        for this blocker's LATERAL join is 0 since the row is keyed to a
        different blocker_id, so its own cooldown is unaffected. The master
        cooldown (recent) should block the entity outright.
        """
        rows = [self._row(1, entity_id=10, attempt_count=0, latest_attempt_hours_ago=None)]
        # Master cooldown recent (1h ago) from an unrelated (e.g. non-blocker) row
        master = {10: datetime.now(timezone.utc) - timedelta(hours=1.0)}
        p1, p2, p3 = self._patched(m, rows, entity_master=master)
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        # Blocked by master cooldown even though per-blocker attempt_count is 0
        assert result["actionable"] is False

    # ---- top-3 tiebreak determinism ----

    def test_top_3_tiebreak_determinism(self, m):
        """5 blockers for one entity, all same priority/first_seen — only first
        3 by id (as returned in SQL ORDER BY) are selected."""
        now_h = 1.0
        rows = [
            self._row(i, entity_id=10, priority=5, first_seen_hours_ago=now_h, attempt_count=0)
            for i in range(1, 6)
        ]
        p1, p2, p3 = self._patched(m, rows, entity_master={})
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is True
        selected = result["data"]["eligible_entities"][0]["selected_blockers"]
        assert len(selected) == 3
        assert [b["id"] for b in selected] == [1, 2, 3]

    def test_top_3_respects_priority_ordering(self, m):
        """Lower priority number sorts first (already ordered by SQL); function
        must preserve incoming row order, not re-sort."""
        rows = [
            self._row(3, entity_id=10, priority=1, attempt_count=0),
            self._row(1, entity_id=10, priority=2, attempt_count=0),
            self._row(2, entity_id=10, priority=3, attempt_count=0),
        ]
        p1, p2, p3 = self._patched(m, rows, entity_master={})
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        selected = result["data"]["eligible_entities"][0]["selected_blockers"]
        assert [b["id"] for b in selected] == [3, 1, 2]

    # ---- empty tables ----

    def test_empty_blockers_table(self, m):
        p1, p2, p3 = self._patched(m, rows=[], entity_master={})
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is False
        assert "reason" in result

    def test_db_failure(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("db error")):
            result = m.check_step8_blocker_outreach()
        assert result["actionable"] is False
        assert "error" in result

    # ---- cascade level -> channel mapping ----

    def test_cascade_level_maps_to_agent_chat_for_agents(self, m):
        rows = [self._row(1, entity_id=99, attempt_count=0)]
        p1, p2, p3 = self._patched(m, rows, entity_master={}, is_agent=True)
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        entity = result["data"]["eligible_entities"][0]
        assert entity["actual_channel"] == "agent_chat"

    def test_cascade_level_maps_to_available_human_channel(self, m):
        rows = [self._row(1, entity_id=2, attempt_count=0)]
        channels = {"discord_channel": "123", "discord_dm": "123", "email": "x@y.com"}
        p1, p2, p3 = self._patched(m, rows, entity_master={}, channels=channels, is_agent=False)
        with p1, p2, p3:
            result = m.check_step8_blocker_outreach()
        entity = result["data"]["eligible_entities"][0]
        assert entity["actual_channel"] == "discord_channel"

    # ---- cascade exhaustion + reassignment (D-1 fix, ruling #7 / TC-D07) ----

    def test_zero_channels_zero_attempts_triggers_reassignment(self, m):
        """Entity with 0 contact channels and 0 prior attempts (cascade_level=1)
        is immediately exhausted (1 > 0 available channels) — must reassign
        rather than silently returning 'none'."""
        rows = [self._row(1, entity_id=10, attempt_count=0)]
        p1, p2, p3 = self._patched(m, rows, entity_master={}, channels={}, is_agent=False)
        with (
            p1, p2, p3,
            patch.object(m, "_reassign_exhausted_entity", return_value=(20, False)) as mock_reassign,
            patch.object(m, "_entity_channel_facts", side_effect=lambda eid: {"discord_channel": "abc"} if eid == 20 else {}),
            patch.object(m, "_entity_is_agent", return_value=False),
            patch.object(m, "_entity_name_lookup", return_value="Next Entity"),
        ):
            result = m.check_step8_blocker_outreach()
        entity = result["data"]["eligible_entities"][0]
        mock_reassign.assert_called_once_with(10, {10})
        assert entity["entity_id"] == 20
        assert entity["reassigned_from_entity_id"] == 10
        assert entity["exhausted"] is False
        assert entity["max_cascade_level"] == 1
        assert entity["actual_channel"] == "discord_channel"

    def test_n_channels_level_n_plus_1_triggers_reassignment(self, m):
        """Entity with N channels, cascade_level = N+1 (first exhaustion past
        the ceiling) — must reassign rather than repeating the last channel
        silently."""
        # attempt_count=2 -> cascade_level=3; only 2 channels available (N=2)
        # so level 3 > 2 available channels -> exhausted.
        rows = [self._row(1, entity_id=11, attempt_count=2)]
        channels = {"discord_channel": "123", "discord_dm": "123"}
        p1, p2, p3 = self._patched(m, rows, entity_master={}, channels=channels, is_agent=False)
        with (
            p1, p2, p3,
            patch.object(m, "_reassign_exhausted_entity", return_value=(30, False)) as mock_reassign,
            patch.object(m, "_entity_channel_facts", side_effect=lambda eid: {"signal": "sig"} if eid == 30 else channels),
            patch.object(m, "_entity_is_agent", return_value=False),
            patch.object(m, "_entity_name_lookup", return_value="Reassigned Entity"),
        ):
            result = m.check_step8_blocker_outreach()
        entity = result["data"]["eligible_entities"][0]
        mock_reassign.assert_called_once_with(11, {11})
        assert entity["entity_id"] == 30
        assert entity["reassigned_from_entity_id"] == 11
        assert entity["max_cascade_level"] == 1
        assert entity["actual_channel"] == "signal"

    def test_iruid_exhausted_holds_no_reassignment(self, m):
        """Entity is I)ruid (entity_id=2); cascade_level exceeds his channel
        count. Must NOT reassign — holds at his last available channel and
        is marked exhausted=True so the agent turn knows to keep the 72h
        cadence rather than escalate further."""
        # attempt_count=3 -> cascade_level=4; only 1 channel available -> exhausted.
        rows = [self._row(1, entity_id=2, attempt_count=3)]
        channels = {"discord_channel": "123"}
        p1, p2, p3 = self._patched(m, rows, entity_master={}, channels=channels, is_agent=False)
        with (
            p1, p2, p3,
            patch.object(m, "_reassign_exhausted_entity") as mock_reassign,
        ):
            result = m.check_step8_blocker_outreach()
        entity = result["data"]["eligible_entities"][0]
        mock_reassign.assert_not_called()
        assert entity["entity_id"] == 2
        assert entity["exhausted"] is True
        assert entity["max_cascade_level"] == 4
        assert entity["actual_channel"] == "discord_channel"
        assert "reassigned_from_entity_id" not in entity

    def test_full_reassignment_chain_falls_to_iruid(self, m):
        """Original entity exhausted -> reassigned entity ALSO exhausted ->
        falls through to I)ruid (entity_id=2) as final fallback."""
        rows = [self._row(1, entity_id=10, attempt_count=0)]
        p1, p2, p3 = self._patched(m, rows, entity_master={}, channels={}, is_agent=False)

        # First reassignment: 10 -> 40 (also exhausted, 0 channels).
        # Second reassignment: 40 -> 2 (I)ruid, final fallback), with channels.
        reassign_calls = {"count": 0}

        def fake_reassign(entity_id, exclude_ids):
            reassign_calls["count"] += 1
            if reassign_calls["count"] == 1:
                assert entity_id == 10
                assert exclude_ids == {10}
                return 40, False
            assert entity_id == 40
            assert exclude_ids == {10, 40}
            return 2, True

        def fake_channels(eid):
            if eid == 2:
                return {"discord_channel": "999"}
            return {}

        with (
            p1, p2, p3,
            patch.object(m, "_reassign_exhausted_entity", side_effect=fake_reassign) as mock_reassign,
            patch.object(m, "_entity_channel_facts", side_effect=fake_channels),
            patch.object(m, "_entity_is_agent", return_value=False),
            patch.object(m, "_entity_name_lookup", return_value="I)ruid"),
        ):
            result = m.check_step8_blocker_outreach()
        entity = result["data"]["eligible_entities"][0]
        assert mock_reassign.call_count == 2
        assert entity["entity_id"] == 2
        assert entity["reassigned_from_entity_id"] == 10
        assert entity["exhausted"] is False  # landed on I)ruid with a channel, not a hold
        assert entity["max_cascade_level"] == 1
        assert entity["actual_channel"] == "discord_channel"


# ---------------------------------------------------------------------------
# Cascade exhaustion helpers — direct unit coverage (D-1 fix)
# ---------------------------------------------------------------------------

class TestIsCascadeExhausted:
    def test_agent_never_exhausted(self, m):
        assert m._is_cascade_exhausted(99, {}, is_agent=True) is False

    def test_zero_channels_exhausted_at_level_1(self, m):
        assert m._is_cascade_exhausted(1, {}, is_agent=False) is True

    def test_level_within_available_channels_not_exhausted(self, m):
        channels = {"discord_channel": "1", "discord_dm": "1", "signal": "s"}
        assert m._is_cascade_exhausted(3, channels, is_agent=False) is False

    def test_level_exceeding_available_channels_exhausted(self, m):
        channels = {"discord_channel": "1", "discord_dm": "1"}
        assert m._is_cascade_exhausted(3, channels, is_agent=False) is True


class TestEntityDomainTopics:
    def _mock_conn_for_topics(self, agent_rows, user_rows, exists_rows=None):
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        state = {"last": None}

        def fake_execute(sql, params=None):
            state["last"] = "agent" if "ad.domain_topic" in sql else "user"

        def fake_fetchall():
            if state["last"] == "agent":
                return agent_rows
            return user_rows

        mock_cur.execute.side_effect = fake_execute
        mock_cur.fetchall.side_effect = fake_fetchall

        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        mock_conn.close = MagicMock()
        return mock_conn

    def test_combines_agent_and_user_domain_topics(self, m):
        conn = self._mock_conn_for_topics(
            agent_rows=[("Software Engineering",)],
            user_rows=[("Project Leadership",)],
        )
        with patch.object(m, "_db_connect", return_value=conn):
            topics = m._entity_domain_topics(2)
        assert topics == ["Project Leadership", "Software Engineering"]

    def test_db_failure_returns_empty_list(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("db down")):
            topics = m._entity_domain_topics(2)
        assert topics == []


class TestNextDomainEntity:
    def _mock_conn(self, agent_row, user_row):
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        state = {"last": None}

        def fake_execute(sql, params=None):
            state["last"] = "agent" if "agent_domains ad" in sql else "user"

        def fake_fetchone():
            return agent_row if state["last"] == "agent" else user_row

        mock_cur.execute.side_effect = fake_execute
        mock_cur.fetchone.side_effect = fake_fetchone

        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        mock_conn.close = MagicMock()
        return mock_conn

    def test_agent_domains_wins_when_present_and_not_excluded(self, m):
        conn = self._mock_conn(agent_row=(50,), user_row=(60,))
        with patch.object(m, "_db_connect", return_value=conn):
            result = m._next_domain_entity("Software Engineering", set())
        assert result == 50

    def test_falls_back_to_user_domains_when_agent_excluded(self, m):
        conn = self._mock_conn(agent_row=(50,), user_row=(60,))
        with patch.object(m, "_db_connect", return_value=conn):
            result = m._next_domain_entity("Software Engineering", {50})
        assert result == 60

    def test_returns_none_when_no_candidate(self, m):
        conn = self._mock_conn(agent_row=None, user_row=None)
        with patch.object(m, "_db_connect", return_value=conn):
            result = m._next_domain_entity("obscure-topic", set())
        assert result is None

    def test_db_failure_returns_none(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("db down")):
            result = m._next_domain_entity("Software Engineering", set())
        assert result is None


class TestReassignExhaustedEntity:
    def test_reassigns_to_next_domain_entity(self, m):
        with (
            patch.object(m, "_entity_domain_topics", return_value=["Software Engineering"]),
            patch.object(m, "_next_domain_entity", return_value=99),
        ):
            new_id, is_final = m._reassign_exhausted_entity(10, set())
        assert new_id == 99
        assert is_final is False

    def test_falls_back_to_iruid_when_no_topics_owned(self, m):
        with patch.object(m, "_entity_domain_topics", return_value=[]):
            new_id, is_final = m._reassign_exhausted_entity(10, set())
        assert new_id == 2
        assert is_final is True

    def test_falls_back_to_iruid_when_all_topic_candidates_excluded(self, m):
        with (
            patch.object(m, "_entity_domain_topics", return_value=["Some Topic"]),
            patch.object(m, "_next_domain_entity", return_value=None),
        ):
            new_id, is_final = m._reassign_exhausted_entity(10, set())
        assert new_id == 2
        assert is_final is True

    def test_exclude_set_includes_entity_itself(self, m):
        """The exhausted entity is always added to the exclusion set passed
        to _next_domain_entity, even if the caller's exclude set didn't
        already contain it."""
        with (
            patch.object(m, "_entity_domain_topics", return_value=["Topic"]),
            patch.object(m, "_next_domain_entity") as mock_next,
        ):
            mock_next.return_value = 5
            m._reassign_exhausted_entity(10, {7})
        mock_next.assert_called_once_with("Topic", {7, 10})


# ---------------------------------------------------------------------------
# Step 10 — filesystem hygiene
# ---------------------------------------------------------------------------

class TestStep10FilesystemHygiene:
    def test_recently_audited_not_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text(_iso(24.0))  # 1 day ago, threshold 7 days
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step10_filesystem_hygiene()
        assert result["actionable"] is False

    def test_stale_audit_is_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text(_iso(8 * 24.0))  # 8 days ago, threshold 7 days
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step10_filesystem_hygiene()
        assert result["actionable"] is True

    def test_missing_marker_is_actionable(self, m, tmp_path):
        missing = str(tmp_path / "no-such-file")
        with patch.object(m, "FS_AUDIT_MARKER", missing):
            result = m.check_step10_filesystem_hygiene()
        assert result["actionable"] is True

    def test_empty_marker_is_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text("")
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step10_filesystem_hygiene()
        assert result["actionable"] is True

    def test_malformed_timestamp_is_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text("not-a-timestamp")
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step10_filesystem_hygiene()
        assert result["actionable"] is True


# ---------------------------------------------------------------------------
# Step 11 — D100
# ---------------------------------------------------------------------------

class TestStep11D100:
    def _mock_conn(self, last_rolled):
        mock_cur = MagicMock()
        mock_cur.__enter__ = MagicMock(return_value=mock_cur)
        mock_cur.__exit__ = MagicMock(return_value=False)
        mock_cur.fetchone.return_value = (last_rolled,)
        mock_conn = MagicMock()
        mock_conn.__enter__ = MagicMock(return_value=mock_conn)
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cur
        return mock_conn

    def test_mandatory_when_no_prior_work(self, m):
        """Last roll recent (<=12h), no prior actionable steps -> mandatory catch-all."""
        with patch.object(m, "_db_connect", return_value=self._mock_conn(datetime.now(timezone.utc) - timedelta(hours=1))):
            result = m.check_step11_d100(prior_actionable_count=0)
        assert result["actionable"] is True
        assert "mandatory" in result["reason"].lower()

    def test_optional_when_prior_work_exists(self, m):
        """Last roll recent (<=12h), prior actionable steps exist -> optional."""
        with patch.object(m, "_db_connect", return_value=self._mock_conn(datetime.now(timezone.utc) - timedelta(hours=1))):
            result = m.check_step11_d100(prior_actionable_count=3)
        assert result["actionable"] is False
        assert "optional" in result["reason"].lower()

    def test_boundary_one_prior_step(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(datetime.now(timezone.utc) - timedelta(hours=1))):
            result = m.check_step11_d100(prior_actionable_count=1)
        assert result["actionable"] is False

    # ---- forced D100 (issue #358) ----

    def test_forced_when_more_than_12h_since_last_roll(self, m):
        """Strictly >12h since last roll forces actionable, even with prior work."""
        last = datetime.now(timezone.utc) - timedelta(hours=12, seconds=1)
        with patch.object(m, "_db_connect", return_value=self._mock_conn(last)):
            result = m.check_step11_d100(prior_actionable_count=5)
        assert result["actionable"] is True
        assert "forced" in result["reason"].lower()

    def test_not_forced_at_exactly_12h(self, m):
        """Exactly 12h elapsed does not force (strict > threshold); falls back to
        the prior-actionable-count logic.

        A small safety margin (100ms) is subtracted from the 12h delta to
        absorb the microseconds that elapse between constructing `last` here
        and the function's internal _now_utc() call — without the margin this
        boundary test is flaky (elapsed drifts to just over 12h and forces).
        """
        last = datetime.now(timezone.utc) - timedelta(hours=12) + timedelta(milliseconds=100)
        with patch.object(m, "_db_connect", return_value=self._mock_conn(last)):
            result = m.check_step11_d100(prior_actionable_count=5)
        assert result["actionable"] is False
        assert "optional" in result["reason"].lower()

    def test_forced_when_no_roll_history(self, m):
        """No rows in d100_roll_log (MAX returns None) -> forced, regardless of
        prior actionable count."""
        with patch.object(m, "_db_connect", return_value=self._mock_conn(None)):
            result = m.check_step11_d100(prior_actionable_count=5)
        assert result["actionable"] is True
        assert "forced" in result["reason"].lower()

    def test_under_12h_preserves_mandatory_catch_all(self, m):
        """<=12h since last roll: 0 prior actionable -> mandatory (old behavior)."""
        last = datetime.now(timezone.utc) - timedelta(hours=6)
        with patch.object(m, "_db_connect", return_value=self._mock_conn(last)):
            result = m.check_step11_d100(prior_actionable_count=0)
        assert result["actionable"] is True
        assert "mandatory" in result["reason"].lower()

    def test_under_12h_preserves_optional_when_prior_work(self, m):
        """<=12h since last roll: prior actionable exists -> optional (old behavior)."""
        last = datetime.now(timezone.utc) - timedelta(hours=6)
        with patch.object(m, "_db_connect", return_value=self._mock_conn(last)):
            result = m.check_step11_d100(prior_actionable_count=2)
        assert result["actionable"] is False
        assert "optional" in result["reason"].lower()

    def test_db_failure_falls_back_to_forced(self, m):
        """DB error while checking roll history -> treated like no-history (forced),
        matching the code's `except Exception: last_rolled = None` fallback."""
        with patch.object(m, "_db_connect", side_effect=Exception("db error")):
            result = m.check_step11_d100(prior_actionable_count=5)
        assert result["actionable"] is True


# ---------------------------------------------------------------------------
# Output format validation
# ---------------------------------------------------------------------------

class TestOutputFormat:
    """Validate the JSON manifest emitted by main()."""

    def _run_main(self, m, idle: bool = True, monkeypatch=None) -> dict:
        """Run main() with all gate checks mocked; return parsed JSON output."""
        import io
        from unittest.mock import patch

        idle_data = {
            "idle": idle,
            "idle_minutes": 90.0 if idle else 10.0,
            "idle_threshold_minutes": 60,
        }
        not_actionable: dict[str, Any] = {"actionable": False, "reason": "mocked"}

        with patch.object(m, "check_idle", return_value=idle_data), \
             patch.object(m, "check_step1_agent_chat", return_value=not_actionable), \
             patch.object(m, "check_step2_unanswered_sessions", return_value=not_actionable), \
             patch.object(m, "check_step3_introspection", return_value=not_actionable), \
             patch.object(m, "check_step4_memory_maintenance", return_value=not_actionable), \
             patch.object(m, "check_step5_entity_dedup", return_value=not_actionable), \
             patch.object(m, "check_step6_pending_tasks", return_value=not_actionable), \
             patch.object(m, "check_step7_github_issues", return_value=not_actionable), \
             patch.object(m, "check_step8_blocker_outreach", return_value=not_actionable), \
             patch.object(m, "check_step9_unsolved_problems", return_value=not_actionable), \
             patch.object(m, "check_step10_filesystem_hygiene", return_value=not_actionable), \
             patch("builtins.print") as mock_print:
            m.main()
            printed = mock_print.call_args[0][0]

        return json.loads(printed)

    def test_idle_false_no_steps(self, m):
        output = self._run_main(m, idle=False)
        assert output["idle"] is False
        assert "steps" not in output

    def test_idle_true_has_all_steps(self, m):
        output = self._run_main(m, idle=True)
        assert output["idle"] is True
        assert "steps" in output
        for step_key in [
            "1_agent_chat", "2_unanswered", "3_introspect", "4_memory",
            "5_entities", "6_tasks", "7_github", "8_blocker_outreach",
            "9_research", "10_filesystem", "11_d100",
        ]:
            assert step_key in output["steps"], f"Missing step: {step_key}"

    def test_required_top_level_fields(self, m):
        output = self._run_main(m, idle=True)
        required = ["timestamp", "idle", "idle_minutes", "idle_threshold_minutes",
                    "steps", "actionable_steps", "actionable_count", "summary"]
        for field in required:
            assert field in output, f"Missing field: {field}"

    def test_actionable_steps_is_list_of_ints(self, m):
        output = self._run_main(m, idle=True)
        assert isinstance(output["actionable_steps"], list)
        for item in output["actionable_steps"]:
            assert isinstance(item, int)

    def test_d100_mandatory_when_all_others_not_actionable(self, m):
        output = self._run_main(m, idle=True)
        # All steps 1-10 mocked as not-actionable, so D100 must be mandatory
        # (this exercises the real check_step11_d100, which is NOT mocked by
        # _run_main; the DB call inside it will raise since there's no real
        # connection, which is treated as no-history -> forced actionable)
        assert 11 in output["actionable_steps"]
        assert output["steps"]["11_d100"]["actionable"] is True

    def test_timestamp_is_valid_iso(self, m):
        output = self._run_main(m, idle=True)
        ts = output["timestamp"]
        # Should parse without error
        datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")

    def test_summary_string_format(self, m):
        output = self._run_main(m, idle=True)
        assert "of 11 steps actionable" in output["summary"]

    def test_output_is_valid_json(self, m):
        """main() must print valid JSON — no exceptions."""
        import io
        with patch.object(m, "check_idle", return_value={"idle": False, "idle_minutes": 5.0, "idle_threshold_minutes": 60}), \
             patch("builtins.print") as mock_print:
            m.main()
            printed = mock_print.call_args[0][0]
        parsed = json.loads(printed)  # must not raise
        assert isinstance(parsed, dict)


# ---------------------------------------------------------------------------
# Boundary Value Analysis (BVA) — exact threshold values
# ---------------------------------------------------------------------------

class TestBoundaryValues:
    """Exact-boundary tests for all numeric thresholds (Fix C6)."""

    def _heartbeat_state(self, lines: int, bytez: int, hours_ago: float) -> str:
        return json.dumps({
            "lastIntrospection": {
                "dailyLogLines": lines,
                "sessionTranscriptBytes": bytez,
                "timestamp": _iso(hours_ago),
            }
        })

    # ---- Step 3: line growth exactly at threshold (50) ----

    def test_step3_line_growth_exactly_50_is_actionable(self, m, tmp_path):
        """Line growth == 50 (threshold >= 50) → actionable."""
        state_file = tmp_path / "heartbeat-state.json"
        # 1h ago — well below the 8h time threshold so time check won’t fire
        state_file.write_text(self._heartbeat_state(100, 1_000_000, 3.0))

        mock_wc = MagicMock()
        mock_wc.returncode = 0
        mock_wc.stdout = "150 /path"   # baseline=100, current=150 → growth=50
        mock_du = MagicMock()
        mock_du.returncode = 0
        mock_du.stdout = "1000000"     # 0 byte growth

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "50 new daily log lines" in result["reason"]

    # ---- Step 3: byte growth exactly at threshold (102400) ----

    def test_step3_byte_growth_exactly_102400_is_actionable(self, m, tmp_path):
        """Byte growth == 102400 (threshold >= 102400) → actionable."""
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._heartbeat_state(100, 1_000_000, 3.0))

        mock_wc = MagicMock()
        mock_wc.returncode = 0
        mock_wc.stdout = "100 /path"   # 0 line growth
        mock_du = MagicMock()
        mock_du.returncode = 0
        mock_du.stdout = str(1_000_000 + 102_400)  # exactly 102400 byte growth

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "bytes" in result["reason"]

    # ---- Step 3: elapsed time exactly at threshold (8.0h) ----

    def test_step3_time_exactly_8h_is_actionable(self, m, tmp_path):
        """Elapsed time == 8.0h (threshold >= 8h) → actionable.

        _iso(8.0) truncates to whole seconds, so by the time check_step3
        executes, the measured elapsed will be >= 8.0h.
        """
        state_file = tmp_path / "heartbeat-state.json"
        state_file.write_text(self._heartbeat_state(100, 1_000_000, 8.0))

        mock_wc = MagicMock()
        mock_wc.returncode = 0
        mock_wc.stdout = "100 /path"   # 0 line growth
        mock_du = MagicMock()
        mock_du.returncode = 0
        mock_du.stdout = "1000000"     # 0 byte growth

        def fake_run(cmd, **kwargs):
            return mock_wc if isinstance(cmd, list) and cmd[0] == "wc" else mock_du

        with patch.object(m, "HEARTBEAT_STATE_JSON", str(state_file)), \
             patch("subprocess.run", side_effect=fake_run):
            result = m.check_step3_introspection()
        assert result["actionable"] is True
        assert "h since last introspection" in result["reason"]

    # ---- Step 4: cooldown exactly at threshold (4.0h) ----

    def test_step4_cooldown_exactly_4h_is_actionable(self, m, tmp_path):
        """Elapsed == 4.0h (threshold >= 4h) → actionable.

        _iso(4.0) truncates to whole seconds, so the measured elapsed is >= 4h.
        """
        state_file = tmp_path / "memory-maintenance.json"
        state_file.write_text(json.dumps({"last_run": _iso(4.0)}))
        with patch.object(m, "MEMORY_MAINTENANCE_JSON", str(state_file)):
            result = m.check_step4_memory_maintenance()
        assert result["actionable"] is True

    # ---- Step 10: staleness exactly at threshold (7 days) ----

    def test_step10_staleness_exactly_7_days_is_actionable(self, m, tmp_path):
        """Elapsed == 7 days (threshold >= 7d) → actionable.

        _iso(7 * 24.0) truncates to whole seconds, so measured elapsed >= 7d.
        """
        marker = tmp_path / ".last-fs-audit"
        marker.write_text(_iso(7 * 24.0))  # exactly 7 days ago
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step10_filesystem_hygiene()
        assert result["actionable"] is True
