#!/usr/bin/env python3
"""
extract_memories.py — Unified memory extraction pipeline.

Replaces process-input.sh, extract-memories.sh, store-memories.sh.

Interface:
  - Reads message text from stdin
  - Env vars: SENDER_NAME, SENDER_ID, IS_GROUP, SOURCE_SESSION_ID,
              SOURCE_TIMESTAMP, SOURCE_CHANNEL_TRANSCRIPT_ID,
              SOURCE_CHANNEL_SESSION_ID, OPENROUTER_API_KEY,
              MEMORY_EXTRACTION_MODEL
  - Outputs extracted JSON to stdout
  - Exits 0 on success or empty extraction, non-zero on errors

Issues: #184 (bug), #112 (enhancement), #175 (enhancement), #141 (enhancement)
"""

import json
import os
import re
import sys
from typing import Any, Optional

import psycopg2
import psycopg2.extras
import requests

# ── Bootstrap: load OpenClaw env + pg config ──────────────────────────────────

sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))

try:
    from env_loader import load_openclaw_env
    load_openclaw_env()
except ImportError:
    pass  # Library not available; keys already in env

from pg_env import load_pg_env
load_pg_env()

# ── Constants ─────────────────────────────────────────────────────────────────

MIN_MESSAGE_LENGTH = 10  # characters (trimmed)
DEFAULT_MODEL = "google/gemini-2.5-flash-preview-05-20"
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"

# New extraction categories (additive to existing ones)
NEW_CATEGORIES = ("decisions", "milestones", "problems")
# Storage key mapping for new categories
NEW_CATEGORY_KEYS = {
    "decisions": "decision",
    "milestones": "milestone",
    "problems": "problem",
}


# ── DB helpers ────────────────────────────────────────────────────────────────

def get_db_connection():
    """Return a psycopg2 connection using PG* env vars."""
    return psycopg2.connect()


def lookup_default_visibility(sender_id: str, conn) -> str:
    """
    Look up the sender's default_visibility preference by matching
    their SENDER_ID (phone / UUID) to an entity_fact.

    Falls back to 'public' when not found.
    """
    if not sender_id or sender_id == "unknown":
        return "public"

    # Normalise to digits only for phone matching
    digits_only = re.sub(r"[^0-9]", "", sender_id)

    try:
        with conn.cursor() as cur:
            if digits_only:
                cur.execute(
                    """
                    SELECT ef2.value
                    FROM entity_facts ef1
                    JOIN entity_facts ef2 ON ef1.entity_id = ef2.entity_id
                    WHERE ef1.key IN ('phone', 'has_phone_number', 'signal')
                      AND REGEXP_REPLACE(ef1.value, '[^0-9]', '', 'g') = %s
                      AND ef2.key = 'default_visibility'
                    LIMIT 1
                    """,
                    (digits_only,),
                )
                row = cur.fetchone()
                if row and row[0]:
                    return row[0]

            # Also try UUID match (Signal, Discord, etc.)
            cur.execute(
                """
                SELECT ef2.value
                FROM entity_facts ef1
                JOIN entity_facts ef2 ON ef1.entity_id = ef2.entity_id
                WHERE ef1.key IN ('signal_uuid', 'discord_id', 'discord_username', 'github', 'email')
                  AND LOWER(ef1.value) = LOWER(%s)
                  AND ef2.key = 'default_visibility'
                LIMIT 1
                """,
                (sender_id,),
            )
            row = cur.fetchone()
            if row and row[0]:
                return row[0]
    except Exception as e:
        print(f"[extract_memories] WARNING: Could not look up default_visibility: {e}", file=sys.stderr)

    return "public"


def resolve_source_entity_id(source_name: str, sender_id: str, conn) -> Optional[int]:
    """Resolve a name/sender_id to a DB entity ID."""
    if not source_name or source_name in ("null", "unknown"):
        return None

    try:
        with conn.cursor() as cur:
            # Try phone/UUID match first
            if sender_id and sender_id not in ("", "unknown"):
                digits_only = re.sub(r"[^0-9]", "", sender_id)
                if digits_only:
                    cur.execute(
                        """
                        SELECT DISTINCT entity_id FROM entity_facts
                        WHERE key IN ('phone', 'has_phone_number', 'signal', 'signal_id')
                          AND REGEXP_REPLACE(value, '[^0-9]', '', 'g') = %s
                        LIMIT 1
                        """,
                        (digits_only,),
                    )
                    row = cur.fetchone()
                    if row:
                        return row[0]

            # Name / nickname match
            cur.execute(
                """
                SELECT id FROM entities
                WHERE LOWER(name) = LOWER(%s)
                   OR LOWER(full_name) = LOWER(%s)
                   OR LOWER(%s) = ANY(SELECT LOWER(unnest(nicknames)))
                LIMIT 1
                """,
                (source_name, source_name, source_name),
            )
            row = cur.fetchone()
            if row:
                return row[0]
    except Exception as e:
        print(f"[extract_memories] WARNING: Could not resolve entity id: {e}", file=sys.stderr)

    return None


def find_entity_id(subject_name: str, conn) -> Optional[int]:
    """Look up entity ID by name/full_name/nickname."""
    if not subject_name or subject_name in ("null", "unknown"):
        return None
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id FROM entities
                WHERE LOWER(name) = LOWER(%s)
                   OR LOWER(full_name) = LOWER(%s)
                   OR LOWER(%s) = ANY(SELECT LOWER(unnest(nicknames)))
                LIMIT 1
                """,
                (subject_name, subject_name, subject_name),
            )
            row = cur.fetchone()
            return row[0] if row else None
    except Exception:
        return None


# Valid entity types per DB constraint
VALID_ENTITY_TYPES = {"person", "ai", "organization", "pet", "stuffed_animal", "character", "other"}
PLACE_TYPES = {"place", "restaurant", "cafe", "bar", "venue"}


def normalize_entity_type(etype: str) -> str:
    """Map LLM-extracted types to DB-valid entity types."""
    etype = etype.lower().strip()
    if etype in VALID_ENTITY_TYPES:
        return etype
    if etype in PLACE_TYPES:
        return "other"
    return "other"


def ensure_entity(name: str, entity_type: str, conn) -> Optional[int]:
    """Insert entity if not already present; return its id."""
    entity_type = normalize_entity_type(entity_type)
    if not name or name in ("null", "unknown"):
        return None
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO entities (name, type)
                VALUES (%s, %s)
                ON CONFLICT DO NOTHING
                """,
                (name, entity_type),
            )
            conn.commit()
            return find_entity_id(name, conn)
    except Exception as e:
        print(f"[extract_memories] WARNING: Could not ensure entity {name!r}: {e}", file=sys.stderr)
        try:
            conn.rollback()
        except Exception:
            pass
        return None


def find_existing_fact(entity_id: int, key: str, value: str, cur) -> Optional[dict]:
    """Exact + fuzzy match for deduplication (mirrors dedup_helper.py)."""
    # Exact match
    cur.execute(
        """
        SELECT id, vote_count, confirmation_count
        FROM entity_facts
        WHERE entity_id = %s AND LOWER(key) = LOWER(%s) AND LOWER(value) = LOWER(%s)
        LIMIT 1
        """,
        (entity_id, key, value),
    )
    row = cur.fetchone()
    if row:
        return {"id": row[0], "vote_count": row[1], "confirmation_count": row[2]}

    # Fuzzy match (pg_trgm)
    try:
        cur.execute(
            """
            SELECT id, vote_count, confirmation_count,
                   similarity(LOWER(value), LOWER(%s)) AS sim
            FROM entity_facts
            WHERE entity_id = %s AND LOWER(key) = LOWER(%s)
              AND similarity(LOWER(value), LOWER(%s)) > 0.85
            ORDER BY sim DESC
            LIMIT 1
            """,
            (value, entity_id, key, value),
        )
        row = cur.fetchone()
        if row:
            return {"id": row[0], "vote_count": row[1], "confirmation_count": row[2], "fuzzy": True}
    except Exception:
        pass  # pg_trgm not installed — skip fuzzy

    return None


def store_or_reinforce_fact(
    entity_id: int,
    key: str,
    value: str,
    source_entity_id: Optional[int],
    source: str,
    visibility: str,
    visibility_reason: Optional[str],
    conn,
    src_channel_transcript_id: str = "",
    src_channel_session_id: str = "",
) -> str:
    """Insert fact or reinforce if already exists. Returns 'created' or 'reinforced'."""
    with conn.cursor() as cur:
        existing = find_existing_fact(entity_id, key, value, cur)
        if existing:
            # Reinforce
            update_parts = [
                "vote_count = vote_count + 1",
                "last_confirmed = NOW()",
                "last_confirmed_at = NOW()",
                "confirmation_count = COALESCE(confirmation_count, 0) + 1",
                "updated_at = NOW()",
            ]
            params: list = []

            if src_channel_transcript_id and src_channel_transcript_id.isdigit():
                update_parts.append(
                    "source_channel_transcript_id = COALESCE(source_channel_transcript_id, %s)"
                )
                params.append(int(src_channel_transcript_id))
            if src_channel_session_id and src_channel_session_id.isdigit():
                update_parts.append(
                    "source_channel_session_id = COALESCE(source_channel_session_id, %s)"
                )
                params.append(int(src_channel_session_id))

            params.append(existing["id"])
            cur.execute(
                f"UPDATE entity_facts SET {', '.join(update_parts)} WHERE id = %s",
                params,
            )
            return "reinforced"
        else:
            # Insert new
            cols = ["entity_id", "key", "value", "source", "visibility"]
            vals: list = [entity_id, key, value, source, visibility]
            ph = ["%s"] * 5

            if source_entity_id is not None:
                cols.append("source_entity_id")
                vals.append(source_entity_id)
                ph.append("%s")
            if visibility_reason:
                cols.append("visibility_reason")
                vals.append(visibility_reason)
                ph.append("%s")
            if src_channel_transcript_id and src_channel_transcript_id.isdigit():
                cols.append("source_channel_transcript_id")
                vals.append(int(src_channel_transcript_id))
                ph.append("%s")
            if src_channel_session_id and src_channel_session_id.isdigit():
                cols.append("source_channel_session_id")
                vals.append(int(src_channel_session_id))
                ph.append("%s")

            cur.execute(
                f"INSERT INTO entity_facts ({', '.join(cols)}) VALUES ({', '.join(ph)}) ON CONFLICT DO NOTHING",
                vals,
            )
            return "created"


# ── Prompt builder ────────────────────────────────────────────────────────────

def build_extraction_prompt(
    text: str,
    sender: str,
    is_group: bool,
    default_visibility: str,
) -> str:
    return f"""Extract memory data as JSON from a conversation message.

SENDER: {sender}
IS_GROUP_CHAT: {is_group}
USER_DEFAULT_VISIBILITY: {default_visibility}

MESSAGE:
{text}

IMPORTANT INSTRUCTIONS:

1. EXTRACT facts, opinions, events, decisions, and other memory-worthy information from the message above.

2. FOR EVERY EXTRACTED ITEM, include:
   - source_person: "{sender}" (who said this)
   - visibility: privacy level (see below)
   - visibility_reason: ONLY if visibility differs from user default

PRIVACY DETECTION:
The user's default visibility is "{default_visibility}".
- If default is "private": everything is private UNLESS they explicitly say otherwise
- If default is "public": everything is public UNLESS they explicitly say otherwise

Look for privacy cues that OVERRIDE the default:
- Make PUBLIC: "feel free to share", "this is public", "you can tell others"
- Make PRIVATE: "just between us", "don't tell anyone", "keep this secret", "confidential"

ENTITY ID EXTRACTION:
Extract the following contact identifiers as facts when present:
- Phone numbers: key="phone", normalize to E.164 (+countrycode digits, e.g. +15125550199), visibility="private" ALWAYS (hard rule — no exceptions)
- Email addresses: key="email", value=full address, visibility="private" by default
- Discord numeric IDs (18-19 digit snowflake): key="discord_id", value=numeric string (preserve full precision — do not cast to integer)
- Discord usernames/handles: key="discord_username", value=handle (strip leading @)
- GitHub handles: key="github", value=handle (strip leading @)
- Signal UUIDs (8-4-4-4-12 hex format): key="signal_uuid", value=UUID string
If a handle applies to both GitHub and Discord, create TWO separate facts with distinct keys.
Only extract phone numbers if they appear complete (full country code + subscriber number). Partial or ambiguous numbers (e.g. "555" alone) must NOT be extracted.

DELEGATION CONTEXT:
NOVA frequently delegates tasks to specialized agents. Extract agent delegation facts with subject="NOVA".
Known agents: Coder (coding), Gidget (git-ops), Scout (research), IRIS (creative), Hermes (comms), Scribe (docs), Ticker (portfolio), Athena (media), Newhart (meta/agents).

Return JSON with these categories (only include non-empty ones):

entities: [{{name, type (person|ai|organization|place), location?, source_person, visibility, visibility_reason?}}]
facts: [{{subject, predicate, value, source_person, confidence, visibility, visibility_reason?}}]
opinions: [{{holder, subject, opinion, source_person, confidence, visibility, visibility_reason?}}]
preferences: [{{person, category, preference, source_person, confidence, visibility, visibility_reason?}}]
vocabulary: [{{word, category, misheard_as?, source_person, visibility}}]
events: [{{description, date?, source_person, visibility, visibility_reason?}}]
decisions: [{{subject, decision, rationale?, source_person, confidence, visibility, visibility_reason?}}]
milestones: [{{description, date?, source_person, visibility, visibility_reason?}}]
problems: [{{description, status (open|solved), solution?, source_person, visibility, visibility_reason?}}]

PHONE NUMBER RULE: ANY extracted phone number MUST have visibility="private" regardless of the user's default_visibility or any explicit override in the message. This is a hard security rule.

If the message contains NO extractable new information (casual chat, acknowledgments, etc), return: {{}}

Return ONLY valid JSON, no markdown fences."""


# ── LLM call ──────────────────────────────────────────────────────────────────

def call_llm(prompt: str, api_key: str, model: str) -> dict:
    """
    Call OpenRouter API and return parsed JSON dict.

    Raises on HTTP errors or JSON parse failures.
    """
    payload = {
        "model": model,
        "max_tokens": 2048,
        "messages": [{"role": "user", "content": prompt}],
    }
    try:
        resp = requests.post(
            OPENROUTER_API_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=60,
        )
    except requests.exceptions.RequestException as e:
        raise RuntimeError(f"LLM API call failed: {e}") from e

    if resp.status_code != 200:
        raise RuntimeError(
            f"LLM API call failed: HTTP {resp.status_code}: {resp.text[:200]}"
        )

    try:
        resp_json = resp.json()
    except ValueError as e:
        raise RuntimeError(f"LLM API returned non-JSON response: {e}") from e

    content = None
    try:
        content = resp_json["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        pass

    if not content:
        # Empty response — treat as no-op
        return {}

    # Strip markdown fences if present
    content = content.strip()
    if content.startswith("```"):
        content = re.sub(r"^```[a-zA-Z]*\n?", "", content)
        content = re.sub(r"\n?```$", "", content)
        content = content.strip()

    try:
        parsed = json.loads(content)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"Failed to parse LLM response as JSON: {e}\nRaw: {content[:200]}"
        ) from e

    if not isinstance(parsed, dict):
        return {}

    return parsed


# ── Storage ───────────────────────────────────────────────────────────────────

def store_extracted(
    data: dict,
    sender_name: str,
    sender_id: str,
    src_timestamp: str,
    src_channel_transcript_id: str,
    src_channel_session_id: str,
    conn,
) -> None:
    """Persist extracted data to nova_memory tables."""
    source_entity_id = resolve_source_entity_id(sender_name, sender_id, conn)

    def _store_fact(
        subject_name: str,
        key: str,
        value: str,
        source_person: str,
        visibility: str,
        visibility_reason: Optional[str],
    ) -> None:
        """Find/create entity and store a fact."""
        entity_id = find_entity_id(subject_name, conn)
        if entity_id is None:
            entity_id = ensure_entity(subject_name, "person", conn)
        if entity_id is None:
            print(
                f"[extract_memories] WARNING: Could not resolve entity for {subject_name!r}, skipping fact",
                file=sys.stderr,
            )
            return

        src_eid = resolve_source_entity_id(source_person, sender_id, conn) if source_person else source_entity_id

        action = store_or_reinforce_fact(
            entity_id=entity_id,
            key=key,
            value=value,
            source_entity_id=src_eid,
            source=source_person or sender_name or "auto-extracted",
            visibility=visibility,
            visibility_reason=visibility_reason,
            conn=conn,
            src_channel_transcript_id=src_channel_transcript_id,
            src_channel_session_id=src_channel_session_id,
        )
        print(f"[extract_memories]   {action}: {subject_name}.{key} = {value[:60]}", file=sys.stderr)

    # ── entities ──────────────────────────────────────────────────────────────
    for ent in data.get("entities", []) or []:
        name = (ent.get("name") or "").strip()
        etype = (ent.get("type") or "other").strip()
        if not name:
            continue
        ensure_entity(name, etype, conn)
        print(f"[extract_memories]   entity: {name} ({etype})", file=sys.stderr)

    # ── facts ─────────────────────────────────────────────────────────────────
    for fact in data.get("facts", []) or []:
        subject = (fact.get("subject") or sender_name or "").strip()
        predicate = (fact.get("predicate") or "").strip()
        value = (fact.get("value") or "").strip()
        source_person = (fact.get("source_person") or sender_name or "").strip()
        visibility = (fact.get("visibility") or "public").strip()
        visibility_reason = (fact.get("visibility_reason") or "").strip() or None

        # Hard rule: phone numbers are always private
        if predicate == "phone":
            visibility = "private"
            visibility_reason = None

        if not (subject and predicate and value):
            continue

        _store_fact(subject, predicate, value, source_person, visibility, visibility_reason)

    # ── opinions ──────────────────────────────────────────────────────────────
    for opinion in data.get("opinions", []) or []:
        holder = (opinion.get("holder") or sender_name or "").strip()
        subject = (opinion.get("subject") or "").strip()
        opinion_text = (opinion.get("opinion") or "").strip()
        source_person = (opinion.get("source_person") or sender_name or "").strip()
        visibility = (opinion.get("visibility") or "public").strip()
        visibility_reason = (opinion.get("visibility_reason") or "").strip() or None

        if not (holder and subject and opinion_text):
            continue

        key = f"opinion_{subject}"
        _store_fact(holder, key, opinion_text, source_person, visibility, visibility_reason)

    # ── preferences ───────────────────────────────────────────────────────────
    for pref in data.get("preferences", []) or []:
        person = (pref.get("person") or pref.get("holder") or sender_name or "").strip()
        category = (pref.get("category") or "general").strip()
        preference = (pref.get("preference") or pref.get("likes") or pref.get("prefers") or "").strip()
        source_person = (pref.get("source_person") or sender_name or "").strip()
        visibility = (pref.get("visibility") or "public").strip()
        visibility_reason = (pref.get("visibility_reason") or "").strip() or None

        if not (person and preference):
            continue

        key = f"preference_{category}"
        _store_fact(person, key, preference, source_person, visibility, visibility_reason)

    # ── vocabulary ────────────────────────────────────────────────────────────
    for vocab in data.get("vocabulary", []) or []:
        word = (vocab.get("word") or "").strip()
        category = (vocab.get("category") or "custom").strip()
        misheard_as = vocab.get("misheard_as") or []
        if isinstance(misheard_as, str):
            misheard_as = [misheard_as] if misheard_as else []

        if not word:
            continue

        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT id FROM vocabulary WHERE LOWER(word) = LOWER(%s) LIMIT 1",
                    (word,),
                )
                row = cur.fetchone()
                if row:
                    cur.execute(
                        "UPDATE vocabulary SET vote_count = vote_count + 1, last_confirmed = NOW() WHERE id = %s",
                        (row[0],),
                    )
                    print(f"[extract_memories]   vocab reinforced: {word}", file=sys.stderr)
                else:
                    if misheard_as:
                        cur.execute(
                            "INSERT INTO vocabulary (word, category, misheard_as) VALUES (%s, %s, %s) ON CONFLICT (word) DO UPDATE SET misheard_as = EXCLUDED.misheard_as",
                            (word, category, misheard_as),
                        )
                    else:
                        cur.execute(
                            "INSERT INTO vocabulary (word, category) VALUES (%s, %s) ON CONFLICT (word) DO NOTHING",
                            (word, category),
                        )
                    print(f"[extract_memories]   vocab added: {word} ({category})", file=sys.stderr)
        except Exception as e:
            print(f"[extract_memories] WARNING: vocab storage failed for {word!r}: {e}", file=sys.stderr)
            try:
                conn.rollback()
            except Exception:
                pass

    # ── events ────────────────────────────────────────────────────────────────
    # events table requires: title (NOT NULL), event_date (NOT NULL)
    for event in data.get("events", []) or []:
        description = (event.get("description") or "").strip()
        source_person = (event.get("source_person") or sender_name or "").strip()
        date_val = (event.get("date") or "").strip() or None

        if not description:
            continue

        try:
            with conn.cursor() as cur:
                # Deduplicate on title (description truncated to 500 chars)
                title = description[:500]
                cur.execute(
                    "SELECT id FROM events WHERE LOWER(title) = LOWER(%s) LIMIT 1",
                    (title,),
                )
                if cur.fetchone():
                    print(f"[extract_memories]   event exists: {description[:60]}", file=sys.stderr)
                    continue

                # Use provided date, fallback to src_timestamp, fallback to NOW()
                event_date = date_val or src_timestamp or None
                event_date_expr = "%s::timestamptz" if event_date else "NOW()"

                cols = ["title", "description", "event_date", "source"]
                vals_list: list[Any] = [title, description]
                if event_date:
                    vals_list.append(event_date)
                else:
                    vals_list = [title, description]  # event_date uses NOW() literal

                vals_list.append(source_person or sender_name or "auto-extracted")
                ph_list = ["%s", "%s", event_date_expr, "%s"]

                cur.execute(
                    f"INSERT INTO events ({', '.join(cols)}) VALUES ({', '.join(ph_list)}) ON CONFLICT DO NOTHING",
                    vals_list,
                )
                print(f"[extract_memories]   event stored: {description[:60]}", file=sys.stderr)
        except Exception as e:
            print(f"[extract_memories] WARNING: event storage failed: {e}", file=sys.stderr)
            try:
                conn.rollback()
            except Exception:
                pass

    # ── new categories: decisions, milestones, problems ───────────────────────
    # All stored as entity_facts with key = 'decision' | 'milestone' | 'problem'

    for category_name in NEW_CATEGORIES:
        key_prefix = NEW_CATEGORY_KEYS[category_name]
        items = data.get(category_name, []) or []

        for item in items:
            source_person = (item.get("source_person") or sender_name or "").strip()
            visibility = (item.get("visibility") or "public").strip()
            visibility_reason = (item.get("visibility_reason") or "").strip() or None

            if category_name == "decisions":
                subject = (item.get("subject") or sender_name or "").strip()
                decision_text = (item.get("decision") or "").strip()
                rationale = (item.get("rationale") or "").strip()
                if not (subject and decision_text):
                    continue
                value = decision_text
                if rationale:
                    value = f"{decision_text} (rationale: {rationale})"
                _store_fact(subject, key_prefix, value, source_person, visibility, visibility_reason)

            elif category_name == "milestones":
                description = (item.get("description") or "").strip()
                if not description:
                    continue
                subject = sender_name
                _store_fact(subject, key_prefix, description, source_person, visibility, visibility_reason)

            elif category_name == "problems":
                description = (item.get("description") or "").strip()
                if not description:
                    continue
                status = (item.get("status") or "open").strip()
                solution = (item.get("solution") or "").strip()
                value = description
                if status:
                    value = f"[{status}] {description}"
                if solution and status == "solved":
                    value = f"[solved] {description} — solution: {solution}"
                subject = sender_name
                _store_fact(subject, key_prefix, value, source_person, visibility, visibility_reason)

    conn.commit()


# ── Main entry point ──────────────────────────────────────────────────────────

def main() -> int:
    """
    Read text from stdin, extract memories via LLM, store to DB.

    Returns process exit code (0 = success, 1 = error).
    """
    # Read message from stdin
    try:
        text = sys.stdin.read()
    except Exception as e:
        print(f"[extract_memories] ERROR: Failed to read stdin: {e}", file=sys.stderr)
        return 1

    # Minimum length guard (defense-in-depth; handler also checks this)
    if not text or len(text.strip()) < MIN_MESSAGE_LENGTH:
        print("[extract_memories] Skipping short or empty message", file=sys.stderr)
        print("{}")
        return 0

    # Read environment variables
    api_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        print("[extract_memories] ERROR: OPENROUTER_API_KEY not set", file=sys.stderr)
        return 1

    sender_name = os.environ.get("SENDER_NAME", "unknown").strip() or "unknown"
    sender_id = os.environ.get("SENDER_ID", "").strip()
    is_group_raw = os.environ.get("IS_GROUP", "false").lower()
    is_group = is_group_raw in ("true", "1", "yes")
    src_session_id = os.environ.get("SOURCE_SESSION_ID", "").strip()
    src_timestamp = os.environ.get("SOURCE_TIMESTAMP", "").strip()
    src_channel_transcript_id = os.environ.get("SOURCE_CHANNEL_TRANSCRIPT_ID", "").strip()
    src_channel_session_id = os.environ.get("SOURCE_CHANNEL_SESSION_ID", "").strip()
    model = os.environ.get("MEMORY_EXTRACTION_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL

    print(
        f"[extract_memories] Processing message from {sender_name!r} "
        f"(len={len(text.strip())}, model={model})",
        file=sys.stderr,
    )

    # DB connection (needed for visibility lookup and storage)
    try:
        conn = get_db_connection()
    except Exception as e:
        print(f"[extract_memories] ERROR: DB connection failed: {e}", file=sys.stderr)
        return 1

    try:
        # Look up sender's default visibility preference
        default_visibility = lookup_default_visibility(sender_id, conn)

        # Ensure sender entity exists
        if sender_name and sender_name != "unknown":
            ensure_entity(sender_name, "person", conn)
            # If we have a sender_id that looks like a phone number, store it
            if sender_id and sender_id not in ("", "unknown"):
                entity_id = find_entity_id(sender_name, conn)
                if entity_id is not None:
                    digits = re.sub(r"[^0-9+]", "", sender_id)
                    if digits:
                        with conn.cursor() as cur:
                            cur.execute(
                                """
                                INSERT INTO entity_facts (entity_id, key, value, source, visibility)
                                VALUES (%s, 'phone', %s, 'auto-extracted', 'private')
                                ON CONFLICT DO NOTHING
                                """,
                                (entity_id, sender_id),
                            )
                        conn.commit()

        # Build extraction prompt
        prompt = build_extraction_prompt(text.strip(), sender_name, is_group, default_visibility)

        # Call LLM
        extracted = call_llm(prompt, api_key, model)

        # Output extracted JSON to stdout
        print(json.dumps(extracted))

        if not extracted:
            print("[extract_memories] No data extracted (empty response)", file=sys.stderr)
            return 0

        # Store to DB
        store_extracted(
            data=extracted,
            sender_name=sender_name,
            sender_id=sender_id,
            src_timestamp=src_timestamp,
            src_channel_transcript_id=src_channel_transcript_id,
            src_channel_session_id=src_channel_session_id,
            conn=conn,
        )

        print("[extract_memories] Extraction complete", file=sys.stderr)
        return 0

    except RuntimeError as e:
        print(f"[extract_memories] ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"[extract_memories] UNHANDLED ERROR: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return 1
    finally:
        try:
            conn.close()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
