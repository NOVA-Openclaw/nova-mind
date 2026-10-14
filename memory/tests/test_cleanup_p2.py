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
) -> Any:
    """Combine identification and row-fetch handlers for end-to-end removal."""
    ident = _removal_identification_handler(existing_dbs, sessions, senders)
    fetch = _removal_row_fetch_handler(senders)

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        result = ident(sql, params)
        if result != (None, []):
            return result
        return fetch(sql, params)

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


def _write_full_backup_manifest(backup_dir: Path) -> tuple[dict[str, Any], str]:
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

            def combined(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
                result = _removal_identification_handler({"graybeard"}, sessions=_REMOVAL_SESSIONS)(sql, params)
                if result != (None, []):
                    return result
                return fetch_handler(sql, params)

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
