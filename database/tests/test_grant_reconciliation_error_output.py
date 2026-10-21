"""Unit test for agent-install.sh grant-reconciliation ERROR-first output.

The installer block under test prints ERROR lines before WARNING summaries and
persists the full stderr file.  This test exercises the same bash logic in
isolation so it does not require a live database or a full installer run.
"""

import os
import subprocess
import tempfile
import textwrap

import pytest


BASH_SNIPPET = textwrap.dedent(
    r'''
    set -u
    CROSS_MARK="X"
    GRANT_PSQL_ERR="$1"

    echo -e "  ${CROSS_MARK} Grant reconciliation failed"
    if [ -s "$GRANT_PSQL_ERR" ]; then
        _error_lines=$(grep -n '^ERROR:' "$GRANT_PSQL_ERR" || true)
        _warning_count=$(grep -c '^WARNING:' "$GRANT_PSQL_ERR" 2>/dev/null || echo 0)
        if [ -n "$_error_lines" ]; then
            echo "  psql errors:"
            echo "$_error_lines" | head -20 | sed 's/^/    /'
        fi
        if [ "$_warning_count" -gt 0 ]; then
            echo "  ($_warning_count WARNING line(s) omitted; see full log below)"
        fi
        echo "  Full stderr preserved at: $GRANT_PSQL_ERR"
    fi
    '''
).strip()


def test_error_lines_printed_first_and_warnings_counted():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".stderr", delete=False) as fh:
        fh.write("WARNING:  noisy warning 1\n")
        fh.write("ERROR:  permission denied for relation t\n")
        fh.write("CONTEXT:  SQL statement \"GRANT SELECT ...\"\n")
        fh.write("WARNING:  noisy warning 2\n")
        fh.write("WARNING:  noisy warning 3\n")
        err_path = fh.name

    try:
        result = subprocess.run(
            ["bash", "-c", BASH_SNIPPET, "snippet", err_path],
            capture_output=True,
            text=True,
            check=False,
        )
        out = result.stdout
        assert result.returncode == 0, result.stderr
        assert "Grant reconciliation failed" in out
        assert "psql errors:" in out
        assert "ERROR:  permission denied for relation t" in out
        assert "3 WARNING line(s) omitted" in out
        assert f"Full stderr preserved at: {err_path}" in out
        # WARNING bodies are summarized, not re-printed.
        assert "WARNING:  noisy warning" not in out

        # ERROR line appears before the warning summary.
        error_pos = out.index("ERROR:  permission denied")
        warning_summary_pos = out.index("WARNING line(s) omitted")
        assert error_pos < warning_summary_pos
    finally:
        os.unlink(err_path)


def test_warning_count_zero_when_only_errors():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".stderr", delete=False) as fh:
        fh.write("ERROR:  something failed\n")
        err_path = fh.name

    try:
        result = subprocess.run(
            ["bash", "-c", BASH_SNIPPET, "snippet", err_path],
            capture_output=True,
            text=True,
            check=False,
        )
        out = result.stdout
        assert "something failed" in out
        assert "WARNING line(s) omitted" not in out
        assert f"Full stderr preserved at: {err_path}" in out
    finally:
        os.unlink(err_path)


def test_no_output_when_stderr_empty():
    with tempfile.NamedTemporaryFile(mode="w", suffix=".stderr", delete=False) as fh:
        err_path = fh.name

    try:
        result = subprocess.run(
            ["bash", "-c", BASH_SNIPPET, "snippet", err_path],
            capture_output=True,
            text=True,
            check=False,
        )
        assert "Full stderr preserved at" not in result.stdout
    finally:
        os.unlink(err_path)
