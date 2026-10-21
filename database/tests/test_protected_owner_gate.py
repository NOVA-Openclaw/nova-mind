"""Tests for grant_reconcile_gate.py protected-owner gate (#756)."""

import io
import json
import sys
from unittest.mock import MagicMock, patch

import pytest

import database.grant_reconcile_gate as grg


class _FakeCursor:
    """Minimal cursor stand-in for _check_cmd."""

    def __init__(self):
        self.results = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, query, params=None):
        pass

    def fetchone(self):
        return self.results.pop(0) if self.results else None

    def fetchall(self):
        return self.results.pop(0) if self.results else []


class _FakeConn:
    def __init__(self):
        self._cursor = _FakeCursor()

    def cursor(self):
        return self._cursor

    def close(self):
        pass


@pytest.fixture
def fake_conn(monkeypatch):
    """Make _check_cmd use a fake connection."""
    conn = _FakeConn()
    monkeypatch.setattr(grg, "_connect", lambda _dbname: conn)
    return conn


def _make_args(superuser="nova", protected_snapshot=None):
    args = MagicMock()
    args.dbname = "nova_memory"
    args.db_user = "nova"
    args.superuser = superuser
    args.protected_snapshot = protected_snapshot
    return args


def test_non_super_with_snapshot_passes_when_unchanged(fake_conn, monkeypatch, tmp_path):
    """Default non-super role: snapshot-compare gate passes if owners are unchanged."""
    snapshot = {"event trigger:schema_change_trigger": "postgres"}
    snap_path = tmp_path / "snap.json"
    snap_path.write_text(json.dumps(snapshot))

    monkeypatch.setattr(grg, "_check_privileges", lambda _cur, _db_user, _superuser: [])
    monkeypatch.setattr(
        grg,
        "_protected_owner_snapshot",
        lambda _cur, _superuser: {
            ("event trigger", "schema_change_trigger"): "postgres",
        },
    )

    args = _make_args(superuser="nova", protected_snapshot=str(snap_path))
    err = io.StringIO()
    with patch.object(sys, "stderr", err):
        rc = grg._check_cmd(args)

    assert rc == 0
    err_text = err.getvalue()
    assert "changed during the run" not in err_text
    assert "OK: DB_USER 'nova' has all required privileges" in err_text


def test_missing_snapshot_refuses_check(fake_conn, monkeypatch):
    """The gate always requires a protected-owner snapshot."""
    monkeypatch.setattr(grg, "_check_privileges", lambda _cur, _db_user, _superuser: [])

    args = _make_args(superuser="nova", protected_snapshot=None)
    err = io.StringIO()
    with patch.object(sys, "stderr", err):
        rc = grg._check_cmd(args)

    assert rc == 1
    err_text = err.getvalue()
    assert "--protected-snapshot is required" in err_text
    assert "changed during the run" not in err_text


def test_snapshot_compare_detects_actual_change(fake_conn, monkeypatch, tmp_path):
    """Snapshot-compare mode only fails when an owner really changed."""
    snapshot = {"event trigger:schema_change_trigger": "postgres"}
    snap_path = tmp_path / "snap.json"
    snap_path.write_text(json.dumps(snapshot))

    monkeypatch.setattr(grg, "_check_privileges", lambda _cur, _db_user, _superuser: [])
    monkeypatch.setattr(
        grg,
        "_protected_owner_snapshot",
        lambda _cur, _superuser: {
            ("event trigger", "schema_change_trigger"): "nova",
        },
    )

    args = _make_args(superuser="nova", protected_snapshot=str(snap_path))
    err = io.StringIO()
    with patch.object(sys, "stderr", err):
        rc = grg._check_cmd(args)

    assert rc == 1
    err_text = err.getvalue()
    assert "changed during the run" in err_text
    assert "postgres -> nova" in err_text
