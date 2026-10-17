#!/usr/bin/env python3
"""Post-reconciliation privilege gate for the target database agent user.

Captures a snapshot of table/sequence privileges held by DB_USER on relations
it owns, then verifies that no privilege was lost after grant reconciliation.
Any loss prints the (relation, privilege) list and exits non-zero (#590).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Dict, List, Tuple

import psycopg2

_PRIVS_BY_KIND = {
    "r": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "v": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "m": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "f": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "p": [("SELECT", "has_table"), ("INSERT", "has_table"), ("UPDATE", "has_table"), ("DELETE", "has_table")],
    "S": [("USAGE", "has_sequence"), ("SELECT", "has_sequence"), ("UPDATE", "has_sequence")],
}


def _connect(dbname: str):
    dsn = f"host=/var/run/postgresql dbname={dbname}"
    return psycopg2.connect(dsn)


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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dbname", default=os.environ.get("PGDATABASE", ""), help="Target database")
    parser.add_argument("--db-user", dest="db_user", default=os.environ.get("PGUSER", ""), help="Agent user")
    sub = parser.add_subparsers(dest="action", required=True)
    snap = sub.add_parser("snapshot", help="Print JSON privilege snapshot")
    snap.set_defaults(func=_snapshot_cmd)
    verify = sub.add_parser("verify", help="Verify snapshot and report losses")
    verify.add_argument("snapshot", help="Path to JSON snapshot")
    verify.set_defaults(func=_verify_cmd)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
