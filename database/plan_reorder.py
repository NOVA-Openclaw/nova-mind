#!/usr/bin/env python3
"""Dependency-aware reorderer for pgschema plan JSON.

Reads a pgschema plan (``pgschema plan --output-json``), parses each step's SQL
with pglast, builds an object-level dependency graph, and emits a topologically
sorted plan that is safe to apply on a fresh database.

Design constraints (nova-mind#597 batch):

* Only ``groups[]`` may change.  ``version``, ``pgschema_version``,
  ``source_fingerprint`` and ``created_at`` are preserved byte-for-byte.
* Directive-bearing and non-transactional steps remain isolated in their own
  groups; their relative order is preserved unless a dependency forces a move.
* Directive-free transactional groups may be merged into a single atomic group
  when a valid total order exists.
* DROP-type operations use reverse dependency direction: dependents must be
  dropped before the objects they depend on.
* CREATE FUNCTION bodies are inspected recursively: ``parse_sql`` outer →
  ``parse_plpgsql`` body → ``parse_sql`` on each ``PLpgSQL_stmt_return`` or
  ``PLpgSQL_stmt_execsql`` ``.query`` string.  ``PLpgSQL_stmt_dynexecute``
  holds a function-call expression, not SQL, and is intentionally skipped.
* Schema-qualified references to ``pg_catalog`` / ``information_schema`` and
  references to objects not mentioned anywhere in the plan are treated as
  externally satisfied; they do not generate dependency edges.
* Statements that reference objects which are missing from both the plan and
  the live database pass through unchanged (known limitation: the failure
  surfaces as the native Postgres error at apply time).

Hard failures (nonzero exit, statement-level report):

* Dependency cycles.
* Top-level statement parse failure.
* Unknown plan-format version.
* Structurally malformed plan JSON.

The four failure classes above are reported distinctly.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict, deque
from pathlib import Path
from typing import Any, Iterable

import pglast
from pglast.enums import ObjectType

SUPPORTED_PLAN_VERSIONS = {"1.0.0"}

EXTERNAL_SCHEMAS = {"pg_catalog", "information_schema"}

# Object-type to dependency-kind mapping for COMMENT/GRANT statements.
# Where PostgreSQL namespaces overlap (e.g. tables/views/sequences) we use the
# same kind that the corresponding CREATE statement emits.
OBJECT_KIND_MAP: dict[int, str] = {
    ObjectType.OBJECT_TABLE: "table",
    ObjectType.OBJECT_VIEW: "table",
    ObjectType.OBJECT_SEQUENCE: "table",
    ObjectType.OBJECT_FUNCTION: "function",
    ObjectType.OBJECT_PROCEDURE: "function",
    ObjectType.OBJECT_ROUTINE: "function",
    ObjectType.OBJECT_INDEX: "index",
    ObjectType.OBJECT_TYPE: "type",
    ObjectType.OBJECT_TRIGGER: "trigger",
    ObjectType.OBJECT_COLUMN: "column",
}


# ---------------------------------------------------------------------------
# Error classes
# ---------------------------------------------------------------------------


class PlanReorderError(Exception):
    """Base class for reorderer errors."""

    def __init__(self, message: str, *, statements: list[dict[str, Any]] | None = None):
        super().__init__(message)
        self.message = message
        self.statements = statements or []


class PlanFormatError(PlanReorderError):
    """Plan JSON is structurally malformed or uses an unsupported version."""


class ParseError(PlanReorderError):
    """A top-level SQL statement could not be parsed."""


class CycleError(PlanReorderError):
    """The dependency graph contains a cycle."""


# ---------------------------------------------------------------------------
# Object naming helpers
# ---------------------------------------------------------------------------


def _obj(kind: str, name: str) -> str:
    return f"{kind}:{name}"


def _is_external_ref(schema: str | None, name: str) -> bool:
    """Return True if a schema-qualified reference is externally satisfied."""
    if schema in EXTERNAL_SCHEMAS:
        return True
    return False


def _type_name(names: Iterable[Any]) -> str | None:
    """Extract a normalized type name from a TypeName names tuple.

    Returns None for built-in catalog types (e.g. ``pg_catalog.int4``).
    """
    parts = []
    for item in names:
        sval = getattr(item, "sval", None)
        if sval is None:
            continue
        parts.append(sval)
    if not parts:
        return None
    if len(parts) == 2 and parts[0] in EXTERNAL_SCHEMAS:
        return None
    return parts[-1]


def _type_name_for_signature(type_name_node: Any) -> str | None:
    """Return a canonical type name suitable for a function signature identity.

    Unlike `_type_name`, catalog types are kept (with the ``pg_catalog.``
    prefix stripped) so that ``integer``, ``int``, and ``int4`` all collapse to
    the same identity.  Array bounds are appended as ``[]`` markers.
    """
    names = [getattr(n, "sval", None) for n in getattr(type_name_node, "names", [])]
    names = [n for n in names if n]
    if not names:
        return None
    if len(names) >= 2 and names[0] in EXTERNAL_SCHEMAS:
        names = names[1:]
    base = ".".join(names)
    array_bounds = getattr(type_name_node, "arrayBounds", None) or []
    if array_bounds:
        base += "[]" * len(array_bounds)
    return base


def _function_name(funcname: Iterable[Any]) -> str | None:
    parts = [getattr(p, "sval", None) for p in funcname]
    parts = [p for p in parts if p]
    if not parts:
        return None
    return parts[-1]


def _function_identity(name: str, arg_types: list[str]) -> str:
    """Build a dependency-graph identity for a function, including its signature."""
    if arg_types:
        return _obj("function", f"{name}({','.join(arg_types)})")
    return _obj("function", f"{name}()")


def _function_identity_from_create(stmt: Any) -> str | None:
    """Build a function identity from a CreateFunctionStmt."""
    name = _function_name(getattr(stmt, "funcname", []))
    if not name:
        return None
    arg_types: list[str] = []
    for param in getattr(stmt, "parameters", []) or []:
        arg_type = getattr(param, "argType", None)
        if arg_type is None:
            continue
        tname = _type_name_for_signature(arg_type)
        if tname:
            arg_types.append(tname)
    return _function_identity(name, arg_types)


def _function_identity_from_object_with_args(obj: Any) -> str | None:
    """Build a function identity from an ObjectWithArgs node (DROP/COMMENT/GRANT)."""
    name = _function_name(getattr(obj, "objname", []))
    if not name:
        return None
    arg_types: list[str] = []
    for arg in getattr(obj, "objargs", []) or []:
        tname = _type_name_for_signature(arg)
        if tname:
            arg_types.append(tname)
    return _function_identity(name, arg_types)


def _object_name_from_strings(parts: Iterable[Any], kind: str | None = None) -> str | None:
    """Join a tuple/list of String nodes into a dotted object name.

    Strips a leading schema qualifier so that schema-qualified references match
    the unqualified identities emitted by CREATE handlers (e.g. ``public.foo``
    becomes ``foo``).  References into external/system schemas are ignored.

    ``kind`` disambiguates multi-part unqualified names: column and trigger
    identities are ``table.name`` (two parts), so a schema is only stripped when
    there are three or more parts.
    """
    names = [getattr(p, "sval", None) for p in parts]
    names = [n for n in names if n]
    if not names:
        return None
    if names[0] in EXTERNAL_SCHEMAS:
        return None
    # Column and trigger identities are two-part (table.name) in unqualified
    # form; strip a leading schema only when there are 3+ parts.
    if kind in {"column", "trigger"}:
        if len(names) >= 3:
            names = names[1:]
        return ".".join(names)
    # Single-part objects (table, view, index, sequence, type): strip schema.
    if len(names) >= 2:
        names = names[1:]
    return ".".join(names)


# ---------------------------------------------------------------------------
# AST reference extraction
# ---------------------------------------------------------------------------


class _ReferenceExtractor:
    """Walk pglast AST nodes and collect referenced objects.

    Maintains a context of table aliases so that unqualified columns can be
    resolved to ``table.column`` when the table set is unambiguous.  The
    visitor uses stack discipline so nested subqueries do not leak context.
    """

    def __init__(self) -> None:
        self.refs: set[str] = set()
        self.table_aliases: dict[str, str] = {}
        self.table_stack: list[str] = []

    def _resolve_column(self, column: str, *, explicit_table: str | None = None) -> None:
        # Wildcards do not name a specific column; rely on table-level deps.
        if column == "*":
            if explicit_table is not None:
                self.refs.add(_obj("table", explicit_table))
            return
        if explicit_table is not None:
            # Resolve aliases to the underlying table so that ``ef.col`` where
            # ``ef`` aliases ``entity_facts`` records ``column:entity_facts.col``.
            table = self.table_aliases.get(explicit_table, explicit_table)
            self.refs.add(_obj("table", table))
            self.refs.add(_obj("column", f"{table}.{column}"))
            return
        if len(self.table_stack) == 1:
            table = self.table_stack[0]
            self.refs.add(_obj("table", table))
            self.refs.add(_obj("column", f"{table}.{column}"))
            return
        # Ambiguous unqualified column reference (0 or >1 tables in scope).
        # Do NOT emit speculative column: edges: a missing edge is preferable
        # to a wrong edge.  Table-level dependencies are already recorded by
        # the range vars in the FROM clause.

    def _range_var_name(self, node) -> str | None:
        """Return the normalized table/view name, or None for catalog refs."""
        schema = getattr(node, "schemaname", None)
        relname = getattr(node, "relname", None)
        if relname is None:
            return None
        if _is_external_ref(schema, relname):
            return None
        return relname

    def _visit_range_var(self, node) -> None:
        name = self._range_var_name(node)
        if name:
            self.refs.add(_obj("table", name))
            alias = getattr(node, "alias", None)
            if alias:
                # In current pglast versions aliasname is a plain str; older
                # versions may wrap it in a String node.  Accept both.
                alias_name = getattr(alias, "aliasname", None)
                if alias_name is not None and hasattr(alias_name, "sval"):
                    alias_name = alias_name.sval
                if alias_name:
                    self.table_aliases[alias_name] = name
            self.table_stack.append(name)

    def _visit_column_ref(self, node) -> None:
        fields = list(getattr(node, "fields", []))
        names = [getattr(f, "sval", None) for f in fields]
        names = [n for n in names if n is not None]
        if len(names) >= 2:
            table_or_alias = names[-2]
            column = names[-1]
            table = self.table_aliases.get(table_or_alias, table_or_alias)
            self._resolve_column(column, explicit_table=table)
        elif len(names) == 1:
            self._resolve_column(names[0])

    def _visit_func_call(self, node) -> None:
        funcname = getattr(node, "funcname", [])
        parts = [getattr(p, "sval", None) for p in funcname]
        parts = [p for p in parts if p]
        if parts and parts[0] not in EXTERNAL_SCHEMAS:
            # Ignore common function-call expressions that are not user functions.
            if parts[-1] not in {
                "format", "coalesce", "nullif", "greatest", "least",
                "now", "current_timestamp", "clock_timestamp",
            }:
                self.refs.add(_obj("function", parts[-1]))

    def _visit_type_name(self, node) -> None:
        tname = _type_name(getattr(node, "names", []))
        if tname:
            self.refs.add(_obj("type", tname))

    def _visit_type_cast(self, node) -> None:
        tname = _type_name(getattr(getattr(node, "typeName", None), "names", []))
        if tname:
            self.refs.add(_obj("type", tname))

    def _visit_select(self, node) -> None:
        """Visit SELECT with fromClause before targetList to establish context."""
        saved_stack = list(self.table_stack)
        saved_aliases = dict(self.table_aliases)
        for from_item in getattr(node, "fromClause", []) or []:
            self.visit(from_item)
        for attr in ("targetList", "whereClause", "groupClause", "havingClause",
                     "sortClause", "limitCount", "limitOffset"):
            self._visit_children(getattr(node, attr, None))
        self.table_stack = saved_stack
        self.table_aliases = saved_aliases

    def visit(self, node) -> None:
        if node is None:
            return
        if isinstance(node, (str, int, float, bool)):
            return

        name = node.__class__.__name__

        if name == "RangeVar":
            self._visit_range_var(node)
            return

        if name == "ColumnRef":
            self._visit_column_ref(node)
            return

        if name == "FuncCall":
            self._visit_func_call(node)
            self._visit_children(node)
            return

        if name == "TypeName":
            self._visit_type_name(node)
            return

        if name == "TypeCast":
            self._visit_type_cast(node)
            self._visit_children(node)
            return

        if name == "SelectStmt":
            self._visit_select(node)
            return

        self._visit_children(node)

    def _visit_children(self, node) -> None:
        if node is None:
            return
        if isinstance(node, (list, tuple)):
            for c in node:
                self.visit(c)
            return
        for attr in ("query", "stmt", "targetList", "fromClause", "whereClause",
                     "args", "arg", "raw_expr", "def_", "constraints", "tableElts",
                     "indexParams", "pktable", "fk_attrs", "pk_attrs", "body",
                     "expr", "val", "left", "right", "lexpr", "rexpr",
                     "larg", "rarg", "quals"):
            child = getattr(node, attr, None)
            if child is None:
                continue
            if isinstance(child, (list, tuple)):
                for c in child:
                    self.visit(c)
            else:
                self.visit(child)


# ---------------------------------------------------------------------------
# Statement-level analysis
# ---------------------------------------------------------------------------


def _extract_sql_refs(sql: str) -> set[str]:
    """Extract references from a SQL-language string."""
    extractor = _ReferenceExtractor()
    for raw_stmt in pglast.parse_sql(sql):
        extractor.visit(raw_stmt.stmt)
    return extractor.refs


def _extract_plpgsql_refs(sql: str) -> set[str]:
    """Extract references from a plpgsql CREATE FUNCTION statement.

    Best-effort: re-parse static query strings inside return/execsql nodes.
    Dynamic EXECUTE expressions are skipped.  Failures in inner re-parsing are
    swallowed; the function is ordered using whatever static refs we can find.
    """
    refs: set[str] = set()
    try:
        plpgsql = pglast.parse_plpgsql(sql)
    except Exception:
        return refs
    refs.update(_walk_plpgsql_statements(plpgsql))
    return refs


def _extract_sql_function_refs(create_stmt: Any, params: set[str]) -> set[str]:
    """Extract references from a SQL-language CREATE FUNCTION body string."""
    refs: set[str] = set()
    for option in getattr(create_stmt, "options", []):
        if getattr(option, "defname", None) != "as":
            continue
        arg = getattr(option, "arg", [])
        if not arg:
            continue
        body_text = getattr(arg[0], "sval", "") if hasattr(arg, "__getitem__") else ""
        if not body_text:
            continue
        try:
            body_refs = _extract_sql_refs(body_text)
        except Exception:
            continue
        # Filter out references that match function parameter names.
        filtered: set[str] = set()
        for ref in body_refs:
            if ref.startswith("column:"):
                _, col_spec = ref.split(":", 1)
                if "." in col_spec:
                    col_name = col_spec.split(".", 1)[1]
                    if col_name in params:
                        continue
            filtered.add(ref)
        refs.update(filtered)
    return refs


def _walk_plpgsql_statements(plpgsql: Any) -> set[str]:
    """Recursively walk parsed plpgsql and re-parse static SQL fragments."""
    refs: set[str] = set()
    nodes = list(plpgsql) if isinstance(plpgsql, (list, tuple)) else [plpgsql]
    while nodes:
        node = nodes.pop()
        if not isinstance(node, dict):
            continue
        for key, value in node.items():
            if key == "PLpgSQL_stmt_dynexecute":
                # Function-call expression, not SQL; do NOT re-parse.
                continue
            if key in {"PLpgSQL_stmt_return", "PLpgSQL_stmt_execsql"}:
                # The query lives either under .query.PLpgSQL_expr.query
                # (execsql) or .expr.PLpgSQL_expr.query (return).
                query = None
                for path in (
                    ("query", "PLpgSQL_expr", "query"),
                    ("expr", "PLpgSQL_expr", "query"),
                ):
                    cur = value
                    for p in path:
                        cur = cur.get(p) if isinstance(cur, dict) else None
                        if cur is None:
                            break
                    if cur is not None:
                        query = cur
                        break
                if query:
                    try:
                        refs.update(_extract_sql_refs(query))
                    except Exception:
                        pass
                continue
            if isinstance(value, dict):
                nodes.append(value)
            elif isinstance(value, list):
                nodes.extend(value)
    return refs


def _statement_kind_from_create(create_stmt: Any) -> str:
    """Map a CreateStmt/ViewStmt/IndexStmt/etc. to a dependency kind."""
    name_map = {
        "CreateStmt": "table",
        "ViewStmt": "table",
        "IndexStmt": "index",
        "CreateFunctionStmt": "function",
        "CreateTrigStmt": "trigger",
        "CreateEnumStmt": "type",
    }
    return name_map.get(create_stmt.__class__.__name__, "table")


def analyze_statement(sql: str) -> dict[str, Any]:
    """Return dependency metadata for a single SQL statement.

    Result keys:
      - defines:   set of objects created/altered/dropped by this statement
      - refs:      set of objects referenced (dependencies)
      - is_drop:   True if this is a DROP-type operation
      - non_txn:   True if the step cannot run inside a transaction
    """
    result: dict[str, Any] = {
        "defines": set(),
        "refs": set(),
        "is_drop": False,
        "non_txn": False,
    }

    try:
        raw_stmts = list(pglast.parse_sql(sql))
    except Exception as exc:
        raise ParseError(
            f"Failed to parse statement: {exc}",
            statements=[{"sql": sql}],
        ) from exc

    if not raw_stmts:
        return result

    raw = raw_stmts[0]
    stmt = raw.stmt
    class_name = stmt.__class__.__name__

    # ------------------------------------------------------------------
    # DROP statements
    # ------------------------------------------------------------------
    if class_name == "DropStmt":
        result["is_drop"] = True
        remove_type = getattr(stmt, "removeType", None)
        kind_map = {
            "OBJECT_TABLE": "table",
            "OBJECT_VIEW": "table",
            "OBJECT_FUNCTION": "function",
            "OBJECT_TRIGGER": "trigger",
            "OBJECT_INDEX": "index",
            "OBJECT_TYPE": "type",
            "OBJECT_SEQUENCE": "sequence",
        }
        remove_type_name = getattr(remove_type, "name", str(remove_type)) if remove_type is not None else ""
        kind = kind_map.get(remove_type_name, "table")
        for obj in getattr(stmt, "objects", []) or []:
            if obj.__class__.__name__ == "ObjectWithArgs":
                # DROP FUNCTION / PROCEDURE includes the signature.
                identity = _function_identity_from_object_with_args(obj)
                if identity:
                    result["defines"].add(identity)
            else:
                name = _object_name_from_strings(obj, kind=kind)
                if name:
                    result["defines"].add(_obj(kind, name))
        return result

    # ------------------------------------------------------------------
    # ALTER TABLE
    # ------------------------------------------------------------------
    if class_name == "AlterTableStmt":
        relation = getattr(stmt, "relation", None)
        table = getattr(relation, "relname", None) if relation else None
        objtype = getattr(stmt, "objtype", None)
        cmds = getattr(stmt, "cmds", []) or []
        has_owner_change = any(
            getattr(getattr(cmd, "subtype", None), "name", "") == "AT_ChangeOwner"
            for cmd in cmds
        )
        if table:
            if has_owner_change:
                # OWNER TO is a metadata change; it depends on the object.
                kind = OBJECT_KIND_MAP.get(objtype, "table")
                result["refs"].add(_obj(kind, table))
            else:
                result["defines"].add(_obj("table", table))
        for cmd in cmds:
            subtype = getattr(cmd, "subtype", None)
            subtype_name = getattr(subtype, "name", str(subtype)) if subtype is not None else ""

            if subtype_name == "AT_AddColumn":
                coldef = getattr(cmd, "def_", None)
                if coldef and table:
                    colname = getattr(coldef, "colname", None)
                    if colname:
                        result["defines"].add(_obj("column", f"{table}.{colname}"))
                result["refs"].update(_extract_refs_from_node(coldef))

            elif subtype_name == "AT_DropColumn":
                result["is_drop"] = True
                colname = getattr(cmd, "name", None)
                if table and colname:
                    result["defines"].add(_obj("column", f"{table}.{colname}"))

            elif subtype_name == "AT_AddConstraint":
                con = getattr(cmd, "def_", None)
                if con:
                    con_type = getattr(con, "contype", None)
                    con_type_name = getattr(con_type, "name", str(con_type)) if con_type is not None else ""
                    if con_type_name == "CONSTR_FOREIGN":
                        pktable = getattr(con, "pktable", None)
                        ref_table = getattr(pktable, "relname", None) if pktable else None
                        if ref_table:
                            result["refs"].add(_obj("table", ref_table))
                            for attr in getattr(con, "pk_attrs", []):
                                col = getattr(attr, "sval", None)
                                if col:
                                    result["refs"].add(_obj("column", f"{ref_table}.{col}"))
                    if con_type_name == "CONSTR_CHECK" and table:
                        expr = getattr(con, "raw_expr", None) or getattr(con, "expr", None)
                        if expr is not None:
                            result["refs"].update(_extract_refs_with_table_context(expr, table))
                    result["refs"].update(_extract_refs_from_node(con))

            elif subtype_name == "AT_DropConstraint":
                result["is_drop"] = True
                conname = getattr(cmd, "name", None)
                if table and conname:
                    result["defines"].add(_obj("constraint", f"{table}.{conname}"))
        return result

    # ------------------------------------------------------------------
    # CREATE TABLE
    # ------------------------------------------------------------------
    if class_name == "CreateStmt":
        relation = getattr(stmt, "relation", None)
        table = getattr(relation, "relname", None) if relation else None
        if table:
            result["defines"].add(_obj("table", table))
        for elt in getattr(stmt, "tableElts", []):
            elt_class = elt.__class__.__name__
            if elt_class == "ColumnDef":
                colname = getattr(elt, "colname", None)
                if table and colname:
                    result["defines"].add(_obj("column", f"{table}.{colname}"))
                result["refs"].update(_extract_refs_from_node(elt))
            elif elt_class == "Constraint":
                con_type = getattr(elt, "contype", None)
                con_type_name = getattr(con_type, "name", str(con_type)) if con_type is not None else ""
                if con_type_name == "CONSTR_FOREIGN":
                    pktable = getattr(elt, "pktable", None)
                    ref_table = getattr(pktable, "relname", None) if pktable else None
                    if ref_table:
                        result["refs"].add(_obj("table", ref_table))
                        for attr in getattr(elt, "pk_attrs", []):
                            col = getattr(attr, "sval", None)
                            if col:
                                result["refs"].add(_obj("column", f"{ref_table}.{col}"))
                if con_type_name == "CONSTR_CHECK" and table:
                    expr = getattr(elt, "raw_expr", None) or getattr(elt, "expr", None)
                    if expr is not None:
                        result["refs"].update(_extract_refs_with_table_context(expr, table))
                result["refs"].update(_extract_refs_from_node(elt))
        return result

    # ------------------------------------------------------------------
    # CREATE VIEW / CREATE MATERIALIZED VIEW
    # ------------------------------------------------------------------
    if class_name == "ViewStmt":
        view = getattr(stmt, "view", None)
        view_name = getattr(view, "relname", None) if view else None
        if view_name:
            # Views occupy the same namespace as tables for dependency ordering.
            result["defines"].add(_obj("table", view_name))
        result["refs"].update(_extract_refs_from_node(getattr(stmt, "query", None)))
        return result

    if class_name == "CreateTableAsStmt":
        # CREATE MATERIALIZED VIEW stores its target in into.rel.
        into = getattr(stmt, "into", None)
        relation = getattr(into, "rel", None) if into else None
        mv_name = getattr(relation, "relname", None) if relation else None
        if mv_name:
            # Materialized views share the table namespace.
            result["defines"].add(_obj("table", mv_name))
        query = getattr(stmt, "query", None)
        if query is not None:
            result["refs"].update(_extract_refs_from_node(query))
        return result

    # ------------------------------------------------------------------
    # CREATE INDEX
    # ------------------------------------------------------------------
    if class_name == "IndexStmt":
        idxname = getattr(stmt, "idxname", None)
        relation = getattr(stmt, "relation", None)
        table = getattr(relation, "relname", None) if relation else None
        if idxname:
            result["defines"].add(_obj("index", idxname))
        if table:
            result["refs"].add(_obj("table", table))
            for param in getattr(stmt, "indexParams", []):
                col = getattr(param, "name", None)
                if col:
                    result["refs"].add(_obj("column", f"{table}.{col}"))
                # Expression indexes: extract columns from the expression.
                expr = getattr(param, "expr", None)
                if expr is not None:
                    result["refs"].update(_extract_refs_with_table_context(expr, table))
            # Partial-index WHERE clauses reference columns too.
            where_clause = getattr(stmt, "whereClause", None)
            if where_clause is not None:
                result["refs"].update(_extract_refs_with_table_context(where_clause, table))
        if getattr(stmt, "concurrent", False):
            result["non_txn"] = True
        return result

    # ------------------------------------------------------------------
    # CREATE FUNCTION / CREATE PROCEDURE
    # ------------------------------------------------------------------
    if class_name == "CreateFunctionStmt":
        identity = _function_identity_from_create(stmt)
        if identity:
            result["defines"].add(identity)
        params: set[str] = set()
        for param in getattr(stmt, "parameters", []) or []:
            pname = getattr(param, "name", None)
            if pname:
                params.add(pname)
            # Parameter types are dependencies (e.g. a user-defined enum).
            arg_type = getattr(param, "argType", None)
            if arg_type:
                tname = _type_name(getattr(arg_type, "names", []))
                if tname:
                    result["refs"].add(_obj("type", tname))
        # Return type is also a dependency.
        return_type = getattr(stmt, "returnType", None)
        if return_type:
            tname = _type_name(getattr(return_type, "names", []))
            if tname:
                result["refs"].add(_obj("type", tname))
        language = None
        for option in getattr(stmt, "options", []) or []:
            if getattr(option, "defname", None) == "language":
                language = getattr(getattr(option, "arg", None), "sval", None)
        if language == "plpgsql":
            result["refs"].update(_extract_plpgsql_refs(sql))
        else:
            # SQL-language body parsed from the DefElem 'as' string.
            result["refs"].update(_extract_sql_function_refs(stmt, params))
        return result

    # ------------------------------------------------------------------
    # CREATE TRIGGER
    # ------------------------------------------------------------------
    if class_name == "CreateTrigStmt":
        trigname = getattr(stmt, "trigname", None)
        relation = getattr(stmt, "relation", None)
        table = getattr(relation, "relname", None) if relation else None
        if trigname and table:
            result["defines"].add(_obj("trigger", f"{table}.{trigname}"))
        if table:
            result["refs"].add(_obj("table", table))
        funcname = _function_name(getattr(stmt, "funcname", []))
        if funcname:
            # Trigger functions are referenced by name only; the signature is
            # implicit in the trigger context, so we keep the simple identity
            # and resolve it via the function-name fallback in the graph builder.
            result["refs"].add(_obj("function", funcname))
        return result

    # ------------------------------------------------------------------
    # CREATE TYPE (enum)
    # ------------------------------------------------------------------
    if class_name == "CreateEnumStmt":
        type_name = _type_name(getattr(stmt, "typeName", []))
        if type_name:
            result["defines"].add(_obj("type", type_name))
        return result

    # ------------------------------------------------------------------
    # CREATE SEQUENCE
    # ------------------------------------------------------------------
    if class_name == "CreateSeqStmt":
        seq = getattr(stmt, "sequence", None)
        seq_name = getattr(seq, "relname", None) if seq else None
        if seq_name:
            # Sequences share a namespace with tables in PostgreSQL.
            result["defines"].add(_obj("table", seq_name))
        return result

    # ------------------------------------------------------------------
    # ALTER ... OWNER TO
    # ------------------------------------------------------------------
    if class_name == "AlterOwnerStmt":
        objtype = getattr(stmt, "objectType", None)
        kind = OBJECT_KIND_MAP.get(objtype, "table")
        obj = getattr(stmt, "object", None)
        if obj is not None:
            if obj.__class__.__name__ == "ObjectWithArgs":
                identity = _function_identity_from_object_with_args(obj)
                if identity:
                    result["refs"].add(identity)
            else:
                name = _object_name_from_strings(obj, kind=kind)
                if name:
                    result["refs"].add(_obj(kind, name))
        return result

    # ------------------------------------------------------------------
    # SECURITY LABEL ON <object>
    # ------------------------------------------------------------------
    if class_name == "SecLabelStmt":
        objtype = getattr(stmt, "objtype", None)
        kind = OBJECT_KIND_MAP.get(objtype, "table")
        obj = getattr(stmt, "object", None)
        if obj is not None:
            if obj.__class__.__name__ == "ObjectWithArgs":
                identity = _function_identity_from_object_with_args(obj)
                if identity:
                    result["refs"].add(identity)
            else:
                name = _object_name_from_strings(obj, kind=kind)
                if name:
                    result["refs"].add(_obj(kind, name))
        return result

    # ------------------------------------------------------------------
    # COMMENT ON <object>
    # ------------------------------------------------------------------
    if class_name == "CommentStmt":
        objtype = getattr(stmt, "objtype", None)
        kind = OBJECT_KIND_MAP.get(objtype) if objtype is not None else None
        if kind:
            obj = getattr(stmt, "object", None)
            if obj is not None:
                if obj.__class__.__name__ == "ObjectWithArgs":
                    identity = _function_identity_from_object_with_args(obj)
                    if identity:
                        result["refs"].add(identity)
                elif obj.__class__.__name__ == "TypeName":
                    type_name = _object_name_from_strings(getattr(obj, "names", []), kind=kind)
                    if type_name:
                        result["refs"].add(_obj(kind, type_name))
                else:
                    name = _object_name_from_strings(obj, kind=kind)
                    if name:
                        result["refs"].add(_obj(kind, name))
        return result

    # ------------------------------------------------------------------
    # GRANT / REVOKE
    # ------------------------------------------------------------------
    if class_name in {"GrantStmt", "RevokeStmt"}:
        objtype = getattr(stmt, "objtype", None)
        kind = OBJECT_KIND_MAP.get(objtype) if objtype is not None else "table"
        for obj in getattr(stmt, "objects", []) or []:
            if obj.__class__.__name__ == "ObjectWithArgs":
                identity = _function_identity_from_object_with_args(obj)
                if identity:
                    result["refs"].add(identity)
            elif obj.__class__.__name__ == "RangeVar":
                name = getattr(obj, "relname", None)
                schema = getattr(obj, "schemaname", None)
                if name and not _is_external_ref(schema, name):
                    result["refs"].add(_obj(kind, name))
                    for priv in getattr(stmt, "privileges", []):
                        cols = getattr(priv, "cols", []) or []
                        for col in cols:
                            cname = getattr(col, "sval", None)
                            if cname:
                                result["refs"].add(_obj("column", f"{name}.{cname}"))
            elif obj.__class__.__name__ == "TypeName":
                type_name = _object_name_from_strings(getattr(obj, "names", []), kind=kind)
                if type_name:
                    result["refs"].add(_obj(kind, type_name))
            else:
                name = _object_name_from_strings(obj, kind=kind)
                if name:
                    result["refs"].add(_obj(kind, name))
        return result

    # ------------------------------------------------------------------
    # Generic fallback: extract whatever refs we can find.
    # ------------------------------------------------------------------
    result["refs"].update(_extract_refs_from_node(stmt))
    return result


def _extract_refs_from_node(node: Any) -> set[str]:
    """Extract references from an arbitrary AST node."""
    extractor = _ReferenceExtractor()
    extractor.visit(node)
    return extractor.refs


def _extract_refs_with_table_context(node: Any, table: str) -> set[str]:
    """Extract references assuming unqualified columns belong to ``table``."""
    extractor = _ReferenceExtractor()
    extractor.table_stack.append(table)
    extractor.visit(node)
    return extractor.refs


# ---------------------------------------------------------------------------
# Plan loading / saving / validation
# ---------------------------------------------------------------------------


def _validate_plan(data: Any) -> None:
    """Validate a parsed plan JSON object in memory.

    ``groups`` may be absent, ``null``, or an array; all three are treated as
    a valid empty plan (no statements to reorder).  Any other type for
    ``groups`` is still a structural error.
    """
    if not isinstance(data, dict):
        raise PlanFormatError("Plan JSON must be an object")

    required_keys = {"version", "pgschema_version", "source_fingerprint"}
    missing = required_keys - set(data.keys())
    if missing:
        raise PlanFormatError(f"Malformed plan JSON: missing keys {sorted(missing)}")

    version = data.get("version")
    if version not in SUPPORTED_PLAN_VERSIONS:
        raise PlanFormatError(
            f"Unsupported plan format version {version!r}; "
            f"supported versions: {sorted(SUPPORTED_PLAN_VERSIONS)}"
        )

    groups = data.get("groups")
    if groups is None:
        return
    if not isinstance(groups, list):
        raise PlanFormatError("Malformed plan JSON: 'groups' must be an array")

    for gidx, group in enumerate(groups):
        if not isinstance(group, dict) or not isinstance(group.get("steps"), list):
            raise PlanFormatError(
                f"Malformed plan JSON: groups[{gidx}] must be an object with a 'steps' array"
            )


def load_plan(path: Path | str) -> dict[str, Any]:
    """Load and validate a pgschema plan JSON file."""
    path = Path(path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise PlanFormatError(f"Invalid JSON in plan file {path}: {exc}") from exc
    except FileNotFoundError as exc:
        raise PlanFormatError(f"Plan file not found: {path}") from exc

    _validate_plan(data)
    return data


def save_plan(plan: dict[str, Any], path: Path | str) -> None:
    Path(path).write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Dependency graph + topological sort
# ---------------------------------------------------------------------------


def _object_dependency_map(analyses: list[dict[str, Any]]) -> dict[str, set[str]]:
    """Build object-level dependency map from all non-DROP analyses.

    For each object D defined by a non-DROP statement, record the set of
    objects O it depends on.  Self-dependencies (D == O) are skipped: a
    statement can never genuinely depend on itself, and retaining them
    causes false statement-level self-loops via the DROP reverse-dependency
    rule (nova-mind#605).
    """
    obj_deps: dict[str, set[str]] = defaultdict(set)
    for analysis in analyses:
        if analysis["is_drop"]:
            continue
        for defined in analysis["defines"]:
            for ref in analysis["refs"]:
                if ref == defined:
                    continue
                obj_deps[defined].add(ref)
    return obj_deps


def _build_statement_graph(
    steps: list[dict[str, Any]],
    analyses: list[dict[str, Any]],
) -> tuple[dict[int, set[int]], dict[int, int]]:
    """Build statement-level dependency graph and in-degree counts."""
    obj_deps = _object_dependency_map(analyses)

    # Map each defined object to the earliest statement that defines it, plus
    # a separate map to any DROP statement that drops it (used for DROP-DROP
    # reverse-order edges when the same object is both created and dropped).
    object_to_statement: dict[str, int] = {}
    object_to_drop_statement: dict[str, int] = {}
    for idx, analysis in enumerate(analyses):
        for obj in analysis["defines"]:
            if obj not in object_to_statement:
                object_to_statement[obj] = idx
            if analysis["is_drop"] and obj not in object_to_drop_statement:
                object_to_drop_statement[obj] = idx

    # Function calls in views/bodies/triggers are recorded by simple name only
    # (the AST does not carry argument type information for a call site).  When
    # the plan contains exactly one signature-aware identity for that name,
    # resolve the simple-name reference to it.
    simple_func_to_identity: dict[str, str] = {}
    for obj in object_to_statement:
        if obj.startswith("function:") and "(" not in obj:
            continue
        if obj.startswith("function:"):
            simple_name = obj.split("(", 1)[0]
            if simple_name not in simple_func_to_identity:
                simple_func_to_identity[simple_name] = obj
            else:
                simple_func_to_identity[simple_name] = ""

    def _resolve_ref(ref: str) -> int | None:
        if ref in object_to_statement:
            return object_to_statement[ref]
        if ref.startswith("function:") and "(" not in ref:
            identity = simple_func_to_identity.get(ref)
            if identity:
                return object_to_statement.get(identity)
        return None

    n = len(steps)
    graph: dict[int, set[int]] = {i: set() for i in range(n)}

    for idx, analysis in enumerate(analyses):
        if analysis["is_drop"]:
            # DROP statement idx drops object O. Any other DROP statement that
            # drops an object depending on O must run first, so O's drop must
            # come after the dependent's drop: edge dependent_drop -> this_drop.
            for obj in analysis["defines"]:
                for dependent_obj, deps in obj_deps.items():
                    if obj in deps:
                        other_idx = object_to_drop_statement.get(dependent_obj)
                        if other_idx is not None:
                            graph[other_idx].add(idx)
            # DROP-and-recreate: a non-DROP statement defining the same object
            # must run after the DROP.
            for obj in analysis["defines"]:
                for other_idx, other_analysis in enumerate(analyses):
                    if other_idx == idx:
                        continue
                    if not other_analysis["is_drop"] and obj in other_analysis["defines"]:
                        graph[idx].add(other_idx)
        else:
            # Non-DROP statement depends on non-DROP statements that define
            # objects it references.  Dependencies on objects being dropped in
            # the same plan are a user conflict; we do not try to order them.
            for ref in analysis["refs"]:
                provider_idx = _resolve_ref(ref)
                if provider_idx is not None and provider_idx != idx:
                    if not analyses[provider_idx]["is_drop"]:
                        # T defines O, S references O => T must come before S.
                        graph[provider_idx].add(idx)

    in_degree = {i: 0 for i in range(n)}
    for src, targets in graph.items():
        for target in targets:
            in_degree[target] += 1

    return graph, in_degree


def _topological_sort(
    steps: list[dict[str, Any]],
    analyses: list[dict[str, Any]],
) -> list[int]:
    """Kahn's algorithm with stable tie-breaking preserving input order.

    The input order is the original step order across all groups flattened.
    At each iteration the ready node with the smallest original index is
    chosen, which keeps independent statements in their original relative
    position whenever dependencies allow.
    """
    graph, in_degree = _build_statement_graph(steps, analyses)
    n = len(steps)

    ready = sorted(i for i in range(n) if in_degree[i] == 0)
    order: list[int] = []

    while ready:
        node = ready.pop(0)
        order.append(node)
        for target in sorted(graph[node]):
            in_degree[target] -= 1
            if in_degree[target] == 0:
                ready.append(target)
                ready.sort()

    if len(order) != n:
        # Cycle detected: collect remaining nodes for the diagnostic.
        remaining = [i for i in range(n) if i not in order]
        raise CycleError(
            "Dependency cycle detected between statements",
            statements=[{"sql": steps[i]["sql"], "index": i} for i in remaining],
        )

    return order


# ---------------------------------------------------------------------------
# Group restructuring
# ---------------------------------------------------------------------------


def _flatten_steps(plan: dict[str, Any]) -> list[dict[str, Any]]:
    """Flatten all steps from all groups, preserving group index for stability."""
    flat: list[dict[str, Any]] = []
    groups = plan.get("groups") or []
    for gidx, group in enumerate(groups):
        for sidx, step in enumerate(group["steps"]):
            enriched = dict(step)
            enriched["_group_index"] = gidx
            enriched["_step_index"] = sidx
            flat.append(enriched)
    return flat


def _rebuild_groups(
    ordered_steps: list[dict[str, Any]],
    analyses: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Rebuild groups respecting directive/non-transactional isolation.

    Directive-free transactional steps are merged into a single atomic group.
    Directive-bearing and non-transactional steps stay isolated in their own
    groups, with their relative input order preserved.
    """
    transactional: list[dict[str, Any]] = []
    isolated_groups: list[list[dict[str, Any]]] = []

    for step in ordered_steps:
        analysis = analyses[step["_original_index"]]
        has_directive = step.get("directive") is not None
        if has_directive or analysis["non_txn"]:
            # If we have accumulated transactional steps, flush them first so
            # the isolated step lands after them in the new group order.
            if transactional:
                isolated_groups.append(transactional)
                transactional = []
            isolated_groups.append([step])
        else:
            transactional.append(step)

    if transactional:
        isolated_groups.append(transactional)

    groups: list[dict[str, Any]] = []
    for bucket in isolated_groups:
        group: dict[str, Any] = {"steps": []}
        for step in bucket:
            clean = {k: v for k, v in step.items() if not k.startswith("_")}
            group["steps"].append(clean)
        groups.append(group)

    return groups


# ---------------------------------------------------------------------------
# Main reorderer entry point
# ---------------------------------------------------------------------------


def reorder_plan(plan: dict[str, Any]) -> dict[str, Any]:
    """Return a new plan with reordered groups/steps.

    The top-level verbatim fields are preserved exactly; only ``groups`` is
    rewritten.  A missing or ``null`` ``groups`` is normalized to an empty
    array and returned with all metadata verbatim.
    """
    _validate_plan(plan)
    flat = _flatten_steps(plan)
    if not flat:
        return {
            "version": plan["version"],
            "pgschema_version": plan["pgschema_version"],
            "created_at": plan.get("created_at"),
            "source_fingerprint": plan["source_fingerprint"],
            "groups": [],
        }

    analyses: list[dict[str, Any]] = []
    for step in flat:
        analysis = analyze_statement(step["sql"])
        analyses.append(analysis)

    for idx, step in enumerate(flat):
        step["_original_index"] = idx

    order = _topological_sort(flat, analyses)
    ordered_steps = [flat[i] for i in order]
    new_groups = _rebuild_groups(ordered_steps, analyses)

    new_plan = {
        "version": plan["version"],
        "pgschema_version": plan["pgschema_version"],
        "created_at": plan.get("created_at"),
        "source_fingerprint": plan["source_fingerprint"],
        "groups": new_groups,
    }
    return new_plan


def validate_plan_invariants(plan: dict[str, Any]) -> None:
    """Verify that the reordered plan respects all extracted dependencies.

    For every dependency edge between two statements, the prerequisite must
    appear earlier in the flattened group/step order than the dependent.  This
    is the invariant the reordered output must satisfy regardless of group
    boundaries.

    Additionally checks a stricter column-level invariant: a statement that
    references ``table.column`` must not appear before the (non-DROP)
    statement that creates that column.  This catches missing view->column
    edges even if the main graph builder has a subtle identity mismatch.
    """
    flat = _flatten_steps(plan)
    analyses = [analyze_statement(step["sql"]) for step in flat]

    # Graph invariant: every edge's source must precede its target.
    graph, _ = _build_statement_graph(flat, analyses)
    for src, targets in graph.items():
        for dst in targets:
            if src >= dst:
                raise PlanReorderError(
                    f"Invariant violation: statement {src} must precede statement {dst}",
                    statements=[
                        {"sql": flat[src]["sql"], "index": src},
                        {"sql": flat[dst]["sql"], "index": dst},
                    ],
                )

    # Column invariant: every referenced column is defined no later than the
    # referencing statement (self-references inside CREATE TABLE are fine).
    column_def_index: dict[str, int] = {}
    for idx, analysis in enumerate(analyses):
        if analysis["is_drop"]:
            continue
        for defined in analysis["defines"]:
            if defined.startswith("column:"):
                # Keep the earliest definition index.
                if defined not in column_def_index:
                    column_def_index[defined] = idx

    for idx, analysis in enumerate(analyses):
        if analysis["is_drop"]:
            continue
        for ref in analysis["refs"]:
            if not ref.startswith("column:"):
                continue
            def_idx = column_def_index.get(ref)
            if def_idx is not None and def_idx > idx:
                raise PlanReorderError(
                    f"Invariant violation: statement {idx} references column "
                    f"{ref.split(':', 1)[1]} before it is defined at statement {def_idx}",
                    statements=[
                        {"sql": flat[def_idx]["sql"], "index": def_idx},
                        {"sql": flat[idx]["sql"], "index": idx},
                    ],
                )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _format_diagnostic(error: PlanReorderError) -> str:
    lines = [f"ERROR: {error.message}"]
    for stmt in error.statements:
        idx = stmt.get("index")
        sql = stmt.get("sql", "")
        if idx is not None:
            lines.append(f"  statement index: {idx}")
        if sql:
            lines.append(f"  SQL: {sql}")
    lines.append(
        "Suggested manual resolution: inspect the reported statements, "
        "resolve the cycle or syntax issue, and re-run the installer."
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, help="Input pgschema plan JSON")
    parser.add_argument("--output", required=True, help="Output reordered plan JSON")
    args = parser.parse_args(argv)

    try:
        plan = load_plan(args.plan)
        new_plan = reorder_plan(plan)
    except PlanFormatError as exc:
        print(_format_diagnostic(exc), file=sys.stderr)
        return 2
    except ParseError as exc:
        print(_format_diagnostic(exc), file=sys.stderr)
        return 3
    except CycleError as exc:
        print(_format_diagnostic(exc), file=sys.stderr)
        return 4

    save_plan(new_plan, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
