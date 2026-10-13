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


def _make_mock_connect(exists_for: set[str] | None = None):
    """Build a mock psycopg2.connect that records dbname and supports pg_database queries.

    exists_for: set of agent names whose `<agent>_memory` database is considered
    to exist. The guard query is "SELECT 1 FROM pg_database WHERE datname = %s".
    """
    exists_for = exists_for or set()

    def mock_connect(**kwargs):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value

        def fetchone_side_effect():
            call = cursor.execute.call_args
            if call is not None and call.args:
                sql, params = call.args[0], call.args[1] if len(call.args) > 1 else call.kwargs.get("parameters")
                if params and len(params) == 1 and isinstance(params[0], str):
                    if params[0] in {f"{a}_memory" for a in exists_for}:
                        return (1,)
            return None

        cursor.fetchone.side_effect = fetchone_side_effect
        conn._connect_kwargs = kwargs
        return conn

    return mock_connect


class TestGetDbConnectionResolution(unittest.TestCase):
    """TC-703 coverage for extract_memories.get_db_connection().

    Hermetic environment:
    - HOME and os.path.expanduser are patched to a temp directory so the module
      never reads the real ~/.openclaw/* files.
    - PGDATABASE and SOURCE_SESSION_ID are cleared in setUp and restored in
      tearDown.
    - The module is re-imported fresh for each test because it reads config at
      import time.
    - psycopg2.connect is always mocked; no test reaches a real database.
    """

    def setUp(self):
        self._orig_pgdatabase = os.environ.get("PGDATABASE")
        self._orig_session_id = os.environ.get("SOURCE_SESSION_ID")
        self._orig_override = os.environ.get("OPENCLAW_POSTGRES_CONFIG_OVERRIDE")
        self._orig_home = os.environ.get("HOME")
        self._tmp_dir = tempfile.TemporaryDirectory()

        os.environ["HOME"] = self._tmp_dir.name
        os.environ.pop("PGDATABASE", None)
        os.environ.pop("SOURCE_SESSION_ID", None)
        # Point away from the real config so tests are hermetic even when
        # ~/.openclaw/postgres.json exists.
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = os.path.join(
            self._tmp_dir.name, "nonexistent-postgres.json"
        )

        self._expanduser_patcher = patch(
            "os.path.expanduser",
            side_effect=lambda p: p.replace("~", self._tmp_dir.name),
        )
        self._expanduser_patcher.start()

    def tearDown(self):
        self._expanduser_patcher.stop()
        self._restore("PGDATABASE", self._orig_pgdatabase)
        self._restore("SOURCE_SESSION_ID", self._orig_session_id)
        self._restore("OPENCLAW_POSTGRES_CONFIG_OVERRIDE", self._orig_override)
        self._restore("HOME", self._orig_home)
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
        # Reset per-process peer-DB cache so guard tests are independent.
        extract_memories._PEER_DB_CACHE.clear()
        return extract_memories

    def test_pgdatabase_unset_uses_postgres_config(self):
        """Production reality: PGDATABASE absent, DB comes from postgres.json."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:discord:channel:123"
        mod = self._import_fresh()
        with patch("psycopg2.connect", side_effect=_make_mock_connect()) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "nova_memory")
        mock_connect.assert_called_once()

    def test_missing_config_and_env_fails_loudly(self):
        """No env and no postgres.json -> clear error."""
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            with self.assertRaisesRegex(RuntimeError, "Could not resolve memory database"):
                mod.get_db_connection()
        mock_connect.assert_not_called()

    def test_pgdatabase_overrides_postgres_config(self):
        """Env wins over config file."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["PGDATABASE"] = "newhart_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect", side_effect=_make_mock_connect()) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "newhart_memory")
        mock_connect.assert_called_once()

    def test_subagent_lex_uses_nova_memory(self):
        """No hardcoded roster: lex resolves to nova_memory like any subagent."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:lex:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect", side_effect=_make_mock_connect()) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "nova_memory")
        mock_connect.assert_called_once()

    def test_arbitrary_new_subagent_against_nova_memory(self):
        """A brand-new agent name still works as long as DB is nova_memory."""
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:futurebot:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect", side_effect=_make_mock_connect()) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "nova_memory")
        mock_connect.assert_called_once()

    def test_cross_peer_guard_blocks_peer_on_peer_db(self):
        """A newhart-prefixed session must not write to graybeard's DB.

        Derivation: graybeard is a DB-owning peer because graybeard_memory
        exists on the server; newhart != graybeard, so the guard refuses.
        """
        os.environ["PGDATABASE"] = "graybeard_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with patch(
            "psycopg2.connect",
            side_effect=_make_mock_connect(exists_for={"graybeard", "newhart"}),
        ) as mock_connect:
            with self.assertRaisesRegex(RuntimeError, "Cross-peer guard"):
                mod.get_db_connection()
        mock_connect.assert_called_once()
        self.assertEqual(mock_connect.call_args.kwargs.get("dbname"), "graybeard_memory")

    def test_cross_peer_guard_blocks_graybeard_on_newhart_db(self):
        """A graybeard-prefixed session must not write to newhart's DB.

        Derivation: graybeard is a DB-owning peer because graybeard_memory
        exists on the server; newhart != graybeard, so the guard refuses.
        """
        os.environ["PGDATABASE"] = "newhart_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:graybeard:agent_chat"
        mod = self._import_fresh()
        with patch(
            "psycopg2.connect",
            side_effect=_make_mock_connect(exists_for={"graybeard", "newhart"}),
        ) as mock_connect:
            with self.assertRaisesRegex(RuntimeError, "Cross-peer guard"):
                mod.get_db_connection()
        mock_connect.assert_called_once()
        self.assertEqual(mock_connect.call_args.kwargs.get("dbname"), "newhart_memory")

    def test_cross_peer_guard_allows_subagent_on_peer_db(self):
        """A peer's subagent (bastion) on victoria_memory is allowed.

        Derivation: bastion_memory does not exist as a database, so bastion is
        not itself a DB-owning peer; the guard has no peer boundary to enforce.
        """
        os.environ["PGDATABASE"] = "victoria_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:bastion:agent_chat"
        mod = self._import_fresh()
        with patch(
            "psycopg2.connect",
            side_effect=_make_mock_connect(exists_for={"victoria"}),
        ) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "victoria_memory")
        mock_connect.assert_called_once()

    def test_cross_peer_guard_allows_nova_subagent_lex(self):
        """NOVA subagent 'lex' on nova_memory is allowed.

        Derivation: lex_memory does not exist as a database, so lex is treated
        as a subagent rather than a DB-owning peer.
        """
        config_path = self._config_path("nova_memory")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:lex:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect", side_effect=_make_mock_connect()) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "nova_memory")
        mock_connect.assert_called_once()

    def test_non_memory_db_name_rejected(self):
        """Resolved DB must end with _memory."""
        config_path = self._config_path("not_a_memory_db")
        os.environ["OPENCLAW_POSTGRES_CONFIG_OVERRIDE"] = config_path
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            with self.assertRaisesRegex(RuntimeError, "does not look like a memory database"):
                mod.get_db_connection()
        mock_connect.assert_not_called()

    def test_guard_lookup_failure_is_allowed(self):
        """If pg_database lookup fails, log warning and allow (defense-in-depth)."""
        os.environ["PGDATABASE"] = "newhart_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:graybeard:agent_chat"
        mod = self._import_fresh()

        def failing_connect(**kwargs):
            conn = MagicMock()
            cursor = conn.cursor.return_value.__enter__.return_value
            cursor.execute.side_effect = RuntimeError("catalog lookup failed")
            conn._connect_kwargs = kwargs
            return conn

        with patch("psycopg2.connect", side_effect=failing_connect) as mock_connect:
            conn = mod.get_db_connection()
        self.assertEqual(conn._connect_kwargs.get("dbname"), "newhart_memory")
        mock_connect.assert_called_once()


if __name__ == "__main__":
    unittest.main(verbosity=2)
