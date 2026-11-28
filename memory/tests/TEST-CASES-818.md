# Test Cases: Issue #818 — env_loader targeted resolution + remove load_openclaw_env() from DB-only scripts

**Issue:** [#818](https://github.com/NOVA-Openclaw/nova-mind/issues/818) (SE run 1533)
**Repo/commit:** NOVA-Openclaw/nova-mind @ 315255a
**Date:** 2026-11-28
**Author:** Gem (QA subagent)
**Stage:** Design only — no implementation code, no script changes.

---

## 1. Context

Since 2026-11-26 07:16Z, 100% of semantic-recall turns have failed. `proactive-recall.py`
calls `load_openclaw_env()` at import time; `env_loader.py` resolves all 13 item-map
entries with sequential `nova-op item get --reveal` subprocesses (~5.5s total), which
blows past the hardcoded `SPAWN_TIMEOUT_MS = 5000` in
`~/.openclaw/plugins/turn-context/src/semantic-recall.ts`. Recall needs none of those
secrets — only `pgpass` (via `pg_env.py`) and a local Ollama embedding endpoint (via
`embedding_config.py`), neither of which touches `nova-op`.

A second casualty: `memory-maintenance.py` crashed outright when `nova-op` wasn't on the
launcher's PATH, because only `ImportError` is caught around `load_openclaw_env()`,
and `_nova_op_bin()` raises `RuntimeError` when `shutil.which("nova-op")` returns `None`.

### Approved scope (I)ruid, 2026-11-28)
1. Remove `load_openclaw_env()` from the DB-only scripts: `proactive-recall.py`,
   `dedup_helper.py`, `confidence_helper.py`, `memory-maintenance.py`. Keep it in
   `extract_memories.py` (needs `OPENROUTER_API_KEY`).
2. `env_loader.py`: resolve only requested keys (`load_openclaw_env(keys=[...])`), skip
   keys already in `os.environ`, cache per process, add a per-call subprocess timeout,
   and treat `nova-op` missing/failure/timeout as a **warning**, not a crash. Locate
   `nova-op` via PATH, falling back to `$HOME/.local/bin/nova-op`.
3. Regression test: importing/running `proactive-recall.py` makes **zero** `nova-op` calls.

**Not in scope:** raising `SPAWN_TIMEOUT_MS`; the index-friendly group query rewrite.

### Files read for this design
- `memory/lib/env_loader.py` (current: sequential resolve of every map entry, PATH-only
  lookup, aggregate `RuntimeError` on any failure)
- `memory/scripts/proactive-recall.py` (catches only `ImportError` around the loader)
- `memory/scripts/dedup_helper.py`, `memory/scripts/confidence_helper.py` (same pattern;
  `dedup_helper` imports `confidence_helper`, so **both** call `load_openclaw_env()` in
  the same process today — two redundant 5.5s loads if ever invoked together)
- `memory/scripts/extract_memories.py` (already catches both `ImportError` **and**
  `RuntimeError`, with an explicit fallback check on `OPENROUTER_API_KEY`; only ever
  needs `OPENROUTER_API_KEY` — the `MEMORY_EXTRACTION_MODEL` env var selects a model
  name, not a different provider key)
- `memory/templates/memory-maintenance.py` (catches only `ImportError`; this is the
  exact crash reported in the issue's third comment: `RuntimeError: env_loader: nova-op
  not found in PATH`)
- `memory/tests/test_env_loader.py` (13 existing tests; see §8)
- `~/.openclaw/plugins/turn-context/src/semantic-recall.ts` — confirms
  `SPAWN_TIMEOUT_MS = 5000`, hard `SIGTERM` kill on timeout, and that the Node caller
  only logs+returns `null` on any child failure (so a crashing `proactive-recall.py`
  today silently degrades recall to "nothing found" rather than crashing OpenClaw —
  but still took the full 5s+ doing so)
- `~/.openclaw/scripts/nova-op-item-map.json` — confirmed 13 secret entries (keys only,
  no values read): `OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY,
  GOOGLE_API_KEY, OPENPROJECT_API_KEY, ELEVENLABS_API_KEY, ALPHA_VANTAGE_API_KEY,
  CAPSOLVER_API_KEY, GOG_KEYRING_PASSWORD, NOSTR_HEX_PRIVATE_KEY, NOSTR_NSEC,
  INSTAGRAM_USERNAME, INSTAGRAM_PASSWORD`
- `~/.openclaw/lib/pg_env.py`, `~/.openclaw/lib/embedding_config.py` — confirmed neither
  touches `nova-op` or `load_openclaw_env`

---

## 2. Key design decisions (for the implementer)

| # | Decision | Reasoning |
|---|----------|-----------|
| D1 | New signature: `load_openclaw_env(config_path=None, keys=None)`. | Additive, backward compatible in shape. |
| D2 | **`keys=None` (no args) preserves today's legacy full-resolve behavior** — attempt every non-metadata entry in the item map, same as pre-fix. | Safest default for any caller this audit missed (see TC-G3 static sweep). A silent no-op default would be more "correct" for the new targeted model but risks silently breaking an unaudited caller that genuinely needs a secret. Explicit `keys=[...]` is the recommended path going forward; no-args is kept working, not optimized. |
| D3 | `extract_memories.py`'s call should become `load_openclaw_env(keys=["OPENROUTER_API_KEY"])`, not a bare call. | It only ever reads `OPENROUTER_API_KEY` (confirmed by grep: the only `os.environ.get(...API_KEY...)` in the file). Targeting this one key makes extract_memories 1 subprocess call instead of up to 13, without needing any no-args fallback behavior. TC-F1 encodes this as the expected call shape. |
| D4 | For a given `keys=[...]` call, a key already non-empty in `os.environ` is skipped **before** any map/nova-op access. If **every** requested key is already set (or `keys=[]`), the function returns immediately without opening the item-map file or resolving `nova-op`'s path. | Matches "skip keys already in os.environ" from scope, and makes the library a true no-op when nothing is needed — important because some hosts/dev boxes may not have `nova-op` installed at all and should never be forced to care when every caller-requested var is already present (e.g., plugin-injected). |
| D5 | Per-key `nova-op` subprocess gets a timeout, default **2000ms** (vs. the observed 390–460ms healthy call). Worst case for `extract_memories` (1 key) is ~2s, still far under any of its timeouts; worst case for a legacy no-args call (13 keys, all failing/hanging) is ~26s — acceptable since no-args is no longer used on any 5s-budget hot path after this fix. | Bounds a stuck `nova-op` without being so tight it flakes on a loaded host. Should be overridable via an optional parameter for tests, not a new required argument. |
| D6 | **Failure-class split:** (a) *nova-op availability/runtime* problems — binary missing (PATH + $HOME fallback both fail), subprocess timeout, non-zero exit (`CalledProcessError`, e.g. wrong item ID), or an empty resolved value — are now **warnings**: log to stderr, skip that var, continue, never raise. (b) *Map/config authoring* problems — item map file missing/unreadable, malformed JSON, non-dict top-level JSON, empty map, incomplete entry (missing item/field/vault), or unreplaced `REPLACE_WITH_*` placeholders — **still raise `RuntimeError`**, unchanged. | The issue's "nova-op missing/failure/timeout → warning" language is about *transient/environmental* nova-op problems, which is exactly what caused both production incidents. A broken item map is a different, static bug class that should still fail loudly in CI/dev rather than silently produce an agent running with a missing secret and no signal. `extract_memories.py` already catches *any* `RuntimeError` broadly and falls back to checking `OPENROUTER_API_KEY` directly, so this split doesn't change its degrade behavior either way — belt and suspenders. |
| D7 | `_nova_op_bin()` resolution order: `shutil.which("nova-op")` (PATH) first; if that is `None`, fall back to `$HOME/.local/bin/nova-op` if it exists and is executable; if neither resolves, treat as "missing" under D6(a). | Matches nova-mind#839/#840 and the issue's stopgap note: a minimal-PATH `systemd-run` launcher has no `~/.local/bin`, which is exactly where `nova-op` installs by default. |
| D8 | Process-level cache is keyed by **`(normalized config_path, var)`**, not by var name alone. | Several *existing* `test_env_loader.py` tests run in the same Python process and deliberately reuse env var names (e.g. `OPENROUTER_API_KEY`) against different tmp item maps/stub mappings per test. Each test already uses a fresh `tempfile.mkdtemp()`, so config_path differs per test — keying on `(config_path, var)` means the cache never leaks a value from one test's stub into another test's assertions, with no explicit cache-reset hook required. A var-name-only cache would silently break ~4 existing tests. |
| D9 | A requested key not present as an entry in the item map at all (typo, or a var nobody ever added) is a **warning**, not a raise — "requested key not in item map", var simply stays unresolved. | Consistent with "never crash a caller over secrets config"; still visible via stderr for debugging. |
| D10 | All env_loader warning/error text goes to **stderr only**, and must never include a resolved secret value (only var name / item id / nova-op's own stderr text). | `proactive-recall.py --inject` and `extract_memories.py` both emit machine-parsed JSON on **stdout**; a stray warning on stdout would corrupt that JSON for their callers. This is unchanged from today's convention but must be explicitly verified under the new warning paths (new code = new place to regress it). |

### Open questions for I)ruid / implementer
- **OQ1:** Should the per-key timeout (D5, default 2000ms) be a public keyword argument on `load_openclaw_env`, or only an internal constant? Recommend a keyword arg (`timeout_s`) so tests don't need to monkeypatch a module constant.
- **OQ2:** D6 keeps "incomplete map entry" and "placeholder value" as hard `RuntimeError`s even for a single targeted key. Confirm this is desired — the alternative (warn+skip for those too) would make `env_loader` never raise under any circumstance once keys are supplied, which is a bigger philosophy change than the issue asked for.
- **OQ3:** No existing caller other than `extract_memories.py` and `env_loader.py`'s own `__main__` block should call `load_openclaw_env()` after this change (TC-G3 is a static sweep for this). If that sweep turns up another caller, scope must be revisited before merge.

---

## 3. Test infrastructure notes (for whoever implements these tests)

These extend the existing `test_env_loader.py` helpers rather than replace them:

- **Recording stub:** extend `make_nova_op(tmpdir, mapping)` (or add
  `make_recording_nova_op(tmpdir, mapping, log_path)`) so every invocation appends its
  `argv` (joined) as one line to `log_path` *before* resolving/failing, so tests can
  assert exact call counts even on the failure paths.
- **Slow stub:** a variant that `time.sleep(N)` before responding, for timeout (§6) and
  timing (§5) tests. Must still record its invocation (so a test can tell "it was called
  and took too long" apart from "it was never called").
- **Always-fails stub:** exits non-zero unconditionally (simulates `CalledProcessError`,
  e.g. a wrong item ID or vault lockout), still recording the call.
- **Missing-binary case:** don't add a stub at all; use a temp `PATH` with no `nova-op`,
  and a temp `HOME` whose `.local/bin` doesn't contain one either.
- **$HOME fallback case:** place the stub only at `$HOME/.local/bin/nova-op` with a temp
  `HOME`, and a `PATH` that excludes it.
- **Import-time tests (§4):** run via a subprocess (`python3 -c "import proactive-recall"`
  style, or `python3 -m py_compile` + `runpy`) with a rigged `PATH`/`HOME`, not via the
  test runner's own process, so that a crash during import can't take down the whole
  test suite and so `sys.path`/module-cache pollution between tests is avoided.
- All of the above are **temp-directory based** — no writes to `~/.secrets`, `.env`,
  `secrets.env`, or the real `~/.openclaw/openclaw.json`/item map, and no reads of their
  contents either.

---

## 4. Category A — Zero `nova-op` calls per DB-only script (regression, scope item 1 & 3)

| ID | Script | Check | Type |
|----|--------|-------|------|
| TC-A1 | `proactive-recall.py` | Static: source no longer contains `load_openclaw_env` or `from env_loader import` | static |
| TC-A2 | `proactive-recall.py` | Importing the module (PATH rigged to a recording stub) records **0** invocations in the call log; import succeeds | unit |
| TC-A3 | `dedup_helper.py` | Static: source no longer references `load_openclaw_env`/`env_loader` | static |
| TC-A4 | `dedup_helper.py` | Importing the module records **0** invocations — including transitively, since `dedup_helper` imports `confidence_helper` (today's double-load path) | unit |
| TC-A5 | `confidence_helper.py` | Static: source no longer references `load_openclaw_env`/`env_loader` | static |
| TC-A6 | `confidence_helper.py` | Importing the module standalone records **0** invocations | unit |
| TC-A7 | `memory-maintenance.py` | Static: source no longer references `load_openclaw_env`/`env_loader` | static |
| TC-A8 | `memory-maintenance.py` | Importing the module (PATH rigged to recording stub) records **0** invocations; import succeeds even though this is the exact script that crashed in production | unit |
| TC-A9 | all four scripts | Importing each with **no `nova-op` anywhere** (not PATH, not `$HOME/.local/bin`, no stub at all) still succeeds with zero errors — proves true independence from `nova-op`'s existence, not just that calls happen to be zero | unit |

---

## 5. Category B — Recall timing stays well under `SPAWN_TIMEOUT_MS`

| ID | Description | Setup | Expected | Type |
|----|-------------|-------|----------|------|
| TC-B1 | Full `proactive-recall.py` run (via subprocess, mirroring `semantic-recall.ts`'s `spawn()` call) with a **slow** `nova-op` stub (10s sleep) first on PATH | Real stdin JSON payload (`{"content": "..."}`); DB/Ollama may be live or stubbed — what's measured is wall-clock time and the recording stub's call count | Call log shows **0** invocations (script never touches nova-op at all, regardless of how slow a hypothetical one is); total wall time is governed only by DB+embedding latency, not by the stub's sleep duration | unit |
| TC-B2 | Live, read-only: on `nova-staging@localhost`, run the real post-fix `proactive-recall.py` against the real staging DB + local Ollama with a representative query | Shadow the staging `PATH` for this one invocation with a recording wrapper ahead of the real `nova-op`, so any accidental call is both counted and still answered correctly (never breaks other concurrent use of nova-op on the box) | Wall time comfortably under 2s (budget: `SPAWN_TIMEOUT_MS=5000`); **0** nova-op invocations recorded | live-read-only |
| TC-B3 | Confirm the Node-side `SPAWN_TIMEOUT_MS=5000` hard kill in `semantic-recall.ts` is no longer the limiting factor | Time just the Python script phases (env/DB-connect/embed/SQL) the way the issue's own phase breakdown did, with the slow stub from TC-B1 on PATH | Env-load phase is ~0ms (skipped entirely, not merely fast); total stays in the same tens-to-low-hundreds-of-ms range the issue reported for everything *except* env load (12ms DB connect + 26ms embed + ~519ms SQL) | unit |

---

## 6. Category C — Targeted resolution, skip-if-present, short-circuit, caching

| ID | Description | Expected | Type |
|----|-------------|----------|------|
| TC-C1 | Map has 3 secret entries; call `load_openclaw_env(keys=["B"])` | Only `B`'s subprocess is invoked (call log length 1); `A` and `C` are never touched, not returned, not set in `os.environ` | unit |
| TC-C2 | Requested key `X` already non-empty in `os.environ` | Call log length 0 for `X`; returned dict has `X` == pre-existing value (existing value wins, per current convention) | unit |
| TC-C3 | All requested keys already present in `os.environ`; item-map **file is deleted** before the call | Function returns normally (no `RuntimeError` for a missing map file) because the map is never opened when nothing needs resolving | unit |
| TC-C4 | `keys=[]` (explicit empty list), with or without a map file present | Returns `{}` immediately; call log length 0; no file I/O against the map | unit |
| TC-C5 | Same process, `load_openclaw_env(config_path=cfg, keys=["X"])` called twice | Call log length stays at **1** after the second call (cache hit); both calls return the same value | unit |
| TC-C6 | After TC-C5's first call, delete `X` from `os.environ` externally (`os.environ.pop`), then call again with the same `config_path`/`keys` | Cache still answers without a second subprocess call (call log stays 1); `os.environ["X"]` is re-set from the cached value (cache survives external env mutation, per D8) | unit |
| TC-C7 | Two **different** `config_path`s (different tmp dirs) both define a var named `X` with different stub mappings, requested via `keys=["X"]` in the same process | Each call resolves against **its own** config's stub mapping (cache keyed by `(config_path, var)` per D8) — second config's result is NOT the first config's cached value | unit |
| TC-C8 | `keys=["_description"]` (a metadata key) requested explicitly | No subprocess call; `_description` never resolved/returned, same as when it's encountered during a full scan | unit |
| TC-C9 | `keys=["NOT_IN_MAP"]` — var not present as an entry in the item map at all | No `RuntimeError`; stderr warning names the requested key; var absent from result/env (D9) | unit |

---

## 7. Category D — `nova-op` missing/failure/timeout degrade to warning, never crash

| ID | Description | Expected | Type |
|----|-------------|----------|------|
| TC-D1 | Requested key's `nova-op` stub sleeps longer than the per-key timeout (D5) | No exception; stderr warning names the var (not the would-be value); var absent from result/env; call duration ≈ timeout, not the full sleep | unit |
| TC-D2 | `nova-op` exits non-zero for a requested key (always-fails stub) | No exception; warning to stderr; key skipped; any **other** requested keys in the same call still resolve normally | unit |
| TC-D3 | `nova-op` absent from both PATH and `$HOME/.local/bin` | No exception; one warning covering the missing binary; all requested keys end up unresolved | unit |
| TC-D4 | `extract_memories.py`-style caller: `load_openclaw_env(keys=["OPENROUTER_API_KEY"])` with a failing stub, but `OPENROUTER_API_KEY` already set in `os.environ` (plugin-injected) | D4's skip-if-present fires before the failing stub is ever reached — key resolves from existing env, 0 subprocess calls, caller proceeds normally | unit |
| TC-D5 | `nova-op` succeeds (exit 0) but prints an empty string for a requested key | Treated as a failure under D6(a): warning, key skipped, no `RuntimeError` (this is a **behavior change** from today, where empty-value is a hard `RuntimeError` — see §8, supersedes current empty-value coverage for the targeted/warn path) | unit |
| TC-D6 | Structural map errors — incomplete entry (missing `item`/`field`/`vault`) and unreplaced `REPLACE_WITH_*` placeholders — for a requested key | **Still raises `RuntimeError`** (per D6(b)); confirms these are NOT downgraded to warnings alongside D1–D3, D5 | unit |

---

## 8. Category E — `$HOME/.local/bin/nova-op` fallback

| ID | Description | Expected | Type |
|----|-------------|----------|------|
| TC-E1 | `nova-op` absent from PATH, present+executable at `$HOME/.local/bin/nova-op` (temp `HOME`) | Resolution succeeds via the fallback binary; requested key resolves correctly | unit |
| TC-E2 | `nova-op` absent from both PATH and the $HOME fallback | Degrades per TC-D3 (cross-reference, not a new behavior) | unit |
| TC-E3 | Two distinguishable recording stubs (each tags its log line, e.g. `PATH-STUB`/`HOME-STUB`) present at both PATH and `$HOME/.local/bin` | Only the **PATH** stub's tag appears in the call log — confirms PATH takes precedence over the $HOME fallback (D7 order) | unit |

---

## 9. Category F — `extract_memories.py` still gets its provider key

| ID | Description | Expected | Type |
|----|-------------|----------|------|
| TC-F1 | `OPENROUTER_API_KEY` not pre-set; working recording stub returns a fake key | `os.environ["OPENROUTER_API_KEY"]` is set to the resolved value; call log length is exactly **1** (not 13) — confirms the call shape recommended in D3 (`keys=["OPENROUTER_API_KEY"]`), not a bare/legacy call | unit |
| TC-F2 | `OPENROUTER_API_KEY` pre-injected (plugin env var case) | Zero `nova-op` calls at all (D4 short-circuit) | unit |
| TC-F3 | `nova-op` missing entirely, `OPENROUTER_API_KEY` **not** set anywhere | Existing fallback path fires unchanged: script prints `"env_loader failed and OPENROUTER_API_KEY is not set"`-style message to stderr and exits non-zero (regression check against lines ~40–47 of `extract_memories.py`, which already catch `RuntimeError` broadly) | unit |
| TC-F4 | `nova-op` missing entirely, `OPENROUTER_API_KEY` **is** set elsewhere (e.g. plugin env) | Script continues normally past the env_loader call — the new warning path (D6a) and the script's own pre-existing `RuntimeError` catch no longer even need to cooperate here, since D6a means no exception is raised in the first place; confirms the degrade story is strictly better than before, not merely equivalent | unit |

---

## 10. Category G — Backward compatibility of a bare `load_openclaw_env()` call

| ID | Description | Expected | Type |
|----|-------------|----------|------|
| TC-G1 | Call `load_openclaw_env()` with **zero args**, `HOME` overridden to a temp dir containing both a full item map (default location under that `HOME`) and a working recording stub, so the default `config_path` resolves safely without ever touching the real vault | Every non-metadata entry in the map is attempted, matching pre-fix "resolve everything" behavior (D2) — confirms no-args is NOT a silent no-op | unit |
| TC-G2 | Same no-args setup, but one entry's stub fails (always-fails) | That one entry warns+skips (D6a) while the rest still resolve — confirms no-args mode uses the **same** new failure handling as targeted mode, only the key-selection differs | unit |
| TC-G3 | Static: `grep -rn "load_openclaw_env("` across the whole repo (and installed `~/.openclaw/scripts`, `~/.openclaw/lib` tree) | Only two call sites remain: `extract_memories.py` (expected to use `keys=[...]`, per D3) and `env_loader.py`'s own `__main__` block. Any other hit is a caller this design missed and must be triaged before merge (OQ3) | static |

---

## 11. Category H — No secrets in stdout/stderr/logs

| ID | Description | Expected | Type |
|----|-------------|----------|------|
| TC-H1 | Meta-check over every captured stdout/stderr buffer produced by the unit tests in §4–§10 | None of the stub-fixture fake secret values (e.g. `"fake-openrouter-key"`) appear in any captured output — only in the test's own in-memory assertions, never echoed by the library | unit |
| TC-H2 | For TC-D1–TC-D3 (warning paths) and TC-F1/TC-F3 specifically, capture stdout and stderr separately | All warning/error text appears on **stderr only**; stdout is empty (library tests) or valid, uncorrupted JSON (end-to-end `proactive-recall.py`/`extract_memories.py` invocations) even while a warning fired underneath (D10) | unit |
| TC-H3 | Static: grep `env_loader.py` and the five target scripts for any `print(value)`/`logging.*(value)`-style statement that could emit a resolved secret | No such statement exists; all diagnostic output references var names / item IDs / nova-op's own stderr text, never the resolved value itself | static |

---

## 12. Category I — Existing `test_env_loader.py` coverage: still valid vs. superseded

| Existing test | Verdict | Notes |
|---|---|---|
| TEST-1.2 loads vars from valid map via nova-op | **Still valid** | Exercises the legacy/no-keys path (D2); consider adding a sibling using `keys=[...]` (covered by new TC-C1/TC-F1) but no change needed to this test itself. |
| TEST-2.2 existing env var NOT overwritten | **Still valid** | Unchanged behavior; also exercised under targeted mode by TC-C2. |
| TEST-2.3 empty env var IS overwritten | **Still valid** | Empty-string-in-env is still treated as "unset," unchanged. |
| TEST-3.2 metadata keys skipped | **Still valid** | Also exercised explicitly-requested via TC-C8. |
| TEST-5.2 malformed JSON raises RuntimeError | **Still valid** | Config-level error, kept fatal per D6(b). |
| TEST-5.3 non-dict top-level JSON raises | **Still valid** | Same as above. |
| TEST-6.2 missing config raises RuntimeError | **Still valid, with a caveat** | True whenever at least one key actually needs resolving (this test's existing call has no `keys=`, so it still exercises the full legacy path and still needs the file). The new short-circuit (file never opened when nothing needs resolving) is a *distinct* scenario, covered by new TC-C3/TC-C4 — not a change to this test. |
| TEST-7.2 unreadable config raises RuntimeError | **Still valid, same caveat as TEST-6.2** | |
| TEST-8.3 empty map raises RuntimeError | **Still valid** | Config-level error, kept fatal per D6(b). |
| TEST-10.5 idempotent double call | **Still valid, recommend extending** | Currently only checks returned values are equal across two calls; it does not use a call-counting stub, so it does not yet prove the new caching requirement. Recommend swapping in the recording stub and asserting call-log length stays at 1 after the second call. Fully covered going forward by new TC-C5. |
| TEST-10.6 wrong item ID fails loudly | **SUPERSEDED** | Under D6(a), a wrong item ID produces a `CalledProcessError` from `nova-op` — now a *failure*, not a config error, so it must **warn + skip**, not raise. This test's current assertion (`except RuntimeError: ... "wrong-item-id" in str(exc)`) will fail against the new implementation and must be rewritten to: call does not raise; stderr warning contains "wrong-item-id" (or the var name); the var is absent from both `os.environ` and the returned dict. See TC-D2 for the generalized version of this case. |
| TEST-10.7 custom config_path | **Still valid** | Unchanged; also implicitly exercised by every targeted-mode test since they all pass explicit `config_path`s. |
| TEST-10.8 placeholder values fail loudly | **Still valid** | Config-authoring error, kept fatal per D6(b); confirmed not downgraded by TC-D6. |

**Summary: 12 of 13 existing tests remain valid as written (2 of those — TEST-6.2/7.2 — carry a scenario-scope caveat, not a behavior change); 1 (TEST-10.5) should be extended but still passes as-is; 1 (TEST-10.6) is superseded and must be rewritten.**

---

## 13. Case counts

| Category | Count |
|---|---|
| A — Zero-nova-op regression (per script) | 9 |
| B — Recall timing | 3 |
| C — Targeted resolution / skip / short-circuit / cache | 9 |
| D — Warning-not-crash on nova-op failure | 6 |
| E — $HOME fallback | 3 |
| F — extract_memories provider key | 4 |
| G — Backward compatibility (no-args) | 3 |
| H — No secrets leak | 3 |
| **New test cases total** | **40** |
| I — Existing test_env_loader.py disposition | 13 reviewed (11 unchanged, 1 extend-recommended, 1 superseded/rewrite) |

By type: **static = 7**, **unit = 32**, **live-read-only = 1** (TC-B2, staging-only, read-only).

---

## 14. Open questions (recap)

- **OQ1:** Public `timeout_s` kwarg vs. internal constant for the per-key subprocess timeout (D5).
- **OQ2:** Confirm D6's split (availability/runtime → warn; map/config → raise) matches intent, vs. making `env_loader` never raise once `keys` is supplied.
- **OQ3:** TC-G3's static sweep must come back clean (only `extract_memories.py` + `env_loader.py`'s `__main__`) before this is safe to merge; if it doesn't, scope needs a second look.
