#!/usr/bin/env python3
"""Post-reconciliation privilege gate for the target database agent user.

Captures a snapshot of required table/sequence privileges held by DB_USER on
relations it owns, verifies that no privilege was lost after grant
reconciliation (#590), and performs an absolute "after" check that DB_USER has
the required privileges on every relation it owns plus every relation the
installer run created (i.e., objects still owned by the superuser that are not
part of the peer/FDW exclusion set) (#666 / #1231).

Required privileges by relkind:
  r, p  -> SELECT, INSERT, UPDATE, DELETE
  v, m, f -> SELECT
  S     -> USAGE, SELECT, UPDATE

Any missing privilege prints the (relation, privilege) list and exits non-zero.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Dict, List, Set, Tuple

import psycopg2

# Required privileges for the gate.  Keys match pg_class.relkind.
_PRIVS_BY_KIND: Dict[str, List[Tuple[str, str]]] = {
    "r": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "p": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "v": [("SELECT", "has_table")],
    "m": [("SELECT", "has_table")],
    "f": [("SELECT", "has_table")],
    "S": [("USAGE", "has_sequence"), ("SELECT", "has_sequence"), ("UPDATE", "has_sequence")],
}


def _connect(dbname: str):
    dsn = f"host=/var/run/postgresql dbname={dbname}"
    return psycopg2.connect(dsn)


def _fdw_excluded_oids(cur) -> Set[int]:
    """Return OIDs of the FDW bootstrap view stack that must not be gated.

    We exclude only foreign tables that back a local view (e.g.
    ``nova_bootstrap_context`` backing ``agent_bootstrap_context``) plus the
    view itself and its dependencies.  Standalone foreign tables (such as
    peer-imported ``ai_models``) remain in scope so the gate verifies the
    agent can read them.
    """
    cur.execute(
        """
        WITH RECURSIVE fdw_tables AS (
            -- Foreign tables referenced by a public view.
            SELECT DISTINCT d.refobjid AS oid
              FROM pg_depend d
              JOIN pg_rewrite rw ON rw.oid = d.objid
              JOIN pg_class c ON c.oid = rw.ev_class
              JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE d.classid = 'pg_rewrite'::regclass
               AND d.refclassid = 'pg_class'::regclass
               AND d.refobjid IN (
                   SELECT cc.oid FROM pg_class cc
                   JOIN pg_namespace nn ON nn.oid = cc.relnamespace
                   WHERE nn.nspname = 'public' AND cc.relkind = 'f'
               )
               AND n.nspname = 'public'
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
        fdw_auto_deps AS (
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
        SELECT oid FROM fdw_auto_deps
        """
    )
    return {row[0] for row in cur.fetchall()}


def _relations_to_check(
    cur,
    db_user: str,
    superuser: str,
    excluded_oids: Set[int],
) -> List[Tuple[str, str, str]]:
    """Return (schema, name, relkind) for relations DB_USER must be able to use.

    This includes every relation DB_USER owns and every non-excluded relation
    still owned by the superuser (the run-created fallback set).
    """
    excluded_list = list(excluded_oids) if excluded_oids else [0]
    cur.execute(
        """
        SELECT n.nspname, c.relname, c.relkind
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_roles r ON r.oid = c.relowner
         WHERE n.nspname = 'public'
           AND c.relkind IN ('r','v','m','S','f','p')
           AND (
               r.rolname = %s
               OR (r.rolname = %s AND NOT (c.oid = ANY(%s)))
           )
         ORDER BY n.nspname, c.relkind, c.relname
        """,
        (db_user, superuser, excluded_list),
    )
    return [(row[0], row[1], row[2]) for row in cur.fetchall()]


def _check_privileges(cur, db_user: str, superuser: str) -> List[Tuple[str, str, str]]:
    """Return list of (schema, name, privilege) that DB_USER is missing."""
    excluded_oids = _fdw_excluded_oids(cur)
    relations = _relations_to_check(cur, db_user, superuser, excluded_oids)
    missing: List[Tuple[str, str, str]] = []
    for schema, name, kind in relations:
        rel = f'"{schema}"."{name}"'
        for priv, func in _PRIVS_BY_KIND.get(kind, []):
            if func == "has_table":
                cur.execute("SELECT has_table_privilege(%s, %s, %s)", (db_user, rel, priv))
            else:
                cur.execute("SELECT has_sequence_privilege(%s, %s, %s)", (db_user, rel, priv))
            if not cur.fetchone()[0]:
                missing.append((schema, name, priv))
    return missing


def _snapshot(cur, db_user: str) -> Dict[str, Dict[str, bool]]:
    snapshot: Dict[str, Dict[str, bool]] = {}
    for schema, name, kind in _owned_relations(cur, db_user):
        rel = f'"{schema}"."{name}"'
        snapshot[rel] = {}
        for priv, func in _PRIVS_BY_KIND.get(kind, []):
            if func == "has_table":
                cur.execute("SELECT has_table_privilege(%s, %s, %s)", (db_user, rel, priv))
            else:
                cur.execute("SELECT has_sequence_privilege(%s, %s, %s)", (db_user, rel, priv))
            snapshot[rel][priv] = bool(cur.fetchone()[0])
    return snapshot


def _owned_relations(cur, db_user: str) -> List[Tuple[str, str, str]]:
    cur.execute(
        "SELECT n.nspname, c.relname, c.relkind "
        "FROM pg_class c "
        "JOIN pg_namespace n ON n.oid = c.relnamespace "
        "JOIN pg_roles r ON r.oid = c.relowner "
        "WHERE r.rolname = %s "
        "  AND c.relkind IN ('r','v','m','S','f','p') "
        "  AND n.nspname NOT IN ('pg_catalog','information_schema') "
        "ORDER BY n.nspname, c.relname",
        (db_user,),
    )
    return [(row[0], row[1], row[2]) for row in cur.fetchall()]


def _snapshot_cmd(args) -> int:
    conn = _connect(args.dbname)
    try:
        with conn.cursor() as cur:
            snapshot = _snapshot(cur, args.db_user)
    finally:
        conn.close()
    json.dump(snapshot, sys.stdout, sort_keys=True, indent=2)
    print()
    return 0


def _verify_cmd(args) -> int:
    with open(args.snapshot, "r", encoding="utf-8") as fh:
        before: Dict[str, Dict[str, bool]] = json.load(fh)
    conn = _connect(args.dbname)
    try:
        with conn.cursor() as cur:
            after = _snapshot(cur, args.db_user)
    finally:
        conn.close()
    lost: List[Tuple[str, str]] = []
    for rel, privs in sorted(before.items()):
        for priv, had in sorted(privs.items()):
            if had and not after.get(rel, {}).get(priv, False):
                lost.append((rel, priv))
    if lost:
        print("ERROR: DB_USER lost privileges after reconciliation:", file=sys.stderr)
        for rel, priv in lost:
            print(f"  {rel} {priv}", file=sys.stderr)
        return 1
    print(f"OK: DB_USER '{args.db_user}' retained all {len(before)} owned relation privileges", file=sys.stderr)
    return 0


def _check_cmd(args) -> int:
    conn = _connect(args.dbname)
    try:
        with conn.cursor() as cur:
            missing = _check_privileges(cur, args.db_user, args.superuser)
    finally:
        conn.close()
    if missing:
        print(
            f"ERROR: DB_USER '{args.db_user}' is missing required privileges:",
            file=sys.stderr,
        )
        for schema, name, priv in missing:
            print(f'  "{schema}"."{name}" {priv}', file=sys.stderr)
        return 1
    print(f"OK: DB_USER '{args.db_user}' has all required privileges", file=sys.stderr)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dbname", default=os.environ.get("PGDATABASE", ""), help="Target database")
    parser.add_argument("--db-user", dest="db_user", default=os.environ.get("PGUSER", ""), help="Agent user")
    parser.add_argument("--superuser", default="postgres", help="Superuser role that owns run-created objects")
    sub = parser.add_subparsers(dest="action", required=True)
    snap = sub.add_parser("snapshot", help="Print JSON privilege snapshot")
    snap.set_defaults(func=_snapshot_cmd)
    verify = sub.add_parser("verify", help="Verify snapshot and report losses")
    verify.add_argument("snapshot", help="Path to JSON snapshot")
    verify.set_defaults(func=_verify_cmd)
    check = sub.add_parser("check", help="Absolute check for required DB_USER privileges")
    check.set_defaults(func=_check_cmd)
    args = parser.parse_args(argv)

    if not args.dbname or not args.db_user:
        print("ERROR: --dbname and --db-user are required", file=sys.stderr)
        return 2

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
