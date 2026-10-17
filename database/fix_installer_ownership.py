#!/usr/bin/env python3
"""Generate/apply per-object ownership fixes for nova-mind#666.

pgschema applies schema.sql as the configured PostgreSQL superuser
(typically ``postgres``).  New relations therefore end up owned by that
superuser.  ``REASSIGN OWNED BY postgres`` fails on every run because the
superuser owns system objects, so the installer must transfer ownership
object-by-object.

This helper derives the transfer list from the catalog, excluding the
peer/FDW bootstrap stack:

* all FOREIGN TABLEs in ``public``
* VIEWs that reference a foreign table
* any tables, sequences or indexes those views depend on
* functions that are triggers on any excluded relation
* functions that belong to an extension

Output (``plan`` subcommand):
    ``ALTER ... OWNER TO "DB_USER";`` statements, one per line, suitable
    for feeding to ``psql`` as the superuser.

Output (``apply`` subcommand):
    Executes the same statements directly; reports counts on stderr.
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Iterable, List, Sequence, Set, Tuple

import psycopg2

EXCLUDED_SCHEMAS = {"pg_catalog", "information_schema"}


def _connect(dbname: str, user: str | None = None) -> psycopg2.extensions.connection:
    dsn = f"host=/var/run/postgresql dbname={dbname}"
    if user:
        dsn += f" user={user}"
    return psycopg2.connect(dsn)


def _quote_ident(ident: str) -> str:
    return '"' + ident.replace('"', '""') + '"'


def _fdw_excluded_oids(cur) -> Set[int]:
    """Return OIDs of the FDW/bootstrap stack that must not be retitled."""
    cur.execute(
        """
        WITH RECURSIVE fdw_tables AS (
            SELECT c.oid
              FROM pg_class c
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public'
               AND c.relkind = 'f'
        ),
        fdw_views AS (
            SELECT DISTINCT c.oid
              FROM pg_depend d
              JOIN pg_rewrite rw ON rw.oid = d.objid
              JOIN pg_class c ON c.oid = rw.ev_class
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE d.refobjid IN (SELECT oid FROM fdw_tables)
               AND d.classid = 'pg_rewrite'::regclass
               AND n.nspname = 'public'
        ),
        fdw_view_deps AS (
            SELECT DISTINCT d.refobjid AS oid
              FROM pg_depend d
              JOIN pg_rewrite rw ON rw.oid = d.objid
             WHERE rw.ev_class IN (SELECT oid FROM fdw_views)
               AND d.classid = 'pg_rewrite'::regclass
               AND d.refclassid = 'pg_class'::regclass
        ),
        fdw_excluded_all AS (
            SELECT oid FROM fdw_tables
            UNION
            SELECT oid FROM fdw_views
            UNION
            SELECT oid FROM fdw_view_deps
        ),
        fdw_seqs AS (
            SELECT d.objid AS oid
              FROM pg_depend d
             WHERE d.classid = 'pg_class'::regclass
               AND d.deptype = 'a'
               AND d.refobjid IN (SELECT oid FROM fdw_excluded_all)
        )
        SELECT oid FROM fdw_tables
        UNION
        SELECT oid FROM fdw_views
        UNION
        SELECT oid FROM fdw_view_deps
        UNION
        SELECT oid FROM fdw_seqs
        """
    )
    return {row[0] for row in cur.fetchall()}


def _relations_to_transfer(
    cur,
    superuser: str,
    excluded_oids: Set[int],
) -> List[Tuple[str, str, str]]:
    """Return (schema, name, relkind) tuples owned by superuser, not excluded."""
    excluded_list = list(excluded_oids) if excluded_oids else [0]
    cur.execute(
        """
        SELECT n.nspname, c.relname, c.relkind
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_roles r ON r.oid = c.relowner
         WHERE n.nspname = 'public'
           AND r.rolname = %s
           AND c.relkind IN ('r','v','m','S','f','p','i')
           AND c.oid <> ALL(%s)
           AND NOT (
               c.relkind = 'S'
               AND EXISTS (
                   SELECT 1 FROM pg_depend d
                    WHERE d.classid = 'pg_class'::regclass
                      AND d.objid = c.oid
                      AND d.refclassid = 'pg_class'::regclass
                      AND d.deptype = 'a'
               )
           )
         ORDER BY c.relkind, n.nspname, c.relname
        """,
        (superuser, excluded_list),
    )
    return [
        (schema, name, kind)
        for schema, name, kind in cur.fetchall()
        if kind != "f"  # foreign tables never transfer, even if detection missed them
    ]


def _toast_names() -> Set[Tuple[str, str]]:
    # pg_toast objects live outside public, but guard against surprises.
    return set()


def _functions_to_transfer(
    cur,
    superuser: str,
    excluded_oids: Set[int],
) -> List[Tuple[str, str, str]]:
    """Return (schema, name, args) for functions owned by superuser, not excluded."""
    excluded_oid_list = list(excluded_oids) if excluded_oids else [0]
    cur.execute(
        """
        SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          JOIN pg_roles r ON r.oid = p.proowner
         WHERE n.nspname = 'public'
           AND r.rolname = %s
           AND NOT EXISTS (
               SELECT 1 FROM pg_depend d
                WHERE d.objid = p.oid
                  AND d.classid = 'pg_proc'::regclass
                  AND d.deptype = 'e'
           )
           AND NOT EXISTS (
               SELECT 1 FROM pg_trigger t
                WHERE t.tgfoid = p.oid
                  AND t.tgrelid = ANY(%s)
           )
         ORDER BY n.nspname, p.proname
        """,
        (superuser, excluded_oid_list),
    )
    return [(row[0], row[1], row[2] or "") for row in cur.fetchall()]


def _alter_statement(
    schema: str,
    name: str,
    kind: str,
    args: str,
    new_owner: str,
) -> str:
    qschema = _quote_ident(schema)
    qname = _quote_ident(name)
    qowner = _quote_ident(new_owner)
    if kind == "S":
        return f"ALTER SEQUENCE {qschema}.{qname} OWNER TO {qowner};"
    if kind == "i":
        return f"ALTER INDEX {qschema}.{qname} OWNER TO {qowner};"
    # r, v, m, f, p all use ALTER TABLE syntax.
    return f"ALTER TABLE {qschema}.{qname} OWNER TO {qowner};"


def _function_alter_statement(schema: str, name: str, args: str, new_owner: str) -> str:
    qschema = _quote_ident(schema)
    qname = _quote_ident(name)
    qowner = _quote_ident(new_owner)
    if args:
        return f"ALTER FUNCTION {qschema}.{qname}({args}) OWNER TO {qowner};"
    return f"ALTER FUNCTION {qschema}.{qname}() OWNER TO {qowner};"


def _generate_sql(
    dbname: str,
    db_user: str,
    superuser: str,
    connect_user: str | None = None,
) -> Tuple[List[str], List[str]]:
    """Return (statements, exclusion_log_lines)."""
    conn = _connect(dbname, connect_user)
    try:
        with conn.cursor() as cur:
            excluded_oids = _fdw_excluded_oids(cur)
            rels = _relations_to_transfer(cur, superuser, excluded_oids)
            funcs = _functions_to_transfer(cur, superuser, excluded_oids)
    finally:
        conn.close()

    statements: List[str] = []
    for schema, name, kind in rels:
        statements.append(_alter_statement(schema, name, kind, "", db_user))

    for schema, name, args in funcs:
        statements.append(_function_alter_statement(schema, name, args, db_user))

    excluded_log: List[str] = []
    if excluded_oids:
        conn2 = _connect(dbname, connect_user)
        try:
            with conn2.cursor() as cur:
                cur.execute(
                    "SELECT n.nspname, c.relname, c.relkind "
                    "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
                    "WHERE c.oid = ANY(%s) ORDER BY c.relname",
                    (list(excluded_oids),),
                )
                for schema, name, kind in cur.fetchall():
                    excluded_log.append(f"excluded {schema}.{name} ({kind})")
        finally:
            conn2.close()

    return statements, excluded_log


def _plan_cmd(args) -> int:
    statements, excluded_log = _generate_sql(args.dbname, args.db_user, args.superuser, args.connect_user)
    for line in excluded_log:
        print(line, file=sys.stderr)
    for stmt in statements:
        print(stmt)
    print(f"-- {len(statements)} ownership transfer statement(s)", file=sys.stderr)
    return 0


def _apply_cmd(args) -> int:
    statements, excluded_log = _generate_sql(args.dbname, args.db_user, args.superuser, args.connect_user)
    for line in excluded_log:
        print(line, file=sys.stderr)
    if not statements:
        print("No ownership changes needed.", file=sys.stderr)
        return 0

    conn = _connect(args.dbname, args.connect_user or args.superuser)
    try:
        with conn.cursor() as cur:
            for stmt in statements:
                cur.execute(stmt)
        conn.commit()
    except psycopg2.Error as exc:
        print(f"ERROR: ownership transfer failed: {exc}", file=sys.stderr)
        conn.rollback()
        return 1
    finally:
        conn.close()

    print(f"Transferred ownership for {len(statements)} object(s).", file=sys.stderr)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dbname", default=os.environ.get("PGDATABASE", ""), help="Target database")
    parser.add_argument("--db-user", dest="db_user", default=os.environ.get("PGUSER", ""), help="Agent user to own objects")
    parser.add_argument("--superuser", default="postgres", help="Superuser role that currently owns the objects")
    parser.add_argument("--connect-user", dest="connect_user", default=None, help="Connect as this user for catalog reads (default: db-user)")
    sub = parser.add_subparsers(dest="action", required=True)
    plan = sub.add_parser("plan", help="Print ALTER OWNER statements")
    plan.set_defaults(func=_plan_cmd)
    apply = sub.add_parser("apply", help="Execute ALTER OWNER statements")
    apply.set_defaults(func=_apply_cmd)
    args = parser.parse_args(argv)

    if not args.dbname or not args.db_user:
        print("ERROR: --dbname and --db-user are required", file=sys.stderr)
        return 2

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
