#!/usr/bin/env python3
"""CI backstop for nova-mind#624: assert every object listed in
database/.schema-manifest.toml is present in database/schema.sql.

This is a static, repo-only check -- it does not connect to any database.
It exists as a second line of defense behind the listener-side veto in
cognition/scripts/pg-notify-listener.py (which is the PRIMARY safeguard,
enforced at sync time against the live DB); this script catches the case
where schema.sql was modified/committed through some path other than the
listener (e.g. a manual edit, a revert, a rebase) and a manifest object was
lost without the listener ever running.

Exit codes:
  0 - all manifest objects present (or no manifest / no entries -- nothing
      to check)
  1 - one or more manifest objects missing from schema.sql
  2 - usage/parse error (missing schema.sql, malformed manifest TOML, etc.)

Usage:
    python3 database/check_schema_manifest.py \
        [--manifest database/.schema-manifest.toml] \
        [--schema database/schema.sql]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    tomllib = None


def load_manifest(path):
    """Parse the manifest TOML. Returns {} if the file does not exist.

    Raises ValueError on malformed TOML (unlike the listener's fail-open
    loader, the CI backstop should fail LOUD on a malformed manifest --
    a manifest that silently fails to load would silently stop protecting
    every entry in it, defeating the backstop's purpose).
    """
    if not os.path.isfile(path):
        return {}
    if tomllib is None:
        raise RuntimeError(
            "tomllib unavailable (Python 3.11+ required) -- cannot parse manifest"
        )
    with open(path, "rb") as f:
        try:
            data = tomllib.load(f)
        except Exception as e:
            raise ValueError(f"malformed manifest TOML at {path}: {e}") from e
    manifest = {}
    for obj_type, section in data.items():
        if isinstance(section, dict) and isinstance(section.get("patterns"), list):
            manifest[obj_type] = [p for p in section["patterns"] if isinstance(p, str)]
    return manifest


def function_signature_present(schema_sql, signature):
    """Same matching semantics as the listener's _function_signature_present:
    tolerant of multi-line CREATE FUNCTION headers, matches on function name
    only (pgschema dump ordering of arg types is stable per definition, so a
    name-based header match is sufficient for this v1 check)."""
    m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\s*$", signature)
    if not m:
        return signature in schema_sql
    func_name = m.group(1)
    header_re = re.compile(
        r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+" + re.escape(func_name) + r"\s*\(",
        re.IGNORECASE,
    )
    return bool(header_re.search(schema_sql))


def find_missing(manifest, schema_sql):
    missing = []
    for obj_type, patterns in manifest.items():
        for pattern in patterns:
            if obj_type == "functions":
                found = function_signature_present(schema_sql, pattern)
            else:
                found = pattern in schema_sql
            if not found:
                missing.append(f"{obj_type}: {pattern}")
    return missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser.add_argument(
        "--manifest",
        default=os.path.join(repo_root, "database", ".schema-manifest.toml"),
    )
    parser.add_argument(
        "--schema",
        default=os.path.join(repo_root, "database", "schema.sql"),
    )
    args = parser.parse_args(argv)

    try:
        manifest = load_manifest(args.manifest)
    except (ValueError, RuntimeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    if not manifest:
        print("No schema manifest entries to check (manifest absent or empty).")
        return 0

    if not os.path.isfile(args.schema):
        print(f"ERROR: schema file not found: {args.schema}", file=sys.stderr)
        return 2

    with open(args.schema, "r") as f:
        schema_sql = f.read()

    missing = find_missing(manifest, schema_sql)
    total = sum(len(v) for v in manifest.values())

    if missing:
        print(f"FAIL: {len(missing)}/{total} manifest object(s) missing from {args.schema}:")
        for obj in missing:
            print(f"  - {obj}")
        print(
            "\nSee database/.schema-manifest.toml for the sanctioned removal path "
            "(manifest-edit PR first, then live-DB drop)."
        )
        return 1

    print(f"OK: all {total} schema manifest object(s) present in {args.schema}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
