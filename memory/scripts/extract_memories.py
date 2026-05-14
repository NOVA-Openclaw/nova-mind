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


def load_config_file(config_path: str) -> dict:
    """Load extraction config from JSON file. Returns empty dict on any error."""
    try:
        if os.path.isfile(config_path):
            with open(config_path, "r") as f:
                return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"[extract_memories] WARNING: Could not load config {config_path}: {e}", file=sys.stderr)
    return {}


# Config resolution: env var > config file > hardcoded default
CONFIG_PATH = os.path.expanduser("~/.openclaw/scripts/memory-extraction-config.json")
CONFIG = load_config_file(CONFIG_PATH)

DEFAULT_MODEL = CONFIG.get("model") or "deepseek/deepseek-v4-flash"
OPENROUTER_API_URL = CONFIG.get("api_url") or "https://openrouter.ai/api/v1/chat/completions"
CONFIG_MAX_TOKENS = CONFIG.get("max_tokens") or 2048

# ── DB helpers ────────────────────────────────────────────────────────────────

def get_db_connection():
    """Return a psycopg2 connection using PG* env vars."""
    return psycopg2.connect()


def lookup_default_visibility(sender_id: str, sender_provider: str, conn) -> str:
    """
    Look up the sender's default_visibility preference by matching
    their SENDER_ID (phone / UUID) to an entity_fact.

    Falls back to 'public' when not found.
    """
    if not sender_id or sender_id == "unknown":
        return "public"

    try:
        with conn.cursor() as cur:
            # Value-first scan (highest priority)
            value_match = _resolve_by_sender_id(sender_id, conn)
            if value_match is not None:
                cur.execute(
                    "SELECT value FROM entity_facts WHERE entity_id = %s AND key = 'default_visibility' LIMIT 1",
                    (value_match,),
                )
                row = cur.fetchone()
                if row and row[0]:
                    return row[0]

            # Normalise to digits only for phone matching
            digits_only = re.sub(r"[^0-9]", "", sender_id)
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


def _resolve_by_sender_id(sender_id: str, conn) -> Optional[int]:
    """Resolve entity by searching for sender_id as a VALUE in entity_facts.
    
    Platform IDs (Discord snowflakes, Telegram IDs, Signal UUIDs) are unique
    enough that matching on value alone is safe. We add a length/format guard
    to avoid false positives on short/common values.
    """
    if not sender_id or sender_id in ("", "unknown"):
        return None
    
    # Only do value-scan for IDs that look like platform identifiers
    # Discord snowflakes: 17-19 digits
    # Telegram IDs: 9-10 digits  
    # Signal UUIDs: 36 chars with hyphens
    # Phone numbers: 10-15 digits with optional +
    # Skip short/ambiguous values
    clean = sender_id.strip()
    if len(clean) < 8:
        return None
    
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT DISTINCT entity_id FROM entity_facts
            WHERE value = %s
            LIMIT 1
            """,
            (sender_id,)
        )
        row = cur.fetchone()
        if row:
            return row[0]
    
    return None


def resolve_source_entity_id(
    source_name: str, sender_id: str, sender_provider: str, conn
) -> Optional[int]:
    """Resolve a name/sender_id to a DB entity ID."""
    if not source_name or source_name in ("null", "unknown"):
        return None

    try:
        with conn.cursor() as cur:
            # 1. Value-first scan (highest priority)
            value_match = _resolve_by_sender_id(sender_id, conn)
            if value_match is not None:
                return value_match

            # 2. Legacy phone/UUID match (fallback)
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

            # 3. Name / nickname match (lowest priority)
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


def find_entity_id(
    subject_name: str,
    conn,
    sender_id: str = "",
    sender_provider: str = "",
    sender_name: str = "",
) -> Optional[int]:
    """Look up entity ID by name/full_name/nickname, with optional platform-ID priority."""
    if not subject_name or subject_name in ("null", "unknown"):
        return None
    try:
        with conn.cursor() as cur:
            # Self-reported facts: subject == sender → use platform ID lookup first
            if (
                sender_provider
                and sender_id
                and sender_name
                and subject_name.lower() == sender_name.lower()
            ):
                value_match = _resolve_by_sender_id(sender_id, conn)
                if value_match is not None:
                    return value_match

            # Fallback to name matching
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


def ensure_entity(
    name: str,
    entity_type: str,
    conn,
    sender_id: str = "",
    sender_provider: str = "",
    sender_name: str = "",
) -> Optional[int]:
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
            return find_entity_id(name, conn, sender_id, sender_provider, sender_name)
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
        SELECT id, extraction_count
        FROM entity_facts
        WHERE entity_id = %s AND LOWER(key) = LOWER(%s) AND LOWER(value) = LOWER(%s)
        LIMIT 1
        """,
        (entity_id, key, value),
    )
    row = cur.fetchone()
    if row:
        return {"id": row[0], "extraction_count": row[1]}

    # Fuzzy match (pg_trgm)
    try:
        cur.execute(
            """
            SELECT id, extraction_count,
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
            return {"id": row[0], "extraction_count": row[1], "fuzzy": True}
    except Exception:
        pass  # pg_trgm not installed — skip fuzzy

    return None


def store_or_reinforce_fact(
    entity_id: int,
    key: str,
    value: str,
    source_entity_id: Optional[int],
    visibility: str,
    visibility_reason: Optional[str],
    conn,
    src_channel_transcript_id: str = "",
    src_channel_session_id: str = "",
    durability: str = "long_term",
    category: str = "observation",
    expires: Optional[str] = None,
    source_citation: Optional[str] = None,
) -> str:
    """Insert fact or reinforce if already exists. Returns 'created' or 'reinforced'."""
    if src_channel_transcript_id:
        print(f"[extract_memories]   channel_transcript_id={src_channel_transcript_id}", file=sys.stderr)
    else:
        print(f"[extract_memories]   channel_transcript_id NOT SET", file=sys.stderr)
    if src_channel_session_id:
        print(f"[extract_memories]   channel_session_id={src_channel_session_id}", file=sys.stderr)
    else:
        print(f"[extract_memories]   channel_session_id NOT SET", file=sys.stderr)

    with conn.cursor() as cur:
        existing = find_existing_fact(entity_id, key, value, cur)
        if existing:
            # Reinforce
            update_parts = [
                "extraction_count = extraction_count + 1",
                "last_confirmed_at = NOW()",
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

            # Upsert source attribution in entity_fact_sources
            if source_entity_id is not None:
                cur.execute(
                    """
                    INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
                    VALUES (%s, %s, %s, 1, NOW(), NOW())
                    ON CONFLICT (fact_id, source_entity_id)
                    DO UPDATE SET
                        attribution_count = entity_fact_sources.attribution_count + 1,
                        last_seen = NOW()
                    """,
                    (existing["id"], source_entity_id, source_citation),
                )

            return "reinforced"
        else:
            # Insert new
            cols = ["entity_id", "key", "value", "visibility", "durability", "category"]
            vals: list = [entity_id, key, value, visibility, durability, category]
            ph = ["%s"] * 6

            if visibility_reason:
                cols.append("visibility_reason")
                vals.append(visibility_reason)
                ph.append("%s")
            if expires:
                cols.append("expires")
                vals.append(expires)
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
                f"INSERT INTO entity_facts ({', '.join(cols)}) VALUES ({', '.join(ph)}) RETURNING id",
                vals,
            )
            row = cur.fetchone()
            new_fact_id = row[0] if row else None

            # Insert source attribution
            if new_fact_id and source_entity_id is not None:
                cur.execute(
                    """
                    INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
                    VALUES (%s, %s, %s, 1, NOW(), NOW())
                    ON CONFLICT (fact_id, source_entity_id)
                    DO UPDATE SET
                        attribution_count = entity_fact_sources.attribution_count + 1,
                        last_seen = NOW()
                    """,
                    (new_fact_id, source_entity_id, source_citation),
                )

            return "created"


# ── Prompt builder ────────────────────────────────────────────────────────────

def build_extraction_prompt(
    text: str,
    sender: str,
    sender_id: str,
    sender_provider: str,
    is_group: bool,
    default_visibility: str,
) -> str:
    # Build a platform-aware sender label
    provider_label = sender_provider.lower() if sender_provider else "unknown"
    if provider_label == "discord":
        sender_label = f"Discord user ID: {sender_id}"
    elif provider_label == "signal":
        sender_label = f"Signal phone: {sender_id}"
    elif provider_label == "telegram":
        sender_label = f"Telegram user: {sender_id}"
    else:
        sender_label = f"{provider_label.capitalize()} user: {sender_id}" if sender_id else f"User: {sender}"

    return f"""Extract memory data as JSON from a conversation message.

SENDER: {sender}
SENDER_ID_LABEL: {sender_label}
IS_GROUP_CHAT: {is_group}
USER_DEFAULT_VISIBILITY: {default_visibility}

MESSAGE:
{text}

IMPORTANT INSTRUCTIONS:

1. EXTRACT facts, opinions, events, decisions, and other memory-worthy information from the message above.

2. FOR EVERY EXTRACTED ITEM, include:
   - subject: who the fact is ABOUT (may be the sender or someone else they're talking about)
   - visibility: privacy level (see below)
   - visibility_reason: ONLY if visibility differs from user default
   - durability: one of permanent, long_term, short_term, ephemeral (see DURABILITY GUIDANCE)
   - category: one of observation, preference, identity, mood, decision, routine, state, obligation (or other appropriate category)
   - expires: ISO-8601 timestamp if the statement implies a temporal boundary (e.g., "until Friday", "this week", "temporarily"), otherwise omit
   NOTE: Do NOT include source_person. Source attribution (who said it) is handled automatically from the sender metadata.

DURABILITY GUIDANCE:
- permanent: Identity facts that rarely change (name, birthplace, core traits). Never auto-decays.
- long_term: Durable preferences and observations (favorite color, career field). Slow decay.
- short_term: Current states and moods ("feeling stressed", "working on X"). Moderate decay.
- ephemeral: Temporary locations, travel plans, fleeting conditions. Aggressive decay.

CATEGORY LIST (examples, not exhaustive):
observation, preference, identity, mood, decision, routine, state, obligation
The LLM may use other appropriate categories not in this list.

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

IMPORTANT: Discord snowflakes (18-19 digit numeric IDs) must NEVER be extracted as phone numbers. They are discord_id facts only.

SOURCE CITATION (for facts from publications or external references):
When a fact references a publication or external source, include:
- source_citation: free-form text with publication metadata (author, publication, date, page, url)
Note: Source attribution (who told us) is always the message sender. source_citation is extra reference metadata.
Resolution hierarchy: author > publisher > publication title.

DELEGATION CONTEXT:
NOVA frequently delegates tasks to specialized agents. Extract agent delegation facts with subject="NOVA".
Known agents: Coder (coding), Gidget (git-ops), Scout (research), IRIS (creative), Hermes (comms), Scribe (docs), Ticker (portfolio), Athena (media), Newhart (meta/agents).

Return a JSON object. Omit empty arrays.

TEMPLATE:
{{
  "facts": [
    {{
      "subject": "Name of the person/entity this fact is ABOUT",
      "key": "descriptive_snake_case_key",
      "value": "the actual information",
      "category": "preference|observation|identity|mood|decision|routine|state|obligation",
      "durability": "permanent|long_term|short_term|ephemeral",
      "confidence": 1.0,
      "visibility": "public|private|trusted",
      "visibility_reason": "optional",
      "expires": "optional ISO-8601 timestamp"
    }}
  ],
  "entities": [
    {{"name": "Full name", "type": "person|ai|organization|place", "visibility": "public"}}
  ],
  "events": [
    {{"description": "what happened", "date": "ISO-8601 or natural language", "visibility": "public"}}
  ],
  "vocabulary": [
    {{"word": "the term", "category": "name|brand|technical|slang", "misheard_as": "optional", "visibility": "public"}}
  ]
}}

RULES:
- Source attribution is handled automatically. Do NOT include source_person in your output. The sender of the message is always the source.
- "subject" is who the fact is ABOUT (may differ from the sender for non-self-reported facts).
- A message may contain multiple distinct facts. Create one entry per distinct fact.
- Do NOT duplicate the same information under different keys. Each piece of information appears EXACTLY ONCE.
- Example: "I like pizza and my favorite color is blue" → TWO facts (food_preference + favorite_color), not one.
- Example: "I prefer Cherry Coke" → ONE fact (soda_preference), not two entries saying the same thing differently.
- The "category" field handles classification. Preferences, opinions, decisions, moods, routines — ALL go in "facts" with the appropriate category value.
- "key" must be a descriptive snake_case identifier (e.g., favorite_animals, current_city, opinion_on_vim, decision_package_manager). NEVER use generic keys like "preference_preference" or "observation_observation".
- Milestones are events — put them in "events".

PHONE NUMBER RULE: ANY extracted phone number MUST have visibility="private" regardless of the user's default_visibility or any explicit override in the message. This is a hard security rule.

TEMPORAL BOUNDARY RULE: When a statement implies a time limit (e.g., "I'll be in Austin until Friday", "working remotely this week"), set the "expires" field to an ISO-8601 timestamp. Do NOT set expires for permanent facts ("My name is Dustin").

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
        "max_tokens": CONFIG_MAX_TOKENS,
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
    sender_provider: str,
    src_timestamp: str,
    src_channel_transcript_id: str,
    src_channel_session_id: str,
    conn,
) -> None:
    """Persist extracted data to nova_memory tables."""
    source_entity_id = resolve_source_entity_id(sender_name, sender_id, sender_provider, conn)

    def _store_fact(
        subject_name: str,
        key: str,
        value: str,
        visibility: str,
        visibility_reason: Optional[str],
        durability: str = "long_term",
        category: str = "observation",
        expires: Optional[str] = None,
        source_citation: Optional[str] = None,
    ) -> None:
        """Find/create entity and store a fact.
        
        Source is ALWAYS the message sender (source_entity_id), resolved once
        at the top of store_extracted() from the sender_id. The LLM only
        identifies the subject (who the fact is about).
        """
        entity_id = find_entity_id(subject_name, conn, sender_id, sender_provider, sender_name)
        if entity_id is None:
            entity_id = ensure_entity(subject_name, "person", conn, sender_id, sender_provider, sender_name)
        if entity_id is None:
            print(
                f"[extract_memories] WARNING: Could not resolve entity for {subject_name!r}, skipping fact",
                file=sys.stderr,
            )
            return

        action = store_or_reinforce_fact(
            entity_id=entity_id,
            key=key,
            value=value,
            source_entity_id=source_entity_id,  # always the sender
            visibility=visibility,
            visibility_reason=visibility_reason,
            conn=conn,
            src_channel_transcript_id=src_channel_transcript_id,
            src_channel_session_id=src_channel_session_id,
            durability=durability,
            category=category,
            expires=expires,
            source_citation=source_citation,
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
        key = (fact.get("key") or fact.get("predicate") or "").strip()
        value = (fact.get("value") or "").strip()
        visibility = (fact.get("visibility") or "public").strip()
        visibility_reason = (fact.get("visibility_reason") or "").strip() or None
        durability = (fact.get("durability") or "long_term").strip()
        category = (fact.get("category") or "observation").strip()
        expires = (fact.get("expires") or "").strip() or None
        source_citation = (fact.get("source_citation") or "").strip() or None

        # Hard rule: phone numbers are always private
        if key == "phone":
            visibility = "private"
            visibility_reason = None

        if not (subject and key and value):
            continue

        _store_fact(subject, key, value, visibility, visibility_reason, durability, category, expires, source_citation)

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
                        "UPDATE vocabulary SET confirmation_count = COALESCE(confirmation_count, 0) + 1, last_confirmed = NOW() WHERE id = %s",
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

                vals_list.append(sender_name or "auto-extracted")
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
    sender_provider = os.environ.get("SENDER_PROVIDER", "").strip()

    print(
        f"[extract_memories] Channel context: transcript_id={src_channel_transcript_id!r} "
        f"session_id={src_channel_session_id!r}",
        file=sys.stderr,
    )
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
        default_visibility = lookup_default_visibility(sender_id, sender_provider, conn)

        # Ensure sender entity exists
        if sender_name and sender_name != "unknown":
            ensure_entity(sender_name, "person", conn, sender_id, sender_provider, sender_name)
            # If we have a sender_id that looks like a phone number, store it
            # Skip platform IDs (Discord snowflakes, Telegram chat IDs, etc.) — only store actual phone numbers
            if sender_id and sender_id not in ("", "unknown") and sender_provider in ("signal", "whatsapp", "sms", ""):
                entity_id = find_entity_id(sender_name, conn, sender_id, sender_provider, sender_name)
                if entity_id is not None:
                    digits = re.sub(r"[^0-9+]", "", sender_id)
                    # Only store if it looks like a real phone number (starts with + or has 10-15 digits)
                    if digits and (digits.startswith("+") or 10 <= len(digits) <= 15):
                        with conn.cursor() as cur:
                            cur.execute(
                                """
                                INSERT INTO entity_facts (entity_id, key, value, visibility, durability, category)
                                VALUES (%s, 'phone', %s, 'private', 'permanent', 'identity')
                                ON CONFLICT DO NOTHING
                                """,
                                (entity_id, sender_id),
                            )
                        conn.commit()

        # Build extraction prompt
        prompt = build_extraction_prompt(text.strip(), sender_name, sender_id, sender_provider, is_group, default_visibility)

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
            sender_provider=sender_provider,
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
