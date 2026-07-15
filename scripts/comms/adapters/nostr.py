#!/usr/bin/env python3
"""
Nostr adapter for comms ingest.

Shells out to ``nak req`` to fetch kind-1 mentions and kind-4 DMs directed at
the configured pubkey. Output is line-delimited JSON event objects. Tests patch
``_run_command`` to return fixture events without touching relays.

Normalized item shape:
    {
        "platform": "nostr",
        "item_id": "<32-byte hex event id>",
        "thread_id": "<root event id or None>",
        "sender": "<32-byte hex pubkey>",
        "subject": None,
        "body": "<content>",
        "snippet": None,
    }

Entity resolution converts the hex pubkey to an npub and queries
``resolve_entity_by_identifier('nostr_public_key', npub)``. The npub<->hex
normalization lives in ``bech32.py`` so it can be unit-tested independently.
"""

from __future__ import annotations

import json
import os
import subprocess
from typing import Optional

from .bech32 import hex_to_npub


PLATFORM = "nostr"
DEFAULT_RELAYS = [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band",
]


def _run_command(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, check=False)


def _root_event_id(event: dict) -> Optional[str]:
    """Return the 'e' tag marked as root, if present."""
    for tag in event.get("tags", []):
        if isinstance(tag, (list, tuple)) and len(tag) >= 2 and tag[0] == "e":
            marker = tag[3] if len(tag) >= 4 else ""
            if marker == "root":
                return tag[1]
    return None


def _normalize_event(event: dict) -> dict:
    pubkey = event.get("pubkey", "")
    return {
        "platform": PLATFORM,
        "item_id": event.get("id"),
        "thread_id": _root_event_id(event) or event.get("id"),
        "sender": pubkey,
        "subject": None,
        "body": event.get("content", ""),
        "snippet": None,
    }


def _parse_events(stdout: str) -> list[dict]:
    events: list[dict] = []
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and obj.get("id"):
            events.append(obj)
    return events


def _our_pubkey() -> Optional[str]:
    """Read the hex pubkey to listen for from the environment."""
    pubkey = os.environ.get("NOSTR_PUBLIC_KEY", "").strip()
    if pubkey:
        return pubkey
    # Accept an npub and normalize it to hex for nak's -p filter.
    npub = os.environ.get("NOSTR_NPUB", "").strip()
    if npub:
        from .bech32 import npub_to_hex
        return npub_to_hex(npub)
    return None


def fetch(
    limit: int = 50,
    relays: Optional[list[str]] = None,
    _run_command=_run_command,
) -> list[dict]:
    """Fetch kind-1 mentions and kind-4 DMs directed at our pubkey."""
    pubkey = _our_pubkey()
    if not pubkey:
        raise RuntimeError("NOSTR_PUBLIC_KEY or NOSTR_NPUB must be set")

    relay_list = relays or DEFAULT_RELAYS
    args = [
        "nak", "req",
        "-k", "1", "-k", "4",
        "-p", pubkey,
        "-l", str(limit),
    ] + relay_list

    result = _run_command(args)
    if result.returncode != 0:
        raise RuntimeError(f"nak req failed: {result.stderr.strip()}")

    return [_normalize_event(e) for e in _parse_events(result.stdout)]


def resolve_pubkey(hex_key: str) -> Optional[str]:
    """Return the npub form of a hex pubkey for entity resolution."""
    try:
        return hex_to_npub(hex_key)
    except Exception:
        return None
