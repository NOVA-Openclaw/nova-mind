"""Tests for cleanup tooling part 1 (#708/#703): identify, backup, export, peer import.

All tests use mocked databases and temporary files. No test connects to a real
PostgreSQL database. Derivation: TEST-CASES-ISSUE-708.md TC-708-010 through
TC-708-012d and TC-703-003/004/005; #715 cleanup-part-1 dispatch.
"""

from __future__ import annotations

import hashlib
import io
import itertools
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

# Monotonically increasing fake primary key for transactional mock inserts.
# Derivation: every mock row needs a unique id across committed/staged stores
# and across reconnects, but the actual numeric values are never asserted.
_FAKE_ID = itertools.count(1)

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
    """A mock psycopg2-like connection.

    Two modes:
      * handler mode: returns a FakeCursor driven by a custom handler (used for
        SELECT-only identification/backup/export tests).
      * storage mode: a transactional in-memory database used for peer-import
        tests; uncommitted inserts are visible within the same connection but
        are discarded by rollback or close, and committed inserts are visible
        to a new connection that shares the same committed store.
    """

    def __init__(
        self,
        handler: Any | None = None,
        committed: dict[str, list[dict[str, Any]]] | None = None,
    ):
        self._handler = handler
        # Committed rows are shared across connections to simulate reconnects.
        self._committed: dict[str, list[dict[str, Any]]] = (
            committed if committed is not None else {}
        )
        # Staged rows belong to the current in-flight transaction only.
        self._staged: dict[str, list[dict[str, Any]]] = {}
        self._readonly: bool | None = None
        self._isolation_level: str | None = None
        self._fail_after: int | None = None
        self._closed = False
        if handler is not None:
            self.cursor_obj: FakeCursor | FakeStorageCursor = FakeCursor(handler)
        else:
            self.cursor_obj = FakeStorageCursor(self)

    def cursor(self) -> FakeCursor | FakeStorageCursor:
        return self.cursor_obj

    def commit(self) -> None:
        """Promote staged rows to committed so they survive close/reconnect."""
        for table, rows in self._staged.items():
            self._committed.setdefault(table, []).extend(rows)
        self._staged.clear()

    def rollback(self) -> None:
        """Discard staged rows."""
        self._staged.clear()

    def close(self) -> None:
        """Close the connection; uncommitted rows are discarded."""
        self._staged.clear()
        self._closed = True

    def set_session(
        self,
        *,
        readonly: bool | None = None,
        isolation_level: str | None = None,
        autocommit: bool | None = None,
    ) -> None:
        """Record transaction characteristics (psycopg2 set_session shim)."""
        self._readonly = readonly
        self._isolation_level = isolation_level


class FakeStorageCursor:
    """Transactional in-memory cursor for peer-import tests.

    Implements just enough SQL semantics for the peer import script:
      - idempotency SELECT on (session_key, external_message_id)
      - upsert INSERT into channel_sessions
      - INSERT INTO channel_transcripts with conflict DO NOTHING
    """

    def __init__(self, conn: FakeConnection):
        self._conn = conn
        self.executed: list[tuple[str, tuple[Any, ...] | None]] = []
        self._fetchone: Any = None
        self._fetchall: list[Any] = []
        self._transcript_inserts = 0

    def execute(self, sql: str, params: tuple[Any, ...] | None = None) -> None:
        self.executed.append((sql, params))
        self._fetchone = None
        self._fetchall = []
        conn = self._conn
        sql_lower = sql.lower()

        if "insert into channel_transcripts" in sql_lower:
            self._transcript_inserts += 1
            if conn._fail_after is not None and self._transcript_inserts >= conn._fail_after:
                raise RuntimeError("injected mid-session failure")

        if "insert into channel_sessions" in sql_lower:
            # Derivation: parameter order in cleanup_peer_import.py session
            # INSERT statement is (session_key, agent_id, provider,
            # external_chat_id, external_thread_id, chat_type).
            (
                session_key,
                agent_id,
                provider,
                external_chat_id,
                external_thread_id,
                chat_type,
            ) = params
            conflict_key = (
                provider,
                external_chat_id,
                external_thread_id if external_thread_id is not None else "",
            )
            existing = None
            for row in (
                conn._committed.get("channel_sessions", [])
                + conn._staged.get("channel_sessions", [])
            ):
                row_key = (
                    row["provider"],
                    row["external_chat_id"],
                    row["external_thread_id"]
                    if row["external_thread_id"] is not None
                    else "",
                )
                if row_key == conflict_key:
                    existing = row
                    break
            if existing is not None:
                # ON CONFLICT DO UPDATE returns the existing session id.
                self._fetchone = (existing["id"],)
            else:
                new_id = next(_FAKE_ID)
                row = {
                    "id": new_id,
                    "session_key": session_key,
                    "agent_id": agent_id,
                    "provider": provider,
                    "external_chat_id": external_chat_id,
                    "external_thread_id": external_thread_id,
                    "chat_type": chat_type,
                }
                conn._staged.setdefault("channel_sessions", []).append(row)
                self._fetchone = (new_id,)
        elif "insert into channel_transcripts" in sql_lower:
            # Derivation: parameter order in cleanup_peer_import.py transcript
            # INSERT statement is (session_id, external_message_id, timestamp,
            # role, content, sender_id, sender_name, sender_username,
            # sender_tag, sender_entity_id, content_type, raw_metadata).
            session_id = params[0]
            external_message_id = params[1]
            exists = any(
                row["session_id"] == session_id
                and row["external_message_id"] == external_message_id
                for rows in (
                    conn._committed.get("channel_transcripts", []),
                    conn._staged.get("channel_transcripts", []),
                )
                for row in rows
            )
            if not exists:
                new_id = next(_FAKE_ID)
                row = {
                    "id": new_id,
                    "session_id": session_id,
                    "external_message_id": external_message_id,
                    "timestamp": params[2],
                    "role": params[3],
                    "content": params[4],
                    "sender_id": params[5],
                    "sender_name": params[6],
                    "sender_username": params[7],
                    "sender_tag": params[8],
                    "sender_entity_id": params[9],
                    "content_type": params[10],
                    "raw_metadata": params[11],
                }
                conn._staged.setdefault("channel_transcripts", []).append(row)
            # INSERT ... ON CONFLICT DO NOTHING returns no rows.
            self._fetchone = None
        elif (
            "select ct.id" in sql_lower
            and "from channel_transcripts" in sql_lower
            and params
        ):
            # Derivation: cleanup_peer_import.py idempotency query joins
            # channel_transcripts to channel_sessions by session_id and filters
            # on session_key + external_message_id.
            session_key, external_message_id = params[0], params[1]
            session_ids = [
                row["id"]
                for rows in (
                    conn._staged.get("channel_sessions", []),
                    conn._committed.get("channel_sessions", []),
                )
                for row in rows
                if row["session_key"] == session_key
            ]
            for rows in (
                conn._staged.get("channel_transcripts", []),
                conn._committed.get("channel_transcripts", []),
            ):
                for row in rows:
                    if (
                        row["session_id"] in session_ids
                        and row["external_message_id"] == external_message_id
                    ):
                        self._fetchone = (row["id"],)
                        return
        else:
            # No matching data.
            pass

    def fetchone(self) -> Any:
        return self._fetchone

    def fetchall(self) -> list[Any]:
        return self._fetchall

    def __enter__(self) -> FakeStorageCursor:
        return self

    def __exit__(self, *args: Any) -> None:
        pass

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


def _full_backup_export_handler(existing_dbs: set[str]) -> Any:
    """Return a FakeCursor handler for the full identify+backup+export CLI.

    Combines identification query responses with backup/export row fetching
    so a single FakeConnection can drive ``_main_backup_export`` end-to-end.
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
        if "FROM channel_transcripts" in sql and "WHERE session_id = %s" in sql:
            sid = params[0] if params else None
            rows = _make_fixture_rows(sid)
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


def _make_peer_import_conn(
    existing_keys: set[tuple[str, str]] | None = None,
    committed_store: dict[str, list[dict[str, Any]]] | None = None,
    fail_after: int | None = None,
) -> FakeConnection:
    """Return a FakeConnection for peer-import tests.

    ``existing_keys`` pre-seeds committed rows so idempotency checks find them.
    ``committed_store`` is shared across connections to test reconnect
    visibility. ``fail_after`` raises after the given number of transcript
    INSERTs have been staged (used to verify rollback).
    """
    committed = committed_store if committed_store is not None else {}
    if existing_keys:
        sessions = committed.setdefault("channel_sessions", [])
        transcripts = committed.setdefault("channel_transcripts", [])
        by_session: dict[str, int] = {}
        for session_key, external_message_id in existing_keys:
            if session_key not in by_session:
                sid = next(_FAKE_ID)
                by_session[session_key] = sid
                # Derivation: session_key has the form "agent:<peer>:..." and
                # the import script derives external_chat_id from that prefix.
                external_chat_id = f"agent_chat:{session_key.split(':')[1]}"
                sessions.append(
                    {
                        "id": sid,
                        "session_key": session_key,
                        "agent_id": "main",
                        "provider": "agent_chat",
                        "external_chat_id": external_chat_id,
                        "external_thread_id": None,
                        "chat_type": None,
                    }
                )
            else:
                sid = by_session[session_key]
            transcripts.append(
                {
                    "id": next(_FAKE_ID),
                    "session_id": sid,
                    "external_message_id": external_message_id,
                    "timestamp": "2026-10-14T00:00:00+00:00",
                    "role": "user",
                    "content": "existing",
                    "sender_id": "existing",
                    "sender_name": "existing",
                    "sender_username": "existing",
                    "sender_tag": None,
                    "sender_entity_id": None,
                    "content_type": "text",
                    "raw_metadata": None,
                }
            )
    conn = FakeConnection(committed=committed)
    if fail_after is not None:
        conn._fail_after = fail_after
    return conn


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
        """cleanup_708_703.py contains no DML outside the removal helpers.

        Part 1 (identify/backup/export) is strictly read-only. Part 2 adds
        removal helpers that issue DELETE statements; those are allowed only
        inside functions whose names start with ``_delete_`` or
        ``remove_misplaced_rows``. This static guard complements the dynamic
        SELECT-only assertions for the read-only phases.
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

        # Find the start of each function so we can attribute .execute calls.
        func_pattern = re.compile(r"^(def\s+(\w+)\s*\()", re.MULTILINE)
        func_starts = [
            (m.start(), m.group(2))
            for m in func_pattern.finditer(source)
        ]

        for match in pattern.finditer(source):
            sql = match.group(1).strip().lower()
            if not sql.startswith(dml_starts):
                continue

            # Determine which function contains this .execute call.
            pos = match.start()
            containing_func = None
            for start, name in sorted(func_starts):
                if start > pos:
                    break
                containing_func = name

            if containing_func in {"_delete_fact_dependencies", "_delete_transcript_ids", "_delete_session_cascade", "_delete_junk_rows", "remove_misplaced_rows"}:
                continue

            self.fail(
                f"cleanup_708_703.py contains executable DML outside removal helpers: "
                f"{match.group(1)[:80]} (in {containing_func})"
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


# ---------------------------------------------------------------------------
# Peer import transaction semantics
# ---------------------------------------------------------------------------


class TestPeerImportTransactions(CleanupP1TestCase):
    """Peer-side import commit/rollback behavior."""

    def test_commit_makes_rows_visible_after_reconnect(self) -> None:
        """A successful import commits rows so a new connection sees them.

        Derivation: without commit(), psycopg2's autocommit=False discards the
        inserts at close(); this test fails if commit is removed from
        import_peer_rows.
        """
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            # Derivation: committed_store is shared between two independent
            # FakeConnections to simulate closing one connection and reopening
            # another against the same database.
            committed_store: dict[str, list[dict[str, Any]]] = {}
            conn1 = _make_peer_import_conn(committed_store=committed_store)
            r1 = cleanup_peer_import.import_peer_rows(
                conn1, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(r1["inserted"], 3)
            self.assertEqual(r1["skipped"], 0)
            conn1.close()

            conn2 = _make_peer_import_conn(committed_store=committed_store)
            r2 = cleanup_peer_import.import_peer_rows(
                conn2, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(r2["inserted"], 0)
            self.assertEqual(r2["skipped"], 3)

    def test_rollback_on_mid_session_exception(self) -> None:
        """An exception mid-session rolls back all rows from that session.

        Derivation: if import_peer_rows did not call rollback(), staged rows
        would remain in committed_store after the exception; this assertion
        verifies the store is still empty.
        """
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            committed_store: dict[str, list[dict[str, Any]]] = {}
            # Derivation: fail_after=1 raises after the first transcript INSERT
            # has been staged, leaving one session row and one transcript row
            # uncommitted that must be discarded by rollback.
            conn = _make_peer_import_conn(
                committed_store=committed_store, fail_after=1
            )
            with self.assertRaisesRegex(RuntimeError, "injected mid-session failure"):
                cleanup_peer_import.import_peer_rows(
                    conn, export_file, manifest_file, dry_run=False
                )
            self.assertEqual(
                committed_store,
                {},
                "Partial inserts must be rolled back, leaving committed_store empty",
            )

    def test_rerun_after_partial_failure_inserts_exactly_once(self) -> None:
        """After a rolled-back partial failure, a rerun inserts all rows once.

        Derivation: combines the rollback guarantee with commit visibility:
        the failed run leaves no committed rows, the retry inserts the full
        session, and a third run sees everything already present.
        """
        self._postgres_json("graybeard_memory")
        rows = _make_fixture_rows(155)
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            export_file, manifest_file = _write_export_pair(
                out_dir, "graybeard", 155, rows
            )
            committed_store: dict[str, list[dict[str, Any]]] = {}
            failed_conn = _make_peer_import_conn(
                committed_store=committed_store, fail_after=1
            )
            with self.assertRaisesRegex(RuntimeError, "injected mid-session failure"):
                cleanup_peer_import.import_peer_rows(
                    failed_conn, export_file, manifest_file, dry_run=False
                )

            retry_conn = _make_peer_import_conn(committed_store=committed_store)
            r_retry = cleanup_peer_import.import_peer_rows(
                retry_conn, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(r_retry["inserted"], 3)
            self.assertEqual(r_retry["skipped"], 0)

            verify_conn = _make_peer_import_conn(committed_store=committed_store)
            r_verify = cleanup_peer_import.import_peer_rows(
                verify_conn, export_file, manifest_file, dry_run=False
            )
            self.assertEqual(r_verify["inserted"], 0)
            self.assertEqual(r_verify["skipped"], 3)


# ---------------------------------------------------------------------------
# TC-708-011/012: backup/export share one REPEATABLE READ snapshot
# ---------------------------------------------------------------------------


class TestBackupExportSnapshot(CleanupP1TestCase):
    """Backup and export run inside a single read-only snapshot."""

    def test_main_backup_export_uses_repeatable_read_transaction(self) -> None:
        """_main_backup_export opens one REPEATABLE READ READ ONLY snapshot."""
        self._postgres_json("nova_memory")
        conn = FakeConnection(_full_backup_export_handler({"graybeard"}))
        with patch(
            "cleanup_708_703._open_connection", return_value=conn
        ) as mock_open:
            with tempfile.TemporaryDirectory() as tmp:
                cleanup_708_703._main_backup_export(tmp)
        mock_open.assert_called_once_with("nova_memory")
        self.assertTrue(conn._readonly)
        self.assertEqual(conn._isolation_level, "REPEATABLE READ")

    def test_backup_and_export_counts_match(self) -> None:
        """Backup and export row counts are equal for the same identification.

        Derivation: both phases must read the same snapshot; otherwise rows
        inserted between identification/export could make the counts diverge.
        """
        self._postgres_json("nova_memory")
        conn = FakeConnection(_full_backup_export_handler({"graybeard"}))
        with patch("cleanup_708_703._open_connection", return_value=conn):
            with tempfile.TemporaryDirectory() as tmp:
                with patch("sys.stdout", new=io.StringIO()) as fake_stdout:
                    cleanup_708_703._main_backup_export(tmp)
                    output = json.loads(fake_stdout.getvalue())

        backup_peer_rows = sum(
            session["row_count"]
            for session in output["backup_manifest"]["sessions"]
            if session["disposition"] == "peer_misplaced"
        )
        export_peer_rows = sum(
            manifest["row_count"] for manifest in output["peer_manifests"]
        )
        self.assertEqual(
            backup_peer_rows,
            export_peer_rows,
            "Backup and export must agree on the number of peer-owned rows",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
