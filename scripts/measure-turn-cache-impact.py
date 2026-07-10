#!/usr/bin/env python3
"""
Measure prompt-cache impact for the turn-context placement change (nova-mind #439).

Reads an OpenClaw session JSONL file, extracts per-turn usage from assistant
message entries, and computes the baseline/validation metrics from the issue
acceptance criteria:

  - cache_hit_ratio = cacheRead / (cacheRead + cacheWrite + input)
  - steady-state cacheWrite/turn (excluding turn 1 and model-change/compaction turns)
  - average input tokens per turn

Usage:
  python3 scripts/measure-turn-cache-impact.py \
      /home/nova/.openclaw/agents/nova/sessions/<uuid>.jsonl

  python3 scripts/measure-turn-cache-impact.py \
      --before baseline.jsonl --after experiment.jsonl
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


# Approximate characters per token for English-like text. This is a coarse
# heuristic used to compare the turn-context prepend block (measured in
# characters by the plugin) against provider cacheWrite deltas (measured in
# tokens). Actual tokenization depends on model and language mix.
CHARS_PER_TOKEN_ESTIMATE = 4


@dataclass(frozen=True)
class TurnUsage:
    turn_number: int
    role: str
    model: str | None
    cache_read: int
    cache_write: int
    input_tokens: int
    output_tokens: int | None


def _get_usage_field(usage: dict, *names: str) -> int:
    """Return the first present numeric usage field, or 0."""
    for name in names:
        value = usage.get(name)
        if isinstance(value, (int, float)):
            return int(value)
    return 0


def parse_session_jsonl(path: Path) -> list[TurnUsage]:
    """Parse assistant message entries from an OpenClaw session JSONL file."""
    turns: list[TurnUsage] = []

    with path.open("r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            # We care about assistant message entries that carry usage.
            # In OpenClaw session JSONL these are typically role == "assistant"
            # and may be wrapped in a "message" object or flat.
            message = entry.get("message") if isinstance(entry.get("message"), dict) else entry
            if not isinstance(message, dict):
                continue
            if message.get("role") != "assistant":
                continue

            usage = message.get("usage")
            if not isinstance(usage, dict):
                continue

            # Accept common input-token field names seen across providers.
            input_tokens = _get_usage_field(
                usage,
                "input",
                "input_tokens",
                "prompt_tokens",
                "promptTokens",
            )
            cache_read = _get_usage_field(usage, "cacheRead", "cache_read_input_tokens")
            cache_write = _get_usage_field(usage, "cacheWrite", "cache_creation_input_tokens")
            output_tokens = _get_usage_field(usage, "output", "output_tokens", "completion_tokens")

            turns.append(
                TurnUsage(
                    turn_number=len(turns) + 1,
                    role="assistant",
                    model=message.get("model") or entry.get("model"),
                    cache_read=cache_read,
                    cache_write=cache_write,
                    input_tokens=input_tokens,
                    output_tokens=output_tokens if output_tokens > 0 else None,
                )
            )

    return turns


def filter_steady_state_turns(turns: list[TurnUsage]) -> list[TurnUsage]:
    """
    Exclude turn 1 and any turn where the model changed from the previous turn.
    This approximates "model-change/compaction turns" without needing to parse
    internal compaction events.
    """
    steady: list[TurnUsage] = []
    prev_model: str | None = None

    for turn in turns:
        # Exclude the first assistant turn (cache warmup / no prior transcript).
        if turn.turn_number == 1:
            prev_model = turn.model
            continue

        # Exclude turns where the model changed (likely compaction / model switch).
        if prev_model is not None and turn.model != prev_model:
            prev_model = turn.model
            continue

        prev_model = turn.model
        steady.append(turn)

    return steady


def compute_metrics(turns: list[TurnUsage]) -> dict:
    steady = filter_steady_state_turns(turns)

    total_cache_read = sum(t.cache_read for t in turns)
    total_cache_write = sum(t.cache_write for t in turns)
    total_input = sum(t.input_tokens for t in turns)
    total_tokens = total_cache_read + total_cache_write + total_input

    cache_hit_ratio = total_cache_read / total_tokens if total_tokens > 0 else 0.0

    steady_cache_write_avg = (
        sum(t.cache_write for t in steady) / len(steady) if steady else 0.0
    )
    steady_input_avg = sum(t.input_tokens for t in steady) / len(steady) if steady else 0.0
    steady_cache_read_avg = sum(t.cache_read for t in steady) / len(steady) if steady else 0.0

    return {
        "total_turns": len(turns),
        "steady_state_turns": len(steady),
        "cache_hit_ratio": cache_hit_ratio,
        "total_cache_read": total_cache_read,
        "total_cache_write": total_cache_write,
        "total_input_tokens": total_input,
        "steady_state": {
            "cache_write_per_turn": steady_cache_write_avg,
            "cache_read_per_turn": steady_cache_read_avg,
            "input_tokens_per_turn": steady_input_avg,
        },
    }


def format_metrics(metrics: dict, label: str) -> str:
    lines = [
        f"=== {label} ===",
        f"  total_turns:             {metrics['total_turns']}",
        f"  steady_state_turns:      {metrics['steady_state_turns']}",
        f"  cache_hit_ratio:         {metrics['cache_hit_ratio']:.4f} "
        f"({metrics['cache_hit_ratio'] * 100:.2f}%)",
        f"  total_cache_read:        {metrics['total_cache_read']}",
        f"  total_cache_write:       {metrics['total_cache_write']}",
        f"  total_input_tokens:      {metrics['total_input_tokens']}",
        "  steady_state:",
        f"    cache_write/turn:      {metrics['steady_state']['cache_write_per_turn']:.2f}",
        f"    cache_read/turn:       {metrics['steady_state']['cache_read_per_turn']:.2f}",
        f"    input_tokens/turn:     {metrics['steady_state']['input_tokens_per_turn']:.2f}",
    ]
    return "\n".join(lines)


# Regex to extract the prepend block size emitted by the turn-context plugin:
#   [turn-context] before_prompt_build DONE ... injecting prepend=<N>chars ...
PREPEND_BLOCK_RE = re.compile(r"prepend=(\d+)chars")


def estimate_tokens_from_chars(chars: int) -> int:
    """Estimate token count from a character count using the English-text heuristic."""
    return round(chars / CHARS_PER_TOKEN_ESTIMATE)


def parse_prepend_block_size(path: Path | None) -> int | None:
    """
    Parse the average dynamic prepend block size (in chars) from a turn-context
    log file. The plugin emits lines like:

      [turn-context] before_prompt_build DONE ... injecting prepend=1234chars ...

    Returns the average prepend size across all matched lines, or None if no
    matching log lines are found. The regex works for plain logs and for JSONL
    entries where the log message is embedded in a JSON object.
    """
    if not path:
        return None

    sizes: list[int] = []
    try:
        with path.open("r", encoding="utf-8") as fh:
            for raw_line in fh:
                if "[turn-context]" not in raw_line or "before_prompt_build DONE" not in raw_line:
                    continue
                match = PREPEND_BLOCK_RE.search(raw_line)
                if match:
                    sizes.append(int(match.group(1)))
    except OSError as err:
        print(f"Warning: could not read turn-context log {path}: {err}", file=sys.stderr)
        return None

    if not sizes:
        return None

    return round(sum(sizes) / len(sizes))


def compare_metrics(before: dict, after: dict, prepend_block_size: int | None = None) -> str:
    before_write = before["steady_state"]["cache_write_per_turn"]
    after_write = after["steady_state"]["cache_write_per_turn"]
    write_delta = after_write - before_write
    write_delta_pct = (write_delta / before_write * 100) if before_write else 0.0

    before_ratio = before["cache_hit_ratio"]
    after_ratio = after["cache_hit_ratio"]
    ratio_delta_pp = (after_ratio - before_ratio) * 100

    lines = [
        "=== Comparison (after vs before) ===",
        f"  steady_state cache_write/turn: {before_write:.2f} -> {after_write:.2f} "
        f"(Δ {write_delta:+.2f}, {write_delta_pct:+.1f}%)",
        f"  cache_hit_ratio:               {before_ratio:.4f} -> {after_ratio:.4f} "
        f"(Δ {ratio_delta_pp:+.2f} pp)",
    ]

    prepend_tokens: int | None = None
    if prepend_block_size is not None:
        lines.append(f"  prepend_block_size (chars):       {prepend_block_size}")
        prepend_tokens = estimate_tokens_from_chars(prepend_block_size)
        lines.append(f"  prepend_block_size (est. tokens): {prepend_tokens}")

    ac1_met = write_delta_pct <= -80.0
    ac2_met = ratio_delta_pp >= 15.0 or (
        after["total_cache_read"] + after["total_cache_write"] > 0
        and after["total_cache_read"] / (after["total_cache_read"] + after["total_cache_write"]) >= 0.90
    )

    # AC-3 sanity check: the measured drop in cacheWrite/turn (in tokens)
    # should be within ±10% of the dynamic prepend block size estimated from
    # the turn-context character count. This catches the false positive where
    # cacheWrite dropped because the block was shrunk rather than moved out of
    # the cached prefix.
    actual_drop = before_write - after_write
    if prepend_tokens is not None and prepend_tokens > 0:
        ac3_met = abs(actual_drop - prepend_tokens) / prepend_tokens <= 0.10
    else:
        ac3_met = False

    lines.append(f"  AC-1 (cacheWrite drop >= 80%): {'PASS' if ac1_met else 'FAIL'}")
    lines.append(f"  AC-2 (ratio improvement >= 15pp or turns 3+ cacheRead/(read+write) >= 90%): "
                 f"{'PASS' if ac2_met else 'FAIL'}")
    lines.append(f"  AC-3 (cacheWrite drop within ±10% of prepend block size): "
                 f"{'PASS' if ac3_met else 'FAIL'}")

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Measure prompt-cache impact from OpenClaw session JSONL usage data."
    )
    parser.add_argument("session", nargs="?", type=Path, help="Path to session JSONL file")
    parser.add_argument("--before", type=Path, help="Baseline session JSONL")
    parser.add_argument("--after", type=Path, help="Experiment session JSONL")
    parser.add_argument(
        "--turn-context-log",
        type=Path,
        dest="turn_context_log",
        help=(
            "Path to a turn-context log file (or JSONL containing turn-context log lines). "
            "Used to extract the average prepend=<N>chars block size for the AC-3 sanity check."
        ),
    )
    args = parser.parse_args(argv)

    if args.before and args.after:
        before_turns = parse_session_jsonl(args.before)
        after_turns = parse_session_jsonl(args.after)
        before_metrics = compute_metrics(before_turns)
        after_metrics = compute_metrics(after_turns)
        prepend_block_size = parse_prepend_block_size(args.turn_context_log)
        print(format_metrics(before_metrics, "Before"))
        print()
        print(format_metrics(after_metrics, "After"))
        print()
        print(compare_metrics(before_metrics, after_metrics, prepend_block_size))
        return 0

    if not args.session:
        parser.error("Provide a session JSONL path or both --before and --after")

    turns = parse_session_jsonl(args.session)
    metrics = compute_metrics(turns)
    print(format_metrics(metrics, "Session"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
