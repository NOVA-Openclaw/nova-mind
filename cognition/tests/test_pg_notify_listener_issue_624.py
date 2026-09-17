"""Tests for cognition/scripts/pg-notify-listener.py issue #624.

Covers the anti-clobber safeguard: a `pgschema dump` that would silently
remove a hand-authored object listed in database/.schema-manifest.toml
(e.g. append_run_note()) must be refused for the ENTIRE sync, the clobbered
schema.sql must be reverted from the working tree (not merely left
uncommitted), the git lock must still be released, and a distinct
agent_chat alert (never notify_clawdbot, a documented no-op) must name the
missing object(s). A dump that removes a non-manifest object must proceed
normally (negative case).

Test IDs below correspond to Gem's test design for #624:
  LSV-1..LSV-9: listener-side veto behavior
  NEW-1: manifest loader/parser unit coverage
  NEW-2: live-DB restoration verified via pgschema plan/apply (covered by
         the manual verification in the SE run report, not unit tests --
         a unit test cannot safely apply DDL to the shared production
         nova_memory database).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from conftest import (
    pg_notify_listener,
    _clone_head,
    _current_branch,
    _lock_is_held,
    _remote_head,
    _set_schema_content,
)


MANIFEST_MISSING_FUNCTION = """\
[functions]
patterns = [
  "append_run_note(integer, text)",
]
"""

# Real append_run_note() body, used to build realistic "before" schema
# content for the veto tests. Derivation: verbatim from
# database/schema.sql (restored in this same issue/PR from commit
# 880aa46) -- NOT retyped from a summary, copied from the file on disk.
APPEND_RUN_NOTE_SQL = """\
--
-- Name: append_run_note(integer, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_stamped_line TEXT;
BEGIN
    IF p_note IS NULL THEN
        RAISE EXCEPTION 'append_run_note: p_note cannot be NULL';
    END IF;

    v_stamped_line := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC — ' || p_note;

    UPDATE workflow_runs
    SET notes = CASE
        WHEN notes IS NULL OR notes = '' THEN v_stamped_line
        ELSE notes || E'\\n' || v_stamped_line
    END
    WHERE id = p_run_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'append_run_note: run_id % not found', p_run_id;
    END IF;
END;
$$;

--
-- Name: append_run_note(integer, text); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION append_run_note(integer, text) IS 'test comment';
"""

UNRELATED_FUNCTION_SQL = """\
--
-- Name: some_other_function(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION some_other_function()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    NULL;
END;
$$;
"""


class TestManifestLoader:
    """NEW-1: manifest file parsing."""

    def test_missing_manifest_file_returns_empty_dict(self, listener_module, tmp_path):
        """No manifest on disk -> fail-open, nothing to protect."""
        listener_module.SCHEMA_MANIFEST_FILE = str(tmp_path / "does-not-exist.toml")
        assert listener_module._load_schema_manifest() == {}

    def test_valid_manifest_parses_functions_section(self, listener_module, manifest_file):
        manifest_file(MANIFEST_MISSING_FUNCTION)
        manifest = listener_module._load_schema_manifest()
        assert manifest == {"functions": ["append_run_note(integer, text)"]}

    def test_malformed_toml_raises_schema_manifest_error(self, listener_module, manifest_file):
        """B-3 (SE run #804 QA review): a PRESENT-but-malformed manifest must
        fail CLOSED, not fail open. Unlike a genuinely absent manifest
        (which fails open -- nothing to protect yet), a manifest that exists
        but fails to parse must raise so the caller can veto the sync,
        rather than silently disabling every entry's protection."""
        manifest_file("[functions\npatterns = not valid toml {{{")
        with pytest.raises(listener_module.SchemaManifestError):
            listener_module._load_schema_manifest()

    def test_empty_manifest_file_returns_empty_dict(self, listener_module, manifest_file):
        manifest_file("")
        assert listener_module._load_schema_manifest() == {}

    def test_non_list_patterns_are_ignored(self, listener_module, manifest_file):
        manifest_file('[functions]\npatterns = "not-a-list"\n')
        manifest = listener_module._load_schema_manifest()
        assert manifest == {}

    def test_absent_manifest_fails_open_malformed_manifest_fails_closed(
        self, listener_module, manifest_file
    ):
        """Direct contrast test for B-3: absent file -> {} (fail open);
        present-but-broken file -> raises (fail closed). These are
        deliberately different outcomes for different conditions.

        The manifest_file fixture points SCHEMA_MANIFEST_FILE at a path with
        no file yet -- so before calling manifest_file(...) to write
        content, the file is genuinely absent at that same path."""
        assert listener_module._load_schema_manifest() == {}  # absent -> fail open

        manifest_file("not valid toml at all {{{")  # writes to the SAME path
        with pytest.raises(listener_module.SchemaManifestError):
            listener_module._load_schema_manifest()  # present-but-broken -> fail closed

    def test_multiple_sections_all_parsed(self, listener_module, manifest_file):
        manifest_file(
            '[functions]\npatterns = ["a(int)"]\n\n[tables]\npatterns = ["b"]\n'
        )
        manifest = listener_module._load_schema_manifest()
        assert manifest == {"functions": ["a(int)"], "tables": ["b"]}


class TestFunctionSignaturePresence:
    """Coverage for the header-matching helper used by the functions section."""

    def test_present_single_line_header(self, listener_module):
        sql = "CREATE OR REPLACE FUNCTION append_run_note(p_run_id integer, p_note text)\nRETURNS void"
        assert listener_module._function_signature_present(
            sql, "append_run_note(integer, text)"
        )

    def test_present_multiline_header(self, listener_module):
        sql = APPEND_RUN_NOTE_SQL
        assert listener_module._function_signature_present(
            sql, "append_run_note(integer, text)"
        )

    def test_absent_when_function_missing(self, listener_module):
        sql = UNRELATED_FUNCTION_SQL
        assert not listener_module._function_signature_present(
            sql, "append_run_note(integer, text)"
        )

    def test_case_insensitive_create_keyword(self, listener_module):
        sql = "create function append_run_note(p_run_id integer, p_note text)"
        assert listener_module._function_signature_present(
            sql, "append_run_note(integer, text)"
        )

    def test_unrecognizable_signature_falls_back_to_substring(self, listener_module):
        # Not a "name(args)" shape -- falls back to plain substring search.
        assert listener_module._function_signature_present("literal-text-present", "literal-text-present")
        assert not listener_module._function_signature_present("nothing here", "literal-text-present")


class TestFindMissingManifestObjects:
    def test_no_manifest_means_nothing_missing(self, listener_module, tmp_path):
        listener_module.SCHEMA_MANIFEST_FILE = str(tmp_path / "absent.toml")
        assert listener_module._find_missing_manifest_objects("anything") == []

    def test_present_object_is_not_reported_missing(self, listener_module, manifest_file):
        manifest_file(MANIFEST_MISSING_FUNCTION)
        sql = APPEND_RUN_NOTE_SQL + "\n" + UNRELATED_FUNCTION_SQL
        assert listener_module._find_missing_manifest_objects(sql) == []

    def test_absent_object_is_reported_missing(self, listener_module, manifest_file):
        manifest_file(MANIFEST_MISSING_FUNCTION)
        sql = UNRELATED_FUNCTION_SQL  # no append_run_note
        missing = listener_module._find_missing_manifest_objects(sql)
        assert missing == ["functions: append_run_note(integer, text)"]


class TestVetoAlertContract:
    """LSV-5/LSV-6: veto alert is distinct from notify_clawdbot and self-contained."""

    def test_veto_alert_never_routes_through_notify_clawdbot(self, listener_module, mock_agent_chat, monkeypatch):
        calls = []
        monkeypatch.setattr(
            listener_module, "notify_clawdbot", lambda msg: calls.append(msg)
        )
        listener_module._send_manifest_veto_alert(
            ["functions: append_run_note(integer, text)"], "CREATE", "some_table"
        )
        assert calls == []  # notify_clawdbot must never be invoked by the veto path
        agent_chat_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(agent_chat_calls) == 1

    def test_veto_alert_names_missing_objects_and_is_distinct_text(self, listener_module, mock_agent_chat):
        listener_module._send_manifest_veto_alert(
            ["functions: append_run_note(integer, text)"], "CREATE", "some_table"
        )
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(calls) == 1
        sender, message, recipients = calls[0]["params"]
        assert sender == listener_module._agent_chat_env["PGUSER"]
        assert message.startswith("[schema-sync]")
        assert "append_run_note(integer, text)" in message
        assert "REFUSED" in message
        # Distinct from the generic push/branch failure text.
        assert "push failed" not in message.lower()
        assert "diverged" not in message.lower()
        assert recipients == listener_module._alert_recipients(sender)

    def test_veto_alert_documents_sanctioned_removal_path(self, listener_module, mock_agent_chat):
        listener_module._send_manifest_veto_alert(
            ["functions: append_run_note(integer, text)"], "CREATE", "some_table"
        )
        calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        message = calls[0]["params"][1]
        assert "manifest-edit" in message.lower() or "manifest edit" in message.lower()

    def test_veto_alert_swallows_connect_failure(self, listener_module, monkeypatch):
        import psycopg2

        def boom(**kwargs):
            raise psycopg2.OperationalError("simulated agent_chat outage")

        monkeypatch.setattr(listener_module.psycopg2, "connect", boom)
        # Must not raise.
        listener_module._send_manifest_veto_alert(["functions: x(int)"], "CREATE", "t")

    def test_veto_alert_missing_pguser_does_not_raise(self, listener_module, monkeypatch):
        monkeypatch.setitem(listener_module._agent_chat_env, "PGUSER", "")
        listener_module._send_manifest_veto_alert(["functions: x(int)"], "CREATE", "t")


class TestEndToEndVeto:
    """LSV-1..LSV-4, LSV-7..LSV-9: full sync_schema_to_github() veto behavior."""

    def test_dump_removing_manifest_object_is_refused_and_reverted(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        """LSV-1: manifest object present before, absent in dump -> refused + reverted."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(MANIFEST_MISSING_FUNCTION)

        # Seed the committed schema.sql with the function present.
        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed with append_run_note"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)
        head_before = _clone_head(clone)
        remote_before = _remote_head(git_repos["origin"])

        # The dump would remove the function (clobbering re-dump scenario).
        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)

        ok, commit_hash = listener_module.sync_schema_to_github(
            "ALTER", "table", "public.work_queue"
        )

        assert ok is False
        assert commit_hash is None
        # No new commit was made.
        assert _clone_head(clone) == head_before
        assert _remote_head(git_repos["origin"]) == remote_before
        # schema.sql on disk was reverted to the pre-dump (committed) content,
        # not left dirty with the clobbered content.
        assert schema_file.read_text() == APPEND_RUN_NOTE_SQL
        status = subprocess.run(
            ["git", "-C", str(clone), "status", "--porcelain"],
            capture_output=True,
            text=True,
        )
        assert status.stdout.strip() == ""

    def test_veto_sends_exactly_one_alert_naming_the_object(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        """LSV-2: exactly one alert, naming the missing object."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(MANIFEST_MISSING_FUNCTION)

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed with append_run_note"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        listener_module.sync_schema_to_github("ALTER", "table", "public.work_queue")

        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        _, message, _ = message_calls[0]["params"]
        assert "append_run_note(integer, text)" in message

    def test_veto_releases_git_lock(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        """LSV-3: lock is not leaked on the veto's early return."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(MANIFEST_MISSING_FUNCTION)

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed with append_run_note"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        listener_module.sync_schema_to_github("ALTER", "table", "public.work_queue")

        assert not _lock_is_held(listener_module._git_lock_path)
        assert listener_module._git_lock_fd is None

    def test_veto_does_not_orphan_branch_state(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        """LSV-4: after a veto, clone remains on main (branch-safety invariant holds)."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(MANIFEST_MISSING_FUNCTION)

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed with append_run_note"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        listener_module.sync_schema_to_github("ALTER", "table", "public.work_queue")

        assert _current_branch(clone) == "main"

    def test_veto_all_or_nothing_multiple_missing_objects_reported_together(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        """LSV-7: multiple manifest violations in one dump are all named in a single refusal."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(
            '[functions]\n'
            'patterns = [\n'
            '  "append_run_note(integer, text)",\n'
            '  "some_other_manifest_fn(integer)",\n'
            ']\n'
        )

        schema_file = clone / "database" / "schema.sql"
        seed = APPEND_RUN_NOTE_SQL + "\nCREATE OR REPLACE FUNCTION some_other_manifest_fn(p integer)\nRETURNS void\nAS $$ BEGIN NULL; END; $$ LANGUAGE plpgsql;\n"
        schema_file.write_text(seed)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed with two manifest fns"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)
        head_before = _clone_head(clone)

        # Dump removes BOTH manifest functions.
        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        ok, commit_hash = listener_module.sync_schema_to_github(
            "ALTER", "table", "public.work_queue"
        )

        assert ok is False
        assert _clone_head(clone) == head_before
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        _, message, _ = message_calls[0]["params"]
        assert "append_run_note(integer, text)" in message
        assert "some_other_manifest_fn(integer)" in message

    def test_veto_check_precedes_git_status_short_circuit(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        """LSV-8: even when the dump happens to be byte-identical to a prior
        clobbered commit (so git status would report "no changes"), the
        manifest check still runs on every invocation because it reads the
        freshly dumped file directly rather than relying on git diff state.
        """
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(MANIFEST_MISSING_FUNCTION)

        # Seed committed schema.sql WITHOUT the function (already clobbered upstream).
        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(UNRELATED_FUNCTION_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "already clobbered upstream"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)
        head_before = _clone_head(clone)

        # New dump is identical to what's already committed (no git diff),
        # but still missing the manifest object -- veto must still fire.
        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        ok, commit_hash = listener_module.sync_schema_to_github(
            "ALTER", "table", "public.work_queue"
        )

        assert ok is False
        assert commit_hash is None
        assert _clone_head(clone) == head_before
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1


class TestFailClosedOnMalformedManifest:
    """B-3 (SE run #804 QA review): sync_schema_to_github() must fail CLOSED
    (refuse the sync, revert schema.sql, alert) when the manifest file
    EXISTS but is malformed -- not silently proceed as if no manifest
    existed. This is distinct from the LSV tests above, which cover a
    valid manifest whose OBJECT is missing from the dump; here the manifest
    ITSELF is broken."""

    def test_malformed_manifest_refuses_sync_and_reverts(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file("[functions\npatterns = not valid toml {{{")

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)
        head_before = _clone_head(clone)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        ok, commit_hash = listener_module.sync_schema_to_github(
            "ALTER", "table", "public.work_queue"
        )

        assert ok is False
        assert commit_hash is None
        # No new commit; schema.sql on disk reverted to committed content,
        # not left dirty with the (also-clobbered) dump content.
        assert _clone_head(clone) == head_before
        assert schema_file.read_text() == APPEND_RUN_NOTE_SQL
        status = subprocess.run(
            ["git", "-C", str(clone), "status", "--porcelain"],
            capture_output=True,
            text=True,
        )
        assert status.stdout.strip() == ""

    def test_malformed_manifest_sends_alert_mentioning_parse_error(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file("[functions\npatterns = not valid toml {{{")

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        listener_module.sync_schema_to_github("ALTER", "table", "public.work_queue")

        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 1
        _, message, _ = message_calls[0]["params"]
        assert "REFUSED" in message
        assert "manifest parse error" in message.lower()

    def test_malformed_manifest_releases_git_lock(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file("not valid toml at all {{{")

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)
        listener_module.sync_schema_to_github("ALTER", "table", "public.work_queue")

        assert not _lock_is_held(listener_module._git_lock_path)
        assert listener_module._git_lock_fd is None


class TestNegativeCaseNonManifestObjectsProceed:
    """LSV-9 (mandatory negative case): removing a non-manifest object must
    proceed and commit normally -- the veto is targeted, not a general
    anti-drop lock that would freeze legitimate schema evolution."""

    def test_dump_removing_non_manifest_object_commits_and_pushes_normally(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, manifest_file
    ):
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        manifest_file(MANIFEST_MISSING_FUNCTION)

        # Seed committed schema.sql with BOTH the manifest function and an
        # unrelated function.
        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL + "\n" + UNRELATED_FUNCTION_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed with both functions"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        # New dump keeps the manifest function but legitimately drops the
        # unrelated (non-manifest) function -- e.g. it was DROP FUNCTION'd
        # intentionally on the live DB.
        _set_schema_content(listener_module, APPEND_RUN_NOTE_SQL)

        ok, commit_hash = listener_module.sync_schema_to_github(
            "DROP", "function", "public.some_other_function"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        assert _remote_head(git_repos["origin"]) == _clone_head(clone)
        # schema.sql on disk reflects the new dump (function legitimately gone).
        assert schema_file.read_text() == APPEND_RUN_NOTE_SQL
        # No veto alert was sent.
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 0

    def test_no_manifest_file_at_all_never_vetoes(
        self, listener_module, git_repos, mock_pgschema_dump, mock_agent_chat, tmp_path
    ):
        """When no manifest exists, any dump content (even one that would drop
        append_run_note) proceeds -- the manifest is opt-in per-repo state,
        not an implicit hardcoded protection list."""
        clone = Path(git_repos["clone"])
        listener_module.NOVA_MIND_DIR = str(clone)
        listener_module.SCHEMA_FILE = str(clone / "database" / "schema.sql")
        listener_module.SCHEMA_MANIFEST_FILE = str(tmp_path / "absent-manifest.toml")

        schema_file = clone / "database" / "schema.sql"
        schema_file.write_text(APPEND_RUN_NOTE_SQL)
        subprocess.run(["git", "-C", str(clone), "add", "database/schema.sql"], check=True)
        subprocess.run(
            ["git", "-C", str(clone), "commit", "-m", "seed"],
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "-C", str(clone), "push", "origin", "main"], check=True, capture_output=True)

        _set_schema_content(listener_module, UNRELATED_FUNCTION_SQL)  # drops append_run_note
        ok, commit_hash = listener_module.sync_schema_to_github(
            "ALTER", "table", "public.work_queue"
        )

        assert ok is True
        assert commit_hash == _clone_head(clone)
        message_calls = [c for c in mock_agent_chat if "send_agent_message" in c.get("query", "")]
        assert len(message_calls) == 0


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
