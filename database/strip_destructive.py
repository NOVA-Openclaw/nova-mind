#!/usr/bin/env python3
"""Strip destructive operations from a pgschema plan JSON.

Reads a pgschema plan (``pgschema plan --output-json``), removes every step
whose ``operation`` is ``"drop"`` (DROP TABLE, DROP COLUMN, DROP CONSTRAINT,
DROP INDEX, DROP VIEW, DROP TYPE, DROP FUNCTION, DROP TRIGGER, DROP SEQUENCE,
etc.), and emits the additive remainder.

Design constraints (nova-mind#498):

* Top-level metadata fields are preserved byte-for-byte.
* Only steps with ``.operation == "drop"`` are removed.  ALTER and other
  non-DROP operations pass through unchanged; pgschema normally expresses
  destructive changes as DROP steps, so this matches the installer's previous
  hazard-detection scope.
* A missing or ``null`` ``groups`` is normalized to an empty array.
* The script reports the number of removed steps on stderr so the installer
  can log what was stripped.

Hard failures (nonzero exit):

* Malformed plan JSON or unsupported plan version.
* ``groups`` present but not an array.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SUPPORTED_PLAN_VERSIONS = {"1.0.0"}


def _validate_plan(data: Any) -> None:
    """Validate top-level plan structure."""
    if not isinstance(data, dict):
        raise ValueError("Plan JSON must be an object")

    required_keys = {"version", "pgschema_version", "source_fingerprint"}
    missing = required_keys - set(data.keys())
    if missing:
        raise ValueError(f"Malformed plan JSON: missing keys {sorted(missing)}")

    version = data.get("version")
    if version not in SUPPORTED_PLAN_VERSIONS:
        raise ValueError(
            f"Unsupported plan format version {version!r}; "
            f"supported versions: {sorted(SUPPORTED_PLAN_VERSIONS)}"
        )

    groups = data.get("groups")
    if groups is None:
        return
    if not isinstance(groups, list):
        raise ValueError("Malformed plan JSON: 'groups' must be an array")

    for gidx, group in enumerate(groups):
        if not isinstance(group, dict) or not isinstance(group.get("steps"), list):
            raise ValueError(
                f"Malformed plan JSON: groups[{gidx}] must be an object with a 'steps' array"
            )


def strip_destructive(plan: dict[str, Any]) -> tuple[dict[str, Any], int]:
    """Return a new plan with all DROP steps removed and the count removed."""
    _validate_plan(plan)

    new_groups: list[dict[str, Any]] = []
    stripped = 0

    for group in plan.get("groups") or []:
        kept_steps: list[dict[str, Any]] = []
        for step in group.get("steps", []):
            if step.get("operation") == "drop":
                stripped += 1
                continue
            kept_steps.append(step)
        if kept_steps:
            new_groups.append({"steps": kept_steps})

    new_plan = {
        "version": plan["version"],
        "pgschema_version": plan["pgschema_version"],
        "created_at": plan.get("created_at"),
        "source_fingerprint": plan["source_fingerprint"],
        "groups": new_groups,
    }
    return new_plan, stripped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, help="Input pgschema plan JSON")
    parser.add_argument("--output", required=True, help="Output filtered plan JSON")
    args = parser.parse_args(argv)

    try:
        plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in plan file: {exc}", file=sys.stderr)
        return 2
    except FileNotFoundError:
        print(f"ERROR: plan file not found: {args.plan}", file=sys.stderr)
        return 2

    try:
        new_plan, stripped = strip_destructive(plan)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    Path(args.output).write_text(
        json.dumps(new_plan, indent=2) + "\n", encoding="utf-8"
    )
    print(stripped, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
