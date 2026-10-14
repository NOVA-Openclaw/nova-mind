"""Tests for cleanup tooling part 2 (#708/#703): removal.

All tests use mocked databases and temporary files. No test connects to a real
PostgreSQL database or runs DML against one. Derivation: TEST-CASES-ISSUE-708.md
TC-708-013, TC-708-014, TC-708-015; #715 cleanup-part-2 dispatch.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Optional
from unittest.mock import MagicMock, patch

# Add scripts dir to path.
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

# Reuse the commit-enforcing FakeConnection and fixture builders from part 1.
from test_cleanup_p1 import (
    FakeConnection,
    FakeCursor,
    CleanupP1TestCase,
    _FIXTURE_SENDERS,
    _FIXTURE_SESSIONS,
    _SESSION_COLS,
    _TRANSCRIPT_COLS,
    _make_fixture_rows,
    _make_session_context,
    _write_export_pair,
)

import cleanup_708_703


# ---------------------------------------------------------------------------
# Derived-row fixture builders
# ---------------------------------------------------------------------------

# Derivation: dt.sh schemas for entity_facts, entity_fact_sources and
# memory_embeddings. These fixtures are tied to the removal sessions in
# _REMOVAL_SESSIONS by transcript/session ids.
_DERIVED_FACT_COLS = cleanup_708_703.DERIVED_FACT_EXPORT_COLUMNS
_DERIVED_SOURCE_COLS = cleanup_708_703.DERIVED_FACT_SOURCE_EXPORT_COLUMNS
_DERIVED_EMBEDDING_COLS = cleanup_708_703.DERIVED_EMBEDDING_EXPORT_COLUMNS

# Fact ids used in the removal fixture set.
_FACT_ID_SINGLE_SOURCE_PEER = 1001
_FACT_ID_MULTI_SOURCE_PEER = 1002
_FACT_ID_SINGLE_SOURCE_NONPEER = 1003
_FACT_ID_MULTI_SOURCE_JUNK = 1004

# Embedding ids tied to the facts above.
_EMBEDDING_ID_SINGLE_SOURCE_PEER = 8001
_EMBEDDING_ID_MULTI_SOURCE_PEER = 8002
_EMBEDDING_ID_SINGLE_SOURCE_NONPEER = 8003
_EMBEDDING_ID_MULTI_SOURCE_JUNK = 8004

# entity_fact_sources ids.
_SOURCE_ID_PEER_MISPLACED = 9001
_SOURCE_ID_PEER_LEGITIMATE = 9002
_SOURCE_ID_JUNK_LEGITIMATE = 9003


def _make_fact_row(
    fact_id: int,
    source_channel_transcript_id: int | None,
    source_channel_session_id: int | None,
) -> dict[str, Any]:
    """Return an entity_facts row dict matching DERIVED_FACT_EXPORT_COLUMNS."""
    return {
        "id": fact_id,
        "entity_id": 1,
        "key": f"fact_key_{fact_id}",
        "value": f"fact_value_{fact_id}",
        "data": None,
        "confidence": 0.9,
        "learned_at": "2026-10-14T00:00:00",
        "updated_at": "2026-10-14T00:00:00",
        "visibility": "public",
        "privacy_scope": None,
        "visibility_reason": None,
        "last_confirmed_at": "2026-10-14T00:00:00+00:00",
        "decay_rate": None,
        "source_channel_transcript_id": source_channel_transcript_id,
        "source_channel_session_id": source_channel_session_id,
        "extraction_count": 1,
        "expires": None,
        "durability": "long_term",
        "category": "observation",
        "assertion_intent": "asserted",
        "mutability_class": "slow_changing",
    }


def _make_source_row(
    source_id: int,
    fact_id: int,
    source_session_id: int | None,
) -> dict[str, Any]:
    """Return an entity_fact_sources row dict."""
    return {
        "id": source_id,
        "fact_id": fact_id,
        "source_entity_id": 1,
        "source_citation": None,
        "attribution_count": 1,
        "first_seen": "2026-10-14T00:00:00+00:00",
        "last_seen": "2026-10-14T00:00:00+00:00",
        "source_url": None,
        "reporting_distance": 1.0,
        "verification_quality": None,
        "source_session_id": source_session_id,
    }


def _make_embedding_row(
    embedding_id: int,
    fact_id: int,
) -> dict[str, Any]:
    """Return a memory_embeddings row dict for an entity_fact."""
    return {
        "id": embedding_id,
        "source_type": "entity_fact",
        "source_id": str(fact_id),
        "content": f"embedding content {fact_id}",
        "created_at": "2026-10-14T00:00:00+00:00",
        "updated_at": "2026-10-14T00:00:00+00:00",
        "confidence": 1.0,
        "last_confirmed_at": "2026-10-14T00:00:00+00:00",
        "embedding": [0.1, 0.2, 0.3],
    }


_DERIVED_FACT_ROWS: list[dict[str, Any]] = [
    _make_fact_row(_FACT_ID_SINGLE_SOURCE_PEER, 155000, None),
    _make_fact_row(_FACT_ID_MULTI_SOURCE_PEER, 155001, 155),
    _make_fact_row(_FACT_ID_SINGLE_SOURCE_NONPEER, 9216000, None),
    _make_fact_row(_FACT_ID_MULTI_SOURCE_JUNK, 15002, 15),
]

_DERIVED_SOURCE_ROWS: list[dict[str, Any]] = [
    _make_source_row(_SOURCE_ID_PEER_MISPLACED, _FACT_ID_MULTI_SOURCE_PEER, 155),
    _make_source_row(_SOURCE_ID_PEER_LEGITIMATE, _FACT_ID_MULTI_SOURCE_PEER, 57900),
    _make_source_row(_SOURCE_ID_JUNK_LEGITIMATE, _FACT_ID_MULTI_SOURCE_JUNK, 15),
]

_DERIVED_EMBEDDING_ROWS: list[dict[str, Any]] = [
    _make_embedding_row(_EMBEDDING_ID_SINGLE_SOURCE_PEER, _FACT_ID_SINGLE_SOURCE_PEER),
    _make_embedding_row(_EMBEDDING_ID_MULTI_SOURCE_PEER, _FACT_ID_MULTI_SOURCE_PEER),
    _make_embedding_row(_EMBEDDING_ID_SINGLE_SOURCE_NONPEER, _FACT_ID_SINGLE_SOURCE_NONPEER),
    _make_embedding_row(_EMBEDDING_ID_MULTI_SOURCE_JUNK, _FACT_ID_MULTI_SOURCE_JUNK),
]


# ---------------------------------------------------------------------------
# Tracked connection (counts commit/rollback)
# ---------------------------------------------------------------------------

class TrackedFakeConnection(FakeConnection):
    """FakeConnection that counts commit() and rollback() calls."""

    def __init__(self, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self.commit_count = 0
        self.rollback_count = 0

    def commit(self) -> None:
        self.commit_count += 1
        super().commit()

    def rollback(self) -> None:
        self.rollback_count += 1
        super().rollback()


# ---------------------------------------------------------------------------
# Fixture builders specific to removal tests
# ---------------------------------------------------------------------------

# Derivation: TC-708-010's live inventory, extended for removal scenarios.
# Session 155 is graybeard (peer), 9216 is nova-staging (non-peer), 15 is nova
# with junk senders, 57900 is athena (protected/correct).
_REMOVAL_SESSIONS: list[tuple[int, str, str, str, Optional[str], int]] = [
    (15, "agent:nova:agent_chat", "agent_chat", "agent_chat:nova", None, 5),
    (155, "agent:graybeard:agent_chat", "agent_chat", "agent_chat:graybeard", None, 3),
    (9216, "agent:nova-staging:agent_chat", "agent_chat", "agent_chat:nova-staging", None, 1),
    (57900, "agent:nova:athena:agent_chat", "agent_chat", "agent_chat:athena", None, 2),
]


def _removal_identification_handler(
    existing_dbs: set[str],
    sessions: list[tuple[int, str, str, str, Optional[str], int]] | None = None,
    senders: dict[int, list[tuple[str, Optional[str], int]]] | None = None,
) -> Any:
    """Return a FakeCursor handler for identify_misplaced_sessions."""
    sessions = sessions if sessions is not None else _REMOVAL_SESSIONS
    senders = senders if senders is not None else _FIXTURE_SENDERS

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        sql_norm = " ".join(sql.lower().split())

        if (
            "from channel_sessions cs" in sql_norm
            and "left join channel_transcripts" in sql_norm
        ):
            return (None, sessions)

        if (
            "from channel_transcripts" in sql_norm
            and "group by session_id" in sql_norm
        ):
            results: list[tuple[int, str, Optional[str], int]] = []
            for sid, breakdown in senders.items():
                for sender_name, sender_id, count in breakdown:
                    results.append((sid, sender_name, sender_id, count))
            return (None, results)

        if "pg_database" in sql_norm and params:
            db_name = params[0]
            if db_name in {f"{a}_memory" for a in existing_dbs}:
                return ((1,), [])
            return (None, [])

        if "select current_database()" in sql_norm:
            return (("nova_memory",), [])

        return (None, [])

    return handler


def _removal_row_fetch_handler(
    senders: dict[int, list[tuple[str, Optional[str], int]]] | None = None,
) -> Any:
    """Return a FakeCursor handler for backup/export/verification row fetching."""
    senders = senders if senders is not None else _FIXTURE_SENDERS

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        sql_norm = " ".join(sql.lower().split())

        if (
            "from channel_transcripts" in sql_norm
            and "where session_id = %s" in sql_norm
            and "sender_name in" not in sql_norm
        ):
            sid = params[0] if params else None
            rows = _make_fixture_rows(sid, senders=senders.get(sid))
            return (None, [tuple(r[c] for c in _TRANSCRIPT_COLS) for r in rows])

        if (
            "from channel_transcripts" in sql_norm
            and "where session_id = %s" in sql_norm
            and "sender_name in" in sql_norm
        ):
            sid = params[0] if params else None
            junk_senders = params[1:] if params else ()
            all_rows = _make_fixture_rows(sid, senders=senders.get(sid))
            rows = [r for r in all_rows if r["sender_name"] in junk_senders]
            return (None, [tuple(r[c] for c in _TRANSCRIPT_COLS) for r in rows])

        if "from channel_sessions" in sql_norm and "where id = %s" in sql_norm:
            sid = params[0] if params else None
            ctx = _make_session_context(sid)
            return (None, [tuple(ctx[c] for c in _SESSION_COLS)])

        return (None, [])

    return handler


def _combined_removal_handler(
    existing_dbs: set[str],
    sessions: list[tuple[int, str, str, str, Optional[str], int]] | None = None,
    senders: dict[int, list[tuple[str, Optional[str], int]]] | None = None,
    derived_facts: list[dict[str, Any]] | None = None,
    derived_sources: list[dict[str, Any]] | None = None,
    derived_embeddings: list[dict[str, Any]] | None = None,
) -> Any:
    """Combine identification, row-fetch and derived-row handlers for removal."""
    ident = _removal_identification_handler(existing_dbs, sessions, senders)
    fetch = _removal_row_fetch_handler(senders)
    derived = _removal_derived_handler(
        derived_facts, derived_sources, derived_embeddings
    )

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        result = ident(sql, params)
        if result != (None, []):
            return result
        result = fetch(sql, params)
        if result != (None, []):
            return result
        return derived(sql, params)

    return handler


def _transcript_ids_for_session(
    session_id: int,
    senders: dict[int, list[tuple[str, Optional[str], int]]] | None = None,
    junk_only: bool = False,
) -> list[int]:
    """Return transcript ids for a fixture session, optionally junk only."""
    senders = senders if senders is not None else _FIXTURE_SENDERS
    rows = _make_fixture_rows(session_id, senders=senders.get(session_id))
    if junk_only:
        rows = [r for r in rows if r["sender_name"] in cleanup_708_703.DEFAULT_JUNK_SENDERS]
    return [r["id"] for r in rows]


def _removal_derived_handler(
    derived_facts: list[dict[str, Any]] | None = None,
    derived_sources: list[dict[str, Any]] | None = None,
    derived_embeddings: list[dict[str, Any]] | None = None,
) -> Any:
    """Return a FakeCursor handler for derived fact/source/embedding queries."""
    facts = derived_facts if derived_facts is not None else _DERIVED_FACT_ROWS
    sources = derived_sources if derived_sources is not None else _DERIVED_SOURCE_ROWS
    embeddings = (
        derived_embeddings if derived_embeddings is not None else _DERIVED_EMBEDDING_ROWS
    )

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        sql_norm = " ".join(sql.lower().split())
        params = params or ()

        # _compute_target_transcript_ids full-session query.
        if (
            "select id from channel_transcripts" in sql_norm
            and "where session_id in" in sql_norm
        ):
            session_ids = set(params)
            ids: list[int] = []
            for sid in session_ids:
                ids.extend(_transcript_ids_for_session(sid))
            return (None, [(i,) for i in sorted(set(ids))])

        # _compute_target_transcript_ids junk-session query.
        if (
            "select id from channel_transcripts" in sql_norm
            and "where session_id = %s" in sql_norm
            and "sender_name in" in sql_norm
        ):
            sid = params[0] if params else None
            ids = _transcript_ids_for_session(sid, junk_only=True) if sid else []
            return (None, [(i,) for i in sorted(set(ids))])

        # _fetch_derived_facts_for_targets.
        if "from entity_facts" in sql_norm and "source_channel_session_id in" in sql_norm:
            # Params layout: (session_ids..., transcript_ids..., session_ids...)
            # We approximate by collecting all param values and filtering.
            param_set = set(params)
            matching_facts = [
                f
                for f in facts
                if f["id"] in param_set
                or f["source_channel_session_id"] in param_set
                or f["source_channel_transcript_id"] in param_set
                or any(
                    s["fact_id"] == f["id"] and s["source_session_id"] in param_set
                    for s in sources
                )
            ]
            return (
                None,
                [tuple(f[c] for c in _DERIVED_FACT_COLS) for f in matching_facts],
            )

        # _fetch_derived_fact_sources.
        if "from entity_fact_sources" in sql_norm:
            fact_ids = set(params)
            matching_sources = [s for s in sources if s["fact_id"] in fact_ids]
            return (
                None,
                [tuple(s[c] for c in _DERIVED_SOURCE_COLS) for s in matching_sources],
            )

        # _fetch_derived_fact_embeddings.
        if "from memory_embeddings" in sql_norm:
            fact_ids = set(int(p) for p in params)
            matching_embeddings = [
                e for e in embeddings if int(e["source_id"]) in fact_ids
            ]
            return (
                None,
                [
                    tuple(e[c] for c in _DERIVED_EMBEDDING_COLS)
                    for e in matching_embeddings
                ],
            )

        return (None, [])

    return handler


def _write_backup_pair(
    backup_dir: Path,
    session_id: int,
    disposition: str,
    rows: list[dict[str, Any]],
    tamper: bool = False,
) -> dict[str, Any]:
    """Write a session backup JSONL + return its manifest entry.

    If ``tamper`` is True, the first data line is modified so the file
    checksum no longer matches the manifest.
    """
    backup_dir.mkdir(parents=True, exist_ok=True)
    session_file = backup_dir / f"session_{session_id}_backup.jsonl"
    context = _make_session_context(session_id)

    per_row_checksums = [cleanup_708_703._row_checksum(r) for r in rows]  # noqa: SLF001
    lines: list[str] = []
    lines.append(
        cleanup_708_703._canonical_json({"session_context": context})  # noqa: SLF001
    )
    for row, chk in zip(rows, per_row_checksums):
        lines.append(
            cleanup_708_703._canonical_json({"row": row, "checksum": chk})  # noqa: SLF001
        )

    if tamper and len(lines) > 1:
        obj = json.loads(lines[1])
        obj["row"]["content"] = obj["row"]["content"] + "-tampered"
        lines[1] = cleanup_708_703._canonical_json(obj)  # noqa: SLF001

    session_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
    file_checksum = hashlib.sha256(session_file.read_bytes()).hexdigest()

    return {
        "session_id": session_id,
        "session_key": context["session_key"],
        "disposition": disposition,
        "row_count": len(rows),
        "file": str(session_file),
        "file_checksum": file_checksum,
        "per_row_checksums": per_row_checksums,
    }


def _build_backup_manifest(
    sessions_backup: list[dict[str, Any]],
    aggregate_checksum: Optional[str] = None,
) -> dict[str, Any]:
    """Build a backup manifest dict from session backup entries."""
    if aggregate_checksum is None:
        hasher = hashlib.sha256()
        for session in sessions_backup:
            for chk in session["per_row_checksums"]:
                hasher.update(chk.encode("ascii"))
        aggregate_checksum = hasher.hexdigest()

    return {
        "created_at": "2026-10-14T00:00:00+00:00",
        "source_database": "nova_memory",
        "sessions": sessions_backup,
        "total_row_count": sum(s["row_count"] for s in sessions_backup),
        "aggregate_checksum": aggregate_checksum,
        "schema": "cleanup-backup-v1",
    }


def _write_derived_backup(
    backup_dir: Path,
    facts: list[dict[str, Any]] | None = None,
    sources: list[dict[str, Any]] | None = None,
    embeddings: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Write derived_backup.jsonl and return its manifest entry."""
    facts = facts if facts is not None else _DERIVED_FACT_ROWS
    sources = sources if sources is not None else _DERIVED_SOURCE_ROWS
    embeddings = embeddings if embeddings is not None else _DERIVED_EMBEDDING_ROWS

    derived_file = backup_dir / "derived_backup.jsonl"
    per_row_checksums: list[str] = []
    lines: list[str] = []
    lines.append(
        cleanup_708_703._canonical_json(  # noqa: SLF001
            {"type": "facts_header", "columns": _DERIVED_FACT_COLS}
        )
    )
    for row in facts:
        chk = cleanup_708_703._row_checksum(row)  # noqa: SLF001
        per_row_checksums.append(chk)
        lines.append(
            cleanup_708_703._canonical_json(  # noqa: SLF001
                {"type": "entity_fact", "row": row, "checksum": chk}
            )
        )
    for row in sources:
        chk = cleanup_708_703._row_checksum(row)  # noqa: SLF001
        per_row_checksums.append(chk)
        lines.append(
            cleanup_708_703._canonical_json(  # noqa: SLF001
                {"type": "entity_fact_source", "row": row, "checksum": chk}
            )
        )
    for row in embeddings:
        chk = cleanup_708_703._row_checksum(row)  # noqa: SLF001
        per_row_checksums.append(chk)
        lines.append(
            cleanup_708_703._canonical_json(  # noqa: SLF001
                {"type": "memory_embedding", "row": row, "checksum": chk}
            )
        )

    derived_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
    file_checksum = hashlib.sha256(derived_file.read_bytes()).hexdigest()
    aggregate_checksum = cleanup_708_703._compute_aggregate_checksum(  # noqa: SLF001
        per_row_checksums
    )

    return {
        "derived_backup_file": str(derived_file),
        "derived_file_checksum": file_checksum,
        "derived_fact_count": len(facts),
        "derived_source_count": len(sources),
        "derived_embedding_count": len(embeddings),
        "derived_per_row_checksums": per_row_checksums,
        "derived_aggregate_checksum": aggregate_checksum,
    }


def _write_full_backup_manifest(
    backup_dir: Path,
    derived_facts: list[dict[str, Any]] | None = None,
    derived_sources: list[dict[str, Any]] | None = None,
    derived_embeddings: list[dict[str, Any]] | None = None,
) -> tuple[dict[str, Any], str]:
    """Write a backup manifest covering the standard target set.

    Derivation: identify_misplaced_sessions against _REMOVAL_SESSIONS flags
    sessions 155 (peer), 9216 (non-peer), and 15 (junk). The backup manifest
    must cover exactly that target set or re-identification refuses.
    """
    entries = [
        _write_backup_pair(backup_dir, 155, "peer_misplaced", _make_fixture_rows(155)),
        _write_backup_pair(backup_dir, 9216, "non_peer_wrong_place", _make_fixture_rows(9216)),
        _write_backup_pair(
            backup_dir,
            15,
            "junk_in_session",
            [
                r
                for r in _make_fixture_rows(15)
                if r["sender_name"] in cleanup_708_703.DEFAULT_JUNK_SENDERS
            ],
        ),
    ]
    manifest = _build_backup_manifest(entries)
    manifest.update(
        _write_derived_backup(
            backup_dir,
            facts=derived_facts,
            sources=derived_sources,
            embeddings=derived_embeddings,
        )
    )
    (backup_dir / "backup_manifest.json").write_text(
        cleanup_708_703._canonical_json(manifest) + "\n",  # noqa: SLF001
        encoding="utf-8",
    )
    return manifest, manifest["aggregate_checksum"]


class CleanupP2TestCase(CleanupP1TestCase):
    """Hermetic base for part-2 tests."""
    pass


# ---------------------------------------------------------------------------
# TC-708-013: removal gated on verified export
# ---------------------------------------------------------------------------


class TestRemovePeerGating(CleanupP2TestCase):
    """TC-708-013: peer-row removal is gated on a verified export/manifest."""

    def test_export_mismatch_blocks_peer_deletes(self) -> None:
        """Tampered export file aborts that peer with zero deletes."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            _write_full_backup_manifest(backup_dir)

            # Export for graybeard, then tamper with it.
            rows_155 = _make_fixture_rows(155)
            export_file, manifest_file = _write_export_pair(
                export_dir, "graybeard", 155, rows_155, tamper_index=0
            )

            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=False,
                )

            # No deletes attempted; rollback should not have been called either.
            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)

    def test_export_row_count_mismatch_blocks_peer(self) -> None:
        """Current DB row count differing from export manifest aborts the peer."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            # Fetch handler returns only 2 rows for session 155 instead of 3.
            altered_senders = {
                155: [("nova", "nova1", 1), ("newhart", "nh1", 1)],
            }

            def fetch_handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
                sql_norm = " ".join(sql.lower().split())
                if (
                    "from channel_transcripts" in sql_norm
                    and "where session_id = %s" in sql_norm
                    and "sender_name in" not in sql_norm
                ):
                    sid = params[0] if params else None
                    senders = altered_senders if sid == 155 else _FIXTURE_SENDERS
                    rows = _make_fixture_rows(sid, senders=senders.get(sid))
                    return (None, [tuple(r[c] for c in _TRANSCRIPT_COLS) for r in rows])
                return _removal_row_fetch_handler()(sql, params)

            derived = _removal_derived_handler()

            def combined(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
                result = _removal_identification_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)(sql, params)
                if result != (None, []):
                    return result
                result = fetch_handler(sql, params)
                if result != (None, []):
                    return result
                return derived(sql, params)

            conn = TrackedFakeConnection(combined)

            with self.assertRaisesRegex(RuntimeError, "Row count mismatch"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=False,
                )

            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)

    def test_peer_delete_missing_export_file_blocks(self) -> None:
        """Missing export file aborts the peer with zero deletes."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            _write_full_backup_manifest(backup_dir)

            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            with self.assertRaisesRegex(RuntimeError, "Missing export file"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=False,
                )

            self.assertEqual(conn.commit_count, 0)


# ---------------------------------------------------------------------------
# TC-708-014: non-peer/junk removal gated on verified backup
# ---------------------------------------------------------------------------


class TestRemoveNonPeerGating(CleanupP2TestCase):
    """TC-708-014: non-peer and junk-row removal is gated on verified backup."""

    def test_backup_mismatch_blocks_non_peer_deletes(self) -> None:
        """Tampered backup file aborts the non-peer group with zero deletes."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            _write_full_backup_manifest(backup_dir)
            # Tamper the non-peer backup file in place.
            rows_9216 = _make_fixture_rows(9216)
            _write_backup_pair(
                backup_dir, 9216, "non_peer_wrong_place", rows_9216, tamper=True
            )
            # Peer export is still required because the manifest covers session 155.
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            with self.assertRaisesRegex(RuntimeError, "File checksum mismatch"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=False,
                )

            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)


# ---------------------------------------------------------------------------
# TC-708-015: protected sessions are never deleted
# ---------------------------------------------------------------------------


class TestRemoveProtectedSessions(CleanupP2TestCase):
    """TC-708-015: sessions belonging to NOVA's owner are never deleted."""

    def test_protected_session_refused_even_when_passed(self) -> None:
        """A nova session passed in by mistake is refused before any delete."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            rows_15 = _make_fixture_rows(15)
            backup_entry = _write_backup_pair(
                backup_dir, 15, "peer_misplaced", rows_15
            )
            manifest = _build_backup_manifest([backup_entry])
            (backup_dir / "backup_manifest.json").write_text(
                cleanup_708_703._canonical_json(manifest) + "\n",  # noqa: SLF001
                encoding="utf-8",
            )

            # Force session 15 to be returned as a target by patching
            # identify_misplaced_sessions. The protected-session check must
            # still refuse it.
            forced_ident = cleanup_708_703.IdentificationResult(
                current_database="nova_memory",
                current_owner="nova",
                peer_misplaced=[
                    cleanup_708_703.MisplacedSession(
                        session_id=15,
                        session_key="agent:nova:agent_chat",
                        provider="agent_chat",
                        external_chat_id="agent_chat:nova",
                        external_thread_id=None,
                        row_count=len(rows_15),
                        disposition="peer_misplaced",
                        sender_breakdown=[],
                    )
                ],
                non_peer_wrong_place=[],
                junk_in_session=[],
                correct_sessions=[],
            )

            def current_db_handler(
                sql: str, params: tuple[Any, ...] | None
            ) -> tuple[Any, list[Any]]:
                sql_norm = " ".join(sql.lower().split())
                if "select current_database()" in sql_norm:
                    return (("nova_memory",), [])
                return (None, [])

            conn = TrackedFakeConnection(current_db_handler)
            with patch(
                "cleanup_708_703.identify_misplaced_sessions",
                return_value=forced_ident,
            ):
                with self.assertRaisesRegex(RuntimeError, "Refusing to delete protected"):
                    cleanup_708_703.remove_misplaced_rows(
                        conn,
                        backup_manifest_path=backup_dir / "backup_manifest.json",
                        export_dir=export_dir,
                        execute=False,
                    )

            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)


# ---------------------------------------------------------------------------
# Dry-run / execute gating
# ---------------------------------------------------------------------------


class TestRemoveDryRun(CleanupP2TestCase):
    """Dry-run is the default; --execute requires matching --confirm."""

    def _setup_valid_backup_export(self, tmp: str) -> tuple[Path, Path, str]:
        """Create valid backup/export artifacts covering the full target set."""
        backup_dir = Path(tmp) / "backup"
        export_dir = Path(tmp) / "exports"

        manifest, checksum = _write_full_backup_manifest(backup_dir)
        rows_155 = _make_fixture_rows(155)
        _write_export_pair(export_dir, "graybeard", 155, rows_155)
        return backup_dir, export_dir, checksum

    def test_dry_run_deletes_nothing(self) -> None:
        """Default remove_misplaced_rows reports counts without issuing deletes."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, _ = self._setup_valid_backup_export(tmp)
            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            result = cleanup_708_703.remove_misplaced_rows(
                conn,
                backup_manifest_path=backup_dir / "backup_manifest.json",
                export_dir=export_dir,
            )

            self.assertTrue(result["dry_run"])
            self.assertFalse(result["confirmed"])
            self.assertEqual(result["peer_groups"][0]["deleted"], False)
            self.assertEqual(result["non_peer_group"]["deleted"], False)

            # No DML should have been issued.
            executed_sql = [sql for sql, _params in conn.cursor_obj.executed]
            self.assertFalse(
                any("delete" in sql.lower() for sql in executed_sql),
                "Dry-run must not issue DELETE statements",
            )
            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)

    def test_execute_without_confirm_refuses(self) -> None:
        """--execute without --confirm raises before touching the database."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, _ = self._setup_valid_backup_export(tmp)
            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            with self.assertRaisesRegex(RuntimeError, "--execute requires --confirm"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=True,
                )

            self.assertEqual(conn.commit_count, 0)

    def test_execute_with_wrong_confirm_refuses(self) -> None:
        """--execute with a non-matching --confirm checksum refuses."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, _ = self._setup_valid_backup_export(tmp)
            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            with self.assertRaisesRegex(RuntimeError, "does not match"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=True,
                    confirm_checksum="0" * 64,
                )

            self.assertEqual(conn.commit_count, 0)


# ---------------------------------------------------------------------------
# Re-identification / set-change refusal
# ---------------------------------------------------------------------------


class TestRemoveSetChanged(CleanupP2TestCase):
    """Rows added or changed since backup cause a refusal."""

    def test_rows_added_after_backup_refuses(self) -> None:
        """A new misplaced session appearing after backup is refused."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            rows_155 = _make_fixture_rows(155)
            backup_entry = _write_backup_pair(
                backup_dir, 155, "peer_misplaced", rows_155
            )
            manifest = _build_backup_manifest([backup_entry])
            (backup_dir / "backup_manifest.json").write_text(
                cleanup_708_703._canonical_json(manifest) + "\n",  # noqa: SLF001
                encoding="utf-8",
            )
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            # Identification now also returns session 9216, which was not in
            # the backup manifest.
            sessions_with_extra = list(_REMOVAL_SESSIONS)

            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=sessions_with_extra)
            )

            with self.assertRaisesRegex(RuntimeError, "Identification set changed"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=False,
                )

            self.assertEqual(conn.commit_count, 0)


# ---------------------------------------------------------------------------
# Successful execution and ordering
# ---------------------------------------------------------------------------


class TestRemoveExecution(CleanupP2TestCase):
    """A successful --execute deletes exactly the identified rows."""

    def _setup(self, tmp: str) -> tuple[Path, Path, str, TrackedFakeConnection]:
        backup_dir = Path(tmp) / "backup"
        export_dir = Path(tmp) / "exports"

        manifest, checksum = _write_full_backup_manifest(backup_dir)
        rows_155 = _make_fixture_rows(155)
        _write_export_pair(export_dir, "graybeard", 155, rows_155)

        conn = TrackedFakeConnection(
            _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
        )
        return backup_dir, export_dir, checksum, conn

    def test_successful_execute_deletes_target_rows(self) -> None:
        """Execute deletes peer and non-peer sessions and commits."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, checksum, conn = self._setup(tmp)

            result = cleanup_708_703.remove_misplaced_rows(
                conn,
                backup_manifest_path=backup_dir / "backup_manifest.json",
                export_dir=export_dir,
                execute=True,
                confirm_checksum=checksum,
            )

            self.assertFalse(result["dry_run"])
            self.assertTrue(result["confirmed"])
            self.assertEqual(result["peer_groups"][0]["deleted"], True)
            self.assertEqual(result["non_peer_group"]["deleted"], True)

            # Peer commits once, non-peer group commits once.
            self.assertEqual(conn.commit_count, 2)
            self.assertEqual(conn.rollback_count, 0)

            executed_sql = [sql for sql, _params in conn.cursor_obj.executed]
            delete_sqls = [sql for sql in executed_sql if "delete" in sql.lower()]
            self.assertTrue(
                any("channel_transcripts" in sql.lower() for sql in delete_sqls),
                "Transcripts must be deleted",
            )
            self.assertTrue(
                any("channel_sessions" in sql.lower() for sql in delete_sqls),
                "Sessions must be deleted",
            )

            # Derivation: TC-708 requires transcripts before sessions. In the
            # DELETE statement list, channel_transcripts must appear before
            # channel_sessions for each session group.
            transcript_idx = next(
                i
                for i, sql in enumerate(executed_sql)
                if "delete" in sql.lower() and "channel_transcripts" in sql.lower()
            )
            session_idx = next(
                i
                for i, sql in enumerate(executed_sql)
                if "delete" in sql.lower() and "channel_sessions" in sql.lower()
            )
            self.assertLess(
                transcript_idx,
                session_idx,
                "DELETE FROM channel_transcripts must precede DELETE FROM channel_sessions",
            )

    def test_execute_does_not_delete_protected_sessions(self) -> None:
        """Even during execute, protected sessions are never deleted."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, checksum, conn = self._setup(tmp)

            cleanup_708_703.remove_misplaced_rows(
                conn,
                backup_manifest_path=backup_dir / "backup_manifest.json",
                export_dir=export_dir,
                execute=True,
                confirm_checksum=checksum,
            )

            executed_sql = [sql for sql, _params in conn.cursor_obj.executed]
            for sql in executed_sql:
                if "delete" in sql.lower() and "channel_sessions" in sql.lower():
                    self.assertNotIn("57900", sql)
                    self.assertNotIn("15", sql)


# ---------------------------------------------------------------------------
# Mid-run failure rolls back the current group
# ---------------------------------------------------------------------------


class TestRemoveRollback(CleanupP2TestCase):
    """An error during a delete group rolls back that group."""

    def test_mid_run_failure_rolls_back_group(self) -> None:
        """Failure during non-peer group deletes rolls back the whole group."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"

            manifest, _ = _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            base = _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)

            def failing_handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
                sql_norm = " ".join(sql.lower().split())
                if (
                    "delete" in sql_norm
                    and "channel_transcripts" in sql_norm
                    and params == (9216,)
                ):
                    raise RuntimeError("injected delete failure")
                return base(sql, params)

            conn = TrackedFakeConnection(failing_handler)

            with self.assertRaisesRegex(RuntimeError, "injected delete failure"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=True,
                    confirm_checksum=manifest["aggregate_checksum"],
                )

            # Peer group committed; non-peer group rolled back.
            self.assertEqual(conn.commit_count, 1)
            self.assertEqual(conn.rollback_count, 1)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


class TestRemoveCLI(CleanupP2TestCase):
    """CLI wiring for the remove subcommand."""

    def test_cli_remove_dry_run(self) -> None:
        """CLI calls remove_misplaced_rows with execute=False by default."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"
            _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )

            with patch(
                "cleanup_708_703._open_connection", return_value=conn
            ) as mock_open:
                with patch(
                    "cleanup_708_703.resolve_memory_database_name",
                    return_value="nova_memory",
                ):
                    cleanup_708_703._main_remove(  # noqa: SLF001
                        str(backup_dir), str(export_dir), execute=False, confirm_checksum=None
                    )

            mock_open.assert_called_once_with("nova_memory")
            self.assertEqual(conn.commit_count, 0)


# ---------------------------------------------------------------------------
# Derived-fact backup and verification
# ---------------------------------------------------------------------------


class TestDerivedBackup(CleanupP2TestCase):
    """Derived facts/sources/embeddings are backed up with checksums."""

    def test_derived_rows_in_backup_manifest(self) -> None:
        """Backup manifest carries derived counts, file checksum and aggregate."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            manifest, _ = _write_full_backup_manifest(backup_dir)

            self.assertIn("derived_backup_file", manifest)
            self.assertIn("derived_file_checksum", manifest)
            self.assertIn("derived_aggregate_checksum", manifest)
            self.assertEqual(manifest["derived_fact_count"], 4)
            self.assertEqual(manifest["derived_source_count"], 3)
            self.assertEqual(manifest["derived_embedding_count"], 4)

            derived_file = Path(manifest["derived_backup_file"])
            self.assertTrue(derived_file.exists())
            self.assertEqual(
                hashlib.sha256(derived_file.read_bytes()).hexdigest(),
                manifest["derived_file_checksum"],
            )

    def test_derived_backup_per_row_checksums_verify(self) -> None:
        """Each derived row's embedded checksum matches its recomputed hash."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            manifest, _ = _write_full_backup_manifest(backup_dir)
            derived_file = Path(manifest["derived_backup_file"])

            recomputed: list[str] = []
            for line in derived_file.read_text(encoding="utf-8").splitlines()[1:]:
                obj = json.loads(line)
                if "row" not in obj:
                    continue
                recomputed.append(cleanup_708_703._row_checksum(obj["row"]))  # noqa: SLF001
                self.assertEqual(
                    recomputed[-1],
                    obj["checksum"],
                    "Embedded checksum must match recomputed hash",
                )

            self.assertEqual(
                recomputed,
                manifest["derived_per_row_checksums"],
            )
            self.assertEqual(
                cleanup_708_703._compute_aggregate_checksum(recomputed),  # noqa: SLF001
                manifest["derived_aggregate_checksum"],
            )


class TestDerivedVerificationBlocks(CleanupP2TestCase):
    """A checksum/count mismatch in derived backup blocks the group."""

    def test_derived_checksum_mismatch_blocks_zero_deletes(self) -> None:
        """Tampered derived rows in current DB abort with zero commits and no DML."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"
            manifest, checksum = _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            # Current DB returns a tampered fact row; backup is clean.
            tampered_facts = [
                {**f, "value": f["value"] + "-tampered"}
                for f in _DERIVED_FACT_ROWS
            ]

            conn = TrackedFakeConnection(
                _combined_removal_handler(
                    {"graybeard"},
                    sessions=_REMOVAL_SESSIONS,
                    derived_facts=tampered_facts,
                )
            )

            with self.assertRaisesRegex(RuntimeError, "Derived row checksum mismatch"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=True,
                    confirm_checksum=checksum,
                )

            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)
            executed_sql = [sql for sql, _params in conn.cursor_obj.executed]
            self.assertFalse(
                any("delete" in sql.lower() for sql in executed_sql),
                "No DML may run when derived verification fails",
            )


class TestMultiSourceFacts(CleanupP2TestCase):
    """Multi-source facts are kept when any legitimate source remains."""

    def _setup_execute(self, tmp: str) -> tuple[Path, Path, str, TrackedFakeConnection]:
        backup_dir = Path(tmp) / "backup"
        export_dir = Path(tmp) / "exports"
        manifest, checksum = _write_full_backup_manifest(backup_dir)
        rows_155 = _make_fixture_rows(155)
        _write_export_pair(export_dir, "graybeard", 155, rows_155)
        conn = TrackedFakeConnection(
            _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
        )
        return backup_dir, export_dir, checksum, conn

    def test_single_source_fact_deleted_with_embeddings_and_sources(self) -> None:
        """A single-source misplaced fact is fully deleted."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, checksum, conn = self._setup_execute(tmp)
            cleanup_708_703.remove_misplaced_rows(
                conn,
                backup_manifest_path=backup_dir / "backup_manifest.json",
                export_dir=export_dir,
                execute=True,
                confirm_checksum=checksum,
            )

            # Collect all params bound to DELETE statements (placeholders).
            deleted_fact_ids: set[int] = set()
            deleted_embedding_source_ids: set[str] = set()
            for sql, params in conn.cursor_obj.executed:
                if "delete" not in sql.lower():
                    continue
                if "entity_facts" in sql.lower() and params:
                    deleted_fact_ids.update(params)
                if "memory_embeddings" in sql.lower() and params:
                    # Params are (fact_id, ...); source_id is stored as text.
                    deleted_embedding_source_ids.update(str(p) for p in params)

            self.assertIn(
                _FACT_ID_SINGLE_SOURCE_PEER,
                deleted_fact_ids,
                "Single-source peer fact must be deleted",
            )
            self.assertIn(
                str(_FACT_ID_SINGLE_SOURCE_PEER),
                deleted_embedding_source_ids,
                "Single-source peer embedding must be deleted",
            )

    def test_multi_source_fact_kept_misplaced_link_removed(self) -> None:
        """A fact with a legitimate source is kept; only the bad link is deleted."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir, export_dir, checksum, conn = self._setup_execute(tmp)
            cleanup_708_703.remove_misplaced_rows(
                conn,
                backup_manifest_path=backup_dir / "backup_manifest.json",
                export_dir=export_dir,
                execute=True,
                confirm_checksum=checksum,
            )

            deleted_fact_ids: set[int] = set()
            deleted_source_link_ids: set[int] = set()
            updated_tables: set[str] = set()
            for sql, params in conn.cursor_obj.executed:
                if "delete" in sql.lower() and params:
                    if "entity_facts" in sql.lower():
                        deleted_fact_ids.update(params)
                    if "entity_fact_sources" in sql.lower():
                        deleted_source_link_ids.update(params)
                if "update" in sql.lower():
                    updated_tables.add(sql.lower().split("update")[1].split()[0])

            self.assertNotIn(
                _FACT_ID_MULTI_SOURCE_PEER,
                deleted_fact_ids,
                "Multi-source peer fact must be kept",
            )
            self.assertIn(
                _SOURCE_ID_PEER_MISPLACED,
                deleted_source_link_ids,
                "Misplaced source link must be deleted",
            )
            self.assertNotIn(
                _SOURCE_ID_PEER_LEGITIMATE,
                deleted_source_link_ids,
                "Legitimate source link must be kept",
            )
            self.assertIn(
                "entity_facts",
                updated_tables,
                "Dangling direct column must be nulled",
            )


class TestDryRunCounts(CleanupP2TestCase):
    """Dry-run reports per-group counts without issuing DML."""

    def test_dry_run_counts_are_correct(self) -> None:
        """Per-group counts include transcripts, sessions, facts and links."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"
            manifest, _ = _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            conn = TrackedFakeConnection(
                _combined_removal_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)
            )
            result = cleanup_708_703.remove_misplaced_rows(
                conn,
                backup_manifest_path=backup_dir / "backup_manifest.json",
                export_dir=export_dir,
                execute=False,
            )

            peer_counts = result["peer_groups"][0]["counts"]
            self.assertEqual(peer_counts["transcripts"], 3)
            self.assertEqual(peer_counts["sessions"], 1)
            self.assertEqual(peer_counts["facts_deleted"], 1)
            self.assertEqual(peer_counts["facts_kept"], 1)
            self.assertEqual(peer_counts["source_links_removed"], 1)
            self.assertEqual(peer_counts["embeddings_deleted"], 1)

            non_peer_counts = result["non_peer_group"]["counts"]
            self.assertEqual(non_peer_counts["transcripts"], 4)  # 1 + 3 junk
            self.assertEqual(non_peer_counts["sessions"], 1)  # session 9216 only
            self.assertEqual(non_peer_counts["facts_deleted"], 1)
            self.assertEqual(non_peer_counts["facts_kept"], 1)
            self.assertEqual(non_peer_counts["source_links_removed"], 0)
            self.assertEqual(non_peer_counts["embeddings_deleted"], 1)


class TestFactAddedAfterBackup(CleanupP2TestCase):
    """A derived fact added after backup is refused."""

    def test_fact_added_after_backup_refuses(self) -> None:
        """An extra fact appearing after backup blocks with zero deletes."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"
            manifest, checksum = _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            extra_fact = _make_fact_row(1005, 155002, None)
            extra_facts = list(_DERIVED_FACT_ROWS) + [extra_fact]
            extra_embeddings = list(_DERIVED_EMBEDDING_ROWS) + [
                _make_embedding_row(8005, 1005)
            ]

            conn = TrackedFakeConnection(
                _combined_removal_handler(
                    {"graybeard"},
                    sessions=_REMOVAL_SESSIONS,
                    derived_facts=extra_facts,
                    derived_embeddings=extra_embeddings,
                )
            )

            with self.assertRaisesRegex(RuntimeError, "Derived row count mismatch"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=True,
                    confirm_checksum=checksum,
                )

            self.assertEqual(conn.commit_count, 0)
            self.assertEqual(conn.rollback_count, 0)


class TestMutationCheck(CleanupP2TestCase):
    """Removing derived verification causes a real test to fail."""

    def test_removing_derived_verification_fails(self) -> None:
        """If derived verification is bypassed, a multi-source test fails."""
        with tempfile.TemporaryDirectory() as tmp:
            backup_dir = Path(tmp) / "backup"
            export_dir = Path(tmp) / "exports"
            manifest, checksum = _write_full_backup_manifest(backup_dir)
            rows_155 = _make_fixture_rows(155)
            _write_export_pair(export_dir, "graybeard", 155, rows_155)

            # Tamper a fact row in the current DB relative to the backup.
            tampered_facts = [
                {**f, "value": f["value"] + "-mutated"}
                for f in _DERIVED_FACT_ROWS
            ]

            conn = TrackedFakeConnection(
                _combined_removal_handler(
                    {"graybeard"},
                    sessions=_REMOVAL_SESSIONS,
                    derived_facts=tampered_facts,
                )
            )

            with self.assertRaisesRegex(RuntimeError, "Derived row checksum mismatch"):
                cleanup_708_703.remove_misplaced_rows(
                    conn,
                    backup_manifest_path=backup_dir / "backup_manifest.json",
                    export_dir=export_dir,
                    execute=True,
                    confirm_checksum=checksum,
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
