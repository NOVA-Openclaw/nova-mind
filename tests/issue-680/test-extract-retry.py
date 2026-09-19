#!/usr/bin/env python3
"""Unit tests for issue #680 — real-time memory extraction retry loop.

These tests exercise memory/scripts/extract_memories.py directly. They mock
requests.post and psycopg2 so no real network calls or DB connections are made.
"""

import json
import os
import sys
import time
import unittest
from io import StringIO
from unittest.mock import MagicMock, patch

import requests

# Ensure the script under test can be imported.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT_DIR = os.path.join(REPO_ROOT, "memory", "scripts")
sys.path.insert(0, SCRIPT_DIR)

# Patch env before importing extract_memories so bootstrap loads cleanly.
os.environ.setdefault("OPENROUTER_API_KEY", "test-key")
os.environ.setdefault("PGDATABASE", "nova_memory")
os.environ.setdefault("PGHOST", "localhost")
os.environ.setdefault("PGUSER", "tester")

import extract_memories as em  # noqa: E402


class FakeResponse:
    def __init__(self, status_code, json_data=None, text="", raise_json=None):
        self.status_code = status_code
        self._json = json_data
        self.text = text
        self._raise_json = raise_json

    def json(self):
        if self._raise_json:
            raise self._raise_json
        return self._json


def _make_llm_json(content: str):
    return {"choices": [{"message": {"content": content}}]}


class TestCallLLMRetry(unittest.TestCase):
    def setUp(self):
        # Enable retry for every test in this class.
        self.env_patch = patch.dict(os.environ, {"EXTRACTION_ENABLE_RETRY": "1"})
        self.env_patch.start()
        # Force module to re-read env flag for each test.
        em.EXTRACTION_ENABLE_RETRY = os.environ.get("EXTRACTION_ENABLE_RETRY", "") in (
            "1",
            "true",
            "yes",
        )

    def tearDown(self):
        self.env_patch.stop()

    def _patch_post(self, side_effects):
        """Return a patch for requests.post with the given side_effect sequence."""
        return patch("extract_memories.requests.post", side_effect=side_effects)

    @patch("extract_memories.requests.post")
    def test_tc01_happy_path_single_attempt(self, mock_post):
        """TC-01: success on first attempt, no retry, no backoff."""
        mock_post.return_value = FakeResponse(
            200, json_data=_make_llm_json('{"facts": []}')
        )
        start = time.monotonic()
        result = em.call_llm("prompt", "key", "model")
        elapsed = time.monotonic() - start

        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 1)
        self.assertLess(elapsed, 0.5)

    @patch("extract_memories.requests.post")
    def test_tc02_timeout_then_success_attempt2(self, mock_post):
        """TC-02: timeout on attempt 1, success on attempt 2."""
        mock_post.side_effect = [
            requests.exceptions.Timeout("connection timed out"),
            FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
        ]
        start = time.monotonic()
        result = em.call_llm("prompt", "key", "model")
        elapsed = time.monotonic() - start

        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 2)
        # Backoff after attempt 1 is ~1s.
        self.assertGreaterEqual(elapsed, 0.9)
        self.assertLess(elapsed, 2.5)

    @patch("extract_memories.requests.post")
    def test_tc03_timeout_twice_then_success_attempt3(self, mock_post):
        """TC-03: timeout on attempts 1 and 2, success on attempt 3."""
        mock_post.side_effect = [
            requests.exceptions.Timeout("connection timed out"),
            requests.exceptions.Timeout("connection timed out"),
            FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
        ]
        start = time.monotonic()
        result = em.call_llm("prompt", "key", "model")
        elapsed = time.monotonic() - start

        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 3)
        # Backoff total: 1s + 2s = ~3s.
        self.assertGreaterEqual(elapsed, 2.8)
        self.assertLess(elapsed, 4.5)

    @patch("extract_memories.requests.post")
    def test_tc04_all_three_timeouts_exhausted(self, mock_post):
        """TC-04: all 3 attempts timeout -> distinct exit code 3."""
        mock_post.side_effect = [
            requests.exceptions.Timeout("connection timed out"),
            requests.exceptions.Timeout("connection timed out"),
            requests.exceptions.Timeout("connection timed out"),
        ]

        with self.assertRaises(em.LLMTransientRetriesExhausted):
            em.call_llm("prompt", "key", "model")
        self.assertEqual(mock_post.call_count, 3)

    @patch("extract_memories.requests.post")
    def test_tc05_json_parse_failure_no_retry(self, mock_post):
        """TC-05: JSON parse failure is not retried."""
        mock_post.return_value = FakeResponse(
            200,
            json_data=_make_llm_json("not valid json"),
        )
        with self.assertRaises(em.JsonParseFailure):
            em.call_llm("prompt", "key", "model")
        self.assertEqual(mock_post.call_count, 1)

    @patch("extract_memories.requests.post")
    def test_tc07_http_401_no_retry(self, mock_post):
        """TC-07: HTTP 4xx (except 429) is not retried."""
        mock_post.return_value = FakeResponse(401, text="Unauthorized")
        with self.assertRaises(RuntimeError) as ctx:
            em.call_llm("prompt", "key", "model")
        self.assertIn("401", str(ctx.exception))
        self.assertEqual(mock_post.call_count, 1)

    @patch("extract_memories.requests.post")
    def test_tc07b_http_400_no_retry(self, mock_post):
        """TC-07b: HTTP 400 is not retried."""
        mock_post.return_value = FakeResponse(400, text="Bad Request")
        with self.assertRaises(RuntimeError) as ctx:
            em.call_llm("prompt", "key", "model")
        self.assertIn("400", str(ctx.exception))
        self.assertEqual(mock_post.call_count, 1)

    @patch("extract_memories.requests.post")
    def test_tc08_connection_error_retried(self, mock_post):
        """TC-08: ConnectionError is retried until success."""
        mock_post.side_effect = [
            requests.exceptions.ConnectionError("connection refused"),
            FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
        ]
        result = em.call_llm("prompt", "key", "model")
        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 2)

    @patch("extract_memories.requests.post")
    def test_tc09_http_429_retried(self, mock_post):
        """TC-09: HTTP 429 is retried."""
        mock_post.side_effect = [
            FakeResponse(429, text="Rate limited"),
            FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
        ]
        result = em.call_llm("prompt", "key", "model")
        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 2)

    @patch("extract_memories.requests.post")
    def test_tc09b_http_503_retried(self, mock_post):
        """TC-09b: HTTP 503 is retried."""
        mock_post.side_effect = [
            FakeResponse(503, text="Service Unavailable"),
            FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
        ]
        result = em.call_llm("prompt", "key", "model")
        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 2)

    @patch("extract_memories.requests.post")
    def test_http_500_retried(self, mock_post):
        mock_post.side_effect = [
            FakeResponse(500, text="Internal Server Error"),
            FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
        ]
        result = em.call_llm("prompt", "key", "model")
        self.assertEqual(result, {"facts": []})
        self.assertEqual(mock_post.call_count, 2)


class TestRetryFlagGating(unittest.TestCase):
    @patch("extract_memories.requests.post")
    def test_replay_path_single_shot_when_flag_off(self, mock_post):
        """When EXTRACTION_ENABLE_RETRY is unset, retries are disabled."""
        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("EXTRACTION_ENABLE_RETRY", None)
            em.EXTRACTION_ENABLE_RETRY = False
            mock_post.side_effect = [
                requests.exceptions.Timeout("timeout"),
                FakeResponse(200, json_data=_make_llm_json('{"facts": []}')),
            ]
            with self.assertRaises(RuntimeError):
                em.call_llm("prompt", "key", "model")
            self.assertEqual(mock_post.call_count, 1)


class TestMainExitCodes(unittest.TestCase):
    @patch("extract_memories.requests.post")
    @patch("extract_memories.get_db_connection")
    @patch("sys.stdin", StringIO("this is a test message with enough length"))
    def test_main_returns_3_on_retry_exhaustion(self, mock_conn, mock_post):
        """TC-04 integration: main() exits 3 and writes no partial JSON."""
        with patch.dict(os.environ, {"EXTRACTION_ENABLE_RETRY": "1"}):
            em.EXTRACTION_ENABLE_RETRY = True
            mock_post.side_effect = [
                requests.exceptions.Timeout("timeout"),
                requests.exceptions.Timeout("timeout"),
                requests.exceptions.Timeout("timeout"),
            ]
            mock_conn.return_value = MagicMock()

            stdout_capture = StringIO()
            stderr_capture = StringIO()
            with patch("sys.stdout", stdout_capture), patch(
                "sys.stderr", stderr_capture
            ):
                code = em.main()

            self.assertEqual(code, 3)
            stdout_text = stdout_capture.getvalue()
            # Must not emit partial/invalid JSON on stdout.
            self.assertEqual(stdout_text.strip(), "")
            stderr_text = stderr_capture.getvalue()
            self.assertIn("retries exhausted", stderr_text)
            self.assertNotIn("Traceback", stderr_text)

    @patch("extract_memories.requests.post")
    @patch("extract_memories.get_db_connection")
    @patch("sys.stdin", StringIO("this is a test message with enough length"))
    def test_main_returns_2_on_json_parse_failure(self, mock_conn, mock_post):
        """TC-05 integration: main() exits 2 on JSON parse failure."""
        with patch.dict(os.environ, {"EXTRACTION_ENABLE_RETRY": "1"}):
            em.EXTRACTION_ENABLE_RETRY = True
            mock_post.return_value = FakeResponse(
                200, json_data=_make_llm_json("not valid json")
            )
            mock_conn.return_value = MagicMock()

            stdout_capture = StringIO()
            stderr_capture = StringIO()
            with patch("sys.stdout", stdout_capture), patch(
                "sys.stderr", stderr_capture
            ):
                code = em.main()

            self.assertEqual(code, 2)
            self.assertEqual(mock_post.call_count, 1)

    @patch("extract_memories.requests.post")
    @patch("extract_memories.get_db_connection")
    @patch("sys.stdin", StringIO("this is a test message with enough length"))
    def test_main_returns_1_on_missing_api_key(self, mock_conn, mock_post):
        """TC-06: missing OPENROUTER_API_KEY exits 1 before any HTTP call."""
        with patch.dict(os.environ, {"EXTRACTION_ENABLE_RETRY": "1"}, clear=True):
            em.EXTRACTION_ENABLE_RETRY = True
            mock_conn.return_value = MagicMock()
            # Ensure OPENROUTER_API_KEY is absent.
            os.environ.pop("OPENROUTER_API_KEY", None)

            stdout_capture = StringIO()
            stderr_capture = StringIO()
            with patch("sys.stdout", stdout_capture), patch(
                "sys.stderr", stderr_capture
            ):
                code = em.main()

            self.assertEqual(code, 1)
            self.assertEqual(mock_post.call_count, 0)
            self.assertIn("OPENROUTER_API_KEY not set", stderr_capture.getvalue())


class TestBudgetArithmetic(unittest.TestCase):
    def test_default_timeout_values_fit_outer_budget(self):
        """Verify the documented budget arithmetic still holds."""
        per_attempt = em.LLM_TIMEOUT_SECONDS
        attempts = em.MAX_LLM_ATTEMPTS
        backoff_total = sum(em.RETRY_BACKOFF_SECONDS)
        safety_margin = 12
        # Matches handler.ts DEFAULT_EXTRACTION_TIMEOUT_MS / 1000.
        outer_budget_seconds = 95
        total_budget = per_attempt * attempts + backoff_total + safety_margin
        self.assertLess(total_budget, outer_budget_seconds)
        self.assertEqual(per_attempt, 25)
        self.assertEqual(attempts, 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
