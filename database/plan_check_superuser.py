#!/usr/bin/env python3
"""Inspect a pgschema plan and report steps that require a PostgreSQL superuser.

Reads a pgschema plan JSON and checks every step for SQL patterns that can
only run as a PostgreSQL superuser (CREATE EXTENSION, FDW server/user mapping,
CREATE EVENT TRIGGER, SECURITY DEFINER functions, etc.).

When database connection details are supplied, it also resolves each step that
targets an existing object in the catalog (as DB_USER) and flags any object
not owned by DB_USER.  Unparseable or unresolvable references are treated as
superuser-required.

Exit code:
  0 with no output if the plan contains no superuser-only steps.
  1 and one stderr line per flagged step otherwise.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any

import psycopg2

SUPERUSER_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bCREATE\s+EXTENSION\b", re.IGNORECASE), "CREATE EXTENSION"),
    (re.compile(r"\bCREATE\s+SERVER\b", re.IGNORECASE), "CREATE SERVER (FDW)"),
    (re.compile(r"\bCREATE\s+USER\s+MAPPING\b", re.IGNORECASE), "CREATE USER MAPPING (FDW)"),
    (re.compile(r"\bCREATE\s+EVENT\s+TRIGGER\b", re.IGNORECASE), "CREATE EVENT TRIGGER"),
    (re.compile(r"\bSECURITY\s+DEFINER\b", re.IGNORECASE), "SECURITY DEFINER function"),
]

# Map a step type to the catalog category used to resolve ownership.
_TYPE_CATEGORY: dict[str, tuple[str, tuple[str, ...]]] = {
    "table": ("relation", ("r", "p")),
    "table.comment": ("relation", ("r", "p")),
    "table.column": ("relation", ("r", "p")),
    "table.column.comment": ("relation", ("r", "p")),
    "table.index": ("relation", ("i",)),
    "table.constraint": ("relation", ("r", "p")),
    "table.trigger": ("trigger", ()),
    "view": ("relation", ("v", "m")),
    "function": ("function", ()),
    "type": ("type", ()),
    "trigger": ("trigger", ()),
    "event_trigger": ("event_trigger", ()),
    "server": ("server", ()),
    "user_mapping": ("user_mapping", ()),
    "extension": ("extension", ()),
    "namespace": ("namespace", ()),
}


class _CatalogResolver:
    """Resolve catalog owners via psycopg2."""

    def __init__(self, host: str, port: str, dbname: str, user: str) -> None:
        self.host = host
        self.port = port
        self.dbname = dbname
        self.user = user

    def _connect(self) -> Any:
        dsn = f"host={self.host} port={self.port} dbname={self.dbname} user={self.user}"
        password = os.environ.get("PGPASSWORD", "")
        if password:
            dsn += f" password={password}"
        return psycopg2.connect(dsn)

    def owners(self, schema: str | None, name: str, category: str, relkinds: tuple[str, ...]) -> list[str]:
        query: str
        params: list[Any]
        if category == "relation":
            query = (
                "SELECT pg_get_userbyid(c.relowner) AS owner "
                "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
                "WHERE n.nspname = %s AND c.relname = %s AND c.relkind = ANY(%s)"
            )
            params = [schema, name, list(relkinds)]
        elif category == "function":
            query = (
                "SELECT pg_get_userbyid(p.proowner) AS owner "
                "FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                "WHERE n.nspname = %s AND p.proname = %s"
            )
            params = [schema, name]
        elif category == "type":
            query = (
                "SELECT pg_get_userbyid(t.typowner) AS owner "
                "FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace "
                "WHERE n.nspname = %s AND t.typname = %s"
            )
            params = [schema, name]
        elif category == "trigger":
            query = (
                "SELECT pg_get_userbyid(c.relowner) AS owner "
                "FROM pg_trigger tg JOIN pg_class c ON c.oid = tg.tgrelid "
                "JOIN pg_namespace n ON n.oid = c.relnamespace "
                "WHERE n.nspname = %s AND tg.tgname = %s"
            )
            params = [schema, name]
        elif category == "event_trigger":
            query = "SELECT pg_get_userbyid(evtowner) AS owner FROM pg_event_trigger WHERE evtname = %s"
            params = [name]
        elif category == "server":
            query = "SELECT pg_get_userbyid(srvowner) AS owner FROM pg_foreign_server WHERE srvname = %s"
            params = [name]
        elif category == "user_mapping":
            # User mappings are tied to the server owner; superuser required.
            query = "SELECT pg_get_userbyid(s.srvowner) AS owner FROM pg_user_mapping um JOIN pg_foreign_server s ON s.oid = um.umserver WHERE s.srvname = %s"
            params = [name]
        elif category == "extension":
            query = "SELECT pg_get_userbyid(extowner) AS owner FROM pg_extension WHERE extname = %s"
            params = [name]
        elif category == "namespace":
            query = "SELECT pg_get_userbyid(nspowner) AS owner FROM pg_namespace WHERE nspname = %s"
            params = [name]
        else:
            return []
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                return [row[0] for row in cur.fetchall()]


class _StubResolver:
    """In-memory catalog stub for tests."""

    def __init__(self, items: list[dict[str, Any]]) -> None:
        self.items = items

    def owners(self, schema: str | None, name: str, category: str, relkinds: tuple[str, ...]) -> list[str]:
        result: list[str] = []
        for item in self.items:
            if item.get("name") != name:
                continue
            if schema is not None and item.get("schema") != schema:
                continue
            item_kind = item.get("kind", "")
            if category == "relation":
                kind_map = {"table": "r", "view": "v", "materialized_view": "m", "index": "i", "sequence": "S", "foreign_table": "f"}
                if kind_map.get(item_kind) not in relkinds:
                    continue
            elif item_kind != category:
                continue
            result.append(item["owner"])
        return result


def _step_requires_superuser(step: dict[str, Any]) -> str | None:
    """Return a human-readable reason if the step requires superuser, else None."""
    if step.get("type") == "extension":
        return "CREATE EXTENSION"
    sql = step.get("sql", "")
    for pattern, reason in SUPERUSER_PATTERNS:
        if pattern.search(sql):
            return reason
    return None


def _is_create_only(step: dict[str, Any]) -> bool:
    """True if the step creates a new object and cannot replace an existing one."""
    sql = step.get("sql", "")
    if re.search(r"\bCREATE\s+OR\s+REPLACE\b", sql, re.IGNORECASE):
        return False
    if step.get("operation") == "create":
        return True
    return re.search(r"\bCREATE\b", sql, re.IGNORECASE) is not None and \
        re.search(r"\bALTER\b|\bDROP\b|\bCOMMENT\b|\bGRANT\b|\bREVOKE\b", sql, re.IGNORECASE) is None


def _resolve_owners(step: dict[str, Any], resolver: Any) -> list[str] | None:
    """Return owners for the object targeted by the step, or None if unresolvable."""
    path = step.get("path", "")
    stype = step.get("type", "")

    category, relkinds = _TYPE_CATEGORY.get(stype, (None, ()))
    if category is None:
        return None

    parts = path.split(".")
    if category == "relation" and stype == "table.index" and len(parts) == 3:
        schema, _table, name = parts
    elif category == "relation" and len(parts) >= 3 and stype.startswith("table."):
        schema, name = parts[0], parts[1]
    elif category == "trigger" and len(parts) == 3:
        schema, _table, name = parts
    elif len(parts) == 2:
        schema, name = parts
    elif category in ("event_trigger", "server", "user_mapping", "extension") and len(parts) >= 1:
        schema, name = None, parts[-1]
    else:
        return None

    # Some plan paths include a schema prefix for non-schema-qualified objects;
    # event triggers and servers have no schema, so drop it.
    if category in ("event_trigger", "server", "user_mapping", "extension"):
        schema = None
        name = parts[-1]

    try:
        return resolver.owners(schema, name, category, relkinds)
    except psycopg2.Error:
        return None


def _check_step(step: dict[str, Any], db_user: str, resolver: Any) -> tuple[str, str | None] | None:
    """Return (reason, owner) if the step should halt, else None."""
    stype = step.get("type", "")
    path = step.get("path", "")
    if stype == "privilege" or path.startswith("privileges."):
        return None

    regex_reason = _step_requires_superuser(step)
    if regex_reason:
        return regex_reason, None

    # Without a resolver we can only perform the static regex checks.
    if resolver is None:
        return None

    if _is_create_only(step):
        return None

    owners = _resolve_owners(step, resolver)
    if owners is None:
        return "unparseable or unresolvable object reference", None
    if not owners:
        # Target object does not yet exist; a CREATE-only step would have
        # returned above, so an ALTER/DROP/GRANT/COMMENT on a missing object is
        # unsafe to attempt as DB_USER.
        return "target object does not exist", None

    bad_owners = [o for o in owners if o != db_user]
    if bad_owners:
        return f"owned by {bad_owners[0]}", bad_owners[0]
    return None


def check_plan(plan_path: str, db_user: str | None, resolver: Any | None) -> list[tuple[str, str, str, str | None]]:
    """Return a list of (path, reason, sql_snippet, owner) for flagged steps."""
    with open(plan_path, "r", encoding="utf-8") as fh:
        plan = json.load(fh)

    found: list[tuple[str, str, str, str | None]] = []
    for group in plan.get("groups") or []:
        for step in group.get("steps", []):
            result = _check_step(step, db_user or "", resolver)
            if result:
                reason, owner = result
                path = step.get("path", "")
                sql = step.get("sql", "")[:120].replace("\n", " ")
                found.append((path, reason, sql, owner))
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, help="Input pgschema plan JSON")
    parser.add_argument("--host", default=os.environ.get("PGHOST", "/var/run/postgresql"), help="PostgreSQL host")
    parser.add_argument("--port", default=os.environ.get("PGPORT", "5432"), help="PostgreSQL port")
    parser.add_argument("--dbname", default=os.environ.get("PGDATABASE"), help="Database name")
    parser.add_argument("--db-user", default=os.environ.get("PGUSER"), help="Agent DB role")
    parser.add_argument("--catalog-stub", help="JSON catalog stub for testing (disables live DB)")
    args = parser.parse_args(argv)

    resolver: Any | None = None
    if args.catalog_stub:
        with open(args.catalog_stub, "r", encoding="utf-8") as fh:
            resolver = _StubResolver(json.load(fh))
    elif args.dbname and args.db_user:
        resolver = _CatalogResolver(args.host, args.port, args.dbname, args.db_user)

    try:
        found = check_plan(args.plan, args.db_user, resolver)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"Failed to read plan: {exc}", file=sys.stderr)
        return 2

    if not found:
        return 0

    print("The following schema steps require a PostgreSQL superuser or target objects not owned by DB_USER:", file=sys.stderr)
    for path, reason, sql, owner in found:
        suffix = f" (owner={owner})" if owner else ""
        print(f"  [{reason}]{suffix} {path}: {sql}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
