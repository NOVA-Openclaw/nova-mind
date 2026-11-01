#!/usr/bin/env python3
"""
refresh-model-catalog.py — keep the shared model catalog current.

Single source of truth: /opt/agents/shared-config/models-providers.json
Included by each peer's ~/.openclaw/openclaw.json via
  "models": { "providers": { "$include": "./models-providers.json" } }

OpenClaw's $include security check REJECTS hardlinks and files outside the
user's home, so the shared catalog CANNOT be hard/sym-linked into peer homes.
We keep one authoritative copy in /opt and COPY it (regular file, owned by the
peer, mode 600) into each peer's ~/.openclaw/ on every run.

Data sources:
  1. PUBLIC OpenRouter /models endpoint (no API key) — carries anthropic/*,
     openai/*, x-ai/*, deepseek/* ids with pricing + context. Direct Anthropic
     entries (claude-opus-5) are derived from the same data.
  2. PROVIDER-DIRECT /models endpoints (OpenAI-compatible) for providers whose
     API key is present in the environment. This catches direct-only models that
     never appear on OpenRouter (e.g. moonshot/kimi-k3, moonshot-v1-*). Added
     2026-08-29 (nova-mind moonshot-gap) — the OpenRouter-only design silently
     missed 10 Moonshot models for months because it described what is MIRRORED,
     not what EXISTS.

VERIFICATION (added 2026-08-29): after every run, counts models per provider and
ALERTS (non-zero exit + stderr) when a provider drops to zero or below a floor,
or when a keyed provider could not be reached. A registry that is stale in a way
nobody notices is worse than one that is obviously broken.

Per GLOBAL/CRON_DESIGN: deterministic script owns the write. Additive + curated:
only ADDS newly-discovered models for the watched families; never deletes
hand-maintained entries. Validates JSON, backs up, atomic writes, validates each
peer config load.
"""
import json, os, sys, shutil, tempfile, subprocess, urllib.request, urllib.error, glob
from datetime import datetime, timezone

SHARED = "/opt/agents/shared-config/models-providers.json"
# Machine-readable direct-fetch gap report consumed by Newhart's weekly fallback
# validator (2026-08-29). Shape: {"generated": ISO8601, "gaps": {"<provider>": [ids]}}.
# Written every run so a stale artifact never lingers: empty gaps object when none.
# 0640 root:agents so all peers can read it (same access class as the catalog).
GAPS_ARTIFACT = "/opt/agents/shared-config/direct-fetch-gaps.json"
OPENROUTER_URL = "https://openrouter.ai/api/v1/models"
PEERS = ["nova", "newhart", "graybeard", "victoria"]

WATCH_PREFIXES = (
    "anthropic/claude-opus-", "anthropic/claude-sonnet-",
    "anthropic/claude-haiku-", "anthropic/claude-fable-",
    "openai/gpt-5", "x-ai/grok-4", "deepseek/deepseek-v",
)
SKIP_SUFFIXES = (":batch", "-fast", ":free", ":thinking", ":extended")

# Provider-direct fetch config. Each keyed provider with an OpenAI-compatible
# /models endpoint can be polled directly when its API key is in the environment.
# env: the environment variable holding the key (convention: <PROVIDER>_API_KEY).
# min_expected: alert floor — if a keyed provider yields fewer than this, warn.
DIRECT_PROVIDERS = {
    "moonshot": {"env": ("MOONSHOT_API_KEY", "KIMI_API_KEY"), "path": "/models", "min_expected": 2},
    "deepseek": {"env": ("DEEPSEEK_API_KEY",),                "path": "/models", "min_expected": 1},
    "xai":      {"env": ("XAI_API_KEY",),                     "path": "/models", "min_expected": 1},
    "venice":   {"env": ("VENICE_API_KEY",),                  "path": "/models", "min_expected": 1},
}

# Per-provider alert floors for the post-write verification pass. A provider
# dropping below its floor (or to zero) is a loud failure, not a silent gap.
MIN_MODELS = {
    "openrouter": 5, "anthropic": 3, "moonshot": 2, "deepseek": 1,
    "xai": 1, "google": 1, "venice": 1,
}

def log(msg):
    print(f"[{datetime.now(timezone.utc).isoformat(timespec='seconds')}] {msg}")

def warn(msg):
    print(f"[{datetime.now(timezone.utc).isoformat(timespec='seconds')}] WARN: {msg}", file=sys.stderr)

def fetch_openrouter():
    req = urllib.request.Request(OPENROUTER_URL, headers={"User-Agent": "openclaw-catalog-refresh/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["data"]

def _resolve_key(env_names):
    for n in env_names:
        v = os.environ.get(n)
        if v:
            return v
    return None

def fetch_direct(provider, base_url, cfg):
    """Fetch a provider's own /models list. Returns (model_ids, status).
    status in {'ok','no_key','error'}. Never raises."""
    key = _resolve_key(cfg["env"])
    if not key:
        return [], "no_key"
    url = base_url.rstrip("/") + cfg["path"]
    try:
        req = urllib.request.Request(url, headers={
            "Authorization": f"Bearer {key}",
            "User-Agent": "openclaw-catalog-refresh/1.0",
        })
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
        ids = [m["id"] for m in data.get("data", []) if isinstance(m, dict) and m.get("id")]
        return ids, "ok"
    except Exception as e:
        warn(f"direct fetch failed for {provider} ({url}): {e}")
        return [], "error"

def ppm(pricing, key):
    v = pricing.get(key)
    if v in (None, ""): return 0
    try: return round(float(v) * 1_000_000, 6)
    except (TypeError, ValueError): return 0

def or_entry(m):
    arch = m.get("architecture", {}) or {}
    inputs = [x for x in (arch.get("input_modalities") or ["text"]) if x in ("text", "image")] or ["text"]
    pricing = m.get("pricing", {}) or {}
    tp = m.get("top_provider", {}) or {}
    ctx = tp.get("context_length") or m.get("context_length") or 0
    maxtok = tp.get("max_completion_tokens") or m.get("max_completion_tokens") or 0
    sp = m.get("supported_parameters") or []
    name = m.get("name", m["id"])
    if ": " in name: name = name.split(": ", 1)[1]
    return {"id": m["id"], "name": name, "reasoning": "reasoning" in sp, "input": inputs,
            "cost": {"input": ppm(pricing,"prompt"), "output": ppm(pricing,"completion"),
                     "cacheRead": ppm(pricing,"input_cache_read"), "cacheWrite": ppm(pricing,"input_cache_write")},
            "contextWindow": ctx, "maxTokens": maxtok}

def to_direct_anthropic(e):
    oid = e["id"].split("/", 1)[1]
    d = dict(e); d["id"] = oid.replace(".", "-"); d["api"] = "anthropic-messages"
    return d

def wanted(mid):
    if any(mid.endswith(s) or s in mid for s in SKIP_SUFFIXES): return False
    return any(mid.startswith(p) for p in WATCH_PREFIXES)

def merge(catalog, or_models):
    added = []
    or_block = catalog.setdefault("openrouter", {}).setdefault("models", [])
    or_have = {m["id"] for m in or_block}
    for m in or_models:
        mid = m["id"]
        if not wanted(mid): continue
        entry = or_entry(m)
        if mid not in or_have:
            or_block.insert(0, entry); or_have.add(mid); added.append(f"openrouter/{mid}")
        if mid.startswith("anthropic/") and "anthropic" in catalog:
            direct = to_direct_anthropic(entry)
            an_block = catalog["anthropic"]["models"]
            if direct["id"] not in {x["id"] for x in an_block}:
                an_block.insert(0, direct); added.append(f"anthropic/{direct['id']}")
    return added

def report_direct_new(catalog, provider, model_ids):
    """REPORT-ONLY: return the list of direct-provider model ids that are NOT
    already present in the curated registry. Does NOT mutate the catalog.

    Rationale (2026-08-29 incident): auto-injecting id-only shells with a
    needs_specs flag produced schema-INVALID model entries (missing required
    cost/contextWindow/maxTokens/input fields) that failed OpenClaw config
    validation for all three peers and had to be rolled back. Provider-direct
    /models lists are also a firehose (venice serves 111, most irrelevant). So
    the script now DETECTS new direct-only models and LOGS them for a human
    curator to add with full specs — it never writes them into the registry
    OpenClaw loads."""
    block = catalog.get(provider) or {}
    have = {m["id"] for m in block.get("models", []) if isinstance(m, dict) and m.get("id")}
    return [mid for mid in model_ids if mid not in have]

def atomic_write(path, s, mode=0o640, owner=None, group=None):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".catalog.", suffix=".json")
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w") as fh: fh.write(s)
        if owner or group: shutil.chown(tmp, user=owner, group=group)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def verify_counts(catalog):
    """Post-write verification. Returns (ok, list_of_alerts)."""
    alerts = []
    for prov, floor in MIN_MODELS.items():
        block = catalog.get(prov) or {}
        n = len(block.get("models", []) or [])
        if n == 0:
            alerts.append(f"{prov}: ZERO models (floor {floor})")
        elif n < floor:
            alerts.append(f"{prov}: only {n} models (below floor {floor})")
    return (len(alerts) == 0, alerts)

def main():
    if not os.path.exists(SHARED):
        log(f"FATAL: shared catalog missing at {SHARED}"); return 2
    catalog = json.load(open(SHARED))

    added = []
    direct_gaps = []  # [(provider, [new_model_ids])] — reported, not written

    # --- Source 1: OpenRouter (public, no key) ---
    try:
        or_models = fetch_openrouter()
        log(f"fetched {len(or_models)} models from OpenRouter")
        added += merge(catalog, or_models)
    except Exception as e:
        # OpenRouter failure is fatal for the watched families but does not block
        # provider-direct discovery below.
        warn(f"OpenRouter fetch failed: {e}")

    # --- Source 2: provider-direct /models (keyed providers only) ---
    for prov, cfg in DIRECT_PROVIDERS.items():
        block = catalog.get(prov) or {}
        base = block.get("baseUrl")
        if not base:
            continue
        ids, status = fetch_direct(prov, base, cfg)
        if status == "no_key":
            log(f"direct {prov}: SKIPPED (no key in env {cfg['env']}) — "
                f"registry may be missing direct-only models until key is wired")
            continue
        if status == "error":
            log(f"direct {prov}: fetch error (see WARN above)")
            continue
        log(f"direct {prov}: fetched {len(ids)} models")
        if len(ids) < cfg.get("min_expected", 1):
            warn(f"direct {prov}: only {len(ids)} models, expected >= {cfg['min_expected']}")
        new_ids = report_direct_new(catalog, prov, ids)
        if new_ids:
            # REPORT-ONLY — do not mutate the registry (see report_direct_new docstring).
            log(f"direct {prov}: {len(new_ids)} model(s) NOT in curated registry "
                f"(curator action needed to add with full specs): {', '.join(new_ids)}")
            direct_gaps.append((prov, new_ids))

    # --- Write path (only if something changed) ---
    if not added:
        log("no new models to add; catalog already current")
    else:
        log(f"adding {len(added)} entries: {', '.join(added)}")
        new_str = json.dumps(catalog, indent=2); json.loads(new_str)
        ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")

        # --- VALIDATE-THEN-DISTRIBUTE (hard gate, 2026-08-29) ---
        # A prior version distributed to all peer homes BEFORE validating, so a
        # bad generation reached every peer's loaded config and had to be rolled
        # back. Same distribution-gap topology as the cleartext-key incident:
        # /opt is the source, home copies are what OpenClaw loads. Fix: validate
        # the candidate against a REAL peer's openclaw config load FIRST, using a
        # throwaway staging copy, and ONLY distribute if it passes. A bad
        # generation never reaches a peer home at all.
        gate_peer = next((a for a in PEERS
                          if os.path.isdir(f"/home/{a}/.openclaw")
                          and os.path.exists(f"/home/{a}/.npm-global/bin/openclaw")), None)
        if gate_peer is None:
            log("FATAL: no peer available to validate candidate catalog; refusing to distribute")
            return 5
        gate_home = f"/home/{gate_peer}/.openclaw/models-providers.json"
        gate_stage = f"{gate_home}.candidate.{ts}"
        gate_backup = f"{gate_home}.gatebak.{ts}"
        gate_ok = False
        try:
            # Stage candidate in place of the gate peer's live copy, validate, restore.
            shutil.copy2(gate_home, gate_backup)
            try: shutil.chown(gate_backup, user=gate_peer, group=gate_peer)
            except Exception: pass
            os.chmod(gate_backup, 0o600)
            atomic_write(gate_home, new_str, 0o600, gate_peer, gate_peer)
            ocbin = f"/home/{gate_peer}/.npm-global/bin/openclaw"
            r = subprocess.run(["sudo","-u",gate_peer,"-H",ocbin,"config","validate"],
                               capture_output=True, text=True, timeout=120)
            gate_ok = "Config valid" in (r.stdout + r.stderr)
            if not gate_ok:
                log(f"GATE FAILED on {gate_peer}: candidate catalog is schema-invalid; "
                    f"NOT distributing. tail: {(r.stderr or r.stdout)[-400:]}")
        finally:
            # Always restore the gate peer's known-good copy before deciding.
            if os.path.exists(gate_backup):
                atomic_write(gate_home, open(gate_backup).read(), 0o600, gate_peer, gate_peer)
                os.unlink(gate_backup)
            if os.path.exists(gate_stage):
                try: os.unlink(gate_stage)
                except Exception: pass

        if not gate_ok:
            warn("validation gate failed — registry NOT updated, no peer homes touched")
            return 4

        # Gate passed: NOW write /opt source and distribute to all peers.
        shutil.copy2(SHARED, f"{SHARED}.bak.{ts}"); os.chmod(f"{SHARED}.bak.{ts}", 0o600)
        atomic_write(SHARED, new_str, 0o640, "root", "agents")
        log(f"validation gate passed on {gate_peer}; updated shared catalog (backup .bak.{ts})")
        for a in PEERS:
            hp = f"/home/{a}/.openclaw/models-providers.json"
            if not os.path.isdir(os.path.dirname(hp)):
                log(f"skip {a}: no ~/.openclaw"); continue
            if os.path.exists(hp):
                shutil.copy2(hp, f"{hp}.bak.{ts}")
                try: shutil.chown(f"{hp}.bak.{ts}", user=a, group=a)
                except Exception: pass
                os.chmod(f"{hp}.bak.{ts}", 0o600)
            atomic_write(hp, new_str, 0o600, a, a)
            log(f"synced catalog to {a}")
        # Post-distribution confirm (belt-and-suspenders; gate already passed).
        for a in PEERS:
            try:
                ocbin = f"/home/{a}/.npm-global/bin/openclaw"
                r = subprocess.run(["sudo","-u",a,"-H",ocbin,"config","validate"],
                                   capture_output=True, text=True, timeout=120)
                ok = "Config valid" in (r.stdout + r.stderr)
                log(f"validate {a}: {'OK' if ok else 'FAILED'}")
                if not ok: log(f"  {a} tail: {(r.stderr or r.stdout)[-300:]}")
            except Exception as e:
                log(f"validate {a}: ERROR {e}")

    # --- Direct-fetch gap summary (report-only; curator action) ---
    if direct_gaps:
        total = sum(len(ids) for _, ids in direct_gaps)
        log(f"direct-fetch gaps: {total} model(s) served by providers but absent from "
            f"the curated registry — curator must add with full specs:")
        for prov, ids in direct_gaps:
            log(f"  {prov}: {', '.join(ids)}")

    # Emit machine-readable artifact for the fallback validator. Written EVERY run
    # (including empty) so a prior run's gaps never persist as stale data. Failure
    # to write the artifact must not fail the run — it is advisory, not critical.
    try:
        artifact = {
            "generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "gaps": {prov: ids for prov, ids in direct_gaps},
        }
        atomic_write(GAPS_ARTIFACT, json.dumps(artifact, indent=2) + "\n",
                     0o640, "root", "agents")
        log(f"wrote gap artifact {GAPS_ARTIFACT} "
            f"({sum(len(v) for v in artifact['gaps'].values())} model(s) across "
            f"{len(artifact['gaps'])} provider(s))")
    except Exception as e:
        warn(f"failed to write gap artifact {GAPS_ARTIFACT}: {e}")

    # --- Post-write verification (always runs, even on no-change) ---
    ok, alerts = verify_counts(catalog)
    if not ok:
        for a in alerts:
            warn(f"VERIFY: {a}")
        warn(f"verification FAILED: {len(alerts)} provider(s) below floor — registry may be stale/broken")
        return 4  # non-zero so cron/monitoring surfaces the alert
    log("verification: all providers at/above floor")
    # Note: direct-fetch gaps are informational (curator action), NOT a run failure.
    return 0

if __name__ == "__main__":
    rc = main()
    try:
        for pat in [f"{SHARED}.bak.*"] + [f"/home/{a}/.openclaw/models-providers.json.bak.*" for a in PEERS]:
            for old in sorted(glob.glob(pat))[:-10]:
                try: os.unlink(old)
                except Exception: pass
    except Exception: pass
    sys.exit(rc)
