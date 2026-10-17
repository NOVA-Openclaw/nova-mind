#!/usr/bin/env python3
"""Inspect a pgschema plan and report steps that require a PostgreSQL superuser.

Reads a pgschema plan JSON and checks every step for SQL patterns that can
only run as a PostgreSQL superuser (CREATE EXTENSION, FDW server/user mapping,
CREATE EVENT TRIGGER, SECURITY DEFINER functions, etc.).

Exit code:
  0 with no output if the plan contains no superuser-only steps.
  1 and one stderr line per superuser-only step otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any

SUPERUSER_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bCREATE\s+EXTENSION\b", re.IGNORECASE), "CREATE EXTENSION"),
    (re.compile(r"\bCREATE\s+SERVER\b", re.IGNORECASE), "CREATE SERVER (FDW)"),
    (re.compile(r"\bCREATE\s+USER\s+MAPPING\b", re.IGNORECASE), "CREATE USER MAPPING (FDW)"),
    (re.compile(r"\bCREATE\s+EVENT\s+TRIGGER\b", re.IGNORECASE), "CREATE EVENT TRIGGER"),
    (re.compile(r"\bSECURITY\s+DEFINER\b", re.IGNORECASE), "SECURITY DEFINER function"),
]


def _step_requires_superuser(step: dict[str, Any]) -> str | None:
    """Return a human-readable reason if the step requires superuser, else None."""
    if step.get("type") == "extension":
        return "CREATE EXTENSION"
    sql = step.get("sql", "")
    for pattern, reason in SUPERUSER_PATTERNS:
        if pattern.search(sql):
            return reason
    return None


def check_plan(plan_path: str) -> list[tuple[str, str, str]]:
    """Return a list of (path, reason, sql_snippet) for superuser-only steps."""
    with open(plan_path, "r", encoding="utf-8") as fh:
        plan = json.load(fh)

    found: list[tuple[str, str, str]] = []
    for group in plan.get("groups") or []:
        for step in group.get("steps", []):
            reason = _step_requires_superuser(step)
            if reason:
                path = step.get("path", "")
                sql = step.get("sql", "")[:120].replace("\n", " ")
                found.append((path, reason, sql))
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, help="Input pgschema plan JSON")
    args = parser.parse_args(argv)

    try:
        found = check_plan(args.plan)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"Failed to read plan: {exc}", file=sys.stderr)
        return 2

    if not found:
        return 0

    print("The following schema steps require a PostgreSQL superuser:", file=sys.stderr)
    for path, reason, sql in found:
        print(f"  [{reason}] {path}: {sql}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
