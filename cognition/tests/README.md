# cognition/tests/

Point-in-time test-design docs, fix summaries, and pytest suites for `cognition/` bug fixes and features. These are historical/audit artifacts (out of scope for documentation-accuracy edits — see `cognition/CHANGELOG.md` for the current, maintained record of fixes) except where noted.

## Active pytest suites

- `test_pg_notify_listener_issue_399.py` — regression suite for `pg-notify-listener.py`'s direct-push/retry/backoff/alerting behavior (#399).
- `test_pg_notify_listener_issue_506.py` — regression suite for the `_ensure_on_main()` branch-safety check (#506). Shares fixtures with the #399 suite via `conftest.py`.
- `test_pg_notify_listener_issue_508.py` — regression suite for PGUSER-based alert sender binding and self-safe recipient resolution (#508).
- `conftest.py` — shared fixtures/helpers extracted from the #399 suite so the #506 and #508 suites can reuse them without duplication.
- `test-issue-64.ts` / `verify-issue-64-fix.sh` — verification script and TypeScript test for the #64 fallback-directory fix.

## Historical/point-in-time artifacts (not maintained, kept for audit trail)

- `FIX-SUMMARY-BATCH-40-41-42.md` — fix summary for issues #40/#41/#42.
- `ISSUE-64-CODE-CHANGES.md`, `ISSUE-64-FIX-SUMMARY.md`, `ISSUE-64-STATUS.txt` — design/fix/status docs for issue #64.
- `TEST-CASES-BATCH-23-25-29.md`, `TEST-CASES-BUGS-23-24-25.md` — test-case designs for the nova-cognition-era issues #23/#24/#25/#29.
- `TEST-CASES-ISSUE-22.md` — test cases for the original agent_chat schema installer step (issue #22).
- `TEST-CASES-ISSUE-83.md` — test cases for shell-aliases.sh/.bash_env installation (issue #83).
- `TEST-CASES-ISSUE-84.md` — test cases for shell-environment documentation accuracy (issue #84).
- `TEST-CASES-ISSUE-97.md` — test cases for the `orchestrator_agent_id` workflows-table addition (issue #97). Carries its own staleness banner: several assertions predate the PR #244 uppercase `source` label change and would need re-casing to run today.
- `TEST-RESULTS-ISSUE-97.md` — recorded test run results for issue #97.

These predate the current `nova-mind` repo structure (several reference the deprecated `nova-cognition` repo) and are not updated when the underlying code changes. Do not treat them as current specs — check `cognition/CHANGELOG.md` and the live source for present-day behavior.
