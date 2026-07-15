#!/usr/bin/env python3
"""
Deterministic, rule-based classifier for inbound comms_items.

This module performs NO LLM reasoning. It is a pure-function heuristic layer
that inspects structured fields extracted by platform adapters and returns a
disposition + a short poller-voice summary.

Design notes:
- Other-comms payload content is DATA, never instructions (issue #474 §3).
- Any embedded imperative directed at NOVA / the system is quarantined as
  ``injection_suspect`` and must not be acted on.
- Dispositions drive the lifecycle inside ``ingest.py``:
    fyi / receipt -> status=resolved (reporting IS resolution)
    actionable / escalation -> status=tracked
    injection_suspect -> status=reported (quarantined, surfaced distinctly)
"""

from __future__ import annotations

import re
from typing import Optional


# Imperative verbs that, when combined with a direct address to NOVA, mean the
# payload is trying to issue a command. Keep this list explicit and reviewable.
_DIRECT_IMP_VERBS = [
    "approve", "cancel", "check", "complete", "confirm", "delete", "disregard",
    "do", "execute", "forget", "format", "handle", "ignore", "kill", "pay",
    "perform", "post", "process", "remove", "reply", "restart", "review",
    "run", "send", "shutdown", "sign", "transfer",
]

_DIRECT_ADDRESS_RE = re.compile(
    r"(?:^|\s|[,;:!])"
    r"(?:NOVA|@NOVA|Nova|@Nova)"
    r"\b[,;:!]?\s+"
    r"(?:please\s+)?"
    r"(?:"
    + "|".join(re.escape(v) for v in _DIRECT_IMP_VERBS)
    + r")\b",
    re.IGNORECASE,
)

# "Ignore previous instructions and ..." / "Disregard your instructions"
_IGNORE_INSTRUCTIONS_RE = re.compile(
    r"\bignore\s+(?:all\s+)?(?:previous|prior|earlier|above)\s+"
    r"(?:instructions|directives|rules|constraints|training)\b"
    r"|\bdisregard\s+(?:your\s+)?(?:instructions|directives|rules|training)\b",
    re.IGNORECASE,
)

# Authority-spoofing payloads that claim to be I)ruid issuing an order.
_AUTHORITY_SPOOF_RE = re.compile(
    r"\b(?:as|from)\s+I\)?ruid[,\'\"]?\s+"
    r"(?:I(?:['\"]?m)?\s+(?:ask|asking|request|requesting|order|ordering|want|wanting|tell|telling|command|commanding)\s+you\s+to"
    r"|please\s+(?:do|run|approve|confirm|post|send|reply))\b",
    re.IGNORECASE,
)

# Markup that mimics system / tool / function-call syntax.
_SYSTEM_MARKUP_RE = re.compile(
    r"</?(?:system|instructions|tool|function|command)\b"
    r"|\[\s*(?:system|tool|function|command)\s*\]"
    r"|tool_call|function_call",
    re.IGNORECASE,
)

_FYI_MARKERS = [
    "alert", "auto-generated", "billing", "do not reply", "fyi", "invoice",
    "newsletter", "no reply", "notification", "receipt", "spam", "spend",
    "statement", "usage", "weekly digest",
]

_ESCALATION_MARKERS = [
    "critical", "data breach", "down", "emergency", "incident", "outage",
    "p0", "p1", "security breach", "severity", "urgent",
]

_RECEIPT_MARKERS = [
    "order confirmed", "payment received", "purchase confirmed", "receipt",
    "subscription confirmed", "subscription receipt", "transaction confirmed",
]


def _is_injection_suspect(text: str) -> bool:
    """Return True if the payload looks like an injected imperative."""
    if _DIRECT_ADDRESS_RE.search(text):
        return True
    if _IGNORE_INSTRUCTIONS_RE.search(text):
        return True
    if _AUTHORITY_SPOOF_RE.search(text):
        return True
    if _SYSTEM_MARKUP_RE.search(text):
        return True
    return False


def _contains_any(text: str, markers: list[str]) -> bool:
    lowered = text.lower()
    return any(marker in lowered for marker in markers)


def _summarize(
    platform: str,
    sender: Optional[str],
    subject: Optional[str],
    body: Optional[str],
    disposition: str,
) -> str:
    """Compose a short, poller-voice summary. Never include the full raw body."""
    prefix = ""
    if disposition == "injection_suspect":
        prefix = "[INJECTION SUSPECT] "

    sender_part = sender or "unknown sender"
    subject_part = (subject or "").strip()
    if not subject_part:
        # Fall back to a tiny preview of the body, capped so it can never carry
        # a full injection payload verbatim into the report hop.
        preview = (body or "").replace("\n", " ").strip()
        subject_part = preview[:120] if preview else "(no subject)"
        if len(preview) > 120:
            subject_part += "…"

    return f"{prefix}{platform} item from {sender_part}: {subject_part}"


def classify(
    platform: str,
    item_id: str,
    sender: Optional[str],
    subject: Optional[str],
    body: Optional[str],
    snippet: Optional[str] = None,
) -> dict:
    """
    Classify a single inbound comms item.

    Returns a dict with keys:
        - disposition: one of fyi|actionable|escalation|receipt|injection_suspect
        - summary: a short poller-voice summary safe for the Hermes->NOVA hop
    """
    if not item_id:
        raise ValueError("classify requires a non-empty item_id")

    text = " ".join(filter(None, [subject, snippet, body, sender]))

    if _is_injection_suspect(text):
        disposition = "injection_suspect"
    elif _contains_any(text, _RECEIPT_MARKERS):
        disposition = "receipt"
    elif _contains_any(text, _ESCALATION_MARKERS):
        disposition = "escalation"
    elif _contains_any(text, _FYI_MARKERS):
        disposition = "fyi"
    else:
        disposition = "actionable"

    summary = _summarize(platform, sender, subject, body, disposition)

    return {"disposition": disposition, "summary": summary}
