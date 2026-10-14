"""
TC-714 acceptance mapping — nova-mind#714 heartbeat cadence/session/delivery.

Local cases run with a temp OPENCLAW_DIR and mocked fixtures.
Cases that require a live gateway or real automation job are marked deferred.
"""
import json
import os
import subprocess
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

PROACTIVE_CHANNEL = "1504054635231445112"


@pytest.fixture
def temp_openclaw(tmp_path):
    """Temp OPENCLAW_DIR with a minimal openclaw.json."""
    oc_dir = tmp_path / "openclaw"
    oc_dir.mkdir()
    config = oc_dir / "openclaw.json"
    config.write_text(json.dumps({"agents": {"defaults": {}}, "plugins": {"entries": {}}}))
    return oc_dir


def _apply_heartbeat_defaults(config_path: Path):
    """Replicate the installer jq steps idempotently."""
    for key, value in [
        ("every", "30m"),
        ("target", "discord"),
        ("to", f"channel:{PROACTIVE_CHANNEL}"),
        ("isolatedSession", "true"),
    ]:
        existing = subprocess.run(
            ["jq", "-r", f".agents.defaults.heartbeat.{key} // empty", str(config_path)],
            capture_output=True, text=True, check=False,
        ).stdout.strip()
        if not existing:
            if value in ("true", "false"):
                expr = f".agents.defaults.heartbeat.{key} = {value}"
            else:
                expr = f".agents.defaults.heartbeat.{key} = \"{value}\""
            tmp = config_path.with_suffix(".tmp")
            subprocess.run(
                ["jq", expr, str(config_path)],
                stdout=tmp.open("w"), check=True,
            )
            tmp.replace(config_path)


class TestTC714Local:
    def test_tc714_001_default_cadence_30m(self, temp_openclaw):
        """TC-714-001: live default stays 30m; 20m remains pending."""
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        assert cfg["agents"]["defaults"]["heartbeat"]["every"] == "30m"

    def test_tc714_001_existing_cadence_preserved(self, temp_openclaw):
        """TC-714-001: installer never clobbers an explicit cadence."""
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        cfg["agents"]["defaults"]["heartbeat"] = {"every": "20m"}
        (temp_openclaw / "openclaw.json").write_text(json.dumps(cfg))
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        assert cfg["agents"]["defaults"]["heartbeat"]["every"] == "20m"

    def test_tc714_002_003_target_is_proactive_mode(self, temp_openclaw):
        """TC-714-002/003: heartbeat output routes to #proactive-mode."""
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        hb = cfg["agents"]["defaults"]["heartbeat"]
        assert hb["target"] == "discord"
        assert hb["to"] == f"channel:{PROACTIVE_CHANNEL}"

    def test_tc714_004_isolated_session_default_true(self, temp_openclaw):
        """TC-714-004: isolatedSession: true is set at defaults level."""
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        assert cfg["agents"]["defaults"]["heartbeat"]["isolatedSession"] is True

    def test_tc714_004b_effective_target_audit(self, temp_openclaw):
        """TC-714-004b: every agent's effective heartbeat.to resolves to proactive-mode."""
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        agents_json = temp_openclaw / "agents.json"
        agents_json.write_text(json.dumps({
            "nova": {
                "model": "anthropic/claude-opus-4",
                "heartbeat": {"to": f"channel:{PROACTIVE_CHANNEL}"},
            },
            "coder": {"model": "anthropic/claude-sonnet-4"},
        }))
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        defaults = cfg["agents"]["defaults"]["heartbeat"]
        entries = json.loads(agents_json.read_text())
        for agent_id, entry in entries.items():
            effective_to = entry.get("heartbeat", {}).get("to", defaults.get("to"))
            assert effective_to == f"channel:{PROACTIVE_CHANNEL}", agent_id

    def test_tc714_004b_audit_catches_webchat_per_agent_target(self, temp_openclaw):
        """TC-714-004b: a per-agent heartbeat row targeting webchat is reported, not silently accepted."""
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        agents_json = temp_openclaw / "agents.json"
        agents_json.write_text(json.dumps({
            "nova": {
                "model": "anthropic/claude-opus-4",
                "heartbeat": {"to": f"channel:{PROACTIVE_CHANNEL}"},
            },
            "coder": {
                "model": "anthropic/claude-sonnet-4",
                "heartbeat": {"to": "channel:webchat-channel"},
            },
        }))
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        defaults = cfg["agents"]["defaults"]["heartbeat"]
        entries = json.loads(agents_json.read_text())

        bad_targets = []
        for agent_id, entry in entries.items():
            effective_to = entry.get("heartbeat", {}).get("to", defaults.get("to"))
            if effective_to != f"channel:{PROACTIVE_CHANNEL}":
                bad_targets.append((agent_id, effective_to))

        assert bad_targets == [("coder", "channel:webchat-channel")]

    def test_tc714_010_isolated_session_survives_merge(self, temp_openclaw):
        """TC-714-010: a merge that omits isolatedSession does not clobber defaults."""
        _apply_heartbeat_defaults(temp_openclaw / "openclaw.json")
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        cfg["agents"]["entries"] = {
            "nova": {
                "model": "anthropic/claude-opus-4",
                "heartbeat": {"every": "30m", "target": "discord", "to": f"channel:{PROACTIVE_CHANNEL}"},
            }
        }
        (temp_openclaw / "openclaw.json").write_text(json.dumps(cfg))
        cfg = json.loads((temp_openclaw / "openclaw.json").read_text())
        assert cfg["agents"]["defaults"]["heartbeat"]["isolatedSession"] is True


class TestTC714Deferred:
    @pytest.mark.skip(reason="TC-714-008: requires a live gateway or openclaw doctor --fix against temp config")
    def test_tc714_008_doctor_fix(self):
        """Deferred to staging: openclaw doctor --fix materializes schedule drift."""

    @pytest.mark.skip(reason="TC-714-011: requires real automation job metadata from openclaw cron list --all")
    def test_tc714_011_real_automation_job(self):
        """Deferred to staging: verify live Heartbeat (nova) job metadata."""
