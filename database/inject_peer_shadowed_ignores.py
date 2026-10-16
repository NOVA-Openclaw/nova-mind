#!/usr/bin/env python3
"""Inject detected peer-shadowed relation names into a .pgschemaignore file.

Reads an existing .pgschemaignore-style TOML file and appends each detected
name to the appropriate section:
  * relkind 'v' -> [views]
  * relkind 'f' -> [tables]

Sections are created if absent.  Duplicate entries are ignored.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def _section_pattern(section: str) -> re.Pattern[str]:
    return re.compile(rf"^\[{re.escape(section)}\]\s*$")


def _read_array_entries(text: str) -> set[str]:
    """Return quoted string entries found in a TOML array body."""
    return set(re.findall(r'"([^"]+)"', text))


def _inject_section(
    lines: list[str],
    section: str,
    names: set[str],
) -> list[str]:
    """Return new lines with names added to the given [section]."""
    if not names:
        return lines

    section_re = _section_pattern(section)
    start_idx: int | None = None
    end_idx: int | None = None

    for idx, line in enumerate(lines):
        if section_re.match(line):
            start_idx = idx
            continue
        if start_idx is not None and end_idx is None:
            if line.strip().startswith("]"):
                end_idx = idx
                break

    if start_idx is None:
        # Section does not exist; append it.
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(f"[{section}]")
        lines.append("patterns = [")
        for name in sorted(names):
            lines.append(f'  "{name}",')
        lines.append("]")
        return lines

    if end_idx is None:
        # Malformed: section started but never closed.
        print(f"ERROR: malformed [{section}] section in ignore file", file=sys.stderr)
        sys.exit(2)

    # Read existing entries to avoid duplicates.
    existing = _read_array_entries("\n".join(lines[start_idx:end_idx]))
    new_names = sorted(names - existing)
    if not new_names:
        return lines

    # The line immediately before the closing ']' must end with a comma so
    # that the new entries are valid TOML array elements, UNLESS the only
    # thing between the opening "patterns = [" and the closing "]" is
    # whitespace/comments.  Find the previous non-empty, non-comment line and
    # add a comma if it looks like an array entry (a quoted string).
    prev_idx = end_idx - 1
    while prev_idx > start_idx:
        prev_line = lines[prev_idx].strip()
        if prev_line and not prev_line.startswith("#"):
            break
        prev_idx -= 1

    if (
        prev_idx > start_idx
        and '"' in lines[prev_idx]
        and not lines[prev_idx].rstrip().endswith(",")
    ):
        # Add the comma after the last quoted string on the line, before any
        # trailing comment, so "\"foo\" # comment" becomes
        # "\"foo\", # comment".
        lines[prev_idx] = re.sub(
            r'("[^"]*")(\s*(?:#.*)?)$',
            r'\1,\2',
            lines[prev_idx],
        )

    # Insert new entries before the closing ']'.
    insert_lines = [f'  "{name}",' for name in new_names]
    return lines[:end_idx] + insert_lines + lines[end_idx:]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ignore-file", required=True, help="Path to .pgschemaignore file")
    parser.add_argument(
        "--names",
        required=True,
        help="Comma-separated list of relation names to inject",
    )
    parser.add_argument(
        "--relkinds",
        required=True,
        help="Comma-separated relkinds ('f' or 'v') matching --names",
    )
    args = parser.parse_args(argv)

    names = [n.strip() for n in args.names.split(",") if n.strip()]
    relkinds = [k.strip() for k in args.relkinds.split(",") if k.strip()]
    if len(names) != len(relkinds):
        print("ERROR: --names and --relkinds must have same length", file=sys.stderr)
        return 2

    tables: set[str] = set()
    views: set[str] = set()
    for name, relkind in zip(names, relkinds):
        if relkind == "v":
            views.add(name)
        elif relkind == "f":
            tables.add(name)
        else:
            print(f"ERROR: unknown relkind '{relkind}' for {name}", file=sys.stderr)
            return 2

    path = Path(args.ignore_file)
    if not path.is_file():
        print(f"ERROR: ignore file not found: {args.ignore_file}", file=sys.stderr)
        return 2

    lines = path.read_text(encoding="utf-8").splitlines()
    lines = _inject_section(lines, "tables", tables)
    lines = _inject_section(lines, "views", views)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    sys.exit(main())
