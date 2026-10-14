#!/usr/bin/env python3
"""Cleanup tooling for nova-mind #708 / #703 — part 1 (identify + backup + export).

Scope (PART 1 ONLY):
  - Identify misplaced sessions/transcripts in the current memory database.
  - Back up every misplaced row with row counts + checksums.
  - Export peer-owned rows to per-peer, importable files + checksum manifest.
  - Provide an idempotent split/replay helper for stranded rows (no DELETE in
    part 1; deletion is gated to a later dispatch).

Design rules:
  - Never hardcodes ``nova_memory``; the target database is resolved the same
    way #703 does (PGDATABASE env var -> ~/.openclaw/postgres.json).
  - Peer detection reuses extract_memories.py's session-key parser and the
    ``<peer>_memory`` catalog lookup.
  - NOVA never connects to a peer database; exports are files consumed by the
    peer's own import process.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

# Add scripts dir to path so tests/production can import extract_memories.
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))


# ---------------------------------------------------------------------------
# Derivation comments for every literal
# ---------------------------------------------------------------------------

# Regex for agent prefix in session_key. Derivation: matches #703's
# _parse_agent_from_session_key in extract_memories.py (line ~108), which is
# the canonical peer resolver for memory-extract events.
SESSION_KEY_AGENT_RE = re.compile(r"^agent:([^:]+):")

# Known test/legacy sender names that should be treated as junk inside an
# otherwise correct session. Derivation: TEST-CASES-ISSUE-708.md §1b enumerates
# "zztest_a, schema-sync, and similar" as non-real-agent senders; this default
# list is the minimum set observed live in session 15 during SE #1231 step 5.
DEFAULT_JUNK_SENDERS = {
    "zztest_a",
    "schema-sync",
    "agent_chat",
    "system",
}

# Columns exported for channel_sessions. Derivation: dt.sh schema for
# channel_sessions (see cleanup-identify-live.log), ordered to keep parent-row
# context directly next to each transcript row in the JSONL export.
SESSION_EXPORT_COLUMNS = [
    "id",
    "session_key",
    "agent_id",
    "provider",
    "external_chat_id",
    "external_thread_id",
    "chat_type",
    "title",
    "group_subject",
    "group_space_id",
    "started_at",
    "last_message_at",
    "message_count",
    "raw_metadata",
    "created_at",
    "updated_at",
]

# Columns exported for channel_transcripts. Derivation: dt.sh schema for
# channel_transcripts.
TRANSCRIPT_EXPORT_COLUMNS = [
    "id",
    "session_id",
    "external_message_id",
    "timestamp",
    "sender_id",
    "sender_name",
    "sender_username",
    "sender_tag",
    "sender_entity_id",
    "role",
    "content",
    "content_type",
    "raw_metadata",
    "created_at",
]

# Stable JSON serialization for checksums. Derivation: JSONL export must be
# byte-reproducible so manifest checksums verify; sort_keys=True removes dict
# ordering differences, ensure_ascii=False keeps unicode stable, default=str
# handles datetime/jsonb values.
def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, default=str)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _row_checksum(row: dict[str, Any]) -> str:
    """Content checksum for a single exported row.

    Derivation: TEST-CASES-ISSUE-708.md TC-708-011 requires "per-row hash of
    the transcript content + timestamp + sender"; we hash the canonical JSON
    of the full row so any field change is detectable.
    """
    return _sha256(_canonical_json(row).encode("utf-8"))


# ---------------------------------------------------------------------------
# Reuse #703 resolver helpers (lazy import to avoid module-load side effects)
# ---------------------------------------------------------------------------

def _import_extract_memories() -> Any:
    """Lazy import extract_memories so callers can patch pg_env first."""
    try:
        import extract_memories  # type: ignore
    except ImportError as exc:  # pragma: no cover - production guard
        raise RuntimeError("Could not import extract_memories resolver") from exc
    return extract_memories


def _load_database_from_postgres_config() -> Optional[str]:
    """Read database name from ~/.openclaw/postgres.json.

    Derivation: mirrors extract_memories._load_database_from_postgres_config()
    so cleanup and the extraction pipeline resolve config identically.
    """
    config_path = os.path.expanduser("~/.openclaw/postgres.json")
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            parsed = json.load(f)
        db = parsed.get("database")
        if isinstance(db, str) and db.strip():
            return db.strip()
    except FileNotFoundError:
        pass
    except (OSError, json.JSONDecodeError) as exc:
        print(f"[cleanup] Could not read postgres.json: {exc}", file=sys.stderr)
    return None


def resolve_memory_database_name(session_key: str = "") -> str:
    """Resolve the memory database name using #703's resolution order.

    Resolution: PGDATABASE env var -> ~/.openclaw/postgres.json ``database``.
    Validates the name ends with ``_memory``. Does NOT open a connection.

    Derivation: extract_memories.get_db_connection() lines 102-122 implement
    the same env->config order and ``_memory`` suffix validation; we reuse it
    here so cleanup never hardcodes a database name.
    """
    pg_database = os.environ.get("PGDATABASE")
    db_name = pg_database.strip() if pg_database and pg_database.strip() else _load_database_from_postgres_config()

    if not db_name:
        raise RuntimeError(
            "[cleanup] Could not resolve memory database: PGDATABASE unset and "
            "~/.openclaw/postgres.json missing or has no usable database field"
        )
    if not db_name.endswith("_memory"):
        raise RuntimeError(
            f"[cleanup] Resolved database '{db_name}' does not look like a memory database"
        )

    return db_name


def parse_agent_from_session_key(session_key: str) -> Optional[str]:
    """Parse ``agent:<peer>:...`` prefix; returns None if no match."""
    match = SESSION_KEY_AGENT_RE.match(session_key or "")
    return match.group(1) if match else None


def agent_has_memory_database(agent: str, conn: Any) -> bool:
    """Return True if ``<agent>_memory`` exists on the connected server.

    Derivation: mirrors extract_memories._agent_has_memory_database() so peer
    detection is consistent with #703's cross-peer guard.
    """
    candidate = f"{agent}_memory"
    try:
        cur = conn.cursor()
        try:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (candidate,))
            return cur.fetchone() is not None
        finally:
            cur.close()
    except Exception as exc:  # pragma: no cover - defensive
        print(
            f"[cleanup] WARNING: Could not verify peer database ownership for '{agent}': {exc}",
            file=sys.stderr,
        )
        return False


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class MisplacedSession:
    session_id: int
    session_key: str
    provider: str
    external_chat_id: str
    external_thread_id: Optional[str]
    row_count: int
    disposition: str  # 'peer_misplaced', 'non_peer_wrong_place', 'junk_in_session'
    sender_breakdown: list[dict[str, Any]]


@dataclass(frozen=True)
class IdentificationResult:
    current_database: str
    current_owner: str
    peer_misplaced: list[MisplacedSession]
    non_peer_wrong_place: list[MisplacedSession]
    junk_in_session: list[MisplacedSession]
    correct_sessions: list[MisplacedSession]

    @property
    def total_peer_rows(self) -> int:
        return sum(s.row_count for s in self.peer_misplaced)

    @property
    def total_non_peer_rows(self) -> int:
        return sum(s.row_count for s in self.non_peer_wrong_place)

    @property
    def total_junk_rows(self) -> int:
        return sum(s.row_count for s in self.junk_in_session)


@dataclass
class BackupManifest:
    created_at: str
    source_database: str
    sessions: list[dict[str, Any]]
    total_row_count: int
    aggregate_checksum: str


@dataclass
class PeerExportManifest:
    created_at: str
    peer: str
    source_database: str
    session_id: int
    session_key: str
    row_count: int
    file_path: str
    file_checksum: str
    per_row_checksums: list[str]
    aggregate_checksum: str


# ---------------------------------------------------------------------------
# Identification
# ---------------------------------------------------------------------------

def identify_misplaced_sessions(
    conn: Any,
    current_database: str,
    junk_senders: Optional[set[str]] = None,
) -> IdentificationResult:
    """Read-only identification of every misplaced session/transcript set.

    Parameters:
      conn: open psycopg2-like connection to the memory database being cleaned.
      current_database: name of the database ``conn`` is connected to.
      junk_senders: sender names considered junk inside an otherwise correct
        session. Defaults to DEFAULT_JUNK_SENDERS.

    Derivation: TEST-CASES-ISSUE-708.md TC-708-010 and §1b define the three
    disposition categories (peer misplaced, non-peer wrong-place, junk senders
    inside correct session).
    """
    junk_senders = junk_senders or DEFAULT_JUNK_SENDERS
    owner = current_database.replace("_memory", "") if current_database.endswith("_memory") else current_database

    with conn.cursor() as cur:
        # Fetch all provider='agent_chat' sessions with transcript counts.
        cur.execute(
            """
            SELECT cs.id, cs.session_key, cs.provider, cs.external_chat_id,
                   cs.external_thread_id, COUNT(ct.id) AS row_count
            FROM channel_sessions cs
            LEFT JOIN channel_transcripts ct ON ct.session_id = cs.id
            WHERE cs.provider = 'agent_chat'
            GROUP BY cs.id, cs.session_key, cs.provider, cs.external_chat_id,
                     cs.external_thread_id
            ORDER BY cs.id
            """
        )
        session_rows = cur.fetchall()

        # Build sender breakdown for every agent_chat session.
        session_ids = [row[0] for row in session_rows]
        sender_breakdowns: dict[int, list[dict[str, Any]]] = {sid: [] for sid in session_ids}
        if session_ids:
            # Safe because session_ids are integers from the DB.
            id_list = ",".join(str(sid) for sid in session_ids)
            cur.execute(
                f"""
                SELECT session_id,
                       COALESCE(sender_name, 'NULL') AS sender_name,
                       COALESCE(sender_id, 'NULL') AS sender_id,
                       COUNT(*) AS row_count
                FROM channel_transcripts
                WHERE session_id IN ({id_list})
                GROUP BY session_id, sender_name, sender_id
                ORDER BY session_id, row_count DESC
                """
            )
            for sid, sender_name, sender_id, count in cur.fetchall():
                sender_breakdowns[sid].append(
                    {
                        "sender_name": sender_name,
                        "sender_id": sender_id,
                        "row_count": count,
                    }
                )

    peer_misplaced: list[MisplacedSession] = []
    non_peer_wrong_place: list[MisplacedSession] = []
    correct_sessions: list[MisplacedSession] = []
    junk_in_session: list[MisplacedSession] = []

    for sid, skey, provider, chat_id, thread_id, count in session_rows:
        agent = parse_agent_from_session_key(skey)
        # Peer detection: the session's agent owns a <agent>_memory database
        # and that agent is not the owner of the database we're scanning.
        is_peer_misplaced = (
            agent is not None
            and agent != owner
            and agent_has_memory_database(agent, conn)
        )

        breakdown = sender_breakdowns.get(sid, [])
        session = MisplacedSession(
            session_id=sid,
            session_key=skey,
            provider=provider,
            external_chat_id=chat_id,
            external_thread_id=thread_id,
            row_count=count,
            disposition="",
            sender_breakdown=breakdown,
        )

        if is_peer_misplaced:
            peer_misplaced.append(
                MisplacedSession(
                    **{**asdict(session), "disposition": "peer_misplaced"}
                )
            )
        elif agent is not None and agent != owner:
            # agent: prefix points somewhere but no peer DB exists.
            non_peer_wrong_place.append(
                MisplacedSession(
                    **{**asdict(session), "disposition": "non_peer_wrong_place"}
                )
            )
        else:
            # Correct session. Check for junk senders inside it.
            junk_breakdown = [b for b in breakdown if b["sender_name"] in junk_senders]
            junk_count = sum(b["row_count"] for b in junk_breakdown)
            if junk_count:
                junk_in_session.append(
                    MisplacedSession(
                        **{
                            **asdict(session),
                            "disposition": "junk_in_session",
                            "row_count": junk_count,
                            "sender_breakdown": junk_breakdown,
                        }
                    )
                )
            correct_sessions.append(session)

    return IdentificationResult(
        current_database=current_database,
        current_owner=owner,
        peer_misplaced=peer_misplaced,
        non_peer_wrong_place=non_peer_wrong_place,
        junk_in_session=junk_in_session,
        correct_sessions=correct_sessions,
    )


# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

def _fetch_session_rows(cur: Any, session_id: int) -> list[dict[str, Any]]:
    """Return every channel_transcripts row for a session as ordered dicts."""
    cur.execute(
        f"""
        SELECT {', '.join(TRANSCRIPT_EXPORT_COLUMNS)}
        FROM channel_transcripts
        WHERE session_id = %s
        ORDER BY id
        """,
        (session_id,),
    )
    return [dict(zip(TRANSCRIPT_EXPORT_COLUMNS, row)) for row in cur.fetchall()]


def _fetch_junk_rows(
    cur: Any, session_id: int, junk_senders: set[str]
) -> list[dict[str, Any]]:
    """Return junk-sender transcript rows for a correct session."""
    if not junk_senders:
        return []
    placeholders = ",".join("%s" for _ in junk_senders)
    cur.execute(
        f"""
        SELECT {', '.join(TRANSCRIPT_EXPORT_COLUMNS)}
        FROM channel_transcripts
        WHERE session_id = %s AND sender_name IN ({placeholders})
        ORDER BY id
        """,
        (session_id, *junk_senders),
    )
    return [dict(zip(TRANSCRIPT_EXPORT_COLUMNS, row)) for row in cur.fetchall()]


def _fetch_session_context(cur: Any, session_id: int) -> dict[str, Any]:
    """Return the parent channel_sessions row as an ordered dict."""
    cur.execute(
        f"""
        SELECT {', '.join(SESSION_EXPORT_COLUMNS)}
        FROM channel_sessions
        WHERE id = %s
        """,
        (session_id,),
    )
    row = cur.fetchone()
    if not row:
        return {}
    return dict(zip(SESSION_EXPORT_COLUMNS, row))


def backup_misplaced_rows(
    conn: Any,
    identification: IdentificationResult,
    output_dir: Path,
    junk_senders: Optional[set[str]] = None,
) -> BackupManifest:
    """Write a verifiable backup of every misplaced row.

    Returns a manifest with per-session row counts, per-row checksums, and an
    aggregate checksum. Derivation: TEST-CASES-ISSUE-708.md TC-708-011.
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).isoformat()

    sessions_backup: list[dict[str, Any]] = []
    aggregate_hasher = hashlib.sha256()
    total_rows = 0

    targets = (
        identification.peer_misplaced
        + identification.non_peer_wrong_place
        + identification.junk_in_session
    )

    with conn.cursor() as cur:
        for session in targets:
            if session.disposition == "junk_in_session":
                rows = _fetch_junk_rows(
                    cur, session.session_id, junk_senders or DEFAULT_JUNK_SENDERS
                )
                context = _fetch_session_context(cur, session.session_id)
            else:
                rows = _fetch_session_rows(cur, session.session_id)
                context = _fetch_session_context(cur, session.session_id)

            per_row_checksums = [_row_checksum(r) for r in rows]
            for chk in per_row_checksums:
                aggregate_hasher.update(chk.encode("ascii"))

            session_file = output_dir / f"session_{session.session_id}_backup.jsonl"
            with session_file.open("w", encoding="utf-8") as f:
                f.write(_canonical_json({"session_context": context}) + "\n")
                for row, chk in zip(rows, per_row_checksums):
                    f.write(_canonical_json({"row": row, "checksum": chk}) + "\n")

            file_bytes = session_file.read_bytes()
            file_checksum = _sha256(file_bytes)
            total_rows += len(rows)

            sessions_backup.append(
                {
                    "session_id": session.session_id,
                    "session_key": session.session_key,
                    "disposition": session.disposition,
                    "row_count": len(rows),
                    "file": str(session_file),
                    "file_checksum": file_checksum,
                    "per_row_checksums": per_row_checksums,
                }
            )

    aggregate_checksum = aggregate_hasher.hexdigest()
    manifest = BackupManifest(
        created_at=timestamp,
        source_database=identification.current_database,
        sessions=sessions_backup,
        total_row_count=total_rows,
        aggregate_checksum=aggregate_checksum,
    )

    manifest_path = output_dir / "backup_manifest.json"
    manifest_path.write_text(
        _canonical_json({**asdict(manifest), "schema": "cleanup-backup-v1"}) + "\n",
        encoding="utf-8",
    )
    return manifest


# ---------------------------------------------------------------------------
# Export (peer rows only)
# ---------------------------------------------------------------------------

def export_peer_rows(
    conn: Any,
    identification: IdentificationResult,
    output_dir: Path,
) -> list[PeerExportManifest]:
    """Export peer-owned rows to per-peer importable JSONL + manifest.

    Derivation: TEST-CASES-ISSUE-708.md TC-708-012, TC-708-012b, TC-708-012c.
    NOVA never writes into a peer database; exports are files.
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).isoformat()
    manifests: list[PeerExportManifest] = []

    with conn.cursor() as cur:
        for session in identification.peer_misplaced:
            agent = parse_agent_from_session_key(session.session_key)
            if not agent:
                continue

            context = _fetch_session_context(cur, session.session_id)
            rows = _fetch_session_rows(cur, session.session_id)
            per_row_checksums = [_row_checksum(r) for r in rows]

            export_file = output_dir / f"{agent}_memory_export.jsonl"
            with export_file.open("w", encoding="utf-8") as f:
                # Header line carries session context so a peer import script
                # can reconstruct the parent session without guessing IDs.
                header = {
                    "type": "session_context",
                    "session": context,
                }
                f.write(_canonical_json(header) + "\n")
                for row, chk in zip(rows, per_row_checksums):
                    f.write(
                        _canonical_json(
                            {
                                "type": "channel_transcript",
                                "row": row,
                                "checksum": chk,
                            }
                        )
                        + "\n"
                    )

            file_bytes = export_file.read_bytes()
            file_checksum = _sha256(file_bytes)
            aggregate_hasher = hashlib.sha256()
            for chk in per_row_checksums:
                aggregate_hasher.update(chk.encode("ascii"))

            manifest = PeerExportManifest(
                created_at=timestamp,
                peer=agent,
                source_database=identification.current_database,
                session_id=session.session_id,
                session_key=session.session_key,
                row_count=len(rows),
                file_path=str(export_file),
                file_checksum=file_checksum,
                per_row_checksums=per_row_checksums,
                aggregate_checksum=aggregate_hasher.hexdigest(),
            )
            manifests.append(manifest)

            manifest_path = output_dir / f"{agent}_memory_manifest.json"
            manifest_path.write_text(
                _canonical_json({**asdict(manifest), "schema": "cleanup-peer-export-v1"})
                + "\n",
                encoding="utf-8",
            )

    return manifests


# ---------------------------------------------------------------------------
# Peer-side import contract (#703 replay, no delete in part 1)
# ---------------------------------------------------------------------------

# NOVA never writes into a peer database. The split/replay logic has been
# moved to the peer-side script cleanup_peer_import.py. This module ends at
# export; peers import their own export files as their own user against their
# own resolved memory database.


# ---------------------------------------------------------------------------
# CLI entry points
# ---------------------------------------------------------------------------

def _open_connection(database: str) -> Any:
    """Open a psycopg2 connection to the named database."""
    import psycopg2
    return psycopg2.connect(dbname=database)


def _main_identify() -> None:
    """CLI: run identification against the resolved memory database."""
    dbname = resolve_memory_database_name()
    conn = _open_connection(dbname)
    try:
        result = identify_misplaced_sessions(conn, dbname)
        print(_canonical_json({
            "current_database": result.current_database,
            "current_owner": result.current_owner,
            "peer_misplaced": [asdict(s) for s in result.peer_misplaced],
            "non_peer_wrong_place": [asdict(s) for s in result.non_peer_wrong_place],
            "junk_in_session": [asdict(s) for s in result.junk_in_session],
            "correct_sessions": [asdict(s) for s in result.correct_sessions],
            "total_peer_rows": result.total_peer_rows,
            "total_non_peer_rows": result.total_non_peer_rows,
            "total_junk_rows": result.total_junk_rows,
        }))
    finally:
        conn.close()


def _main_backup_export(output_dir: str) -> None:
    """CLI: identify, backup, and export peer rows.

    Derivation: TC-708-011/012 require that identify, backup, and export all
    read the same database snapshot; otherwise new rows arriving between the
    three phases can make backup and export counts disagree. We run the whole
    sequence inside a single REPEATABLE READ READ ONLY transaction.
    """
    dbname = resolve_memory_database_name()
    conn = _open_connection(dbname)
    try:
        # One snapshot for all three read-only phases. set_session commits any
        # prior transaction on the connection and starts a new one with the
        # requested properties.
        conn.set_session(
            readonly=True,
            isolation_level="REPEATABLE READ",
            autocommit=False,
        )
        ident = identify_misplaced_sessions(conn, dbname)
        out = Path(output_dir)
        backup_manifest = backup_misplaced_rows(conn, ident, out / "backup")
        peer_manifests = export_peer_rows(conn, ident, out / "exports")
        # Read-only transaction: rollback to release the snapshot cleanly.
        conn.rollback()
        print(_canonical_json({
            "backup_manifest": asdict(backup_manifest),
            "peer_manifests": [asdict(m) for m in peer_manifests],
        }))
    finally:
        conn.close()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Cleanup tooling part 1 (#708/#703)")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("identify", help="Identify misplaced sessions")
    p_backup = sub.add_parser("backup-export", help="Backup and export misplaced rows")
    p_backup.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    if args.command == "identify":
        _main_identify()
    elif args.command == "backup-export":
        _main_backup_export(args.output_dir)
    else:
        parser.print_help()
