"""Tests for filter_shadowed_grants.py non-owner grant skipping (#1231 step 5)."""

import io
import sys
from unittest.mock import patch

import pytest

import database.filter_shadowed_grants as fsg


@pytest.fixture
def captured():
    """Capture stdout/stderr and reload the module-level lookup functions."""
    # Ensure fresh monkeypatch state for each test.
    fsg._load_owner_map = fsg._load_owner_map
    fsg._is_superuser = fsg._is_superuser
    return None


def _run_filter(monkeypatch, stdin, owners, is_super, dbname="nova_memory", db_user="nova", shadowed_names=""):
    """Run filter_shadowed_grants.main with mocked catalog lookups."""
    monkeypatch.setattr(fsg, "_load_owner_map", lambda _dbname: owners)
    monkeypatch.setattr(fsg, "_is_superuser", lambda _dbname, _user: is_super)

    old_stdin, old_stdout, old_stderr = sys.stdin, sys.stdout, sys.stderr
    sys.stdin = io.StringIO(stdin)
    out, err = io.StringIO(), io.StringIO()
    sys.stdout, sys.stderr = out, err
    try:
        args = ["--dbname", dbname, "--db-user", db_user]
        if shadowed_names:
            args += ["--shadowed-names", shadowed_names]
        rc = fsg.main(args)
    finally:
        sys.stdin, sys.stdout, sys.stderr = old_stdin, old_stdout, old_stderr
    return rc, out.getvalue(), err.getvalue()


def test_non_super_skips_non_owned_table(monkeypatch, captured):
    owners = {("public", "t"): "other"}
    rc, out, err = _run_filter(
        monkeypatch,
        "GRANT SELECT ON TABLE t TO role1;\n",
        owners,
        is_super=False,
    )
    assert rc == 0
    assert "GRANT SELECT ON TABLE t TO role1" not in out
    assert "SKIPPED: 1 grant/revoke statement(s) for non-owned object 'public.t' (owner 'other')" in err
    assert "Kept 0 grant/revoke statement(s)" in err


def test_non_super_skips_non_owned_view(monkeypatch, captured):
    owners = {("public", "v_current_stateful_facts"): "newhart"}
    stdin = "GRANT SELECT ON TABLE v_current_stateful_facts TO argus;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert out.strip() == ""
    assert "newhart" in err
    assert "Kept 0" in err


def test_non_super_skips_non_owned_sequence(monkeypatch, captured):
    owners = {("public", "t_id_seq"): "other"}
    rc, out, err = _run_filter(
        monkeypatch,
        "GRANT USAGE ON SEQUENCE t_id_seq TO role1;\n",
        owners,
        is_super=False,
    )
    assert rc == 0
    assert out.strip() == ""
    assert "non-owned object 'public.t_id_seq'" in err


def test_non_super_skips_non_owned_function(monkeypatch, captured):
    owners = {("public", "current_agent_id()"): "other"}
    rc, out, err = _run_filter(
        monkeypatch,
        "GRANT EXECUTE ON FUNCTION current_agent_id() TO role1;\n",
        owners,
        is_super=False,
    )
    assert rc == 0
    assert out.strip() == ""
    assert "non-owned object 'public.current_agent_id()'" in err


def test_super_keeps_non_owned_object(monkeypatch, captured):
    owners = {("public", "t"): "other"}
    rc, out, err = _run_filter(
        monkeypatch,
        "GRANT SELECT ON TABLE t TO role1;\n",
        owners,
        is_super=True,
    )
    assert rc == 0
    assert "GRANT SELECT ON TABLE t TO role1" in out
    assert "SKIPPED" not in err
    assert "Kept 1" in err


def test_non_super_keeps_owned_object(monkeypatch, captured):
    owners = {("public", "t"): "nova"}
    rc, out, err = _run_filter(
        monkeypatch,
        "GRANT SELECT ON TABLE t TO role1;\n",
        owners,
        is_super=False,
    )
    assert rc == 0
    assert "GRANT SELECT ON TABLE t TO role1" in out
    assert "SKIPPED" not in err
    assert "Kept 1" in err


def test_non_super_skips_only_non_owned_target(monkeypatch, captured):
    owners = {("public", "owned"): "nova", ("public", "other"): "iris"}
    stdin = (
        "GRANT SELECT ON TABLE owned TO role1;\n"
        "GRANT SELECT ON TABLE other TO role1;\n"
    )
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert "GRANT SELECT ON TABLE owned TO role1" in out
    assert "GRANT SELECT ON TABLE other TO role1" not in out
    assert "iris" in err
    assert "Kept 1" in err


def test_shadowed_still_skipped_before_non_owned_check(monkeypatch, captured):
    owners = {("public", "ai_models"): "other"}
    stdin = (
        "GRANT SELECT ON TABLE ai_models TO role1;\n"
        "GRANT SELECT ON TABLE other TO role1;\n"
    )
    rc, out, err = _run_filter(
        monkeypatch,
        stdin,
        owners,
        is_super=False,
        db_user="nova",
        shadowed_names="ai_models",
    )
    assert rc == 0
    assert "ai_models" not in out
    assert "GRANT SELECT ON TABLE other TO role1" in out
    assert "peer-shadowed object 'ai_models'" in err
    assert "Kept 1" in err


def test_owner_revoke_still_skipped_before_non_owned_check(monkeypatch, captured):
    owners = {("public", "t"): "nova"}
    stdin = "REVOKE SELECT ON TABLE t FROM nova;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert out.strip() == ""
    assert "owner/DB_USER REVOKE" in err
    assert "Kept 0" in err


def test_named_role_revoke_on_table_is_dropped(monkeypatch, captured):
    """Stale REVOKE from a former owner is dropped (#759)."""
    owners = {("public", "t"): "nova"}
    stdin = "REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE t FROM newhart;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert out.strip() == ""
    assert "named-role REVOKE" in err
    assert "newhart" in err
    assert "Kept 0" in err


def test_named_role_revoke_on_sequence_is_dropped(monkeypatch, captured):
    owners = {("public", "t_id_seq"): "nova"}
    stdin = "REVOKE USAGE, SELECT, UPDATE ON SEQUENCE t_id_seq FROM newhart;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert out.strip() == ""
    assert "named-role REVOKE" in err
    assert "Kept 0" in err


def test_revoke_from_public_on_table_is_kept(monkeypatch, captured):
    """REVOKE ... FROM PUBLIC is intentionally preserved."""
    owners = {("public", "t"): "nova"}
    stdin = "REVOKE INSERT, UPDATE ON TABLE t FROM PUBLIC;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert "REVOKE INSERT, UPDATE ON TABLE t FROM PUBLIC" in out
    assert "SKIPPED" not in err
    assert "Kept 1" in err


def test_allowlisted_named_role_revoke_is_kept(monkeypatch, captured):
    """An intentional restrictive revoke in the allowlist passes through."""
    owners = {("public", "t"): "nova"}
    allow = (
        "table",
        "public",
        "t",
        frozenset(["newhart"]),
        frozenset(["select", "update"]),
        "documented intentional denylist in #381",
    )
    monkeypatch.setattr(fsg, "_INTENTIONAL_REVOKE_ALLOWLIST", [allow])
    stdin = "REVOKE SELECT, UPDATE ON TABLE t FROM newhart;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert "REVOKE SELECT, UPDATE ON TABLE t FROM newhart" in out
    assert "SKIPPED" not in err
    assert "Kept 1" in err


def test_allowlist_does_not_cover_unlisted_privilege(monkeypatch, captured):
    """A statement with both allowlisted and unlisted privileges is dropped."""
    owners = {("public", "t"): "nova"}
    allow = (
        "table",
        "public",
        "t",
        frozenset(["newhart"]),
        frozenset(["select"]),
        "documented intentional denylist in #381",
    )
    monkeypatch.setattr(fsg, "_INTENTIONAL_REVOKE_ALLOWLIST", [allow])
    stdin = "REVOKE SELECT, DELETE ON TABLE t FROM newhart;\n"
    rc, out, err = _run_filter(monkeypatch, stdin, owners, is_super=False)
    assert rc == 0
    assert out.strip() == ""
    assert "named-role REVOKE" in err
    assert "Kept 0" in err
