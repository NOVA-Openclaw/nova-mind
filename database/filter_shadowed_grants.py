#!/usr/bin/env python3
"""Filter GRANT/REVOKE lines that target peer-shadowed or owner-owned relations.

Reads SQL lines from stdin, prints lines that should be applied to stdout,
and reports skipped-statement counts per object to stderr.

A statement is skipped when any of its target objects (the object names after
``ON TABLE`` / ``ON SEQUENCE`` / ...) is either a peer-shadowed relation name
or its default ``<name>_id_seq`` sequence.  The privileges of peer-shadowed
relations are owned by the FDW setup on the peer (#520), so schema.sql's
GRANT/REVOKE lines must not be reconciled against the local database.

Additionally, REVOKE statements that would strip privileges from the target
relation's owner or from the target database's agent user (``DB_USER``) are
skipped (#590).  Ownership is derived from the catalog, not from role names.

When ``DB_USER`` is not a PostgreSQL superuser, GRANT/REVOKE statements that
target objects not owned by ``DB_USER`` are also skipped, because a non-owner
cannot grant privileges on those objects.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import Dict, Tuple

import psycopg2

GRANT_REVOKE_RE = re.compile(
    r"^\s*(GRANT|REVOKE)\b",
    re.IGNORECASE,
)

TARGET_RE = re.compile(
    r"\bON\s+"
    r"(TABLE|SEQUENCE|DOMAIN|FOREIGN\s+DATA\s+WRAPPER|FOREIGN\s+SERVER|"
    r"FUNCTION|LANGUAGE|LARGE\s+OBJECT|SCHEMA|TYPE)\s+"
    r"([^;]+?)(?=\s+(?:TO|FROM)\b|$)",
    re.IGNORECASE,
)

FROM_RE = re.compile(
    r"\bFROM\s+(.+?)(?:\s+(?:CASCADE|RESTRICT))?\s*;?\s*$",
    re.IGNORECASE,
)

_SPLIT_RE = re.compile(r"\s*,\s*")


def _normalize_identifier(ident: str) -> str:
    ident = ident.strip()
    if len(ident) >= 2 and ident[0] == ident[-1] == '"':
        # Strip double quotes and unescape doubled quotes.
        ident = ident[1:-1].replace('""', '"')
    return ident.lower()


def _split_qualified(ident: str) -> Tuple[str, str]:
    """Return (schema, name) for a possibly schema-qualified identifier."""
    ident = ident.strip()
    if not ident:
        return ("", "")
    depth = 0
    split_pos = -1
    for i, ch in enumerate(ident):
        if ch == '"':
            depth = 1 - depth
        elif ch == "." and depth == 0:
            split_pos = i
    if split_pos > 0:
        schema = _normalize_identifier(ident[:split_pos])
        name = _normalize_identifier(ident[split_pos + 1 :])
    else:
        schema = "public"
        name = _normalize_identifier(ident)
    return (schema, name)


def _target_objects(line: str) -> list[Tuple[str, str]]:
    """Return normalized (schema, name) tuples mentioned as GRANT/REVOKE targets."""
    objects: list[Tuple[str, str]] = []
    for match in TARGET_RE.finditer(line):
        raw = match.group(2)
        for part in _SPLIT_RE.split(raw):
            schema, name = _split_qualified(part)
            if name:
                objects.append((schema, name))
    return objects


def _target_roles(line: str) -> list[str]:
    """Return normalized role names in the FROM clause of a REVOKE statement."""
    match = FROM_RE.search(line)
    if not match:
        return []
    roles: list[str] = []
    for part in _SPLIT_RE.split(match.group(1)):
        role = _normalize_identifier(part)
        if role:
            roles.append(role)
    return roles


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


def _load_owner_map(dbname: str) -> Dict[Tuple[str, str], str]:
    """Query the catalog for relation and function owners in the target database."""
    conn = psycopg2.connect(_dsn(dbname))
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT n.nspname, c.relname, r.rolname "
                "FROM pg_class c "
                "JOIN pg_namespace n ON n.oid = c.relnamespace "
                "JOIN pg_roles r ON r.oid = c.relowner "
                "WHERE c.relkind IN ('r','v','m','S','f','p') "
                "  AND n.nspname NOT IN ('pg_catalog','information_schema')"
            )
            owners = {
                (_normalize_identifier(row[0]), _normalize_identifier(row[1])): _normalize_identifier(row[2])
                for row in cur.fetchall()
            }
            # Function grants are rare in schema.sql but must be covered when
            # present.  The catalog stores argument types separately, so build
            # a name that matches the FUNCTION target text (e.g. func()).
            cur.execute(
                "SELECT n.nspname, p.proname || '(' || "
                "COALESCE(pg_get_function_identity_arguments(p.oid), '') || ')', r.rolname "
                "FROM pg_proc p "
                "JOIN pg_namespace n ON n.oid = p.pronamespace "
                "JOIN pg_roles r ON r.oid = p.proowner "
                "WHERE n.nspname NOT IN ('pg_catalog','information_schema')"
            )
            for row in cur.fetchall():
                owners[(_normalize_identifier(row[0]), _normalize_identifier(row[1]))] = _normalize_identifier(row[2])
            return owners
    finally:
        conn.close()


def _is_superuser(dbname: str, db_user: str) -> bool:
    """Return True if db_user is a PostgreSQL superuser in dbname."""
    if not db_user:
        return False
    conn = psycopg2.connect(_dsn(dbname))
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT rolsuper FROM pg_roles WHERE rolname = %s", (db_user,))
            row = cur.fetchone()
            return bool(row and row[0])
    finally:
        conn.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--shadowed-names",
        default="",
        metavar="NAME1,NAME2,...",
        help="Comma-separated peer-shadowed relation names (default: empty)",
    )
    parser.add_argument(
        "--dbname",
        default=os.environ.get("PGDATABASE", ""),
        help="Target database name (default: $PGDATABASE)",
    )
    parser.add_argument(
        "--db-user",
        dest="db_user",
        default=os.environ.get("PGUSER", ""),
        help="Target database agent user (default: $PGUSER)",
    )
    args = parser.parse_args(argv)

    shadowed = {n.strip().lower() for n in args.shadowed_names.split(",") if n.strip()}
    shadowed_seqs = {f"{n}_id_seq" for n in shadowed}
    db_user = args.db_user.lower()

    owner_map: Dict[Tuple[str, str], str] = {}
    is_db_super = False
    if db_user and args.dbname:
        try:
            is_db_super = _is_superuser(args.dbname, db_user)
            owner_map = _load_owner_map(args.dbname)
        except psycopg2.Error as exc:
            print(f"ERROR: cannot load relation owners: {exc}", file=sys.stderr)
            return 1

    skipped: dict[str, int] = {}
    kept = 0

    for line in sys.stdin:
        line = line.rstrip("\n")
        if not GRANT_REVOKE_RE.match(line):
            print(line)
            continue

        objects = _target_objects(line)
        skip_name: str | None = None
        for obj in objects:
            # shadowed names/sequences are unqualified; compare the relation name.
            if obj[1] in shadowed or obj[1] in shadowed_seqs:
                skip_name = obj[1]
                break

        if skip_name is None and line.lstrip().upper().startswith("REVOKE"):
            from_roles = _target_roles(line)
            if db_user in from_roles:
                skip_name = f"DB_USER '{db_user}'"
            else:
                for obj in objects:
                    owner = owner_map.get(obj)
                    if owner and owner in from_roles:
                        skip_name = f"owner '{owner}'"
                        break

        # Non-superusers cannot grant/revoke privileges on objects they do
        # not own, so skip those statements entirely.
        if skip_name is None and not is_db_super and objects:
            for obj in objects:
                owner = owner_map.get(obj)
                if owner and owner != db_user:
                    schema, name = obj
                    skip_name = f"non-owned object '{schema}.{name}' (owner '{owner}')"
                    break

        if skip_name is not None:
            skipped[skip_name] = skipped.get(skip_name, 0) + 1
        else:
            print(line)
            kept += 1

    for name in sorted(skipped):
        count = skipped[name]
        if name.startswith("owner ") or name.startswith("DB_USER "):
            print(
                f"SKIPPED: {count} owner/DB_USER REVOKE statement(s) ({name})",
                file=sys.stderr,
            )
        elif name.startswith("non-owned object "):
            print(
                f"SKIPPED: {count} grant/revoke statement(s) for {name}",
                file=sys.stderr,
            )
        else:
            print(
                f"SKIPPED: {count} grant/revoke statement(s) for peer-shadowed "
                f"object '{name}'",
                file=sys.stderr,
            )

    print(f"Kept {kept} grant/revoke statement(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
