#!/usr/bin/env python3
"""Filter GRANT/REVOKE lines that target peer-shadowed relations.

Reads SQL lines from stdin, prints lines that should be applied to stdout,
and reports skipped-statement counts per object to stderr.

A statement is skipped when any of its target objects (the object names after
``ON TABLE`` / ``ON SEQUENCE`` / ...) is either a peer-shadowed relation name
or its default ``<name>_id_seq`` sequence.  The privileges of peer-shadowed
relations are owned by the FDW setup on the peer (#520), so schema.sql's
GRANT/REVOKE lines must not be reconciled against the local database.
"""

from __future__ import annotations

import argparse
import re
import sys

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


_SPLIT_RE = re.compile(r"\s*,\s*")


def _normalize_identifier(ident: str) -> str:
    ident = ident.strip()
    if len(ident) >= 2 and ident[0] == ident[-1] == '"':
        # Strip double quotes and unescape doubled quotes.
        ident = ident[1:-1].replace('""', '"')
    return ident.lower()


def _target_objects(line: str) -> list[str]:
    """Return normalized object names mentioned as GRANT/REVOKE targets."""
    objects: list[str] = []
    for match in TARGET_RE.finditer(line):
        raw = match.group(2)
        for part in _SPLIT_RE.split(raw):
            obj = _normalize_identifier(part)
            if obj:
                objects.append(obj)
    return objects


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--shadowed-names",
        default="",
        metavar="NAME1,NAME2,...",
        help="Comma-separated peer-shadowed relation names (default: empty)",
    )
    args = parser.parse_args(argv)

    shadowed = {n.strip().lower() for n in args.shadowed_names.split(",") if n.strip()}
    shadowed_seqs = {f"{n}_id_seq" for n in shadowed}

    skipped: dict[str, int] = {}
    kept = 0

    for line in sys.stdin:
        line = line.rstrip("\n")
        if not GRANT_REVOKE_RE.match(line):
            # Pass through non-GRANT/REVOKE lines unchanged.
            print(line)
            continue

        objects = _target_objects(line)
        skip_name: str | None = None
        for obj in objects:
            if obj in shadowed or obj in shadowed_seqs:
                skip_name = obj
                break

        if skip_name is not None:
            skipped[skip_name] = skipped.get(skip_name, 0) + 1
        else:
            print(line)
            kept += 1

    for name in sorted(skipped):
        count = skipped[name]
        print(
            f"SKIPPED: {count} grant/revoke statement(s) for peer-shadowed "
            f"object '{name}'",
            file=sys.stderr,
        )

    print(f"Kept {kept} grant/revoke statement(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
