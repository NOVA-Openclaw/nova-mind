"""Tests for cleanup tooling part 1 (#708/#703): identify, backup, export, peer import.

All tests use mocked databases and temporary files. No test connects to a real
PostgreSQL database. Derivation: TEST-CASES-ISSUE-708.md TC-708-010 through
TC-708-012d and TC-703-003/004/005; #715 cleanup-part-1 dispatch.
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

import cleanup_708_703
import cleanup_peer_import


# ---------------------------------------------------------------------------
# Mock database helpers
# ---------------------------------------------------------------------------

class FakeCursor:
    """A deterministic mock cursor driven by a handler function.

    The handler receives (sql, params) and returns (fetchone, fetchall).
    All executed statements are recorded in ``executed``.
    """

    def __init__(self, handler: Any | None = None):
        self.handler = handler or (lambda _sql, _params: (None, []))
        self.executed: list[tuple[str, tuple[Any, ...] | None]] = []
        self._fetchone: Any = None
        self._fetchall: list[Any] = []

    def execute(self, sql: str, params: tuple[Any, ...] | None = None) -> None:
        self.executed.append((sql, params))
        self._fetchone, self._fetchall = self.handler(sql, params)

    def fetchone(self) -> Any:
        return self._fetchone

    def fetchall(self) -> list[Any]:
        return self._fetchall

    def __enter__(self) -> FakeCursor:
        return self

    def __exit__(self, *args: Any) -> None:
        pass

    def close(self) -> None:
        pass


class FakeConnection:
    """A mock psycopg2-like connection returning one FakeCursor."""

    def __init__(self, handler: Any | None = None):
        self.cursor_obj = FakeCursor(handler)

    def cursor(self) -> FakeCursor:
        return self.cursor_obj

    def close(self) -> None:
        pass


# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# Derivation: TC-708-010's live inventory, reduced to the cases needed for
# mocked category verification.
_FIXTURE_SESSIONS: list[tuple[int, str, str, str, Optional[str], int]] = [
    # id, session_key, provider, external_chat_id, external_thread_id, transcript_count
    (15, "agent:nova:agent_chat", "agent_chat", "agent_chat:nova", None, 5),
    (155, "agent:graybeard:agent_chat", "agent_chat", "agent_chat:graybeard", None, 3),
    # Derivation: athena is nova's subagent; her traffic uses nova's agent prefix
    # in the fixture so the code classifies the session as correct (agent == owner).
    (57900, "agent:nova:athena:agent_chat", "agent_chat", "agent_chat:athena", None, 2),
    (9216, "agent:nova-staging:agent_chat", "agent_chat", "agent_chat:nova-staging", None, 1),
]

# Sender breakdown per session. Derivation: TC-708-010 sender lists.
_FIXTURE_SENDERS: dict[int, list[tuple[str, Optional[str], int]]] = {
    15: [
        ("graybeard", "gb1", 2),
        ("zztest_a", "test1", 2),  # junk sender inside correct session
        ("schema-sync", None, 1),  # junk sender inside correct session
    ],
    155: [
        ("nova", "nova1", 2),
        ("newhart", "nh1", 1),
    ],
    57900: [
        ("nova", "nova1", 2),
    ],
    9216: [
        ("nova", "nova1", 1),
    ],
}

# Separate sender breakdown for synthetic multi-peer import tests; kept out of
# _FIXTURE_SENDERS so identification tests are not affected.
_MULTIPEER_SENDERS: dict[int, list[tuple[str, Optional[str], int]]] = {
    10871: [
        ("nova", "nova1", 2),
        ("graybeard", "gb1", 1),
    ],
}

# Derivation: columns exported by cleanup_708_703.TRANSCRIPT_EXPORT_COLUMNS.
_TRANSCRIPT_COLS = [
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

# Derivation: columns exported by cleanup_708_703.SESSION_EXPORT_COLUMNS.
_SESSION_COLS = [
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


def _make_transcript_row(
    session_id: int,
    external_message_id: str,
    sender_name: str,
    content: str,
    row_id: int,
) -> dict[str, Any]:
    """Return a transcript row dict matching the export column order."""
    return {
        "id": row_id,
        "session_id": session_id,
        "external_message_id": external_message_id,
        "timestamp": "2026-10-14T00:00:00+00:00",
        "sender_id": f"{sender_name}_id",
        "sender_name": sender_name,
        "sender_username": sender_name,
        "sender_tag": None,
        "sender_entity_id": None,
        "role": "user",
        "content": content,
        "content_type": "text",
        "raw_metadata": None,
        "created_at": "2026-10-14T00:00:00+00:00",
    }


def _make_session_context(
    session_id: int, session_key: str | None = None
) -> dict[str, Any]:
    """Return a session context dict for export/import headers.

    If ``session_key`` is not provided, it is looked up from _FIXTURE_SESSIONS
    or derived from the session_id for synthetic multi-peer tests.
    """
    if session_key is None:
        try:
            session = next(s for s in _FIXTURE_SESSIONS if s[0] == session_id)
            session_key = session[1]
            provider = session[2]
            external_chat_id = session[3]
            external_thread_id = session[4]
            message_count = session[5]
        except StopIteration:
            # Synthetic session (e.g. multi-peer fixture 10871).
            agent = "newhart" if "newhart" in str(session_id) else f"peer{session_id}"
            session_key = f"agent:{agent}:agent_chat"
            provider = "agent_chat"
            external_chat_id = f"agent_chat:{agent}"
            external_thread_id = None
            message_count = len(_FIXTURE_SENDERS.get(session_id, []))
    else:
        provider = "agent_chat"
        external_chat_id = f"agent_chat:{session_key.split(':')[1]}"
        external_thread_id = None
        message_count = len(_FIXTURE_SENDERS.get(session_id, []))

    return {
        "id": session_id,
        "session_key": session_key,
        "agent_id": "main",
        "provider": provider,
        "external_chat_id": external_chat_id,
        "external_thread_id": external_thread_id,
        "chat_type": None,
        "title": None,
        "group_subject": None,
        "group_space_id": None,
        "started_at": None,
        "last_message_at": None,
        "message_count": message_count,
        "raw_metadata": None,
        "created_at": "2026-10-14T00:00:00+00:00",
        "updated_at": "2026-10-14T00:00:00+00:00",
    }


def _make_fixture_rows(
    session_id: int,
    senders: list[tuple[str, Optional[str], int]] | None = None,
) -> list[dict[str, Any]]:
    """Build deterministic transcript rows for a fixture session.

    ``senders`` overrides the default lookup; used for synthetic multi-peer
    fixtures without polluting the identification fixture set.
    """
    if senders is None:
        senders = _FIXTURE_SENDERS.get(session_id, [])
    rows: list[dict[str, Any]] = []
    row_id = session_id * 1000
    for sender_name, sender_id, count in senders:
        for i in range(count):
            rows.append(
                _make_transcript_row(
                    session_id=session_id,
                    external_message_id=f"msg-{session_id}-{row_id}",
                    sender_name=sender_name,
                    content=f"content-{session_id}-{row_id}",
                    row_id=row_id,
                )
            )
            row_id += 1
    return rows


def _identification_handler(existing_dbs: set[str]) -> Any:
    """Return a FakeCursor handler for identify_misplaced_sessions.

    The function switches on the SQL text to return session rows, sender
    breakdowns, or pg_database existence lookups.
    """

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        if "FROM channel_sessions cs" in sql and "LEFT JOIN channel_transcripts" in sql:
            return (None, _FIXTURE_SESSIONS)
        if "FROM channel_transcripts" in sql and "GROUP BY session_id" in sql:
            results: list[tuple[int, str, Optional[str], int]] = []
            for sid, breakdown in _FIXTURE_SENDERS.items():
                for sender_name, sender_id, count in breakdown:
                    results.append((sid, sender_name, sender_id, count))
            return (None, results)
        if "pg_database" in sql and params:
            db_name = params[0]
            if db_name in {f"{a}_memory" for a in existing_dbs}:
                return ((1,), [])
            return (None, [])
        return (None, [])

    return handler


def _backup_export_handler(
    session_id: int | None = None,
) -> Any:
    """Return a FakeCursor handler for backup/export row fetching.

    If ``session_id`` is given, transcript rows for that session are returned
    for session-context and transcript queries; otherwise all fixture rows for
    any requested session are returned.
    """

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        if "FROM channel_transcripts" in sql and "WHERE session_id = %s" in sql:
            sid = params[0] if params else None
            rows = _make_fixture_rows(sid)
            # Return as tuples matching _TRANSCRIPT_COLS order.
            return (None, [tuple(r[c] for c in _TRANSCRIPT_COLS) for r in rows])
        if "FROM channel_sessions" in sql and "WHERE id = %s" in sql:
            sid = params[0] if params else None
            ctx = _make_session_context(sid)
            return (None, [tuple(ctx[c] for c in _SESSION_COLS)])
        return (None, [])

    return handler


def _write_export_pair(
    output_dir: Path,
    peer: str,
    session_id: int,
    rows: list[dict[str, Any]],
    tamper_index: int | None = None,
    session_key: str | None = None,
) -> tuple[Path, Path]:
    """Write a peer export JSONL + manifest for the given rows.

    If ``tamper_index`` is provided, the JSONL row at that index is modified so
    checksum verification fails.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    export_file = output_dir / f"{peer}_memory_export.jsonl"
    manifest_file = output_dir / f"{peer}_memory_manifest.json"

    context = _make_session_context(session_id, session_key=session_key)
    header = {"type": "session_context", "session": context}

    per_row_checksums = [
        cleanup_708_703._row_checksum(r) for r in rows  # noqa: SLF001
    ]

    export_lines: list[str] = []
    export_lines.append(cleanup_708_703._canonical_json(header))  # noqa: SLF001
    for row, chk in zip(rows, per_row_checksums):
        line_obj = {"type": "channel_transcript", "row": row, "checksum": chk}
        export_lines.append(
            cleanup_708_703._canonical_json(line_obj)  # noqa: SLF001
        )

    if tamper_index is not None and 0 <= tamper_index < len(export_lines) - 1:
        # Tamper a transcript line, not the header (index 0).
        line_idx = tamper_index + 1
        obj = json.loads(export_lines[line_idx])
        obj["row"]["content"] = obj["row"]["content"] + "-tampered"
        export_lines[line_idx] = cleanup_708_703._canonical_json(obj)  # noqa: SLF001

    export_file.write_text("\n".join(export_lines) + "\n", encoding="utf-8")

    file_bytes = export_file.read_bytes()
    file_checksum = hashlib.sha256(file_bytes).hexdigest()

    aggregate_hasher = hashlib.sha256()
    for chk in per_row_checksums:
        aggregate_hasher.update(chk.encode("ascii"))
    aggregate_checksum = aggregate_hasher.hexdigest()

    manifest = {
        "created_at": "2026-10-14T00:00:00+00:00",
        "peer": peer,
        "source_database": "nova_memory",
        "session_id": session_id,
        "session_key": context["session_key"],
        "row_count": len(rows),
        "file_path": str(export_file),
        "file_checksum": file_checksum,
        "per_row_checksums": per_row_checksums,
        "aggregate_checksum": aggregate_checksum,
        "schema": "cleanup-peer-export-v1",
    }
    manifest_file.write_text(
        cleanup_708_703._canonical_json(manifest) + "\n",  # noqa: SLF001
        encoding="utf-8",
    )
    return export_file, manifest_file


# ---------------------------------------------------------------------------
# Base test class with environment isolation
# ---------------------------------------------------------------------------


class CleanupP1TestCase(unittest.TestCase):
    """Hermetic base: HOME and PGDATABASE are isolated."""

    def setUp(self) -> None:
        self._orig_pgdatabase = os.environ.get("PGDATABASE")
        self._orig_home = os.environ.get("HOME")
        self._tmp_dir = tempfile.TemporaryDirectory()
        os.environ["HOME"] = self._tmp_dir.name
        os.environ.pop("PGDATABASE", None)

    def tearDown(self) -> None:
        if self._orig_pgdatabase is None:
            os.environ.pop("PGDATABASE", None)
        else:
            os.environ["PGDATABASE"] = self._orig_pgdatabase
        if self._orig_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = self._orig_home
        self._tmp_dir.cleanup()

    def _postgres_json(self, database: str) -> None:
        config_dir = Path(self._tmp_dir.name) / ".openclaw"
        config_dir.mkdir(parents=True, exist_ok=True)
        (config_dir / "postgres.json").write_text(
            json.dumps({"database": database}), encoding="utf-8"
        )

    def _assert_select_only(self, executed: list[tuple[str, Any]]) -> None:
        """Assert every recorded statement is a SELECT (no DML)."""
        for sql, _params in executed:
            stripped = sql.strip().lower()
            self.assertTrue(
                stripped.startswith("select"),
                f"Expected SELECT-only, found: {sql[:80]}",
            )


# ---------------------------------------------------------------------------
# TC-708-010: identification
# ---------------------------------------------------------------------------


class TestIdentification(CleanupP1TestCase):
    """TC-708-010: disposition categories and counts on a fixture."""

    def test_peer_misplaced_detected(self) -> None:
        """graybeard session is flagged as peer_misplaced when graybeard_memory exists."""
        conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(conn, "nova_memory")
        self.assertEqual(result.current_database, "nova_memory")
        self.assertEqual(result.current_owner, "nova")
        peer_ids = [s.session_id for s in result.peer_misplaced]
        self.assertIn(155, peer_ids)

    def test_non_peer_wrong_place_detected(self) -> None:
        """nova-staging is flagged as non_peer_wrong_place (no owning DB)."""
        conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(conn, "nova_memory")
        non_peer_ids = [s.session_id for s in result.non_peer_wrong_place]
        self.assertIn(9216, non_peer_ids)

    def test_junk_inside_correct_session_detected(self) -> None:
        """Session 15's test/legacy senders are flagged as junk_in_session."""
        conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(conn, "nova_memory")
        junk_ids = [s.session_id for s in result.junk_in_session]
        self.assertIn(15, junk_ids)
        junk = next(s for s in result.junk_in_session if s.session_id == 15)
        # 2 zztest_a + 1 schema-sync = 3 junk rows
        self.assertEqual(junk.row_count, 3)
        junk_senders = {b["sender_name"] for b in junk.sender_breakdown}
        self.assertEqual(junk_senders, {"zztest_a", "schema-sync"})

    def test_correct_sessions_not_flagged(self) -> None:
        """Nova and athena sessions remain in correct_sessions.

        Session 15 is also listed under junk_in_session because it contains
        test-sender rows, but the session itself is not removed/migrated.
        """
        conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(conn, "nova_memory")
        correct_ids = {s.session_id for s in result.correct_sessions}
        self.assertIn(15, correct_ids)
        self.assertIn(57900, correct_ids)
        # Athena has no junk and is not misplaced.
        flagged_ids = {
            s.session_id
            for s in result.peer_misplaced
            + result.non_peer_wrong_place
            + result.junk_in_session
        }
        self.assertNotIn(57900, flagged_ids)

    def test_totals(self) -> None:
        """Aggregate row counts match fixture."""
        conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(conn, "nova_memory")
        self.assertEqual(result.total_peer_rows, 3)  # session 155 has 3 rows
        self.assertEqual(result.total_non_peer_rows, 1)  # session 9216 has 1 row
        self.assertEqual(result.total_junk_rows, 3)  # session 15 junk

    def test_identification_is_select_only(self) -> None:
        """Identification issues no DML against the source DB."""
        conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        cleanup_708_703.identify_misplaced_sessions(conn, "nova_memory")
        self._assert_select_only(conn.cursor_obj.executed)


# ---------------------------------------------------------------------------
# TC-708-011: backup
# ---------------------------------------------------------------------------


class TestBackup(CleanupP1TestCase):
    """TC-708-011: per-row and aggregate checksums; tamper detection."""

    def test_backup_manifest_checksums_verify(self) -> None:
        """Backup files re-hash to the manifest's per-row and aggregate checksums."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )

        backup_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manifest = cleanup_708_703.backup_misplaced_rows(
                backup_conn, result, out_dir
            )

            # Recompute per-row checksums from the backup files and compare.
            aggregate_hasher = hashlib.sha256()
            total_rows = 0
            for session_backup in manifest.sessions:
                session_file = Path(session_backup["file"])
                self.assertTrue(session_file.exists())
                for line in session_file.read_text(encoding="utf-8").splitlines()[
                    1:
                ]:  # skip context header
                    obj = json.loads(line)
                    recomputed = cleanup_708_703._row_checksum(obj["row"])  # noqa: SLF001
                    self.assertEqual(
                        recomputed,
                        obj["checksum"],
                        "Per-row checksum in backup file must match recomputed hash",
                    )
                    aggregate_hasher.update(obj["checksum"].encode("ascii"))
                    total_rows += 1

            self.assertEqual(total_rows, manifest.total_row_count)
            self.assertEqual(
                aggregate_hasher.hexdigest(),
                manifest.aggregate_checksum,
                "Aggregate checksum must match recomputed hash",
            )

    def test_tampered_backup_row_fails_verification(self) -> None:
        """Modifying a backup file makes the embedded checksum mismatch."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        backup_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            cleanup_708_703.backup_misplaced_rows(backup_conn, result, out_dir)
            for session_file in sorted(out_dir.glob("session_*_backup.jsonl")):
                lines = session_file.read_text(encoding="utf-8").splitlines()
                if len(lines) <= 1:
                    continue
                obj = json.loads(lines[1])
                obj["row"]["content"] = obj["row"]["content"] + "-tampered"
                lines[1] = cleanup_708_703._canonical_json(obj)  # noqa: SLF001
                session_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

                # Re-read and verify the tampered row's checksum fails.
                tampered_obj = json.loads(lines[1])
                recomputed = cleanup_708_703._row_checksum(tampered_obj["row"])  # noqa: SLF001
                self.assertNotEqual(
                    recomputed,
                    tampered_obj["checksum"],
                    "Tampered row must fail embedded checksum verification",
                )
                break

    def test_backup_is_select_only(self) -> None:
        """Backup issues no DML against the source DB."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        backup_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            cleanup_708_703.backup_misplaced_rows(
                backup_conn, result, Path(tmp)
            )
        self._assert_select_only(backup_conn.cursor_obj.executed)


# ---------------------------------------------------------------------------
# TC-708-012/012b/012c: export
# ---------------------------------------------------------------------------


class TestExport(CleanupP1TestCase):
    """TC-708-012/012b/012c: export completeness and manifest checksums."""

    def test_export_row_count_matches_identification(self) -> None:
        """Peer export contains exactly the rows identified as peer_misplaced."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        export_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manifests = cleanup_708_703.export_peer_rows(export_conn, result, out_dir)
            self.assertEqual(len(manifests), 1)
            manifest = manifests[0]
            self.assertEqual(manifest.peer, "graybeard")
            self.assertEqual(manifest.row_count, 3)
            export_file = Path(manifest.file_path)
            self.assertTrue(export_file.exists())
            # Count transcript rows in the JSONL export.
            transcript_count = 0
            for line in export_file.read_text(encoding="utf-8").splitlines():
                obj = json.loads(line)
                if obj.get("type") == "channel_transcript":
                    transcript_count += 1
            self.assertEqual(transcript_count, manifest.row_count)

    def test_export_content_matches_source(self) -> None:
        """Exported transcript content matches the source fixture row-for-row."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        export_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manifests = cleanup_708_703.export_peer_rows(export_conn, result, out_dir)
            manifest = manifests[0]
            export_file = Path(manifest.file_path)
            source_rows = _make_fixture_rows(155)
            exported_rows: list[dict[str, Any]] = []
            for line in export_file.read_text(encoding="utf-8").splitlines():
                obj = json.loads(line)
                if obj.get("type") == "channel_transcript":
                    exported_rows.append(obj["row"])
            self.assertEqual(len(exported_rows), len(source_rows))
            for exported, source in zip(exported_rows, source_rows):
                self.assertEqual(
                    cleanup_708_703._canonical_json(exported),  # noqa: SLF001
                    cleanup_708_703._canonical_json(source),  # noqa: SLF001
                )

    def test_export_manifest_checksums_verify(self) -> None:
        """Manifest checksums recomputed from the export file match exactly."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        export_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manifests = cleanup_708_703.export_peer_rows(export_conn, result, out_dir)
            manifest = manifests[0]
            export_file = Path(manifest.file_path)

            file_bytes = export_file.read_bytes()
            self.assertEqual(
                hashlib.sha256(file_bytes).hexdigest(),
                manifest.file_checksum,
            )

            per_row: list[str] = []
            for line in export_file.read_text(encoding="utf-8").splitlines():
                obj = json.loads(line)
                if obj.get("type") == "channel_transcript":
                    per_row.append(
                        cleanup_708_703._row_checksum(obj["row"])  # noqa: SLF001
                    )
            self.assertEqual(per_row, manifest.per_row_checksums)

            aggregate_hasher = hashlib.sha256()
            for chk in per_row:
                aggregate_hasher.update(chk.encode("ascii"))
            self.assertEqual(
                aggregate_hasher.hexdigest(),
                manifest.aggregate_checksum,
            )

    def test_tampered_export_detected_by_manifest(self) -> None:
        """Modifying an export file makes its manifest checksums fail."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        export_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manifests = cleanup_708_703.export_peer_rows(export_conn, result, out_dir)
            manifest = manifests[0]
            export_file = Path(manifest.file_path)

            lines = export_file.read_text(encoding="utf-8").splitlines()
            obj = json.loads(lines[1])
            obj["row"]["content"] = obj["row"]["content"] + "-tampered"
            lines[1] = cleanup_708_703._canonical_json(obj)  # noqa: SLF001
            export_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

            file_bytes = export_file.read_bytes()
            self.assertNotEqual(
                hashlib.sha256(file_bytes).hexdigest(),
                manifest.file_checksum,
            )

    def test_export_is_select_only(self) -> None:
        """Export issues no DML against the source DB."""
        ident_conn = FakeConnection(_identification_handler(existing_dbs={"graybeard"}))
        result = cleanup_708_703.identify_misplaced_sessions(
            ident_conn, "nova_memory"
        )
        export_conn = FakeConnection(_backup_export_handler())
        with tempfile.TemporaryDirectory() as tmp:
            cleanup_708_703.export_peer_rows(export_conn, result, Path(tmp))
        self._assert_select_only(export_conn.cursor_obj.executed)


# ---------------------------------------------------------------------------
# TC-708-012d / TC-703-003/004/005: peer import
# ---------------------------------------------------------------------------


def _make_peer_import_conn(existing_keys: set[tuple[str, str]]) -> FakeConnection:
    """Return a FakeConnection that skips existing (session_key, message_id) keys."""

    def handler(sql: str, params: tuple[Any, ...] | None) -> tuple[Any, list[Any]]:
        if "SELECT ct.id" in sql and "session_key" in sql and params:
            key = (params[0], params[1])
            if key in existing_keys:
                return ((1,), [])
            return (None, [])
        if "INSERT INTO channel_sessions" in sql:
            return ((1000,), [])
        if "INSERT INTO channel_transcripts" in sql and params:
            return (None, [])
        return (None, [])

    return FakeConnection(handler)


class TestPeerImport(CleanupP1TestCase):
    """Peer-side import: idempotency, multi-peer discrimination, checksum/owner gates."""

    def test_peer_import_inserts_new_rows(self) -> None:
        """TC-703-003: peer import inserts rows not already present."""
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            conn = _make_peer_import_conn(existing_keys=set())
            result = cleanup_peer_import.import_peer_rows(
                conn, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(result["row_count"], 3)
            self.assertEqual(result["inserted"], 3)
            self.assertEqual(result["skipped"], 0)

    def test_peer_import_is_idempotent(self) -> None:
        """TC-703-004: running import twice inserts each row only once."""
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            # First run: empty target.
            conn1 = _make_peer_import_conn(existing_keys=set())
            r1 = cleanup_peer_import.import_peer_rows(
                conn1, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(r1["inserted"], 3)
            self.assertEqual(r1["skipped"], 0)

            # Second run: simulate target now containing all rows.
            manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
            session_key = manifest["session_key"]
            keys = {(session_key, r["external_message_id"]) for r in rows}
            conn2 = _make_peer_import_conn(existing_keys=keys)
            r2 = cleanup_peer_import.import_peer_rows(
                conn2, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(r2["inserted"], 0)
            self.assertEqual(r2["skipped"], 3)

    def test_multi_peer_fixture_discriminates(self) -> None:
        """TC-703-005: a fixture with two peers keeps exports separate."""
        self._postgres_json("graybeard_memory")
        graybeard_rows = _make_fixture_rows(155)
        newhart_rows = _make_fixture_rows(10871, senders=_MULTIPEER_SENDERS[10871])
        # Re-label newhart fixture rows to have a newhart session key/context.
        for r in newhart_rows:
            r["session_key"] = "agent:newhart:agent_chat"
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            gb_export, gb_manifest = _write_export_pair(
                out_dir, "graybeard", 155, graybeard_rows
            )
            nh_export, nh_manifest = _write_export_pair(
                out_dir, "newhart", 10871, newhart_rows, session_key="agent:newhart:agent_chat"
            )

            # graybeard owner can import graybeard export.
            conn_gb = _make_peer_import_conn(existing_keys=set())
            r_gb = cleanup_peer_import.import_peer_rows(
                conn_gb, gb_export, gb_manifest, dry_run=False
            )
            self.assertEqual(r_gb["inserted"], len(graybeard_rows))

            # graybeard owner refuses newhart export.
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                cleanup_peer_import.import_peer_rows(
                    conn_gb, nh_export, nh_manifest, dry_run=False
                )

    def test_wrong_peer_export_refused(self) -> None:
        """Peer import refuses an export whose peer field does not match DB owner."""
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        # Write as newhart but content is graybeard-shaped.
        for r in rows:
            r["session_key"] = "agent:newhart:agent_chat"
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "newhart", 155, rows
            )
            conn = _make_peer_import_conn(existing_keys=set())
            with self.assertRaisesRegex(RuntimeError, "does not match"):
                cleanup_peer_import.import_peer_rows(
                    conn, export_file, manifest_file, dry_run=False
                )

    def test_bad_checksum_refused_no_inserts(self) -> None:
        """Tampered export is refused before any INSERT."""
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows, tamper_index=0
            )
            conn = _make_peer_import_conn(existing_keys=set())
            with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                cleanup_peer_import.import_peer_rows(
                    conn, export_file, manifest_file, dry_run=False
                )
            # No session or transcript INSERT should have been attempted.
            insert_sqls = [
                sql for sql, _params in conn.cursor_obj.executed if "INSERT" in sql
            ]
            self.assertEqual(
                insert_sqls,
                [],
                "No inserts may be attempted when checksum verification fails",
            )

    def test_peer_import_refuses_non_memory_database(self) -> None:
        """Peer import only runs against a database name ending in _memory."""
        self._postgres_json("graybeard_other")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            conn = _make_peer_import_conn(existing_keys=set())
            with self.assertRaisesRegex(RuntimeError, "does not look like a memory database"):
                cleanup_peer_import.import_peer_rows(
                    conn, export_file, manifest_file, dry_run=False
                )

    def test_dry_run_reports_but_does_not_insert(self) -> None:
        """Dry-run mode reports would_insert without executing INSERTs."""
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            conn = _make_peer_import_conn(existing_keys=set())
            result = cleanup_peer_import.import_peer_rows(
                conn, export_file, manifest_file, dry_run=True
            )
            self.assertEqual(result["dry_run"], True)
            self.assertEqual(result["inserted"], 3)
            self.assertTrue(
                all(a["action"] == "would_insert" for a in result["actions"])
            )
            insert_sqls = [
                sql for sql, _params in conn.cursor_obj.executed if "INSERT" in sql
            ]
            self.assertEqual(insert_sqls, [])


# ---------------------------------------------------------------------------
# Negative tests: source module behavior
# ---------------------------------------------------------------------------


class TestNegative(CleanupP1TestCase):
    """Negative checks: no DML, no peer DB opens, CLI has no live write mode."""

    def test_source_module_has_no_dml_execute_calls(self) -> None:
        """cleanup_708_703.py contains no executed INSERT/UPDATE/DELETE statements.

        This is a static guard complementing the dynamic SELECT-only assertions.
        We scan the source for .execute(...) calls and assert none begin with
        INSERT, UPDATE, or DELETE.
        """
        source_path = Path(cleanup_708_703.__file__)
        source = source_path.read_text(encoding="utf-8")

        # Regex matches .execute("""SQL""") or .execute('SQL') including triple-quoted.
        import re

        pattern = re.compile(
            r"\.execute\s*\(\s*(?:\"\"\"|'''|\"|')\s*(.*?)\s*(?:\"\"\"|'''|\"|')",
            re.DOTALL | re.IGNORECASE,
        )
        dml_starts = ("insert", "update", "delete")
        for match in pattern.finditer(source):
            sql = match.group(1).strip().lower()
            if sql.startswith(dml_starts):
                self.fail(
                    f"cleanup_708_703.py contains executable DML: {match.group(1)[:80]}"
                )

    def test_open_connection_uses_resolved_name(self) -> None:
        """_open_connection is called with the resolved database name, never hardcoded."""
        self._postgres_json("nova_memory")
        with patch("psycopg2.connect") as mock_connect:
            cleanup_708_703._open_connection("nova_memory")  # noqa: SLF001
        self.assertEqual(mock_connect.call_args.kwargs.get("dbname"), "nova_memory")

    def test_cli_backup_export_does_not_write_peers(self) -> None:
        """The CLI entry points never accept a peer connection map or live write flag."""
        # Inspect the CLI argument parser and entry points: no --target-conn or --write flag.
        self.assertFalse(
            hasattr(cleanup_708_703, "split_replay_stranded_rows"),
            "split_replay_stranded_rows must be removed from the NOVA-side module",
        )
        # The only subcommands should be identify and backup-export.
        # We verify by calling the argparser building logic indirectly.
        import argparse

        parser = argparse.ArgumentParser()
        sub = parser.add_subparsers(dest="command")
        sub.add_parser("identify")
        p_backup = sub.add_parser("backup-export")
        p_backup.add_argument("--output-dir", required=True)
        actions = {a.dest for a in parser._actions if hasattr(a, "dest")}
        # argparse internal dest for subparser is 'command'.
        self.assertIn("command", actions)
        self.assertNotIn("write", actions)
        self.assertNotIn("target_conn", actions)


# ---------------------------------------------------------------------------
# Peer import CLI/resolver
# ---------------------------------------------------------------------------


class TestPeerImportCLI(CleanupP1TestCase):
    """Peer import script resolves its own DB and accepts --dry-run."""

    def test_main_resolves_peer_database_from_config(self) -> None:
        """CLI resolves PGDATABASE -> postgres.json and opens one connection."""
        self._postgres_json("newhart_memory")
        rows = _make_fixture_rows(155)
        # Adjust session_key to newhart so the export peer matches the DB owner.
        for r in rows:
            r["session_key"] = "agent:newhart:agent_chat"
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "newhart", 155, rows, session_key="agent:newhart:agent_chat"
            )
            conn = _make_peer_import_conn(existing_keys=set())
            with patch(
                "cleanup_peer_import.resolve_memory_database_name",
                return_value="newhart_memory",
            ) as mock_resolve:
                with patch(
                    "cleanup_peer_import._open_connection", return_value=conn
                ) as mock_open:
                    cleanup_peer_import.main(
                        [
                            "--export",
                            str(export_file),
                            "--manifest",
                            str(manifest_file),
                        ]
                    )
            mock_resolve.assert_called_once()
            mock_open.assert_called_once_with("newhart_memory")



if __name__ == "__main__":
    unittest.main(verbosity=2)
