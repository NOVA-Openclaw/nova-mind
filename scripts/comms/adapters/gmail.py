#!/usr/bin/env python3
"""
Gmail adapter for comms ingest.

Shells out to ``gog gmail messages search`` so the orchestrator stays a simple
Python loop. All subprocess calls are routed through ``_run_command`` so tests
can patch the external CLI without touching the network.

Expected ``gog`` JSON shape (with --include-body):

    [
      {
        "id": "186ff...",
        "threadId": "186ff...",
        "snippet": "short preview...",
        "payload": {
          "headers": [
            {"name": "From", "value": "Sender Name <sender@example.com>"},
            {"name": "Subject", "value": "..."}
          ],
          "parts": [
            {"mimeType": "text/plain", "body": {"data": "base64url..."}}
          ]
        }
      }
    ]

The adapter is intentionally defensive: missing immutable IDs are skipped at
the ingest layer rather than inserted with NULL values.
"""

from __future__ import annotations

import base64
import json
import re
import subprocess
from typing import Optional


PLATFORM = "email"

_EMAIL_RE = re.compile(r"<([^<>]+@[^<>]+)>|")


def _run_command(args: list[str]) -> subprocess.CompletedProcess:
    """Run a subprocess and return its CompletedProcess."""
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        check=False,
    )


def _extract_email_address(from_header: Optional[str]) -> Optional[str]:
    """Return the bare email address from a From header, or the whole string."""
    if not from_header:
        return None
    match = _EMAIL_RE.search(from_header)
    if match and match.group(1):
        return match.group(1).strip().lower()
    # No angle brackets; assume the header is already an address.
    candidate = from_header.strip().lower()
    if "@" in candidate:
        return candidate
    return None


def _decode_body_part(part: dict) -> str:
    """Best-effort extraction of a text/plain body from a message part."""
    body = part.get("body", {})
    data = body.get("data")
    if not data:
        return ""
    try:
        # Gmail returns URL-safe base64.
        decoded = base64.urlsafe_b64decode(data + "==")
        return decoded.decode("utf-8", errors="replace")
    except Exception:
        return ""


def _extract_body(payload: dict) -> str:
    """Return the first text/plain body found in the payload."""
    if not isinstance(payload, dict):
        return ""
    parts = payload.get("parts") or [payload]
    for part in parts:
        if not isinstance(part, dict):
            continue
        if part.get("mimeType") == "text/plain" or "text/plain" in (part.get("mimeType") or ""):
            text = _decode_body_part(part)
            if text:
                return text
    return ""


def _extract_headers(payload: dict) -> dict:
    """Return a lower-cased header name -> value mapping."""
    headers: dict[str, str] = {}
    if not isinstance(payload, dict):
        return headers
    for header in payload.get("headers", []):
        if isinstance(header, dict) and "name" in header and "value" in header:
            headers[header["name"].lower()] = header["value"]
    return headers


def _normalize_message(message: dict) -> dict:
    """Convert a raw Gmail API message into the comms ingest item shape."""
    payload = message.get("payload", {})
    headers = _extract_headers(payload)
    return {
        "platform": PLATFORM,
        "item_id": message.get("id"),
        "thread_id": message.get("threadId"),
        "sender": _extract_email_address(headers.get("from")),
        "subject": headers.get("subject"),
        "body": _extract_body(payload) or message.get("snippet", ""),
        "snippet": message.get("snippet"),
    }


def fetch(
    query: str = "in:inbox -label:reported",
    limit: int = 25,
    account: Optional[str] = None,
    client: Optional[str] = None,
    _run_command=_run_command,
) -> list[dict]:
    """Fetch recent Gmail messages matching ``query``."""
    args = ["gog", "gmail", "messages", "search", query, "--json", "--include-body"]
    if limit:
        args.extend(["--max", str(limit)])
    if account:
        args.extend(["--account", account])
    if client:
        args.extend(["--client", client])

    result = _run_command(args)
    if result.returncode != 0:
        raise RuntimeError(f"gog gmail search failed: {result.stderr.strip()}")

    stdout = result.stdout.strip()
    if not stdout:
        return []

    try:
        data = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON from gog: {exc}") from exc

    messages = data if isinstance(data, list) else data.get("messages", [])
    items: list[dict] = []
    for message in messages:
        if not isinstance(message, dict):
            continue
        item = _normalize_message(message)
        if item.get("item_id"):
            items.append(item)
    return items


def archive(thread_id: str, account: Optional[str] = None, _run_command=_run_command) -> None:
    """
    Archive a resolved Gmail thread by removing the INBOX label.

    If ``thread_id`` is empty, this is a no-op; the caller already validated the
    item exists in the DB.
    """
    if not thread_id:
        return
    args = ["gog", "gmail", "thread", "modify", thread_id, "--remove", "INBOX"]
    if account:
        args.extend(["--account", account])
    result = _run_command(args)
    if result.returncode != 0:
        raise RuntimeError(f"gog gmail thread modify failed: {result.stderr.strip()}")
