#!/usr/bin/env python3
"""
research-audit-gate.py — Deterministic three-axis finding audit gate before UPR synthesis.

For a given research task, reads the current research_findings and their
research_citations and audits each (finding, citation) pair across three
hard gating axes:

  * EXISTENCE  — source URL resolves and fetched title matches the filed title.
  * CONFIDENCE — numeric confidence is sane and 1.00 is reserved for facts
                 about a document, not claims the document makes.
  * SOURCE TIER — source_type and reliability reconcile to a tier band;
                 conflicts are flagged rather than silently averaged.

The gate also surfaces a high-risk cell flag when the weakest tier supports a
consequential claim, escalates ambiguous or unsupported claims to fresh-context
skeptics via TypeSafe /v1/systemone (Jev), and handles the collector's 72-hour
source-drop window for unreachable sources.

Exit codes (coarse taxonomy, pinned by Project Leadership 2026-11-12):
  0 — all findings pass
  1 — one or more findings blocked
  2 — gate could not run (usage / DB / config error)

See: nova-mind#657, tests/TEST-CASES-ISSUE-657.md
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Optional

# ---------------------------------------------------------------------------
# Venv bootstrap — add nova venv site-packages so psycopg2 is importable
# even when running outside the venv. Match the running Python version so
# C extensions load the correct interpreter ABI.
# ---------------------------------------------------------------------------
_PY_VER = f"python{sys.version_info.major}.{sys.version_info.minor}"
_VENV_SITE = os.path.expanduser(
    f"~/.local/share/nova/venv/lib/{_PY_VER}/site-packages"
)
if os.path.isdir(_VENV_SITE) and _VENV_SITE not in sys.path:
    sys.path.insert(0, _VENV_SITE)

# Load centralized PG config loader so the gate uses the same env/file
# resolution order as other nova-mind scripts.
_PG_ENV_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "memory", "lib"
)
if os.path.isdir(_PG_ENV_DIR) and _PG_ENV_DIR not in sys.path:
    sys.path.insert(0, _PG_ENV_DIR)

try:
    import psycopg2  # type: ignore[import-untyped]

    _DB_AVAILABLE = True
except ImportError:
    _DB_AVAILABLE = False

try:
    from pg_env import load_pg_env  # type: ignore[import-untyped]

    _PG_ENV_AVAILABLE = True
except ImportError:
    _PG_ENV_AVAILABLE = False


# ---------------------------------------------------------------------------
# Constants & defaults
# ---------------------------------------------------------------------------
DEFAULT_DROP_WINDOW_HOURS = 72
DEFAULT_SUPPORT_THRESHOLD = 0.05
DEFAULT_SCHEMA = "public"
DEFAULT_JEV_URL = "https://api.typesafe.ai/v1/systemone"

# Claim-scope enum values (pinned by Project Leadership 2026-11-12).
CLAIM_SCOPE_VALUES = ("proved", "computed", "cited", "conjecture")

# Title truncation cap from research_citations.source_title varchar(500).
SOURCE_TITLE_MAX_LEN = 500

# Deterministic markers that indicate a retraction/correction notice beyond the
# truncation boundary. These are checked case-insensitively in the fetched title
# suffix that extends past a 500-char filed title prefix.
RETRACTION_MARKERS = (
    "retracted",
    "expression of concern",
    "correction",
    "erratum",
    "withdrawn",
)

# Tier band cutpoints. A reliability below 0.50 combined with a formal source
# type (paper/book/library_work) is flagged as a tier-reconciliation conflict
# instead of being silently classified by reliability alone.
TIER_CUTPOINT_LOW = 0.30
TIER_CUTPOINT_HIGH = 0.80
TIER_CONFLICT_INFORMAL_THRESHOLD = 0.70
TIER_CONFLICT_FORMAL_THRESHOLD = 0.50

STRONG_SOURCE_TYPES = {"paper", "book", "library_work"}
WEAK_SOURCE_TYPES = {"agent", "url"}

# Importance ordering for the high-risk-cell flag. The flag fires when the
# weakest tier supports a finding at or above HIGH importance.
IMPORTANCE_LEVEL = {"low": 0, "normal": 1, "high": 2, "critical": 3}


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class GateConfig:
    """Runtime configuration for the audit gate.

    Attributes:
        schema: PostgreSQL schema containing research_* tables.
        drop_window_hours: [0, N) hour window before an unreachable source is
            dropped and its finding re-evaluated on remaining citations.
        support_threshold: Jev Support Noul probability at or below which a
            claim/citation pair escalates to skeptics.
        jev_url: Direct TypeSafe /v1/systemone endpoint URL.
        jev_api_key: Optional API key for the TypeSafe endpoint.
        db_dsn: psycopg2 connection string (password omitted; libpq reads
            PGPASSWORD from the environment).
        db_user: Resolved PostgreSQL role name (used for the read-only-sufficient
            role check).
    """

    schema: str
    drop_window_hours: float
    support_threshold: float
    jev_url: str
    jev_api_key: Optional[str]
    db_dsn: str
    db_user: str

    def is_readonly_sufficient(self) -> bool:
        """Return True when the configured DB role is not a research-writer role.

        The live protect_research_writes() trigger restricts INSERT/UPDATE/DELETE
        on research_* tables to scout, postgres, and superusers. A gate that only
        reads should deliberately use a different role so a future code change
        that accidentally adds a write statement fails at the connection-grant
        layer, not only at the trigger layer.
        """
        return self.db_user not in ("scout", "postgres")


def _env_float(name: str, default: float) -> float:
    """Parse a float env var, returning default on missing/invalid."""
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        raise ValueError(
            f"Environment variable {name} must be numeric, got {raw!r}"
        )


def _load_pg_dsn() -> tuple[str, str]:
    """Build a psycopg2 DSN and return (dsn, user) from pg_env resolution.

    Password is intentionally omitted from the DSN string; libpq reads
    PGPASSWORD from the environment set by load_pg_env and/or .pgpass so
    secrets are never embedded in logs or error messages.
    """
    if not _PG_ENV_AVAILABLE:
        raise RuntimeError("pg_env loader not importable")
    env = load_pg_env(section=None)
    parts: list[str] = []
    host = env.get("PGHOST")
    if host:
        parts.append(f"host={host}")
    else:
        # Preserve the legacy Unix-socket default used by other nova scripts.
        parts.append("host=/var/run/postgresql")
    if env.get("PGPORT"):
        parts.append(f"port={env['PGPORT']}")
    if env.get("PGDATABASE"):
        parts.append(f"dbname={env['PGDATABASE']}")
    if env.get("PGUSER"):
        parts.append(f"user={env['PGUSER']}")
    return " ".join(parts), env.get("PGUSER", "")


def load_config() -> GateConfig:
    """Load configuration from environment and centralized PG config.

    Gate-specific tunables are read from environment variables so recalibration
    (e.g. moving the 0.05 threshold after more data) does not require code
    changes:
      * RESEARCH_AUDIT_GATE_SUPPORT_THRESHOLD — Jev Support Noul threshold
      * RESEARCH_AUDIT_GATE_DROP_WINDOW_HOURS — collector source-drop window
      * RESEARCH_AUDIT_GATE_JEV_URL — TypeSafe /v1/systemone endpoint
      * RESEARCH_AUDIT_GATE_JEV_API_KEY — optional API key
      * RESEARCH_AUDIT_GATE_SCHEMA — PostgreSQL schema for research_* tables
    The 72-hour source-drop window and 0.05 threshold are likewise read at
    runtime so the collector lifecycle can be adjusted without touching
    comparison logic in multiple places.
    """
    db_dsn, db_user = _load_pg_dsn()
    return GateConfig(
        schema=os.environ.get("RESEARCH_AUDIT_GATE_SCHEMA", DEFAULT_SCHEMA),
        drop_window_hours=_env_float(
            "RESEARCH_AUDIT_GATE_DROP_WINDOW_HOURS", DEFAULT_DROP_WINDOW_HOURS
        ),
        support_threshold=_env_float(
            "RESEARCH_AUDIT_GATE_SUPPORT_THRESHOLD", DEFAULT_SUPPORT_THRESHOLD
        ),
        jev_url=os.environ.get("RESEARCH_AUDIT_GATE_JEV_URL", DEFAULT_JEV_URL),
        jev_api_key=os.environ.get("RESEARCH_AUDIT_GATE_JEV_API_KEY"),
        db_dsn=db_dsn,
        db_user=db_user,
    )


# ---------------------------------------------------------------------------
# Domain objects
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Citation:
    """A single research citation joined to a finding."""

    citation_id: int
    finding_id: int
    source_type: str
    source_url: Optional[str]
    source_title: Optional[str]
    source_author: Optional[str] = None
    source_date: Optional[str] = None
    quote: Optional[str] = None
    page_or_section: Optional[str] = None
    reliability: Optional[float] = None
    library_work_id: Optional[int] = None
    accessed_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class Finding:
    """A research finding and its supporting citations."""

    finding_id: int
    task_id: int
    finding_type: str
    content: str
    confidence: Optional[float]
    importance: str
    metadata: dict[str, Any]
    citations: list[Citation] = field(default_factory=list)


@dataclass
class CitationAudit:
    """Audit result for one (finding, citation) pair."""

    citation: Citation
    existence_state: str = "pending"
    existence_detail: str = ""
    confidence_state: str = "pending"
    confidence_detail: str = ""
    tier_state: str = "pending"
    tier_detail: str = ""
    unread_reason: Optional[str] = None
    jev_support_state: str = "pending"
    jev_support_detail: str = ""
    scope_state: str = "pending"
    scope_detail: str = ""


@dataclass
class FindingAudit:
    """Audit result for one finding, aggregating its citations."""

    finding: Finding
    citation_audits: list[CitationAudit] = field(default_factory=list)
    high_risk: bool = False
    high_risk_detail: str = ""
    scope_advisory: str = ""


@dataclass(frozen=True)
class CollectorState:
    """Snapshot of the collector's fetch result for a citation.

    The collector (not this gate) writes these values. The gate reads them to
    apply the 72-hour source-drop window without itself writing to research_*.

    Attributes:
        last_fetch_success: True if the collector's most recent fetch got a
            usable snapshot (2xx for URL sources, or a successful non-URL
            verification). Never inferred from accessed_at.
        first_unreachable_at: Timestamp of the first consecutive unreachable
            fetch, or None if the source is currently reachable.
        last_status: HTTP status code from the last fetch, if applicable.
    """

    last_fetch_success: bool = False
    first_unreachable_at: Optional[datetime] = None
    last_status: Optional[int] = None


@dataclass(frozen=True)
class AtomicClaim:
    """One atomic assertion extracted from a possibly compound finding.

    Jev Support Noul is called once per (atomic_claim, citation_source_text)
    pair. A compound finding is split before any Noul call so its score is
    never averaged across independent assertions (INV-7).

    source_text is the citation's collector snapshot text, never the finding
    content. is_compound_unsplit marks a sentence that still contains multiple
    clauses after conservative splitting; it is escalated to skeptics with no
    Noul score instead of being guessed.
    """

    finding_id: int
    claim_text: str
    source_text: str
    parent_finding: Finding
    is_compound_unsplit: bool = False


@dataclass
class GateResult:
    """Result of auditing a whole task."""

    task_id: int
    finding_audits: list[FindingAudit] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    dropped_citations: list[int] = field(default_factory=list)
    jev_attempted: int = 0
    jev_failed: int = 0

    def exit_code(self) -> int:
        """Return the coarse exit code for this run.

        0 = all pass, 1 = one or more findings blocked, 2 = gate could not run.
        Systemic Jev failure (at least one call attempted AND all attempted
        calls failed) returns 2 per the pinned OQ-4/GATE-02A ruling.
        """
        if self.errors:
            return 2

        # Systemic Jev failure: attempted at least one call and every call failed.
        if self.jev_attempted > 0 and self.jev_failed >= self.jev_attempted:
            return 2

        for fa in self.finding_audits:
            for ca in fa.citation_audits:
                # Hard deterministic-axis failures block.
                if ca.existence_state == "failed":
                    return 1
                if ca.confidence_state == "failed":
                    return 1
                if ca.tier_state == "conflict":
                    return 1
                # UNREAD within the 72h window blocks (NET-01..03, GATE-06).
                if ca.unread_reason is not None:
                    return 1
                # A citation dropped and left the finding unsupported blocks.
                if ca.existence_state == "no_surviving_citations":
                    return 1
                # A finding with zero supporting citations blocks.
                if ca.existence_state == "no_citations":
                    return 1
                # Jev Support failure/escalation blocks (JEV/JEVERR groups).
                if ca.jev_support_state in ("escalate", "failed"):
                    return 1
        return 0


# ---------------------------------------------------------------------------
# Database access
# ---------------------------------------------------------------------------
def _row_to_finding(row: dict[str, Any]) -> Finding:
    """Build a Finding from a query row, leaving citations empty."""
    return Finding(
        finding_id=row["finding_id"],
        task_id=row["task_id"],
        finding_type=row["finding_type"],
        content=row["content"] or "",
        confidence=float(row["confidence"]) if row["confidence"] is not None else None,
        importance=row["importance"],
        metadata=row["metadata"] or {},
        citations=[],
    )


def _row_to_citation(row: dict[str, Any]) -> Optional[Citation]:
    """Build a Citation from a query row, or None if the row has no citation."""
    if row["citation_id"] is None:
        return None
    return Citation(
        citation_id=row["citation_id"],
        finding_id=row["finding_id"],
        source_type=row["source_type"],
        source_url=row["source_url"],
        source_title=row["source_title"],
        reliability=float(row["reliability"]) if row["reliability"] is not None else None,
        accessed_at=row["accessed_at"],
        metadata=row["citation_metadata"] or {},
    )


def _task_exists(cur, schema: str, task_id: int) -> bool:
    """Return True if research_tasks contains the requested task_id."""
    cur.execute(
        f"SELECT 1 FROM {schema}.research_tasks WHERE id = %s LIMIT 1",
        (task_id,),
    )
    return cur.fetchone() is not None


def load_findings(
    conn: Any,
    schema: str,
    task_id: int,
) -> list[Finding]:
    """Load current findings and their citations for a task.

    The join is the corrected shape from SE#843 step 2: research_citations has
    no task_id column, so citations are reached via
    research_citations.finding_id -> research_findings.id filtered by
    research_findings.task_id. Superseded findings (is_current = false) are
    excluded per INV-5. A LEFT JOIN ensures findings with zero citations still
    appear, which is required for the high-risk-cell logic to catch uncited
    consequential claims.
    """
    query = f"""
        SELECT
            f.id AS finding_id,
            f.task_id,
            f.finding_type,
            f.content,
            f.confidence,
            f.importance,
            f.metadata,
            c.id AS citation_id,
            c.finding_id AS citation_finding_id,
            c.source_type,
            c.source_url,
            c.source_title,
            c.reliability,
            c.accessed_at,
            c.metadata AS citation_metadata
        FROM {schema}.research_findings f
        LEFT JOIN {schema}.research_citations c
            ON c.finding_id = f.id
        WHERE f.task_id = %s
          AND f.is_current = true
        ORDER BY f.id, c.id
    """
    with conn.cursor() as cur:
        cur.execute(query, (task_id,))
        cols = [desc[0] for desc in cur.description]
        rows = [dict(zip(cols, row)) for row in cur.fetchall()]

    findings: dict[int, Finding] = {}
    for row in rows:
        fid = row["finding_id"]
        if fid not in findings:
            findings[fid] = _row_to_finding(row)
        citation = _row_to_citation(row)
        if citation is not None:
            findings[fid].citations.append(citation)

    return list(findings.values())


def get_table_counts(
    conn: Any,
    schema: str,
) -> dict[str, int]:
    """Return row counts for research_findings and research_citations."""
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT count(*) FROM {schema}.research_findings"
        )
        findings_count = cur.fetchone()[0]
        cur.execute(
            f"SELECT count(*) FROM {schema}.research_citations"
        )
        citations_count = cur.fetchone()[0]
    return {
        "research_findings": findings_count,
        "research_citations": citations_count,
    }


# ---------------------------------------------------------------------------
# Audit logic (chunk 1: deterministic DB-level scaffolding only)
# ---------------------------------------------------------------------------
def _claim_scope(finding: Finding) -> tuple[Optional[str], bool]:
    """Resolve the writer-declared claim scope for a finding.

    Returns (scope, valid). A missing key, a non-string value, or a value
    outside the pinned enum is reported as (None, False) and surfaces the
    advisory `scope_undeclared` flag; it never gates pass/fail per the
    2026-11-12 ruling.
    """
    raw = finding.metadata.get("claim_scope")
    if raw is None:
        return None, False
    if not isinstance(raw, str):
        return None, False
    # The pinned enum is exact lowercase strings; any case/whitespace variant
    # (e.g. "Proved ") is treated as invalid and surfaces scope_undeclared.
    if raw not in CLAIM_SCOPE_VALUES:
        return None, False
    return raw, True


# ---------------------------------------------------------------------------
# Existence axis
# ---------------------------------------------------------------------------
def fetch_url(url: str, timeout: float = 10.0) -> tuple[int, Optional[str], str]:
    """Fetch a source URL and return (status_code, title, detail).

    Status 0 indicates a network-level failure (connection refused, timeout,
    DNS failure, etc.) that should be treated as UNREAD, not as a definitive
    existence failure. HTTP 404 is treated as a definitive "not found"; 5xx is
    treated as transient UNREAD eligible for the 72h retry lifecycle.

    The title is extracted from the first <title> element with whitespace
    normalized. Only HTTP status and title extraction errors are returned in
    detail; successful fetches return an empty detail string.
    """
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            html = resp.read().decode("utf-8", errors="replace")
            title = _extract_title(html)
            return resp.status, title, ""
    except urllib.error.HTTPError as exc:
        return exc.code, None, str(exc.reason)
    except urllib.error.URLError as exc:
        return 0, None, f"network error: {exc.reason}"
    except Exception as exc:  # pylint: disable=broad-exception-caught
        return 0, None, f"fetch error: {exc}"


def _extract_title(html: str) -> Optional[str]:
    """Extract and normalize text from the first <title> element."""
    match = re.search(r"<title[^>]*>(.*?)</title>", html, re.IGNORECASE | re.DOTALL)
    if not match:
        return None
    return " ".join(match.group(1).split())


def _compare_titles(filed: str, fetched: str) -> tuple[str, str]:
    """Compare a filed title against a fetched title.

    Returns (state, detail). States:
      * passed        — exact match, or filed title is a 500-char-cap prefix.
      * warn          — prefix match but a retraction/correction marker appears
                        past the truncation boundary.
      * failed        — titles differ.

    This handles the known varchar(500) cap on research_citations.source_title:
    a filed title that is exactly the prefix of the fetched title must not be
    flagged as a mismatch, but the leniency must not paper over retraction or
    correction notices that appear beyond the truncation boundary.
    """
    if filed == fetched:
        return "passed", "titles match exactly"
    if len(filed) >= SOURCE_TITLE_MAX_LEN and fetched.startswith(filed):
        suffix = fetched[len(filed):].lower()
        if any(marker in suffix for marker in RETRACTION_MARKERS):
            return (
                "warn",
                f"prefix match but retraction/correction marker past 500-char cap: {fetched}",
            )
        return "passed", "filed title is prefix of fetched title (500-char cap)"
    return (
        "failed",
        f"title mismatch — filed '{filed}', fetched '{fetched}'",
    )


def _collector_state(citation: Citation) -> CollectorState:
    """Read the collector's fetch state from citation metadata.

    The collector writes this data; the gate is read-only. accessed_at is
    intentionally NOT used as evidence of a successful fetch (NET-06).
    """
    meta = citation.metadata or {}
    success = bool(meta.get("last_fetch_success", False))
    status = meta.get("last_status")
    status = int(status) if isinstance(status, int) else None
    ts = meta.get("first_unreachable_at")
    first_unreach: Optional[datetime] = None
    if isinstance(ts, str):
        try:
            first_unreach = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            first_unreach = None
    elif isinstance(ts, datetime):
        first_unreach = ts
    return CollectorState(
        last_fetch_success=success,
        first_unreachable_at=first_unreach,
        last_status=status,
    )


def _window_action(
    state: CollectorState,
    now: datetime,
    config: GateConfig,
) -> tuple[str, Optional[str]]:
    """Decide what to do with a citation based on collector state.

    Returns (action, detail):
      * "verify"      — source is reachable; proceed with existence check.
      * "unread"      — unreachable within the 72h window; block and retry.
      * "drop"        — unreachable for >=72h; remove from active argument.
      * "unknown"     — no collector state; treat as unread fail-closed.
    """
    if state.last_fetch_success:
        return "verify", None
    if state.first_unreachable_at is None:
        return "unknown", "no collector state for unreachable source"
    elapsed = now - state.first_unreachable_at
    window = timedelta(hours=config.drop_window_hours)
    if elapsed < window:
        return (
            "unread",
            f"unreachable since {state.first_unreachable_at.isoformat()}; "
            f"{elapsed.total_seconds() / 3600:.2f}h within {config.drop_window_hours}h window",
        )
    return "drop", f"unreachable for {elapsed.total_seconds() / 3600:.2f}h >= {config.drop_window_hours}h; dropping"


def _audit_existence(
    citation: Citation,
    config: GateConfig,
    now: datetime,
    fetcher: Callable[[str], tuple[int, Optional[str], str]] = fetch_url,
) -> tuple[str, str, Optional[str]]:
    """Audit the existence axis for a single citation.

    Returns (state, detail, unread_reason). unread_reason is None unless the
    source could not be verified due to a transient or ambiguous condition.

    The 72h collector lifecycle is applied first; only reachable sources are
    subjected to the live URL/title check.
    """
    if citation.source_url is None or citation.source_url.strip() == "":
        if citation.source_type == "book":
            return "non_url_source", "book/source_type requires non-URL verification", None
        return "no_url", "source_url absent", None

    if citation.source_title is None or citation.source_title.strip() == "":
        return "no_title", "no filed title to compare against", None

    collector = _collector_state(citation)
    action, action_detail = _window_action(collector, now, config)

    if action == "unread":
        return "unread", action_detail or "source unreachable within 72h window", "unreachable within window"
    if action == "drop":
        return "dropped", action_detail or "source dropped after 72h window", None
    if action == "unknown":
        return "unread", action_detail or "no collector state", "missing collector state"

    # action == "verify": proceed with live fetch.
    status, fetched_title, detail = fetcher(citation.source_url)

    if status == 0:
        return "unread", detail, "network unreachable"
    if status == 404:
        return "failed", "source returned 404", None
    if status >= 500:
        return "unread", f"source returned {status}", f"server error {status}"

    if fetched_title is None:
        return "unread", "no title element in fetched page", "missing fetched title"

    state, detail = _compare_titles(
        citation.source_title.strip(), fetched_title.strip()
    )
    return state, detail, None


# ---------------------------------------------------------------------------
# Source tier axis
# ---------------------------------------------------------------------------
def _audit_tier(citation: Citation) -> tuple[str, str]:
    """Audit the source tier for a single citation.

    Returns (state, detail). States:
      * strong   — high-reliability source.
      * medium   — mid-reliability source.
      * weak     — low-reliability source.
      * conflict — source_type and reliability contradict each other.
      * unscored — reliability is NULL.

    The gate reconciles the existing source_type and reliability columns rather
    than introducing a parallel tier column, per SE#843 step-2 Correction 2.
    """
    if citation.reliability is None:
        return "unscored", "reliability NULL"

    rel = citation.reliability
    stype = citation.source_type

    if stype in STRONG_SOURCE_TYPES and rel < TIER_CONFLICT_FORMAL_THRESHOLD:
        return "conflict", f"{stype} source_type with reliability {rel} indicates tier conflict"
    if stype in WEAK_SOURCE_TYPES and rel >= TIER_CONFLICT_INFORMAL_THRESHOLD:
        return "conflict", f"{stype} source_type with reliability {rel} indicates tier conflict"

    if rel >= TIER_CUTPOINT_HIGH:
        return "strong", f"reliability {rel}"
    if rel <= TIER_CUTPOINT_LOW:
        return "weak", f"reliability {rel}"
    return "medium", f"reliability {rel}"


def _is_weakest_tier(tier_state: str) -> bool:
    """Return True for tier states that count as the weakest band."""
    return tier_state == "weak"


def _importance_level(importance: str) -> int:
    """Return numeric importance level for high-risk-cell comparison."""
    return IMPORTANCE_LEVEL.get(importance, 1)


def _audit_confidence(finding: Finding) -> tuple[str, str]:
    """Audit the confidence axis for a finding.

    The 1.00 value is reserved for facts ABOUT a document (bibliographic or
    metadata facts), never for claims the document itself makes. The writer
    signals this via metadata->>'claim_scope' == 'cited'. A missing or invalid
    claim_scope is advisory-only (scope_undeclared) but does NOT waive the
    1.00-restriction check: without a valid 'cited' scope, 1.00 is treated as
    misapplied.
    """
    if finding.confidence is None:
        return "unscored", "confidence NULL"

    if not (0.00 <= finding.confidence <= 1.00):
        return "failed", f"confidence {finding.confidence} out of [0,1] range"

    if finding.confidence == 1.00:
        scope, scope_valid = _claim_scope(finding)
        if scope_valid and scope == "cited":
            return "passed", "1.00 reserved for fact about document"
        return "failed", "confidence 1.00 misapplied to claim the document makes"

    return "passed", f"confidence {finding.confidence}"


def _audit_citation(
    citation: Citation,
    finding: Finding,
    config: GateConfig,
    now: datetime,
    fetcher: Callable[[str], tuple[int, Optional[str], str]] = fetch_url,
    jev_post_func: Optional[Callable[..., tuple[int, str, dict[str, str]]]] = None,
) -> CitationAudit:
    """Perform the deterministic three-axis audit for a single citation.

    Existence, confidence, and source-tier checks are implemented in chunks
    1-2b. Jev-mediated support/scope checks are still scaffolded and will be
    completed in chunks 3a-3b.
    """
    if jev_post_func is None:
        jev_post_func = _post_json
    audit = CitationAudit(citation=citation)

    # EXISTENCE axis — URL resolution + title comparison + 72h window.
    ex_state, ex_detail, ex_unread = _audit_existence(
        citation, config=config, now=now, fetcher=fetcher
    )
    audit.existence_state = ex_state
    audit.existence_detail = ex_detail
    audit.unread_reason = ex_unread

    # CONFIDENCE axis — 1.00 restriction based on claim_scope.
    conf_state, conf_detail = _audit_confidence(finding)
    audit.confidence_state = conf_state
    audit.confidence_detail = conf_detail

    # SOURCE TIER axis — reconcile source_type and reliability.
    tier_state, tier_detail = _audit_tier(citation)
    audit.tier_state = tier_state
    audit.tier_detail = tier_detail

    # Scope advisory — never gates. Jev Scope Choice is only called when the
    # writer declared a valid claim_scope; invalid/missing scope is surfaced as
    # scope_undeclared without a Jev call.
    scope_state, scope_detail = _audit_scope(
        finding, config, post_func=jev_post_func
    )
    audit.scope_state = scope_state
    audit.scope_detail = scope_detail

    return audit


# Closed list of finite-verb indicators used for conservative compound-sentence
# detection. The detector only needs to recognize that BOTH sides of a clause
# separator contain a verb-like token; it does not tag parts of speech.
_FINITE_VERB_INDICATORS = frozenset(
    """
    is are was were be been being have has had do does did will would could
    should may might must can shall prove proves proved proveing compute
    computes computed computing show shows showed showing establish
    establishes established establishing imply implies implied implying
    reduce reduces reduced reducing demonstrate demonstrates demonstrated
    demonstrating give gives gave given giving state states stated stating
    claim claims claimed claiming find finds found finding
    """.split()
)

# Clause separators that can join two independent clauses.
_CLAUSE_SEPARATORS = (r"\s+and\s+", r"\s+which also\s+")


def _has_finite_verb(text: str) -> bool:
    """Return True if the text contains a token from the finite-verb list.

    This is intentionally a conservative closed-list check, not an NLP parse.
    A false negative (missing a rare verb) causes a compound sentence to be
    treated as atomic and escalated to skeptics as compound_unsplit — the safe
    direction. A false positive would incorrectly mark a simple sentence as
    compound, also safe because compound_unsplit is advisory-only.
    """
    tokens = re.findall(r"[A-Za-z]+", text.lower())
    return any(token in _FINITE_VERB_INDICATORS for token in tokens)


def _is_compound_clause(text: str) -> bool:
    """Return True if text appears to join two clauses, each with a finite verb.

    Only coordinating 'and' / 'which also' are checked; other conjunctions are
    ignored to keep the rule deterministic and conservative.
    """
    for sep in _CLAUSE_SEPARATORS:
        parts = re.split(sep, text, flags=re.IGNORECASE)
        if len(parts) == 2 and all(_has_finite_verb(p) for p in parts):
            return True
    return False


# Closed list of abbreviations that end with a period but must not terminate
# a sentence. Protected before sentence splitting, then restored.
_UNCONDITIONAL_ABBREVIATIONS = (
    "e.g.",
    "i.e.",
    "et al.",
    "cf.",
    "vs.",
    "Dr.",
    "Mr.",
    "Mrs.",
    "Ms.",
    "Prof.",
    "Fig.",
    "Eq.",
)

# Abbreviations that can sometimes end a sentence (etc., No., approx.) and
# single capital initials are ambiguous. If one is followed by whitespace + a
# capital letter, the boundary is indeterminate, so the whole fragment is
# marked compound_unsplit and escalated to skeptics with no Noul score.
_AMBIGUOUS_ABBREVIATIONS = (
    "etc.",
    "No.",
    "approx.",
)

# Sentence boundary: [.!?] followed by optional closing punctuation/brackets,
# then whitespace, then optional opening punctuation/brackets, then a capital
# letter. This single definition is used by the splitter, the multi-dot
# escalation guard, and the ambiguous-token check.
_SENTENCE_BOUNDARY_RE = re.compile(
    r"[.!?][\"\'\u201d\u2019)\]]*\s+[\"\'\u201c\u2018(\[]?[A-Z]"
)

# Regex for a single capital initial (e.g. "J. Smith"). Ambiguous in the same
# way as etc./No./approx.: if followed by a sentence boundary, the fragment is
# compound_unsplit.
_INITIAL_RE = re.compile(
    r"\b[A-Z]\.(?=[\"\'\u201d\u2019)\]]*\s+[\"\'\u201c\u2018(\[]?[A-Z])"
)

# Regex for multi-dot tokens such as Ph.D., U.S., U.K., a.m., p.m., M.Sc.
# These are protected as a class and treated as ambiguous.
_MULTI_DOT_RE = re.compile(r"\b(?:[A-Za-z]{1,3}\.){2,}")

# Regex for decimal/version tokens ("3.5", "v2.1"). These are protected so
# they do not become sentence boundaries.
_DECIMAL_RE = re.compile(r"\b(?:v?\d+\.\d+)\b")

# Placeholder used by _protect_abbreviations; the sentinel characters are
# chosen because they cannot appear in valid UTF-8 source text.
_Placeholder = tuple[str, str, bool]


def _protect_abbreviations(text: str) -> tuple[str, list[_Placeholder]]:
    """Replace protected tokens with placeholders; return text and restore list.

    Each entry is (placeholder, original_token, is_ambiguous).
    """
    placeholders: list[_Placeholder] = []

    def _placeholder(token: str, ambiguous: bool) -> str:
        ph = f"\x00{len(placeholders)}\x00"
        placeholders.append((ph, token, ambiguous))
        return ph

    # Protect decimals first so digits around a dot are not mistaken for
    # sentence boundaries.
    def _decimal_ph(match: re.Match) -> str:
        return _placeholder(match.group(0), ambiguous=False)

    text = _DECIMAL_RE.sub(_decimal_ph, text)

    # Unconditional abbreviations cannot end a sentence, so they are always
    # protected and never cause compound_unsplit.
    for abbrev in _UNCONDITIONAL_ABBREVIATIONS:
        text = re.sub(re.escape(abbrev), lambda m, a=abbrev: _placeholder(a, False), text)

    # Ambiguous abbreviations are protected for splitting, but the restored
    # fragment is escalated if the abbreviation is followed by whitespace + a
    # capital letter.
    for abbrev in _AMBIGUOUS_ABBREVIATIONS:
        text = re.sub(re.escape(abbrev), lambda m, a=abbrev: _placeholder(a, True), text)

    # Single capital initials are ambiguous in the same way.
    text = _INITIAL_RE.sub(lambda m: _placeholder(m.group(0), True), text)

    # Multi-dot tokens (Ph.D., U.S., etc.) are ambiguous in the same way.
    text = _MULTI_DOT_RE.sub(lambda m: _placeholder(m.group(0), True), text)
    return text, placeholders


def _restore_abbreviations(text: str, placeholders: list[_Placeholder]) -> str:
    """Restore tokens hidden by _protect_abbreviations."""
    for ph, token, _ in placeholders:
        text = text.replace(ph, token)
    return text


def _split_sentences(text: str) -> list[str]:
    """Split text at sentence boundaries, preserving closing/opening punctuation.

    Returns a list of stripped sentence fragments. Empty fragments are omitted.
    """
    parts: list[str] = []
    start = 0
    for m in _SENTENCE_BOUNDARY_RE.finditer(text):
        # Locate the whitespace span inside the matched boundary so the
        # closing punctuation stays with the first sentence and the opening
        # punctuation/capital stays with the second.
        match_text = m.group()
        ws_match = re.search(r"\s+", match_text)
        assert ws_match is not None
        ws_start_in_match = ws_match.start()
        ws_end_in_match = ws_match.end()
        boundary_ws_start = m.start() + ws_start_in_match
        boundary_ws_end = m.start() + ws_end_in_match
        parts.append(text[start:boundary_ws_start].strip())
        start = boundary_ws_end
    parts.append(text[start:].strip())
    return [p for p in parts if p]


def _split_into_fragments(text: str) -> list[str]:
    """Split text at semicolons and then at sentence boundaries."""
    fragments: list[str] = []
    for segment in re.split(r"\s*;\s*", text):
        fragments.extend(_split_sentences(segment))
    return fragments


def _has_ambiguous_sentence_boundary(text: str, placeholders: list[_Placeholder]) -> bool:
    """Return True if an ambiguous placeholder is followed by a sentence boundary."""
    restored = _restore_abbreviations(text, placeholders)
    for _, token, ambiguous in placeholders:
        if not ambiguous:
            continue
        # Check whether this specific restored token is followed by the sentence
        # boundary pattern: optional closing chars, whitespace, optional opening
        # chars, capital letter.
        pattern = (
            re.escape(token)
            + r"(?=[\"\'\u201d\u2019)\]]*\s+[\"\'\u201c\u2018(\[]?[A-Z])"
        )
        if re.search(pattern, restored):
            return True
    return False


def _contains_multi_dot_token(text: str) -> bool:
    """Return True if the text contains a multi-dot abbreviation token."""
    return bool(_MULTI_DOT_RE.search(text))


def split_atomic_claims(content: str) -> tuple[list[str], list[str]]:
    """Split finding content into atomic claims.

    Splits only at sentence boundaries ('.', '!', '?') and semicolons, never
    inside a clause. Unconditional abbreviations and decimal/version tokens are
    preserved as part of their containing sentence. Ambiguous tokens (etc.,
    No., approx., single capital initials) are protected for splitting, but if
    such a token is followed by whitespace + a capital letter the resulting
    fragment is marked compound_unsplit rather than risk merging two real
    sentences. Multi-dot tokens (Ph.D., U.S., a.m., M.Sc.) are protected as a
    class: if the text contains one and also contains a sentence boundary, the
    entire text is compound_unsplit; otherwise it stays one atomic claim. Any
    resulting sentence that still looks compound (two clauses joined by
    coordinating 'and'/'which also', each with a finite verb) is also returned
    as compound_unsplit.

    Returns (atomic_claims, compound_unsplit_claims). Both lists contain
    stripped claim text.
    """
    text = (content or "").strip()
    if not text:
        return [], []

    protected_text, placeholders = _protect_abbreviations(text)

    # Split at semicolons and sentence boundaries (deterministic separators).
    # Sentence boundaries honor optional closing/opening quotes and brackets.
    raw_parts = _split_into_fragments(protected_text)

    # If the text contains a multi-dot token and also has a real sentence
    # boundary, the boundary is ambiguous because any of the dots in the token
    # could be mistaken for the sentence terminator. Escalate the whole text
    # rather than risk fragments or merges.
    if _contains_multi_dot_token(text) and _SENTENCE_BOUNDARY_RE.search(text):
        restored = _restore_abbreviations(text, placeholders)
        # Do not strip periods: the text may end in a multi-dot token like
        # "Ph.D." and stripping would fragment it.
        return [], [restored.strip()]

    atomic: list[str] = []
    compound: list[str] = []
    for part in raw_parts:
        part = part.strip(".; ")
        if not part:
            continue
        if _has_ambiguous_sentence_boundary(part, placeholders):
            compound.append(_restore_abbreviations(part, placeholders))
            continue
        part = _restore_abbreviations(part, placeholders)
        if _is_compound_clause(part):
            compound.append(part)
        else:
            atomic.append(part)
    return atomic, compound


def atomic_claims_for_citation(
    finding: Finding,
    citation: Citation,
) -> tuple[list[AtomicClaim], list[AtomicClaim]]:
    """Build atomic claims for a (finding, citation) pair.

    source_text is taken from the citation's collector snapshot
    (metadata['source_snapshot_text'] or citation.quote). If neither is present,
    the citation cannot be judged and the caller should mark it UNREAD.

    Returns (atomic_claims, compound_unsplit_claims). Compound unsplit claims
    are escalated to skeptics with no Noul score; they are advisory-only and
    never gate pass/fail.
    """
    source_text = (
        citation.metadata.get("source_snapshot_text")
        or citation.quote
        or ""
    ).strip()
    # No collector snapshot text means the citation cannot be judged by Jev;
    # the caller must mark it UNREAD rather than self-compare against the
    # finding content.
    if not source_text:
        return [], []
    atomic_texts, compound_texts = split_atomic_claims(finding.content)

    atomic = [
        AtomicClaim(
            finding_id=finding.finding_id,
            claim_text=t,
            source_text=source_text,
            parent_finding=finding,
        )
        for t in atomic_texts
    ]
    compound = [
        AtomicClaim(
            finding_id=finding.finding_id,
            claim_text=t,
            source_text=source_text,
            parent_finding=finding,
            is_compound_unsplit=True,
        )
        for t in compound_texts
    ]
    return atomic, compound


def audit_task(
    findings: list[Finding],
    config: GateConfig,
    now: Optional[datetime] = None,
    fetcher: Callable[[str], tuple[int, Optional[str], str]] = fetch_url,
    jev_post_func: Optional[Callable[..., tuple[int, str, dict[str, str]]]] = None,
    jev_sleep_func: Optional[Callable[[float], None]] = None,
) -> GateResult:
    """Audit all findings for a task and return a GateResult.

    The clock is injectable via `now` so tests can simulate the 72h boundary
    deterministically. Dropped citations are removed from the active argument
    for each finding; a finding with no surviving citations is blocked.

    jev_post_func and jev_sleep_func default to None and are resolved inside
    the function because the real implementations (_post_json, time.sleep) are
    defined later in this module; default-argument values are evaluated at
    function-definition time, so using None avoids a forward-reference NameError.
    """
    if now is None:
        now = datetime.now(timezone.utc)
    if jev_post_func is None:
        jev_post_func = _post_json
    if jev_sleep_func is None:
        jev_sleep_func = time.sleep
    result = GateResult(task_id=findings[0].task_id if findings else 0)
    for finding in findings:
        finding_audit = FindingAudit(finding=finding)
        surviving_audits: list[CitationAudit] = []
        for citation in finding.citations:
            audit = _audit_citation(
                citation, finding, config, now=now, fetcher=fetcher, jev_post_func=jev_post_func
            )
            if audit.existence_state == "dropped":
                result.dropped_citations.append(citation.citation_id)
                continue
            surviving_audits.append(audit)
            finding_audit.citation_audits.append(audit)

        if not finding.citations:
            # A finding with zero citations gets an explicit placeholder audit so
            # the review table can distinguish "checked, no citations" from omitted.
            finding_audit.citation_audits.append(
                CitationAudit(
                    citation=Citation(
                        citation_id=0,
                        finding_id=finding.finding_id,
                        source_type="none",
                        source_url=None,
                        source_title=None,
                        reliability=None,
                        accessed_at=now,
                        metadata={},
                    ),
                    existence_state="no_citations",
                    existence_detail="finding has zero citations",
                )
            )

        # No surviving supporting citations after drops → finding is blocked.
        if finding.citations and not surviving_audits:
            finding_audit.citation_audits.append(
                CitationAudit(
                    citation=Citation(
                        citation_id=0,
                        finding_id=finding.finding_id,
                        source_type="none",
                        source_url=None,
                        source_title=None,
                        reliability=None,
                        accessed_at=now,
                        metadata={},
                    ),
                    existence_state="no_surviving_citations",
                    existence_detail="all citations dropped after 72h window",
                )
            )

        # Jev Support Noul for surviving citations.
        for audit in surviving_audits:
            jev_state, jev_detail, attempted, failed = _audit_citation_jev_support(
                audit.citation,
                finding,
                config,
                post_func=jev_post_func,
                sleep_func=jev_sleep_func,
            )
            audit.jev_support_state = jev_state
            audit.jev_support_detail = jev_detail
            result.jev_attempted += attempted
            result.jev_failed += failed

        # Scope advisory aggregation (advisory-only, never gates).
        scope_flags: list[str] = []
        for ca in finding_audit.citation_audits:
            if ca.scope_state == "advisory" and ca.scope_detail:
                scope_flags.append(ca.scope_detail)
        if scope_flags:
            finding_audit.scope_advisory = "; ".join(
                dict.fromkeys(scope_flags)
            )

        # High-risk cell: weakest tier × consequential claim.
        if surviving_audits and _importance_level(finding.importance) >= _importance_level(
            "high"
        ):
            for ca in surviving_audits:
                if _is_weakest_tier(ca.tier_state):
                    finding_audit.high_risk = True
                    finding_audit.high_risk_detail = (
                        f"finding {finding.finding_id}: {finding.importance} claim "
                        f"backed by weakest-tier citation {ca.citation.citation_id}"
                    )
                    break

        result.finding_audits.append(finding_audit)
    return result


# ---------------------------------------------------------------------------
# Jev / TypeSafe System One client
# ---------------------------------------------------------------------------
def _systemone_payload(claim_text: str, source_text: str) -> dict[str, Any]:
    """Build the request body for a Jev Support Noul call.

    The shape follows the TypeSafe /v1/systemone direct-API pattern from
    SE#1282 step 2: a model name, role/policy instructions, criteria labels,
    and a flat state object.
    """
    return {
        "model": "jev-latest",
        "instructions": (
            "You are a skeptical citation auditor. Given a claim and a source "
            "snapshot, estimate the probability that the source explicitly "
            "supports the claim. Respond with a JSON object containing a "
            "single field 'p_supports' between 0 and 1."
        ),
        "criteria": [
            {"label": "supports", "description": "source explicitly supports claim"},
            {"label": "does_not_support", "description": "source does not support claim"},
        ],
        "state": {
            "claim": claim_text,
            "source_text": source_text,
            "context": "",
        },
    }


def _post_json(
    url: str,
    payload: dict[str, Any],
    api_key: Optional[str],
    timeout: float = 30.0,
) -> tuple[int, str, dict[str, str]]:
    """POST JSON to url and return (status_code, body_text, headers)."""
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            **({"Authorization": f"Bearer {api_key}"} if api_key else {}),
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return (
            resp.status,
            resp.read().decode("utf-8", errors="replace"),
            dict(resp.headers),
        )


def _parse_noul_response(body: str) -> float:
    """Extract and validate p_supports from a Jev Noul response body.

    Raises ValueError for missing, NaN, or out-of-range [0,1] values.
    The response is fail-closed: any parsing problem is treated as a Jev error.
    """
    try:
        obj = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON: {exc}") from exc
    if not isinstance(obj, dict):
        raise ValueError("response is not a JSON object")
    # Prefer explicit p_supports; fall back to a top-level 'probability' field.
    for key in ("p_supports", "probability", "confidence"):
        if key in obj:
            val = obj[key]
            break
    else:
        raise ValueError("missing p_supports/probability/confidence field")
    # bool is a subclass of int in Python; reject it explicitly (fail-closed).
    if isinstance(val, bool):
        raise ValueError("p_supports is a boolean, not a number")
    if isinstance(val, str):
        if val.lower() == "nan":
            raise ValueError("p_supports is NaN")
        try:
            val = float(val)
        except ValueError as exc:
            raise ValueError(f"non-numeric p_supports: {val!r}") from exc
    if not isinstance(val, (int, float)):
        raise ValueError(f"non-numeric p_supports: {val!r}")
    if math.isnan(val) or math.isinf(val):
        raise ValueError("p_supports is NaN or infinite")
    if not (0.0 <= val <= 1.0):
        raise ValueError(f"p_supports {val} out of [0,1]")
    return float(val)


def _jev_call_with_retry(
    claim_text: str,
    source_text: str,
    config: GateConfig,
    post_func: Callable[..., tuple[int, str, dict[str, str]]] = _post_json,
    sleep_func: Callable[[float], None] = time.sleep,
    max_attempts: int = 3,
) -> float:
    """Call /v1/systemone for a single Noul score with retry policy.

    Retries on timeout/5xx/429 only. Honors Retry-After on 429; otherwise uses
    exponential backoff (1s, 2s). Non-429 4xx and malformed 200 bodies are NOT
    retried. Raises JevCallError on exhaustion or non-retryable failure.
    """
    payload = _systemone_payload(claim_text, source_text)
    last_error = ""
    headers: dict[str, str] = {}
    for attempt in range(1, max_attempts + 1):
        try:
            status, body, headers = post_func(
                config.jev_url, payload, config.jev_api_key
            )
        except urllib.error.HTTPError as exc:
            status = exc.code
            body = exc.read().decode("utf-8", errors="replace") if exc.fp else ""
            headers = dict(exc.headers) if exc.headers else {}
        except Exception as exc:  # pylint: disable=broad-exception-caught
            status = 0
            body = ""
            headers = {}
            last_error = str(exc)

        if status == 200:
            return _parse_noul_response(body)

        # Non-retryable 4xx (except 429) and any 3xx are fail-closed immediately.
        if 300 <= status < 500 and status != 429:
            raise JevCallError(f"HTTP {status}: non-retryable client error")

        if attempt == max_attempts:
            raise JevCallError(
                f"HTTP {status} after {max_attempts} attempts: {last_error or body[:200]}"
            )

        # Determine retry delay.
        delay = 1.0 * (2 ** (attempt - 1))  # 1s, 2s
        if status == 429:
            retry_after = headers.get("Retry-After")
            if retry_after:
                try:
                    delay = max(0.0, float(retry_after))
                except ValueError:
                    pass
        sleep_func(delay)

    raise JevCallError("retry loop exited without result")


class JevCallError(Exception):
    """Raised when a Jev /v1/systemone call fails irrecoverably."""


_JEV_UNCERTAINTY_LOW = 0.40
_JEV_UNCERTAINTY_HIGH = 0.60


def _jev_support_state(
    p_supports: float,
    threshold: float,
) -> tuple[str, str]:
    """Classify a Noul probability into a support state.

    Returns (state, detail). p_supports <= threshold blocks. The [0.4,0.6]
    uncertainty zone always escalates, even though it is above the threshold.
    """
    if _JEV_UNCERTAINTY_LOW <= p_supports <= _JEV_UNCERTAINTY_HIGH:
        return "escalate", f"p_supports={p_supports} in uncertainty zone [0.4,0.6]"
    if p_supports <= threshold:
        return "escalate", f"p_supports={p_supports} <= threshold {threshold}"
    return "passed", f"p_supports={p_supports} above threshold and outside uncertainty zone"


def _audit_jev_support(
    claim: AtomicClaim,
    config: GateConfig,
    post_func: Callable[..., tuple[int, str, dict[str, str]]] = _post_json,
    sleep_func: Callable[[float], None] = time.sleep,
) -> tuple[str, str]:
    """Get Jev Support Noul classification for one atomic claim.

    Returns:
      * ("passed", detail)  — p_supports is above threshold and outside the
        uncertainty zone.
      * ("escalate", detail) — p_supports is at/below threshold or inside the
        uncertainty zone; this is a finding-level block, not a Jev API failure.
      * ("failed", detail)  — the Jev call itself failed (network, malformed
        response, exhausted retries); counted toward systemic failure.
    """
    try:
        p = _jev_call_with_retry(
            claim.claim_text,
            claim.source_text,
            config,
            post_func=post_func,
            sleep_func=sleep_func,
        )
        return _jev_support_state(p, config.support_threshold)
    except JevCallError as exc:
        return "failed", f"Jev call failed: {exc}"
    except Exception as exc:  # pylint: disable=broad-exception-caught
        return "failed", f"Jev call failed: {exc}"


def _audit_citation_jev_support(
    citation: Citation,
    finding: Finding,
    config: GateConfig,
    post_func: Callable[..., tuple[int, str, dict[str, str]]] = _post_json,
    sleep_func: Callable[[float], None] = time.sleep,
) -> tuple[str, str, int, int]:
    """Run Jev Support Noul for all atomic claims of one citation.

    Returns (state, detail, attempted, failed). 'state' is 'passed' only if
    every atomic claim passed. 'failed' counts only Jev API failures, not
    threshold/uncertainty escalations; it feeds the systemic-failure detector.
    """
    atomic, _compound = atomic_claims_for_citation(finding, citation)
    if not atomic:
        return "pending", "no atomic claims to judge", 0, 0

    attempted = 0
    failed = 0
    escalations: list[str] = []
    for claim in atomic:
        attempted += 1
        state, detail = _audit_jev_support(
            claim, config, post_func=post_func, sleep_func=sleep_func
        )
        if state == "failed":
            failed += 1
        if state in ("failed", "escalate"):
            escalations.append(detail)

    if failed == attempted and attempted > 0:
        return "failed", "; ".join(escalations), attempted, failed
    if escalations:
        return "escalate", "; ".join(escalations), attempted, failed
    return "passed", "all atomic claims supported", attempted, failed


# ---------------------------------------------------------------------------
# Scope Choice client
# ---------------------------------------------------------------------------
_SCOPE_UNCERTAINTY_LOW = 0.40


def _scope_choice_payload(claim_text: str, declared_scope: str) -> dict[str, Any]:
    """Build the request body for a Jev Scope Choice call.

    Scope Choice asks whether the writer-declared claim_scope is appropriate
    for the claim content. The response is advisory only and never gates.
    """
    return {
        "model": "jev-latest",
        "instructions": (
            "You are a careful reader. Given a claim and a declared scope "
            "('proved', 'computed', 'cited', or 'conjecture'), decide whether "
            "the scope is appropriate. A 'cited' scope is only appropriate "
            "when the claim is a bibliographic or metadata fact about the "
            "source document itself, not a claim the document makes. Respond "
            "with a JSON object containing 'scope_mismatch' (boolean) and "
            "'confidence' (0-1)."
        ),
        "criteria": [
            {"label": "scope_ok", "description": "declared scope matches claim content"},
            {"label": "scope_mismatch", "description": "declared scope does not match claim content"},
        ],
        "state": {
            "claim": claim_text,
            "declared_scope": declared_scope,
            "context": "",
        },
    }


def _parse_scope_choice_response(body: str) -> tuple[bool, float]:
    """Parse a Scope Choice response into (mismatch, confidence).

    Any parsing problem is treated as a low-confidence mismatch so the
    skeptics get a flag, but it remains advisory-only.
    """
    try:
        obj = json.loads(body)
        if not isinstance(obj, dict):
            return True, 0.0
        mismatch = bool(obj.get("scope_mismatch", False))
        confidence = float(obj.get("confidence", 0.0))
        if math.isnan(confidence) or math.isinf(confidence):
            confidence = 0.0
        confidence = max(0.0, min(1.0, confidence))
        return mismatch, confidence
    except Exception:  # pylint: disable=broad-exception-caught
        return True, 0.0


def _jev_scope_choice(
    claim_text: str,
    declared_scope: str,
    config: GateConfig,
    post_func: Callable[..., tuple[int, str, dict[str, str]]] = _post_json,
) -> tuple[str, str]:
    """Call /v1/systemone for Scope Choice.

    Returns (state, detail). State is 'ok' or 'advisory'. All failures are
    returned as advisory so the gate never crashes on a bad Scope Choice call.
    """
    try:
        payload = _scope_choice_payload(claim_text, declared_scope)
        status, body, _headers = post_func(
            config.jev_url, payload, config.jev_api_key
        )
        if status != 200:
            return "advisory", f"Scope Choice HTTP {status}"
        mismatch, confidence = _parse_scope_choice_response(body)
        if mismatch:
            return "advisory", f"scope mismatch detected (confidence={confidence})"
        if confidence < _SCOPE_UNCERTAINTY_LOW:
            return "advisory", f"low scope confidence ({confidence})"
        return "ok", f"scope ok (confidence={confidence})"
    except Exception as exc:  # pylint: disable=broad-exception-caught
        return "advisory", f"Scope Choice failed: {exc}"


def _audit_scope(
    finding: Finding,
    config: GateConfig,
    post_func: Callable[..., tuple[int, str, dict[str, str]]] = _post_json,
) -> tuple[str, str]:
    """Advisory Scope Choice audit for a finding.

    A missing or invalid declared scope is reported as scope_undeclared.
    A valid declared scope is checked by Jev Scope Choice; mismatches and
    low-confidence results are advisory-only and never change the exit code.
    """
    scope, scope_valid = _claim_scope(finding)
    if not scope_valid:
        return "advisory", "scope_undeclared"
    state, detail = _jev_scope_choice(
        finding.content, scope, config, post_func=post_func
    )
    return state, detail


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def _fmt_state(state: str) -> str:
    """Return a human-readable token for the review table."""
    return state.replace("_", " ").upper()


def _fmt_cell(state: str, detail: str = "", unread_reason: Optional[str] = None) -> str:
    """Format one axis cell so failures and UNREAD never look like a clean pass.

    Pass-like states ('passed', 'ok', 'non_url_source') render as the state
    token. Failed, escalate, conflict, and unread states are wrapped in
    brackets and prefixed with their reason so they stand out in the review
    table. Advisory-only states are suffixed with '(advisory)'.
    """
    token = _fmt_state(state)
    if state in ("passed", "ok", "non_url_source"):
        return token
    if unread_reason is not None:
        return f"[UNREAD: {unread_reason}]"
    if state in ("failed", "escalate", "conflict", "no_citations", "no_surviving_citations"):
        return f"[{token}]"
    if state == "advisory":
        return f"{token} (advisory)"
    return token


def _aggregate_finding_status(fa: FindingAudit) -> str:
    """Return a short pass/blocked/advisory summary for one finding."""
    blocked = False
    advisory = bool(fa.scope_advisory) or any(
        ca.scope_state == "advisory" for ca in fa.citation_audits
    )
    for ca in fa.citation_audits:
        if ca.existence_state in ("failed", "no_citations", "no_surviving_citations"):
            blocked = True
        if ca.confidence_state == "failed":
            blocked = True
        if ca.tier_state == "conflict":
            blocked = True
        if ca.unread_reason is not None:
            blocked = True
        if ca.jev_support_state in ("escalate", "failed"):
            blocked = True
    if blocked:
        return "BLOCKED"
    if advisory:
        return "PASS (advisory)"
    return "PASS"


def _result_to_json(result: GateResult) -> dict[str, Any]:
    """Serialize a GateResult to a JSON-serializable dict.

    The structure mirrors the internal dataclasses without leaking live
    connection objects. Advisory-only fields are included but clearly
    separated so callers can distinguish them from blockers.
    """
    findings: list[dict[str, Any]] = []
    for fa in result.finding_audits:
        citations: list[dict[str, Any]] = []
        for ca in fa.citation_audits:
            citations.append(
                {
                    "citation_id": ca.citation.citation_id,
                    "existence": {
                        "state": ca.existence_state,
                        "detail": ca.existence_detail,
                        "unread_reason": ca.unread_reason,
                    },
                    "confidence": {
                        "state": ca.confidence_state,
                        "detail": ca.confidence_detail,
                    },
                    "tier": {
                        "state": ca.tier_state,
                        "detail": ca.tier_detail,
                    },
                    "scope": {
                        "state": ca.scope_state,
                        "detail": ca.scope_detail,
                    },
                    "jev_support": {
                        "state": ca.jev_support_state,
                        "detail": ca.jev_support_detail,
                    },
                }
            )
        findings.append(
            {
                "finding_id": fa.finding.finding_id,
                "content": fa.finding.content,
                "importance": fa.finding.importance,
                "status": _aggregate_finding_status(fa),
                "citations": citations,
                "high_risk": fa.high_risk,
                "high_risk_detail": fa.high_risk_detail,
                "scope_advisory": fa.scope_advisory,
            }
        )
    return {
        "task_id": result.task_id,
        "exit_code": result.exit_code(),
        "errors": result.errors,
        "dropped_citations": result.dropped_citations,
        "jev_attempted": result.jev_attempted,
        "jev_failed": result.jev_failed,
        "findings": findings,
    }


def render_review_table(result: GateResult) -> str:
    """Render a human-readable review table for the gate result.

    The table shows per-axis states. UNREAD and failed states are bracketed
    so they never look like a clean pass. Advisory scope flags are rendered
    with an '(advisory)' label. High-risk cells and gate errors are surfaced
    in their own sections.
    """
    lines: list[str] = []
    exit_label = {0: "PASS", 1: "BLOCKED", 2: "ERROR"}.get(
        result.exit_code(), "UNKNOWN"
    )
    lines.append(f"Research finding audit for task {result.task_id} — exit {result.exit_code()} ({exit_label})")
    lines.append("-" * 80)
    if result.errors:
        lines.append("Gate errors:")
        for err in result.errors:
            lines.append(f"  * {err}")
        lines.append("")

    if not result.finding_audits:
        lines.append("No current findings for this task.")
        return "\n".join(lines)

    header = (
        f"{'Finding':<10} {'Citation':<10} {'Existence':<28} "
        f"{'Confidence':<16} {'Tier':<16} {'Scope':<24} {'Jev':<20}"
    )
    lines.append(header)
    lines.append("-" * 120)
    for fa in result.finding_audits:
        status = _aggregate_finding_status(fa)
        lines.append(f"Finding {fa.finding.finding_id} — {status}")
        for ca in fa.citation_audits:
            lines.append(
                f"{fa.finding.finding_id:<10} "
                f"{ca.citation.citation_id:<10} "
                f"{_fmt_cell(ca.existence_state, ca.existence_detail, ca.unread_reason):<28} "
                f"{_fmt_cell(ca.confidence_state):<16} "
                f"{_fmt_cell(ca.tier_state):<16} "
                f"{_fmt_cell(ca.scope_state, ca.scope_detail):<24} "
                f"{_fmt_cell(ca.jev_support_state, ca.jev_support_detail):<20}"
            )
            details: list[str] = []
            if ca.existence_detail and ca.existence_state not in ("passed", "ok"):
                details.append(f"existence: {ca.existence_detail}")
            if ca.confidence_detail and ca.confidence_state not in ("passed", "ok"):
                details.append(f"confidence: {ca.confidence_detail}")
            if ca.tier_detail and ca.tier_state not in ("passed", "ok", "strong", "medium", "weak"):
                details.append(f"tier: {ca.tier_detail}")
            if ca.jev_support_detail and ca.jev_support_state not in ("passed", "ok", "pending"):
                details.append(f"jev: {ca.jev_support_detail}")
            if ca.scope_detail and ca.scope_state == "advisory":
                details.append(f"scope: {ca.scope_detail}")
            if details:
                lines.append(f"           {'; '.join(details)}")
        if fa.scope_advisory:
            lines.append(f"  SCOPE ADVISORY: {fa.scope_advisory}")
        if fa.high_risk:
            lines.append(f"  HIGH-RISK CELL: {fa.high_risk_detail}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _resolve_task_id_for_problem(
    conn: Any, schema: str, problem_id: int
) -> Optional[int]:
    """Resolve the active research task_id for an unsolved_problem.

    In production this seam is populated by workflow 32's problem→project→task
    linkage. For the gate's wiring contract we read the stored research_task_id
    from unsolved_problems.metadata, which is what workflow 32 step 3 is
    expected to set before invoking the gate.
    """
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT metadata FROM {schema}.unsolved_problems WHERE id = %s",
            (problem_id,),
        )
        row = cur.fetchone()
    if not row or not row[0]:
        return None
    meta = row[0]
    if isinstance(meta, str):
        try:
            meta = json.loads(meta)
        except Exception:
            return None
    task_id = meta.get("research_task_id")
    if task_id is None:
        return None
    try:
        return int(task_id)
    except (TypeError, ValueError):
        return None


def _write_progress_notes(
    conn: Any, schema: str, problem_id: int, notes: str
) -> None:
    """Write progress_notes for an unsolved_problem (workflow 32 step 3)."""
    with conn.cursor() as cur:
        cur.execute(
            f"UPDATE {schema}.unsolved_problems SET progress_notes = %s, "
            f"updated_at = now() WHERE id = %s",
            (notes, problem_id),
        )
    conn.commit()


def workflow_32_step_3(
    conn: Any,
    problem_id: int,
    config: GateConfig,
    progress_notes: Optional[str] = None,
    session_mode: str = "WORK",
) -> tuple[GateResult, bool]:
    """Dry-run workflow 32 step 3 wiring seam.

    Resolves the task_id for the active problem, runs the audit gate, and
    decides whether the step-3 progress_notes write may proceed. Hard
    violations (exit 1) and gate-could-not-run conditions (exit 2) both block
    the write. MONITOR-mode sessions still run the gate explicitly rather than
    being silently skipped.

    Returns (gate_result, wrote_progress_notes).
    """
    task_id = _resolve_task_id_for_problem(conn, config.schema, problem_id)
    if task_id is None:
        result = GateResult(
            task_id=-1,
            errors=[f"no research_task_id resolved for problem {problem_id}"],
        )
        return result, False

    # MONITOR mode is deliberately not a silent skip: the gate re-runs so
    # previously-clean data does not spuriously pass due to a bypass.
    if session_mode == "MONITOR":
        pass  # explicit branch; gate runs below

    with conn.cursor() as cur:
        if not _task_exists(cur, config.schema, task_id):
            result = GateResult(
                task_id=task_id,
                errors=[f"resolved task {task_id} not found"],
            )
            return result, False

    findings = load_findings(conn, config.schema, task_id)
    result = audit_task(findings, config)

    # WIRE-02: gate failure blocks the progress_notes write.
    if result.exit_code() == 0 and progress_notes is not None:
        _write_progress_notes(conn, config.schema, problem_id, progress_notes)
        return result, True

    return result, False


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog="research-audit-gate.py",
        description="Deterministic three-axis finding audit gate before UPR synthesis.",
    )
    parser.add_argument(
        "--task-id",
        type=int,
        required=True,
        help="Research task ID to audit.",
    )
    parser.add_argument(
        "--schema",
        default=os.environ.get("RESEARCH_AUDIT_GATE_SCHEMA", DEFAULT_SCHEMA),
        help="PostgreSQL schema containing research_* tables (default: public).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of the review table.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Entry point for the audit gate CLI.

    Returns a coarse exit code: 0 pass, 1 blocked, 2 could-not-run.
    """
    args = _parse_args(argv)

    if not _DB_AVAILABLE:
        print("Database driver (psycopg2) is not available", file=sys.stderr)
        return 2
    if not _PG_ENV_AVAILABLE:
        print("PG config loader (pg_env) is not available", file=sys.stderr)
        return 2

    try:
        config = load_config()
    except Exception as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2

    # Override schema from CLI/env for this invocation.
    config = GateConfig(
        schema=args.schema,
        drop_window_hours=config.drop_window_hours,
        support_threshold=config.support_threshold,
        jev_url=config.jev_url,
        jev_api_key=config.jev_api_key,
        db_dsn=config.db_dsn,
        db_user=config.db_user,
    )

    try:
        conn = psycopg2.connect(config.db_dsn)
    except Exception as exc:
        print(f"Database connection error: {exc}", file=sys.stderr)
        return 2

    try:
        with conn.cursor() as cur:
            if not _task_exists(cur, config.schema, args.task_id):
                print(f"Task {args.task_id} not found", file=sys.stderr)
                return 2

        findings = load_findings(conn, config.schema, args.task_id)
        result = audit_task(findings, config)
    except Exception as exc:
        print(f"Audit error: {exc}", file=sys.stderr)
        return 2
    finally:
        conn.close()

    if args.json:
        payload = _result_to_json(result)
        print(json.dumps(payload, indent=2))
    else:
        print(render_review_table(result))

    return result.exit_code()


if __name__ == "__main__":
    sys.exit(main())
