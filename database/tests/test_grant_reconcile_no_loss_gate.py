"""Tests for grant_reconcile_gate.py per-grantee no-loss snapshot/verify (#759)."""

import io
import json
import sys
from unittest.mock import MagicMock, patch

import pytest

import database.grant_reconcile_gate as grg


class _FakeCursor:
    """Cursor that replays grantee lists and privilege results on demand."""

    def __init__(self):
        self.queries = []
        self._grantee_lists = {}
        self._priv_results = {}

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, query, params=None):
        self.queries.append((query, params))

    def fetchone(self):
        # The most recent query should be a has_*_privilege call.
        _, params = self.queries[-1]
        grantee, rel, priv = params
        return (self._priv_results.get((grantee, rel, priv), False),)

    def fetchall(self):
        # The most recent query should be a grantee list query.
        _, params = self.queries[-1]
        # params are (schema, name, schema, name) for sequences or (schema, name) for tables.
        key = (params[0], params[1])
        return [(r,) for r in self._grantee_lists.get(key, [])]

    def set_grantees(self, schema, name, grantees):
        self._grantee_lists[(schema, name)] = grantees

    def set_privilege(self, grantee, rel, priv, value):
        self._priv_results[(grantee, rel, priv)] = value


class _FakeConn:
    def __init__(self):
        self.cur = _FakeCursor()

    def cursor(self):
        return self.cur

    def close(self):
        pass


@pytest.fixture
def fake_conn(monkeypatch):
    conn = _FakeConn()
    monkeypatch.setattr(grg, "_connect", lambda _dbname: conn)
    return conn


def _make_snapshot_args():
    args = MagicMock()
    args.dbname = "nova_memory"
    args.db_user = "nova"
    return args


def _make_verify_args(snapshot_path):
    args = MagicMock()
    args.dbname = "nova_memory"
    args.db_user = "nova"
    args.snapshot = str(snapshot_path)
    return args


def test_snapshot_records_per_grantee_privileges(fake_conn, monkeypatch):
    """The snapshot command captures privileges for every grantee on owned objects."""
    monkeypatch.setattr(
        grg,
        "_owned_relations",
        lambda _cur, _db_user: [("public", "t", "r"), ("public", "s", "S")],
    )

    fake_conn.cur.set_grantees("public", "t", ["nova", "newhart"])
    fake_conn.cur.set_grantees("public", "s", ["nova"])

    # nova on t
    fake_conn.cur.set_privilege("nova", '"public"."t"', "SELECT", True)
    fake_conn.cur.set_privilege("nova", '"public"."t"', "INSERT", True)
    fake_conn.cur.set_privilege("nova", '"public"."t"', "UPDATE", True)
    fake_conn.cur.set_privilege("nova", '"public"."t"', "DELETE", False)
    fake_conn.cur.set_privilege("nova", '"public"."t"', "TRUNCATE", False)
    fake_conn.cur.set_privilege("nova", '"public"."t"', "REFERENCES", False)
    fake_conn.cur.set_privilege("nova", '"public"."t"', "TRIGGER", False)
    # newhart on t
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "SELECT", True)
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "INSERT", False)
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "UPDATE", False)
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "DELETE", False)
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "TRUNCATE", False)
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "REFERENCES", False)
    fake_conn.cur.set_privilege("newhart", '"public"."t"', "TRIGGER", False)
    # nova on s
    fake_conn.cur.set_privilege("nova", '"public"."s"', "USAGE", True)
    fake_conn.cur.set_privilege("nova", '"public"."s"', "SELECT", False)
    fake_conn.cur.set_privilege("nova", '"public"."s"', "UPDATE", True)

    args = _make_snapshot_args()
    out = io.StringIO()
    with patch.object(sys, "stdout", out):
        rc = grg._snapshot_cmd(args)

    assert rc == 0
    snapshot = json.loads(out.getvalue())
    assert snapshot["nova"]['"public"."t"']["SELECT"] is True
    assert snapshot["newhart"]['"public"."t"']["SELECT"] is True
    assert snapshot["newhart"]['"public"."t"']["INSERT"] is False
    assert snapshot["nova"]['"public"."s"']["USAGE"] is True


def test_verify_detects_privilege_loss(fake_conn, monkeypatch, tmp_path):
    """The gate fails when a grantee loses a privilege it held before."""
    before = {
        "newhart": {
            '"public"."t"': {
                "SELECT": True,
                "INSERT": False,
                "UPDATE": False,
                "DELETE": False,
                "TRUNCATE": False,
                "REFERENCES": False,
                "TRIGGER": False,
            }
        }
    }
    snap_path = tmp_path / "snap.json"
    snap_path.write_text(json.dumps(before))

    monkeypatch.setattr(
        grg,
        "_snapshot",
        lambda _cur, _db_user: {
            "newhart": {'"public"."t"': {"SELECT": False}}
        },
    )

    args = _make_verify_args(snap_path)
    err = io.StringIO()
    with patch.object(sys, "stderr", err):
        rc = grg._verify_cmd(args)

    assert rc == 1
    err_text = err.getvalue()
    assert "grantees lost privileges" in err_text
    assert 'role "newhart" lost SELECT on "public"."t"' in err_text


def test_verify_passes_when_no_privilege_lost(fake_conn, monkeypatch, tmp_path):
    """The gate passes when all previously-held privileges are retained."""
    before = {
        "newhart": {
            '"public"."t"': {
                "SELECT": True,
                "INSERT": False,
            }
        }
    }
    snap_path = tmp_path / "snap.json"
    snap_path.write_text(json.dumps(before))

    monkeypatch.setattr(
        grg,
        "_snapshot",
        lambda _cur, _db_user: {
            "newhart": {'"public"."t"': {"SELECT": True, "INSERT": False}}
        },
    )

    args = _make_verify_args(snap_path)
    err = io.StringIO()
    with patch.object(sys, "stderr", err):
        rc = grg._verify_cmd(args)

    assert rc == 0
    assert "all grantees retained privileges" in err.getvalue()
