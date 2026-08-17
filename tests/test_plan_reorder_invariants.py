"""Global dependency-order invariants for reordered plans (nova-mind#597 retry).

The key invariant: for every statement, all objects it depends on must be
created/defined by statements that appear earlier in the flattened group/step
order.  This is the test the original suite was missing; it would have caught
the staging failure where COMMENT ON FUNCTION / GRANT EXECUTE ON FUNCTION
stayed in group 0 while their CREATE FUNCTION moved to group 3.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from database.plan_reorder import (
    PlanReorderError,
    load_plan,
    reorder_plan,
    validate_plan_invariants,
)


FIXTURES_DIR = Path(__file__).parent / "fixtures" / "plan_reorder"
STAGING_PLAN = Path(
    "/home/nova/.openclaw/workspace/se-runs/se709/staging-fail1/pgschema-debug-plan.json"
)


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


def test_invariant_holds_for_simple_dependency():
    """A dependent statement appears after its prerequisite."""
    plan = _make_plan([
        _step("CREATE TABLE foo (id int);"),
        _step("CREATE INDEX idx_foo ON foo (id);", type="table.index", operation="create", path="public.foo.idx_foo"),
    ])
    out = reorder_plan(plan)
    validate_plan_invariants(out)


def test_invariant_holds_for_comment_grant_followers():
    """COMMENT/GRANT follow the object they reference."""
    plan = _make_plan([
        _step("COMMENT ON TABLE foo IS 'docs';", type="comment", operation="create", path="public.foo"),
        _step("GRANT SELECT ON TABLE foo TO some_role;", type="privilege", operation="grant", path="public.foo"),
        _step("CREATE TABLE foo (id int);"),
    ])
    out = reorder_plan(plan)
    validate_plan_invariants(out)


def test_invariant_fails_when_defect_reintroduced():
    """If metadata dependents are not wired to their CREATE, invariant fails."""
    plan = _make_plan([
        _step("COMMENT ON TABLE foo IS 'docs';", type="comment", operation="create", path="public.foo"),
        _step("CREATE TABLE foo (id int);"),
    ])
    # Simulate the defective output: COMMENT comes before CREATE.
    defective = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "test"},
        "groups": [
            {"steps": [plan["groups"][0]["steps"][0]]},
            {"steps": [plan["groups"][0]["steps"][1]]},
        ],
    }
    with pytest.raises(PlanReorderError):
        validate_plan_invariants(defective)


@pytest.mark.parametrize(
    "fixture_name",
    [
        "plan_597.json",
        "plan_447.json",
    ],
)
def test_invariant_holds_for_existing_regression_fixtures(fixture_name):
    """All existing regression fixtures satisfy the dependency invariant."""
    fixture = FIXTURES_DIR / fixture_name
    if not fixture.exists():
        pytest.skip(f"fixture {fixture_name} not present")
    plan = load_plan(fixture)
    out = reorder_plan(plan)
    validate_plan_invariants(out)


def test_invariant_holds_for_real_staging_plan():
    """The actual captured SE #709 staging plan satisfies the invariant.

    This is the full-plan smoke test against the real artifact.  It would have
    failed with the original bug because COMMENT ON FUNCTION and the 12 GRANT
    EXECUTE ON FUNCTION statements remained in group 0 while the CREATE FUNCTION
    moved to group 3.
    """
    if not STAGING_PLAN.exists():
        pytest.skip("staging plan fixture not present")
    plan = load_plan(STAGING_PLAN)
    out = reorder_plan(plan)
    validate_plan_invariants(out)

    # Additional explicit check for the SE #709 defect: every metadata
    # statement referencing get_strictest_mutability must follow its CREATE.
    create_location = None
    metadata_locations = []
    create_prefix = "CREATE OR REPLACE FUNCTION get_strictest_mutability("
    comment_prefix = "COMMENT ON FUNCTION get_strictest_mutability("
    grant_prefix = "GRANT EXECUTE ON FUNCTION get_strictest_mutability("

    def _flat_index(gidx: int, sidx: int) -> int:
        return sum(len(g["steps"]) for g in out["groups"][:gidx]) + sidx

    for gidx, group in enumerate(out["groups"]):
        for sidx, step in enumerate(group["steps"]):
            sql = step["sql"]
            if sql.startswith(create_prefix):
                create_location = _flat_index(gidx, sidx)
            elif sql.startswith(comment_prefix) or sql.startswith(grant_prefix):
                metadata_locations.append(_flat_index(gidx, sidx))

    assert create_location is not None, "CREATE FUNCTION get_strictest_mutability not found"
    for loc in metadata_locations:
        assert loc > create_location, (
            f"metadata statement at flat index {loc} does not follow "
            f"CREATE FUNCTION at flat index {create_location}"
        )


R2_PLAN = FIXTURES_DIR / "pgschema-debug-plan-r2.json"


def test_invariant_holds_for_r2_retest_plan_and_view_follows_add_column():
    """SE #709 retest r2 artifact: view must follow ALTER TABLE ADD COLUMN.

    The original analyzer failed to resolve column references through table
    aliases (``ef`` -> ``entity_facts``), so ``CREATE VIEW v_fact_grades``
    did not depend on ``ALTER TABLE entity_facts ADD COLUMN assertion_intent``.
    The reorderer placed the view in group 0 and the ADD COLUMN in group 3,
    which caused a 42703 error at apply time.  This test pins the fix.
    """
    if not R2_PLAN.exists():
        pytest.skip("r2 plan fixture not present")
    plan = load_plan(R2_PLAN)
    out = reorder_plan(plan)
    validate_plan_invariants(out)

    def _flat_index(gidx: int, sidx: int) -> int:
        return sum(len(g["steps"]) for g in out["groups"][:gidx]) + sidx

    view_location = None
    alter_location = None
    view_prefix = "CREATE OR REPLACE VIEW v_fact_grades AS"
    alter_prefix = "ALTER TABLE entity_facts ADD COLUMN assertion_intent"

    for gidx, group in enumerate(out["groups"]):
        for sidx, step in enumerate(group["steps"]):
            sql = step["sql"]
            if sql.startswith(view_prefix):
                view_location = _flat_index(gidx, sidx)
            elif sql.startswith(alter_prefix):
                alter_location = _flat_index(gidx, sidx)

    assert alter_location is not None, "ALTER TABLE ADD COLUMN assertion_intent not found"
    assert view_location is not None, "CREATE VIEW v_fact_grades not found"
    assert view_location > alter_location, (
        f"view at flat index {view_location} must follow "
        f"ADD COLUMN at flat index {alter_location}"
    )
