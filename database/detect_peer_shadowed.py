#!/usr/bin/env python3
"""Detect relations on a target database that shadow tables declared by schema.sql.

Federation peers expose some canonical tables as foreign tables or views (e.g.
``agent_bootstrap_context`` as a VIEW, ``ai_models`` as a FOREIGN TABLE).
schema.sql always declares these as ``CREATE TABLE``.  If pgschema is asked to
plan against the peer, it will try to ``DROP VIEW`` / ``CREATE TABLE`` and fail
with SQLSTATE 42809.

This helper reads the local ``schema.sql``, extracts every table name it
declares, then queries the target database for public relations with
``relkind IN ('f','v')`` whose name matches one of those tables.  The matched
names are the "shadowed" relations that the installer must leave untouched.

Output (stdout):
    One JSON object per line, each with keys:
    * ``name``  - relation name
    * "kind"   - ``'foreign table'`` or ``'view'``
    * "relkind" - ``'f'`` or ``'v'``
    * "reason" - human-readable explanation

Logging (stderr):
    Lists the detected shadowed objects and notes when none are found.

Exit codes:
    0 - success (empty result is still success)
    2 - bad arguments, missing schema file, or malformed query result
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SCHEMA_TABLE_RE = re.compile(
    r"^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z_][a-z0-9_]*)\s*\(",
    re.IGNORECASE | re.MULTILINE,
)


def _extract_schema_tables(schema_sql: str) -> list[str]:
    """Return sorted unique table names declared by schema.sql."""
    names = SCHEMA_TABLE_RE.findall(schema_sql)
    return sorted({n.lower() for n in names})


def _query_shadowed_tables(
    schema_tables: list[str],
    dsn: str,
) -> list[dict[str, Any]]:
    """Query target DB for public f/v relations matching schema.sql tables."""
    import psycopg2

    query = """
        SELECT c.relname AS name,
               c.relkind AS relkind,
               CASE c.relkind
                   WHEN 'f' THEN 'foreign table'
                   WHEN 'v' THEN 'view'
                   ELSE c.relkind::text
               END AS kind
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relkind IN ('f', 'v')
           AND c.relname = ANY(%s)
         ORDER BY c.relname;
    """
    with psycopg2.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (schema_tables,))
            rows = cur.fetchall()

    results: list[dict[str, Any]] = []
    for name, relkind, kind in rows:
        results.append(
            {
                "name": name,
                "relkind": relkind,
                "kind": kind,
                "reason": (
                    f"{name} is a {kind} on the target DB but schema.sql "
                    f"declares it as a TABLE; excluding from plan"
                ),
            }
        )
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--schema-file",
        required=True,
        help="Path to the schema.sql file whose CREATE TABLE names to match",
    )
    parser.add_argument(
        "--dsn",
        required=True,
        help="libpq connection string for the target database",
    )
    args = parser.parse_args(argv)

    schema_path = Path(args.schema_file)
    if not schema_path.is_file():
        print(f"ERROR: schema file not found: {args.schema_file}", file=sys.stderr)
        return 2

    schema_sql = schema_path.read_text(encoding="utf-8")
    schema_tables = _extract_schema_tables(schema_sql)

    if not schema_tables:
        print("ERROR: no CREATE TABLE statements found in schema.sql", file=sys.stderr)
        return 2

    try:
        shadowed = _query_shadowed_tables(schema_tables, args.dsn)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: failed to query target database: {exc}", file=sys.stderr)
        return 2

    if shadowed:
        print(
            f"Detected {len(shadowed)} peer-shadowed relation(s): "
            + ", ".join(f"{r['name']} ({r['kind']})" for r in shadowed),
            file=sys.stderr,
        )
    else:
        print(
            "No peer-shadowed relations detected (all schema.sql tables are "
            "real tables on the target DB).",
            file=sys.stderr,
        )

    for row in shadowed:
        print(json.dumps(row))

    return 0


if __name__ == "__main__":
    sys.exit(main())
