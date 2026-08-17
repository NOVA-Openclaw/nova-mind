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

SUPPORTED_PLAN_VERSIONS = {"1.0.0"}

EXTERNAL_SCHEMAS = {"pg_catalog", "information_schema"}


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
        if explicit_table is not None:
            self.refs.add(_obj("table", explicit_table))
            self.refs.add(_obj("column", f"{explicit_table}.{column}"))
            return
        if len(self.table_stack) == 1:
            table = self.table_stack[0]
            self.refs.add(_obj("table", table))
            self.refs.add(_obj("column", f"{table}.{column}"))
        elif column != "*":
            # Ambiguous or parameter reference; record a weak column ref only.
            for table in self.table_stack:
                self.refs.add(_obj("column", f"{table}.{column}"))

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
                alias_name = getattr(getattr(alias, "aliasname", None), "sval", None)
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
                     "expr", "val", "left", "right"):
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


def _function_name(funcname: Iterable[Any]) -> str | None:
    parts = [getattr(p, "sval", None) for p in funcname]
    parts = [p for p in parts if p]
    if not parts:
        return None
    return parts[-1]


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
        for obj_list in getattr(stmt, "objects", []):
            name_parts = [getattr(p, "sval", None) for p in obj_list]
            name_parts = [p for p in name_parts if p]
            if name_parts:
                result["defines"].add(_obj(kind, name_parts[-1]))
        return result

    # ------------------------------------------------------------------
    # ALTER TABLE
    # ------------------------------------------------------------------
    if class_name == "AlterTableStmt":
        relation = getattr(stmt, "relation", None)
        table = getattr(relation, "relname", None) if relation else None
        if table:
            result["defines"].add(_obj("table", table))
        for cmd in getattr(stmt, "cmds", []):
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
                result["refs"].update(_extract_refs_from_node(elt))
        return result

    # ------------------------------------------------------------------
    # CREATE VIEW
    # ------------------------------------------------------------------
    if class_name == "ViewStmt":
        view = getattr(stmt, "view", None)
        view_name = getattr(view, "relname", None) if view else None
        if view_name:
            # Views occupy the same namespace as tables for dependency ordering.
            result["defines"].add(_obj("table", view_name))
        result["refs"].update(_extract_refs_from_node(getattr(stmt, "query", None)))
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
        if getattr(stmt, "concurrent", False):
            result["non_txn"] = True
        return result

    # ------------------------------------------------------------------
    # CREATE FUNCTION / CREATE PROCEDURE
    # ------------------------------------------------------------------
    if class_name == "CreateFunctionStmt":
        funcname = _function_name(getattr(stmt, "funcname", []))
        if funcname:
            result["defines"].add(_obj("function", funcname))
        params: set[str] = set()
        for param in getattr(stmt, "parameters", []):
            pname = getattr(param, "name", None)
            if pname:
                params.add(pname)
        language = None
        for option in getattr(stmt, "options", []):
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
    # GRANT / REVOKE
    # ------------------------------------------------------------------
    if class_name in {"GrantStmt", "RevokeStmt"}:
        for obj in getattr(stmt, "objects", []):
            name = getattr(obj, "relname", None)
            schema = getattr(obj, "schemaname", None)
            if name and not _is_external_ref(schema, name):
                result["refs"].add(_obj("table", name))
                for priv in getattr(stmt, "privileges", []):
                    cols = getattr(priv, "cols", []) or []
                    for col in cols:
                        cname = getattr(col, "sval", None)
                        if cname:
                            result["refs"].add(_obj("column", f"{name}.{cname}"))
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


# ---------------------------------------------------------------------------
# Plan loading / saving / validation
# ---------------------------------------------------------------------------


def _validate_plan(data: Any) -> None:
    """Validate a parsed plan JSON object in memory."""
    if not isinstance(data, dict):
        raise PlanFormatError("Plan JSON must be an object")

    required_keys = {"version", "pgschema_version", "source_fingerprint", "groups"}
    missing = required_keys - set(data.keys())
    if missing:
        raise PlanFormatError(f"Malformed plan JSON: missing keys {sorted(missing)}")

    version = data.get("version")
    if version not in SUPPORTED_PLAN_VERSIONS:
        raise PlanFormatError(
            f"Unsupported plan format version {version!r}; "
            f"supported versions: {sorted(SUPPORTED_PLAN_VERSIONS)}"
        )

    if not isinstance(data.get("groups"), list):
        raise PlanFormatError("Malformed plan JSON: 'groups' must be an array")

    for gidx, group in enumerate(data["groups"]):
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
    objects O it depends on.
    """
    obj_deps: dict[str, set[str]] = defaultdict(set)
    for analysis in analyses:
        if analysis["is_drop"]:
            continue
        for defined in analysis["defines"]:
            for ref in analysis["refs"]:
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
                provider_idx = object_to_statement.get(ref)
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
    """
    graph, in_degree = _build_statement_graph(steps, analyses)
    n = len(steps)

    # Stable queue: process nodes with in-degree 0 in input order.
    queue = deque(sorted([i for i in range(n) if in_degree[i] == 0]))
    order: list[int] = []

    while queue:
        node = queue.popleft()
        order.append(node)
        for target in sorted(graph[node]):
            in_degree[target] -= 1
            if in_degree[target] == 0:
                queue.append(target)

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
    for gidx, group in enumerate(plan["groups"]):
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
    rewritten.
    """
    _validate_plan(plan)
    flat = _flatten_steps(plan)
    if not flat:
        return plan

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
