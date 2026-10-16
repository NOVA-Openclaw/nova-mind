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
* An optional ``--ignore-objects`` argument (legacy alias
  ``--ignore-table-triggers``) removes every plan step that refers to a named
  table or its default ``<table>_id_seq`` sequence.  This closes the peer-FDW
  bootstrap-context gap (nova-mind#608 / #1231): pgschema v1.7.2 does not
  honour the ``[triggers]`` ignore section for ``type="table.trigger"`` steps,
  and privilege/comment/constraint/index steps for the peer VIEW / foreign-
  table stack are owned by the FDW setup (#520) rather than ``schema.sql``.
  The installer uses this flag in peer mode so that every shadowed relation
  (table/foreign table/view, sequence, triggers, privileges, comments,
  constraints, indexes) is left untouched.
* The list fed to ``--ignore-objects`` is dynamic: the installer queries the
  target database for public relations with ``relkind IN ('f','v')`` whose
  names match a table declared by ``schema.sql`` (#1231).
* A missing or ``null`` ``groups`` is normalized to an empty array.
* The script reports the number of removed steps on stderr so the installer
  can log what was stripped, and also reports the names of auto-excluded
  objects.

Hard failures (nonzero exit):

* Malformed plan JSON or unsupported plan version.
* ``groups`` present but not an array.
"""

from __future__ import annotations

import argparse
import json
import re
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


def _compile_ignore_patterns(
    ignored_objects: list[str],
) -> list[tuple[str, re.Pattern[str]]]:
    """Compile path-component regexes for an object and its id sequence.

    The path in a pgschema step uses ``.`` as a delimiter, e.g.
    ``public.table.column``, ``privileges.TABLE.table.role``, or
    ``privileges.SEQUENCE.table_id_seq.role``.  We match the bare object name
    as a full path component so that ``agent_bootstrap_context`` does NOT
    accidentally match ``agent_bootstrap_context_local``.

    Returns a list of (object_name, pattern) so callers can report exactly
    which object caused a step to be stripped.
    """
    patterns: list[tuple[str, re.Pattern[str]]] = []
    for obj in ignored_objects:
        for target in (obj, f"{obj}_id_seq"):
            patterns.append(
                (obj, re.compile(rf"(?:^|\.){re.escape(target)}(?:\.|$)"))
            )
    return patterns


def _step_matches_ignored(
    step: dict[str, Any],
    ignore_patterns: list[tuple[str, re.Pattern[str]]],
) -> str | None:
    """Return the object name that matched, or None if no match."""
    path = step.get("path", "")
    for obj, pattern in ignore_patterns:
        if pattern.search(path):
            return obj
    return None


def strip_destructive(
    plan: dict[str, Any],
    ignored_objects: list[str] | None = None,
) -> tuple[dict[str, Any], int, dict[str, list[str]]]:
    """Return a new plan with all DROP steps removed and the count removed.

    Also returns a mapping from ignored object name to the list of paths that
    were stripped because of that object, so callers can log exactly what was
    auto-excluded and why.
    """
    _validate_plan(plan)

    ignore_patterns = _compile_ignore_patterns(ignored_objects or [])

    new_groups: list[dict[str, Any]] = []
    stripped = 0
    excluded: dict[str, list[str]] = {}

    for group in plan.get("groups") or []:
        kept_steps: list[dict[str, Any]] = []
        for step in group.get("steps", []):
            reason = "drop"
            if step.get("operation") == "drop":
                stripped += 1
                excluded.setdefault(reason, []).append(step.get("path", ""))
                continue
            matched_obj = _step_matches_ignored(step, ignore_patterns)
            if matched_obj is not None:
                stripped += 1
                excluded.setdefault(matched_obj, []).append(step.get("path", ""))
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
    return new_plan, stripped, excluded


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, help="Input pgschema plan JSON")
    parser.add_argument("--output", required=True, help="Output filtered plan JSON")
    parser.add_argument(
        "--ignore-objects",
        type=lambda s: [x.strip() for x in s.split(",") if x.strip()],
        default=[],
        metavar="OBJ1,OBJ2,...",
        help=(
            "Comma-separated list of object names to strip from the plan. "
            "Every step whose path contains an object name (or its default "
            "<obj>_id_seq sequence) as a full path component is removed."
        ),
    )
    parser.add_argument(
        "--ignore-table-triggers",
        action="append",
        default=[],
        metavar="TABLE",
        help=(
            "Legacy alias for --ignore-objects. Strip every step that refers "
            "to TABLE or its default <table>_id_seq sequence (may be given "
            "multiple times)"
        ),
    )
    parser.add_argument(
        "--log-exclusions",
        action="store_true",
        help=(
            "Log each auto-excluded object and the paths stripped because of "
            "it to stderr"
        ),
    )
    args = parser.parse_args(argv)

    # Combine --ignore-objects (comma-separated) and legacy --ignore-table-triggers.
    ignored_objects: list[str] = list(args.ignore_objects)
    for item in args.ignore_table_triggers:
        ignored_objects.append(item)

    try:
        plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in plan file: {exc}", file=sys.stderr)
        return 2
    except FileNotFoundError:
        print(f"ERROR: plan file not found: {args.plan}", file=sys.stderr)
        return 2

    try:
        new_plan, stripped, excluded = strip_destructive(plan, ignored_objects)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    Path(args.output).write_text(
        json.dumps(new_plan, indent=2) + "\n", encoding="utf-8"
    )

    if args.log_exclusions:
        for obj, paths in excluded.items():
            if obj == "drop":
                print(
                    f"EXCLUDED: {len(paths)} destructive DROP step(s) stripped",
                    file=sys.stderr,
                )
            else:
                print(
                    f"EXCLUDED: object '{obj}' shadows schema.sql table on peer; "
                    f"stripped {len(paths)} step(s): {', '.join(paths[:5])}"
                    f"{' ...' if len(paths) > 5 else ''}",
                    file=sys.stderr,
                )

    print(stripped, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
