"""Tests for database/check_schema_manifest.py (nova-mind#624 CI backstop).

Static, repo-only checks -- no database connection. Covers B8: CI assertion
that append_run_note (and every manifest entry) is present in
database/schema.sql.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import pytest

SCRIPT_PATH = Path(__file__).parent.parent / "check_schema_manifest.py"
spec = importlib.util.spec_from_file_location("check_schema_manifest", SCRIPT_PATH)
check_schema_manifest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_schema_manifest)

REPO_ROOT = Path(__file__).parent.parent.parent


def _repo_schema_has_weight() -> bool:
    """Return True once the live schema dumper has added weight to schema.sql.

    nova-mind#803's weight column is added by migration 089 and will reach
    database/schema.sql via the pg-notify-listener schema dumper after deploy.
    Until then, the real-repo manifest checks are post-deploy only.
    """
    schema_path = REPO_ROOT / "database" / "schema.sql"
    if not schema_path.exists():
        return False
    return "weight numeric NOT NULL DEFAULT 1" in schema_path.read_text()


def _repo_manifest_has_weight() -> bool:
    """Return True once the real manifest lists the #803 objects.

    The manifest entries are added in step 11 after the schema dumper commits
    the updated schema.sql. Pre-deploy the real manifest intentionally omits
    roll_d100() and the weight column so the installer BATS suite passes.
    """
    manifest_path = REPO_ROOT / "database" / ".schema-manifest.toml"
    if not manifest_path.exists():
        return False
    text = manifest_path.read_text()
    return 'roll_d100()' in text and 'weight numeric NOT NULL DEFAULT 1' in text


MANIFEST_ONE_FUNCTION = """\
[functions]
patterns = [
  "append_run_note(integer, text)",
]
"""

MANIFEST_WITH_SECURITY = """\
[functions]
patterns = [
  "append_run_note(integer, text)",
]

[function_security]
"append_run_note" = ["SECURITY DEFINER", "SET search_path = public"]
"""

SCHEMA_WITH_FUNCTION = """\
CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
AS $$ BEGIN NULL; END; $$ LANGUAGE plpgsql;
"""

SCHEMA_WITH_FUNCTION_SECDEF = """\
CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$ BEGIN NULL; END; $$;
"""

SCHEMA_WITHOUT_FUNCTION = """\
CREATE OR REPLACE FUNCTION some_other_function()
RETURNS void
AS $$ BEGIN NULL; END; $$ LANGUAGE plpgsql;
"""

# nova-mind#803 D4 synthetic fixtures: prove the manifest checker has teeth
# for roll_d100() and the motivation_d100.weight column once they belong in
# the manifest (step 11). The real manifest intentionally omits them pre-deploy.
MANIFEST_WITH_ROLL_D100 = """\
[functions]
patterns = [
  "append_run_note(integer, text)",
  "roll_d100()",
]

[columns]
patterns = [
  "weight numeric NOT NULL DEFAULT 1",
]

[function_security]
"append_run_note" = ["SECURITY DEFINER", "SET search_path = public"]
"roll_d100" = ["SECURITY DEFINER", "SET search_path = public"]
"""

SCHEMA_WITH_ROLL_D100_AND_WEIGHT = """\
CREATE TABLE motivation_d100 (
    roll integer NOT NULL,
    task_name character varying(255),
    weight numeric NOT NULL DEFAULT 1,
    CONSTRAINT motivation_d100_pkey PRIMARY KEY (roll)
);

CREATE OR REPLACE FUNCTION roll_d100()
RETURNS TABLE(roll integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY SELECT 1;
END;
$$;

CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ BEGIN NULL; END; $$;
"""

SCHEMA_WITHOUT_ROLL_D100 = """\
CREATE TABLE motivation_d100 (
    roll integer NOT NULL,
    task_name character varying(255),
    weight numeric NOT NULL DEFAULT 1,
    CONSTRAINT motivation_d100_pkey PRIMARY KEY (roll)
);

CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ BEGIN NULL; END; $$;
"""

SCHEMA_WITHOUT_WEIGHT = """\
CREATE TABLE motivation_d100 (
    roll integer NOT NULL,
    task_name character varying(255),
    CONSTRAINT motivation_d100_pkey PRIMARY KEY (roll)
);

CREATE OR REPLACE FUNCTION roll_d100()
RETURNS TABLE(roll integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY SELECT 1;
END;
$$;

CREATE OR REPLACE FUNCTION append_run_note(
    p_run_id integer,
    p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ BEGIN NULL; END; $$;
"""

SCHEMA_ROLL_D100_NO_SECDEF = """\
CREATE OR REPLACE FUNCTION roll_d100()
RETURNS TABLE(roll integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY SELECT 1;
END;
$$;
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


class TestFunctionSecuritySection:
    """B-1 (SE run #804 QA review): static assertion for security properties
    (SECURITY DEFINER, search_path pinning) declared in [function_security].
    """

    def test_load_function_security_parses_section(self, tmp_path):
        p = tmp_path / "manifest.toml"
        p.write_text(MANIFEST_WITH_SECURITY)
        result = check_schema_manifest.load_function_security(str(p))
        assert result == {
            "append_run_note": ["SECURITY DEFINER", "SET search_path = public"]
        }

    def test_load_function_security_absent_section_returns_empty(self, tmp_path):
        p = tmp_path / "manifest.toml"
        p.write_text(MANIFEST_ONE_FUNCTION)  # no [function_security] section
        assert check_schema_manifest.load_function_security(str(p)) == {}

    def test_load_function_security_missing_file_returns_empty(self, tmp_path):
        assert check_schema_manifest.load_function_security(str(tmp_path / "absent.toml")) == {}

    def test_extract_function_body_scopes_to_single_function(self):
        schema = SCHEMA_WITH_FUNCTION_SECDEF + "\n" + SCHEMA_WITHOUT_FUNCTION
        body = check_schema_manifest.extract_function_body(schema, "append_run_note")
        assert body is not None
        assert "append_run_note" in body
        assert "some_other_function" not in body

    def test_extract_function_body_missing_function_returns_none(self):
        body = check_schema_manifest.extract_function_body(SCHEMA_WITHOUT_FUNCTION, "append_run_note")
        assert body is None

    def test_find_missing_security_properties_all_present(self):
        function_security = {"append_run_note": ["SECURITY DEFINER", "SET search_path = public"]}
        missing = check_schema_manifest.find_missing_security_properties(
            function_security, SCHEMA_WITH_FUNCTION_SECDEF
        )
        assert missing == []

    def test_find_missing_security_properties_reports_absent_property(self):
        schema_no_secdef = SCHEMA_WITH_FUNCTION_SECDEF.replace("SECURITY DEFINER\n", "")
        function_security = {"append_run_note": ["SECURITY DEFINER", "SET search_path = public"]}
        missing = check_schema_manifest.find_missing_security_properties(
            function_security, schema_no_secdef
        )
        assert len(missing) == 1
        assert "SECURITY DEFINER" in missing[0]

    def test_find_missing_security_properties_reports_missing_function(self):
        function_security = {"append_run_note": ["SECURITY DEFINER"]}
        missing = check_schema_manifest.find_missing_security_properties(
            function_security, SCHEMA_WITHOUT_FUNCTION
        )
        assert len(missing) == 1
        assert "not found" in missing[0]

    def test_main_exit_1_when_security_property_missing(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_WITH_SECURITY)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITH_FUNCTION_SECDEF.replace("SECURITY DEFINER\n", ""))

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 1
        out = capsys.readouterr().out
        assert "FAIL" in out
        assert "SECURITY DEFINER" in out

    def test_main_exit_0_when_security_properties_all_present(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_WITH_SECURITY)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITH_FUNCTION_SECDEF)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 0
        assert "OK" in capsys.readouterr().out

    @pytest.mark.skipif(
        not (_repo_schema_has_weight() and _repo_manifest_has_weight()),
        reason="post-deploy only: real manifest/schema lack #803 entries until step 11",
    )
    def test_real_repo_schema_passes_security_check(self):
        """Integration smoke test: append_run_note() and the #803 roll_d100()
        entries still declare SECURITY DEFINER and SET search_path = public."""
        exit_code = check_schema_manifest.main(
            [
                "--manifest", str(REPO_ROOT / "database" / ".schema-manifest.toml"),
                "--schema", str(REPO_ROOT / "database" / "schema.sql"),
            ]
        )
        assert exit_code == 0


class TestIssue803PostDeploy:
    """Area I D1-D3 (nova-mind#803): post-deploy verification against the
    real committed database/schema.sql and .schema-manifest.toml. These tests
    only run once the live apply + automated pgschema dump has landed the
    weight column, the rewritten roll_d100(), and the hand-maintained column
    grant in schema.sql (step 11). Pre-deploy they are skipped automatically.
    """

    @pytest.mark.skipif(
        not (_repo_schema_has_weight() and _repo_manifest_has_weight()),
        reason="post-deploy only: real manifest/schema lack #803 entries until step 11",
    )
    def test_schema_sql_contains_weight_column_and_weighted_roll_d100(self):
        """D1: schema.sql contains the weight column and the new roll_d100() body."""
        schema_path = REPO_ROOT / "database" / "schema.sql"
        schema_sql = schema_path.read_text()

        # Column + constraint.
        assert "weight numeric NOT NULL DEFAULT 1" in schema_sql
        assert "motivation_d100_weight_check" in schema_sql
        assert "CHECK (weight >= 0)" in schema_sql

        # Function body is the weighted-draw rewrite, not the old 1-100 re-roll.
        body = check_schema_manifest.extract_function_body(schema_sql, "roll_d100")
        assert body is not None, "roll_d100() not found in schema.sql"
        assert "WITH pop AS MATERIALIZED" in body, "expected weighted-draw CTEs"
        assert "weight > 0" in body, "expected weight eligibility filter"
        assert "floor(random() * 100 + 1)" not in body, "old uniform 1-100 draw still present"

    @pytest.mark.skipif(
        not (_repo_schema_has_weight() and _repo_manifest_has_weight()),
        reason="post-deploy only: real manifest/schema lack #803 entries until step 11",
    )
    def test_check_schema_manifest_passes_post_deploy(self):
        """D2: check_schema_manifest.py exits 0 on the real post-deploy files."""
        exit_code = check_schema_manifest.main(
            [
                "--manifest", str(REPO_ROOT / "database" / ".schema-manifest.toml"),
                "--schema", str(REPO_ROOT / "database" / "schema.sql"),
            ]
        )
        assert exit_code == 0

    @pytest.mark.skipif(
        not (_repo_schema_has_weight() and _repo_manifest_has_weight()),
        reason="post-deploy only: real manifest/schema lack #803 entries until step 11",
    )
    def test_schema_sql_contains_weight_grant_to_nova(self):
        """D3: the hand-maintained GRANT UPDATE (weight) line is present.

        pgschema dump does not emit column-level GRANT statements, so this line
        only survives if a human added it to schema.sql in the same PR as the
        migration.
        """
        schema_sql = (REPO_ROOT / "database" / "schema.sql").read_text()
        grant_re = re.compile(
            r"GRANT\s+UPDATE\s*\([^)]*\bweight\b[^)]*\)\s+ON\s+TABLE\s+motivation_d100\s+TO\s+nova\s*;",
            re.IGNORECASE,
        )
        assert grant_re.search(schema_sql), (
            "missing GRANT UPDATE (...) ON TABLE motivation_d100 TO nova for weight"
        )


class TestIssue803SyntheticManifest:
    """D4 (nova-mind#803): synthetic fixtures proving the manifest checker
    catches a #624-style silent clobber of roll_d100() or the weight column.
    The real manifest omits these entries pre-deploy, so these fixtures stand
    in for the real entries and demonstrate the checker has teeth once step 11
    adds them.
    """

    def test_main_exit_0_when_roll_d100_and_weight_present(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_WITH_ROLL_D100)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITH_ROLL_D100_AND_WEIGHT)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 0
        out = capsys.readouterr().out
        assert "OK" in out
        assert "roll_d100" in out

    def test_main_exit_1_when_roll_d100_missing(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_WITH_ROLL_D100)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITHOUT_ROLL_D100)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 1
        out = capsys.readouterr().out
        assert "FAIL" in out
        assert "roll_d100" in out

    def test_main_exit_1_when_weight_column_missing(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_WITH_ROLL_D100)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_WITHOUT_WEIGHT)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 1
        out = capsys.readouterr().out
        assert "FAIL" in out
        assert "weight numeric NOT NULL DEFAULT 1" in out

    def test_main_exit_1_when_roll_d100_security_property_missing(self, tmp_path, capsys):
        manifest_path = tmp_path / "manifest.toml"
        manifest_path.write_text(MANIFEST_WITH_ROLL_D100)
        schema_path = tmp_path / "schema.sql"
        schema_path.write_text(SCHEMA_ROLL_D100_NO_SECDEF)

        exit_code = check_schema_manifest.main(
            ["--manifest", str(manifest_path), "--schema", str(schema_path)]
        )
        assert exit_code == 1
        out = capsys.readouterr().out
        assert "FAIL" in out
        assert "SECURITY DEFINER" in out


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

    @pytest.mark.skipif(
        not (_repo_schema_has_weight() and _repo_manifest_has_weight()),
        reason="post-deploy only: real manifest/schema lack #803 entries until step 11",
    )
    def test_real_repo_schema_passes(self):
        """Integration smoke test against the actual repo files (not tmp_path
        fixtures) -- confirms every manifest entry, including the #803
        roll_d100() and weight column, is present in database/schema.sql."""
        exit_code = check_schema_manifest.main(
            [
                "--manifest", str(REPO_ROOT / "database" / ".schema-manifest.toml"),
                "--schema", str(REPO_ROOT / "database" / "schema.sql"),
            ]
        )
        assert exit_code == 0


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
