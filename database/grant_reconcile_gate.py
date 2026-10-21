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


def _dsn(dbname: str, superuser: bool = False) -> str:
    """Build a libpq DSN from PG* env vars (#743).

    Defaults to the agent's own DB role.  When ``superuser`` is True, uses
    PG_SUPERUSER/PG_SUPERUSER_PASSWORD/PG_SUPERUSER_HOST instead.
    """
    if superuser:
        host = os.environ.get("PG_SUPERUSER_HOST", "/var/run/postgresql")
        port = os.environ.get("PGPORT", "5432")
        user = os.environ.get("PG_SUPERUSER", "")
        password = os.environ.get("PG_SUPERUSER_PASSWORD", "")
    else:
        host = os.environ.get("PGHOST", "/var/run/postgresql")
        port = os.environ.get("PGPORT", "5432")
        user = os.environ.get("PGUSER", "")
        password = os.environ.get("PGPASSWORD", "")
    parts = [f"host={host}", f"port={port}", f"dbname={dbname}"]
    if user:
        parts.append(f"user={user}")
    if password:
        parts.append(f"password={password}")
    return " ".join(parts)


def _connect(dbname: str, superuser: bool = False):
    return psycopg2.connect(_dsn(dbname, superuser=superuser))


from fix_installer_ownership import _protected_oids, _check_target_role as _role_exists


# Stable key for a protected object in the owner snapshot.
_OwnerKey = Tuple[str, str]  # (kind, name)


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
    protected_oids: Set[int],
) -> List[Tuple[str, str, str]]:
    """Return (schema, name, relkind) for relations DB_USER must be able to use.

    This includes every relation DB_USER owns and every non-excluded relation
    still owned by the superuser (the run-created fallback set).  Protected
    SOUL objects are excluded because they must remain superuser-owned.
    """
    skip = excluded_oids | protected_oids
    skip_list = list(skip) if skip else [0]
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
        (db_user, superuser, skip_list),
    )
    return [(row[0], row[1], row[2]) for row in cur.fetchall()]


def _protected_owner_snapshot(cur, superuser: str) -> Dict[_OwnerKey, str]:
    """Return a snapshot mapping of protected object -> owner rolname."""
    snapshot: Dict[_OwnerKey, str] = {}
    protected, _ = _protected_oids(cur, _fdw_excluded_oids(cur))
    if not protected:
        return snapshot
    cur.execute(
        """
        SELECT 'relation', n.nspname || '.' || c.relname, r.rolname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_roles r ON r.oid = c.relowner
         WHERE c.oid = ANY(%s)
        UNION ALL
        SELECT 'function', n.nspname || '.' || p.proname, r.rolname
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          JOIN pg_roles r ON r.oid = p.proowner
         WHERE p.oid = ANY(%s)
        UNION ALL
        SELECT 'event trigger', evtname, r.rolname
          FROM pg_event_trigger e
          JOIN pg_roles r ON r.oid = e.evtowner
         WHERE e.evtfoid = ANY(%s)
        ORDER BY 1, 2
        """,
        (list(protected), list(protected), list(protected)),
    )
    for kind, name, owner in cur.fetchall():
        snapshot[(kind, name)] = owner
    return snapshot


def _check_protected_ownership(
    cur,
    superuser: str,
    snapshot: Dict[_OwnerKey, str],
) -> Tuple[List[Tuple[_OwnerKey, str, str]], List[_OwnerKey]]:
    """Return (changed, drift) relative to a pre-transfer owner snapshot.

    ``changed`` lists objects whose owner changed during the run.
    ``drift`` lists objects that were already not owned by the superuser
    before the run and still aren't (pre-existing drift, reported as a
    warning rather than a failure).
    """
    current = _protected_owner_snapshot(cur, superuser)
    changed: List[Tuple[_OwnerKey, str, str]] = []
    drift: List[_OwnerKey] = []
    for key, before in snapshot.items():
        after = current.get(key)
        if after is None:
            # Object no longer exists; treat as a change to be safe.
            changed.append((key, before, "<dropped>"))
        elif after != before:
            changed.append((key, before, after))
        elif after != superuser:
            drift.append(key)
    return changed, drift


def _check_privileges(cur, db_user: str, superuser: str) -> List[Tuple[str, str, str]]:
    """Return list of (schema, name, privilege) that DB_USER is missing."""
    if not _role_exists(cur, db_user):
        return [("", f"role '{db_user}' does not exist", "")]
    excluded_oids = _fdw_excluded_oids(cur)
    protected_oids, _ = _protected_oids(cur, excluded_oids)
    relations = _relations_to_check(cur, db_user, superuser, excluded_oids, protected_oids)
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


def _protected_snapshot_cmd(args) -> int:
    conn = _connect(args.dbname)
    try:
        with conn.cursor() as cur:
            snapshot = _protected_owner_snapshot(cur, args.superuser)
    finally:
        conn.close()
    json.dump({f"{kind}:{name}": owner for (kind, name), owner in snapshot.items()}, sys.stdout, sort_keys=True, indent=2)
    print()
    return 0


def _check_cmd(args) -> int:
    protected_snapshot: Dict[_OwnerKey, str] = {}
    if args.protected_snapshot:
        with open(args.protected_snapshot, "r", encoding="utf-8") as fh:
            raw: Dict[str, str] = json.load(fh)
        for key, owner in raw.items():
            kind, name = key.split(":", 1)
            protected_snapshot[(kind, name)] = owner
    if not protected_snapshot:
        print(
            "ERROR: --protected-snapshot is required for the protected-owner gate",
            file=sys.stderr,
        )
        return 1
    conn = _connect(args.dbname)
    try:
        with conn.cursor() as cur:
            missing = _check_privileges(cur, args.db_user, args.superuser)
            changed, drift = _check_protected_ownership(
                cur, args.superuser, protected_snapshot
            )
    finally:
        conn.close()
    failed = False
    if missing:
        failed = True
        print(
            f"ERROR: DB_USER '{args.db_user}' is missing required privileges:",
            file=sys.stderr,
        )
        for schema, name, priv in missing:
            print(f'  "{schema}"."{name}" {priv}', file=sys.stderr)
    if changed:
        failed = True
        print(
            "ERROR: protected object owner(s) changed during the run:",
            file=sys.stderr,
        )
        for (kind, name), before, after in changed:
            print(f"  [{kind}] {name}: {before} -> {after}", file=sys.stderr)
    if drift:
        print(
            "WARNING: pre-existing protected-object ownership drift (not a failure):",
            file=sys.stderr,
        )
        for kind, name in drift:
            print(f"  [{kind}] {name}", file=sys.stderr)
    if failed:
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
    prot_snap = sub.add_parser("protected-snapshot", help="Print JSON protected-object owner snapshot")
    prot_snap.set_defaults(func=_protected_snapshot_cmd)
    check = sub.add_parser("check", help="Absolute check for required DB_USER privileges")
    check.add_argument("--protected-snapshot", dest="protected_snapshot", default=None, help="Path to protected-owner snapshot for relative ownership check")
    check.set_defaults(func=_check_cmd)
    args = parser.parse_args(argv)

    if not args.dbname or not args.db_user:
        print("ERROR: --dbname and --db-user are required", file=sys.stderr)
        return 2

    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
