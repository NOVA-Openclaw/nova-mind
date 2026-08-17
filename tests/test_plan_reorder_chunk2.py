"""Tests for database/plan_reorder.py (chunk 2: regression fixtures + group restructuring).

Derived from /home/nova/.openclaw/workspace/evals/se709/test-case-design-v2.md.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from database.plan_reorder import load_plan, reorder_plan


FIXTURES = Path(__file__).parent / "fixtures" / "plan_reorder"


# ---------------------------------------------------------------------------
# Regression fixtures (Section 1)
# ---------------------------------------------------------------------------


def test_tc01_regression_597_ordering():
    """TC-1: #597 mutability_class group reorders so ALTER TABLE precedes dependents."""
    plan = load_plan(FIXTURES / "plan_597.json")
    out = reorder_plan(plan)
    assert len(out["groups"]) == 1
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]

    # Expected safe order from v2 doc: type, ALTER TABLE, function, view, view.
    assert sqls[0] == "CREATE TYPE mutability_class_enum AS ENUM ('slow_changing', 'fast_changing');"
    assert "ADD COLUMN mutability_class" in sqls[1]
    assert "CREATE FUNCTION get_strictest_mutability" in sqls[2]
    assert "v_current_stateful_facts" in sqls[3]
    assert "v_fact_grades" in sqls[4]


def test_tc02_regression_447_grant_before_add_column():
    """TC-2: #447 ADD COLUMN must precede GRANT referencing that column."""
    plan = load_plan(FIXTURES / "plan_447.json")
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "ALTER TABLE motivation_d100 ADD COLUMN reserved boolean DEFAULT false NOT NULL;",
        "GRANT UPDATE (reserved) ON TABLE motivation_d100 TO some_role;",
    ]


def test_tc03_regression_392_fixture_exists():
    """TC-3: broken schema.sql fixture exists for the CI negative control."""
    schema = (FIXTURES / "schema_392.sql").read_text()
    assert "CREATE VIEW v_portfolio_allocation" in schema
    assert "CREATE TABLE positions" in schema
    # The view text appears before the table text, producing the known fault.
    assert schema.index("CREATE VIEW v_portfolio_allocation") < schema.index("CREATE TABLE positions")


# ---------------------------------------------------------------------------
# Group restructuring rules (Section 5)
# ---------------------------------------------------------------------------


def _make_plan(steps: list[dict]) -> dict:
    return {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "test"},
        "groups": [{"steps": steps}],
    }


def _step(sql: str, **extra) -> dict:
    return {"sql": sql, "type": "table", "operation": "create", "path": "public.x", **extra}


def test_tc35_directive_bearing_step_isolated():
    """TC-35: directive-bearing synthetic wait step stays in its own group."""
    plan = _make_plan([
        _step("CREATE TABLE a (id int);"),
        {
            "sql": "SELECT pg_sleep(0);",
            "type": "directive",
            "operation": "wait",
            "path": "public.a",
            "directive": {"type": "wait", "message": "Creating index..."},
        },
        _step("CREATE TABLE b (id int);"),
    ])
    out = reorder_plan(plan)
    group_types = [
        [s.get("type") for s in g["steps"]]
        for g in out["groups"]
    ]
    # Directive step must not be merged into adjacent transactional groups.
    assert any(g == ["directive"] for g in group_types)


def test_tc36_non_transactional_relative_position_preserved():
    """TC-36: CREATE INDEX CONCURRENTLY keeps its relative group position."""
    plan = _make_plan([
        _step("CREATE TABLE a (id int);"),
        {
            "sql": "CREATE INDEX CONCURRENTLY idx_a ON a (id);",
            "type": "index",
            "operation": "create",
            "path": "public.idx_a",
        },
        _step("CREATE TABLE b (id int);"),
    ])
    out = reorder_plan(plan)
    sqls = []
    for g in out["groups"]:
        for s in g["steps"]:
            sqls.append(s["sql"])
    # Without dependency reason to move it, concurrent index stays between the two tables.
    assert sqls.index("CREATE INDEX CONCURRENTLY idx_a ON a (id);") == 1


def test_tc37_cross_group_dependency_restructures():
    """TC-37: dependency across original groups restructures while respecting isolation."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "test"},
        "groups": [
            {"steps": [_step("CREATE VIEW v_x AS SELECT * FROM t1;", type="view", operation="create", path="public.v_x")]},
            {"steps": [_step("CREATE TABLE t1 (id int);", type="table", operation="create", path="public.t1")]},
        ],
    }
    out = reorder_plan(plan)
    sqls = [s["sql"] for g in out["groups"] for s in g["steps"]]
    assert sqls.index("CREATE TABLE t1 (id int);") < sqls.index("CREATE VIEW v_x AS SELECT * FROM t1;")


def test_tc38_directive_free_groups_merged_atomically():
    """TC-38: directive-free groups with valid total order merge into one group."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "test"},
        "groups": [
            {"steps": [_step("CREATE TABLE t1 (id int);")]},
            {"steps": [_step("CREATE VIEW v1 AS SELECT * FROM t1;", type="view", operation="create", path="public.v1")]},
        ],
    }
    out = reorder_plan(plan)
    assert len(out["groups"]) == 1
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls[0] == "CREATE TABLE t1 (id int);"
    assert sqls[1] == "CREATE VIEW v1 AS SELECT * FROM t1;"


def test_tc39_drop_ordering_across_groups():
    """TC-39: reverse dependency ordering applied consistently across groups."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "test"},
        "groups": [
            {"steps": [
                _step("DROP TABLE foo;", type="table", operation="drop", path="public.foo"),
                _step("CREATE VIEW v_foo AS SELECT * FROM foo;", type="view", operation="create", path="public.v_foo"),
            ]},
            {"steps": [
                _step("DROP VIEW v_foo;", type="view", operation="drop", path="public.v_foo"),
            ]},
        ],
    }
    out = reorder_plan(plan)
    sqls = [s["sql"] for g in out["groups"] for s in g["steps"]]
    assert sqls.index("DROP VIEW v_foo;") < sqls.index("DROP TABLE foo;")
