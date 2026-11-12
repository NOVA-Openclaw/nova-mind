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

    All gate-specific tunables are env-driven so recalibration (e.g. moving the
    0.05 threshold after more data) does not require code changes. The 72-hour
    source-drop window is likewise read at runtime so the collector lifecycle
    can be adjusted without touching comparison logic in multiple places.
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
    reliability: Optional[float]
    accessed_at: datetime
    metadata: dict[str, Any]


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


@dataclass
class GateResult:
    """Result of auditing a whole task."""

    task_id: int
    finding_audits: list[FindingAudit] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    jev_attempted: int = 0
    jev_failed: int = 0

    def exit_code(self) -> int:
        """Return the coarse exit code for this run.

        0 = all pass, 1 = one or more findings blocked, 2 = gate could not run.
        For chunk 1 the Jev layer is not yet implemented, so the systemic-failure
        corner (all Jev calls failed) is not reachable; it will be wired in chunk 3.
        """
        if self.errors:
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
                # Jev Support failure/escalation blocks (JEV/JEVERR groups).
                if ca.jev_support_state in ("escalate", "failed"):
                    return 1
            # No surviving citations after a drop blocks (GATE-06A fixture B).
            if fa.finding.citations and not any(
                ca.unread_reason is None for ca in fa.citation_audits
            ):
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
    scope = raw.strip().lower()
    if scope not in CLAIM_SCOPE_VALUES:
        return None, False
    return scope, True


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


def _audit_existence(
    citation: Citation,
    fetcher: Callable[[str], tuple[int, Optional[str], str]] = fetch_url,
) -> tuple[str, str, Optional[str]]:
    """Audit the existence axis for a single citation.

    Returns (state, detail, unread_reason). unread_reason is None unless the
    source could not be verified due to a transient or ambiguous condition.
    """
    if citation.source_url is None or citation.source_url.strip() == "":
        if citation.source_type == "book":
            return "non_url_source", "book/source_type requires non-URL verification", None
        return "no_url", "source_url absent", None

    if citation.source_title is None or citation.source_title.strip() == "":
        return "no_title", "no filed title to compare against", None

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


def _audit_citation(
    citation: Citation,
    finding: Finding,
    config: GateConfig,
    fetcher: Callable[[str], tuple[int, Optional[str], str]] = fetch_url,
) -> CitationAudit:
    """Perform the deterministic three-axis audit for a single citation.

    Existence and source-tier checks are implemented in chunks 1-2. Confidence
    and Jev-mediated support/scope checks are still scaffolded and will be
    completed in chunks 2b and 3.
    """
    audit = CitationAudit(citation=citation)

    # EXISTENCE axis — URL resolution + title comparison.
    ex_state, ex_detail, ex_unread = _audit_existence(citation, fetcher=fetcher)
    audit.existence_state = ex_state
    audit.existence_detail = ex_detail
    audit.unread_reason = ex_unread

    # CONFIDENCE axis — chunk 2b will implement the 1.00 restriction. For now
    # we flag NULL as unscored and defer the rest.
    if finding.confidence is None:
        audit.confidence_state = "unscored"
        audit.confidence_detail = "confidence NULL"
    else:
        scope, scope_valid = _claim_scope(finding)
        if finding.confidence == 1.00 and scope_valid and scope == "cited":
            # Placeholder for the valid fact-about-document path; exact logic in chunk 2b.
            audit.confidence_state = "pending"
            audit.confidence_detail = "1.00 with claim_scope=cited (chunk 2b)"
        elif finding.confidence == 1.00:
            audit.confidence_state = "pending"
            audit.confidence_detail = "1.00 restriction check pending (chunk 2b)"
        else:
            audit.confidence_state = "pending"
            audit.confidence_detail = "confidence within [0,1] (chunk 2b)"

    # SOURCE TIER axis — reconcile source_type and reliability.
    tier_state, tier_detail = _audit_tier(citation)
    audit.tier_state = tier_state
    audit.tier_detail = tier_detail

    # Scope advisory — never gates.
    scope, scope_valid = _claim_scope(finding)
    if not scope_valid:
        audit.scope_state = "advisory"
        audit.scope_detail = "scope_undeclared"
    else:
        audit.scope_state = "pending"
        audit.scope_detail = f"claim_scope={scope} (chunk 3)"

    return audit


def audit_task(
    findings: list[Finding],
    config: GateConfig,
    fetcher: Callable[[str], tuple[int, Optional[str], str]] = fetch_url,
) -> GateResult:
    """Audit all findings for a task and return a GateResult."""
    result = GateResult(task_id=findings[0].task_id if findings else 0)
    for finding in findings:
        finding_audit = FindingAudit(finding=finding)
        for citation in finding.citations:
            finding_audit.citation_audits.append(
                _audit_citation(citation, finding, config, fetcher=fetcher)
            )
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
                        accessed_at=datetime.now(timezone.utc),
                        metadata={},
                    ),
                    existence_state="no_citations",
                    existence_detail="finding has zero citations",
                )
            )

        # High-risk cell: weakest tier × consequential claim.
        if finding.citations and _importance_level(finding.importance) >= _importance_level(
            "high"
        ):
            for ca in finding_audit.citation_audits:
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
# Output
# ---------------------------------------------------------------------------
def _fmt_state(state: str) -> str:
    """Return a human-readable token for the review table."""
    return state.replace("_", " ").upper()


def render_review_table(result: GateResult) -> str:
    """Render a human-readable review table for the gate result.

    The table is intentionally simple in chunk 1; it will gain per-axis detail
    and the high-risk-cell section as the remaining axes are implemented.
    """
    lines: list[str] = []
    lines.append(f"Research finding audit for task {result.task_id}")
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
        f"{'Finding':<10} {'Citation':<10} {'Existence':<12} "
        f"{'Confidence':<12} {'Tier':<12} {'Scope':<16}"
    )
    lines.append(header)
    lines.append("-" * 80)
    for fa in result.finding_audits:
        for ca in fa.citation_audits:
            lines.append(
                f"{fa.finding.finding_id:<10} "
                f"{ca.citation.citation_id:<10} "
                f"{_fmt_state(ca.existence_state):<12} "
                f"{_fmt_state(ca.confidence_state):<12} "
                f"{_fmt_state(ca.tier_state):<12} "
                f"{_fmt_state(ca.scope_state):<16}"
            )
            if ca.existence_detail:
                lines.append(f"           detail: {ca.existence_detail}")
        if fa.high_risk:
            lines.append(f"  HIGH-RISK CELL: {fa.high_risk_detail}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
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
        # Minimal JSON output scaffold for chunk 1; richer serialization in later chunks.
        payload = {
            "task_id": result.task_id,
            "exit_code": result.exit_code(),
            "finding_count": len(result.finding_audits),
        }
        print(json.dumps(payload, indent=2))
    else:
        print(render_review_table(result))

    return result.exit_code()


if __name__ == "__main__":
    sys.exit(main())
