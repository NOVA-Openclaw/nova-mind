#!/usr/bin/env python3
"""CI backstop for nova-mind#624: assert every object listed in
database/.schema-manifest.toml is present in database/schema.sql, and that
any declared security properties (SECURITY DEFINER, search_path pinning,
etc.) are still present in that object's CREATE statement.

This is a static, repo-only check -- it does not connect to any database.
It exists as a second line of defense behind the listener-side veto in
cognition/scripts/pg-notify-listener.py (which is the PRIMARY safeguard,
enforced at sync time against the live DB); this script catches the case
where schema.sql was modified/committed through some path other than the
listener (e.g. a manual edit, a revert, a rebase) and a manifest object (or
its security hardening) was lost without the listener ever running.

The [function_security] manifest section (B-1, SE run #804 QA review)
asserts required literal substrings (e.g. "SECURITY DEFINER",
"SET search_path = public") are present within a given function's CREATE
FUNCTION statement. This is a text-level check against schema.sql, not a
live-catalog query (prosecdef/proconfig) -- it re-verifies what the SQL
text declares, not what is actually applied to any given database. Live
catalog verification for a specific database still requires a psql query
(e.g. `SELECT prosecdef, proconfig FROM pg_proc WHERE proname = ...`);
this script cannot and does not replace that for the live DB.

Exit codes:
  0 - all manifest objects present with required properties (or no
      manifest / no entries -- nothing to check)
  1 - one or more manifest objects missing from schema.sql, or missing a
      declared security property
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

    Returns a dict with two possible top-level shapes merged together:
      - "list sections" (e.g. functions/tables/...): {obj_type: [patterns]}
      - "function_security": {func_name: [required_substrings]}, parsed
        separately from the generic patterns loop since its value shape is
        a mapping, not a list.
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
        if obj_type == "function_security":
            continue  # handled separately by load_function_security()
        if isinstance(section, dict) and isinstance(section.get("patterns"), list):
            manifest[obj_type] = [p for p in section["patterns"] if isinstance(p, str)]
    return manifest


def load_function_security(path):
    """Parse the optional [function_security] section: {func_name: [required substrings]}.

    Returns {} if the manifest is absent or has no such section. Raises
    ValueError on malformed TOML (same fail-closed contract as load_manifest
    -- a function_security section that silently failed to load would
    silently stop enforcing the security properties in it).
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
    section = data.get("function_security")
    if not isinstance(section, dict):
        return {}
    result = {}
    for func_name, required in section.items():
        if isinstance(required, list):
            result[func_name] = [r for r in required if isinstance(r, str)]
    return result


def function_signature_present(schema_sql, signature):
    """Same matching semantics as the listener's _function_signature_present:
    tolerant of multi-line CREATE FUNCTION headers. This is a NAME-ONLY
    presence check -- it does not parse or compare the declared argument
    types in `signature` against the actual dumped signature, only confirms
    a `CREATE [OR REPLACE] FUNCTION <name>(` header exists for the function
    name extracted from `signature`. Sufficient for detecting whether a
    hand-authored function was removed entirely by a dump, but would NOT
    distinguish two overloads of the same function name with different
    argument lists."""
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


def extract_function_body(schema_sql, func_name):
    """Return the text of the first `CREATE [OR REPLACE] FUNCTION <func_name>(`
    statement through its terminating `$$;` in schema_sql, or None if not
    found. Used to scope security-property substring checks to the
    function's own statement rather than the whole file (so a required
    substring like "SECURITY DEFINER" isn't satisfied by an unrelated
    function elsewhere in schema.sql).
    """
    header_re = re.compile(
        r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+" + re.escape(func_name) + r"\s*\(",
        re.IGNORECASE,
    )
    m = header_re.search(schema_sql)
    if not m:
        return None
    # pgschema dumps terminate function bodies with a line consisting of
    # exactly "$$;" (dollar-quoted body close + statement semicolon).
    end_re = re.compile(r"\$\$;", re.MULTILINE)
    end_m = end_re.search(schema_sql, m.end())
    if not end_m:
        # No terminator found; fall back to end of file so callers still get
        # a best-effort text blob rather than nothing.
        return schema_sql[m.start():]
    return schema_sql[m.start():end_m.end()]


def find_missing_security_properties(function_security, schema_sql):
    """Return a list of "func_name: required_substring" strings for
    function_security entries whose required substring is absent from that
    function's own CREATE FUNCTION statement (or whose function is entirely
    absent from schema_sql -- reported as "func_name: <function not found>").
    """
    missing = []
    for func_name, required_substrings in function_security.items():
        body = extract_function_body(schema_sql, func_name)
        if body is None:
            missing.append(f"{func_name}: <function not found in {func_name}(...)>")
            continue
        for substring in required_substrings:
            if substring not in body:
                missing.append(f"{func_name}: missing required property '{substring}'")
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
        function_security = load_function_security(args.manifest)
    except (ValueError, RuntimeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    if not manifest and not function_security:
        print("No schema manifest entries to check (manifest absent or empty).")
        return 0

    if not os.path.isfile(args.schema):
        print(f"ERROR: schema file not found: {args.schema}", file=sys.stderr)
        return 2

    with open(args.schema, "r") as f:
        schema_sql = f.read()

    missing = find_missing(manifest, schema_sql)
    missing_security = find_missing_security_properties(function_security, schema_sql)
    total = sum(len(v) for v in manifest.values()) + sum(
        len(v) for v in function_security.values()
    )

    if missing or missing_security:
        all_missing = missing + missing_security
        print(f"FAIL: {len(all_missing)}/{total} manifest check(s) failed against {args.schema}:")
        for obj in missing:
            print(f"  - {obj}")
        for obj in missing_security:
            print(f"  - function_security: {obj}")
        print(
            "\nSee database/.schema-manifest.toml for the sanctioned removal path "
            "(manifest-edit PR first, then live-DB drop)."
        )
        return 1

    print(f"OK: all {total} schema manifest check(s) passed against {args.schema}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
