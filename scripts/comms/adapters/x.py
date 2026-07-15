#!/usr/bin/env python3
"""
X (Twitter) adapter for comms ingest.

Shells out to ``xurl`` for mentions and DMs. Both commands are expected to emit
JSON (either a single array or one JSON object per line). Tests patch
``_run_command`` to return fixture output without touching the live X API.

Normalized item shape:
    {
        "platform": "x",
        "item_id": "<tweet_id or dm_id>",
        "thread_id": "<conversation_id or id>",
        "sender": "<handle without @>",
        "subject": None,
        "body": "<text>",
        "snippet": None,
    }

Entity resolution is intentionally left NULL in v1: there is no established
X-handle entity_facts key yet (issue #474, design decision F). The adapter does
not invent a new identifier convention ahead of #227.
"""

from __future__ import annotations

import json
import subprocess
from typing import Optional


PLATFORM = "x"


def _run_command(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, check=False)


def _strip_at(handle: Optional[str]) -> Optional[str]:
    if not handle:
        return None
    return handle.lstrip("@")


def _normalize_tweet(tweet: dict) -> dict:
    """Normalize a mention/timeline tweet object."""
    author = tweet.get("author") or {}
    return {
        "platform": PLATFORM,
        "item_id": str(tweet.get("id", "")) if tweet.get("id") is not None else None,
        "thread_id": tweet.get("conversation_id") or str(tweet.get("id", "")),
        "sender": _strip_at(author.get("username") or tweet.get("author_username")),
        "subject": None,
        "body": tweet.get("text") or "",
        "snippet": None,
    }


def _normalize_dm(dm: dict) -> dict:
    """Normalize a DM object."""
    sender = dm.get("sender") or {}
    return {
        "platform": PLATFORM,
        "item_id": str(dm.get("id", "")) if dm.get("id") is not None else None,
        "thread_id": dm.get("conversation_id") or str(dm.get("id", "")),
        "sender": _strip_at(sender.get("username") or dm.get("sender_username")),
        "subject": None,
        "body": dm.get("text") or "",
        "snippet": None,
    }


def _parse_json_output(stdout: str) -> list[dict]:
    """Parse xurl JSON output: either a JSON array or line-delimited objects."""
    stdout = stdout.strip()
    if not stdout:
        return []
    try:
        data = json.loads(stdout)
        if isinstance(data, list):
            return data
        return [data]
    except json.JSONDecodeError:
        items: list[dict] = []
        for line in stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                items.append(json.loads(line))
            except json.JSONDecodeError:
                continue
        return items


def fetch_mentions(
    limit: int = 25,
    _run_command=_run_command,
) -> list[dict]:
    args = ["xurl", "mentions"]
    if limit:
        args.extend(["-n", str(limit)])
    result = _run_command(args)
    if result.returncode != 0:
        raise RuntimeError(f"xurl mentions failed: {result.stderr.strip()}")
    return [_normalize_tweet(t) for t in _parse_json_output(result.stdout) if t.get("id")]


def fetch_dms(
    limit: int = 25,
    _run_command=_run_command,
) -> list[dict]:
    args = ["xurl", "dms"]
    if limit:
        args.extend(["-n", str(limit)])
    result = _run_command(args)
    if result.returncode != 0:
        raise RuntimeError(f"xurl dms failed: {result.stderr.strip()}")
    return [_normalize_dm(d) for d in _parse_json_output(result.stdout) if d.get("id")]


def fetch(
    limit: int = 25,
    _run_command=_run_command,
) -> list[dict]:
    """Fetch both mentions and DMs, flattening into one list."""
    items: list[dict] = []
    items.extend(fetch_mentions(limit=limit, _run_command=_run_command))
    items.extend(fetch_dms(limit=limit, _run_command=_run_command))
    return items
