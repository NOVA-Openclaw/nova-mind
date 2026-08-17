#!/usr/bin/env python3
"""
Unit tests for nova-mind#611 changes.

Covers:
  - Context-window helper config/truncation/formatting
  - extract_memories.py context prompt assembly
  - extract_memories.py environment field extraction/storage
  - extract_memories.py confidence-honesty safety net

No DB required for most tests — DB helpers are mocked.
"""

import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "memory" / "scripts"))

# Prevent the production env loaders from touching real environment / files.
sys.modules["env_loader"] = mock.MagicMock()
sys.modules["pg_env"] = mock.MagicMock()

# Mock psycopg2 before importing extract_memories so the module can load
# without a real DB driver.
sys.modules["psycopg2"] = mock.MagicMock()
sys.modules["psycopg2.extras"] = mock.MagicMock()

import context_window_helper as cwh  # noqa: E402
import extract_memories as em  # noqa: E402


class TestContextWindowConfig(unittest.TestCase):
    """Tests for context_window_helper config resolution (#611, Group A/B)."""

    def test_default_max_prior_messages(self):
        """A1/B5: missing config falls back to default 10."""
        self.assertEqual(cwh.resolve_max_prior_messages({}), cwh.DEFAULT_MAX_PRIOR_MESSAGES)
        self.assertEqual(cwh.resolve_max_prior_messages({"max_prior_messages": 10}), 10)

    def test_valid_override_max_prior_messages(self):
        """A4/B5: config override is honored."""
        self.assertEqual(cwh.resolve_max_prior_messages({"max_prior_messages": 3}), 3)

    def test_zero_max_prior_messages(self):
        """A5: N=0 is a valid boundary value."""
        self.assertEqual(cwh.resolve_max_prior_messages({"max_prior_messages": 0}), 0)

    def test_negative_max_prior_messages_falls_back(self):
        """A6: negative value falls back to default 10."""
        self.assertEqual(cwh.resolve_max_prior_messages({"max_prior_messages": -1}), 10)

    def test_non_numeric_max_prior_messages_falls_back(self):
        """A6: non-numeric value falls back to default 10."""
        self.assertEqual(cwh.resolve_max_prior_messages({"max_prior_messages": "ten"}), 10)
        self.assertEqual(cwh.resolve_max_prior_messages({"max_prior_messages": None}), 10)

    def test_context_window_enabled_defaults_true(self):
        """A8: missing/invalid values default to enabled."""
        self.assertTrue(cwh.is_context_window_enabled({}))
        self.assertTrue(cwh.is_context_window_enabled({"context_window_enabled": True}))

    def test_context_window_disabled(self):
        """A8: explicit false disables the window."""
        self.assertFalse(cwh.is_context_window_enabled({"context_window_enabled": False}))
        self.assertFalse(cwh.is_context_window_enabled({"context_window_enabled": "false"}))
        self.assertFalse(cwh.is_context_window_enabled({"context_window_enabled": "0"}))


class TestContextTruncation(unittest.TestCase):
    """Tests for context message truncation (#611, Group F)."""

    def _make_msgs(self, count: int, content_len: int = 10) -> list:
        return [
            {"role": "user", "content": f"msg{i:02d}" + "x" * content_len}
            for i in range(count)
        ]

    def test_slice_to_last_n(self):
        """C11: most recent N messages, chronological order preserved."""
        msgs = self._make_msgs(15)
        result = cwh.truncate_context_messages(msgs, max_prior_messages=10)
        self.assertEqual(len(result), 10)
        # The oldest in the window should be msg05 (index 5).
        self.assertIn("msg05", result[0]["content"])
        self.assertIn("msg14", result[-1]["content"])

    def test_zero_max_returns_empty(self):
        """A5: N=0 produces empty context window."""
        msgs = self._make_msgs(5)
        result = cwh.truncate_context_messages(msgs, max_prior_messages=0)
        self.assertEqual(result, [])

    def test_per_message_truncation(self):
        """F4: oversized single message is truncated."""
        big = "x" * 5000
        result = cwh.truncate_context_messages(
            [{"role": "user", "content": big}],
            max_prior_messages=10,
            max_per_message_chars=100,
        )
        self.assertEqual(len(result), 1)
        self.assertLessEqual(len(result[0]["content"]), 120)  # includes marker
        self.assertTrue(result[0]["content"].endswith(cwh.TRUNCATION_MARKER.strip()))

    def test_total_budget_drops_oldest(self):
        """F5: combined context size is bounded by dropping oldest first."""
        msgs = self._make_msgs(5, content_len=1000)
        result = cwh.truncate_context_messages(
            msgs,
            max_prior_messages=10,
            max_per_message_chars=2000,
            max_total_chars=3000,
        )
        total = sum(len(m["content"]) for m in result)
        self.assertLessEqual(total, 3000)
        # Oldest messages should have been dropped to fit the budget.
        self.assertLess(len(result), 5)


class TestPromptAssembly(unittest.TestCase):
    """Tests for build_extraction_prompt context handling (#611, Group A/C)."""

    def test_no_context_uses_simple_message_label(self):
        """A3: no context produces a simple MESSAGE label."""
        prompt = em.build_extraction_prompt(
            "hello world", "Zonkism", "", "discord", True, "public"
        )
        self.assertIn("MESSAGE:\nhello world", prompt)
        self.assertNotIn("PRIOR CONVERSATION CONTEXT", prompt)

    def test_context_block_present_and_separated(self):
        """A1/C7: context block is present and current message is clearly marked."""
        ctx = [
            {"role": "user", "content": "prior one", "timestamp": "t1", "sender_name": "Zonkism"},
            {"role": "assistant", "content": "prior two", "timestamp": "t2"},
        ]
        prompt = em.build_extraction_prompt(
            "current message",
            "Zonkism",
            "",
            "discord",
            True,
            "public",
            context_messages=ctx,
            current_role="user",
        )
        self.assertIn("PRIOR CONVERSATION CONTEXT", prompt)
        self.assertIn("[CURRENT USER MESSAGE - EXTRACT FROM THIS]", prompt)
        self.assertIn("prior one", prompt)
        self.assertIn("prior two", prompt)
        self.assertIn("current message", prompt)

    def test_extract_current_only_guardrail_in_prompt(self):
        """C7: prompt contains explicit extract-current-only instruction."""
        ctx = [{"role": "user", "content": "context"}]
        prompt = em.build_extraction_prompt(
            "current", "Zonkism", "", "discord", True, "public", context_messages=ctx
        )
        self.assertIn("EXTRACT FROM THIS", prompt)
        self.assertIn("DISAMBIGUATION CONTEXT ONLY", prompt)
        self.assertIn("NEVER extract", prompt)
        self.assertIn("CURRENT MESSAGE", prompt)

    def test_environment_field_in_template(self):
        """D1/D7: events template includes environment field."""
        prompt = em.build_extraction_prompt("event text", "Z", "", "discord", False, "public")
        self.assertIn('"environment"', prompt)
        self.assertIn("host/system identifier", prompt)

    def test_confidence_not_anchored_to_one(self):
        """E1/E6: template example confidence is not 1.0 and prompt warns against defaulting."""
        prompt = em.build_extraction_prompt("text", "Z", "", "discord", False, "public")
        self.assertIn('"confidence": 0.85', prompt)
        self.assertIn("confidence is NOT a constant", prompt)
        self.assertIn("Do NOT default every extraction to 1.0", prompt)


class TestConfidenceHonesty(unittest.TestCase):
    """Tests for apply_confidence_honesty (#611, Group E)."""

    def _make_fact(self, confidence: float) -> dict:
        return {"subject": "Z", "key": "k", "value": "v", "confidence": confidence}

    @mock.patch("extract_memories.get_initial_confidence")
    def test_short_no_context_capped(self, mock_get_conf):
        """E1/E4: short ambiguous message with no context gets capped below 1.0."""
        mock_get_conf.return_value = 0.5
        data = {"facts": [self._make_fact(1.0)]}
        em.apply_confidence_honesty(data, "short msg", [], 123, mock.MagicMock())
        self.assertEqual(data["facts"][0]["confidence"], 0.5)
        mock_get_conf.assert_called_once_with(123, source="inferred", conn=mock.ANY)

    @mock.patch("extract_memories.get_initial_confidence")
    def test_context_present_not_capped(self, mock_get_conf):
        """E2: context present lets LLM confidence stand."""
        data = {"facts": [self._make_fact(1.0)]}
        em.apply_confidence_honesty(
            data, "short msg", [{"role": "user", "content": "ctx"}], 123, mock.MagicMock()
        )
        self.assertEqual(data["facts"][0]["confidence"], 1.0)
        mock_get_conf.assert_not_called()

    @mock.patch("extract_memories.get_initial_confidence")
    def test_long_message_not_capped(self, mock_get_conf):
        """E3: clear/long message keeps high confidence."""
        data = {"facts": [self._make_fact(0.95)]}
        em.apply_confidence_honesty(
            data, "this is a much longer message with clear facts stated directly", [], 123, mock.MagicMock()
        )
        self.assertEqual(data["facts"][0]["confidence"], 0.95)
        mock_get_conf.assert_not_called()

    @mock.patch("extract_memories.get_initial_confidence")
    def test_only_caps_exact_one_point_zero(self, mock_get_conf):
        """E3: facts already below 1.0 are not further reduced."""
        data = {"facts": [self._make_fact(0.7)]}
        em.apply_confidence_honesty(data, "short", [], 123, mock.MagicMock())
        self.assertEqual(data["facts"][0]["confidence"], 0.7)
        mock_get_conf.assert_not_called()


class TestEnvironmentStorage(unittest.TestCase):
    """Tests for events.environment storage (#611, Group D)."""

    @mock.patch("extract_memories.resolve_source_entity_id", return_value=None)
    @mock.patch("extract_memories.ensure_entity")
    def test_event_environment_flows_to_insert(self, mock_ensure, mock_resolve):
        """D4: environment value flows through to the events INSERT."""
        conn = mock.MagicMock()
        cur = conn.cursor.return_value.__enter__.return_value
        cur.fetchone.return_value = None  # no duplicate

        data = {
            "events": [
                {
                    "description": "Deployed fix to nova-local",
                    "date": "2026-08-17",
                    "environment": "nova-local",
                }
            ]
        }
        em.store_extracted(
            data=data,
            sender_name="Z",
            sender_id="",
            sender_provider="discord",
            src_timestamp="2026-08-17T00:00:00Z",
            src_channel_transcript_id="",
            src_channel_session_id="",
            conn=conn,
        )

        # Find the INSERT call for events.
        calls = [c for c in cur.execute.call_args_list if "INSERT INTO events" in str(c.args[0])]
        self.assertEqual(len(calls), 1)
        sql = calls[0].args[0]
        params = calls[0].args[1]
        self.assertIn("environment", sql)
        self.assertIn("nova-local", params)

    @mock.patch("extract_memories.resolve_source_entity_id", return_value=None)
    @mock.patch("extract_memories.ensure_entity")
    def test_null_environment_omitted_from_insert(self, mock_ensure, mock_resolve):
        """D3: null/absent environment is not included in INSERT."""
        conn = mock.MagicMock()
        cur = conn.cursor.return_value.__enter__.return_value
        cur.fetchone.return_value = None

        data = {"events": [{"description": "Had dinner", "date": "2026-08-17"}]}
        em.store_extracted(
            data=data,
            sender_name="Z",
            sender_id="",
            sender_provider="discord",
            src_timestamp="2026-08-17T00:00:00Z",
            src_channel_transcript_id="",
            src_channel_session_id="",
            conn=conn,
        )

        calls = [c for c in cur.execute.call_args_list if "INSERT INTO events" in str(c.args[0])]
        self.assertEqual(len(calls), 1)
        params = calls[0].args[1]
        self.assertNotIn("NULL environment", [p for p in params if p is not None])

    @mock.patch("extract_memories.resolve_source_entity_id", return_value=None)
    @mock.patch("extract_memories.ensure_entity")
    def test_environment_truncated_to_255(self, mock_ensure, mock_resolve):
        """D8: environment value longer than 255 chars is truncated before INSERT."""
        conn = mock.MagicMock()
        cur = conn.cursor.return_value.__enter__.return_value
        cur.fetchone.return_value = None

        long_env = "x" * 300
        data = {
            "events": [
                {
                    "description": "Event",
                    "environment": long_env,
                }
            ]
        }
        em.store_extracted(
            data=data,
            sender_name="Z",
            sender_id="",
            sender_provider="discord",
            src_timestamp="",
            src_channel_transcript_id="",
            src_channel_session_id="",
            conn=conn,
        )

        calls = [c for c in cur.execute.call_args_list if "INSERT INTO events" in str(c.args[0])]
        params = calls[0].args[1]
        env_param = next((p for p in params if isinstance(p, str) and p.startswith("x")), "")
        self.assertEqual(len(env_param), 255)


class TestParseContextJson(unittest.TestCase):
    """Tests for EXTRACTION_CONTEXT_JSON parsing (#611, Group A/F)."""

    def test_valid_context_json(self):
        """Valid context JSON normalizes to message list."""
        raw = json.dumps([
            {"role": "user", "content": "hello", "timestamp": "t1"},
            {"role": "assistant", "content": "hi there", "sender_name": "NOVA"},
        ])
        result = cwh.parse_context_json(raw)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["content"], "hello")
        self.assertEqual(result[1]["role"], "assistant")

    def test_invalid_context_json_degrades(self):
        """F2: malformed context JSON degrades gracefully to empty list."""
        with mock.patch("sys.stderr", new_callable=io.StringIO):
            result = cwh.parse_context_json("not json")
        self.assertEqual(result, [])


if __name__ == "__main__":
    unittest.main()
