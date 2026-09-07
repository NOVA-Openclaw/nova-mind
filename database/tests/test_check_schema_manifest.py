"""Tests for database/check_schema_manifest.py (nova-mind#624 CI backstop).

Static, repo-only checks -- no database connection. Covers B8: CI assertion
that append_run_note (and every manifest entry) is present in
database/schema.sql.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "check_schema_manifest.py"
spec = importlib.util.spec_from_file_location("check_schema_manifest", SCRIPT_PATH)
check_schema_manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_schema_manifest)


MANIFEST_ONE_FUNCTION = """\
[functions]
patterns = [
  "append_run_note(integer, text)",
]
"""

SCHEMA_WITH_FUNCTION = """\
CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
AS $$ BEGIN NULL; END; $$ LANGUAGE plpgsql;
"""

SCHEMA_WITHOUT_FUNCTION = """\
CREATE OR REPLACE FUNCTION some_other_function()
RETURNS void
AS $$ BEGIN NULL; END; $$ LANGUAGE plpgsql;
"""


class TestLoadManifest:
    def test_missing_manifest_returns_empty_dict(self, tmp_path):
        assert check_schema_manifest.load_manifest(str(tmp_path / "absent.toml")) == {}

    def test_valid_manifest_parses(self, tmp_path):
        p = tmp_path / "manifest.toml"
        p.write_text(MANIFEST_ONE_FUNCTION)
        manifest = check_schema_manifest.load_manifest(str(p))
        assert manifest == {"functions": ["append_run_note(integer, text)"]}

    def test_malformed_manifest_raises_valueerror(self, tmp_path):
        """Unlike the listener's fail-open loader, the CI backstop fails LOUD
        on malformed TOML -- a manifest that silently fails to parse would
        silently stop protecting every entry, defeating the backstop."""
        p = tmp_path / "manifest.toml"
        p.write_text("[functions\nnot valid toml {{{")
        with pytest.raises(ValueError):
            check_schema_manifest.load_manifest(str(p))


class TestFunctionSignaturePresent:
    def test_present(self):
        assert check_schema_manifest.function_signature_present(
            SCHEMA_WITH_FUNCTION, "append_run_note(integer, text)"
        )

    def test_absent(self):
        assert not check_schema_manifest.function_signature_present(
            SCHEMA_WITHOUT_FUNCTION, "append_run_note(integer, text)"
        )


class TestFindMissing:
    def test_no_manifest_entries_means_nothing_missing(self):
        assert check_schema_manifest.find_missing({}, SCHEMA_WITHOUT_FUNCTION) == []

    def test_present_object_not_reported(self):
        manifest = {"functions": ["append_run_note(integer, text)"]}
        assert check_schema_manifest.find_missing(manifest, SCHEMA_WITH_FUNCTION) == []

    def test_absent_object_reported(self):
        manifest = {"functions": ["append_run_note(integer, text)"]}
        missing = check_schema_manifest.find_missing(manifest, SCHEMA_WITHOUT_FUNCTION)
        assert missing == ["functions: append_run_note(integer, text)"]


class TestMainExitCodes:
    def test_exit_0_when_object_present(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_ONE_FUNCTION)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITH_FUNCTION)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 0
        assert "OK" in capsys.readouterr().out

    def test_exit_1_when_object_missing(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_ONE_FUNCTION)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITHOUT_FUNCTION)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 1
        out = capsys.readouterr().out
        assert "FAIL" in out
        assert "append_run_note(integer, text)" in out

    def test_exit_0_when_no_manifest_file(self, tmp_path, capsys):
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITHOUT_FUNCTION)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(tmp_path / "absent.toml"), "--schema", str(schema_path)]
        )
        assert exit_code == 0

    def test_exit_2_when_schema_file_missing(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_ONE_FUNCTION)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(tmp_path / "absent-schema.sql")]
        )
        assert exit_code == 2
        assert "ERROR" in capsys.readouterr().err

    def test_exit_2_when_manifest_malformed(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text("[functions\nnot valid {{{")
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITH_FUNCTION)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 2

    def test_real_repo_schema_passes(self):
        """Integration smoke test against the actual repo files (not tmp_path
        fixtures) -- confirms the restored append_run_note() in this PR
        satisfies the backstop against the real database/schema.sql."""
        repo_root = Path(__file__).parent.parent.parent
        exit_code = check_schema_manifest.main(
            [
                "--manifest", str(repo_root / "database" / ".schema-manifest.toml"),
                "--schema", str(repo_root / "database" / "schema.sql"),
            ]
        )
        assert exit_code == 0


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
