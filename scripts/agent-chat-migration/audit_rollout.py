#!/usr/bin/env python3
"""
audit_rollout.py — Report which agents on this host have migrated to the
dedicated agent_chat database.

Reads each candidate postgres.json and resolves the agent_chat database using
the same config-file logic as load_pg_env(section="agent_chat"): the nested
agent_chat section takes precedence over top-level flat keys, with per-field
fallback to defaults. ENV vars are deliberately ignored so the audit reflects
persistent config state rather than the shell environment of this run.

Exit code:
  0  all candidates readable and migrated (agent_chat resolves to agent_chat)
  1  any candidate is unmigrated, unreadable, or missing

Usage:
  ./scripts/agent-chat-migration/audit_rollout.py
  ./scripts/agent-chat-migration/audit_rollout.py --json
"""

import argparse
import json
import os
import sys
from pathlib import Path


# Peer agents run as separate unix users with their own home dirs and pgpass.
# Permission errors on peer homes are expected when this script is run as a
# non-root user; they are reported as unreadable and the operator should re-run
# the audit as that peer or from a user with read access.
CANDIDATE_PATHS = [
    Path("/home/nova/.openclaw/postgres.json"),
    Path("/home/newhart/.openclaw/postgres.json"),
    Path("/home/graybeard/.openclaw/postgres.json"),
]

# Per-agent workspace conventions observed in the NOVA ecosystem.
_PER_AGENT_PATTERNS = [
    "~/.openclaw/workspace-*/postgres.json",
    "~/.openclaw/agents/*/postgres.json",
]

_FIELD_MAP = [
    ("host", "localhost"),
    ("port", "5432"),
    ("database", None),
    ("user", os.environ.get("USER", "unknown")),
    ("password", None),
]


def _expand_candidates() -> list[Path]:
    """Return candidate postgres.json paths, de-duplicated by real path."""
    candidates: list[Path] = []
    seen: set[str] = set()

    for path in CANDIDATE_PATHS:
        try:
            rp = path.resolve()
            if str(rp) not in seen:
                candidates.append(path)
                seen.add(str(rp))
        except OSError:
            candidates.append(path)
            seen.add(str(path))

    for pattern in _PER_AGENT_PATTERNS:
        for path in Path.home().glob(pattern):
            try:
                rp = path.resolve()
                if str(rp) not in seen:
                    candidates.append(path)
                    seen.add(str(rp))
            except OSError:
                if str(path) not in seen:
                    candidates.append(path)
                    seen.add(str(path))

    return candidates


def _resolve_agent_chat_db(path: Path) -> tuple[str, str | None, str | None, str | None]:
    """Return (status, database, user, error) for agent_chat resolution."""
    if not path.exists():
        return ("missing", None, None, "file not found")

    try:
        with open(path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except (json.JSONDecodeError, OSError, PermissionError) as e:
        return ("unreadable", None, None, str(e))

    if not isinstance(config, dict):
        return ("unreadable", None, None, "top level is not a JSON object")

    section = config.get("agent_chat")
    section_is_valid = isinstance(section, dict)
    if section is not None and not section_is_valid:
        return ("unreadable", None, None, "agent_chat section is not a JSON object")

    result: dict[str, str] = {}
    for json_key, default in _FIELD_MAP:
        # 1. section field
        if section_is_valid and section.get(json_key) is not None:
            result[json_key] = str(section[json_key])
            continue

        # 2. top-level flat key
        cfg_val = config.get(json_key)
        if cfg_val is not None:
            result[json_key] = str(cfg_val)
            continue

        # 3. default
        if default is not None:
            result[json_key] = default

    database = result.get("database")
    user = result.get("user")
    status = "migrated" if database == "agent_chat" else "unmigrated"
    return (status, database, user, None)


def _agent_name_from_path(path: Path) -> str:
    """Best-effort agent name from a postgres.json path."""
    parts = path.parts
    path_str = str(path)

    if "workspace-" in path_str:
        for part in parts:
            if part.startswith("workspace-"):
                return part.split("-", 1)[1]

    if "agents" in parts:
        try:
            idx = parts.index("agents")
            if idx + 1 < len(parts):
                return parts[idx + 1]
        except ValueError:
            pass

    home = Path.home()
    if path == home / ".openclaw" / "postgres.json":
        return os.environ.get("USER", "current")

    for home_dir in ("/home/nova", "/home/newhart", "/home/graybeard"):
        if path_str.startswith(home_dir):
            return Path(home_dir).name

    return "unknown"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit agent_chat database rollout status across agents."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output raw JSON instead of a human-readable table.",
    )
    args = parser.parse_args()

    candidates = _expand_candidates()
    rows: list[dict] = []

    for path in candidates:
        status, database, user, error = _resolve_agent_chat_db(path)
        agent = _agent_name_from_path(path)
        rows.append(
            {
                "agent": agent,
                "path": str(path),
                "status": status,
                "database": database,
                "user": user,
                "error": error,
            }
        )

    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        print(f"{'Agent':<12} {'Status':<12} {'Database':<20} {'User':<15} {'Path'}")
        print("-" * 90)
        for row in rows:
            print(
                f"{row['agent']:<12} {row['status']:<12} "
                f"{str(row['database']):<20} {str(row['user']):<15} {row['path']}"
            )
            if row["error"]:
                print(f"             error: {row['error']}")

        migrated = sum(1 for r in rows if r["status"] == "migrated")
        unmigrated = sum(1 for r in rows if r["status"] == "unmigrated")
        unreadable = sum(1 for r in rows if r["status"] in ("unreadable", "missing"))
        print()
        print(
            f"Summary: {migrated} migrated, {unmigrated} unmigrated, "
            f"{unreadable} unreadable/missing (of {len(rows)} candidates)"
        )

    if any(r["status"] != "migrated" for r in rows):
        if not args.json:
            print("At least one agent is not fully migrated.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
