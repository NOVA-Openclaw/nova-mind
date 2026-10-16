"""Source-anchor verification for memory_embeddings (#706).

Issue #706 root cause: memory_embeddings.source_id values used to point at
OpenClaw session transcript files (`~/.openclaw/agents/<agent>/sessions/*.jsonl`)
or at line numbers inside those files. After the 2026.9.x upgrade those JSONL
files are gone, so those anchors no longer resolve.

Decision (SE #1231, 2026-10-13): nova-mind memory sources are anchored ONLY to
nova_memory `channel_sessions` / `channel_transcripts` (for conversation-derived
memories) or to their own dedicated source record (for every other
memory_embeddings.source_type). OpenClaw's per-agent SQLite store is out of
bounds.

This module provides read-only verification/coverage helpers:
  * inventory of every memory_embeddings.source_type,
  * per-source-type anchor resolution,
  * detection of broken legacy file/SQLite anchors,
  * end-to-end "follow the anchor" from a memory_embeddings row back to the
    original source content.

No function in this module writes to a database. Production callers that do
want to migrate rows should use the reports produced here to drive a separate,
explicit migration step.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any, Optional


# ---------------------------------------------------------------------------
# Source-type specifications
# ---------------------------------------------------------------------------
#
# Each entry maps a memory_embeddings.source_type to the place its source_id
# should resolve.  Specs are derived from:
#   * dt.sh schema output for nova_memory (channel_sessions/channel_transcripts
#     FKs on entity_facts, id columns on each owning table).
#   * memory/templates/memory-maintenance.py TABLE_EMBED_SPECS and
#     phase_embed_research (lesson/event/vocabulary/library/research_*).
#   * Issue #706 evidence and comments (agent_chat lives in the shared
#     agent_chat database, not in nova_memory).
#   * Live source_id samples from nova_memory.memory_embeddings
#     (domain_topic for agent_domain, roll for motivation_d100, polymorphic
#     "<table>:<id>" for research, file-chunk strings for memory_file/memory_md).


@dataclass(frozen=True)
class SourceSpec:
    """Resolution spec for one memory_embeddings.source_type."""

    source_type: str
    # Target table (unqualified). None means this source_type is not a DB row.
    table: Optional[str]
    # Database name.  None means "resolve to the runtime memory database";
    # "agent_chat" is the only explicit named database today.
    db: Optional[str] = None
    # Column that source_id matches against.  Defaults to the table's id column.
    key_column: str = "id"
    # Columns fetched as "provenance" when the anchor resolves.
    provenance_columns: tuple[str, ...] = ()
    # True when this source_type requires a second hop from its own table to
    # channel_sessions/channel_transcripts (only entity_fact today).
    follows_channel_fks: bool = False
    # True for source_ids that name a file/chunk rather than a DB row.
    is_file_anchor: bool = False


# Columns used to prove that a source row actually carries its own provenance.
# These are intentionally conservative snippets, not full rows.
_DEFAULT_PROVENANCE = ("created_at", "updated_at")

SOURCE_SPECS: dict[str, SourceSpec] = {
    # Conversation-derived memories ------------------------------------------------
    # entity_fact stores its provenance directly on the row via FKs to the
    # transcript/session that produced it (confirmed by dt.sh schema).
    "entity_fact": SourceSpec(
        source_type="entity_fact",
        table="entity_facts",
        provenance_columns=(
            "source_channel_transcript_id",
            "source_channel_session_id",
            "learned_at",
            "updated_at",
        ),
        follows_channel_fks=True,
    ),
    # agent_chat messages live in the shared agent_chat database, not in
    # nova_memory (issue #706 decision comment; TC-706-003 corrected model).
    "agent_chat": SourceSpec(
        source_type="agent_chat",
        table="agent_chat",
        db="agent_chat",
        provenance_columns=("sender", "message", "timestamp"),
    ),
    # Dedicated source tables ------------------------------------------------------
    # The mappings below come from memory/templates/memory-maintenance.py
    # TABLE_EMBED_SPECS / phase_embed_research plus the live table inventory.
    "agent": SourceSpec(
        source_type="agent", table="agents", provenance_columns=("name", "created_at")
    ),
    # agent_domain embeddings are keyed by domain_topic, not by surrogate id
    # (seed-domain-embeddings.py uses source_id=domain_topic).
    "agent_domain": SourceSpec(
        source_type="agent_domain",
        table="agent_domains",
        key_column="domain_topic",
        provenance_columns=("domain_topic", "agent_id", "created_at"),
    ),
    "artwork": SourceSpec(source_type="artwork", table="artwork", provenance_columns=("title", "created_at")),
    "comms_digest": SourceSpec(
        source_type="comms_digest", table="comms_digests", provenance_columns=("generated_at",)
    ),
    "entity": SourceSpec(source_type="entity", table="entities", provenance_columns=("name", "type", "created_at")),
    "entity_relationship": SourceSpec(
        source_type="entity_relationship",
        table="entity_relationships",
        provenance_columns=("relationship", "since"),
    ),
    "event": SourceSpec(
        source_type="event", table="events", provenance_columns=("title", "event_date", "source")
    ),
    "gambling_log": SourceSpec(
        source_type="gambling_log", table="gambling_logs", provenance_columns=("name", "created_at")
    ),
    "income_source": SourceSpec(
        source_type="income_source",
        table="income_sources",
        provenance_columns=("name", "description", "created_at"),
    ),
    # Both "journal" and "journal_entry" point at journal_entries.  The older
    # "journal" source_type is retained for backward compatibility.
    "journal": SourceSpec(
        source_type="journal", table="journal_entries", provenance_columns=("content", "created_at")
    ),
    "journal_entry": SourceSpec(
        source_type="journal_entry", table="journal_entries", provenance_columns=("content", "created_at")
    ),
    "lesson": SourceSpec(source_type="lesson", table="lessons", provenance_columns=("lesson", "learned_at")),
    # library source_type predates the library -> library_works rename (#259);
    # memory-maintenance.py keeps source_type='library' for backward compat.
    "library": SourceSpec(
        source_type="library", table="library_works", provenance_columns=("title", "added_at")
    ),
    "media_consumed": SourceSpec(
        source_type="media_consumed", table="media_consumed", provenance_columns=("title", "created_at")
    ),
    # motivation_d100 is keyed by roll number, not a surrogate id.
    "motivation_d100": SourceSpec(
        source_type="motivation_d100",
        table="motivation_d100",
        key_column="roll",
        provenance_columns=("task_name", "roll", "created_at"),
    ),
    "music_work": SourceSpec(
        source_type="music_work", table="music_works", provenance_columns=("title", "created_at")
    ),
    "place": SourceSpec(source_type="place", table="places", provenance_columns=("name", "type", "created_at")),
    "preference": SourceSpec(
        source_type="preference", table="preferences", provenance_columns=("key", "value", "learned_at")
    ),
    "project": SourceSpec(
        source_type="project", table="projects", provenance_columns=("name", "started_at")
    ),
    # "research" is a polymorphic legacy source_type: source_id is
    # "research_task:<id>", "research_finding:<id>", or
    # "research_conclusion:<id>" (live sample "research_task:9").
    "research": SourceSpec(
        source_type="research",
        table="research_polymorphic",
        provenance_columns=("polymorphic_kind", "resolved_table", "title_or_summary"),
    ),
    "research_conclusion": SourceSpec(
        source_type="research_conclusion",
        table="research_conclusions",
        provenance_columns=("title", "summary", "created_at"),
    ),
    "research_finding": SourceSpec(
        source_type="research_finding",
        table="research_findings",
        provenance_columns=("content", "is_current", "created_at"),
    ),
    "research_task": SourceSpec(
        source_type="research_task", table="research_tasks", provenance_columns=("query", "created_at")
    ),
    # task embeddings resolve to work_queue (confirmed by live sample ids 100,
    # 101, 129 existing in work_queue).
    "task": SourceSpec(
        source_type="task", table="work_queue", provenance_columns=("description", "status", "created_at")
    ),
    "unsolved_problem": SourceSpec(
        source_type="unsolved_problem",
        table="unsolved_problems",
        provenance_columns=("description", "added_at"),
    ),
    "vehicle": SourceSpec(
        source_type="vehicle", table="vehicles", provenance_columns=("make", "model", "year")
    ),
    "vocabulary": SourceSpec(
        source_type="vocabulary", table="vocabulary", provenance_columns=("word", "category", "last_confirmed")
    ),
    "workflow": SourceSpec(
        source_type="workflow", table="workflows", provenance_columns=("name", "created_at")
    ),
    "workflow_run": SourceSpec(
        source_type="workflow_run",
        table="workflow_runs",
        provenance_columns=("trigger_context", "notes", "started_at"),
    ),
    # File-based anchors -----------------------------------------------------------
    # These do not point at a DB row; the source_id names a file/chunk.
    # blog_post source_ids are HTML filenames (live sample
    # "2026-02-08-upgrade-recovery.html").  memory_file/memory_md use
    # "<filename>#<chunk>" (issue #706 evidence and memory-maintenance.py
    # _embed_file_chunks).
    "blog_post": SourceSpec(
        source_type="blog_post", table=None, is_file_anchor=True
    ),
    "memory_file": SourceSpec(
        source_type="memory_file", table=None, is_file_anchor=True
    ),
    "memory_md": SourceSpec(
        source_type="memory_md", table=None, is_file_anchor=True
    ),
}

# Types that are currently expected in nova_memory but for which no explicit
# spec exists yet.  The resolver treats them as "unmapped" rather than silently
# failing coverage checks.


# ---------------------------------------------------------------------------
# Memory database resolution (mirrors #703 in extract_memories.py)
# ---------------------------------------------------------------------------

_NOVA_MEMORY_DB: Optional[str] = None


def _load_database_from_postgres_config() -> Optional[str]:
    """Read database name from the running user's ~/.openclaw/postgres.json."""
    config_path = os.path.expanduser("~/.openclaw/postgres.json")
    try:
        with open(config_path, "r") as f:
            parsed = json.load(f)
        db = parsed.get("database")
        if isinstance(db, str) and db.strip():
            return db.strip()
    except FileNotFoundError:
        pass
    except (OSError, json.JSONDecodeError) as e:
        print(f"[source_anchor] Could not read postgres.json: {e}", file=sys.stderr)
    return None


def _resolve_memory_database() -> str:
    """Resolve the target memory database the same way #703 does.

    Precedence:
      1. PGDATABASE environment variable (if non-empty)
      2. The `database` field of ~/.openclaw/postgres.json

    The resolved name must end with `_memory`.  This function is intentionally
    self-contained so that importing source_anchor does not pull in the
    import-time side effects of extract_memories.py.
    """
    pg_database = os.environ.get("PGDATABASE")
    db_name = pg_database.strip() if pg_database and pg_database.strip() else _load_database_from_postgres_config()

    if not db_name:
        raise RuntimeError(
            "[source_anchor] Could not resolve memory database: PGDATABASE unset and "
            "~/.openclaw/postgres.json missing or has no usable database field"
        )
    if not db_name.endswith("_memory"):
        raise RuntimeError(
            f"[source_anchor] Resolved database '{db_name}' does not look like a memory database"
        )
    return db_name


def _get_memory_database() -> str:
    """Return the cached resolved memory database name."""
    global _NOVA_MEMORY_DB
    if _NOVA_MEMORY_DB is None:
        _NOVA_MEMORY_DB = _resolve_memory_database()
    return _NOVA_MEMORY_DB


def _db_name_for(spec: SourceSpec) -> str:
    """Return the effective database name for a spec."""
    if spec.db is not None:
        return spec.db
    return _get_memory_database()


# ---------------------------------------------------------------------------
# Legacy broken-anchor detection
# ---------------------------------------------------------------------------

# Patterns derived from issue #706 evidence:
#   * "~/.openclaw/agents/<agent>/sessions/<uuid>.jsonl"
#   * ".../newhart/sessions/<uuid>.jsonl.bak.2026-07-21..."
#   * references to the per-agent SQLite store
#   * generic "*.jsonl" wildcard mentions that are not real anchors
_LEGACY_ANCHOR_PATTERNS = [
    re.compile(r"\.jsonl", re.IGNORECASE),
    re.compile(r"\.sqlite", re.IGNORECASE),
    re.compile(r"\.openclaw[/\\]agents", re.IGNORECASE),
    re.compile(r"[/\\]sessions[/\\][^/\\]+\.jsonl", re.IGNORECASE),
]


def is_legacy_file_anchor(source_id: Optional[str]) -> bool:
    """Return True when source_id names a broken JSONL/SQLite/OpenClaw file."""
    if not isinstance(source_id, str) or not source_id:
        return False
    return any(pat.search(source_id) for pat in _LEGACY_ANCHOR_PATTERNS)


# ---------------------------------------------------------------------------
# Resolver class
# ---------------------------------------------------------------------------


class SourceAnchorResolver:
    """Read-only verifier for memory_embeddings source anchors."""

    def __init__(self, nova_conn: Any, agent_chat_conn: Any | None = None):
        self.nova_conn = nova_conn
        self.agent_chat_conn = agent_chat_conn

    def _connection_for(self, spec: SourceSpec) -> Any:
        """Pick the right connection for a spec's database."""
        if spec.db == "agent_chat":
            return self.agent_chat_conn
        return self.nova_conn

    def _resolve_polymorphic_research(
        self,
        cur: Any,
        source_id: str,
        db_name: str,
    ) -> Optional[dict[str, Any]]:
        """Resolve a "research" source_id of the form "<kind>:<id>".

        Live samples are "research_task:9", "research_conclusion:1", etc.
        The kind prefix maps directly to the research_tasks / research_findings /
        research_conclusions tables.
        """
        if ":" not in source_id:
            return None
        kind, _, raw_id = source_id.partition(":")
        if not raw_id:
            return None
        table_map = {
            "research_task": "research_tasks",
            "research_finding": "research_findings",
            "research_conclusion": "research_conclusions",
        }
        table = table_map.get(kind)
        if table is None:
            return None
        cur.execute(
            f"SELECT id FROM {table} WHERE id::text = %s LIMIT 1",
            (raw_id,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "resolved": True,
            "location": f"{db_name}.{table}(id={raw_id})",
            "polymorphic_kind": kind,
            "resolved_table": table,
            "row_id": raw_id,
        }

    def _resolve_db_anchor(
        self,
        conn: Any,
        spec: SourceSpec,
        source_id: str,
    ) -> dict[str, Any]:
        """Resolve a source_id against its spec's DB table."""
        db_name = _db_name_for(spec)

        if conn is None:
            return {
                "resolved": False,
                "location": None,
                "reason": f"no connection available for {db_name}",
            }

        if spec.source_type == "research":
            result = self._resolve_polymorphic_research(conn.cursor(), source_id, db_name)
            if result is not None:
                return result
            return {
                "resolved": False,
                "location": None,
                "reason": "unrecognised research polymorphic format",
            }

        cols = [spec.key_column]
        cols.extend(spec.provenance_columns)
        # Deduplicate while preserving order so the generated SQL is deterministic.
        seen: set[str] = set()
        select_cols: list[str] = []
        for c in cols:
            if c not in seen:
                seen.add(c)
                select_cols.append(c)

        cur = conn.cursor()
        cur.execute(
            f"SELECT {', '.join(select_cols)} FROM {spec.table} "
            f"WHERE {spec.key_column}::text = %s LIMIT 1",
            (source_id,),
        )
        row = cur.fetchone()
        if row is None:
            return {
                "resolved": False,
                "location": f"{db_name}.{spec.table}({spec.key_column}={source_id})",
                "reason": "no matching row",
            }

        values = dict(zip(select_cols, row))
        location = f"{db_name}.{spec.table}({spec.key_column}={source_id})"
        result: dict[str, Any] = {
            "resolved": True,
            "location": location,
            "row": values,
        }

        if spec.follows_channel_fks:
            tx_id = values.get("source_channel_transcript_id")
            sess_id = values.get("source_channel_session_id")
            channel_anchor: dict[str, Any] = {}
            if tx_id:
                cur.execute(
                    "SELECT id, session_id, external_message_id, timestamp, content "
                    "FROM channel_transcripts WHERE id = %s LIMIT 1",
                    (tx_id,),
                )
                tx_row = cur.fetchone()
                if tx_row:
                    channel_anchor["transcript"] = dict(
                        zip(
                            ["id", "session_id", "external_message_id", "timestamp", "content"],
                            tx_row,
                        )
                    )
            if sess_id:
                cur.execute(
                    "SELECT id, session_key, provider, external_chat_id FROM channel_sessions "
                    "WHERE id = %s LIMIT 1",
                    (sess_id,),
                )
                sess_row = cur.fetchone()
                if sess_row:
                    channel_anchor["session"] = dict(
                        zip(
                            ["id", "session_key", "provider", "external_chat_id"],
                            sess_row,
                        )
                    )
            result["channel_anchor"] = channel_anchor

        return result

    @staticmethod
    def _resolve_file_anchor(source_id: str) -> dict[str, Any]:
        """Resolve a file-based source_id.

        File anchors are not verified against the filesystem here (that would make
        the module dependent on gateway-local paths).  Instead we classify the
        anchor and flag known-broken legacy patterns.
        """
        broken = is_legacy_file_anchor(source_id)
        return {
            "resolved": not broken,
            "location": f"file:{source_id}",
            "is_file_anchor": True,
            "is_legacy_file_anchor": broken,
            "reason": "legacy JSONL/SQLite anchor" if broken else None,
        }

    def resolve(self, source_type: str, source_id: str) -> dict[str, Any]:
        """Follow one memory_embeddings anchor back to its source record.

        Returns a dict with at least:
          * source_type, source_id
          * resolved (bool)
          * location (human-readable source location)
          * reason (None unless unresolved)
          * row (dict of selected columns, when resolved against a DB table)
          * channel_anchor (for entity_fact, the transcript/session FKs)
          * is_file_anchor / is_legacy_file_anchor (for file-based types)
        """
        result: dict[str, Any] = {
            "source_type": source_type,
            "source_id": source_id,
            "resolved": False,
            "location": None,
            "reason": None,
        }

        spec = SOURCE_SPECS.get(source_type)
        if spec is None:
            result["reason"] = f"source_type '{source_type}' has no coverage spec"
            return result

        if spec.is_file_anchor:
            file_result = self._resolve_file_anchor(source_id)
            result.update(file_result)
            return result

        conn = self._connection_for(spec)
        db_result = self._resolve_db_anchor(conn, spec, source_id)
        result.update(db_result)
        return result

    def inventory_source_types(self) -> list[dict[str, Any]]:
        """Return a read-only inventory: one row per memory_embeddings.source_type.

        Each row contains source_type and the number of embeddings of that type.
        This is the TC-706-001 inventory baseline.
        """
        cur = self.nova_conn.cursor()
        cur.execute(
            "SELECT source_type, COUNT(*) AS embedding_count "
            "FROM memory_embeddings GROUP BY source_type ORDER BY source_type"
        )
        return [
            {"source_type": row[0], "embedding_count": row[1]} for row in cur.fetchall()
        ]

    def find_legacy_anchors(
        self, *, limit: int = 1000
    ) -> list[dict[str, Any]]:
        """Return up to `limit` memory_embeddings rows whose source_id looks like a
        broken JSONL/SQLite/OpenClaw file anchor.
        """
        cur = self.nova_conn.cursor()
        # Read source_ids only; the content is not needed for this classification.
        cur.execute(
            "SELECT id, source_type, source_id FROM memory_embeddings "
            "WHERE source_id IS NOT NULL ORDER BY id LIMIT %s",
            (limit,),
        )
        rows = cur.fetchall()
        return [
            {"id": row[0], "source_type": row[1], "source_id": row[2]}
            for row in rows
            if is_legacy_file_anchor(row[2])
        ]

    def verify_entity_facts_no_out_of_band(
        self,
    ) -> dict[str, Any]:
        """TC-706-002: ensure entity_facts anchors are ONLY channel_sessions/transcripts.

        Checks:
          1. Every non-NULL source_channel_transcript_id resolves to a real
             channel_transcripts row (DB FK already enforces this; the check exists
             to surface any application-level bypass).
          2. Every non-NULL source_channel_session_id resolves to a real
             channel_sessions row.
          3. No entity_fact_sources.source_citation contains an OpenClaw SQLite or
             JSONL path fragment (the old broken anchor format).
        Returns a dict with violation lists.
        """
        cur = self.nova_conn.cursor()
        violations: list[dict[str, Any]] = []

        # (1) transcript FKs
        cur.execute(
            "SELECT ef.id, ef.source_channel_transcript_id "
            "FROM entity_facts ef "
            "WHERE ef.source_channel_transcript_id IS NOT NULL "
            "  AND NOT EXISTS (SELECT 1 FROM channel_transcripts ct WHERE ct.id = ef.source_channel_transcript_id)"
        )
        for fact_id, tx_id in cur.fetchall():
            violations.append(
                {
                    "kind": "dangling_transcript_fk",
                    "fact_id": fact_id,
                    "source_channel_transcript_id": tx_id,
                }
            )

        # (2) session FKs
        cur.execute(
            "SELECT ef.id, ef.source_channel_session_id "
            "FROM entity_facts ef "
            "WHERE ef.source_channel_session_id IS NOT NULL "
            "  AND NOT EXISTS (SELECT 1 FROM channel_sessions cs WHERE cs.id = ef.source_channel_session_id)"
        )
        for fact_id, sess_id in cur.fetchall():
            violations.append(
                {
                    "kind": "dangling_session_fk",
                    "fact_id": fact_id,
                    "source_channel_session_id": sess_id,
                }
            )

        # (3) SQLite/JSONL smuggled into source_citation (entity_fact_sources)
        cur.execute(
            "SELECT efs.fact_id, efs.source_entity_id, efs.source_citation "
            "FROM entity_fact_sources efs "
            "WHERE efs.source_citation IS NOT NULL"
        )
        for fact_id, source_entity_id, citation in cur.fetchall():
            if is_legacy_file_anchor(citation):
                violations.append(
                    {
                        "kind": "legacy_citation",
                        "fact_id": fact_id,
                        "source_entity_id": source_entity_id,
                        "source_citation": citation,
                    }
                )

        return {
            "violations": violations,
            "violation_count": len(violations),
            "ok": len(violations) == 0,
        }

    def coverage_report(
        self,
        *,
        sample_size: int = 100,
    ) -> dict[str, Any]:
        """Read-only coverage report for every memory_embeddings.source_type.

        For each source_type present in the database:
          * total embedding count,
          * whether a resolver spec exists,
          * how many sampled source_ids resolved successfully,
          * how many sampled source_ids are legacy broken anchors.

        The report is intentionally read-only; it never writes, deletes, or
        migrates anything.
        """
        cur = self.nova_conn.cursor()
        cur.execute(
            "SELECT source_type, source_id FROM memory_embeddings "
            "WHERE source_id IS NOT NULL ORDER BY source_type, id"
        )
        by_type: dict[str, list[str]] = {}
        for st, sid in cur.fetchall():
            by_type.setdefault(st, []).append(sid)

        per_type: list[dict[str, Any]] = []
        for st in sorted(by_type):
            sids = by_type[st]
            sample = sids[:sample_size]
            resolved = 0
            legacy = 0
            unmapped = st not in SOURCE_SPECS
            for sid in sample:
                if unmapped:
                    continue
                result = self.resolve(st, sid)
                if result.get("resolved"):
                    resolved += 1
                if result.get("is_legacy_file_anchor"):
                    legacy += 1

            per_type.append(
                {
                    "source_type": st,
                    "total": len(sids),
                    "has_spec": st in SOURCE_SPECS,
                    "sampled": len(sample),
                    "resolved_in_sample": resolved,
                    "legacy_in_sample": legacy,
                }
            )

        return {
            "source_type_count": len(by_type),
            "per_type": per_type,
        }

    def validate_specs_against_schema(
        self,
        *,
        extra_allowed: dict[str, set[str]] | None = None,
    ) -> dict[str, Any]:
        """Cross-check SOURCE_SPECS against information_schema.columns.

        For every spec with a real table, verify that the table exists in the
        appropriate database and that the key column + every provenance column
        exists.  Returns a report with a list of mismatches; ``ok`` is True
        when no mismatches are found.

        The "research" source_type is polymorphic: its placeholder table
        ``research_polymorphic`` does not exist, so it is skipped by default.
        The "agent_chat" source_type lives in the separate agent_chat database;
        it is validated against that connection when available, otherwise
        skipped.  Callers may pass ``extra_allowed`` to whitelist additional
        tables or columns for special cases.
        """

        def _load_columns(conn: Any) -> dict[str, set[str]]:
            cur = conn.cursor()
            cur.execute(
                "SELECT table_name, column_name "
                "FROM information_schema.columns "
                "WHERE table_schema = 'public'"
            )
            result: dict[str, set[str]] = {}
            for table_name, column_name in cur.fetchall():
                result.setdefault(table_name, set()).add(column_name)
            return result

        nova_columns = _load_columns(self.nova_conn)
        agent_chat_columns: dict[str, set[str]] | None = None
        if self.agent_chat_conn is not None:
            agent_chat_columns = _load_columns(self.agent_chat_conn)

        allowed = dict(extra_allowed or {})
        # research is handled by the polymorphic resolver, not a real table.
        allowed.setdefault("research", set()).add("research_polymorphic")

        mismatches: list[dict[str, Any]] = []
        for source_type, spec in SOURCE_SPECS.items():
            if spec.is_file_anchor or spec.table is None:
                continue
            if source_type in allowed and spec.table in allowed[source_type]:
                continue

            # Pick the catalog that matches the spec's database.
            if spec.db == "agent_chat":
                if agent_chat_columns is None:
                    continue
                columns_by_table = agent_chat_columns
            else:
                columns_by_table = nova_columns

            table_cols = columns_by_table.get(spec.table)
            if table_cols is None:
                mismatches.append(
                    {
                        "source_type": source_type,
                        "table": spec.table,
                        "kind": "missing_table",
                    }
                )
                continue

            for col in [spec.key_column, *spec.provenance_columns]:
                if col not in table_cols:
                    mismatches.append(
                        {
                            "source_type": source_type,
                            "table": spec.table,
                            "column": col,
                            "kind": "missing_column",
                        }
                    )

        return {
            "ok": len(mismatches) == 0,
            "mismatch_count": len(mismatches),
            "mismatches": mismatches,
        }


# ---------------------------------------------------------------------------
# Module-level convenience wrappers
# ---------------------------------------------------------------------------


def resolve_source_anchor(
    nova_conn: Any,
    source_type: str,
    source_id: str,
    *,
    agent_chat_conn: Any | None = None,
) -> dict[str, Any]:
    """Convenience wrapper around SourceAnchorResolver.resolve()."""
    return SourceAnchorResolver(nova_conn, agent_chat_conn).resolve(
        source_type, source_id
    )
