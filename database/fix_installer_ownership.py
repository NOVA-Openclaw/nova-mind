#!/usr/bin/env python3
"""Generate/apply per-object ownership fixes for nova-mind#666.

pgschema applies schema.sql as the configured PostgreSQL superuser
(typically ``postgres``).  New relations therefore end up owned by that
superuser.  ``REASSIGN OWNED BY postgres`` fails on every run because the
superuser owns system objects, so the installer must transfer ownership
object-by-object.

This helper derives the transfer list from the catalog, excluding the
peer/FDW bootstrap stack and SOUL-protection objects:

* all FOREIGN TABLEs in ``public``
* VIEWs that reference a foreign table
* any tables, sequences or indexes those views depend on
* SECURITY DEFINER functions
* event triggers and their functions
* relations/functions named ``soul_protect%`` / ``audit_soul_protect%``
  and anything they depend on
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
from typing import Dict, Iterable, List, Sequence, Set, Tuple

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


def _protected_oids(cur) -> Tuple[Set[int], Dict[int, str]]:
    """Return OIDs of SOUL-protection objects and a reason per OID."""
    cur.execute(
        """
        WITH RECURSIVE secdef_funcs AS (
            SELECT p.oid
              FROM pg_proc p
              JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND p.prosecdef
        ),
        evt_funcs AS (
            SELECT p.oid
              FROM pg_proc p
              JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND p.oid IN (SELECT evtfoid FROM pg_event_trigger)
        ),
        soul_rels AS (
            SELECT c.oid
              FROM pg_class c
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public'
               AND (c.relname LIKE 'soul_protect%'
                    OR c.relname LIKE 'audit_soul_protect%')
        ),
        seeds AS (
            SELECT oid, 'pg_proc'::regclass AS classid,
                   'SECURITY DEFINER function'::text AS reason
              FROM secdef_funcs
            UNION ALL
            SELECT oid, 'pg_proc'::regclass,
                   'event-trigger function'::text
              FROM evt_funcs
            UNION ALL
            SELECT oid, 'pg_class'::regclass,
                   'SOUL-protection named object'::text
              FROM soul_rels
        ),
        rec AS (
            SELECT * FROM seeds
            UNION
            SELECT d.refobjid, d.refclassid,
                   'dependency of SOUL-protection event trigger or SECURITY DEFINER function'::text
              FROM pg_depend d
              JOIN rec r ON r.oid = d.objid AND r.classid = d.classid
             WHERE d.deptype IN ('n', 'a', 'f')
               AND d.refclassid IN ('pg_class'::regclass, 'pg_proc'::regclass)
               AND (
                   (d.refclassid = 'pg_class'::regclass
                    AND EXISTS (SELECT 1 FROM pg_class cc
                                 JOIN pg_namespace nn ON nn.oid = cc.relnamespace
                                WHERE cc.oid = d.refobjid
                                  AND nn.nspname = 'public'))
                OR (d.refclassid = 'pg_proc'::regclass
                    AND EXISTS (SELECT 1 FROM pg_proc pp
                                 JOIN pg_namespace nn ON nn.oid = pp.pronamespace
                                WHERE pp.oid = d.refobjid
                                  AND nn.nspname = 'public'))
               )
        )
        SELECT oid, classid, reason FROM rec
        """
    )
    protected: Set[int] = set()
    reasons: Dict[int, str] = {}
    for oid, _classid, reason in cur.fetchall():
        protected.add(oid)
        if oid not in reasons or reason != 'dependency of SOUL-protection event trigger or SECURITY DEFINER function':
            reasons[oid] = reason
    return protected, reasons


def _check_target_role(cur, db_user: str) -> bool:
    cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (db_user,))
    return cur.fetchone() is not None


def _relations_to_transfer(
    cur,
    superuser: str,
    excluded_oids: Set[int],
    protected_oids: Set[int],
    reasons: Dict[int, str],
) -> Tuple[List[Tuple[str, str, str]], List[str]]:
    """Return ((schema, name, relkind), skip_log) owned by superuser, not excluded."""
    excluded_list = list(excluded_oids) if excluded_oids else [0]
    cur.execute(
        """
        SELECT c.oid, n.nspname, c.relname, c.relkind
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
    transfer: List[Tuple[str, str, str]] = []
    log: List[str] = []
    for oid, schema, name, kind in cur.fetchall():
        if kind == "f":
            log.append(f"skip relation {schema}.{name} (foreign table, FDW setup)")
        elif oid in excluded_oids:
            log.append(f"skip relation {schema}.{name} (FDW/shadowed exclusion)")
        elif oid in protected_oids:
            log.append(f"skip relation {schema}.{name} ({reasons[oid]})")
        else:
            transfer.append((schema, name, kind))
    return transfer, log


def _toast_names() -> Set[Tuple[str, str]]:
    # pg_toast objects live outside public, but guard against surprises.
    return set()


def _functions_to_transfer(
    cur,
    superuser: str,
    excluded_oids: Set[int],
    protected_oids: Set[int],
    reasons: Dict[int, str],
) -> Tuple[List[Tuple[str, str, str]], List[str]]:
    """Return ((schema, name, args), skip_log) for functions owned by superuser."""
    excluded_oid_list = list(excluded_oids) if excluded_oids else [0]
    excluded_or_protected = excluded_oids | protected_oids
    cur.execute(
        """
        SELECT p.oid, n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          JOIN pg_roles r ON r.oid = p.proowner
         WHERE n.nspname = 'public'
           AND r.rolname = %s
         ORDER BY n.nspname, p.proname
        """,
        (superuser,),
    )
    transfer: List[Tuple[str, str, str]] = []
    log: List[str] = []
    for oid, schema, name, args in cur.fetchall():
        if oid in protected_oids:
            log.append(f"skip function {schema}.{name} ({reasons[oid]})")
            continue
        cur.execute(
            "SELECT 1 FROM pg_depend WHERE objid = %s AND classid = 'pg_proc'::regclass AND deptype = 'e' LIMIT 1",
            (oid,),
        )
        if cur.fetchone():
            log.append(f"skip function {schema}.{name} (extension function)")
            continue
        cur.execute(
            "SELECT 1 FROM pg_trigger WHERE tgfoid = %s AND tgrelid = ANY(%s) LIMIT 1",
            (oid, list(excluded_or_protected) if excluded_or_protected else [0]),
        )
        if cur.fetchone():
            log.append(f"skip function {schema}.{name} (trigger on excluded/protected relation)")
            continue
        transfer.append((schema, name, args or ""))
    return transfer, log


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
    """Return (statements, log_lines)."""
    conn = _connect(dbname, connect_user)
    try:
        with conn.cursor() as cur:
            if not _check_target_role(cur, db_user):
                raise RuntimeError(
                    f"target role '{db_user}' does not exist in database '{dbname}'"
                )
            excluded_oids = _fdw_excluded_oids(cur)
            protected_oids, reasons = _protected_oids(cur)
            rels, rel_log = _relations_to_transfer(
                cur, superuser, excluded_oids, protected_oids, reasons
            )
            funcs, func_log = _functions_to_transfer(
                cur, superuser, excluded_oids, protected_oids, reasons
            )
    finally:
        conn.close()

    statements: List[str] = []
    for schema, name, kind in rels:
        statements.append(_alter_statement(schema, name, kind, "", db_user))

    for schema, name, args in funcs:
        statements.append(_function_alter_statement(schema, name, args, db_user))

    log: List[str] = []
    log.append(f"-- protected/FDW objects skipped: {len(rel_log) + len(func_log)}")
    log.extend(sorted(rel_log))
    log.extend(sorted(func_log))
    log.append(f"-- {len(statements)} ownership transfer statement(s)")
    return statements, log


def _plan_cmd(args) -> int:
    try:
        statements, log = _generate_sql(args.dbname, args.db_user, args.superuser, args.connect_user)
    except psycopg2.Error as exc:
        print(f"ERROR: cannot plan ownership transfer: {exc}", file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    for line in log:
        print(line, file=sys.stderr)
    for stmt in statements:
        print(stmt)
    return 0


def _apply_cmd(args) -> int:
    try:
        statements, log = _generate_sql(args.dbname, args.db_user, args.superuser, args.connect_user)
    except psycopg2.Error as exc:
        print(f"ERROR: cannot plan ownership transfer: {exc}", file=sys.stderr)
        return 1
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    for line in log:
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
