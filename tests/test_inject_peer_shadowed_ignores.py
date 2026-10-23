"""Unit tests for database/inject_peer_shadowed_ignores.py.

Covers TC-792-051: malformed input handling at the TOML-injection seam.
"""

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent
INJECTOR = REPO_ROOT / "database" / "inject_peer_shadowed_ignores.py"


def _run_injector(args, input_text=None):
    """Run the injector CLI and return (rc, stdout, stderr)."""
    result = subprocess.run(
        [sys.executable, str(INJECTOR)] + args,
        input=input_text,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout, result.stderr


def _make_ignore_file(tmp_path, text):
    p = tmp_path / ".pgschemaignore"
    p.write_text(text, encoding="utf-8")
    return p


def test_malformed_section_unclosed_array_exits_2(tmp_path):
    """TC-792-051a: [tables] opened but never closed -> exit 2.

    The malformed section is only detected when the injector actually tries
    to write into it; relkind 'f' maps to [tables].
    """
    ignore_file = _make_ignore_file(
        tmp_path,
        "[tables]\npatterns = [\n  \"some_table\"\n",
    )
    rc, out, err = _run_injector(
        ["--ignore-file", str(ignore_file), "--names", "shadow_fdw", "--relkinds", "f"]
    )
    assert rc == 2
    assert "malformed [tables] section" in err.lower()


def test_mismatched_names_relkinds_lengths_exits_2(tmp_path):
    """TC-792-051b: --names and --relkinds of different lengths -> exit 2."""
    ignore_file = _make_ignore_file(tmp_path, "[tables]\npatterns = []\n")
    rc, out, err = _run_injector(
        [
            "--ignore-file",
            str(ignore_file),
            "--names",
            "a,b",
            "--relkinds",
            "v",
        ]
    )
    assert rc == 2
    assert "same length" in err.lower()


def test_unknown_relkind_exits_2(tmp_path):
    """TC-792-051c: unknown relkind value -> exit 2."""
    ignore_file = _make_ignore_file(tmp_path, "[tables]\npatterns = []\n")
    rc, out, err = _run_injector(
        [
            "--ignore-file",
            str(ignore_file),
            "--names",
            "weird_thing",
            "--relkinds",
            "x",
        ]
    )
    assert rc == 2
    assert "unknown relkind" in err.lower()


def test_happy_path_injects_view_and_foreign_table(tmp_path):
    """Sanity check that valid injection still works."""
    ignore_file = _make_ignore_file(
        tmp_path,
        "[tables]\npatterns = [\n  \"*_local\"\n]\n[views]\npatterns = [\n]\n",
    )
    rc, out, err = _run_injector(
        [
            "--ignore-file",
            str(ignore_file),
            "--names",
            "agent_bootstrap_context,ai_models",
            "--relkinds",
            "v,f",
        ]
    )
    assert rc == 0
    text = ignore_file.read_text(encoding="utf-8")
    assert '"agent_bootstrap_context"' in text
    assert '"ai_models"' in text


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
