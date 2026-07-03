#!/usr/bin/env python3
"""
delta_check_and_migrate.py — Identify and migrate rows written to the legacy
nova_memory agent_chat tables after the initial migration.

Issue: NOVA-Openclaw/nova-mind#320

The script is designed to be run repeatedly until it reports zero delta rows.
It supports two cutoffs:
  * --cutoff-id      : source rows with agent_chat.id > CUTOFF_ID are considered delta.
  * --cutoff-ts      : ISO 8601 timestamp; processed rows updated after this time
                       are also checked.

If neither cutoff is provided, the script uses the current maximum id and the
latest message timestamp in the target `agent_chat` database.

Collision handling:
  * If a source agent_chat row has the same id as a target row and the content
    matches, the source row is skipped (already present).
  * If the content differs, the script aborts without making changes; the
    operator must resolve the id-space conflict manually.
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from typing import Any

import psycopg2
from psycopg2 import sql
from psycopg2.extras import RealDictCursor


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check for and migrate delta rows from nova_memory to the agent_chat database."
    )
    parser.add_argument("--source-db", default="nova_memory", help="Source database (default: nova_memory)")
    parser.add_argument("--target-db", default="agent_chat", help="Target database (default: agent_chat)")
    parser.add_argument("--host", default="localhost", help="PostgreSQL host")
    parser.add_argument("--port", type=int, default=5432, help="PostgreSQL port")
    parser.add_argument("--user", default="postgres", help="PostgreSQL superuser")
    parser.add_argument("--password", default=None, help="PostgreSQL password (optional, .pgpass preferred)")
    parser.add_argument("--cutoff-id", type=int, default=None, help="Agent_chat.id cutoff (default: target max id)")
    parser.add_argument(
        "--cutoff-ts",
        default=None,
        help="ISO 8601 timestamp for processed-row updates (default: target newest timestamp)",
    )
    parser.add_argument(
        "--migrate",
        action="store_true",
        help="Actually migrate detected delta rows. Without this flag the script reports only.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print SQL that would be executed without running it.",
    )
    return parser.parse_args()


def connect(dbname: str, args: argparse.Namespace) -> psycopg2.connection:
    conn_kwargs: dict[str, Any] = {
        "host": args.host,
        "port": args.port,
        "user": args.user,
        "dbname": dbname,
    }
    if args.password:
        conn_kwargs["password"] = args.password
    return psycopg2.connect(**conn_kwargs)


def scalar(conn: psycopg2.connection, query: sql.Composed | str, params: tuple[Any, ...] = ()) -> Any:
    with conn.cursor() as cur:
        cur.execute(query, params)
        row = cur.fetchone()
        return row[0] if row else None


def query_rows(conn: psycopg2.connection, query: sql.Composed | str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(query, params)
        return [dict(row) for row in cur.fetchall()]


def build_comparable(row: dict[str, Any]) -> tuple[Any, ...]:
    """Return a hashable tuple of the columns that identify content."""
    return (
        row["id"],
        row["sender"],
        row["message"],
        row["recipients"],
        row["reply_to"],
        row["timestamp"].replace(tzinfo=timezone.utc) if row["timestamp"] and row["timestamp"].tzinfo is None else row["timestamp"],
    )


def build_processed_comparable(row: dict[str, Any]) -> tuple[Any, ...]:
    ts_cols = ["received_at", "routed_at", "responded_at"]
    values = [row["chat_id"], row["agent"], row["status"], row["error_message"]]
    for col in ts_cols:
        v = row.get(col)
        if v and v.tzinfo is None:
            v = v.replace(tzinfo=timezone.utc)
        values.append(v)
    return tuple(values)


def parse_cutoff_ts(value: str) -> datetime:
    value = value.strip().replace("Z", "+00:00")
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def main() -> int:
    args = parse_args()

    if args.dry_run:
        print("DRY-RUN mode: no changes will be made.")

    source = connect(args.source_db, args)
    target = connect(args.target_db, args)

    try:
        # Determine cutoffs if not provided.
        if args.cutoff_id is None:
            cutoff_id = scalar(target, "SELECT COALESCE(max(id), 0) FROM public.agent_chat")
        else:
            cutoff_id = args.cutoff_id

        if args.cutoff_ts is None:
            cutoff_ts = scalar(target, "SELECT max(\"timestamp\") FROM public.agent_chat")
        else:
            cutoff_ts = parse_cutoff_ts(args.cutoff_ts)

        print(f"Using cutoff id: {cutoff_id}")
        print(f"Using cutoff timestamp: {cutoff_ts}")

        # ------------------------------------------------------------------
        # agent_chat delta
        # ------------------------------------------------------------------
        source_chat = query_rows(
            source,
            "SELECT id, sender, message, recipients, reply_to, \"timestamp\" FROM public.agent_chat WHERE id > %s ORDER BY id",
            (cutoff_id,),
        )
        target_chat = query_rows(
            target,
            "SELECT id, sender, message, recipients, reply_to, \"timestamp\" FROM public.agent_chat WHERE id > %s ORDER BY id",
            (cutoff_id,),
        )

        target_chat_by_id = {row["id"]: row for row in target_chat}

        delta_chat: list[dict[str, Any]] = []
        collisions: list[tuple[dict[str, Any], dict[str, Any]]] = []

        for srow in source_chat:
            tid = srow["id"]
            trow = target_chat_by_id.get(tid)
            if trow is None:
                delta_chat.append(srow)
            elif build_comparable(srow) != build_comparable(trow):
                collisions.append((srow, trow))

        print(f"\nagent_chat rows in source > cutoff id {cutoff_id}: {len(source_chat)}")
        print(f"agent_chat rows in target > cutoff id {cutoff_id}: {len(target_chat)}")
        print(f"agent_chat delta rows to migrate: {len(delta_chat)}")
        print(f"agent_chat id collisions: {len(collisions)}")

        if collisions:
            print("\nERROR: id-space collisions detected. Manual resolution required.", file=sys.stderr)
            for srow, trow in collisions[:10]:
                print(f"  id={srow['id']} source_sender={srow['sender']} target_sender={trow['sender']}", file=sys.stderr)
            if len(collisions) > 10:
                print(f"  ... and {len(collisions) - 10} more", file=sys.stderr)
            return 2

        # ------------------------------------------------------------------
        # agent_chat_processed delta
        # ------------------------------------------------------------------
        # Two categories:
        #   A) processed rows for newly-detected chat ids
        #   B) processed rows for existing chat ids updated after cutoff_ts
        source_processed_delta_ids = {r["id"] for r in delta_chat}

        if source_processed_delta_ids:
            source_proc_a = query_rows(
                source,
                "SELECT chat_id, agent, received_at, routed_at, responded_at, error_message, status "
                "FROM public.agent_chat_processed WHERE chat_id = ANY(%s)",
                (list(source_processed_delta_ids),),
            )
        else:
            source_proc_a = []

        source_proc_b = query_rows(
            source,
            "SELECT chat_id, agent, received_at, routed_at, responded_at, error_message, status "
            "FROM public.agent_chat_processed "
            "WHERE chat_id <= %s AND ("
            "      received_at > %s OR routed_at > %s OR responded_at > %s"
            ")",
            (cutoff_id, cutoff_ts, cutoff_ts, cutoff_ts),
        )

        # Combine and de-duplicate by (chat_id, agent)
        source_processed: dict[tuple[Any, Any], dict[str, Any]] = {}
        for row in source_proc_a + source_proc_b:
            source_processed[(row["chat_id"], row["agent"])] = row

        # Fetch corresponding target rows for comparison.
        # Use a temporary table because composite-array parameter passing is
        # brittle across psycopg2 versions.
        target_processed: list[dict[str, Any]] = []
        if source_processed:
            keys = list(source_processed.keys())
            with target.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("CREATE TEMP TABLE _delta_proc_keys (chat_id int, agent varchar(50)) ON COMMIT DROP")
                for chat_id, agent in keys:
                    cur.execute("INSERT INTO _delta_proc_keys VALUES (%s, %s)", (chat_id, agent))
                cur.execute(
                    "SELECT p.chat_id, p.agent, p.received_at, p.routed_at, p.responded_at, "
                    "       p.error_message, p.status "
                    "FROM public.agent_chat_processed p "
                    "JOIN _delta_proc_keys k USING (chat_id, agent)"
                )
                target_processed = [dict(row) for row in cur.fetchall()]
            # Stay in the same transaction for the comparison; commit later.
            target.rollback()  # drop temp table, no actual changes yet

        target_proc_by_key = {(r["chat_id"], r["agent"]): r for r in target_processed}

        proc_to_insert: list[dict[str, Any]] = []
        proc_to_update: list[dict[str, Any]] = []

        for key, srow in source_processed.items():
            trow = target_proc_by_key.get(key)
            if trow is None:
                proc_to_insert.append(srow)
            elif build_processed_comparable(srow) != build_processed_comparable(trow):
                proc_to_update.append(srow)

        print(f"\nagent_chat_processed delta rows to insert: {len(proc_to_insert)}")
        print(f"agent_chat_processed delta rows to update: {len(proc_to_update)}")

        # ------------------------------------------------------------------
        # Apply changes
        # ------------------------------------------------------------------
        if not args.migrate:
            total_delta = len(delta_chat) + len(proc_to_insert) + len(proc_to_update)
            if total_delta == 0:
                print("\nOK: No delta rows found. Migration is clean.")
                return 0
            print(f"\nREPORT-ONLY: {total_delta} delta rows would be migrated. Re-run with --migrate to apply.")
            return 1

        if args.dry_run:
            print(f"\nDRY-RUN: Would insert {len(delta_chat)} agent_chat rows.")
            print(f"DRY-RUN: Would insert {len(proc_to_insert)} and update {len(proc_to_update)} agent_chat_processed rows.")
            print("DRY-RUN: Would re-set agent_chat_id_seq to max(id) in target.")
            return 0

        if not delta_chat and not proc_to_insert and not proc_to_update:
            print("\nOK: No delta rows found. Migration is clean.")
            return 0

        print("\nApplying delta migration...")
        with target.cursor() as cur:
            # Bypass the insert enforcement trigger for the bulk delta load.
            cur.execute("SET LOCAL agent_chat.bypass_gate = 'on'")

            # Insert delta chat rows
            for row in delta_chat:
                cur.execute(
                    "INSERT INTO public.agent_chat (id, sender, message, recipients, reply_to, \"timestamp\") "
                    "VALUES (%s, %s, %s, %s, %s, %s)",
                    (row["id"], row["sender"], row["message"], row["recipients"], row["reply_to"], row["timestamp"]),
                )

            # Insert new processed rows
            for row in proc_to_insert:
                cur.execute(
                    "INSERT INTO public.agent_chat_processed "
                    "(chat_id, agent, received_at, routed_at, responded_at, error_message, status) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s)",
                    (
                        row["chat_id"],
                        row["agent"],
                        row["received_at"],
                        row["routed_at"],
                        row["responded_at"],
                        row["error_message"],
                        row["status"],
                    ),
                )

            # Update changed processed rows
            for row in proc_to_update:
                cur.execute(
                    "UPDATE public.agent_chat_processed SET "
                    "received_at = %s, routed_at = %s, responded_at = %s, error_message = %s, status = %s "
                    "WHERE chat_id = %s AND agent = %s",
                    (
                        row["received_at"],
                        row["routed_at"],
                        row["responded_at"],
                        row["error_message"],
                        row["status"],
                        row["chat_id"],
                        row["agent"],
                    ),
                )

            # Re-align sequence
            cur.execute("SELECT setval('public.agent_chat_id_seq', (SELECT COALESCE(max(id), 1) FROM public.agent_chat), true)")

        target.commit()

        # Verify
        new_max_id = scalar(target, "SELECT max(id) FROM public.agent_chat")
        new_seq = scalar(target, "SELECT last_value FROM public.agent_chat_id_seq")
        print(f"\nSUCCESS: Delta migration applied.")
        print(f"  Inserted agent_chat rows: {len(delta_chat)}")
        print(f"  Inserted agent_chat_processed rows: {len(proc_to_insert)}")
        print(f"  Updated agent_chat_processed rows: {len(proc_to_update)}")
        print(f"  New max(agent_chat.id): {new_max_id}")
        print(f"  Sequence last_value: {new_seq}")
        if new_seq < new_max_id:
            print("ERROR: Sequence last_value is below max(id)!", file=sys.stderr)
            return 3

        return 0

    finally:
        source.close()
        target.close()


if __name__ == "__main__":
    sys.exit(main())
