"""Tests for COMMENT/GRANT dependency tracking (nova-mind#597 retry).

COMMENT ON <object> and GRANT/REVOKE ON <object> must be treated as dependents
of the corresponding CREATE statement so they move to the same (or later)
group and appear after the object they reference.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from database.plan_reorder import analyze_statement, load_plan, reorder_plan


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


# ---------------------------------------------------------------------------
# Object extraction from COMMENT / GRANT
# ---------------------------------------------------------------------------


def test_comment_on_function_extracts_signature_aware_identity():
    """COMMENT ON FUNCTION records a function ref including its signature."""
    analysis = analyze_statement(
        "COMMENT ON FUNCTION get_strictest_mutability(integer, varchar) IS 'docs';"
    )
    assert analysis["defines"] == set()
    assert analysis["refs"] == {"function:get_strictest_mutability(int4,varchar)"}


def test_comment_on_function_with_param_names_extracts_signature():
    """Parameter names in the comment signature are ignored for identity."""
    analysis = analyze_statement(
        "COMMENT ON FUNCTION get_strictest_mutability(p_entity_id integer, p_key character varying) IS 'docs';"
    )
    assert analysis["refs"] == {"function:get_strictest_mutability(int4,varchar)"}


def test_grant_execute_on_function_extracts_signature_aware_identity():
    """GRANT EXECUTE ON FUNCTION records a function ref including its signature."""
    analysis = analyze_statement(
        "GRANT EXECUTE ON FUNCTION get_strictest_mutability(integer, varchar) TO argus;"
    )
    assert analysis["defines"] == set()
    assert analysis["refs"] == {"function:get_strictest_mutability(int4,varchar)"}


def test_comment_on_table():
    """COMMENT ON TABLE references the table object."""
    analysis = analyze_statement("COMMENT ON TABLE foo IS 'docs';")
    assert analysis["refs"] == {"table:foo"}


def test_comment_on_view():
    """COMMENT ON VIEW references the view in the table namespace."""
    analysis = analyze_statement("COMMENT ON VIEW v_foo IS 'docs';")
    assert analysis["refs"] == {"table:v_foo"}


def test_comment_on_index():
    """COMMENT ON INDEX references the index object."""
    analysis = analyze_statement("COMMENT ON INDEX idx_foo IS 'docs';")
    assert analysis["refs"] == {"index:idx_foo"}


def test_comment_on_type():
    """COMMENT ON TYPE references the type object."""
    analysis = analyze_statement("COMMENT ON TYPE my_enum IS 'docs';")
    assert analysis["refs"] == {"type:my_enum"}


def test_comment_on_trigger():
    """COMMENT ON TRIGGER references the trigger object."""
    analysis = analyze_statement("COMMENT ON TRIGGER trig ON foo IS 'docs';")
    assert analysis["refs"] == {"trigger:foo.trig"}


def test_comment_on_column():
    """COMMENT ON COLUMN references the column object."""
    analysis = analyze_statement("COMMENT ON COLUMN foo.bar IS 'docs';")
    assert analysis["refs"] == {"column:foo.bar"}


def test_grant_on_sequence():
    """GRANT ON SEQUENCE references the sequence in the table namespace."""
    analysis = analyze_statement("GRANT USAGE ON SEQUENCE seq1 TO some_role;")
    assert analysis["refs"] == {"table:seq1"}


def test_grant_on_type():
    """GRANT ON TYPE references the type object."""
    analysis = analyze_statement("GRANT USAGE ON TYPE my_enum TO some_role;")
    assert analysis["refs"] == {"type:my_enum"}


# ---------------------------------------------------------------------------
# Object extraction with schema-qualified names (nova-mind#597 F1)
# ---------------------------------------------------------------------------


def test_comment_on_table_qualified():
    """Schema-qualified COMMENT ON TABLE strips the schema."""
    analysis = analyze_statement("COMMENT ON TABLE public.foo IS 'docs';")
    assert analysis["refs"] == {"table:foo"}


def test_comment_on_view_qualified():
    """Schema-qualified COMMENT ON VIEW strips the schema."""
    analysis = analyze_statement("COMMENT ON VIEW public.v_foo IS 'docs';")
    assert analysis["refs"] == {"table:v_foo"}


def test_comment_on_index_qualified():
    """Schema-qualified COMMENT ON INDEX strips the schema."""
    analysis = analyze_statement("COMMENT ON INDEX public.idx_foo IS 'docs';")
    assert analysis["refs"] == {"index:idx_foo"}


def test_comment_on_sequence_qualified():
    """Schema-qualified COMMENT ON SEQUENCE strips the schema."""
    analysis = analyze_statement("COMMENT ON SEQUENCE public.seq1 IS 'docs';")
    assert analysis["refs"] == {"table:seq1"}


def test_comment_on_trigger_qualified():
    """Schema-qualified COMMENT ON TRIGGER strips only the schema."""
    analysis = analyze_statement("COMMENT ON TRIGGER trig ON public.foo IS 'docs';")
    assert analysis["refs"] == {"trigger:foo.trig"}


def test_comment_on_column_qualified_three_part():
    """COMMENT ON COLUMN schema.table.column keeps the table identity."""
    analysis = analyze_statement("COMMENT ON COLUMN public.foo.bar IS 'docs';")
    assert analysis["refs"] == {"column:foo.bar"}


def test_comment_on_type_qualified():
    """Schema-qualified COMMENT ON TYPE strips the schema."""
    analysis = analyze_statement("COMMENT ON TYPE public.my_enum IS 'docs';")
    assert analysis["refs"] == {"type:my_enum"}


def test_grant_on_sequence_qualified():
    """Schema-qualified GRANT ON SEQUENCE strips the schema."""
    analysis = analyze_statement("GRANT USAGE ON SEQUENCE public.seq1 TO some_role;")
    assert analysis["refs"] == {"table:seq1"}


def test_grant_on_type_qualified():
    """Schema-qualified GRANT ON TYPE strips the schema."""
    analysis = analyze_statement("GRANT USAGE ON TYPE public.my_enum TO some_role;")
    assert analysis["refs"] == {"type:my_enum"}


# ---------------------------------------------------------------------------
# Reordering: dependents follow the CREATE
# ---------------------------------------------------------------------------


def test_comment_and_grant_follow_create_function_across_groups():
    """When a CREATE FUNCTION moves groups, its COMMENT/GRANT move with it.

    Regression for nova-mind#597 / SE #709: get_strictest_mutability was moved
    to a later group because it depends on a type created there, but its
    COMMENT ON FUNCTION and GRANT EXECUTE ON FUNCTION statements stayed behind
    in the original group and caused the schema apply to fail.
    """
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "test"},
        "groups": [
            {
                "steps": [
                    _step(
                        "CREATE FUNCTION get_strictest_mutability(x int) RETURNS t AS $$ SELECT 1; $$ LANGUAGE sql;",
                        type="function",
                        operation="create",
                        path="public.get_strictest_mutability",
                    ),
                    _step(
                        "COMMENT ON FUNCTION get_strictest_mutability(int) IS 'docs';",
                        type="comment",
                        operation="create",
                        path="public.get_strictest_mutability",
                    ),
                    _step(
                        "GRANT EXECUTE ON FUNCTION get_strictest_mutability(int) TO some_role;",
                        type="privilege",
                        operation="grant",
                        path="public.get_strictest_mutability",
                    ),
                ]
            },
            {
                "steps": [
                    _step(
                        "CREATE TYPE t AS ENUM ('a');",
                        type="type",
                        operation="create",
                        path="public.t",
                    ),
                ]
            },
        ],
    }
    out = reorder_plan(plan)
    sqls = [s["sql"] for g in out["groups"] for s in g["steps"]]

    create_idx = sqls.index(
        "CREATE FUNCTION get_strictest_mutability(x int) RETURNS t AS $$ SELECT 1; $$ LANGUAGE sql;"
    )
    comment_idx = sqls.index("COMMENT ON FUNCTION get_strictest_mutability(int) IS 'docs';")
    grant_idx = sqls.index(
        "GRANT EXECUTE ON FUNCTION get_strictest_mutability(int) TO some_role;"
    )
    type_idx = sqls.index("CREATE TYPE t AS ENUM ('a');")

    # The type must come before the function, and the function before its dependents.
    assert type_idx < create_idx < comment_idx < grant_idx

    # All four statements must end up in the same directive-free transactional group.
    assert len(out["groups"]) == 1


def test_comment_and_grant_follow_create_table():
    """COMMENT ON TABLE and GRANT ON TABLE follow the CREATE TABLE."""
    plan = _make_plan([
        _step("COMMENT ON TABLE foo IS 'docs';", type="comment", operation="create", path="public.foo"),
        _step("GRANT SELECT ON TABLE foo TO some_role;", type="privilege", operation="grant", path="public.foo"),
        _step("CREATE TABLE foo (id int);"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE foo (id int);",
        "COMMENT ON TABLE foo IS 'docs';",
        "GRANT SELECT ON TABLE foo TO some_role;",
    ]


def test_comment_and_grant_follow_create_view():
    """COMMENT ON VIEW and GRANT ON VIEW follow the CREATE VIEW."""
    plan = _make_plan([
        _step("COMMENT ON VIEW v_foo IS 'docs';", type="comment", operation="create", path="public.v_foo"),
        _step("GRANT SELECT ON TABLE v_foo TO some_role;", type="privilege", operation="grant", path="public.v_foo"),
        _step("CREATE VIEW v_foo AS SELECT * FROM foo;", type="view", operation="create", path="public.v_foo"),
        _step("CREATE TABLE foo (id int);"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls.index("CREATE TABLE foo (id int);") < sqls.index("CREATE VIEW v_foo AS SELECT * FROM foo;")
    assert sqls.index("CREATE VIEW v_foo AS SELECT * FROM foo;") < sqls.index("COMMENT ON VIEW v_foo IS 'docs';")
    assert sqls.index("COMMENT ON VIEW v_foo IS 'docs';") < sqls.index("GRANT SELECT ON TABLE v_foo TO some_role;")


def test_comment_and_grant_follow_create_type():
    """COMMENT ON TYPE and GRANT ON TYPE follow the CREATE TYPE."""
    plan = _make_plan([
        _step("COMMENT ON TYPE my_enum IS 'docs';", type="comment", operation="create", path="public.my_enum"),
        _step("GRANT USAGE ON TYPE my_enum TO some_role;", type="privilege", operation="grant", path="public.my_enum"),
        _step("CREATE TYPE my_enum AS ENUM ('a');", type="type", operation="create", path="public.my_enum"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TYPE my_enum AS ENUM ('a');",
        "COMMENT ON TYPE my_enum IS 'docs';",
        "GRANT USAGE ON TYPE my_enum TO some_role;",
    ]


def test_qa_repro_qualified_comment_follows_unqualified_create():
    """QA repro: COMMENT ON TABLE public.foo must follow CREATE TABLE public.foo."""
    plan = _make_plan([
        _step("COMMENT ON TABLE public.foo IS 'docs';", type="comment", operation="create", path="public.foo"),
        _step("CREATE TABLE public.foo (id int);", type="table", operation="create", path="public.foo"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE public.foo (id int);",
        "COMMENT ON TABLE public.foo IS 'docs';",
    ]


def test_qualified_comment_and_grant_follow_unqualified_create_table():
    """Qualified COMMENT/GRANT depend on unqualified CREATE table identity."""
    plan = _make_plan([
        _step("COMMENT ON TABLE public.foo IS 'docs';", type="comment", operation="create", path="public.foo"),
        _step("GRANT SELECT ON TABLE public.foo TO some_role;", type="privilege", operation="grant", path="public.foo"),
        _step("CREATE TABLE foo (id int);", type="table", operation="create", path="public.foo"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE foo (id int);",
        "COMMENT ON TABLE public.foo IS 'docs';",
        "GRANT SELECT ON TABLE public.foo TO some_role;",
    ]


def test_qualified_comment_and_grant_follow_qualified_create_table():
    """Qualified COMMENT/GRANT depend on qualified CREATE table identity."""
    plan = _make_plan([
        _step("COMMENT ON TABLE public.foo IS 'docs';", type="comment", operation="create", path="public.foo"),
        _step("GRANT SELECT ON TABLE public.foo TO some_role;", type="privilege", operation="grant", path="public.foo"),
        _step("CREATE TABLE public.foo (id int);", type="table", operation="create", path="public.foo"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE public.foo (id int);",
        "COMMENT ON TABLE public.foo IS 'docs';",
        "GRANT SELECT ON TABLE public.foo TO some_role;",
    ]


def test_qualified_comment_on_column_three_part_follows_create_table():
    """COMMENT ON COLUMN public.foo.bar depends on CREATE TABLE public.foo."""
    plan = _make_plan([
        _step("COMMENT ON COLUMN public.foo.bar IS 'docs';", type="comment", operation="create", path="public.foo.bar"),
        _step("CREATE TABLE public.foo (id int, bar int);", type="table", operation="create", path="public.foo"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE public.foo (id int, bar int);",
        "COMMENT ON COLUMN public.foo.bar IS 'docs';",
    ]


def test_qualified_grant_on_type_follows_create_type():
    """GRANT ON TYPE public.my_enum depends on CREATE TYPE public.my_enum."""
    plan = _make_plan([
        _step("GRANT USAGE ON TYPE public.my_enum TO some_role;", type="privilege", operation="grant", path="public.my_enum"),
        _step("CREATE TYPE public.my_enum AS ENUM ('a');", type="type", operation="create", path="public.my_enum"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TYPE public.my_enum AS ENUM ('a');",
        "GRANT USAGE ON TYPE public.my_enum TO some_role;",
    ]


# ---------------------------------------------------------------------------
# Regression fixture from staging
# ---------------------------------------------------------------------------


def test_regression_597_staging_fixture_comment_grant_follow_function():
    """Staging fixture: get_strictest_mutability dependents follow its CREATE."""
    fixture = Path(__file__).parent / "fixtures" / "plan_reorder" / "plan_597_regression.json"
    plan = load_plan(fixture)
    out = reorder_plan(plan)

    create_sql = (
        "CREATE OR REPLACE FUNCTION get_strictest_mutability(\n"
        "    p_entity_id integer,\n"
        "    p_key varchar\n"
        ")"
    )
    comment_sql = "COMMENT ON FUNCTION get_strictest_mutability(integer, varchar) IS"
    grant_sql = "GRANT EXECUTE ON FUNCTION get_strictest_mutability(p_entity_id integer, p_key character varying) TO"

    create_location: tuple[int, int] | None = None
    comment_locations: list[tuple[int, int]] = []
    grant_locations: list[tuple[int, int]] = []

    for gidx, group in enumerate(out["groups"]):
        for sidx, step in enumerate(group["steps"]):
            sql = step["sql"]
            if sql.startswith(create_sql):
                create_location = (gidx, sidx)
            elif sql.startswith(comment_sql):
                comment_locations.append((gidx, sidx))
            elif sql.startswith(grant_sql):
                grant_locations.append((gidx, sidx))

    assert create_location is not None, "CREATE FUNCTION not found in reordered plan"
    assert len(comment_locations) == 1, f"expected one COMMENT, found {len(comment_locations)}"
    assert len(grant_locations) == 12, f"expected 12 GRANTs, found {len(grant_locations)}"

    create_group, create_step = create_location
    comment_group, comment_step = comment_locations[0]

    # COMMENT must be in the same group as (or a later group than) the CREATE,
    # and after it within the group.
    assert comment_group >= create_group
    if comment_group == create_group:
        assert comment_step > create_step

    # Each GRANT must be in the same group as (or a later group than) the CREATE,
    # and after it within the group.
    for grant_group, grant_step in grant_locations:
        assert grant_group >= create_group
        if grant_group == create_group:
            assert grant_step > create_step


def test_regression_597_staging_fixture_no_group_zero_function_dependents():
    """Staging fixture: no get_strictest_mutability COMMENT/GRANT left in group 0."""
    fixture = Path(__file__).parent / "fixtures" / "plan_reorder" / "plan_597_regression.json"
    plan = load_plan(fixture)
    out = reorder_plan(plan)

    comment_sql = "COMMENT ON FUNCTION get_strictest_mutability(integer, varchar) IS"
    grant_sql = "GRANT EXECUTE ON FUNCTION get_strictest_mutability(p_entity_id integer, p_key character varying) TO"

    if out["groups"]:
        for step in out["groups"][0]["steps"]:
            assert not step["sql"].startswith(comment_sql)
            assert not step["sql"].startswith(grant_sql)


# ---------------------------------------------------------------------------
# ALTER ... OWNER TO and SECURITY LABEL metadata dependents
# ---------------------------------------------------------------------------


def test_alter_table_owner_to_depends_on_create_table():
    """ALTER TABLE ... OWNER TO is ordered after CREATE TABLE."""
    plan = _make_plan([
        _step("ALTER TABLE foo OWNER TO some_role;", type="table", operation="alter", path="public.foo"),
        _step("CREATE TABLE foo (id int);"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE foo (id int);",
        "ALTER TABLE foo OWNER TO some_role;",
    ]


def test_alter_sequence_owner_to_depends_on_create_sequence():
    """ALTER SEQUENCE ... OWNER TO is ordered after the sequence definition."""
    plan = _make_plan([
        _step("ALTER SEQUENCE seq1 OWNER TO some_role;", type="sequence", operation="alter", path="public.seq1"),
        _step("CREATE SEQUENCE seq1;", type="sequence", operation="create", path="public.seq1"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE SEQUENCE seq1;",
        "ALTER SEQUENCE seq1 OWNER TO some_role;",
    ]


def test_alter_function_owner_to_depends_on_create_function():
    """ALTER FUNCTION ... OWNER TO follows the signature-matched CREATE FUNCTION."""
    plan = _make_plan([
        _step(
            "ALTER FUNCTION get_strictest_mutability(integer, varchar) OWNER TO some_role;",
            type="function",
            operation="alter",
            path="public.get_strictest_mutability",
        ),
        _step(
            "CREATE FUNCTION get_strictest_mutability(x int, y varchar) RETURNS int AS $$ SELECT 1; $$ LANGUAGE sql;",
            type="function",
            operation="create",
            path="public.get_strictest_mutability",
        ),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls[0].startswith("CREATE FUNCTION get_strictest_mutability")
    assert sqls[1].startswith("ALTER FUNCTION get_strictest_mutability")


def test_alter_type_owner_to_depends_on_create_type():
    """ALTER TYPE ... OWNER TO is ordered after CREATE TYPE."""
    plan = _make_plan([
        _step("ALTER TYPE my_enum OWNER TO some_role;", type="type", operation="alter", path="public.my_enum"),
        _step("CREATE TYPE my_enum AS ENUM ('a');", type="type", operation="create", path="public.my_enum"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TYPE my_enum AS ENUM ('a');",
        "ALTER TYPE my_enum OWNER TO some_role;",
    ]


def test_security_label_on_table_depends_on_create_table():
    """SECURITY LABEL ON TABLE is ordered after CREATE TABLE."""
    plan = _make_plan([
        _step("SECURITY LABEL FOR selinux ON TABLE foo IS 'system_u:object_r:sepgsql_table_t:s0';", type="table", operation="alter", path="public.foo"),
        _step("CREATE TABLE foo (id int);"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls[0] == "CREATE TABLE foo (id int);"
    assert sqls[1].startswith("SECURITY LABEL")


def test_security_label_on_function_depends_on_create_function():
    """SECURITY LABEL ON FUNCTION follows the signature-matched CREATE FUNCTION."""
    plan = _make_plan([
        _step(
            "SECURITY LABEL ON FUNCTION get_strictest_mutability(integer, varchar) IS 'label';",
            type="function",
            operation="alter",
            path="public.get_strictest_mutability",
        ),
        _step(
            "CREATE FUNCTION get_strictest_mutability(x int, y varchar) RETURNS int AS $$ SELECT 1; $$ LANGUAGE sql;",
            type="function",
            operation="create",
            path="public.get_strictest_mutability",
        ),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls[0].startswith("CREATE FUNCTION get_strictest_mutability")
    assert sqls[1].startswith("SECURITY LABEL")
