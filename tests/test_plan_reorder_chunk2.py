"""Tests for database/plan_reorder.py (chunk 2: regression fixtures + group restructuring).

Derived from /home/nova/.openclaw/workspace/evals/se709/test-case-design-v2.md.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from database.plan_reorder import (
    PlanReorderError,
    analyze_statement,
    load_plan,
    reorder_plan,
    validate_plan_invariants,
)


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


# ---------------------------------------------------------------------------
# Fix loop 3: view -> column dependency edges (nova-mind#597 staging retest 2)
# ---------------------------------------------------------------------------


def test_tc40_create_view_join_alias_resolves_to_column():
    """TC-40: view with JOIN aliases records column refs on real tables."""
    analysis = analyze_statement(
        "CREATE VIEW v_joined AS SELECT ef.assertion_intent "
        "FROM entity_facts ef JOIN entity_fact_sources efs ON efs.fact_id = ef.id;"
    )
    assert analysis["defines"] == {"table:v_joined"}
    assert "column:entity_facts.assertion_intent" in analysis["refs"]
    assert "column:entity_fact_sources.fact_id" in analysis["refs"]
    # Alias names must not leak into the dependency graph as phony objects.
    assert "table:ef" not in analysis["refs"]
    assert "column:ef.assertion_intent" not in analysis["refs"]


def test_tc41_regression_597_staging_retest2_view_after_add_column():
    """TC-41: #597 staging retest 2 fixture reorders view after ADD COLUMN."""
    plan = load_plan(FIXTURES / "pgschema-debug-plan-r2.json")
    out = reorder_plan(plan)

    def _find(sql_prefix):
        for gidx, group in enumerate(out["groups"]):
            for sidx, step in enumerate(group["steps"]):
                if step["sql"].startswith(sql_prefix):
                    return (gidx, sidx, step["sql"])
        raise AssertionError(f"step not found: {sql_prefix!r}")

    add_col = _find("ALTER TABLE entity_facts ADD COLUMN assertion_intent")
    view = _find("CREATE OR REPLACE VIEW v_fact_grades")
    # The view references ef.assertion_intent, so it must run after the ALTER.
    assert view[:2] > add_col[:2], (
        f"v_fact_grades {view[:2]} must follow ADD COLUMN assertion_intent {add_col[:2]}"
    )


def test_tc42_validate_invariants_catches_stranded_view():
    """TC-42: invariant validator flags the staging retest 2 defective plan."""
    plan = load_plan(
        Path("/home/nova/.openclaw/workspace/se-runs/se709/staging-fail2")
        / "pgschema-debug-plan-r2-reordered.json"
    )
    with pytest.raises(PlanReorderError) as exc_info:
        validate_plan_invariants(plan)
    assert "Invariant violation" in exc_info.value.message
    # The violation must involve v_fact_grades referencing a column.
    sqls = {s["sql"] for s in exc_info.value.statements}
    assert any("v_fact_grades" in sql for sql in sqls)


def test_tc43_validate_invariants_accepts_fixed_reorder():
    """TC-43: invariant validator accepts the corrected reorder of the r2 fixture."""
    plan = load_plan(FIXTURES / "pgschema-debug-plan-r2.json")
    out = reorder_plan(plan)
    validate_plan_invariants(out)  # must not raise
    # Also assert the concrete ordering: the view must follow the ADD COLUMN.
    # This makes TC-43 fail if the analyzer is reverted, even though the
    # validator extension alone cannot catch the defect with a broken analyzer.
    def _find(sql_prefix):
        for gidx, group in enumerate(out["groups"]):
            for sidx, step in enumerate(group["steps"]):
                if step["sql"].startswith(sql_prefix):
                    return (gidx, sidx)
        raise AssertionError(f"step not found: {sql_prefix!r}")

    add_col = _find("ALTER TABLE entity_facts ADD COLUMN assertion_intent")
    view = _find("CREATE OR REPLACE VIEW v_fact_grades")
    assert view > add_col, (
        f"v_fact_grades {view} must follow ADD COLUMN assertion_intent {add_col}"
    )
