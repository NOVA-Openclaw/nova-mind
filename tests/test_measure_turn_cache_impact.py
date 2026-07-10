"""
Tests for scripts/measure-turn-cache-impact.py.

Covers the chars-to-tokens conversion, AC-3 sanity-check behavior, and the
script's CLI smoke paths with matched/mismatched fixtures and missing logs.
"""

from __future__ import annotations

import importlib.util
import io
import sys
from pathlib import Path
from unittest import mock

import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "measure-turn-cache-impact.py"
spec = importlib.util.spec_from_file_location("measure_turn_cache_impact", SCRIPT_PATH)
measure = importlib.util.module_from_spec(spec)
# Required so dataclass annotations resolve against the module namespace.
sys.modules["measure_turn_cache_impact"] = measure
spec.loader.exec_module(measure)

FIXTURES = Path(__file__).parent / "fixtures" / "measure_turn_cache"


def make_metrics(cache_write_per_turn: float, cache_read: int = 0, cache_write: int = 0,
                 input_tokens: int = 0, total_turns: int = 2, steady_turns: int = 1) -> dict:
    """Build a minimal metrics dict for compare_metrics tests."""
    total_tokens = cache_read + cache_write + input_tokens
    return {
        "total_turns": total_turns,
        "steady_state_turns": steady_turns,
        "cache_hit_ratio": cache_read / total_tokens if total_tokens > 0 else 0.0,
        "total_cache_read": cache_read,
        "total_cache_write": cache_write,
        "total_input_tokens": input_tokens,
        "steady_state": {
            "cache_write_per_turn": cache_write_per_turn,
            "cache_read_per_turn": cache_read / steady_turns if steady_turns else 0.0,
            "input_tokens_per_turn": input_tokens / steady_turns if steady_turns else 0.0,
        },
    }


class TestEstimateTokensFromChars:
    def test_rounds_to_nearest_token(self):
        assert measure.estimate_tokens_from_chars(4000) == 1000
        assert measure.estimate_tokens_from_chars(3600) == 900
        assert measure.estimate_tokens_from_chars(100) == 25

    def test_zero_chars_is_zero_tokens(self):
        assert measure.estimate_tokens_from_chars(0) == 0

    def test_uses_configured_heuristic(self):
        # The heuristic is fixed at 4 chars/token; this test guards against
        # accidental changes to the constant used for AC-3.
        assert measure.CHARS_PER_TOKEN_ESTIMATE == 4


class TestCompareMetrics:
    def test_matched_prepend_size_passes_ac3(self):
        before = make_metrics(cache_write_per_turn=1000)
        after = make_metrics(cache_write_per_turn=100)
        result = measure.compare_metrics(before, after, prepend_block_size=3600)
        assert "AC-1 (cacheWrite drop >= 80%): PASS" in result
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): PASS" in result
        assert "prepend_block_size (est. tokens): 900" in result

    def test_mismatched_prepend_size_fails_ac3(self):
        before = make_metrics(cache_write_per_turn=1000)
        after = make_metrics(cache_write_per_turn=100)
        result = measure.compare_metrics(before, after, prepend_block_size=100)
        assert "AC-1 (cacheWrite drop >= 80%): PASS" in result
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): FAIL" in result
        assert "prepend_block_size (est. tokens): 25" in result

    def test_missing_log_degrades_gracefully(self):
        before = make_metrics(cache_write_per_turn=1000)
        after = make_metrics(cache_write_per_turn=100)
        result = measure.compare_metrics(before, after, prepend_block_size=None)
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): FAIL" in result

    def test_zero_prepend_size_fails_ac3(self):
        before = make_metrics(cache_write_per_turn=1000)
        after = make_metrics(cache_write_per_turn=100)
        result = measure.compare_metrics(before, after, prepend_block_size=0)
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): FAIL" in result


class TestCliSmokeTests:
    def test_matched_fixture_passes_ac3(self, tmp_path, monkeypatch):
        with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
            rc = measure.main([
                "--before", str(FIXTURES / "baseline.jsonl"),
                "--after", str(FIXTURES / "experiment.jsonl"),
                "--turn-context-log", str(FIXTURES / "turn-context-matched.log"),
            ])
        assert rc == 0
        output = stdout.getvalue()
        assert "AC-1 (cacheWrite drop >= 80%): PASS" in output
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): PASS" in output

    def test_mismatched_fixture_fails_ac3(self, tmp_path, monkeypatch):
        with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
            rc = measure.main([
                "--before", str(FIXTURES / "baseline.jsonl"),
                "--after", str(FIXTURES / "experiment.jsonl"),
                "--turn-context-log", str(FIXTURES / "turn-context-mismatched.log"),
            ])
        assert rc == 0
        output = stdout.getvalue()
        assert "AC-1 (cacheWrite drop >= 80%): PASS" in output
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): FAIL" in output

    def test_missing_log_degrades_gracefully(self, tmp_path, monkeypatch):
        with mock.patch("sys.stdout", new_callable=io.StringIO) as stdout:
            rc = measure.main([
                "--before", str(FIXTURES / "baseline.jsonl"),
                "--after", str(FIXTURES / "experiment.jsonl"),
            ])
        assert rc == 0
        output = stdout.getvalue()
        assert "AC-3 (cacheWrite drop within ±10% of prepend block size): FAIL" in output


class TestParsePrependBlockSize:
    def test_parses_average_from_plain_log(self):
        log = FIXTURES / "turn-context-matched.log"
        chars = measure.parse_prepend_block_size(log)
        assert chars == 3600

    def test_returns_none_for_missing_file(self, tmp_path):
        missing = tmp_path / "no-such-file.log"
        assert measure.parse_prepend_block_size(missing) is None

    def test_returns_none_for_non_matching_log(self, tmp_path):
        log = tmp_path / "other.log"
        log.write_text("some unrelated log line\n")
        assert measure.parse_prepend_block_size(log) is None


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
