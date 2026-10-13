"""Tests for extract_memories.py #703 DB resolution (no hardcoded fallback)."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add scripts to path
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

# Prevent ~/.openclaw/lib/pg_env.py from overriding PGDATABASE during import.
sys.modules["pg_env"] = MagicMock()
sys.modules["pg_env"].load_pg_env = MagicMock()


class TestGetDbConnectionResolution(unittest.TestCase):
    """TC-703 coverage for extract_memories.get_db_connection()."""

    def setUp(self):
        self._orig_pgdatabase = os.environ.get("PGDATABASE")
        self._orig_override = os.environ.get("OPENCLAW_POSTGRES_CONFIG_OVERRIDE")
        self._tmp_dir = tempfile.TemporaryDirectory()
        # Ensure a clean starting state. Point away from the real config so tests
        # are hermetic even when ~/.openclaw/postgres.json exists.
        os.environ.pop("PGDATABASE", None)
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = os.path.join(
            self._tmp_dir.name, "nonexistent-postgres.json"
        )

    def tearDown(self):
        self._restore("PGDATABASE", self._orig_pgdatabase)
        self._restore("OPENCLAW_POSTGRES_CONFIG_OVERRIDE", self._orig_override)
        self._tmp_dir.cleanup()

    def _restore(self, key, value):
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value

    def _config_path(self, database):
        path = os.path.join(self._tmp_dir.name, "postgres.json")
        with open(path, "w") as f:
            json.dump({"database": database}, f)
        return path

    def _import_fresh(self):
        """Re-import the module so it picks up the current os.environ."""
        if "extract_memories" in sys.modules:
            del sys.modules["extract_memories"]
        import extract_memories
        return extract_memories

    def test_pgdatabase_unset_uses_postgres_config(self):
        """Production reality: PGDATABASE absent, DB comes from postgres.json."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:discord:channel:123"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            mock_connect.return_value = "mock_conn"
            conn = mod.get_db_connection()
        self.assertEqual(conn, "mock_conn")
        mock_connect.assert_called_once()

    def test_missing_config_and_env_fails_loudly(self):
        """No env and no postgres.json -> clear error."""
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:agent_chat"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "Could not resolve memory database"):
            mod.get_db_connection()

    def test_pgdatabase_overrides_postgres_config(self):
        """Env wins over config file."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["PGDATABASE"] = "newhart_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            mock_connect.return_value = "mock_conn"
            conn = mod.get_db_connection()
        self.assertEqual(conn, "mock_conn")

    def test_subagent_lex_uses_nova_memory(self):
        """No hardcoded roster: lex resolves to nova_memory like any subagent."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:lex:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            mock_connect.return_value = "mock_conn"
            conn = mod.get_db_connection()
        self.assertEqual(conn, "mock_conn")

    def test_arbitrary_new_subagent_against_nova_memory(self):
        """A brand-new agent name still works as long as DB is nova_memory."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:futurebot:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            mock_connect.return_value = "mock_conn"
            conn = mod.get_db_connection()
        self.assertEqual(conn, "mock_conn")

    def test_cross_peer_guard(self):
        """A newhart-prefixed session must not write to graybeard's DB."""
        os.environ["PGDATABASE"] = "graybeard_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "Cross-peer guard"):
            mod.get_db_connection()

    def test_non_memory_db_name_rejected(self):
        """Resolved DB must end with _memory."""
        config_path = self._config_path("not_a_memory_db")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:agent_chat"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "does not look like a memory database"):
            mod.get_db_connection()


if __name__ == "__main__":
    unittest.main(verbosity=2)
