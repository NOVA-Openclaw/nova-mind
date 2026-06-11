#!/usr/bin/env python3
"""
proactive-gate-check.py — Deterministic gate checker for NOVA's proactive cascade.

Checks all 10 cascade step gates without LLM involvement. Outputs a structured
JSON manifest so the heartbeat agent can work only on actionable steps.

Exit code is always 0. Per-step errors are embedded in JSON output.

See: nova-mind#324
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
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

DB_DSN = "host=/var/run/postgresql dbname=nova_memory user=nova"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


def _db_connect():
    """Return a psycopg2 connection or raise if unavailable."""
    if not _DB_AVAILABLE:
        raise RuntimeError("psycopg2 not importable")
    return psycopg2.connect(DB_DSN)


def _step_error(msg: str) -> dict:
    return {"actionable": False, "error": msg}


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
        conn = _db_connect()
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


def check_step2_unanswered_sessions() -> dict:
    """
    Step 2: Recent user-facing sessions.
    Runs `openclaw sessions list --json` and counts sessions with ageMs < 24h.
    """
    ONE_DAY_MS = 86_400_000
    try:
        result = subprocess.run(
            ["openclaw", "sessions", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            return _step_error(
                f"openclaw sessions list failed (rc={result.returncode}): {result.stderr[:200]}"
            )
        payload = json.loads(result.stdout)
    except FileNotFoundError:
        return _step_error("openclaw CLI not found")
    except subprocess.TimeoutExpired:
        return _step_error("openclaw sessions list timed out")
    except (json.JSONDecodeError, ValueError) as exc:
        return _step_error(f"Failed to parse openclaw sessions list output: {exc}")

    sessions = payload.get("sessions", [])
    active: list[str] = []
    for sess in sessions:
        key = sess.get("key", "")
        age_ms = sess.get("ageMs", ONE_DAY_MS + 1)
        if age_ms >= ONE_DAY_MS:
            continue
        if not any(pat in key for pat in USER_SESSION_PATTERNS):
            continue
        if any(exc_pat in key for exc_pat in EXCLUDE_PATTERNS):
            continue
        active.append(key)

    count = len(active)
    if count > 0:
        return {
            "actionable": True,
            "reason": f"{count} recent active user-facing session(s)",
            "data": {"count": count, "sessions": active},
        }
    return {"actionable": False, "reason": "No recent active user-facing sessions"}


def check_step3_introspection() -> dict:
    """
    Step 3: Introspection gate.
    Compares current daily log lines + session transcript bytes + elapsed time
    against last recorded values. Any threshold exceeded → actionable.
    """
    # Load last introspection state
    try:
        with open(HEARTBEAT_STATE_JSON, "r") as fh:
            state = json.load(fh)
        last_introspect = state.get("lastIntrospection", {})
        last_lines = last_introspect.get("dailyLogLines")
        last_bytes = last_introspect.get("sessionTranscriptBytes")
        last_ts_str = last_introspect.get("timestamp")
    except FileNotFoundError:
        return {
            "actionable": True,
            "reason": "heartbeat-state.json missing — first run, trigger introspection",
        }
    except (json.JSONDecodeError, ValueError) as exc:
        return {
            "actionable": True,
            "reason": f"heartbeat-state.json malformed: {exc} — trigger introspection",
        }

    # Parse timestamp once; reused by the cooldown check and elapsed check below.
    last_ts = None
    last_ts_parse_error = None
    if last_ts_str:
        try:
            last_ts = _parse_iso(last_ts_str)
        except (ValueError, OverflowError) as exc:
            last_ts_parse_error = str(exc)

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
    msg = "0 open GitHub issues"
    if errors:
        msg += f" ({len(errors)} repo(s) had errors)"
    return {"actionable": False, "reason": msg, "data": result_dict}


def check_step8_unsolved_problems() -> dict:
    """Step 8: Unsolved problems with status != 'solved'."""
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


def check_step9_filesystem_hygiene() -> dict:
    """Step 9: Filesystem hygiene audit marker staleness."""
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


def check_step10_d100(prior_actionable_count: int) -> dict:
    """
    Step 10: D100 roll.

    MANDATORY (actionable=True) if no prior step was actionable.
    Optional (actionable=False, skippable) if at least one prior step was actionable.
    """
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

    # 2. Run all 10 gate checks
    steps: dict[str, dict] = {}

    steps["1_agent_chat"] = check_step1_agent_chat()
    steps["2_unanswered"] = check_step2_unanswered_sessions()
    steps["3_introspect"] = check_step3_introspection()
    steps["4_memory"] = check_step4_memory_maintenance()
    steps["5_entities"] = check_step5_entity_dedup()
    steps["6_tasks"] = check_step6_pending_tasks()
    steps["7_github"] = check_step7_github_issues()
    steps["8_research"] = check_step8_unsolved_problems()
    steps["9_filesystem"] = check_step9_filesystem_hygiene()

    # Count actionable steps 1-9 (excluding step 10)
    prior_actionable = [k for k, v in steps.items() if v.get("actionable")]
    steps["10_d100"] = check_step10_d100(len(prior_actionable))

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
        "summary": f"{actionable_count} of 10 steps actionable",
    }

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
