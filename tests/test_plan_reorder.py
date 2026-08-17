"""Tests for database/plan_reorder.py (chunk 1: dependency extraction + toposort).

Derived from /home/nova/.openclaw/workspace/evals/se709/test-case-design-v2.md.
Every computed expected literal is traced to the v2 doc in a comment.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from database.plan_reorder import (
    CycleError,
    ParseError,
    PlanFormatError,
    analyze_statement,
    reorder_plan,
)


def _make_plan(steps: list[dict]) -> dict:
    """Build a minimal valid pgschema plan around the supplied steps."""
    return {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-01-01T00:00:00Z",
        "source_fingerprint": {"hash": "test-hash"},
        "groups": [{"steps": steps}],
    }


def _step(sql: str, **extra) -> dict:
    return {"sql": sql, "type": "table", "operation": "create", "path": "public.x", **extra}


# ---------------------------------------------------------------------------
# Dependency extraction correctness (Section 2)
# ---------------------------------------------------------------------------


def test_tc04_alter_table_add_column_simple_type():
    """TC-4: ALTER TABLE ADD COLUMN with simple type has no custom dependency."""
    analysis = analyze_statement("ALTER TABLE foo ADD COLUMN bar text;")
    # Defines the table and the new column; no refs beyond the (external) table.
    assert analysis["defines"] == {"table:foo", "column:foo.bar"}
    assert analysis["refs"] == set()


def test_tc05_alter_table_add_column_enum_typed():
    """TC-5: enum type + cast in DEFAULT both depend on CREATE TYPE."""
    analysis = analyze_statement(
        "ALTER TABLE entity_facts ADD COLUMN mutability_class mutability_class_enum "
        "DEFAULT 'slow_changing'::mutability_class_enum NOT NULL;"
    )
    # Column type and cast both reference mutability_class_enum.
    assert analysis["refs"] == {"type:mutability_class_enum"}


def test_tc06_create_function_sql_body_column_ref():
    """TC-6: SQL-language function body column ref extracted."""
    analysis = analyze_statement(
        "CREATE FUNCTION get_strictest_mutability(entity_id bigint, key text) "
        "RETURNS text AS $$ SELECT mutability_class FROM entity_facts "
        "WHERE entity_id = $1 AND key = $2; $$ LANGUAGE sql;"
    )
    assert analysis["defines"] == {"function:get_strictest_mutability(int8,text)"}
    # Body references the entity_facts table and the mutability_class column;
    # the `key text` parameter contributes a (harmless) built-in type ref.
    assert analysis["refs"] == {
        "table:entity_facts",
        "column:entity_facts.mutability_class",
        "type:text",
    }


def test_tc07_create_function_plpgsql_body_column_ref():
    """TC-7: plpgsql function body parsed via parse_plpgsql + inner parse_sql."""
    analysis = analyze_statement(
        "CREATE FUNCTION get_strictest_mutability(entity_id bigint, key text) "
        "RETURNS text AS $$ BEGIN "
        "RETURN (SELECT mutability_class FROM entity_facts WHERE entity_id = $1 AND key = $2); "
        "END; $$ LANGUAGE plpgsql;"
    )
    assert analysis["defines"] == {"function:get_strictest_mutability(int8,text)"}
    # DERIVATION: fix loop 3 extended AST traversal into A_Expr lexpr/rexpr,
    # so the WHERE clause now contributes column refs for entity_id and key in
    # addition to the SELECT target mutability_class.
    assert analysis["refs"] == {
        "table:entity_facts",
        "column:entity_facts.mutability_class",
        "column:entity_facts.entity_id",
        "column:entity_facts.key",
        "type:text",
    }


def test_tc08_create_function_self_contained():
    """TC-8: parameter-only function produces zero dependency edges."""
    analysis = analyze_statement(
        "CREATE FUNCTION add_one(x int) RETURNS int AS $$ SELECT x + 1; $$ LANGUAGE sql;"
    )
    assert analysis["defines"] == {"function:add_one(int4)"}
    assert analysis["refs"] == set()


def test_tc09_create_view_direct_table_column():
    """TC-9: CREATE VIEW extracts table + column refs."""
    analysis = analyze_statement(
        "CREATE VIEW v_x AS SELECT mutability_class FROM entity_facts;"
    )
    # Views share the table namespace for ordering; see module design notes.
    assert analysis["defines"] == {"table:v_x"}
    assert analysis["refs"] == {"table:entity_facts", "column:entity_facts.mutability_class"}


def test_tc09a_create_view_aliased_table_column():
    """CREATE VIEW resolves column refs through table aliases."""
    analysis = analyze_statement(
        "CREATE VIEW v_x AS SELECT ef.mutability_class FROM entity_facts ef;"
    )
    assert analysis["defines"] == {"table:v_x"}
    assert analysis["refs"] == {"table:entity_facts", "column:entity_facts.mutability_class"}


def test_tc09b_create_view_joined_aliased_columns():
    """CREATE VIEW resolves aliases inside JOIN trees."""
    analysis = analyze_statement(
        "CREATE VIEW v_x AS SELECT ef.mutability_class, e.name "
        "FROM entity_facts ef LEFT JOIN entities e ON ef.entity_id = e.id;"
    )
    assert analysis["defines"] == {"table:v_x"}
    assert "column:entity_facts.mutability_class" in analysis["refs"]
    assert "column:entities.name" in analysis["refs"]
    assert "column:entity_facts.entity_id" in analysis["refs"]
    assert "column:entities.id" in analysis["refs"]
    assert "table:ef" not in analysis["refs"]
    assert "table:e" not in analysis["refs"]


def test_tc09c_create_materialized_view_aliased_column():
    """CREATE MATERIALIZED VIEW resolves column refs through aliases."""
    analysis = analyze_statement(
        "CREATE MATERIALIZED VIEW mv_x AS SELECT ef.mutability_class FROM entity_facts ef;"
    )
    assert analysis["defines"] == {"table:mv_x"}
    assert analysis["refs"] == {"table:entity_facts", "column:entity_facts.mutability_class"}


def test_tc10_create_view_chained():
    """TC-10: second view depends on first view (treated as table)."""
    analysis_a = analyze_statement("CREATE VIEW v_a AS SELECT * FROM base_table;")
    assert analysis_a["refs"] == {"table:base_table"}
    analysis_b = analyze_statement("CREATE VIEW v_b AS SELECT * FROM v_a;")
    assert analysis_b["refs"] == {"table:v_a"}


def test_tc11_create_view_function_call():
    """TC-11: view referencing a function call extracts function dependency."""
    analysis = analyze_statement(
        "CREATE VIEW v_fact_grades AS "
        "SELECT get_strictest_mutability(entity_id, key) AS strictest FROM entity_facts;"
    )
    assert analysis["defines"] == {"table:v_fact_grades"}
    assert "function:get_strictest_mutability" in analysis["refs"]
    assert "table:entity_facts" in analysis["refs"]


def test_tc12_grant_whole_table():
    """TC-12: GRANT on whole table depends on the table."""
    analysis = analyze_statement("GRANT SELECT ON TABLE foo TO some_role;")
    assert analysis["refs"] == {"table:foo"}


def test_tc13_grant_specific_columns():
    """TC-13: GRANT on specific columns depends on each table.column."""
    analysis = analyze_statement(
        "GRANT UPDATE (reserved, other_col) ON TABLE motivation_d100 TO some_role;"
    )
    assert analysis["refs"] == {
        "table:motivation_d100",
        "column:motivation_d100.reserved",
        "column:motivation_d100.other_col",
    }


def test_tc14_create_index_plain():
    """TC-14: plain CREATE INDEX depends on table and indexed column."""
    analysis = analyze_statement("CREATE INDEX idx_foo ON bar (baz);")
    assert analysis["defines"] == {"index:idx_foo"}
    assert analysis["refs"] == {"table:bar", "column:bar.baz"}
    assert analysis["non_txn"] is False


def test_tc15_create_index_concurrently():
    """TC-15: CREATE INDEX CONCURRENTLY is flagged non-transactional."""
    analysis = analyze_statement("CREATE INDEX CONCURRENTLY idx_foo ON bar (baz);")
    assert analysis["refs"] == {"table:bar", "column:bar.baz"}
    assert analysis["non_txn"] is True


def test_tc15a_create_index_expression_and_partial():
    """Expression and partial-index WHERE clauses reference columns."""
    analysis = analyze_statement(
        "CREATE INDEX idx_expr ON t ((a + b), c) WHERE d = 'x';"
    )
    assert analysis["defines"] == {"index:idx_expr"}
    assert analysis["refs"] == {
        "table:t",
        "column:t.a",
        "column:t.b",
        "column:t.c",
        "column:t.d",
    }


def test_tc16_create_trigger():
    """TC-16: CREATE TRIGGER depends on table and trigger function."""
    analysis = analyze_statement(
        "CREATE TRIGGER t1 AFTER INSERT ON foo FOR EACH ROW EXECUTE FUNCTION trig_fn();"
    )
    assert analysis["refs"] == {"table:foo", "function:trig_fn"}


def test_tc17_fk_alter_table():
    """TC-17: ALTER TABLE ADD CONSTRAINT FOREIGN KEY refs referenced table/column."""
    analysis = analyze_statement(
        "ALTER TABLE a ADD CONSTRAINT fk1 FOREIGN KEY (b_id) REFERENCES b(id);"
    )
    assert analysis["refs"] == {"table:b", "column:b.id"}


def test_tc18_fk_inline_create_table():
    """TC-18: inline FOREIGN KEY in CREATE TABLE refs referenced table."""
    analysis = analyze_statement(
        "CREATE TABLE a (id serial, b_id int REFERENCES b(id));"
    )
    # v2 doc requires dependency on table b (column dependency is acceptable but not required).
    assert "table:b" in analysis["refs"]


def test_tc18a_check_constraint_inline_create_table():
    """Inline CHECK constraint expression references table columns."""
    analysis = analyze_statement(
        "CREATE TABLE a (id int, status text, CHECK (status IN ('x', 'y')));"
    )
    assert analysis["defines"] == {"table:a", "column:a.id", "column:a.status"}
    assert "column:a.status" in analysis["refs"]


def test_tc18b_check_constraint_alter_table():
    """ALTER TABLE ADD CHECK expression references table columns."""
    analysis = analyze_statement(
        "ALTER TABLE a ADD CONSTRAINT chk_status CHECK (status IN ('x', 'y'));"
    )
    # ADD CONSTRAINT defines the table (for ordering) but not a separate
    # constraint identity; the column refs still drive ordering.
    assert analysis["defines"] == {"table:a"}
    assert "column:a.status" in analysis["refs"]


def test_tc18c_check_constraint_create_table_self_ref_not_a_cycle():
    """CREATE TABLE CHECK on own columns must not create a self-dependency.

    analyze_statement intentionally records both the table definition and the
    table reference; the graph builder must drop the self-dependency.
    """
    analysis = analyze_statement(
        "CREATE TABLE a (id int, status text, CHECK (status IN ('x', 'y')));"
    )
    assert analysis["defines"] == {"table:a", "column:a.id", "column:a.status"}
    assert "column:a.status" in analysis["refs"]
    from database.plan_reorder import _object_dependency_map

    obj_deps = _object_dependency_map([analysis])
    assert "table:a" not in obj_deps.get("table:a", set())


def test_tc18d_check_constraint_alter_table_self_ref_not_a_cycle():
    """ALTER TABLE ADD CHECK on own columns must not create a self-dependency.

    analyze_statement intentionally records both the table definition and the
    table reference; the graph builder must drop the self-dependency.
    """
    analysis = analyze_statement(
        "ALTER TABLE a ADD CONSTRAINT chk_status CHECK (status IN ('x', 'y'));"
    )
    assert analysis["defines"] == {"table:a"}
    assert "column:a.status" in analysis["refs"]
    from database.plan_reorder import _object_dependency_map

    obj_deps = _object_dependency_map([analysis])
    assert "table:a" not in obj_deps.get("table:a", set())


# ---------------------------------------------------------------------------
# DROP reverse dependency (Section 2)
# ---------------------------------------------------------------------------


def test_tc19_drop_view_before_drop_table():
    """TC-19: DROP VIEW must precede DROP TABLE of its dependency.

    Fixture includes the CREATE VIEW so the object dependency graph is known.
    """
    plan = _make_plan([
        _step("DROP TABLE foo;", type="table", operation="drop", path="public.foo"),
        _step("CREATE VIEW v_foo AS SELECT * FROM foo;", type="view", operation="create", path="public.v_foo"),
        _step("DROP VIEW v_foo;", type="view", operation="drop", path="public.v_foo"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls.index("DROP VIEW v_foo;") < sqls.index("DROP TABLE foo;")


def test_tc20_drop_column_with_dependent_view():
    """TC-20: DROP VIEW precedes ALTER TABLE DROP COLUMN it depended on."""
    plan = _make_plan([
        _step("ALTER TABLE foo DROP COLUMN bar;", type="table.column", operation="drop", path="public.foo.bar"),
        _step("CREATE VIEW v_x AS SELECT bar FROM foo;", type="view", operation="create", path="public.v_x"),
        _step("DROP VIEW v_x;", type="view", operation="drop", path="public.v_x"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls.index("DROP VIEW v_x;") < sqls.index("ALTER TABLE foo DROP COLUMN bar;")


def test_tc21_mixed_create_drop_rename_pattern():
    """TC-21: rename-via-drop-add + dependent view reorders correctly."""
    plan = _make_plan([
        _step("ALTER TABLE foo DROP COLUMN old_name;", type="table.column", operation="drop", path="public.foo.old_name"),
        _step("ALTER TABLE foo ADD COLUMN new_name text;", type="table.column", operation="add", path="public.foo.new_name"),
        _step("CREATE VIEW v_new AS SELECT new_name FROM foo;", type="view", operation="create", path="public.v_new"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    # View depends on ADD COLUMN, so ADD COLUMN must precede CREATE VIEW.
    assert sqls.index("ALTER TABLE foo ADD COLUMN new_name text;") < sqls.index(
        "CREATE VIEW v_new AS SELECT new_name FROM foo;"
    )


def test_tc21a_drop_view_then_create_table_same_name_no_self_loop():
    """TC-21a: view->table conversion with CHECK self-reference must not cycle."""
    plan = _make_plan([
        _step("DROP VIEW IF EXISTS agent_boot CASCADE;", type="view", operation="drop", path="public.agent_boot"),
        _step(
            "CREATE TABLE IF NOT EXISTS agent_boot (id int, status text, CHECK (status IN ('x', 'y')));",
            type="table", operation="create", path="public.agent_boot",
        ),
    ])
    # Must not raise CycleError; DROP VIEW should precede CREATE TABLE.
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls.index("DROP VIEW IF EXISTS agent_boot CASCADE;") < sqls.index(
        "CREATE TABLE IF NOT EXISTS agent_boot (id int, status text, CHECK (status IN ('x', 'y')));"
    )


def test_tc21b_drop_constraint_then_add_constraint_check_no_self_loop():
    """TC-21b: ALTER TABLE DROP/ADD CHECK on same table must not cycle."""
    plan = _make_plan([
        _step(
            "ALTER TABLE a DROP CONSTRAINT assertion_intent_not_null;",
            type="table.constraint", operation="drop", path="public.a.assertion_intent_not_null",
        ),
        _step(
            "ALTER TABLE a ADD CONSTRAINT assertion_intent_not_null CHECK (assertion_intent IS NOT NULL) NOT VALID;",
            type="table.constraint", operation="add", path="public.a.assertion_intent_not_null",
        ),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls.index("ALTER TABLE a DROP CONSTRAINT assertion_intent_not_null;") < sqls.index(
        "ALTER TABLE a ADD CONSTRAINT assertion_intent_not_null CHECK (assertion_intent IS NOT NULL) NOT VALID;"
    )


# ---------------------------------------------------------------------------
# Toposort properties (Section 3)
# ---------------------------------------------------------------------------


def test_tc22_deterministic_for_independent_statements():
    """TC-22: stable tie-break preserves input order across repeated runs."""
    plan = _make_plan([
        _step("CREATE TABLE a (id int);"),
        _step("CREATE TABLE b (id int);"),
        _step("CREATE TABLE c (id int);"),
        _step("CREATE TABLE d (id int);"),
        _step("CREATE TABLE e (id int);"),
    ])
    outputs = []
    for _ in range(10):
        out = reorder_plan(plan)
        outputs.append(
            "\n".join(s["sql"] for s in out["groups"][0]["steps"])
        )
    assert len(set(outputs)) == 1


def test_tc23_already_ordered_plan_unchanged():
    """TC-23: correctly ordered plan is emitted unchanged."""
    plan = _make_plan([
        _step("CREATE TABLE foo (id int);"),
        _step("CREATE VIEW v_foo AS SELECT * FROM foo;"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "CREATE TABLE foo (id int);",
        "CREATE VIEW v_foo AS SELECT * FROM foo;",
    ]


def test_tc24_cycle_mutual_fk_raises():
    """TC-24: mutual FK cycle raises CycleError with statement-level report."""
    plan = _make_plan([
        _step(
            "ALTER TABLE a ADD CONSTRAINT fk_a FOREIGN KEY (b_id) REFERENCES b(id);",
            type="table.constraint", operation="add", path="public.a.fk_a",
        ),
        _step(
            "ALTER TABLE b ADD CONSTRAINT fk_b FOREIGN KEY (a_id) REFERENCES a(id);",
            type="table.constraint", operation="add", path="public.b.fk_b",
        ),
    ])
    with pytest.raises(CycleError) as exc_info:
        reorder_plan(plan)
    assert "cycle" in exc_info.value.message.lower()
    assert len(exc_info.value.statements) == 2


def test_tc25_cycle_mutual_view_raises():
    """TC-25: mutual view reference cycle is caught pre-apply."""
    plan = _make_plan([
        _step("CREATE VIEW v_a AS SELECT * FROM v_b;", type="view", operation="create", path="public.v_a"),
        _step("CREATE VIEW v_b AS SELECT * FROM v_a;", type="view", operation="create", path="public.v_b"),
    ])
    with pytest.raises(CycleError):
        reorder_plan(plan)


def test_tc26_unparseable_statement_raises():
    """TC-26: top-level parse failure raises ParseError."""
    plan = _make_plan([_step("THIS IS NOT SQL;")])
    with pytest.raises(ParseError) as exc_info:
        reorder_plan(plan)
    assert "THIS IS NOT SQL" in exc_info.value.statements[0]["sql"]


def test_tc27_pg17_syntax_rejected_by_pg16_grammar():
    """TC-27: PG17+ grammar rejected by pglast 6.x PG16 grammar."""
    # MERGE ... WHEN NOT MATCHED BY TARGET is PG17+.
    plan = _make_plan([
        _step("MERGE INTO t USING s ON t.id = s.id WHEN NOT MATCHED BY TARGET THEN INSERT (id) VALUES (s.id);")
    ])
    with pytest.raises(ParseError):
        reorder_plan(plan)


# ---------------------------------------------------------------------------
# Plan integrity (Section 4)
# ---------------------------------------------------------------------------


def test_tc29_verbatim_fields_preserved():
    """TC-29: top-level verbatim fields are preserved byte-for-byte."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T03:51:00Z",
        "source_fingerprint": {"hash": "preserve-me"},
        "groups": [{"steps": [_step("CREATE TABLE t (id int);")]}],
    }
    out = reorder_plan(plan)
    assert out["version"] == plan["version"]
    assert out["pgschema_version"] == plan["pgschema_version"]
    assert out["created_at"] == plan["created_at"]
    assert out["source_fingerprint"] == plan["source_fingerprint"]


def test_tc30_unknown_plan_version_raises():
    """TC-30: unsupported plan version raises PlanFormatError."""
    plan = {
        "version": "2.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "x"},
        "groups": [],
    }
    with pytest.raises(PlanFormatError) as exc_info:
        reorder_plan(plan)
    assert "2.0.0" in exc_info.value.message


def test_tc31_malformed_plan_raises():
    """TC-31: structurally malformed plan JSON raises PlanFormatError."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "x"},
        "groups": "not-an-array",
    }
    with pytest.raises(PlanFormatError):
        reorder_plan(plan)


def test_tc32_empty_plan_passes_through():
    """TC-32: empty groups array passes through unchanged."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "x"},
        "groups": [],
    }
    out = reorder_plan(plan)
    assert out["groups"] == []


def test_tc32a_null_groups_passes_through():
    """TC-32a: pgschema no-change plan with groups:null is an empty plan."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T14:16:45Z",
        "source_fingerprint": {"hash": "x"},
        "groups": None,
    }
    out = reorder_plan(plan)
    assert out["groups"] == []
    assert out["version"] == plan["version"]
    assert out["pgschema_version"] == plan["pgschema_version"]
    assert out["created_at"] == plan["created_at"]
    assert out["source_fingerprint"] == plan["source_fingerprint"]


def test_tc32b_missing_groups_key_passes_through():
    """TC-32b: absent groups key is treated as an empty plan."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "created_at": "2026-08-17T14:16:45Z",
        "source_fingerprint": {"hash": "x"},
    }
    out = reorder_plan(plan)
    assert out["groups"] == []
    assert out["version"] == plan["version"]
    assert out["pgschema_version"] == plan["pgschema_version"]
    assert out["created_at"] == plan["created_at"]
    assert out["source_fingerprint"] == plan["source_fingerprint"]


def test_tc31_still_rejects_non_array_groups():
    """TC-31: non-null non-array groups remains a structural error."""
    plan = {
        "version": "1.0.0",
        "pgschema_version": "1.7.2",
        "source_fingerprint": {"hash": "x"},
        "groups": "not-an-array",
    }
    with pytest.raises(PlanFormatError):
        reorder_plan(plan)


def test_tc32c_real_idempotent_fixture_passes_through():
    """TC-32c: captured staging no-change plan passes through unchanged."""
    fixture = Path(__file__).parent / "fixtures" / "plan_reorder" / "idempotent-diag-plan.json"
    plan = json.loads(fixture.read_text())
    out = reorder_plan(plan)
    assert out["groups"] == []
    assert out["version"] == plan["version"]
    assert out["pgschema_version"] == plan["pgschema_version"]
    assert out["created_at"] == plan["created_at"]
    assert out["source_fingerprint"] == plan["source_fingerprint"]


def test_tc33_single_statement_plan():
    """TC-33: single-statement single-group plan trivial pass-through."""
    plan = _make_plan([_step("CREATE TABLE t (id int);")])
    out = reorder_plan(plan)
    assert len(out["groups"]) == 1
    assert len(out["groups"][0]["steps"]) == 1


def test_tc34_privilege_only_plan():
    """TC-34: privilege-only plan passes through unchanged."""
    plan = _make_plan([
        _step("GRANT SELECT ON TABLE foo TO some_role;", type="privilege", operation="grant", path="public.foo"),
        _step("GRANT SELECT ON TABLE bar TO some_role;", type="privilege", operation="grant", path="public.bar"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == [
        "GRANT SELECT ON TABLE foo TO some_role;",
        "GRANT SELECT ON TABLE bar TO some_role;",
    ]


# ---------------------------------------------------------------------------
# Boundary values / edge conditions (Section 10)
# ---------------------------------------------------------------------------


def test_tc55_missing_dependency_target_passes_through():
    """TC-55: reference to wholly missing object passes through; not a hard-fail."""
    plan = _make_plan([
        _step("GRANT UPDATE (nonexistent_col) ON TABLE foo TO some_role;", type="privilege", operation="grant", path="public.foo.nonexistent_col"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == ["GRANT UPDATE (nonexistent_col) ON TABLE foo TO some_role;"]


def test_tc56_externally_satisfied_table():
    """TC-56: table target existing only in live DB (not in plan) is external."""
    plan = _make_plan([
        _step("ALTER TABLE existing_table ADD COLUMN new_col text;", type="table.column", operation="add", path="public.existing_table.new_col"),
    ])
    out = reorder_plan(plan)
    sqls = [s["sql"] for s in out["groups"][0]["steps"]]
    assert sqls == ["ALTER TABLE existing_table ADD COLUMN new_col text;"]


def test_tc58_dynamic_sql_in_plpgsql_never_hard_fails():
    """TC-58: EXECUTE format(...) skipped; static refs still extracted."""
    analysis = analyze_statement(
        "CREATE FUNCTION dyn_fn(col text, tbl text) RETURNS void AS $$ "
        "DECLARE r record; "
        "BEGIN "
        "EXECUTE format('SELECT %I FROM %I', col, tbl) INTO r; "
        "RETURN (SELECT mutability_class FROM entity_facts WHERE entity_id = 1); "
        "END; $$ LANGUAGE plpgsql;"
    )
    # Dynamic portion yields no edges; static portion yields entity_facts refs.
    # Parameter/return types contribute harmless built-in type refs.
    # DERIVATION: fix loop 3 extended AST traversal into A_Expr lexpr/rexpr,
    # so the WHERE clause now contributes column:entity_facts.entity_id.
    assert analysis["refs"] == {
        "table:entity_facts",
        "column:entity_facts.mutability_class",
        "column:entity_facts.entity_id",
        "type:text",
        "type:void",
    }


def test_tc59_catalog_and_extension_refs_no_edges():
    """TC-59: pg_catalog/information_schema refs and extension type refs ignored."""
    a = analyze_statement("CREATE VIEW v_x AS SELECT relname FROM pg_catalog.pg_class;")
    assert a["refs"] == set()

    b = analyze_statement("CREATE VIEW v_y AS SELECT table_name FROM information_schema.tables;")
    assert b["refs"] == set()

    c = analyze_statement("CREATE TABLE embeddings (id serial, embedding vector(1536));")
    # vector is not a plan-internal type; no edge generated.
    assert "type:vector" not in c["refs"]
