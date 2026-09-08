#!/usr/bin/env python3
"""
Deterministic ingest orchestrator for comms_items.

Flow (per issue #474 design decision E):
    fetch -> dedupe on (platform, item_id) -> upsert -> classify -> archive-on-resolution

All of this happens BEFORE any LLM reasoning. The script is the DB writer of
record; the Hermes/NOVA report consumes persisted rows only.

Usage:
    python3 scripts/comms/ingest.py [--platforms email,x,nostr] [--limit N] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

import psycopg2

# Allow running this script directly as well as importing it as a module.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
COMMS_DIR = REPO_ROOT / "scripts" / "comms"
if str(COMMS_DIR) not in sys.path:
    sys.path.insert(0, str(COMMS_DIR))

from adapters import gmail, nostr, x  # noqa: E402
from classifier import classify  # noqa: E402


# Inherit gateway PGPASSWORD would break per-agent .pgpass authentication.
os.environ.pop("PGPASSWORD", None)


class IngestError(Exception):
    """Fatal error that should abort the run with a non-zero exit code."""

    def __init__(self, message: str, exit_code: int = 1):
        super().__init__(message)
        self.message = message
        self.exit_code = exit_code


def _load_pg_config() -> dict[str, Any]:
    """Load PostgreSQL connection params from lib/pg_env.py, respecting ENV."""
    lib_dir = REPO_ROOT / "lib"
    if str(lib_dir) not in sys.path:
        sys.path.insert(0, str(lib_dir))
    import pg_env  # noqa: E402

    # pg_env mutates os.environ; return the resolved values.
    env = pg_env.load_pg_env()
    return {
        "host": env.get("PGHOST", "localhost"),
        "port": int(env.get("PGPORT", "5432")),
        "database": env.get("PGDATABASE"),
        "user": env.get("PGUSER"),
        "password": env.get("PGPASSWORD"),
    }


def _connect(config: Optional[dict[str, Any]] = None) -> psycopg2.extensions.connection:
    """Connect to PostgreSQL using the resolved config."""
    cfg = config or _load_pg_config()
    if not cfg.get("database"):
        raise IngestError("PGDATABASE is not configured", exit_code=1)
    if not cfg.get("user"):
        raise IngestError("PGUSER is not configured", exit_code=1)

    kwargs = {
        "host": cfg.get("host", "localhost"),
        "port": cfg.get("port", 5432),
        "database": cfg["database"],
        "user": cfg["user"],
    }
    if cfg.get("password"):
        kwargs["password"] = cfg["password"]

    try:
        return psycopg2.connect(**kwargs)
    except psycopg2.OperationalError as exc:
        raise IngestError(f"database connection failed: {exc}", exit_code=1) from exc
    except psycopg2.Error as exc:
        raise IngestError(f"database error: {exc}", exit_code=1) from exc


def _resolve_entity(
    cur: psycopg2.extensions.cursor,
    platform: str,
    sender: Optional[str],
) -> Optional[int]:
    """Resolve a sender identifier to an entity_id via the shared SQL function."""
    if not sender:
        return None

    if platform == "email":
        key = "email"
        value = sender
    elif platform == "nostr":
        key = "nostr_public_key"
        value = nostr.resolve_pubkey(sender)
        if not value:
            return None
    elif platform == "x":
        # v1 intentionally returns NULL: no established X-handle entity_facts key exists yet.
        return None
    else:
        return None

    cur.execute(
        "SELECT resolve_entity_by_identifier(%s, %s) AS entity_id",
        (key, value),
    )
    row = cur.fetchone()
    return row[0] if row and row[0] is not None else None


def _status_from_disposition(disposition: str) -> tuple[str, Optional[datetime], Optional[datetime]]:
    """Return (status, reported_at, resolved_at) for a classification."""
    now = datetime.now(timezone.utc)
    if disposition in ("fyi", "receipt"):
        # Reporting IS resolution.
        return "resolved", now, now
    if disposition == "injection_suspect":
        # Quarantined but surfaced distinctly in the report.
        return "reported", now, None
    # actionable / escalation
    return "tracked", None, None


def _find_existing(
    cur: psycopg2.extensions.cursor,
    platform: str,
    item_id: str,
) -> Optional[dict[str, Any]]:
    cur.execute(
        """
        SELECT id, status, artifact_ref, entity_id, first_seen_at
        FROM comms_items
        WHERE platform = %s AND item_id = %s
        """,
        (platform, item_id),
    )
    row = cur.fetchone()
    if not row:
        return None
    return {
        "id": row[0],
        "status": row[1],
        "artifact_ref": row[2],
        "entity_id": row[3],
        "first_seen_at": row[4],
    }


def _archive_if_resolved(
    platform: str,
    item_id: str,
    thread_id: Optional[str],
    status: str,
) -> None:
    """Trigger archive-on-resolution for email; other platforms no-op in v1."""
    if status != "resolved" or platform != "email":
        return
    try:
        gmail.archive(thread_id or item_id)
    except Exception as exc:
        # Archive failure must not fail the ingest; it is a secondary cleanup step.
        print(f"[comms-ingest] WARNING: archive failed for {platform}/{item_id}: {exc}", file=sys.stderr)


def _process_item(
    conn: psycopg2.extensions.connection,
    item: dict[str, Any],
    dry_run: bool,
) -> dict[str, Any]:
    """Dedupe, resolve, classify, and insert a single item."""
    platform = item.get("platform")
    item_id = item.get("item_id")

    result = {
        "platform": platform,
        "item_id": item_id,
        "action": "skipped",
        "reason": None,
        "row_id": None,
        "disposition": None,
        "summary": None,
    }

    if not platform or not item_id:
        result["action"] = "skipped"
        result["reason"] = "missing platform or item_id"
        return result

    with conn.cursor() as cur:
        existing = _find_existing(cur, platform, item_id)
        if existing:
            result["action"] = "existing"
            result["reason"] = "already seen"
            result["row_id"] = existing["id"]
            result["disposition"] = None
            return result

        entity_id = _resolve_entity(cur, platform, item.get("sender"))
        classification = classify(
            platform=platform,
            item_id=item_id,
            sender=item.get("sender"),
            subject=item.get("subject"),
            body=item.get("body"),
            snippet=item.get("snippet"),
        )
        disposition = classification["disposition"]
        summary = classification["summary"]
        status, reported_at, resolved_at = _status_from_disposition(disposition)

        result["disposition"] = disposition
        result["summary"] = summary

        if dry_run:
            result["action"] = "would_insert"
            return result

        cur.execute(
            """
            INSERT INTO comms_items
                (platform, item_id, thread_id, entity_id, status, disposition,
                 summary, first_seen_at, reported_at, resolved_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, now(), %s, %s)
            RETURNING id
            """,
            (
                platform,
                item_id,
                item.get("thread_id"),
                entity_id,
                status,
                disposition,
                summary,
                reported_at,
                resolved_at,
            ),
        )
        row = cur.fetchone()
        conn.commit()
        result["row_id"] = row[0] if row else None
        result["action"] = "inserted"

        # Archive-on-resolution is a deterministic consequence of status, not a prompt.
        _archive_if_resolved(platform, item_id, item.get("thread_id"), status)

    return result


def _platform_adapter(platform: str):
    """Return the adapter module for a platform."""
    adapters = {
        "email": gmail,
        "x": x,
        "nostr": nostr,
    }
    return adapters.get(platform)


# Task #717: comms_state.standingItems was write-only — NOVA (and other
# writers) appended dispositions/close-outs to it, but no code path ever read
# the field back to suppress re-asking already-dispositioned items (task #717,
# nova-mind#644). This module reads standingItems at report-compose time and
# surfaces it verbatim so the report consumer (Hermes) can treat a closed-out
# entry as authoritative, per the standing rule already written into those
# entries ("treat a CLOSED-OUT entry in standingItems as authoritative and
# drop the item"). It also uses a conservative task/issue-reference extractor
# to auto-suppress tracked_pending rows whose artifact_ref (e.g. "task#123")
# is named inside a standing item as CLOSED/COMPLETED/DISPOSITIONED, so a
# disposition NOVA already recorded does not require the reader (human or
# agent) to cross-reference prose by hand. Unrecognized prose is never used to
# suppress — it is always still surfaced verbatim; this function only ever
# narrows what silently disappears from tracked_pending, never what appears in
# standing_items_raw.
_CLOSED_DISPOSITION_RE = re.compile(
    r"\b(CLOSED|CLOSED-OUT|COMPLETED|DISPOSITIONED|RESOLVED|NO ACTION)\b",
    re.IGNORECASE,
)
_TASK_REF_RE = re.compile(r"#(\d+)")


def load_standing_items(
    conn: psycopg2.extensions.connection,
    platforms: list[str],
) -> dict[str, list[str]]:
    """Read comms_state.standingItems for each requested platform.

    Returns {platform: [entry, ...]} for platforms that have a standingItems
    array in comms_state.state. Platforms with no row, or no standingItems
    key, are simply absent from the result (not an error — not every
    platform carries standing items).
    """
    if not platforms:
        return {}
    standing: dict[str, list[str]] = {}
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT platform, state -> 'standingItems'
            FROM comms_state
            WHERE platform = ANY(%s) AND state ? 'standingItems'
            """,
            (platforms,),
        )
        for platform, items_json in cur.fetchall():
            if isinstance(items_json, list):
                standing[platform] = [str(entry) for entry in items_json]
    return standing


def _closed_out_task_refs(standing_items: dict[str, list[str]]) -> set[str]:
    """Extract task/issue references (e.g. '123' from '#123') named inside a
    standing item whose text also carries a recognized closure phrase.

    Conservative by design: an entry must contain BOTH a closure phrase AND a
    task reference to suppress that reference. This avoids false suppression
    from entries that merely *mention* a task number while discussing
    something else (e.g. "related: task #484").
    """
    refs: set[str] = set()
    for entries in standing_items.values():
        for entry in entries:
            if not _CLOSED_DISPOSITION_RE.search(entry):
                continue
            refs.update(_TASK_REF_RE.findall(entry))
    return refs


def _artifact_ref_is_closed_out(artifact_ref: Optional[str], closed_refs: set[str]) -> bool:
    """True if artifact_ref names a task/issue number present in closed_refs."""
    if not artifact_ref or not closed_refs:
        return False
    match = _TASK_REF_RE.search(artifact_ref)
    if not match:
        return False
    return match.group(1) in closed_refs


def fetch_platform_items(
    platform: str,
    limit: Optional[int],
) -> tuple[list[dict[str, Any]], Optional[str]]:
    """Fetch items from one platform, returning (items, error_message)."""
    adapter = _platform_adapter(platform)
    if adapter is None:
        return [], f"unknown platform: {platform}"
    try:
        items = adapter.fetch(limit=limit)
        return items, None
    except Exception as exc:
        return [], f"{platform} fetch failed: {exc}"


def run_ingest(
    conn: psycopg2.extensions.connection,
    platforms: list[str],
    limit: Optional[int] = None,
    dry_run: bool = False,
) -> dict[str, Any]:
    """
    Run the deterministic ingest pipeline.

    Returns a report dict with:
        - new_items: items inserted this run
        - existing_items: items already in the DB
        - skipped_items: malformed items
        - platform_errors: per-platform fetch errors
        - tracked_pending: existing tracked rows with artifact_ref still pending,
          EXCLUDING any row whose artifact_ref is named CLOSED/RESOLVED/etc in
          comms_state.standingItems (task #717 read-back)
        - injection_candidates: new injection_suspect rows
        - standing_items: {platform: [entry, ...]} read verbatim from
          comms_state.standingItems for the requested platforms (task #717) —
          the report consumer treats a CLOSED-OUT entry here as authoritative
        - suppressed_pending: tracked rows dropped from tracked_pending because
          standingItems already dispositioned their artifact_ref (visibility
          into what was suppressed and why, for audit/regression testing)
    """
    new_items: list[dict[str, Any]] = []
    existing_items: list[dict[str, Any]] = []
    skipped_items: list[dict[str, Any]] = []
    platform_errors: list[dict[str, Any]] = []

    for platform in platforms:
        items, error = fetch_platform_items(platform, limit)
        if error:
            platform_errors.append({"platform": platform, "error": error})
            continue
        for item in items:
            result = _process_item(conn, item, dry_run=dry_run)
            if result["action"] == "existing":
                existing_items.append(result)
            elif result["action"] == "skipped":
                skipped_items.append(result)
            else:
                new_items.append(result)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id, platform, item_id, status, disposition, summary, artifact_ref
            FROM comms_items
            WHERE status = 'tracked'
            ORDER BY first_seen_at DESC
            LIMIT 100
            """
        )
        all_tracked = [
            {
                "id": row[0],
                "platform": row[1],
                "item_id": row[2],
                "status": row[3],
                "disposition": row[4],
                "summary": row[5],
                "artifact_ref": row[6],
            }
            for row in cur.fetchall()
        ]

        injection_candidates = [i for i in new_items if i.get("disposition") == "injection_suspect"]

    # Task #717 read-back: load standingItems for the platforms in scope and
    # drop any tracked_pending row whose artifact_ref is already dispositioned
    # there, so a resolved item is not re-surfaced to the report consumer.
    standing_items = load_standing_items(conn, platforms)
    closed_refs = _closed_out_task_refs(standing_items)
    tracked_pending = []
    suppressed_pending = []
    for row in all_tracked:
        if _artifact_ref_is_closed_out(row.get("artifact_ref"), closed_refs):
            suppressed_pending.append(row)
        else:
            tracked_pending.append(row)

    return {
        "new_items": new_items,
        "existing_items": existing_items,
        "skipped_items": skipped_items,
        "platform_errors": platform_errors,
        "tracked_pending": tracked_pending,
        "suppressed_pending": suppressed_pending,
        "injection_candidates": injection_candidates,
        "standing_items": standing_items,
    }


def log_comms_check(
    conn: psycopg2.extensions.connection,
    report: dict[str, Any],
    platforms: list[str],
    cron_job_id: str = "hermes-comms-check",
) -> None:
    """Persist a comms_checks audit row for this run.

    This is the writer-of-record step that satisfies TC-474-49: even when the
    comms_state seen-arrays are frozen/retired, comms_checks keeps logging each
    deterministic run.
    """
    new_items = report.get("new_items", [])
    injection_candidates = report.get("injection_candidates", [])
    actionable = [i for i in new_items if i.get("disposition") in ("actionable", "escalation")]
    fyi = [i for i in new_items if i.get("disposition") in ("fyi", "receipt")]

    summary_parts: list[str] = []
    if actionable:
        summary_parts.append(f"{len(actionable)} actionable")
    if fyi:
        summary_parts.append(f"{len(fyi)} FYI/receipt")
    if injection_candidates:
        summary_parts.append(f"{len(injection_candidates)} injection suspect")
    if report.get("platform_errors"):
        summary_parts.append(f"{len(report['platform_errors'])} platform error(s)")
    summary = ", ".join(summary_parts) if summary_parts else "no new items"

    details = {
        "platforms": platforms,
        "new_items_count": len(new_items),
        "existing_items_count": len(report.get("existing_items", [])),
        "skipped_items_count": len(report.get("skipped_items", [])),
        "platform_errors": report.get("platform_errors", []),
    }

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO comms_checks
                (check_type, platforms, summary, details, new_items_count,
                 escalations, action_items, cron_job_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                "comms",
                platforms,
                summary,
                json.dumps(details),
                len(new_items),
                json.dumps([{"platform": i["platform"], "item_id": i["item_id"], "summary": i.get("summary")}
                            for i in injection_candidates]),
                json.dumps([{"platform": i["platform"], "item_id": i["item_id"], "summary": i.get("summary")}
                            for i in actionable]),
                cron_job_id,
            ),
        )
        conn.commit()


def compose_report(report: dict[str, Any]) -> str:
    """Compose a typed Hermes->NOVA report from persisted rows."""
    lines: list[str] = ["## comms ingest report", ""]

    # Task #717: surface standingItems verbatim so a CLOSED-OUT / CORRECTED
    # entry is authoritative for whoever composes the human-facing report
    # (previously write-only — nothing in this pipeline ever read it back).
    standing_items = report.get("standing_items", {})
    if standing_items:
        total = sum(len(v) for v in standing_items.values())
        lines.append(f"### standing dispositions ({total}) — authoritative, do not re-derive or re-ask")
        for platform, entries in standing_items.items():
            for entry in entries:
                lines.append(f"- [{platform}] {entry}")
        lines.append("")

    suppressed = report.get("suppressed_pending", [])
    if suppressed:
        lines.append(f"### suppressed (already dispositioned in standingItems) ({len(suppressed)})")
        for item in suppressed:
            ref = f" ref={item['artifact_ref']}" if item.get("artifact_ref") else ""
            lines.append(f"- [{item['platform']}] {item['summary']}{ref}")
        lines.append("")

    tracked = report.get("tracked_pending", [])
    if tracked:
        lines.append(f"### tracked pending ({len(tracked)})")
        for item in tracked:
            ref = f" ref={item['artifact_ref']}" if item.get("artifact_ref") else ""
            lines.append(f"- [{item['platform']}] {item['summary']}{ref}")
        lines.append("")

    new = report.get("new_items", [])
    actionable = [i for i in new if i.get("disposition") in ("actionable", "escalation")]
    if actionable:
        lines.append(f"### new actionable ({len(actionable)})")
        for item in actionable:
            lines.append(f"- [{item['platform']}] {item['summary']}")
        lines.append("")

    fyi = [i for i in new if i.get("disposition") in ("fyi", "receipt")]
    if fyi:
        lines.append(f"### resolved FYI/receipt ({len(fyi)})")
        for item in fyi:
            lines.append(f"- [{item['platform']}] {item['summary']}")
        lines.append("")

    injections = report.get("injection_candidates", [])
    if injections:
        lines.append(f"### ⚠️ injection suspects ({len(injections)})")
        for item in injections:
            lines.append(f"- [{item['platform']}] {item['summary']}")
        lines.append("")

    errors = report.get("platform_errors", [])
    if errors:
        lines.append(f"### platform errors ({len(errors)})")
        for err in errors:
            lines.append(f"- {err['platform']}: {err['error']}")
        lines.append("")

    if not any([tracked, actionable, fyi, injections, errors]):
        lines.append("No comms items require attention.")
        lines.append("")

    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Deterministic comms ingest pipeline")
    parser.add_argument(
        "--platforms",
        default="email,x,nostr",
        help="Comma-separated platform list (default: email,x,nostr)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Max items to fetch per platform",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Log what would happen without writing to the DB",
    )
    parser.add_argument(
        "--log-check",
        action="store_true",
        dest="log_check",
        help="Log this run to comms_checks (used by the hermes-comms-check cron job)",
    )
    args = parser.parse_args(argv)

    platforms = [p.strip() for p in args.platforms.split(",") if p.strip()]

    try:
        conn = _connect()
    except IngestError as exc:
        print(f"[comms-ingest] ERROR: {exc.message}", file=sys.stderr)
        return exc.exit_code

    try:
        report = run_ingest(conn, platforms=platforms, limit=args.limit, dry_run=args.dry_run)
        print(compose_report(report))
        if args.log_check and not args.dry_run:
            log_comms_check(conn, report, platforms=platforms)
    except IngestError as exc:
        print(f"[comms-ingest] ERROR: {exc.message}", file=sys.stderr)
        return exc.exit_code
    finally:
        conn.close()

    # Return 0 if any platform succeeded; return 1 only if every platform errored.
    if report.get("platform_errors") and not report.get("new_items") and not report.get("existing_items"):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
