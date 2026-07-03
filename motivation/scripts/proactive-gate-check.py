#!/usr/bin/env python3
"""
proactive-gate-check.py — Deterministic gate checker for NOVA's proactive cascade.

Checks all 11 cascade step gates without LLM involvement. Outputs a structured
JSON manifest so the heartbeat agent can work only on actionable steps.

Exit code is always 0. Per-step errors are embedded in JSON output.

See: nova-mind#324
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from typing import Any

# ---------------------------------------------------------------------------
# Venv bootstrap — add nova venv site-packages so psycopg2 is importable
# even when running outside the venv. Match the venv path to the running
# Python version to avoid loading C extensions built for the wrong interpreter.
# ---------------------------------------------------------------------------
_PY_VER = f"python{sys.version_info.major}.{sys.version_info.minor}"
_VENV_SITE = os.path.expanduser(
    f"~/.local/share/nova/venv/lib/{_PY_VER}/site-packages"
)
if os.path.isdir(_VENV_SITE) and _VENV_SITE not in sys.path:
    sys.path.insert(0, _VENV_SITE)

try:
    import psycopg2
    _DB_AVAILABLE = True
except ImportError:
    _DB_AVAILABLE = False

# Load centralized PG config loader so agent_chat queries resolve to the
# dedicated messaging DB while memory-DB queries keep flat/memory config.
_PG_ENV_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"
)
if os.path.isdir(_PG_ENV_DIR) and _PG_ENV_DIR not in sys.path:
    sys.path.insert(0, _PG_ENV_DIR)

try:
    from pg_env import load_pg_env
    _PG_ENV_AVAILABLE = True
except ImportError:
    _PG_ENV_AVAILABLE = False

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
IDLE_THRESHOLD_MINUTES = int(os.environ.get("IDLE_THRESHOLD_MINUTES", "60"))

SESSIONS_JSON = os.path.expanduser(
    "~/.openclaw/agents/nova/sessions/sessions.json"
)
HEARTBEAT_STATE_JSON = os.path.expanduser(
    "~/.openclaw/workspace/memory/heartbeat-state.json"
)
HEARTBEAT_STATE_JSON_ALT = os.path.expanduser(
    "~/.openclaw/workspace/heartbeat-state.json"
)
MEMORY_MAINTENANCE_JSON = os.path.expanduser(
    "~/.openclaw/state/memory-maintenance-last-run.json"
)
FS_AUDIT_MARKER = os.path.expanduser("~/.openclaw/workspace/.last-fs-audit")

# Session key substrings that indicate a user-facing session.
USER_SESSION_PATTERNS = ("discord:channel", "signal:", "telegram:")

# Session key substrings that indicate bot/system sessions to exclude.
EXCLUDE_PATTERNS = (
    "heartbeat",
    "cron",
    "subagent",
    "github-check",
    "music-pipeline",
    "art-pipeline",
    "daily-report",
    "clawdhub-check",
    "gidget-upstream-sync",
)

# Introspection growth thresholds
INTROSPECT_LINE_THRESHOLD = 50       # lines of daily log growth
INTROSPECT_BYTE_THRESHOLD = 102400   # bytes of session transcript growth (100 KB)
INTROSPECT_TIME_THRESHOLD_H = 8      # hours since last introspection
INTROSPECT_MIN_INTERVAL_H = 2        # minimum interval between introspections (prevents heartbeat loop)

# Memory maintenance cooldown
MEMORY_MAINTENANCE_COOLDOWN_H = 4

# Filesystem audit staleness threshold
FS_AUDIT_STALENESS_DAYS = 7

# Blocker outreach cooldowns (issue #356)
BLOCKER_ENTITY_COOLDOWN_H = 24
BLOCKER_PER_BLOCKER_COOLDOWN_H = 72
BLOCKERS_PER_MESSAGE = 3

# D100 forced-roll threshold (issue #358)
D100_FORCED_COOLDOWN_H = 12

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _dsn_from_pg_env(section: str | None = None) -> str:
    """Build a psycopg2 DSN from pg_env, honoring the optional section key.

    Falls back to the original Unix-socket default when no host is configured,
    preserving pre-cutover behavior while still respecting explicit config.
    Password is intentionally omitted from the DSN string; libpq reads
    PGPASSWORD from the environment set by load_pg_env and/or .pgpass.
    """
    if not _PG_ENV_AVAILABLE:
        raise RuntimeError("pg_env loader not importable")
    env = load_pg_env(section=section)
    parts: list[str] = []
    host = env.get("PGHOST")
    if host:
        parts.append(f"host={host}")
    else:
        # Preserve the legacy Unix-socket default used by the hardcoded DSN.
        parts.append("host=/var/run/postgresql")
    if env.get("PGPORT"):
        parts.append(f"port={env['PGPORT']}")
    if env.get("PGDATABASE"):
        parts.append(f"dbname={env['PGDATABASE']}")
    if env.get("PGUSER"):
        parts.append(f"user={env['PGUSER']}")
    return " ".join(parts)


def _db_connect(section: str | None = None):
    """Return a psycopg2 connection for the requested config section."""
    if not _DB_AVAILABLE:
        raise RuntimeError("psycopg2 not importable")
    return psycopg2.connect(_dsn_from_pg_env(section=section))


def _memory_db_connect():
    """Connect to the agent's memory database (flat config keys)."""
    return _db_connect(section=None)


def _agent_chat_db_connect():
    """Connect to the agent_chat messaging database (nested section)."""
    return _db_connect(section="agent_chat")


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _iso_now() -> str:
    return _now_utc().strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_iso(ts: str) -> datetime:
    """Parse an ISO-8601 timestamp, returning a timezone-aware datetime."""
    ts = ts.rstrip("Z")
    if "+" in ts:
        ts = ts.split("+")[0]
    if "." in ts:
        ts = ts.split(".")[0]
    dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S")
    return dt.replace(tzinfo=timezone.utc)


def _step_error(msg: str) -> dict:
    return {"actionable": False, "error": msg}


def _load_heartbeat_state(path: str) -> tuple[dict[str, Any] | None, datetime | None]:
    """
    Load heartbeat state from a single JSON file.

    Returns (state_dict, timestamp_datetime) on success, or (None, None) if
    the file is missing or cannot be parsed.
    """
    try:
        with open(path, "r") as fh:
            state = json.load(fh)
        last_introspect = state.get("lastIntrospection", {})
        ts_str = last_introspect.get("timestamp")
        ts = None
        if ts_str:
            try:
                ts = _parse_iso(ts_str)
            except (ValueError, OverflowError):
                ts = None
        return state, ts
    except (FileNotFoundError, json.JSONDecodeError, ValueError):
        return None, None


# ---------------------------------------------------------------------------
# Idle detection
# ---------------------------------------------------------------------------

def check_idle() -> dict:
    """
    Read sessions.json and determine if NOVA has been idle long enough.

    Returns a dict with:
      idle: bool
      idle_minutes: float
      idle_threshold_minutes: int
      reason: str (on error/edge cases)
    """
    threshold_ms = IDLE_THRESHOLD_MINUTES * 60 * 1000
    now_ms = int(time.time() * 1000)

    try:
        with open(SESSIONS_JSON, "r") as fh:
            raw = fh.read()
        sessions = json.loads(raw)
    except FileNotFoundError:
        return {
            "idle": True,
            "idle_minutes": float("inf"),
            "idle_threshold_minutes": IDLE_THRESHOLD_MINUTES,
            "reason": "sessions.json not found — defaulting to idle",
        }
    except (json.JSONDecodeError, ValueError) as exc:
        return {
            "idle": True,
            "idle_minutes": float("inf"),
            "idle_threshold_minutes": IDLE_THRESHOLD_MINUTES,
            "reason": f"sessions.json malformed: {exc} — defaulting to idle",
        }

    latest_interaction_ms: int | None = None

    for key, session in sessions.items():
        # Must match at least one user-facing pattern
        if not any(pat in key for pat in USER_SESSION_PATTERNS):
            continue
        # Must NOT match any exclude pattern
        if any(exc in key for exc in EXCLUDE_PATTERNS):
            continue

        ts = session.get("lastInteractionAt")
        if ts is not None:
            try:
                ts_int = int(ts)
                if latest_interaction_ms is None or ts_int > latest_interaction_ms:
                    latest_interaction_ms = ts_int
            except (ValueError, TypeError):
                pass

    if latest_interaction_ms is None:
        return {
            "idle": True,
            "idle_minutes": float("inf"),
            "idle_threshold_minutes": IDLE_THRESHOLD_MINUTES,
            "reason": "No user-facing sessions found — defaulting to idle",
        }

    elapsed_ms = now_ms - latest_interaction_ms
    elapsed_minutes = elapsed_ms / 60000.0
    is_idle = elapsed_ms >= threshold_ms

    return {
        "idle": is_idle,
        "idle_minutes": round(elapsed_minutes, 1),
        "idle_threshold_minutes": IDLE_THRESHOLD_MINUTES,
    }


# ---------------------------------------------------------------------------
# Gate check functions — each returns a step result dict
# ---------------------------------------------------------------------------

def check_step1_agent_chat() -> dict:
    """Step 1: Unacknowledged agent_chat messages addressed to nova."""
    try:
        conn = _agent_chat_db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT count(*)
                        FROM agent_chat ac
                        WHERE 'nova' = ANY(ac.recipients)
                        AND NOT EXISTS (
                            SELECT 1 FROM agent_chat_processed acp
                            WHERE acp.chat_id = ac.id AND acp.agent = 'nova'
                        )
                    """)
                    count = cur.fetchone()[0]
            if count > 0:
                return {
                    "actionable": True,
                    "reason": f"{count} unacknowledged message(s) in agent_chat",
                    "data": {"count": count},
                }
            return {"actionable": False, "reason": "0 unacknowledged messages"}
        finally:
            conn.close()
    except Exception as exc:
        return _step_error(f"DB error: {exc}")


def _last_conversational_role(session_file: str) -> str | None:
    """Return the role ('user' or 'assistant') of the last conversational message in a session JSONL file.

    Skips toolResult, system, and other non-conversational entries.
    Returns None if no conversational message is found.
    """
    if not os.path.exists(session_file):
        return None
    try:
        with open(session_file, "r") as fh:
            lines = fh.readlines()
    except OSError:
        return None
    # Walk backwards to find last user or assistant message
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        role = entry.get("message", {}).get("role")
        if role in ("user", "assistant"):
            return role
    return None


def check_step2_unanswered_sessions() -> dict:
    """
    Step 2: Check for unanswered user messages in recent user-facing sessions.
    Reads sessions.json and checks each session's JSONL file to see if the last
    conversational message is from a user (i.e. unanswered).
    """
    ONE_DAY_MS = 86_400_000
    try:
        with open(SESSIONS_JSON, "r") as fh:
            sessions_data = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        return _step_error(f"Failed to read sessions.json: {exc}")

    now_ms = int(time.time() * 1000)
    unanswered: list[str] = []

    for key, sess in sessions_data.items():
        updated = sess.get("updatedAt", 0)
        age_ms = now_ms - updated
        if age_ms >= ONE_DAY_MS:
            continue
        if not any(pat in key for pat in USER_SESSION_PATTERNS):
            continue
        if any(exc_pat in key for exc_pat in EXCLUDE_PATTERNS):
            continue

        session_file = sess.get("sessionFile", "")
        if not session_file:
            continue

        last_role = _last_conversational_role(session_file)
        if last_role == "user":
            unanswered.append(key)

    count = len(unanswered)
    if count > 0:
        return {
            "actionable": True,
            "reason": f"{count} session(s) with unanswered user messages",
            "data": {"count": count, "sessions": unanswered},
        }
    return {"actionable": False, "reason": "No unanswered user messages in recent sessions"}


def check_step3_introspection() -> dict:
    """
    Step 3: Introspection gate.
    Compares current daily log lines + session transcript bytes + elapsed time
    against last recorded values. Any threshold exceeded → actionable.

    Reads heartbeat state from two mirrored locations and uses whichever
    copy has the more recent timestamp (primary wins ties).
    """
    # Load heartbeat state from both mirrors.
    primary_state, primary_ts = _load_heartbeat_state(HEARTBEAT_STATE_JSON)
    alt_state, alt_ts = _load_heartbeat_state(HEARTBEAT_STATE_JSON_ALT)

    if primary_state is None and alt_state is None:
        return {
            "actionable": True,
            "reason": "heartbeat-state.json missing or malformed in both locations — trigger introspection",
        }

    # Prefer the fresher mirror; primary wins ties.
    # Guard against None timestamps: treat None as "oldest possible".
    if alt_state is not None and (primary_state is None or (alt_ts is not None and (primary_ts is None or alt_ts > primary_ts))):
        state = alt_state
        source_path = HEARTBEAT_STATE_JSON_ALT
        stale_path = HEARTBEAT_STATE_JSON
    else:
        state = primary_state
        source_path = HEARTBEAT_STATE_JSON
        stale_path = HEARTBEAT_STATE_JSON_ALT

    last_introspect = state.get("lastIntrospection", {})
    last_lines = last_introspect.get("dailyLogLines")
    last_bytes = last_introspect.get("sessionTranscriptBytes")
    last_ts_str = last_introspect.get("timestamp")

    # Parse timestamp once; reused by the cooldown check and elapsed check below.
    last_ts = None
    last_ts_parse_error = None
    if last_ts_str:
        try:
            last_ts = _parse_iso(last_ts_str)
        except (ValueError, OverflowError) as exc:
            last_ts_parse_error = str(exc)

    # Best-effort sync: write the fresher state to the stale mirror if it exists.
    if source_path != stale_path and os.path.exists(stale_path):
        try:
            with open(stale_path, "w") as fh:
                json.dump(state, fh)
        except (OSError, TypeError):
            pass  # Non-fatal; sync is best-effort

    # Minimum interval floor — prevent over-firing (see nova-mind#326)
    if last_ts is not None:
        elapsed_h = (_now_utc() - last_ts).total_seconds() / 3600.0
        if elapsed_h < INTROSPECT_MIN_INTERVAL_H:
            remaining_h = INTROSPECT_MIN_INTERVAL_H - elapsed_h
            return {
                "actionable": False,
                "reason": f"Cooldown active, {remaining_h:.1f}h remaining",
                "data": {"elapsed_hours": round(elapsed_h, 1), "remaining_hours": round(remaining_h, 1)},
            }

    reasons: list[str] = []
    data: dict[str, Any] = {}

    # Check elapsed time
    if last_ts is not None:
        elapsed_h = (_now_utc() - last_ts).total_seconds() / 3600.0
        data["elapsed_hours"] = round(elapsed_h, 1)
        if elapsed_h >= INTROSPECT_TIME_THRESHOLD_H:
            reasons.append(
                f"{elapsed_h:.1f}h since last introspection (threshold {INTROSPECT_TIME_THRESHOLD_H}h)"
            )
    elif last_ts_parse_error:
        data["elapsed_error"] = last_ts_parse_error

    # Check daily log line growth
    today = _now_utc().strftime("%Y-%m-%d")
    daily_log = os.path.expanduser(f"~/.openclaw/workspace/memory/{today}.md")
    try:
        result = subprocess.run(
            ["wc", "-l", daily_log],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            current_lines = int(result.stdout.strip().split()[0])
            data["current_daily_log_lines"] = current_lines
            if last_lines is not None:
                line_growth = current_lines - last_lines
                data["line_growth"] = line_growth
                if line_growth >= INTROSPECT_LINE_THRESHOLD:
                    reasons.append(
                        f"{line_growth} new daily log lines (threshold {INTROSPECT_LINE_THRESHOLD})"
                    )
    except (subprocess.TimeoutExpired, ValueError, IndexError, FileNotFoundError):
        pass  # Non-fatal; skip this sub-check

    # Check session transcript byte growth
    sessions_dir = os.path.expanduser("~/.openclaw/agents/nova/sessions/")
    try:
        result = subprocess.run(
            ["bash", "-c", f"du -sb {sessions_dir}*.jsonl 2>/dev/null | awk '{{s+=$1}} END{{print s+0}}'"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0 and result.stdout.strip():
            current_bytes = int(result.stdout.strip())
            data["current_session_bytes"] = current_bytes
            if last_bytes is not None:
                byte_growth = current_bytes - last_bytes
                data["byte_growth"] = byte_growth
                if byte_growth >= INTROSPECT_BYTE_THRESHOLD:
                    reasons.append(
                        f"{byte_growth:,} bytes of new session transcripts "
                        f"(threshold {INTROSPECT_BYTE_THRESHOLD:,})"
                    )
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        pass

    if reasons:
        return {
            "actionable": True,
            "reason": "; ".join(reasons),
            "data": data,
        }
    return {
        "actionable": False,
        "reason": "No introspection threshold exceeded",
        "data": data,
    }


def check_step4_memory_maintenance() -> dict:
    """Step 4: Memory maintenance cooldown check."""
    try:
        with open(MEMORY_MAINTENANCE_JSON, "r") as fh:
            state = json.load(fh)
        last_run_str = state.get("last_run")
        if not last_run_str:
            return {"actionable": True, "reason": "No last_run in memory-maintenance state"}
        last_run = _parse_iso(last_run_str)
        elapsed_h = (_now_utc() - last_run).total_seconds() / 3600.0
        threshold_h = MEMORY_MAINTENANCE_COOLDOWN_H
        if elapsed_h >= threshold_h:
            return {
                "actionable": True,
                "reason": f"{elapsed_h:.1f}h since last memory maintenance (threshold {threshold_h}h)",
                "data": {"elapsed_hours": round(elapsed_h, 1)},
            }
        remaining_h = threshold_h - elapsed_h
        return {
            "actionable": False,
            "reason": f"Cooldown active, {remaining_h:.1f}h remaining",
            "data": {"elapsed_hours": round(elapsed_h, 1), "remaining_hours": round(remaining_h, 1)},
        }
    except FileNotFoundError:
        return {"actionable": True, "reason": "memory-maintenance-last-run.json missing"}
    except (json.JSONDecodeError, ValueError) as exc:
        return {"actionable": True, "reason": f"Could not parse memory maintenance state: {exc}"}


def check_step5_entity_dedup() -> dict:
    """Step 5: Entity deduplication candidates using pg_trgm similarity."""
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT count(*) FROM (
                            SELECT e1.id FROM entities e1
                            JOIN entities e2
                            ON e1.id < e2.id
                            AND similarity(e1.name, e2.name) > 0.8
                            LIMIT 1
                        ) sub
                    """)
                    count = cur.fetchone()[0]
            if count > 0:
                return {
                    "actionable": True,
                    "reason": "Entity dedup candidates found (similarity > 0.8)",
                    "data": {"candidates_found": True},
                }
            return {"actionable": False, "reason": "No entity dedup candidates"}
        finally:
            conn.close()
    except Exception as exc:
        err = str(exc)
        if "function similarity" in err.lower() or "pg_trgm" in err.lower():
            return _step_error("pg_trgm extension not available")
        return _step_error(f"DB error: {exc}")


def check_step6_pending_tasks() -> dict:
    """Step 6: Pending unblocked tasks assigned to NOVA (entity_id=1)."""
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT count(*) FROM tasks
                        WHERE status = 'pending'
                        AND assigned_to = 1
                        AND (blocked IS NULL OR blocked = false)
                    """)
                    count = cur.fetchone()[0]
            if count > 0:
                return {
                    "actionable": True,
                    "reason": f"{count} pending unblocked task(s)",
                    "data": {"count": count},
                }
            return {"actionable": False, "reason": "0 pending unblocked tasks"}
        finally:
            conn.close()
    except Exception as exc:
        return _step_error(f"DB error: {exc}")


def check_step7_github_issues() -> dict:
    """Step 7: Open GitHub issues across NOVA-Openclaw repos."""
    try:
        # Get list of repos
        result = subprocess.run(
            [
                "gh", "repo", "list", "NOVA-Openclaw",
                "--no-archived", "--limit", "50",
                "--json", "name", "-q", ".[].name",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return _step_error(
                f"gh repo list failed (rc={result.returncode}): {result.stderr[:200]}"
            )
        repos = [r.strip() for r in result.stdout.strip().splitlines() if r.strip()]
    except FileNotFoundError:
        return _step_error("gh CLI not found")
    except subprocess.TimeoutExpired:
        return _step_error("gh repo list timed out")

    if not repos:
        return {"actionable": False, "reason": "No repos found in NOVA-Openclaw"}

    total_issues = 0
    per_repo: dict[str, int] = {}
    errors: list[str] = []

    for repo in repos:
        try:
            result = subprocess.run(
                [
                    "gh", "issue", "list",
                    "--repo", f"NOVA-Openclaw/{repo}",
                    "--state", "open",
                    "--json", "number",
                    "-q", "length",
                ],
                capture_output=True,
                text=True,
                timeout=20,
            )
            if result.returncode != 0:
                errors.append(f"{repo}: {result.stderr[:100]}")
                continue
            count_str = result.stdout.strip()
            count = int(count_str) if count_str else 0
            if count > 0:
                per_repo[repo] = count
                total_issues += count
        except subprocess.TimeoutExpired:
            errors.append(f"{repo}: timed out")
        except (ValueError, TypeError) as exc:
            errors.append(f"{repo}: parse error {exc}")

    result_dict: dict[str, Any] = {
        "total": total_issues,
        "by_repo": per_repo,
    }
    if errors:
        result_dict["errors"] = errors

    if total_issues > 0:
        return {
            "actionable": True,
            "reason": f"{total_issues} open issue(s) across {len(per_repo)} repo(s)",
            "data": result_dict,
        }
    msg = "0 open Git issues"
    if errors:
        msg += f" ({len(errors)} repo(s) had errors)"
    return {"actionable": False, "reason": msg, "data": result_dict}


def _entity_channel_facts(entity_id: int) -> dict[str, str]:
    """Return available human contact channels for an entity from entity_facts.

    Keys: discord_id, discord_dm (same fact as discord_id), signal, slack, email.
    Values are the fact values. Agents use agent_chat instead.
    """
    channels: dict[str, str] = {}
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        SELECT key, value FROM entity_facts
                        WHERE entity_id = %s
                          AND key IN ('discord_id', 'signal', 'slack', 'email')
                        """,
                        (entity_id,),
                    )
                    for key, value in cur.fetchall():
                        if key == "discord_id":
                            channels["discord_channel"] = value
                            channels["discord_dm"] = value
                        else:
                            channels[key] = value
        finally:
            conn.close()
    except Exception:
        pass
    return channels


def _entity_is_agent(entity_id: int) -> bool:
    """Return True if this entity maps to a row in the agents table."""
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT 1 FROM agents WHERE entity_id = %s LIMIT 1",
                        (entity_id,),
                    )
                    return cur.fetchone() is not None
        finally:
            conn.close()
    except Exception:
        return False


def _entity_name_lookup(entity_id: int) -> str | None:
    """Return entities.name for the given entity_id, or None on failure."""
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT name FROM entities WHERE id = %s LIMIT 1",
                        (entity_id,),
                    )
                    row = cur.fetchone()
                    return row[0] if row is not None else None
        finally:
            conn.close()
    except Exception:
        return None


def _map_cascade_to_channel(level: int, channels: dict[str, str], is_agent: bool) -> str:
    """Map a computed cascade level to a concrete channel.

    Agents always map to agent_chat. Humans escalate through available
    channels: discord_channel (1), discord_dm (2), signal (3), slack (4),
    email (5+). If the requested level has no fact, fall back to the last
    available channel (repeat-at-ceiling). If no channels exist, return
    'none'. Both the repeat-at-ceiling and no-channels cases are signals of
    *cascade exhaustion* for the entity — see _is_cascade_exhausted() and
    _reassign_exhausted_entity(), which detect this condition and drive
    reassignment/hold-at-I)ruid behavior. This function itself only maps
    level -> channel string; it does not decide reassignment.
    """
    if is_agent:
        return "agent_chat"
    order = ["discord_channel", "discord_dm", "signal", "slack", "email"]
    available = [ch for ch in order if ch in channels]
    if not available:
        return "none"
    idx = max(0, level - 1)
    if idx >= len(available):
        return available[-1]
    return available[idx]


def _is_cascade_exhausted(level: int, channels: dict[str, str], is_agent: bool) -> bool:
    """Return True if the cascade level exceeds the entity's available channels.

    Agents are never exhausted (agent_chat is unconditionally available).
    A human entity with zero channels is exhausted at any level >= 1.
    """
    if is_agent:
        return False
    order = ["discord_channel", "discord_dm", "signal", "slack", "email"]
    available_count = len([ch for ch in order if ch in channels])
    return level > available_count


def _entity_domain_topics(entity_id: int) -> list[str]:
    """Return domain_topic values for which this entity is the PRIMARY owner.

    Checks agent_domains first (joined via agents.entity_id), then
    user_domains. Per ruling TC-E07, when the same domain_topic exists in
    both tables, agent_domains wins as primary owner for that topic — so a
    topic already claimed by an agent is excluded from this entity's list
    if the entity itself is not that agent. Only used to find which topics
    an *exhausted* entity currently owns, so we can look up the next
    candidate for the same topic(s).
    """
    topics: set[str] = set()
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    # Topics this entity owns via agent_domains (entity is an agent).
                    cur.execute(
                        """
                        SELECT ad.domain_topic
                        FROM agent_domains ad
                        JOIN agents a ON a.id = ad.agent_id
                        WHERE a.entity_id = %s
                        """,
                        (entity_id,),
                    )
                    topics.update(r[0] for r in cur.fetchall())

                    # Topics this entity owns via user_domains, EXCLUDING any
                    # topic that agent_domains already claims for some agent
                    # (agent_domains wins ties per TC-E07 — a human's
                    # user_domains row for that topic is a fallback, not a
                    # primary ownership claim, when an agent also claims it).
                    cur.execute(
                        """
                        SELECT ud.domain_topic
                        FROM user_domains ud
                        WHERE ud.entity_id = %s
                          AND NOT EXISTS (
                              SELECT 1 FROM agent_domains ad2
                              WHERE ad2.domain_topic = ud.domain_topic
                          )
                        """,
                        (entity_id,),
                    )
                    topics.update(r[0] for r in cur.fetchall())
        finally:
            conn.close()
    except Exception:
        pass
    return sorted(topics)


def _next_domain_entity(domain_topic: str, exclude_entity_ids: set[int]) -> int | None:
    """Resolve the next-priority responsible entity for a domain topic.

    Resolution order matches curation (agent_domains first, then
    user_domains by priority ASC, tiebreak first_seen/id), excluding any
    entity already in exclude_entity_ids (already-exhausted entities in
    this reassignment chain). Returns None if no candidate remains.
    """
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    # agent_domains: domain_topic is globally unique per the
                    # current schema constraint, so at most one candidate.
                    cur.execute(
                        """
                        SELECT a.entity_id
                        FROM agent_domains ad
                        JOIN agents a ON a.id = ad.agent_id
                        WHERE ad.domain_topic = %s
                        """,
                        (domain_topic,),
                    )
                    row = cur.fetchone()
                    if row is not None and row[0] is not None and row[0] not in exclude_entity_ids:
                        return row[0]

                    # user_domains: lower priority number wins; tiebreak
                    # created_at ASC, id ASC (deterministic; the random
                    # tiebreak used in curation is for direct assignment,
                    # not reassignment which needs a stable next-candidate).
                    cur.execute(
                        """
                        SELECT entity_id
                        FROM user_domains
                        WHERE domain_topic = %s
                          AND entity_id != ALL(%s)
                        ORDER BY priority ASC, created_at ASC, id ASC
                        LIMIT 1
                        """,
                        (domain_topic, list(exclude_entity_ids) or [-1]),
                    )
                    row = cur.fetchone()
                    if row is not None:
                        return row[0]
        finally:
            conn.close()
    except Exception:
        return None
    return None


def _reassign_exhausted_entity(
    entity_id: int, exclude_entity_ids: set[int]
) -> tuple[int | None, bool]:
    """Find the reassignment target for an exhausted entity's blockers.

    Per ruling #7 (SE Run #333 Step 4) / TC-D07:
      1. Look up domain topics the exhausted entity currently owns as
         primary responsible entity.
      2. For each topic, find the next-priority domain entity (excluding
         already-exhausted entities in this chain).
      3. If any topic yields a candidate, reassign to it (first match wins;
         topics are not expected to disagree in practice, and picking the
         first deterministic match keeps this function total and simple).
      4. If no topic yields a candidate (or the entity owns no topics),
         fall back to entity_id = 2 (I)ruid) as the final fallback.

    Returns (new_entity_id, is_final_fallback). is_final_fallback is True
    when the returned entity is the I)ruid fallback (2) rather than a
    genuine domain-topic reassignment — callers use this to distinguish
    "reassigned to a peer" from "fell through to the catch-all."

    Callers must not invoke this for entity_id == 2 (I)ruid) — his
    exhaustion is a hold-in-place, not a reassignment; see
    check_step8_blocker_outreach for that branch.
    """
    topics = _entity_domain_topics(entity_id)
    chain_exclude = exclude_entity_ids | {entity_id}
    for topic in topics:
        candidate = _next_domain_entity(topic, chain_exclude)
        if candidate is not None:
            return candidate, False
    return 2, True


def check_step8_blocker_outreach() -> dict:
    """
    Step 8: Blocker outreach.

    Curates eligible open blockers for outreach. Returns actionable=True when
    at least one responsible entity has blockers ready for a new message.

    Eligibility:
      - entity master cooldown: >24h since ANY proactive_outreach row for the entity
      - per-blocker cooldown: >72h since a proactive_outreach row for
        (entity_id, blocker_type='blocker', blocker_id=blocker.id)
      - top-3 per entity ordered by priority ASC, first_seen ASC, id ASC

    Cascade level per blocker = prior proactive_outreach row count + 1.
    One message per entity is sent at the most-escalated requested level among
    its selected blockers; one proactive_outreach row is logged per blocker.

    Cascade exhaustion (ruling #7 / TC-D07): when an entity's max cascade
    level exceeds their available contact channels and they are not I)ruid
    (entity_id=2), the blocker set is reassigned to the next domain entity
    (via _reassign_exhausted_entity — agent_domains first, then
    user_domains by priority, excluding already-exhausted entities in the
    chain), eventually falling to I)ruid if every domain entity is exhausted.
    If I)ruid himself is the exhausted entity, no reassignment occurs — he
    holds at his last available channel/level and the normal 72h per-blocker
    cooldown continues to gate the next attempt. Each returned entity entry
    carries "exhausted" (True only for the I)ruid hold-in-place case) and,
    when reassignment occurred, the original "reassigned_from_entity_id".
    """
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        SELECT
                            b.id,
                            b.source_type,
                            b.source_ref,
                            b.description,
                            b.needs,
                            b.entity_id,
                            e.name AS entity_name,
                            b.priority,
                            b.first_seen,
                            COALESCE(po.attempt_count, 0) AS attempt_count,
                            COALESCE(po.latest_attempt, 'epoch'::timestamptz) AS latest_attempt
                        FROM blockers b
                        JOIN entities e ON e.id = b.entity_id
                        LEFT JOIN LATERAL (
                            SELECT
                                COUNT(*) AS attempt_count,
                                MAX(attempted_at) AS latest_attempt
                            FROM proactive_outreach
                            WHERE entity_id = b.entity_id
                              AND blocker_type = 'blocker'
                              AND blocker_id = b.id
                        ) po ON true
                        WHERE b.status = 'open'
                        ORDER BY b.entity_id, b.priority ASC, b.first_seen ASC, b.id ASC
                        """
                    )
                    rows = cur.fetchall()

                    # Entity master cooldown: latest ANY outreach to entity in last 24h
                    entity_ids = list({r[5] for r in rows})
                    entity_master: dict[int, datetime] = {}
                    if entity_ids:
                        cur.execute(
                            """
                            SELECT entity_id, MAX(attempted_at)
                            FROM proactive_outreach
                            WHERE entity_id = ANY(%s)
                            GROUP BY entity_id
                            """,
                            (entity_ids,),
                        )
                        entity_master = {
                            eid: ts for eid, ts in cur.fetchall() if ts is not None
                        }
        finally:
            conn.close()
    except Exception as exc:
        return _step_error(f"DB error: {exc}")

    now = _now_utc()
    entity_cooldown_cutoff = now - timedelta(hours=BLOCKER_ENTITY_COOLDOWN_H)
    blocker_cooldown_cutoff = now - timedelta(hours=BLOCKER_PER_BLOCKER_COOLDOWN_H)

    by_entity: dict[int, dict[str, Any]] = {}
    for row in rows:
        (
            bid, source_type, source_ref, description, needs,
            entity_id, entity_name, priority, first_seen,
            attempt_count, latest_attempt,
        ) = row

        # Entity master cooldown: strict > 24h elapsed required to be eligible,
        # i.e. blocked while master_latest >= cutoff (elapsed <= 24h exactly
        # still blocks).
        master_latest = entity_master.get(entity_id)
        if master_latest is not None and master_latest >= entity_cooldown_cutoff:
            continue

        # Per-blocker cooldown: strict > 72h elapsed required to be eligible,
        # i.e. blocked while latest_attempt >= cutoff (elapsed <= 72h exactly
        # still blocks).
        if latest_attempt >= blocker_cooldown_cutoff:
            continue

        cascade_level = int(attempt_count) + 1

        if entity_id not in by_entity:
            by_entity[entity_id] = {
                "entity_id": entity_id,
                "entity_name": entity_name,
                "channels": _entity_channel_facts(entity_id),
                "is_agent": _entity_is_agent(entity_id),
                "selected_blockers": [],
            }

        by_entity[entity_id]["selected_blockers"].append({
            "id": bid,
            "source_type": source_type,
            "source_ref": source_ref,
            "description": description,
            "needs": needs,
            "priority": priority,
            "first_seen": first_seen.isoformat() if first_seen else None,
            "cascade_level": cascade_level,
        })

    # Keep only top-3 per entity, compute actual channel, and detect/resolve
    # cascade exhaustion (ruling #7 / TC-D07): when max_level exceeds the
    # entity's available channels and the entity is not I)ruid, reassign to
    # the next domain entity (chain excludes already-exhausted entities),
    # eventually falling to I)ruid if every domain entity is exhausted. If
    # I)ruid himself is exhausted, hold him at his last available channel —
    # no reassignment, no fabricated level increase.
    eligible_entities: list[dict[str, Any]] = []
    for entity_id in sorted(by_entity.keys()):
        ent = by_entity[entity_id]
        selected = ent["selected_blockers"][:BLOCKERS_PER_MESSAGE]
        if not selected:
            continue
        max_level = max(b["cascade_level"] for b in selected)

        current_entity_id = entity_id
        current_channels = ent["channels"]
        current_is_agent = ent["is_agent"]
        current_entity_name = ent["entity_name"]
        exhausted_chain: list[int] = []
        reassigned = False
        exhaustion_hold = False

        while _is_cascade_exhausted(max_level, current_channels, current_is_agent):
            if current_entity_id == 2:
                # I)ruid is exhausted — hold at his last available level,
                # no further reassignment. Normal 72h cadence continues to
                # gate future attempts.
                exhaustion_hold = True
                break

            exhausted_chain.append(current_entity_id)
            new_entity_id, is_final_fallback = _reassign_exhausted_entity(
                current_entity_id, set(exhausted_chain)
            )
            if new_entity_id is None:
                # No candidate at all (defensive; _reassign_exhausted_entity
                # always returns entity 2 as a floor, but guard anyway).
                new_entity_id = 2
                is_final_fallback = True

            reassigned = True
            current_entity_id = new_entity_id
            # Reassignment restarts cascade level at 1 against the new
            # entity — no prior proactive_outreach rows exist against them
            # for this blocker set yet.
            max_level = 1
            current_channels = _entity_channel_facts(current_entity_id)
            current_is_agent = _entity_is_agent(current_entity_id)
            current_entity_name = (
                "I)ruid" if is_final_fallback and current_entity_id == 2
                else _entity_name_lookup(current_entity_id) or current_entity_name
            )

            if current_entity_id in exhausted_chain:
                # Defensive: avoid infinite loop if reassignment somehow
                # cycles back to an already-exhausted entity.
                break

        actual_channel = _map_cascade_to_channel(
            max_level, current_channels, current_is_agent
        )

        entry: dict[str, Any] = {
            "entity_id": current_entity_id,
            "entity_name": current_entity_name,
            "selected_blockers": selected,
            "max_cascade_level": max_level,
            "actual_channel": actual_channel,
            "is_agent": current_is_agent,
            "exhausted": exhaustion_hold,
        }
        if reassigned:
            entry["reassigned_from_entity_id"] = entity_id
        eligible_entities.append(entry)

    total = sum(len(e["selected_blockers"]) for e in eligible_entities)
    if total > 0:
        return {
            "actionable": True,
            "reason": f"{total} blocker(s) eligible across {len(eligible_entities)} entity/entities",
            "data": {
                "eligible_entities": eligible_entities,
                "total_eligible_blockers": total,
            },
        }
    return {"actionable": False, "reason": "No blockers eligible for outreach"}


def check_step9_unsolved_problems() -> dict:
    """Step 9: Unsolved problems with status != 'solved'."""
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        SELECT count(*) FROM unsolved_problems
                        WHERE status != 'solved'
                    """)
                    count = cur.fetchone()[0]
            if count > 0:
                return {
                    "actionable": True,
                    "reason": f"{count} unsolved problem(s) awaiting research",
                    "data": {"count": count},
                }
            return {"actionable": False, "reason": "0 unsolved problems"}
        finally:
            conn.close()
    except Exception as exc:
        return _step_error(f"DB error: {exc}")


def check_step10_filesystem_hygiene() -> dict:
    """Step 10: Filesystem hygiene audit marker staleness."""
    STALE_SECONDS = FS_AUDIT_STALENESS_DAYS * 86_400
    try:
        with open(FS_AUDIT_MARKER, "r") as fh:
            content = fh.read().strip()
        if not content:
            return {"actionable": True, "reason": f"{FS_AUDIT_MARKER} is empty — trigger audit"}

        last_audit = _parse_iso(content)
        elapsed = (_now_utc() - last_audit).total_seconds()
        elapsed_days = elapsed / 86_400

        if elapsed >= STALE_SECONDS:
            return {
                "actionable": True,
                "reason": f"Last audit {elapsed_days:.1f}d ago (threshold {FS_AUDIT_STALENESS_DAYS}d)",
                "data": {"elapsed_days": round(elapsed_days, 1)},
            }
        return {
            "actionable": False,
            "reason": f"Audited {elapsed_days:.1f}d ago (threshold {FS_AUDIT_STALENESS_DAYS}d)",
            "data": {"elapsed_days": round(elapsed_days, 1)},
        }
    except FileNotFoundError:
        return {"actionable": True, "reason": f"{FS_AUDIT_MARKER} missing — trigger audit"}
    except (ValueError, OverflowError) as exc:
        return {"actionable": True, "reason": f"Could not parse audit marker timestamp: {exc}"}


def check_step11_d100(prior_actionable_count: int) -> dict:
    """
    Step 11: D100 roll.

    MANDATORY (actionable=True) if no prior step was actionable.
    Optional (actionable=False, skippable) if at least one prior step was actionable.
    Also forced actionable if >12h since the last D100 roll (issue #358).
    """
    try:
        conn = _db_connect()
        try:
            with conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT MAX(rolled_at) FROM d100_roll_log")
                    row = cur.fetchone()
                    last_rolled = row[0]
        finally:
            conn.close()
    except Exception:
        last_rolled = None

    if last_rolled is None or (_now_utc() - last_rolled).total_seconds() > D100_FORCED_COOLDOWN_H * 3600:
        return {
            "actionable": True,
            "reason": "Forced — >12h since last D100 roll",
        }

    if prior_actionable_count == 0:
        return {
            "actionable": True,
            "reason": "Mandatory — no substantive work found in prior steps (catch-all)",
        }
    return {
        "actionable": False,
        "reason": f"Optional — {prior_actionable_count} prior step(s) already actionable",
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    timestamp = _iso_now()

    # 1. Idle detection — always runs first
    idle_result = check_idle()
    is_idle = idle_result.get("idle", True)
    idle_minutes = idle_result.get("idle_minutes", 0.0)

    base = {
        "timestamp": timestamp,
        "idle": is_idle,
        "idle_minutes": idle_minutes,
        "idle_threshold_minutes": IDLE_THRESHOLD_MINUTES,
    }

    if idle_result.get("reason"):
        base["idle_reason"] = idle_result["reason"]

    if not is_idle:
        print(json.dumps(base, indent=2))
        return

    # 2. Run all 11 gate checks
    steps: dict[str, dict] = {}

    steps["1_agent_chat"] = check_step1_agent_chat()
    steps["2_unanswered"] = check_step2_unanswered_sessions()
    steps["3_introspect"] = check_step3_introspection()
    steps["4_memory"] = check_step4_memory_maintenance()
    steps["5_entities"] = check_step5_entity_dedup()
    steps["6_tasks"] = check_step6_pending_tasks()
    steps["7_github"] = check_step7_github_issues()
    steps["8_blocker_outreach"] = check_step8_blocker_outreach()
    steps["9_research"] = check_step9_unsolved_problems()
    steps["10_filesystem"] = check_step10_filesystem_hygiene()

    # Count actionable steps 1-10 (excluding step 11)
    prior_actionable = [k for k, v in steps.items() if k != "11_d100" and v.get("actionable")]
    steps["11_d100"] = check_step11_d100(len(prior_actionable))

    # Collect final actionable step numbers
    actionable_steps: list[int] = []
    for key, val in steps.items():
        if val.get("actionable"):
            try:
                step_num = int(key.split("_")[0])
                actionable_steps.append(step_num)
            except ValueError:
                pass

    actionable_count = len(actionable_steps)

    output = {
        **base,
        "steps": steps,
        "actionable_steps": actionable_steps,
        "actionable_count": actionable_count,
        "summary": f"{actionable_count} of 11 steps actionable",
    }

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
