#!/usr/bin/env python3
"""
Unit tests for nova-mind#497 changes in extract_memories.py.

Covers:
  - call_llm JSON repair pass (C1-C8)
  - fact value coercion (E1-E7)

No DB required — requests.post and DB helpers are mocked.
"""

import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

# Allow importing extract_memories.py from the production scripts directory.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "memory" / "scripts"))

# Prevent the production env loaders from touching real environment / files.
sys.modules["env_loader"] = mock.MagicMock()
sys.modules["pg_env"] = mock.MagicMock()

import extract_memories as em  # noqa: E402


class FakeResponse:
    def __init__(self, content: str, status_code: int = 200):
        self._content = content
        self.status_code = status_code

    def json(self):
        return {"choices": [{"message": {"content": self._content}}]}

    @property
    def text(self):
        return self._content


class TestCallLlMRepair(unittest.TestCase):
    """Tests for the json_repair pass inside call_llm (spec section C)."""

    def _post_with_content(self, content: str) -> dict:
        with mock.patch("requests.post") as mock_post:
            mock_post.return_value = FakeResponse(content)
            return em.call_llm("prompt", "key", "model")

    def test_c1_valid_json_no_repair(self):
        """C1: valid JSON dict parses immediately; repair is not called."""
        with mock.patch("json_repair.repair_json") as mock_repair:
            result = self._post_with_content('{"facts": [{"key": "k", "value": "v"}]}')
            mock_repair.assert_not_called()
        self.assertEqual(result, {"facts": [{"key": "k", "value": "v"}]})

    def test_c2_malformed_json_repair_succeeds(self):
        """C2: truncated JSON is repaired to a valid dict."""
        result = self._post_with_content('{"facts": [{"key": "favorite_color", "value": "blue"')
        self.assertEqual(result, {"facts": [{"key": "favorite_color", "value": "blue"}]})

    def test_c3_malformed_json_repair_fails(self):
        """C3: unrepairable garbage raises JsonParseFailure mentioning repair failure."""
        with self.assertRaises(em.JsonParseFailure) as ctx:
            self._post_with_content("not json at all")
        msg = str(ctx.exception)
        self.assertIn("Failed to parse LLM response as JSON", msg)
        self.assertIn("repair failed", msg)

    def test_c4_repair_produces_bare_list_of_facts(self):
        """C4a: repaired bare list of fact dicts wraps to {'facts': [...]}."""
        result = self._post_with_content('[{"key":"a","value":"b"}]')
        self.assertEqual(result, {"facts": [{"key": "a", "value": "b"}]})

    def test_c4_repair_produces_key_only_list(self):
        """C4b: list element with only a key still wraps."""
        result = self._post_with_content('[{"key":"a"}]')
        self.assertEqual(result, {"facts": [{"key": "a"}]})

    def test_c4_repair_produces_bare_scalar_list_fails(self):
        """C4c: bare scalar list raises JsonParseFailure instead of silently becoming {}."""
        with self.assertRaises(em.JsonParseFailure):
            self._post_with_content("[1,2,3]")

    def test_c4_repair_produces_empty_list_is_noop(self):
        """C4d: empty array is semantically empty extraction -> {}."""
        result = self._post_with_content("[]")
        self.assertEqual(result, {})

    def test_c5_valid_bare_array_no_repair_needed(self):
        """C5: directly valid JSON bare array is wrapped the same way."""
        with mock.patch("json_repair.repair_json") as mock_repair:
            result = self._post_with_content('[{"key":"x","value":"y"}]')
            mock_repair.assert_not_called()
        self.assertEqual(result, {"facts": [{"key": "x", "value": "y"}]})

    def test_c6_repair_attempted_exactly_once(self):
        """C6: repair is called exactly once even if the result is still bad."""
        with mock.patch("json_repair.repair_json") as mock_repair:
            mock_repair.return_value = "{still not valid"
            with self.assertRaises(RuntimeError):
                self._post_with_content("{not valid")
            self.assertEqual(mock_repair.call_count, 1)

    def test_c7_empty_response_short_circuits(self):
        """C7: empty response returns {} before repair is ever considered."""
        with mock.patch("json_repair.repair_json") as mock_repair:
            result = self._post_with_content("")
            mock_repair.assert_not_called()
        self.assertEqual(result, {})

    def test_c8_fenced_malformed_json_repaired(self):
        """C8: markdown fences are stripped before repair runs."""
        result = self._post_with_content("```json\n{\"facts\": [{\"key\": \"a\", \"value\": \"b\"\n```")
        self.assertEqual(result, {"facts": [{"key": "a", "value": "b"}]})

    def test_c9_unexpected_top_level_type_fails(self):
        """C9: valid JSON whose top-level type is neither dict nor supported list raises JsonParseFailure."""
        with self.assertRaises(em.JsonParseFailure) as ctx:
            self._post_with_content('"just a string"')
        self.assertIn("unexpected type", str(ctx.exception))


class TestCoerceFactValue(unittest.TestCase):
    """Tests for value coercion at extract_memories.py:982 (spec section E)."""

    def test_e1_true_boolean(self):
        """E1: JSON true -> literal string 'true'."""
        self.assertEqual(em.coerce_fact_value(True, "night_owl"), "true")

    def test_e2_false_boolean(self):
        """E2: JSON false -> literal string 'false' (truthy, survives guard)."""
        self.assertEqual(em.coerce_fact_value(False, "flag"), "false")

    def test_e3_none_skipped_with_log(self):
        """E3: JSON null -> None (skip with logged notice)."""
        with mock.patch("sys.stderr", new_callable=io.StringIO) as stderr:
            self.assertIsNone(em.coerce_fact_value(None, "maybe_key"))
            self.assertIn("SKIP", stderr.getvalue())
            self.assertIn("maybe_key", stderr.getvalue())

    def test_e4_integer(self):
        """E4: int value -> string."""
        self.assertEqual(em.coerce_fact_value(42, "count"), "42")

    def test_e5_float(self):
        """E5: float value -> string."""
        self.assertEqual(em.coerce_fact_value(3.14, "pi"), "3.14")

    def test_e6_dict_and_list(self):
        """E6: dict/list values -> json.dumps()."""
        self.assertEqual(em.coerce_fact_value({"nested": "object"}), '{"nested": "object"}')
        self.assertEqual(em.coerce_fact_value(["a", "list"]), '["a", "list"]')

    def test_e7_string_unchanged(self):
        """E7: normal string is stripped, unchanged otherwise."""
        self.assertEqual(em.coerce_fact_value("  blue  "), "blue")


class TestExitCodeMapping(unittest.TestCase):
    """Tests for the new exit-code-2 path from main() (spec section D)."""

    def _run_main_with_call_llm_error(self, side_effect):
        """Helper: run main() with call_llm raising the supplied exception."""
        with mock.patch("extract_memories.call_llm") as mock_call_llm:
            with mock.patch("extract_memories.get_db_connection") as mock_conn:
                mock_call_llm.side_effect = side_effect
                with mock.patch(
                    "sys.stdin", io.StringIO("this is a long enough test message")
                ):
                    with mock.patch.dict(
                        os.environ,
                        {"OPENROUTER_API_KEY": "test-key"},
                        clear=False,
                    ):
                        return em.main()

    def test_json_parse_failure_repair_failed_returns_exit_2(self):
        """JsonParseFailure from repair-failed path -> exit 2."""
        code = self._run_main_with_call_llm_error(
            em.JsonParseFailure(
                "Failed to parse LLM response as JSON and repair failed: ..."
            )
        )
        self.assertEqual(code, 2)

    def test_json_parse_failure_bare_scalar_list_returns_exit_2(self):
        """JsonParseFailure from bare-scalar-list reject -> exit 2."""
        code = self._run_main_with_call_llm_error(
            em.JsonParseFailure(
                "LLM response parsed to a bare list that does not look like a fact array"
            )
        )
        self.assertEqual(code, 2)

    def test_json_parse_failure_unexpected_top_level_type_returns_exit_2(self):
        """JsonParseFailure from unexpected-top-level-type reject -> exit 2."""
        code = self._run_main_with_call_llm_error(
            em.JsonParseFailure(
                "LLM response parsed to an unexpected type (str), expected dict"
            )
        )
        self.assertEqual(code, 2)

    def test_non_json_runtime_error_returns_exit_1(self):
        """Non-JsonParseFailure RuntimeError remains exit 1."""
        code = self._run_main_with_call_llm_error(
            RuntimeError("LLM API call failed: HTTP 503")
        )
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
