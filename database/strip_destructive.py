#!/usr/bin/env python3
"""Strip destructive operations from a pgschema plan JSON.

Removes DROP steps (#498).  When an agent role is supplied it also removes
ALTER DEFAULT PRIVILEGES REVOKEs, ADP FOR ROLE <other>, and any
DROP/CREATE/REPLACE/COMMENT/GRANT step targeting an existing object not owned
by DB_USER (#765).

* Top-level metadata fields are preserved byte-for-byte.
* ``--ignore-objects`` (legacy ``--ignore-table-triggers``) strips every step
  that refers to a named table/sequence, closing the peer-FDW bootstrap-
  context gap (#608 / #1231).
* A missing or ``null`` ``groups`` is normalized to an empty array.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

SUPPORTED_PLAN_VERSIONS = {"1.0.0"}

try:
    from plan_check_superuser import _CatalogResolver, _StubResolver
except Exception:  # pragma: no cover - defensive import fallback
    _CatalogResolver = None
    _StubResolver = None

# Broader relkind set than plan_check_superuser so that a CREATE TABLE on a
# peer-shadowed VIEW is still detected as non-owned.
_RELKIND_ANY_RELATION = ("r", "p", "v", "m", "S", "f", "i")

_NONOWNED_TYPE_CATEGORY: dict[str, tuple[str, tuple[str, ...]]] = {
    "table": ("relation", _RELKIND_ANY_RELATION),
    "table.comment": ("relation", _RELKIND_ANY_RELATION),
    "table.column": ("relation", _RELKIND_ANY_RELATION),
    "table.column.comment": ("relation", _RELKIND_ANY_RELATION),
    "table.index": ("relation", _RELKIND_ANY_RELATION),
    "table.constraint": ("relation", _RELKIND_ANY_RELATION),
    "table.trigger": ("trigger", ()),
    "view": ("relation", _RELKIND_ANY_RELATION),
    "function": ("function", ()),
    "type": ("type", ()),
    "trigger": ("trigger", ()),
    "event_trigger": ("event_trigger", ()),
    "server": ("server", ()),
    "user_mapping": ("user_mapping", ()),
    "extension": ("extension", ()),
    "namespace": ("namespace", ()),
}

_PRIV_KIND_MAP = {
    "TABLE": "relation",
    "SEQUENCE": "relation",
    "FUNCTION": "function",
    "TYPE": "type",
    "DOMAIN": "type",
}


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
    ``public.table.column``, ``privileges.TABLE.table_id_seq.role``, or
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


def _is_default_privilege_step_to_skip(step: dict[str, Any], db_user: str) -> bool:
    """Return True for ADP REVOKEs and ADP FOR ROLE <role != db_user>."""
    if step.get("type") != "default_privilege":
        return False
    sql = step.get("sql", "")
    if re.search(r"\bREVOKE\b", sql, re.IGNORECASE):
        return True
    match = re.search(r"\bFOR\s+ROLE\s+(\"?)([^\"\s]+)\1", sql, re.IGNORECASE)
    if match and match.group(2) != db_user:
        return True
    return False


def _resolve_step_owners(step: dict[str, Any], resolver: Any) -> list[str] | None:
    """Resolve owners of the catalog object targeted by a plan step."""
    stype = step.get("type", "")
    path = step.get("path", "")
    if (
        stype == "default_privilege"
        or path.startswith("default_privileges.")
        or path.startswith("privileges.")
    ):
        return None

    category, relkinds = _NONOWNED_TYPE_CATEGORY.get(stype, (None, ()))
    if category is None:
        return None

    parts = path.split(".")
    schema = "public"
    name: str | None = None

    if stype == "table.index" and len(parts) == 3:
        schema, _table, name = parts
    elif category == "relation" and stype.startswith("table.") and len(parts) >= 3:
        schema, name = parts[0], parts[1]
    elif category == "trigger" and len(parts) == 3:
        schema, _table, name = parts
    elif len(parts) == 2:
        schema, name = parts
    elif category in (
        "event_trigger",
        "server",
        "user_mapping",
        "extension",
        "namespace",
    ) and len(parts) >= 1:
        schema, name = None, parts[-1]
    else:
        return None

    if category in ("event_trigger", "server", "user_mapping", "extension", "namespace"):
        schema = None

    try:
        return resolver.owners(schema, name, category, relkinds)
    except Exception:
        return None


def _privilege_step_object(
    step: dict[str, Any],
) -> tuple[str | None, str | None, str | None]:
    """Extract (schema, name, category) for a plain privilege (GRANT/REVOKE) step."""
    path = step.get("path", "")
    if not path.startswith("privileges."):
        return None, None, None
    parts = path.split(".")
    if len(parts) < 4:
        return None, None, None
    kind = parts[1]
    name = ".".join(parts[2:-1])
    category = _PRIV_KIND_MAP.get(kind, "relation")
    return "public", name, category


def _step_targets_non_owned(
    step: dict[str, Any], db_user: str, resolver: Any
) -> str | None:
    """Return the non-DB_USER owner if step targets an existing non-owned object."""
    stype = step.get("type", "")
    if stype == "default_privilege":
        return None

    if stype == "privilege" or step.get("path", "").startswith("privileges."):
        schema, name, category = _privilege_step_object(step)
        if name is None:
            return None
        relkinds = _RELKIND_ANY_RELATION if category == "relation" else ()
        try:
            owners = resolver.owners(schema, name, category, relkinds)
        except Exception:
            return None
    else:
        owners = _resolve_step_owners(step, resolver)

    if owners is None:
        return None
    if not owners:
        # Target object does not exist yet; allow CREATE-only steps to proceed.
        return None
    bad_owners = [o for o in owners if o != db_user]
    if bad_owners:
        return bad_owners[0]
    return None


def strip_destructive(
    plan: dict[str, Any],
    ignored_objects: list[str] | None = None,
    db_user: str | None = None,
    resolver: Any | None = None,
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
            if db_user and _is_default_privilege_step_to_skip(step, db_user):
                stripped += 1
                excluded.setdefault("default_privileges", []).append(step.get("path", ""))
                continue

            if db_user and resolver is not None:
                non_owner = _step_targets_non_owned(step, db_user, resolver)
                if non_owner is not None:
                    stripped += 1
                    path = step.get("path", "")
                    excluded.setdefault(f"nonowned:{path}", []).append(
                        f"{path} (owner={non_owner})"
                    )
                    continue

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
    parser.add_argument(
        "--db-user",
        default=os.environ.get("PGUSER"),
        help=(
            "Agent DB role. When set, ALTER DEFAULT PRIVILEGES REVOKEs and "
            "steps targeting objects not owned by this role are also stripped."
        ),
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("PGHOST", "/var/run/postgresql"),
        help="PostgreSQL host",
    )
    parser.add_argument(
        "--port",
        default=os.environ.get("PGPORT", "5432"),
        help="PostgreSQL port",
    )
    parser.add_argument(
        "--dbname",
        default=os.environ.get("PGDATABASE"),
        help="Database name",
    )
    parser.add_argument(
        "--catalog-stub",
        help="JSON catalog stub for tests (disables live DB connection)",
    )
    args = parser.parse_args(argv)

    # Combine --ignore-objects (comma-separated) and legacy --ignore-table-triggers.
    ignored_objects: list[str] = list(args.ignore_objects)
    for item in args.ignore_table_triggers:
        ignored_objects.append(item)

    resolver: Any | None = None
    if args.db_user:
        if args.catalog_stub and _StubResolver is not None:
            with open(args.catalog_stub, "r", encoding="utf-8") as fh:
                resolver = _StubResolver(json.load(fh))
        elif args.dbname and _CatalogResolver is not None:
            resolver = _CatalogResolver(
                args.host,
                args.port,
                args.dbname,
                args.db_user,
            )

    try:
        plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid JSON in plan file: {exc}", file=sys.stderr)
        return 2
    except FileNotFoundError:
        print(f"ERROR: plan file not found: {args.plan}", file=sys.stderr)
        return 2

    try:
        new_plan, stripped, excluded = strip_destructive(
            plan, ignored_objects, args.db_user, resolver
        )
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
            elif obj == "default_privileges":
                print(
                    f"EXCLUDED: {len(paths)} ALTER DEFAULT PRIVILEGES step(s) stripped",
                    file=sys.stderr,
                )
            elif obj.startswith("nonowned:"):
                owner = paths[0].split("(owner=")[-1].rstrip(")") if paths else "?"
                print(
                    f"SKIPPED: {obj.split(':', 1)[1]} (owner={owner}): {len(paths)} step(s)",
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
