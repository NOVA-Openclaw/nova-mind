"""Tests for grant_reconcile_gate.py --all-grantees snapshot/verify (#759)."""

from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

import database.grant_reconcile_gate as grg


def test_all_grantees_snapshot_verify_roundtrip():
    """Capture an all-grantee snapshot and verify it against the current DB."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as fh:
        snap_path = fh.name

    try:
        rc = grg.main(
            ["--dbname", "nova_memory", "--db-user", "nova", "snapshot", "--all-grantees"]
        )
        assert rc == 0
        # stdout contains the JSON snapshot; capture it for verification.
        result = subprocess.run(
            [
                sys.executable,
                str(Path(__file__).parent.parent / "grant_reconcile_gate.py"),
                "--dbname",
                "nova_memory",
                "--db-user",
                "nova",
                "snapshot",
                "--all-grantees",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0
        snapshot = json.loads(result.stdout)
        assert isinstance(snapshot, dict)

        Path(snap_path).write_text(result.stdout)
        err = io.StringIO()
        with patch.object(sys, "stderr", err):
            rc = grg.main(
                [
                    "--dbname",
                    "nova_memory",
                    "--db-user",
                    "nova",
                    "verify",
                    "--all-grantees",
                    snap_path,
                ]
            )
        assert rc == 0
        assert "OK: all grantees retained" in err.getvalue()
    finally:
        Path(snap_path).unlink(missing_ok=True)


def test_all_grantees_gate_fails_on_lost_privilege(tmp_path):
    """A fake snapshot claiming a privilege the grantee does not hold fails verify."""
    snap = {
        "newhart": {
            '"public"."agents"': {
                "SELECT": False,
                "INSERT": True,
                "UPDATE": False,
                "DELETE": False,
            }
        }
    }
    snap_path = tmp_path / "fake-all-snapshot.json"
    snap_path.write_text(json.dumps(snap))

    err = io.StringIO()
    with patch.object(sys, "stderr", err):
        rc = grg.main(
            [
                "--dbname",
                "nova_memory",
                "--db-user",
                "nova",
                "verify",
                "--all-grantees",
                str(snap_path),
            ]
        )
    err_text = err.getvalue()
    assert rc == 1
    assert "ERROR: grantee(s) lost base-DML privileges after reconciliation:" in err_text
    assert "newhart" in err_text
    assert '"public"."agents"' in err_text
    assert "INSERT" in err_text
