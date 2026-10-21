#!/usr/bin/env python3
"""Unit tests for database/strip_destructive.py.

Run with: python3 -m pytest tests/test_strip_destructive.py
"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "database"))

from strip_destructive import strip_destructive


def _plan(steps):
    return {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
        "groups": [{"steps": steps}],
    }


def test_strips_drop_table():
    plan = _plan([
        {"sql": "DROP TABLE public.old_table;", "operation": "drop", "type": "table", "path": "public.old_table"},
        {"sql": "CREATE TABLE public.new_table (id int);", "operation": "create", "type": "table", "path": "public.new_table"},
    ])
    filtered, count, excluded = strip_destructive(plan)
    assert count == 1
    assert len(filtered["groups"][0]["steps"]) == 1
    assert filtered["groups"][0]["steps"][0]["operation"] == "create"


def test_strips_drop_column():
    plan = _plan([
        {"sql": "ALTER TABLE public.t DROP COLUMN old_col;", "operation": "drop", "type": "column", "path": "public.t.old_col"},
        {"sql": "ALTER TABLE public.t ADD COLUMN new_col int;", "operation": "alter", "type": "column", "path": "public.t.new_col"},
    ])
    filtered, count, excluded = strip_destructive(plan)
    assert count == 1
    assert len(filtered["groups"][0]["steps"]) == 1
    assert filtered["groups"][0]["steps"][0]["operation"] == "alter"


def test_strips_drop_index_constraint_function_trigger():
    plan = _plan([
        {"sql": "DROP INDEX public.idx_x;", "operation": "drop", "type": "index", "path": "public.idx_x"},
        {"sql": "ALTER TABLE public.t DROP CONSTRAINT c;", "operation": "drop", "type": "constraint", "path": "public.t.c"},
        {"sql": "DROP FUNCTION public.f();", "operation": "drop", "type": "function", "path": "public.f"},
        {"sql": "DROP TRIGGER tr ON public.t;", "operation": "drop", "type": "trigger", "path": "public.t.tr"},
        {"sql": "CREATE TABLE public.t (id int);", "operation": "create", "type": "table", "path": "public.t"},
    ])
    filtered, count, excluded = strip_destructive(plan)
    assert count == 4
    assert len(filtered["groups"][0]["steps"]) == 1


def test_preserves_non_drop_operations():
    plan = _plan([
        {"sql": "CREATE TABLE public.t (id int);", "operation": "create", "type": "table", "path": "public.t"},
        {"sql": "ALTER TABLE public.t ADD COLUMN c int;", "operation": "alter", "type": "column", "path": "public.t.c"},
        {"sql": "CREATE INDEX idx_t ON public.t (c);", "operation": "create", "type": "index", "path": "public.idx_t"},
        {"sql": "COMMENT ON TABLE public.t IS 'x';", "operation": "create", "type": "comment", "path": "public.t"},
    ])
    filtered, count, excluded = strip_destructive(plan)
    assert count == 0
    assert len(filtered["groups"][0]["steps"]) == 4


def test_empty_plan_returns_empty():
    plan = _plan([])
    filtered, count, excluded = strip_destructive(plan)
    assert count == 0
    assert filtered["groups"] == []


def test_null_groups_normalized():
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
        "groups": None,
    }
    filtered, count, excluded = strip_destructive(plan)
    assert count == 0
    assert filtered["groups"] == []


def test_missing_groups_normalized():
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
    }
    filtered, count, excluded = strip_destructive(plan)
    assert count == 0
    assert filtered["groups"] == []


def test_invalid_plan_version_raises():
    plan = {
        "version": "2.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
    }
    with pytest.raises(ValueError):
        strip_destructive(plan)


def test_malformed_groups_raises():
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
        "groups": "not-an-array",
    }
    with pytest.raises(ValueError):
        strip_destructive(plan)


def test_cli_reports_count_on_stderr(tmp_path, capsys):
    from strip_destructive import main

    plan_path = tmp_path / "plan.json"
    out_path = tmp_path / "out.json"
    plan_path.write_text(json.dumps(_plan([
        {"sql": "DROP TABLE public.t;", "operation": "drop", "type": "table", "path": "public.t"},
        {"sql": "CREATE TABLE public.t (id int);", "operation": "create", "type": "table", "path": "public.t"},
    ])))

    rc = main(["--plan", str(plan_path), "--output", str(out_path)])
    assert rc == 0
    captured = capsys.readouterr()
    assert captured.err.strip() == "1"

    out = json.loads(out_path.read_text())
    assert len(out["groups"][0]["steps"]) == 1


def test_adp_revoke_and_for_role_other_removed():
    from plan_check_superuser import _StubResolver

    plan = _plan([
        {"sql": "ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public REVOKE SELECT ON TABLES FROM coder;", "operation": "drop", "type": "default_privilege", "path": "default_privileges.nova.TABLES.coder"},
        {"sql": "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO coder;", "operation": "create", "type": "default_privilege", "path": "default_privileges.postgres.TABLES.coder"},
        {"sql": "ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO coder;", "operation": "create", "type": "default_privilege", "path": "default_privileges.nova.TABLES.coder"},
    ])
    resolver = _StubResolver([])
    filtered, count, excluded = strip_destructive(plan, db_user="nova", resolver=resolver)
    assert count == 2
    paths = [s["path"] for s in filtered["groups"][0]["steps"]]
    assert "default_privileges.nova.TABLES.coder" in paths
    assert "default_privileges.postgres.TABLES.coder" not in paths
    assert "drop" not in excluded
    assert len(excluded["default_privileges"]) == 2


def test_non_owned_drop_and_create_replace_skipped():
    from plan_check_superuser import _StubResolver

    plan = _plan([
        {"sql": "DROP FUNCTION IF EXISTS public.f();", "operation": "drop", "type": "function", "path": "public.f"},
        {"sql": "CREATE OR REPLACE FUNCTION public.f() RETURNS int AS $$ SELECT 1; $$ LANGUAGE sql;", "operation": "alter", "type": "function", "path": "public.f"},
        {"sql": "CREATE TABLE public.new_table (id int);", "operation": "create", "type": "table", "path": "public.new_table"},
        {"sql": "COMMENT ON TABLE public.owned IS 'x';", "operation": "create", "type": "table.comment", "path": "public.owned"},
    ])
    resolver = _StubResolver([
        {"name": "f", "schema": "public", "kind": "function", "owner": "postgres"},
        {"name": "owned", "schema": "public", "kind": "table", "owner": "nova"},
    ])
    filtered, count, excluded = strip_destructive(plan, db_user="nova", resolver=resolver)
    assert count == 2
    paths = [s["path"] for s in filtered["groups"][0]["steps"]]
    assert "public.f" not in paths
    assert "public.new_table" in paths
    assert "public.owned" in paths
    assert "nonowned:public.f" in excluded


def test_non_owned_grant_privilege_step_skipped():
    from plan_check_superuser import _StubResolver

    plan = _plan([
        {"sql": "GRANT SELECT ON TABLE public.t TO nova;", "operation": "create", "type": "privilege", "path": "privileges.TABLE.public.t.nova"},
    ])
    resolver = _StubResolver([
        {"name": "public.t", "schema": "public", "kind": "table", "owner": "postgres"},
    ])
    filtered, count, excluded = strip_destructive(plan, db_user="nova", resolver=resolver)
    assert count == 1
    assert not any(g["steps"] for g in filtered["groups"])
    assert "nonowned:privileges.TABLE.public.t.nova" in excluded


def test_peer_shadowed_ignore_still_works_with_db_user():
    from plan_check_superuser import _StubResolver

    plan = _plan([
        {"sql": "ALTER TABLE public.ignored_table ADD COLUMN c int;", "operation": "alter", "type": "table.column", "path": "public.ignored_table.c"},
        {"sql": "CREATE TABLE public.owned (id int);", "operation": "create", "type": "table", "path": "public.owned"},
    ])
    resolver = _StubResolver([
        {"name": "ignored_table", "schema": "public", "kind": "table", "owner": "nova"},
    ])
    filtered, count, excluded = strip_destructive(
        plan, ignored_objects=["ignored_table"], db_user="nova", resolver=resolver
    )
    paths = [s["path"] for s in filtered["groups"][0]["steps"]]
    assert "public.ignored_table.c" not in paths
    assert "public.owned" in paths
    assert "ignored_table" in excluded


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
