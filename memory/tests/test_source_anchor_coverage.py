"""Tests for memory/lib/source_anchor.py (#706 coverage/verification).

All database access is mocked.  No test in this file connects to a real
Postgres database, so the suite is safe to run in any environment.
"""

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

# Add memory/scripts and memory/lib to the path so we can import the module
# under test.  We intentionally do NOT import extract_memories here, so there
# is no side-effect from its import-time config loading.
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

import source_anchor as sa


# -----------------------------------------------------------------------------
# Mock-connection helpers
# -----------------------------------------------------------------------------

class MockCursor:
    """Cursor that returns programmed rows for programmed queries.

    The resolver only uses execute() + fetchone()/fetchall() against a
    single connection, so a small in-memory lookup table is enough.
    """

    def __init__(self, rows_by_sql: dict[str, list[tuple]] | None = None):
        # rows_by_sql maps a normalized SQL key (first non-empty line) to the
        # rows that fetchall/fetchone should return.
        self.rows_by_sql = rows_by_sql or {}
        self._last_key: str | None = None
        self._last_rows: list[tuple] = []
        self.execute = MagicMock(side_effect=self._execute)

    def _key(self, sql: str) -> str:
        # Normalize whitespace so callers do not need to match exact formatting.
        return " ".join(sql.split())

    def _execute(self, sql: str, params: tuple | None = None) -> None:
        key = self._key(sql)
        self._last_key = key
        self._last_rows = self.rows_by_sql.get(key, [])

    def fetchone(self) -> tuple | None:
        if self._last_rows:
            return self._last_rows[0]
        return None

    def fetchall(self) -> list[tuple]:
        return self._last_rows

    def __enter__(self) -> "MockCursor":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        return False


class MockConnection:
    """Connection whose cursor() returns a MockCursor programmed at init."""

    def __init__(self, cursor: MockCursor):
        self._cursor = cursor

    def cursor(self) -> MockCursor:
        return self._cursor


def make_resolver(
    nova_rows: dict[str, list[tuple]] | None = None,
    agent_chat_rows: dict[str, list[tuple]] | None = None,
) -> tuple[MockConnection, MockConnection | None, sa.SourceAnchorResolver]:
    """Factory: build mocked nova + agent_chat connections and a resolver."""
    nova_conn = MockConnection(MockCursor(nova_rows or {}))
    agent_chat_conn = MockConnection(MockCursor(agent_chat_rows or {}))
    resolver = sa.SourceAnchorResolver(nova_conn, agent_chat_conn)
    return nova_conn, agent_chat_conn, resolver


# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------

class TestLegacyFileAnchorDetection(unittest.TestCase):
    """TC-706-002 prerequisite: identify broken JSONL/SQLite anchors."""

    def test_jsonl_path_flagged(self):
        # Derivation: issue #706 evidence lists "lesson:567 -> sessions/nova/....jsonl"
        self.assertTrue(sa.is_legacy_file_anchor("sessions/nova/9271928b.jsonl"))

    def test_sqlite_path_flagged(self):
        # Derivation: issue #706 evidence lists entity_fact 47895 pointing at
        # ".../newhart/sessions/....jsonl.bak.2026-07-21" and the per-agent
        # SQLite store reset that triggered the issue.
        self.assertTrue(sa.is_legacy_file_anchor(
            "/home/nova/.openclaw/agents/newhart/agent/openclaw-agent.sqlite"
        ))

    def test_openclaw_agents_path_flagged(self):
        self.assertTrue(sa.is_legacy_file_anchor(
            "~/.openclaw/agents/nova/sessions/c35ea839.jsonl.bak.2026-07-21"
        ))

    def test_clean_file_anchor_not_flagged(self):
        # Derivation: memory-maintenance.py embeds workspace memory files as
        # "<filename>#<chunk>" (e.g. "2025-02-06.md#0").
        self.assertFalse(sa.is_legacy_file_anchor("2025-02-06.md#0"))
        self.assertFalse(sa.is_legacy_file_anchor("MEMORY.md:chunk0"))


class TestInventory(unittest.TestCase):
    """TC-706-001: inventory every memory_embeddings.source_type."""

    def test_inventory_returns_counts(self):
        # The SQL orders by source_type, so the mock rows must be sorted.
        rows = {
            "SELECT source_type, COUNT(*) AS embedding_count FROM memory_embeddings GROUP BY source_type ORDER BY source_type": [
                ("agent_chat", 48172),
                ("entity_fact", 23090),
                ("event", 3767),
            ]
        }
        nova_conn, _, resolver = make_resolver(rows)
        result = resolver.inventory_source_types()
        self.assertEqual(len(result), 3)
        self.assertEqual(result[0]["source_type"], "agent_chat")
        self.assertEqual(result[0]["embedding_count"], 48172)


class TestEntityFactNoOutOfBand(unittest.TestCase):
    """TC-706-002: entity_facts anchor only to nova_memory sessions/transcripts."""

    def test_clean_entity_facts_pass(self):
        # Program the cursor to return no dangling FKs and no legacy citations.
        rows = {
            " ".join((
                "SELECT ef.id, ef.source_channel_transcript_id FROM entity_facts ef",
                "WHERE ef.source_channel_transcript_id IS NOT NULL",
                "AND NOT EXISTS (SELECT 1 FROM channel_transcripts ct WHERE ct.id = ef.source_channel_transcript_id)",
            )): [],
            " ".join((
                "SELECT ef.id, ef.source_channel_session_id FROM entity_facts ef",
                "WHERE ef.source_channel_session_id IS NOT NULL",
                "AND NOT EXISTS (SELECT 1 FROM channel_sessions cs WHERE cs.id = ef.source_channel_session_id)",
            )): [],
            " ".join((
                "SELECT efs.fact_id, efs.source_entity_id, efs.source_citation FROM entity_fact_sources efs",
                "WHERE efs.source_citation IS NOT NULL",
            )): [],
        }
        nova_conn, _, resolver = make_resolver(rows)
        report = resolver.verify_entity_facts_no_out_of_band()
        self.assertTrue(report["ok"])
        self.assertEqual(report["violation_count"], 0)

    def test_dangling_transcript_fk_reported(self):
        rows = {
            " ".join((
                "SELECT ef.id, ef.source_channel_transcript_id FROM entity_facts ef",
                "WHERE ef.source_channel_transcript_id IS NOT NULL",
                "AND NOT EXISTS (SELECT 1 FROM channel_transcripts ct WHERE ct.id = ef.source_channel_transcript_id)",
            )): [(42, 999999)],
            " ".join((
                "SELECT ef.id, ef.source_channel_session_id FROM entity_facts ef",
                "WHERE ef.source_channel_session_id IS NOT NULL",
                "AND NOT EXISTS (SELECT 1 FROM channel_sessions cs WHERE cs.id = ef.source_channel_session_id)",
            )): [],
            " ".join((
                "SELECT efs.fact_id, efs.source_entity_id, efs.source_citation FROM entity_fact_sources efs",
                "WHERE efs.source_citation IS NOT NULL",
            )): [],
        }
        nova_conn, _, resolver = make_resolver(rows)
        report = resolver.verify_entity_facts_no_out_of_band()
        self.assertFalse(report["ok"])
        self.assertEqual(len(report["violations"]), 1)
        self.assertEqual(report["violations"][0]["kind"], "dangling_transcript_fk")

    def test_legacy_citation_reported(self):
        rows = {
            " ".join((
                "SELECT ef.id, ef.source_channel_transcript_id FROM entity_facts ef",
                "WHERE ef.source_channel_transcript_id IS NOT NULL",
                "AND NOT EXISTS (SELECT 1 FROM channel_transcripts ct WHERE ct.id = ef.source_channel_transcript_id)",
            )): [],
            " ".join((
                "SELECT ef.id, ef.source_channel_session_id FROM entity_facts ef",
                "WHERE ef.source_channel_session_id IS NOT NULL",
                "AND NOT EXISTS (SELECT 1 FROM channel_sessions cs WHERE cs.id = ef.source_channel_session_id)",
            )): [],
            " ".join((
                "SELECT efs.fact_id, efs.source_entity_id, efs.source_citation FROM entity_fact_sources efs",
                "WHERE efs.source_citation IS NOT NULL",
            )): [(1, 2, "sessions/newhart/c35ea839.jsonl.bak.2026-07-21")],
        }
        nova_conn, _, resolver = make_resolver(rows)
        report = resolver.verify_entity_facts_no_out_of_band()
        self.assertFalse(report["ok"])
        self.assertEqual(report["violations"][0]["kind"], "legacy_citation")


class TestPerSourceTypeResolution(unittest.TestCase):
    """TC-706-003: every memory_embeddings.source_type resolves to its own source record."""

    def _assert_resolved(self, result: dict):
        self.assertTrue(result["resolved"], f"expected resolved, got {result}")

    def test_entity_fact_resolves_and_follows_fks(self):
        # The fact row has FKs to a transcript and session.
        nova_rows = {
            " ".join((
                "SELECT id, source_channel_transcript_id, source_channel_session_id, learned_at, updated_at",
                "FROM entity_facts WHERE id::text = %s LIMIT 1",
            )): [(4782, 3618, 15, "2026-03-01", "2026-03-02")],
            " ".join((
                "SELECT id, session_id, external_message_id, timestamp, content",
                "FROM channel_transcripts WHERE id = %s LIMIT 1",
            )): [(3618, 15, "msg-1", "2026-03-01T00:00:00Z", "hello")],
            " ".join((
                "SELECT id, session_key, provider, external_chat_id",
                "FROM channel_sessions WHERE id = %s LIMIT 1",
            )): [(15, "agent:nova:agent_chat", "agent_chat", "agent:nova:agent_chat")],
        }
        _, _, resolver = make_resolver(nova_rows)
        result = resolver.resolve("entity_fact", "4782")
        self._assert_resolved(result)
        self.assertIn("channel_anchor", result)
        self.assertEqual(result["channel_anchor"]["transcript"]["id"], 3618)
        self.assertEqual(result["channel_anchor"]["session"]["id"], 15)

    def test_agent_chat_resolves_in_shared_db(self):
        # agent_chat lives in the separate agent_chat database.
        # The resolver selects the key column (id) plus provenance columns.
        agent_chat_rows = {
            "SELECT id, sender, message, timestamp FROM agent_chat WHERE id::text = %s LIMIT 1": [
                (1004612, "graybeard", "hello", "2026-03-01T00:00:00Z")
            ]
        }
        _, _, resolver = make_resolver({}, agent_chat_rows)
        result = resolver.resolve("agent_chat", "1004612")
        self._assert_resolved(result)
        self.assertEqual(result["location"], "agent_chat.agent_chat(id=1004612)")

    def test_vocabulary_resolves(self):
        _, _, resolver = make_resolver({
            "SELECT id, word, category, last_confirmed FROM vocabulary WHERE id::text = %s LIMIT 1": [
                (317, "quipu", "custom", "2026-03-01")
            ]
        })
        result = resolver.resolve("vocabulary", "317")
        self._assert_resolved(result)
        self.assertEqual(result["row"]["word"], "quipu")

    def test_library_maps_to_library_works(self):
        # Derivation: memory-maintenance.py comment (#259): source_type stays
        # 'library' after the table rename to library_works.
        # Schema cross-check: library_works has added_at, not created_at.
        _, _, resolver = make_resolver({
            "SELECT id, title, added_at FROM library_works WHERE id::text = %s LIMIT 1": [
                (113, "The Library Book", "2026-01-01")
            ]
        })
        result = resolver.resolve("library", "113")
        self._assert_resolved(result)
        self.assertEqual(result["location"], "nova_memory.library_works(id=113)")

    def test_motivation_d100_resolves_by_roll(self):
        # motivation_d100 has no surrogate id; it is keyed by roll number.
        # The SELECT deduplicates the duplicate roll column.
        _, _, resolver = make_resolver({
            "SELECT roll, task_name, created_at FROM motivation_d100 WHERE roll::text = %s LIMIT 1": [
                (6, "refactor", "2026-01-01")
            ]
        })
        result = resolver.resolve("motivation_d100", "6")
        self._assert_resolved(result)
        self.assertEqual(result["row"]["task_name"], "refactor")

    def test_agent_domain_resolves_by_domain_topic(self):
        # seed-domain-embeddings.py stores source_id=domain_topic.
        # domain_topic is both the key column and the first provenance column,
        # so the SELECT deduplicates it.
        _, _, resolver = make_resolver({
            "SELECT domain_topic, agent_id, created_at FROM agent_domains WHERE domain_topic::text = %s LIMIT 1": [
                ("Agent Architecture", 5, "2026-02-15")
            ]
        })
        result = resolver.resolve("agent_domain", "Agent Architecture")
        self._assert_resolved(result)

    def test_entity_relationship_uses_real_columns(self):
        # QA round 4: entity_relationships has `relationship` and `since`,
        # not `relationship_type` or `created_at`.
        _, _, resolver = make_resolver({
            "SELECT id, relationship, since FROM entity_relationships WHERE id::text = %s LIMIT 1": [
                (42, "friend", "2025-01-01")
            ]
        })
        result = resolver.resolve("entity_relationship", "42")
        self._assert_resolved(result)
        self.assertEqual(result["row"]["relationship"], "friend")
        self.assertEqual(result["location"], "nova_memory.entity_relationships(id=42)")

    def test_comms_digest_uses_real_columns(self):
        # QA round 4: comms_digests has `generated_at`, not `created_at`.
        _, _, resolver = make_resolver({
            "SELECT id, generated_at FROM comms_digests WHERE id::text = %s LIMIT 1": [
                (7, "2026-03-01T00:00:00+00:00")
            ]
        })
        result = resolver.resolve("comms_digest", "7")
        self._assert_resolved(result)
        self.assertIn("generated_at", result["row"])
        self.assertEqual(result["location"], "nova_memory.comms_digests(id=7)")

    def test_gambling_log_uses_real_columns(self):
        # QA round 4: gambling_logs has both `name` and `created_at`.
        _, _, resolver = make_resolver({
            "SELECT id, name, created_at FROM gambling_logs WHERE id::text = %s LIMIT 1": [
                (99, "poker night", "2026-02-15")
            ]
        })
        result = resolver.resolve("gambling_log", "99")
        self._assert_resolved(result)
        self.assertEqual(result["row"]["name"], "poker night")
        self.assertEqual(result["location"], "nova_memory.gambling_logs(id=99)")

    def test_research_polymorphic_resolves_task(self):
        # Live sample: "research_task:9".
        _, _, resolver = make_resolver({
            "SELECT id FROM research_tasks WHERE id::text = %s LIMIT 1": [(9,)]
        })
        result = resolver.resolve("research", "research_task:9")
        self._assert_resolved(result)
        self.assertEqual(result["resolved_table"], "research_tasks")

    def test_task_resolves_to_work_queue(self):
        # Confirmed by live samples 100, 101, 129 existing in work_queue.
        _, _, resolver = make_resolver({
            "SELECT id, description, status, created_at FROM work_queue WHERE id::text = %s LIMIT 1": [
                (100, "Coder: quipu-v2", "pending", "2026-01-01")
            ]
        })
        result = resolver.resolve("task", "100")
        self._assert_resolved(result)
        self.assertEqual(result["location"], "nova_memory.work_queue(id=100)")

    def test_unmapped_source_type_returns_reason(self):
        _, _, resolver = make_resolver({})
        result = resolver.resolve("future_type", "1")
        self.assertFalse(result["resolved"])
        self.assertIn("no coverage spec", result["reason"])

    def test_missing_db_row_reported(self):
        _, _, resolver = make_resolver({
            "SELECT id, title, created_at FROM artwork WHERE id::text = %s LIMIT 1": []
        })
        result = resolver.resolve("artwork", "137")
        self.assertFalse(result["resolved"])
        self.assertIn("no matching row", result["reason"])


class TestFileAnchors(unittest.TestCase):
    """Coverage for file-based source_types (memory_file/memory_md/blog_post)."""

    def test_memory_file_classified_as_file(self):
        _, _, resolver = make_resolver({})
        result = resolver.resolve("memory_file", "2025-02-06.md#0")
        self.assertTrue(result["is_file_anchor"])
        self.assertFalse(result.get("is_legacy_file_anchor", False))
        self.assertTrue(result["resolved"])

    def test_memory_file_with_jsonl_is_legacy(self):
        _, _, resolver = make_resolver({})
        result = resolver.resolve("memory_file", "sessions/nova/x.jsonl#0")
        self.assertTrue(result["is_legacy_file_anchor"])
        self.assertFalse(result["resolved"])

    def test_blog_post_classified_as_file(self):
        _, _, resolver = make_resolver({})
        result = resolver.resolve("blog_post", "2026-02-08-upgrade-recovery.html")
        self.assertTrue(result["is_file_anchor"])
        self.assertTrue(result["resolved"])


class TestEndToEndFollowAnchor(unittest.TestCase):
    """TC-706-003b: semantic-search hit -> original source record."""

    def test_follow_entity_fact_to_transcript_content(self):
        # A semantic recall result is just (source_type, source_id).  The
        # resolver must walk entity_fact -> transcript -> content.
        nova_rows = {
            " ".join((
                "SELECT id, source_channel_transcript_id, source_channel_session_id, learned_at, updated_at",
                "FROM entity_facts WHERE id::text = %s LIMIT 1",
            )): [(4782, 3618, 15, "2026-03-01", "2026-03-02")],
            " ".join((
                "SELECT id, session_id, external_message_id, timestamp, content",
                "FROM channel_transcripts WHERE id = %s LIMIT 1",
            )): [(3618, 15, "msg-1", "2026-03-01T00:00:00Z", "original source text")],
            " ".join((
                "SELECT id, session_key, provider, external_chat_id",
                "FROM channel_sessions WHERE id = %s LIMIT 1",
            )): [(15, "agent:nova:agent_chat", "agent_chat", "agent:nova:agent_chat")],
        }
        _, _, resolver = make_resolver(nova_rows)
        result = resolver.resolve("entity_fact", "4782")
        self.assertEqual(
            result["channel_anchor"]["transcript"]["content"],
            "original source text",
        )

    def test_follow_agent_chat_to_message(self):
        agent_chat_rows = {
            "SELECT id, sender, message, timestamp FROM agent_chat WHERE id::text = %s LIMIT 1": [
                (1004612, "newhart", "I prefer dark mode", "2026-03-01T00:00:00Z")
            ]
        }
        _, _, resolver = make_resolver({}, agent_chat_rows)
        result = resolver.resolve("agent_chat", "1004612")
        self.assertEqual(result["row"]["message"], "I prefer dark mode")

    def test_follow_event_to_description(self):
        _, _, resolver = make_resolver({
            "SELECT id, title, event_date, source FROM events WHERE id::text = %s LIMIT 1": [
                (727, "Birthday", "2026-03-01", "extracted")
            ]
        })
        result = resolver.resolve("event", "727")
        self.assertEqual(result["row"]["title"], "Birthday")


class TestNewAnchorsUseTranscriptSessionIds(unittest.TestCase):
    """TC-706-005: new entity_fact anchors must use transcript/session ids."""

    def test_store_or_reinforce_fact_includes_source_fks(self):
        # Import extract_memories hermetically, mirroring the pattern in
        # test_extract_memories_db_resolution.py so import-time config loading
        # never touches production files.
        sys.modules["pg_env"] = MagicMock()
        sys.modules["pg_env"].load_pg_env = MagicMock()
        sys.modules["env_loader"] = MagicMock()
        sys.modules["env_loader"].load_openclaw_env = MagicMock()
        scripts_path = str(Path(__file__).parent.parent / "scripts")
        if scripts_path not in sys.path:
            sys.path.insert(0, scripts_path)

        import extract_memories

        # No rows programmed -> every fetchone() returns None -> INSERT path.
        cursor = MockCursor({})
        conn = MockConnection(cursor)

        extract_memories.store_or_reinforce_fact(
            entity_id=7,
            key="preference_theme",
            value="dark",
            source_entity_id=None,  # skip entity_fact_sources insertion
            visibility="public",
            visibility_reason=None,
            conn=conn,
            src_channel_transcript_id="123",
            src_channel_session_id="456",
        )

        # The INSERT must include the source FK columns.
        executed_sqls = [call.args[0] for call in cursor.execute.call_args_list]
        insert_sql = next(
            (sql for sql in executed_sqls if "INSERT INTO entity_facts" in sql), ""
        )
        self.assertIn("source_channel_transcript_id", insert_sql)
        self.assertIn("source_channel_session_id", insert_sql)

        # The values must be the integer ids derived from the string env values.
        insert_call = next(
            call for call in cursor.execute.call_args_list if "INSERT INTO entity_facts" in call.args[0]
        )
        params = insert_call.args[1]
        self.assertIn(123, params)
        self.assertIn(456, params)


class TestCoverageReport(unittest.TestCase):
    """TC-706-001 / TC-706-003 aggregate coverage report."""

    def test_coverage_reports_every_source_type(self):
        rows = {
            "SELECT source_type, source_id FROM memory_embeddings WHERE source_id IS NOT NULL ORDER BY source_type, id": [
                ("entity_fact", "4782"),
                ("agent_chat", "1004612"),
                ("event", "727"),
                ("memory_file", "2025-02-06.md#0"),
                ("unknown_type", "1"),
            ]
        }
        agent_chat_rows = {
            "SELECT sender, message, timestamp FROM agent_chat WHERE id::text = %s LIMIT 1": [
                ("newhart", "hello", "2026-03-01")
            ]
        }
        entity_fact_rows = {
            " ".join((
                "SELECT id, source_channel_transcript_id, source_channel_session_id, learned_at, updated_at",
                "FROM entity_facts WHERE id::text = %s LIMIT 1",
            )): [(4782, None, None, "2026-03-01", "2026-03-02")],
        }
        event_rows = {
            "SELECT id, title, event_date, source FROM events WHERE id::text = %s LIMIT 1": [(727, "Birthday", "2026-03-01", "extracted")]
        }
        # Combine all needed rows into one nova lookup map.
        all_nova = {**rows, **entity_fact_rows, **event_rows}
        _, _, resolver = make_resolver(all_nova, agent_chat_rows)
        report = resolver.coverage_report()
        self.assertEqual(report["source_type_count"], 5)
        by_type = {r["source_type"]: r for r in report["per_type"]}
        self.assertTrue(by_type["entity_fact"]["has_spec"])
        self.assertTrue(by_type["agent_chat"]["has_spec"])
        self.assertTrue(by_type["event"]["has_spec"])
        self.assertTrue(by_type["memory_file"]["has_spec"])
        self.assertFalse(by_type["unknown_type"]["has_spec"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
