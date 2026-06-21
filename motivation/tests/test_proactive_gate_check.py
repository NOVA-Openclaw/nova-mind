"""
Tests for motivation/scripts/proactive-gate-check.py

Covers:
- Idle detection (active, idle, boundary, missing file, malformed, bot-only, custom threshold)
- All 10 gate check steps (actionable / not-actionable paths)
- D100 logic (mandatory vs optional)
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
    def _make_openclaw_output(self, sessions: list[dict]) -> str:
        return json.dumps({"sessions": sessions})

    def test_recent_user_sessions_found(self, m):
        payload = self._make_openclaw_output([
            {"key": "agent:nova:discord:channel:123", "ageMs": 1000},
            {"key": "agent:nova:discord:channel:456", "ageMs": 2000},
        ])
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = payload

        with patch("subprocess.run", return_value=mock_result):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is True
        assert result["data"]["count"] == 2

    def test_no_recent_user_sessions(self, m):
        payload = self._make_openclaw_output([
            {"key": "agent:nova:discord:channel:123", "ageMs": 90_000_000},
        ])
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = payload

        with patch("subprocess.run", return_value=mock_result):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False

    def test_excludes_bot_sessions(self, m):
        payload = self._make_openclaw_output([
            {"key": "agent:nova:discord:channel:123", "ageMs": 1000},
            {"key": "agent:nova:main:heartbeat", "ageMs": 500},
            {"key": "agent:nova:cron:abc", "ageMs": 300},
        ])
        mock_result = MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = payload

        with patch("subprocess.run", return_value=mock_result):
            result = m.check_step2_unanswered_sessions()
        # Only the discord channel should count
        assert result["data"]["count"] == 1

    def test_openclaw_cli_not_found(self, m):
        import subprocess as sp
        with patch("subprocess.run", side_effect=FileNotFoundError):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False
        assert "error" in result

    def test_openclaw_cli_failure(self, m):
        mock_result = MagicMock()
        mock_result.returncode = 1
        mock_result.stderr = "something went wrong"

        with patch("subprocess.run", return_value=mock_result):
            result = m.check_step2_unanswered_sessions()
        assert result["actionable"] is False
        assert "error" in result


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
        fixed_ts = "2026-06-21T10:00:00Z"
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

class TestStep8UnsolvedProblems:
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
            result = m.check_step8_unsolved_problems()
        assert result["actionable"] is False

    def test_unsolved_problems_present(self, m):
        with patch.object(m, "_db_connect", return_value=self._mock_conn(3)):
            result = m.check_step8_unsolved_problems()
        assert result["actionable"] is True
        assert result["data"]["count"] == 3

    def test_db_failure(self, m):
        with patch.object(m, "_db_connect", side_effect=Exception("db error")):
            result = m.check_step8_unsolved_problems()
        assert result["actionable"] is False
        assert "error" in result


# ---------------------------------------------------------------------------
# Step 9 — filesystem hygiene
# ---------------------------------------------------------------------------

class TestStep9FilesystemHygiene:
    def test_recently_audited_not_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text(_iso(24.0))  # 1 day ago, threshold 7 days
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step9_filesystem_hygiene()
        assert result["actionable"] is False

    def test_stale_audit_is_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text(_iso(8 * 24.0))  # 8 days ago, threshold 7 days
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step9_filesystem_hygiene()
        assert result["actionable"] is True

    def test_missing_marker_is_actionable(self, m, tmp_path):
        missing = str(tmp_path / "no-such-file")
        with patch.object(m, "FS_AUDIT_MARKER", missing):
            result = m.check_step9_filesystem_hygiene()
        assert result["actionable"] is True

    def test_empty_marker_is_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text("")
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step9_filesystem_hygiene()
        assert result["actionable"] is True

    def test_malformed_timestamp_is_actionable(self, m, tmp_path):
        marker = tmp_path / ".last-fs-audit"
        marker.write_text("not-a-timestamp")
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step9_filesystem_hygiene()
        assert result["actionable"] is True


# ---------------------------------------------------------------------------
# Step 10 — D100
# ---------------------------------------------------------------------------

class TestStep10D100:
    def test_mandatory_when_no_prior_work(self, m):
        result = m.check_step10_d100(prior_actionable_count=0)
        assert result["actionable"] is True
        assert "mandatory" in result["reason"].lower()

    def test_optional_when_prior_work_exists(self, m):
        result = m.check_step10_d100(prior_actionable_count=3)
        assert result["actionable"] is False
        assert "optional" in result["reason"].lower()

    def test_boundary_one_prior_step(self, m):
        result = m.check_step10_d100(prior_actionable_count=1)
        assert result["actionable"] is False


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
             patch.object(m, "check_step8_unsolved_problems", return_value=not_actionable), \
             patch.object(m, "check_step9_filesystem_hygiene", return_value=not_actionable), \
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
            "5_entities", "6_tasks", "7_github", "8_research",
            "9_filesystem", "10_d100",
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
        # All steps 1-9 mocked as not-actionable, so D100 must be mandatory
        assert 10 in output["actionable_steps"]
        assert output["steps"]["10_d100"]["actionable"] is True

    def test_timestamp_is_valid_iso(self, m):
        output = self._run_main(m, idle=True)
        ts = output["timestamp"]
        # Should parse without error
        datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")

    def test_summary_string_format(self, m):
        output = self._run_main(m, idle=True)
        assert "of 10 steps actionable" in output["summary"]

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

    # ---- Step 9: staleness exactly at threshold (7 days) ----

    def test_step9_staleness_exactly_7_days_is_actionable(self, m, tmp_path):
        """Elapsed == 7 days (threshold >= 7d) → actionable.

        _iso(7 * 24.0) truncates to whole seconds, so measured elapsed >= 7d.
        """
        marker = tmp_path / ".last-fs-audit"
        marker.write_text(_iso(7 * 24.0))  # exactly 7 days ago
        with patch.object(m, "FS_AUDIT_MARKER", str(marker)):
            result = m.check_step9_filesystem_hygiene()
        assert result["actionable"] is True
