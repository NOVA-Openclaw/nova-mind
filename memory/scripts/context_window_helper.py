#!/usr/bin/env python3
"""
Shared context-window helpers for memory extraction.

Provides config loading, context truncation, and prompt formatting used by
both the per-turn hook path and the batch/replay path. Follows the same
convention as cognition/metacognition/confidence-check:
  - CONFIG.max_prior_messages defaults to 10
  - messages.slice(-N) semantics (most recent N, chronological order preserved)

Issues: #611
"""

import json
import os
import re
import sys
from typing import Any, Optional

# Default config path mirrors extract_memories.py
DEFAULT_CONFIG_PATH = os.path.expanduser(
    "~/.openclaw/scripts/memory-extraction-config.json"
)

DEFAULT_MAX_PRIOR_MESSAGES = 10
DEFAULT_CONTEXT_WINDOW_ENABLED = True

# Context size limits (defense in depth for prompt cost/size)
MAX_CONTEXT_MESSAGE_CHARS = 2000
MAX_TOTAL_CONTEXT_CHARS = 8000
TRUNCATION_MARKER = "\n...[truncated]"


def load_config(config_path: Optional[str] = None) -> dict:
    """Load extraction config from JSON file. Returns empty dict on any error."""
    path = config_path or DEFAULT_CONFIG_PATH
    try:
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(
            f"[context_window_helper] WARNING: Could not load config {path}: {e}",
            file=sys.stderr,
        )
    return {}


def resolve_max_prior_messages(config: Optional[dict] = None) -> int:
    """Resolve max_prior_messages with the same graceful fallback contract as
    loadExtractionTimeoutMs() / resolvePythonCmd() in handler.ts.

    Valid positive integers are honored. 0 disables context gathering.
    Negative, non-numeric, or missing values fall back to DEFAULT_MAX_PRIOR_MESSAGES.
    """
    cfg = config if config is not None else load_config()
    value = cfg.get("max_prior_messages")
    if isinstance(value, int) and value >= 0:
        return value
    # Reject non-int numeric (floats, booleans masquerading as ints) and negative.
    if isinstance(value, (float, bool)):
        return DEFAULT_MAX_PRIOR_MESSAGES
    if isinstance(value, str):
        try:
            parsed = int(value)
            if parsed >= 0:
                return parsed
        except ValueError:
            pass
    return DEFAULT_MAX_PRIOR_MESSAGES


def is_context_window_enabled(config: Optional[dict] = None) -> bool:
    """Return True if the context window should be gathered/used.

    Explicitly false disables the window entirely. Missing/invalid values
    default to enabled.
    """
    cfg = config if config is not None else load_config()
    value = cfg.get("context_window_enabled")
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() not in ("false", "0", "off", "no", "disabled")
    if isinstance(value, int):
        return value != 0
    return DEFAULT_CONTEXT_WINDOW_ENABLED


def _coerce_message(msg: Any) -> Optional[dict]:
    """Normalize a context message dict into the internal shape."""
    if not isinstance(msg, dict):
        return None
    content = (msg.get("content") or "").strip()
    if not content:
        return None
    return {
        "role": str(msg.get("role") or "user").lower(),
        "content": content,
        "timestamp": msg.get("timestamp") or "",
        "sender_name": str(msg.get("sender_name") or "").strip(),
    }


def truncate_message(content: str, max_chars: int = MAX_CONTEXT_MESSAGE_CHARS) -> str:
    """Truncate a single context message safely, appending a marker."""
    if len(content) <= max_chars:
        return content
    # Leave room for the marker by trimming before the marker is appended.
    cut_at = max(0, max_chars - len(TRUNCATION_MARKER))
    return content[:cut_at].rstrip() + TRUNCATION_MARKER


def truncate_context_messages(
    messages: list[dict],
    max_prior_messages: Optional[int] = None,
    max_per_message_chars: int = MAX_CONTEXT_MESSAGE_CHARS,
    max_total_chars: int = MAX_TOTAL_CONTEXT_CHARS,
) -> list[dict]:
    """Return the most recent N context messages, truncated for safety.

    - Slice to the last max_prior_messages entries (chronological order preserved).
    - Truncate each message to max_per_message_chars.
    - If total truncated text still exceeds max_total_chars, drop oldest messages
      until the remaining window fits.
    """
    if max_prior_messages is None:
        max_prior_messages = resolve_max_prior_messages()

    normalized = [_coerce_message(m) for m in messages]
    normalized = [m for m in normalized if m]

    # Most recent N, chronological order preserved.
    window = normalized[-max_prior_messages:] if max_prior_messages > 0 else []

    # Per-message truncation.
    truncated = [
        {**m, "content": truncate_message(m["content"], max_per_message_chars)}
        for m in window
    ]

    # Total budget: drop oldest messages until we fit.
    while truncated:
        total = sum(len(m["content"]) for m in truncated)
        if total <= max_total_chars:
            break
        truncated.pop(0)

    return truncated


def format_context_for_prompt(
    context_messages: list[dict],
    current_content: str,
    current_role: str = "user",
) -> str:
    """Build the CONTEXT + CURRENT MESSAGE block for the extraction prompt.

    Mirrors the existing memory-catchup.sh labeling convention:
      [USER] 1:\ncontent
      [NOVA] 2:\ncontent
      [CURRENT USER MESSAGE - EXTRACT FROM THIS]\ncurrent

    When no context messages are provided, falls back to the pre-#611
    simple MESSAGE label so the prompt shape is identical for no-context runs.
    """
    lines: list[str] = []

    if context_messages:
        lines.append("=" * 40)
        lines.append("PRIOR CONVERSATION CONTEXT (for disambiguation only)")
        lines.append("=" * 40)
        for i, msg in enumerate(context_messages, start=1):
            role_label = "NOVA" if msg.get("role") == "assistant" else "USER"
            sender = msg.get("sender_name") or ""
            if sender:
                role_label = f"{role_label} ({sender})"
            lines.append(f"[{role_label}] {i}:")
            lines.append(msg.get("content", ""))
            lines.append("---")
        lines.append("")

        current_label = (
            "[CURRENT NOVA MESSAGE - EXTRACT FROM THIS]"
            if current_role == "assistant"
            else "[CURRENT USER MESSAGE - EXTRACT FROM THIS]"
        )
        lines.append("=" * 40)
        lines.append(current_label)
        lines.append("=" * 40)
        lines.append(current_content)
    else:
        lines.append(f"MESSAGE:\n{current_content}")

    return "\n".join(lines)


def parse_context_json(raw: Optional[str]) -> list[dict]:
    """Parse the EXTRACTION_CONTEXT_JSON env var value into context messages."""
    if not raw:
        return []
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, list):
            return [m for m in (_coerce_message(x) for x in parsed) if m]
    except json.JSONDecodeError as e:
        print(
            f"[context_window_helper] WARNING: Could not parse context JSON: {e}",
            file=sys.stderr,
        )
    return []
