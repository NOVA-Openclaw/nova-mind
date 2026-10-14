#!/usr/bin/env python3
"""Peer-side import for cleanup tooling part 1 (#708/#703).

A peer agent runs this script as its own user against its OWN memory database.
It consumes the per-peer export file + manifest produced by NOVA's cleanup
tooling and inserts only rows that do not already exist.

Design rules:
  - Verify file and per-row checksums before inserting.
  - Refuse to run if the export's peer does not match the target DB owner.
  - Idempotent on (session_key, external_message_id).
  - Never connect to a database not owned by this peer.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Optional

# Add scripts dir to path so tests/production can import cleanup_708_703.
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

# Reuse NOVA-side resolver and checksum helpers; on a peer host it resolves to
# <peer>_memory the same way #703 resolves PGDATABASE -> postgres.json.
from cleanup_708_703 import _canonical_json, _sha256, resolve_memory_database_name


# ---------------------------------------------------------------------------
# Derivation comments for every literal
# ---------------------------------------------------------------------------

# Columns inserted into channel_sessions. Derivation: must match the columns
# exported by cleanup_708_703.export_peer_rows; we omit immutable/generated
# fields (id, created_at, updated_at) and only supply values the peer may need
# to recreate the session context. Ordering matches the upsert in the original
# split_replay_stranded_rows implementation.
SESSION_INSERT_COLUMNS = [
    "session_key",
    "agent_id",
    "provider",
    "external_chat_id",
    "external_thread_id",
    "chat_type",
]

# Columns inserted into channel_transcripts. Derivation: matches the export
# columns from cleanup_708_703 minus the immutable/generated id/created_at.
TRANSCRIPT_INSERT_COLUMNS = [
    "session_id",
    "external_message_id",
    "timestamp",
    "role",
    "content",
    "sender_id",
    "sender_name",
    "sender_username",
    "sender_tag",
    "sender_entity_id",
    "content_type",
    "raw_metadata",
]

# Required manifest keys. Derivation: TEST-CASES-ISSUE-708.md TC-708-012c
# requires row count, per-row checksums, file checksum, and aggregate checksum;
# TC-708-012d requires the peer name and session key for ownership/idempotency.
REQUIRED_MANIFEST_KEYS = {
    "peer",
    "source_database",
    "session_key",
    "row_count",
    "file_checksum",
    "per_row_checksums",
    "aggregate_checksum",
}


def _open_connection(database: str) -> Any:
    """Open a psycopg2 connection to the named database."""
    import psycopg2

    return psycopg2.connect(dbname=database)


def _db_owner(database: str) -> str:
    """Return the agent that owns a ``<agent>_memory`` database name.

    Derivation: a peer's memory database is named ``<peer>_memory`` per #703;
    the owner prefix must match the export's ``peer`` field so a peer cannot
    accidentally import another peer's rows.
    """
    if not database.endswith("_memory"):
        raise RuntimeError(
            f"[peer-import] Database '{database}' does not look like a memory database"
        )
    return database[:-7]


def _verify_checksums(export_path: Path, manifest: dict[str, Any]) -> None:
    """Verify the export file against the manifest.

    Derivation: TEST-CASES-ISSUE-708.md TC-708-012c; recompute checksums from
    the file on disk (not the original DB) to prove the manifest describes the
    file that was actually written.
    """
    file_bytes = export_path.read_bytes()
    file_checksum = _sha256(file_bytes)
    if file_checksum != manifest["file_checksum"]:
        raise RuntimeError(
            f"[peer-import] File checksum mismatch for {export_path}: "
            f"expected {manifest['file_checksum']}, got {file_checksum}"
        )

    per_row: list[str] = []
    with export_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj.get("type") != "channel_transcript":
                continue
            row = obj["row"]
            per_row.append(_sha256(_canonical_json(row).encode("utf-8")))

    if per_row != manifest["per_row_checksums"]:
        raise RuntimeError(
            "[peer-import] Per-row checksum mismatch in export file"
        )

    aggregate_hasher = hashlib.sha256()
    for chk in per_row:
        aggregate_hasher.update(chk.encode("ascii"))
    aggregate = aggregate_hasher.hexdigest()
    if aggregate != manifest["aggregate_checksum"]:
        raise RuntimeError(
            "[peer-import] Aggregate checksum mismatch in export file"
        )


def _load_export(export_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Parse a JSONL export into session context + transcript rows.

    Derivation: cleanup_708_703.export_peer_rows writes a session_context
    header followed by channel_transcript rows; this is the inverse parse.
    """
    session_context: Optional[dict[str, Any]] = None
    transcript_rows: list[dict[str, Any]] = []
    with export_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj.get("type") == "session_context":
                session_context = obj["session"]
            elif obj.get("type") == "channel_transcript":
                transcript_rows.append(obj["row"])

    if session_context is None:
        raise RuntimeError("[peer-import] Export file missing session_context header")

    return session_context, transcript_rows


def import_peer_rows(
    conn: Any,
    export_path: Path,
    manifest_path: Path,
    dry_run: bool = False,
    target_database: Optional[str] = None,
) -> dict[str, Any]:
    """Import peer-owned rows from NOVA's export into this peer's own DB.

    Parameters:
      conn: open connection to this peer's memory database.
      export_path: path to the per-peer JSONL export file.
      manifest_path: path to the corresponding manifest JSON.
      dry_run: if True, compute actions without inserting.
      target_database: optional resolved target database name; if omitted, it
        is resolved via #703's resolver.

    Returns a dict with counts and actions. Derivation: TC-708-012d and
    TC-703-003/004/005; idempotency key is (session_key, external_message_id).
    """
    export_path = Path(export_path)
    manifest_path = Path(manifest_path)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    missing = REQUIRED_MANIFEST_KEYS - set(manifest.keys())
    if missing:
        raise RuntimeError(
            f"[peer-import] Manifest missing required keys: {sorted(missing)}"
        )

    # Derivation: ensure the export is actually for this peer before opening
    # any rows. TC-703-005's multi-peer discrimination depends on this gate.
    target_db = target_database or resolve_memory_database_name()
    target_owner = _db_owner(target_db)
    if manifest["peer"] != target_owner:
        raise RuntimeError(
            f"[peer-import] Export peer '{manifest['peer']}' does not match "
            f"target DB owner '{target_owner}'"
        )

    _verify_checksums(export_path, manifest)

    session_context, transcript_rows = _load_export(export_path)

    if len(transcript_rows) != manifest["row_count"]:
        raise RuntimeError(
            f"[peer-import] Row count mismatch: manifest {manifest['row_count']}, "
            f"file {len(transcript_rows)}"
        )

    actions: list[dict[str, Any]] = []
    inserted = 0
    skipped = 0

    with conn.cursor() as cur:
        session_key = session_context["session_key"]
        provider = session_context["provider"]
        external_chat_id = session_context["external_chat_id"]
        external_thread_id = session_context.get("external_thread_id")
        chat_type = session_context.get("chat_type")

        for row in transcript_rows:
            external_message_id = row["external_message_id"]

            # Idempotency: skip rows already present keyed on
            # (session_key, external_message_id).
            cur.execute(
                """
                SELECT ct.id
                FROM channel_transcripts ct
                JOIN channel_sessions cs ON cs.id = ct.session_id
                WHERE cs.session_key = %s AND ct.external_message_id = %s
                LIMIT 1
                """,
                (session_key, external_message_id),
            )
            if cur.fetchone() is not None:
                skipped += 1
                actions.append(
                    {
                        "session_key": session_key,
                        "external_message_id": external_message_id,
                        "action": "skipped",
                    }
                )
                continue

            if not dry_run:
                # Upsert session by unique index; returns the session id to use
                # for transcript insertion.
                cur.execute(
                    """
                    INSERT INTO channel_sessions
                      (session_key, agent_id, provider, external_chat_id,
                       external_thread_id, chat_type)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (provider, external_chat_id,
                                 COALESCE(external_thread_id, ''))
                    DO UPDATE SET updated_at = NOW()
                    RETURNING id
                    """,
                    (session_key, "main", provider, external_chat_id,
                     external_thread_id, chat_type),
                )
                target_session_id = cur.fetchone()[0]

                raw_meta = row.get("raw_metadata")
                cur.execute(
                    """
                    INSERT INTO channel_transcripts
                      (session_id, external_message_id, timestamp, role,
                       content, sender_id, sender_name, sender_username,
                       sender_tag, sender_entity_id, content_type, raw_metadata)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (session_id, external_message_id) DO NOTHING
                    """,
                    (
                        target_session_id,
                        external_message_id,
                        row["timestamp"],
                        row["role"],
                        row["content"],
                        row.get("sender_id"),
                        row.get("sender_name"),
                        row.get("sender_username"),
                        row.get("sender_tag"),
                        row.get("sender_entity_id"),
                        row.get("content_type"),
                        json.dumps(raw_meta) if raw_meta is not None else None,
                    ),
                )

            inserted += 1
            actions.append(
                {
                    "session_key": session_key,
                    "external_message_id": external_message_id,
                    "action": "inserted" if not dry_run else "would_insert",
                }
            )

    return {
        "dry_run": dry_run,
        "row_count": len(transcript_rows),
        "inserted": inserted,
        "skipped": skipped,
        "actions": actions,
    }


def main(argv: list[str] | None = None) -> None:
    """CLI entry point for the peer-side import script."""
    parser = argparse.ArgumentParser(
        description="Peer-side import for NOVA cleanup exports (#708/#703)"
    )
    parser.add_argument(
        "--export", required=True, type=Path,
        help="Path to the per-peer JSONL export file",
    )
    parser.add_argument(
        "--manifest", required=True, type=Path,
        help="Path to the corresponding manifest JSON file",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Compute actions without inserting any rows",
    )
    args = parser.parse_args(argv)

    dbname = resolve_memory_database_name()
    conn = _open_connection(dbname)
    try:
        result = import_peer_rows(
            conn,
            args.export,
            args.manifest,
            dry_run=args.dry_run,
            target_database=dbname,
        )
        print(json.dumps(result, sort_keys=True, indent=2, default=str))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
