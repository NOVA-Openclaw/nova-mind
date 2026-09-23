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
    filtered, count = strip_destructive(plan)
    assert count == 1
    assert len(filtered["groups"][0]["steps"]) == 1
    assert filtered["groups"][0]["steps"][0]["operation"] == "create"


def test_strips_drop_column():
    plan = _plan([
        {"sql": "ALTER TABLE public.t DROP COLUMN old_col;", "operation": "drop", "type": "column", "path": "public.t.old_col"},
        {"sql": "ALTER TABLE public.t ADD COLUMN new_col int;", "operation": "alter", "type": "column", "path": "public.t.new_col"},
    ])
    filtered, count = strip_destructive(plan)
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
    filtered, count = strip_destructive(plan)
    assert count == 4
    assert len(filtered["groups"][0]["steps"]) == 1


def test_preserves_non_drop_operations():
    plan = _plan([
        {"sql": "CREATE TABLE public.t (id int);", "operation": "create", "type": "table", "path": "public.t"},
        {"sql": "ALTER TABLE public.t ADD COLUMN c int;", "operation": "alter", "type": "column", "path": "public.t.c"},
        {"sql": "CREATE INDEX idx_t ON public.t (c);", "operation": "create", "type": "index", "path": "public.idx_t"},
        {"sql": "COMMENT ON TABLE public.t IS 'x';", "operation": "create", "type": "comment", "path": "public.t"},
    ])
    filtered, count = strip_destructive(plan)
    assert count == 0
    assert len(filtered["groups"][0]["steps"]) == 4


def test_empty_plan_returns_empty():
    plan = _plan([])
    filtered, count = strip_destructive(plan)
    assert count == 0
    assert filtered["groups"] == []


def test_null_groups_normalized():
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
        "groups": None,
    }
    filtered, count = strip_destructive(plan)
    assert count == 0
    assert filtered["groups"] == []


def test_missing_groups_normalized():
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "test"},
    }
    filtered, count = strip_destructive(plan)
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


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
