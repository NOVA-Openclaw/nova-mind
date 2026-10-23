"""Grep guard: no runtime file hardcodes an embedding model.

Embedding consumers must read model/base_url/dimensions from
~/.openclaw/scripts/embedding-config.json. This test fails if any runtime
source file contains a hardcoded embedding-model name outside the allowed
locations (the config itself, docs, tests, schema/migrations, and this guard).

Issue: nova-mind #781
"""

import json
import os
import re
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]

# Known embedding model names that must not appear in runtime code.
EMBEDDING_MODEL_PATTERNS = [
    re.compile(r"snowflake-arctic-embed2"),
]

# File extensions to scan for runtime code.
RUNTIME_EXTENSIONS = {".ts", ".js", ".py", ".sh"}


def is_allowed(path: Path) -> bool:
    """Return True if a file is allowed to mention embedding model names."""
    rel = path.relative_to(REPO_ROOT)
    rel_str = str(rel).replace(os.sep, "/")

    # The canonical config file itself.
    if rel_str == "memory/scripts/embedding-config.json":
        return True

    # Documentation.
    if rel_str.endswith(".md"):
        return True

    # Tests and test fixtures.
    if (
        "/tests/" in f"/{rel_str}"
        or rel_str.endswith(".test.ts")
        or rel_str.endswith(".test.py")
        or rel_str.startswith("memory/lib/test_")
        or "/test_" in f"/{rel_str}"
    ):
        return True

    # Schema and migrations.
    if rel_str.startswith("memory/schema/") or "/migrations/" in rel_str or rel_str.endswith(".sql"):
        return True

    # This guard file.
    if rel_str == "tests/test_embedding_model_grep_guard.py":
        return True

    return False


def list_repo_files():
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [REPO_ROOT / line for line in result.stdout.splitlines() if line]


def test_no_hardcoded_embedding_models_in_runtime_files():
    violations = []
    for path in list_repo_files():
        if path.suffix not in RUNTIME_EXTENSIONS:
            continue
        if is_allowed(path):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for pattern in EMBEDDING_MODEL_PATTERNS:
            if pattern.search(text):
                rel = path.relative_to(REPO_ROOT)
                violations.append(f"{rel}: contains '{pattern.pattern}'")
                break

    assert not violations, "Hardcoded embedding model(s) found in runtime files:\n" + "\n".join(
        violations
    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
